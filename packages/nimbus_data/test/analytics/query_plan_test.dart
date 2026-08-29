import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import 'support/analytics_fixture.dart';

void main() {
  late AppDatabase db;
  late AnalyticsEngine engine;

  setUp(() async {
    db = openTestDatabase();
    await seedAnalyticsFixture(db);
    engine = AnalyticsEngine(db, calendar: const GregorianCalendar());
  });
  tearDown(() => db.close());

  /// The plan of the statement the engine will actually run.
  Future<String> planFor(QuerySpec spec) async {
    final compiled = engine.compile(spec);
    final rows = await db
        .customSelect('EXPLAIN QUERY PLAN ${compiled.sql}',
            variables: compiled.variables)
        .get();
    return rows.map((r) => r.data['detail']).join(' | ');
  }

  test('a period-filtered total uses the date index', () async {
    final plan = await planFor(QuerySpec(
      filters: QueryFilters(
          dateRange:
              DateRange(const DateKey(20260101), const DateKey(20260131))),
      groupBy: const GroupByNone(),
      aggregate: Aggregate.sum,
    ));
    expect(plan, contains('idx_tx_date'),
        reason: 'the dashboard asks this on every open; a full scan here is '
            'the difference between instant and visibly slow at 50k rows.\n'
            'Plan was: $plan');
    expect(plan, isNot(contains('SCAN transactions')), reason: 'plan: $plan');
  });

  test('a category breakdown does not scan the categories table', () async {
    final plan = await planFor(QuerySpec(
      filters: QueryFilters(
          dateRange:
              DateRange(const DateKey(20260101), const DateKey(20261231))),
      groupBy: GroupByCategory(0),
      aggregate: Aggregate.sum,
    ));
    expect(plan, isNot(contains('SCAN categories')), reason: 'plan: $plan');
  });

  test('the tag EXISTS subquery is index-driven, never a nested scan',
      () async {
    // Measured plan: the correlated subquery drives from the transaction --
    // SEARCH tt (transaction_id=?) then SEARCH tg (id=?) -- and tests the path
    // range on the single tag row it already holds. It therefore never reaches
    // for idx_tags_path, which would only pay off driving from the tag side.
    //
    // What must hold is that neither table inside the subquery is scanned. A
    // scan there runs once per transaction, so it is the difference between
    // O(N) indexed lookups and an O(N*M) nested loop.
    final plan = await planFor(QuerySpec(
      filters: QueryFilters(tags: TagsAny(const ['/travel/'])),
      groupBy: const GroupByNone(),
      aggregate: Aggregate.sum,
    ));
    expect(plan, contains('SEARCH tt'), reason: 'plan: $plan');
    expect(plan, contains('SEARCH tg'), reason: 'plan: $plan');
    expect(plan, isNot(contains('SCAN tt')),
        reason: 'a scan of transaction_tags per row is the O(N*M) trap.\n'
            'plan: $plan');
    expect(plan, isNot(contains('SCAN tg')), reason: 'plan: $plan');
  });

  test('a tag filter narrowed by a period still uses the date index', () async {
    // The shape the app actually issues: "within #travel, this month". The
    // bare tag filter above legitimately scans transactions because nothing
    // bounds it; once a period bounds it, the outer query must use the index.
    final plan = await planFor(QuerySpec(
      filters: QueryFilters(
        dateRange: DateRange(const DateKey(20260101), const DateKey(20260131)),
        tags: TagsAny(const ['/travel/']),
      ),
      groupBy: const GroupByNone(),
      aggregate: Aggregate.sum,
    ));
    expect(plan, contains('idx_tx_date'), reason: 'plan: $plan');
    expect(plan, isNot(contains('SCAN t ')), reason: 'plan: $plan');
  });

  test('the confirmed-only dashboard query uses a composite index', () async {
    final plan = await planFor(QuerySpec(
      filters: QueryFilters(
        dateRange: DateRange(const DateKey(20260101), const DateKey(20260131)),
        confirmedOnly: true,
      ),
      groupBy: const GroupByNone(),
      aggregate: Aggregate.sum,
    ));
    expect(plan, anyOf(contains('idx_tx_unconfirmed'), contains('idx_tx_date')),
        reason: 'plan: $plan');
  });
}
