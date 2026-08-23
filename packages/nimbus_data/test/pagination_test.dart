import 'package:drift/drift.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

/// 5,000 transactions across roughly three years, which is what the brief
/// requires the list performance check to run against.
Future<void> seedLargeDatabase(AppDatabase db, {int count = 5000}) async {
  await db.categoriesDao.insertNode(id: 'cat', name: 'Cat', parentId: null);
  await db.batch((batch) {
    final now = DateTime.utc(2026, 8, 21);
    for (var i = 0; i < count; i++) {
      final at = now.subtract(Duration(hours: i * 5));
      batch.insert(
        db.transactions,
        TransactionsCompanion.insert(
          id: 'tx-${i.toString().padLeft(6, '0')}',
          direction: i % 7 == 0 ? TxDirection.income : TxDirection.expense,
          amount: Money(1000 + i),
          currencyCode: 'IRT',
          occurredAtUtc: at.millisecondsSinceEpoch,
          localDateKey: DateKey.fromDateTime(at),
          categoryId: 'cat',
          source: TxSource.manual,
          merchant: Value(i % 3 == 0 ? 'Cafe $i' : null),
          createdAt: at.millisecondsSinceEpoch,
          updatedAt: at.millisecondsSinceEpoch,
        ),
      );
    }
  });
}

void main() {
  late AppDatabase db;
  const wholeEra = DateRange(DateKey(20000101), DateKey(20991231));

  setUp(() async {
    db = openTestDatabase();
    await seedLargeDatabase(db);
  });

  tearDown(() => db.close());

  test('a keyset walk visits every row exactly once', () async {
    // The property that matters. LIMIT/OFFSET would also pass a naive count
    // test while quietly repeating or skipping rows whenever a write lands
    // between pages -- which is the normal case for an app being used.
    final seen = <String>[];
    TransactionCursorRow? cursor;

    while (true) {
      final page = await db.transactionsDao
          .pageAfter(range: wholeEra, after: cursor, limit: 100);
      if (page.isEmpty) break;
      seen.addAll(page.map((t) => t.id));
      final last = page.last;
      cursor = (dateKey: last.localDateKey, id: last.id);
    }

    expect(seen, hasLength(5000));
    expect(seen.toSet(), hasLength(5000), reason: 'no row may repeat');
  });

  test('pages come back newest first, and pages do not overlap', () async {
    final first =
        await db.transactionsDao.pageAfter(range: wholeEra, limit: 40);
    final last = first.last;
    final second = await db.transactionsDao.pageAfter(
      range: wholeEra,
      after: (dateKey: last.localDateKey, id: last.id),
      limit: 40,
    );

    expect(first, hasLength(40));
    expect(second, hasLength(40));
    expect(first.first.localDateKey.value,
        greaterThanOrEqualTo(first.last.localDateKey.value));
    expect(
      first.map((t) => t.id).toSet().intersection(
            second.map((t) => t.id).toSet(),
          ),
      isEmpty,
    );
  });

  test('a write landing between two pages cannot make a row repeat', () async {
    // The failure mode that rules LIMIT/OFFSET out. With an offset, inserting
    // a newer row shifts everything down by one and the second page re-serves
    // the last row of the first.
    final first =
        await db.transactionsDao.pageAfter(range: wholeEra, limit: 20);
    final last = first.last;

    await db.transactionsDao.insertTransaction(
      id: 'tx-interloper',
      direction: TxDirection.expense,
      amount: const Money(1),
      currencyCode: 'IRT',
      occurredAtUtc: DateTime.utc(2026, 8, 21).millisecondsSinceEpoch,
      localDateKey: const DateKey(20260821),
      categoryId: 'cat',
      source: TxSource.manual,
    );

    final second = await db.transactionsDao.pageAfter(
      range: wholeEra,
      after: (dateKey: last.localDateKey, id: last.id),
      limit: 20,
    );
    expect(
      first.map((t) => t.id).toSet().intersection(
            second.map((t) => t.id).toSet(),
          ),
      isEmpty,
    );
  });

  test('the page query uses the date index rather than scanning', () async {
    // Same technique Phase 0 used for the materialized path: assert the plan,
    // not the wall clock, so the guarantee survives a fast machine.
    final rows = await db.customSelect(
      'EXPLAIN QUERY PLAN SELECT * FROM transactions '
      'WHERE deleted_at IS NULL AND local_date_key BETWEEN ? AND ? '
      'ORDER BY local_date_key DESC, id DESC LIMIT 40',
      variables: [Variable<int>(20240101), Variable<int>(20991231)],
    ).get();
    final plan = rows.map((r) => r.data.values.join(' ')).join('\n');
    expect(plan.toLowerCase(), contains('idx_tx_date'),
        reason: 'pagination must not degrade into a table scan:\n$plan');
  });

  test('a period total is one SUM, not five thousand rows on the wire',
      () async {
    const range = DateRange(DateKey(20260801), DateKey(20260831));
    final total = await db.transactionsDao
        .sumInRange(range, direction: TxDirection.expense);
    final rows = await db.transactionsDao
        .inRange(range)
        .then((all) => all.where((t) => t.direction == TxDirection.expense));
    expect(total, Money.sum(rows.map((t) => t.amount)));
  });

  test('an empty range sums to zero rather than failing', () async {
    // SUM over no rows is NULL in SQL. That is zero money, not an error, and
    // a screen that shows a month with no spending must not blow up.
    const empty = DateRange(DateKey(19990101), DateKey(19991231));
    expect(await db.transactionsDao.sumInRange(empty), Money.zero);
  });

  test('soft-deleted rows leave the page and come back on restore', () async {
    final before =
        await db.transactionsDao.pageAfter(range: wholeEra, limit: 5);
    await db.transactionsDao.softDelete(before.first.id);

    final after =
        await db.transactionsDao.pageAfter(range: wholeEra, limit: 5);
    expect(after.map((t) => t.id), isNot(contains(before.first.id)));

    await db.transactionsDao.restore(before.first.id);
    final restored =
        await db.transactionsDao.pageAfter(range: wholeEra, limit: 5);
    expect(restored.map((t) => t.id), contains(before.first.id));
  });

  test('search matches merchant and note without treating input as SQL',
      () async {
    // A search box is untrusted input. LIKE wildcards inside it must match
    // literally, or a user typing % gets every row and a user typing _ gets
    // nonsense.
    final hits = await db.transactionsDao
        .pageAfter(range: wholeEra, searchText: 'Cafe 3', limit: 100);
    expect(hits, isNotEmpty);
    expect(hits.every((t) => t.merchant!.contains('Cafe 3')), isTrue);

    final wildcards = await db.transactionsDao
        .pageAfter(range: wholeEra, searchText: '%', limit: 100);
    expect(wildcards, isEmpty,
        reason: 'a literal percent sign matches no merchant in this data');

    final underscores = await db.transactionsDao
        .pageAfter(range: wholeEra, searchText: 'Cafe_3', limit: 100);
    expect(underscores, isEmpty,
        reason: 'an underscore is a literal, not a single-character wildcard');
  });

  test('filters compose with the cursor rather than replacing it', () async {
    final page = await db.transactionsDao.pageAfter(
      range: wholeEra,
      direction: TxDirection.income,
      limit: 10,
    );
    expect(page, hasLength(10));
    expect(page.every((t) => t.direction == TxDirection.income), isTrue);

    final last = page.last;
    final next = await db.transactionsDao.pageAfter(
      range: wholeEra,
      direction: TxDirection.income,
      after: (dateKey: last.localDateKey, id: last.id),
      limit: 10,
    );
    expect(next.every((t) => t.direction == TxDirection.income), isTrue);
    expect(
      page.map((t) => t.id).toSet().intersection(next.map((t) => t.id).toSet()),
      isEmpty,
    );
  });

  test('recentCategoryUsage returns the newest rows first', () async {
    final recent = await db.transactionsDao.recentCategoryUsage(limit: 5);
    expect(recent, hasLength(5));
    expect(recent.first.categoryId, 'cat');
    // Newest first: tx-000000 is the most recent seeded row.
    expect(recent.first.occurredAt.isAfter(recent.last.occurredAt), isTrue);
  });
}
