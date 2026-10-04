import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/settings/application/demo_data_seeder.dart';
import 'package:nimbustats/features/tags/data/tag_repository.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';

void main() {
  // Enough rows for the shares below to settle, few enough to stay fast.
  const count = 400;
  final now = DateTime.utc(2026, 10, 4, 12);
  const categoryIds = ['c0', 'c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7'];
  const paymentMethodIds = ['cash', 'card'];

  Future<AppDatabase> openDatabase() async {
    final db = AppDatabase.openInMemory();
    for (final id in categoryIds) {
      await db.categoriesDao.insertNode(id: id, name: id, parentId: null);
    }
    await db.paymentMethodsDao
        .insertMethod(id: 'cash', name: 'Cash', kind: PaymentMethodKind.cash);
    await db.paymentMethodsDao
        .insertMethod(id: 'card', name: 'Card', kind: PaymentMethodKind.card);
    return db;
  }

  DemoDataSeeder seederFor(AppDatabase db, {Random? random}) => DemoDataSeeder(
        transactions:
            TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman),
        tags: TagRepository(db.tagsDao),
        categoryIds: categoryIds,
        paymentMethodIds: paymentMethodIds,
        nowUtc: now,
        random: random,
      );

  Future<List<Map<String, Object?>>> select(AppDatabase db, String sql) async =>
      [for (final row in await db.customSelect(sql).get()) row.data];

  late AppDatabase db;

  setUp(() async {
    db = await openDatabase();
    await seederFor(db).seed(count: count);
  });
  tearDown(() => db.close());

  test('writes the rows asked for, all within the last two years', () async {
    final row = (await select(db,
            'SELECT COUNT(*) AS n, MIN(occurred_at_utc) AS first, '
            'MAX(occurred_at_utc) AS last FROM transactions'))
        .single;

    expect(row['n'], count);
    final first = DateTime.fromMillisecondsSinceEpoch(row['first']! as int,
        isUtc: true);
    final last =
        DateTime.fromMillisecondsSinceEpoch(row['last']! as int, isUtc: true);
    expect(first.isBefore(now.subtract(DemoDataSeeder.span)), isFalse,
        reason: 'first row at $first');
    expect(last.isAfter(now), isFalse, reason: 'last row at $last');
    // Spread across the span, not bunched at one end of it.
    expect(now.difference(first).inDays, greaterThan(700));
  });

  test('every row carries two or three tags', () async {
    final perRow = await select(db,
        'SELECT t.id, COUNT(tt.tag_id) AS n FROM transactions t '
        'LEFT JOIN transaction_tags tt ON tt.transaction_id = t.id '
        'GROUP BY t.id');

    expect(perRow, hasLength(count));
    expect({for (final r in perRow) r['n']}, everyElement(anyOf(2, 3)));
    expect({for (final r in perRow) r['n']}, containsAll([2, 3]));
  });

  test('some rows carry a tag together with its parent', () async {
    // What nested-tag rollup has to count once, not twice.
    final row = (await select(db,
            'SELECT COUNT(*) AS n FROM transaction_tags a '
            'JOIN tags child ON child.id = a.tag_id '
            'JOIN transaction_tags b ON b.transaction_id = a.transaction_id '
            'AND b.tag_id = child.parent_id'))
        .single;

    expect(row['n'], greaterThan(0));
  });

  test('categories are used unevenly, with a long tail', () async {
    final perCategory = await select(db,
        'SELECT category_id, COUNT(*) AS n FROM transactions '
        'GROUP BY category_id');
    final counts = [for (final r in perCategory) r['n']! as int]..sort();

    expect(perCategory, hasLength(categoryIds.length),
        reason: 'every category appears');
    expect(counts.last, greaterThanOrEqualTo(3 * counts.first),
        reason: 'counts: $counts');
  });

  test('ratings, payment methods, income and unconfirmed captures appear',
      () async {
    final row = (await select(db,
            "SELECT SUM(direction = 'income') AS income, "
            "SUM(direction = 'expense') AS expense, "
            "SUM(direction = 'expense' AND necessity IS NOT NULL "
            'AND satisfaction IS NOT NULL) AS rated, '
            'SUM(payment_method_id IS NOT NULL) AS paid, '
            'SUM(is_confirmed = 0) AS unconfirmed '
            'FROM transactions'))
        .single;
    double share(String key, int of) => (row[key]! as int) / of;
    final expenses = row['expense']! as int;

    expect(share('income', count), inInclusiveRange(0.05, 0.14));
    expect(share('rated', expenses), inInclusiveRange(0.6, 0.8));
    expect(share('paid', count), inInclusiveRange(0.7, 0.9));
    expect(share('unconfirmed', count), inInclusiveRange(0.02, 0.09));
  });

  test('the same seed gives the same history', () async {
    // A measurement repeated next month must be against the same data.
    const fingerprint = 'SELECT t.direction, t.amount, t.occurred_at_utc, '
        't.category_id, t.merchant, t.necessity, t.satisfaction, '
        't.payment_method_id, t.is_confirmed, '
        "(SELECT group_concat(name, ',') FROM (SELECT g.name FROM "
        'transaction_tags tt JOIN tags g ON g.id = tt.tag_id '
        'WHERE tt.transaction_id = t.id ORDER BY g.name)) AS tags '
        'FROM transactions t ORDER BY t.occurred_at_utc, t.amount';
    final first = await select(db, fingerprint);
    // One database at a time: drift warns when two are open at once.
    await db.close();
    db = await openDatabase();
    await seederFor(db).seed(count: count);

    expect(await select(db, fingerprint), first);
  });

  test('seeding again reuses the demo tags instead of duplicating them',
      () async {
    final before = (await select(db, 'SELECT COUNT(*) AS n FROM tags')).single;

    await seederFor(db).seed(count: 10);

    final after = (await select(db, 'SELECT COUNT(*) AS n FROM tags')).single;
    expect(after['n'], before['n']);
  });

  test('refuses to start without a category to file rows under', () {
    expect(
      () => DemoDataSeeder(
        transactions:
            TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman),
        tags: TagRepository(db.tagsDao),
        categoryIds: const [],
        paymentMethodIds: paymentMethodIds,
        nowUtc: now,
      ),
      throwsArgumentError,
    );
  });
}
