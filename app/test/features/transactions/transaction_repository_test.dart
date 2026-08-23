import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/transactions/data/transaction_draft.dart';
import 'package:nimbustats/features/transactions/data/transaction_query.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  const wholeEra = DateRange(DateKey(20000101), DateKey(20991231));

  setUp(() async {
    db = AppDatabase.openInMemory();
    repo = TransactionRepository(
      db.transactionsDao,
      db.tagsDao,
      Currency.toman,
    );
    await db.categoriesDao.insertNode(id: 'cat', name: 'Cat', parentId: null);
    await db.categoriesDao.insertNode(
      id: SystemCategoryIds.uncategorized,
      name: 'Uncategorized',
      parentId: null,
    );
    await db.tagsDao.insertNode(id: 'travel', name: 'travel', parentId: null);
    await db.tagsDao.insertNode(id: 'food', name: 'food', parentId: null);
  });

  tearDown(() => db.close());

  TransactionDraft draft({
    Money amount = const Money(1),
    DateTime? at,
    List<String> tagIds = const [],
  }) =>
      TransactionDraft(
        amount: amount,
        direction: TxDirection.expense,
        categoryId: 'cat',
        occurredAtUtc: at ?? DateTime.utc(2026, 8, 21),
        tagIds: tagIds,
      );

  test('add fills in id, timestamps, currency, and the local date key',
      () async {
    final at = DateTime.utc(2026, 8, 21, 18, 30);
    final tx = await repo.add(draft(amount: const Money(125000), at: at));

    expect(tx.id, isNotEmpty);
    expect(tx.amount, const Money(125000));
    expect(tx.currencyCode, 'IRT', reason: 'taken from the active currency');
    expect(tx.localDateKey, DateKey.fromDateTime(at.toLocal()));
    expect(tx.source, TxSource.manual);
    expect(tx.isConfirmed, isTrue);
    expect(tx.createdAt, greaterThan(0));
  });

  test('the local date key follows local time, not UTC', () async {
    // A purchase at 01:00 local on the 22nd is the 22nd, even though it may
    // still be the 21st in UTC. Getting this wrong puts spending in the wrong
    // day bucket for everyone east of Greenwich -- the entire target market.
    final local = DateTime(2026, 8, 22, 1);
    final tx = await repo.add(draft(at: local.toUtc()));

    expect(tx.localDateKey, const DateKey(20260822));
    expect(tx.tzOffsetMinutes, local.timeZoneOffset.inMinutes);
  });

  test('a draft insists its timestamp is UTC', () {
    // The local date key is derived from this, so a local DateTime here would
    // be converted a second time and land on the wrong day.
    expect(
      () => TransactionDraft(
        amount: const Money(1),
        direction: TxDirection.expense,
        categoryId: 'cat',
        occurredAtUtc: DateTime(2026, 8, 21),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('tags are written and read back through the join table', () async {
    final tx = await repo.add(draft(tagIds: const ['travel', 'food']));
    expect((await repo.tagsOf(tx.id)).toSet(), {'travel', 'food'});
  });

  test('attaching a tag raises its usage count', () async {
    await repo.add(draft(tagIds: const ['travel']));
    expect((await db.tagsDao.byId('travel'))!.usageCount, 1);
  });

  test('editing a transaction does not re-count tag usage', () async {
    // The counter ranks how often a tag is reached for. Re-saving the same
    // transaction ten times is not ten uses, and inflating it would push a
    // rarely-used tag to the top of the picker.
    final tx = await repo.add(draft(tagIds: const ['travel']));
    await repo.update(tx, tagIds: const ['travel', 'food']);

    expect((await db.tagsDao.byId('travel'))!.usageCount, 1);
    expect((await db.tagsDao.byId('food'))!.usageCount, 0);
  });

  test('a draft without a category lands in Uncategorized, never null',
      () async {
    // Every chart depends on category_id being non-null. The draft type makes
    // categoryId required; this asserts the app-level default that feeds it.
    final uncategorized = TransactionDraft.uncategorized(
      amount: const Money(5000),
      direction: TxDirection.expense,
      occurredAtUtc: DateTime.utc(2026, 8, 21),
    );
    expect(uncategorized.categoryId, SystemCategoryIds.uncategorized);

    final tx = await repo.add(uncategorized);
    expect(tx.categoryId, SystemCategoryIds.uncategorized);
  });

  test('soft delete then restore round-trips', () async {
    final tx = await repo.add(draft());
    await repo.softDelete(tx.id);
    expect((await db.transactionsDao.byId(tx.id))!.deletedAt, isNotNull);

    await repo.restore(tx.id);
    expect((await db.transactionsDao.byId(tx.id))!.deletedAt, isNull);
  });

  test('update replaces the tag set rather than appending to it', () async {
    final tx = await repo.add(draft(tagIds: const ['travel', 'food']));
    await repo.update(tx, tagIds: const ['food']);
    expect((await repo.tagsOf(tx.id)).toSet(), {'food'});
  });

  test('update with no tag argument leaves the tags alone', () async {
    final tx = await repo.add(draft(tagIds: const ['travel']));
    await repo.update(tx);
    expect((await repo.tagsOf(tx.id)).toSet(), {'travel'});
  });

  test('clearing every tag actually clears them', () async {
    final tx = await repo.add(draft(tagIds: const ['travel']));
    await repo.update(tx, tagIds: const []);
    expect(await repo.tagsOf(tx.id), isEmpty);
  });

  test('a page carries a cursor only while more rows remain', () async {
    for (var i = 0; i < 45; i++) {
      await repo.add(draft(at: DateTime.utc(2026, 8, 21).subtract(
        Duration(hours: i * 5),
      )));
    }

    const query = PaginatedTransactionQuery(range: wholeEra, limit: 40);
    final first = await repo.page(query);
    expect(first.items, hasLength(40));
    expect(first.hasMore, isTrue);

    final second = await repo.page(query.next(first.cursor!));
    expect(second.items, hasLength(5));
    expect(second.hasMore, isFalse);
    expect(second.cursor, isNull);
  });

  test('a full last page still reports that it is the last one', () async {
    // The case that breaks `items.length == limit` as a hasMore heuristic.
    for (var i = 0; i < 10; i++) {
      await repo.add(draft(at: DateTime.utc(2026, 8, 21).subtract(
        Duration(hours: i * 5),
      )));
    }

    const query = PaginatedTransactionQuery(range: wholeEra, limit: 10);
    final page = await repo.page(query);
    expect(page.items, hasLength(10));
    expect(page.hasMore, isFalse);
  });

  test('next() carries the filters forward', () async {
    for (var i = 0; i < 6; i++) {
      await repo.add(draft(at: DateTime.utc(2026, 8, 21).subtract(
        Duration(hours: i * 5),
      )));
    }
    await repo.add(TransactionDraft(
      amount: const Money(9),
      direction: TxDirection.income,
      categoryId: 'cat',
      occurredAtUtc: DateTime.utc(2026, 8, 20),
    ));

    const query = PaginatedTransactionQuery(
      range: wholeEra,
      limit: 3,
      direction: TxDirection.expense,
    );
    final first = await repo.page(query);
    final second = await repo.page(query.next(first.cursor!));
    // A next page that dropped the filter would serve the income row and look
    // like a pagination bug rather than a filter one.
    expect(
      second.items.every((t) => t.direction == TxDirection.expense),
      isTrue,
    );
  });

  test('total sums the period in SQL and returns Money', () async {
    await repo.add(draft(amount: const Money(1000)));
    await repo.add(draft(amount: const Money(2500)));
    await repo.add(TransactionDraft(
      amount: const Money(9999),
      direction: TxDirection.income,
      categoryId: 'cat',
      occurredAtUtc: DateTime.utc(2026, 8, 21),
    ));

    expect(
      await repo.total(wholeEra, direction: TxDirection.expense),
      const Money(3500),
    );
    expect(await repo.total(wholeEra), const Money(13499));
  });
}
