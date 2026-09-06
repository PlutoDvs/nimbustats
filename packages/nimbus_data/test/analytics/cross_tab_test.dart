import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';

/// A fixture of its own rather than the shared one, which has a single
/// category and so cannot tell a cross-tab from a tag breakdown.
///
/// Numbers below are hand-computed from these rows:
///
///   x1  1000  dining (under food)  tags: travel, work
///   x2   500  transport            tags: travel
///   x3   250  dining               tags: none
///
/// True total 1750 over three transactions. The cells sum to 2500, because x1
/// is counted under both its tags -- and x3 appears in no cell at all.
Future<void> seedCrossTabFixture(AppDatabase db) async {
  Future<void> category(String id, String path, int depth, String? parent) =>
      db.customStatement(
        'INSERT INTO categories (id,name,icon_key,color,parent_id,path,depth,'
        'sort_order,kind,archived,created_at,updated_at,deleted_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,NULL)',
        [id, id, 'tag', 0, parent, path, depth, 0, 'expense', 0, 1, 1],
      );

  await category('food', '/food/', 0, null);
  await category('dining', '/food/dining/', 1, 'food');
  await category('transport', '/transport/', 0, null);

  Future<void> tag(String id, String path) => db.customStatement(
        'INSERT INTO tags (id,name,icon_key,color,parent_id,path,depth,'
        'sort_order,usage_count,archived,created_at,updated_at,deleted_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,NULL)',
        [id, id, 'tag', 0, null, path, 0, 0, 0, 0, 1, 1],
      );

  await tag('travel', '/travel/');
  await tag('work', '/work/');

  Future<void> tx(String id, int amount, String categoryId) =>
      db.customStatement(
        'INSERT INTO transactions (id,direction,amount,currency_code,'
        'occurred_at_utc,local_date_key,tz_offset_minutes,category_id,'
        'payment_method_id,merchant,note,necessity,satisfaction,source,'
        'is_confirmed,capture_id,created_at,updated_at,deleted_at) '
        'VALUES (?,?,?,?,?,?,?,?,NULL,NULL,NULL,NULL,NULL,?,1,NULL,?,?,NULL)',
        [id, 'expense', amount, 'IRT', 0, 20260110, 0, categoryId, 'manual', 1,
            1],
      );

  await tx('x1', 1000, 'dining');
  await tx('x2', 500, 'transport');
  await tx('x3', 250, 'dining');

  Future<void> link(String txId, String tagId) => db.customStatement(
      'INSERT INTO transaction_tags (transaction_id,tag_id) VALUES (?,?)',
      [txId, tagId]);

  await link('x1', 'travel');
  await link('x1', 'work');
  await link('x2', 'travel');
}

void main() {
  late AppDatabase db;
  late AnalyticsEngine engine;

  setUp(() async {
    db = openTestDatabase();
    await seedCrossTabFixture(db);
    engine = AnalyticsEngine(db, calendar: const GregorianCalendar());
  });
  tearDown(() => db.close());

  QuerySpec specAt(int depth) => QuerySpec(
        filters: const QueryFilters(),
        groupBy: GroupByTagCrossCategory(depth),
        aggregate: Aggregate.sum,
      );

  Map<(String, String), int> cellsOf(AnalyticsResult result) => {
        for (final bucket in result.buckets)
          if (bucket.key case TagCategoryKey(:final tagId, :final categoryId))
            (tagId, categoryId): bucket.money.minorUnits,
      };

  test('cells are one per tag and rolled-up category pair', () async {
    final result = await engine.run(specAt(0));

    expect(cellsOf(result), {
      ('travel', 'food'): 1000,
      ('travel', 'transport'): 500,
      ('work', 'food'): 1000,
    });
  });

  test('the cells sum to more than the true total', () async {
    // The inequality is the point. Asserting equality here would be asserting
    // the bug: x1 is counted under travel and again under work.
    final result = await engine.run(specAt(0));

    expect(result.bucketSum, const Money(2500));
    expect(result.trueTotal, const Money(1750));
    expect(result.bucketSum.minorUnits,
        greaterThan(result.trueTotal.minorUnits));
  });

  test('the result declares that its buckets overlap', () async {
    // What the UI reads to decide whether to disclose. Without it the matrix
    // renders cells that cannot be reconciled with the total and says nothing.
    final result = await engine.run(specAt(0));
    expect(result.overlaps, isTrue);
  });

  test('an untagged transaction is in the total but in no cell', () async {
    // x3 has no tags, so a tag axis has nowhere to put it. That is honest, and
    // it is a second reason the cells cannot be reconciled by arithmetic --
    // they are short by 250 and long by 1000 at the same time.
    final result = await engine.run(specAt(0));

    expect(result.trueCount, 3);
    expect(
      result.buckets.fold<int>(0, (sum, b) => sum + b.count),
      3,
      reason: 'x1 twice and x2 once; x3 is absent',
    );
  });

  test('the category axis respects its depth', () async {
    final result = await engine.run(specAt(1));

    expect(cellsOf(result), {
      ('travel', 'dining'): 1000,
      ('travel', 'transport'): 500,
      ('work', 'dining'): 1000,
    });
  });

  test('a category shallower than the depth is kept, not dropped', () async {
    // transport sits at depth 0. Asking for depth 1 must bucket it at its own
    // depth rather than losing it, which is what min(c.depth, ?) is for.
    final result = await engine.run(specAt(5));
    expect(cellsOf(result).containsKey(('travel', 'transport')), isTrue);
  });

  test('the true total is the same whatever the depth', () async {
    for (final depth in [0, 1, 5]) {
      final result = await engine.run(specAt(depth));
      expect(result.trueTotal, const Money(1750),
          reason: 'depth $depth changed a total it must not touch');
    }
  });

  test('nothing is re-scanned per row', () async {
    // Measured plan for the unfiltered cross-tab: the planner drives from
    // transaction_tags and reaches t, c, tg and a by index. That is the right
    // shape -- one pass over the smallest table, indexed lookups for the rest.
    //
    // So the assertion is not "tt is never scanned", which would be asserting
    // a worse plan. What must hold is that only the driving table is scanned:
    // a second SCAN means some table is walked again for every row of the
    // first, which is the O(N*M) trap the brief names.
    final compiled = engine.compile(specAt(0));
    final rows = await db
        .customSelect('EXPLAIN QUERY PLAN ${compiled.sql}',
            variables: compiled.variables)
        .get();
    final plan = rows.map((r) => r.data['detail']! as String).toList();
    final scans = plan.where((line) => line.contains('SCAN')).toList();

    expect(scans, hasLength(1),
        reason: 'more than one table is walked: ${plan.join(" | ")}');
  });

  test('a period-bounded cross-tab drives from the date index', () async {
    // The shape the screen actually issues. Unbounded, a scan of the driving
    // table is unavoidable; once a period bounds it, the planner has an index
    // to start from and must use it.
    final compiled = engine.compile(QuerySpec(
      filters: QueryFilters(
        dateRange: DateRange(const DateKey(20260101), const DateKey(20260131)),
      ),
      groupBy: GroupByTagCrossCategory(0),
      aggregate: Aggregate.sum,
    ));
    final rows = await db
        .customSelect('EXPLAIN QUERY PLAN ${compiled.sql}',
            variables: compiled.variables)
        .get();
    final plan = rows.map((r) => r.data['detail']).join(' | ');

    expect(plan, contains('idx_tx_date'), reason: 'plan: $plan');
  });

}
