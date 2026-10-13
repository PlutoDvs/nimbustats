import 'package:drift/drift.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    await db.categoriesDao.insertNode(id: 'food', name: 'Food', parentId: null);
    await db.categoriesDao
        .insertNode(id: 'uncat', name: 'Uncategorized', parentId: null);
    await db.tagsDao.insertNode(id: 'travel', name: 'travel', parentId: null);
    await db.tagsDao.insertNode(id: 'work', name: 'work', parentId: null);
  });
  tearDown(() => db.close());

  Future<String> addExpense({
    required int amount,
    required DateKey on,
    String category = 'food',
    bool confirmed = true,
  }) async {
    final id = 'tx-${on.value}-$amount';
    await db.transactionsDao.insertTransaction(
      id: id,
      direction: TxDirection.expense,
      amount: Money(amount),
      currencyCode: 'IRT',
      occurredAtUtc: on.toDateTime().millisecondsSinceEpoch,
      localDateKey: on,
      categoryId: category,
      source: TxSource.manual,
      isConfirmed: confirmed,
    );
    return id;
  }

  test('stores and reads back an exact amount', () async {
    final id =
        await addExpense(amount: 450000, on: DateKey.fromParts(2026, 8, 20));
    final tx = await db.transactionsDao.byId(id);
    expect(tx!.amount, const Money(450000));
    expect(tx.localDateKey, DateKey.fromParts(2026, 8, 20));
    expect(tx.isConfirmed, isTrue);
  });

  test('an amount beyond double precision survives storage exactly', () async {
    // 2^53 + 1 is the smallest integer a double cannot represent. Dart ints and
    // SQLite INTEGER are both 64-bit, so this must round-trip unchanged; if a
    // double ever creeps into the path it comes back as 2^53.
    const huge = 9007199254740993;
    final id = await addExpense(amount: huge, on: DateKey.fromParts(2026, 8, 2));
    final tx = await db.transactionsDao.byId(id);
    expect(tx!.amount.minorUnits, huge);
  });

  test('queries by date range inclusively', () async {
    await addExpense(amount: 100, on: DateKey.fromParts(2026, 8, 1));
    await addExpense(amount: 200, on: DateKey.fromParts(2026, 8, 31));
    await addExpense(amount: 300, on: DateKey.fromParts(2026, 9, 1));

    final august =
        DateRange(DateKey.fromParts(2026, 8, 1), DateKey.fromParts(2026, 8, 31));
    final rows = await db.transactionsDao.inRange(august);
    expect(rows.map((t) => t.amount.minorUnits).toSet(), {100, 200});
    expect(await db.transactionsDao.totalInRange(august), const Money(300));
  });

  test('can exclude unconfirmed captures', () async {
    final range =
        DateRange(DateKey.fromParts(2026, 8, 1), DateKey.fromParts(2026, 8, 31));
    await addExpense(amount: 100, on: DateKey.fromParts(2026, 8, 5));
    await addExpense(
        amount: 900, on: DateKey.fromParts(2026, 8, 6), confirmed: false);

    expect((await db.transactionsDao.inRange(range)).length, 2);
    expect(
        (await db.transactionsDao.inRange(range, confirmedOnly: true)).length,
        1);
  });

  test('assigns and replaces tags', () async {
    final id =
        await addExpense(amount: 500, on: DateKey.fromParts(2026, 8, 20));
    await db.transactionsDao.setTags(id, ['travel', 'work']);
    expect((await db.transactionsDao.tagsOf(id)).toSet(), {'travel', 'work'});

    await db.transactionsDao.setTags(id, ['travel']);
    expect((await db.transactionsDao.tagsOf(id)).toSet(), {'travel'});
  });

  test('the same tag cannot be attached twice', () async {
    final id =
        await addExpense(amount: 500, on: DateKey.fromParts(2026, 8, 20));
    await db.transactionsDao.setTags(id, ['travel', 'travel']);
    expect((await db.transactionsDao.tagsOf(id)).length, 1);
  });

  test('deleting a transaction removes its tag links', () async {
    final id =
        await addExpense(amount: 500, on: DateKey.fromParts(2026, 8, 20));
    await db.transactionsDao.setTags(id, ['travel']);
    await db.transactionsDao.deleteTransaction(id);
    expect(await db.transactionsDao.tagsOf(id), isEmpty);
  });

  test('rejects a transaction with a category that does not exist', () async {
    expect(
      () => addExpense(
          amount: 1, on: DateKey.fromParts(2026, 8, 20), category: 'ghost'),
      throwsA(anything),
    );
  });

  test('date-range lookup is an indexed range scan, not a table scan', () async {
    // Every period query in the app -- and every analytics aggregation built
    // on one -- goes through this predicate. A regression to a full scan would
    // stay invisible until the table is large and the app is already shipped.
    final august =
        DateRange(DateKey.fromParts(2026, 8, 1), DateKey.fromParts(2026, 8, 31));
    final query = db.transactionsDao.inRangeQuery(august).constructQuery();
    final plan = await db.customSelect(
      'EXPLAIN QUERY PLAN ${query.sql}',
      variables: query.boundVariables
          .map<Variable<Object>>(
              (v) => v is int ? Variable<int>(v) : Variable<String>('$v'))
          .toList(),
    ).get();
    final detail = plan.map((r) => r.read<String>('detail')).join(' | ');
    expect(detail, contains('idx_tx_date'), reason: 'plan: $detail');
    expect(detail, isNot(contains('SCAN transactions')), reason: 'plan: $detail');
  });

  group('insert only if absent (Phase 6 widget drain)', () {
    const day = DateKey(20261012);

    Future<bool> insertOnce(String id, {int amount = 1000}) =>
        db.transactionsDao.insertTransaction(
          id: id,
          direction: TxDirection.expense,
          amount: Money(amount),
          currencyCode: 'IRT',
          occurredAtUtc: day.toDateTime().millisecondsSinceEpoch,
          localDateKey: day,
          categoryId: 'food',
          source: TxSource.widget,
          onlyIfAbsent: true,
        );

    test('a second insert with the same id writes nothing', () async {
      expect(await insertOnce('w1', amount: 1000), isTrue);
      expect(await insertOnce('w1', amount: 9999), isFalse);
      expect((await db.transactionsDao.byId('w1'))!.amount, const Money(1000));
    });

    test('a soft-deleted row still holds its id: no resurrection', () async {
      await insertOnce('w2');
      await db.transactionsDao.softDelete('w2');
      expect(await insertOnce('w2'), isFalse);
      expect((await db.transactionsDao.byId('w2'))!.deletedAt, isA<int>());
    });

    test('two inserts racing on one id write it once', () async {
      final written = await Future.wait([insertOnce('w3'), insertOnce('w3')]);
      expect(written.where((w) => w), hasLength(1));
    });

    test('without it, a duplicate id is still an error', () async {
      final id = await addExpense(amount: 5, on: day);
      expect(
        () => db.transactionsDao.insertTransaction(
          id: id,
          direction: TxDirection.expense,
          amount: const Money(5),
          currencyCode: 'IRT',
          occurredAtUtc: day.toDateTime().millisecondsSinceEpoch,
          localDateKey: day,
          categoryId: 'food',
          source: TxSource.manual,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
