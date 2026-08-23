import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import 'transaction_draft.dart';
import 'transaction_query.dart';

/// The single write path for transactions.
///
/// Every insert in this app goes through [add], including Phase 2's captured
/// messages and Phase 6's home-screen widget. No second insert path is ever
/// created -- that is what keeps the local date key, the Uncategorized
/// default, the active currency, and tag usage counts from having to be
/// re-implemented correctly in three places, and getting it wrong in two.
final class TransactionRepository {
  /// Positional to keep the DAOs private, which named parameters cannot do.
  /// The three types are distinct, so a mis-ordered call is a compile error
  /// rather than a runtime surprise.
  const TransactionRepository(this._dao, this._tagsDao, this._currency);

  final TransactionsDao _dao;
  final TagsDao _tagsDao;

  /// The currency in force when the row is written, stamped per transaction.
  ///
  /// Stored per row rather than read from settings at display time, so
  /// changing the app's currency later does not silently relabel history that
  /// was recorded in a different one.
  final Currency _currency;

  Future<Transaction> add(TransactionDraft draft) async {
    final id = Ids.newId();
    final local = draft.occurredAtUtc.toLocal();
    await _dao.insertTransaction(
      id: id,
      direction: draft.direction,
      amount: draft.amount,
      currencyCode: _currency.code,
      occurredAtUtc: draft.occurredAtUtc.millisecondsSinceEpoch,
      // Derived from local time, not UTC. A purchase at 01:00 local on the
      // 22nd belongs to the 22nd even though it is still the 21st in UTC;
      // getting this wrong files spending under the wrong day for everyone
      // east of Greenwich, which is the entire target market.
      localDateKey: DateKey.fromDateTime(local),
      tzOffsetMinutes: local.timeZoneOffset.inMinutes,
      categoryId: draft.categoryId,
      source: draft.source,
      isConfirmed: draft.isConfirmed,
      paymentMethodId: draft.paymentMethodId,
      merchant: draft.merchant,
      note: draft.note,
      necessity: draft.necessity,
      satisfaction: draft.satisfaction,
      captureId: draft.captureId,
    );
    await _attachTags(id, draft.tagIds, countUsage: true);

    final row = await _dao.byId(id);
    if (row == null) {
      // Not defensive noise: a row that vanishes between insert and read means
      // the write did not commit, and returning a fabricated object would let
      // the UI show an expense that does not exist.
      throw StateError('Transaction $id was not persisted');
    }
    return row;
  }

  /// Writes an edited transaction.
  ///
  /// [tagIds] null leaves the tag set alone; a list replaces it wholesale.
  /// Replacing rather than merging is what makes removing a tag possible at
  /// all -- there is no other gesture that would express it.
  Future<void> update(Transaction tx, {List<String>? tagIds}) async {
    final local =
        DateTime.fromMillisecondsSinceEpoch(tx.occurredAtUtc, isUtc: true)
            .toLocal();
    await _dao.updateTransaction(
      tx.id,
      amount: tx.amount,
      direction: tx.direction,
      categoryId: tx.categoryId,
      occurredAtUtc: tx.occurredAtUtc,
      localDateKey: DateKey.fromDateTime(local),
      tzOffsetMinutes: local.timeZoneOffset.inMinutes,
      paymentMethodId: tx.paymentMethodId,
      merchant: tx.merchant,
      note: tx.note,
      necessity: tx.necessity,
      satisfaction: tx.satisfaction,
      isConfirmed: tx.isConfirmed,
    );
    if (tagIds != null) {
      // Usage is not re-counted on edit. The counter ranks how often a tag is
      // reached for, and re-editing one transaction ten times is not ten uses.
      await _attachTags(tx.id, tagIds, countUsage: false);
    }
  }

  Future<void> softDelete(String id) => _dao.softDelete(id);

  Future<void> restore(String id) => _dao.restore(id);

  /// One page, newest first.
  ///
  /// Asks the database for one row more than requested. That extra row is
  /// never returned -- it is only how the repository knows whether a next page
  /// exists, instead of the caller inferring it from `items.length == limit`,
  /// which is wrong precisely when the total is a multiple of the page size.
  Future<TransactionPage> page(PaginatedTransactionQuery query) async {
    final rows = await _dao.pageAfter(
      range: query.range,
      after: query.cursor?.row,
      limit: query.limit + 1,
      direction: query.direction,
      categoryId: query.categoryId,
      searchText: query.searchText,
      confirmedOnly: query.confirmedOnly,
    );

    final hasMore = rows.length > query.limit;
    final items = hasMore ? rows.take(query.limit).toList() : rows;
    return TransactionPage(
      items: items,
      cursor: hasMore ? TransactionCursor.of(items.last) : null,
    );
  }

  /// A period total, summed in SQLite rather than in Dart.
  Future<Money> total(DateRange range, {TxDirection? direction}) =>
      _dao.sumInRange(range, direction: direction);

  Future<List<String>> tagsOf(String transactionId) =>
      _dao.tagsOf(transactionId);

  Future<void> _attachTags(
    String transactionId,
    List<String> tagIds, {
    required bool countUsage,
  }) async {
    if (tagIds.isEmpty) {
      // Still written on update, so clearing every tag actually clears them.
      await _dao.setTags(transactionId, const []);
      return;
    }
    await _dao.setTags(transactionId, tagIds);
    if (!countUsage) return;
    for (final tagId in tagIds.toSet()) {
      await _tagsDao.incrementUsage(tagId);
    }
  }
}
