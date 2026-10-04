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

  /// The plan of the true-total statement that runs beside every grouped one.
  Future<String> trueTotalPlanFor(QuerySpec spec) async {
    final compiled = engine.compileTrueTotal(spec);
    final rows = await db
        .customSelect('EXPLAIN QUERY PLAN ${compiled.sql}',
            variables: compiled.variables)
        .get();
    return rows.map((r) => r.data['detail']).join(' | ');
  }

  // SQLite names an aliased table by its alias, so a full pass over
  // transactions reads "SCAN t", with or without an index after it.
  final scansTransactions = matches(RegExp(r'SCAN t\b'));

  const month = DateRange(DateKey(20260101), DateKey(20260131));

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
    expect(plan, isNot(scansTransactions), reason: 'plan: $plan');
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
    expect(plan, isNot(scansTransactions), reason: 'plan: $plan');
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

  test('the pinned-views query is served by its index', () async {
    // The same predicate and order as SavedViewsDao.watchPinned, which the
    // dashboard runs on every open.
    final rows = await db
        .customSelect('EXPLAIN QUERY PLAN SELECT * FROM saved_views '
            'WHERE deleted_at IS NULL AND pinned = 1 ORDER BY sort_order')
        .get();
    final plan = rows.map((r) => r.data['detail']).join(' | ');
    expect(plan, contains('idx_saved_views_pinned'), reason: 'plan: $plan');
  });

  test("the starter breakdown card's query uses the date index", () async {
    final plan = await planFor(QuerySpec(
      filters: QueryFilters(
        dateRange: DateRange(const DateKey(20260101), const DateKey(20260131)),
        direction: MoneyDirection.expense,
      ),
      groupBy: GroupByCategory(0),
      aggregate: Aggregate.sum,
    ));
    expect(plan, contains('idx_tx_date'), reason: 'plan: $plan');
    expect(plan, isNot(scansTransactions), reason: 'plan: $plan');
  });

  test("the starter trend card's query uses the date index", () async {
    final plan = await planFor(QuerySpec(
      filters: QueryFilters(
        dateRange: DateRange(const DateKey(20250801), const DateKey(20260131)),
        direction: MoneyDirection.expense,
      ),
      groupBy: const GroupByPeriod(PeriodType.month),
      aggregate: Aggregate.sum,
    ));
    expect(plan, contains('idx_tx_date'), reason: 'plan: $plan');
    expect(plan, isNot(scansTransactions), reason: 'plan: $plan');
  });

  // Every tab can be pinned, so each tab's question is a dashboard query too.
  for (final (name, groupBy) in const [
    ('hour-of-day', GroupByHourOfDay()),
    ('day-of-week', GroupByDayOfWeek()),
    ('reflection', GroupByReflection()),
  ]) {
    test("the $name pattern's query uses the date index", () async {
      // The shape PatternsView builds: a month of spending.
      final plan = await planFor(QuerySpec(
        filters: const QueryFilters(
            dateRange: month, direction: MoneyDirection.expense),
        groupBy: groupBy,
        aggregate: Aggregate.sum,
      ));
      expect(plan, contains('idx_tx_date'), reason: 'plan: $plan');
      expect(plan, isNot(scansTransactions), reason: 'plan: $plan');
    });
  }

  test("a period's true total uses the date index", () async {
    // Runs beside every grouped query, so it is as hot as they are.
    final plan = await trueTotalPlanFor(QuerySpec(
      filters:
          const QueryFilters(dateRange: month, direction: MoneyDirection.expense),
      groupBy: GroupByCategory(0),
      aggregate: Aggregate.sum,
    ));
    expect(plan, contains('idx_tx_date'), reason: 'plan: $plan');
    expect(plan, isNot(scansTransactions), reason: 'plan: $plan');
  });

  test("a tag-filtered true total stays index-driven", () async {
    final plan = await trueTotalPlanFor(QuerySpec(
      filters: QueryFilters(dateRange: month, tags: TagsAny(const ['/travel/'])),
      groupBy: const GroupByTag(),
      aggregate: Aggregate.sum,
    ));
    expect(plan, contains('idx_tx_date'), reason: 'plan: $plan');
    expect(plan, isNot(scansTransactions), reason: 'plan: $plan');
    expect(plan, isNot(contains('SCAN tt')), reason: 'plan: $plan');
    expect(plan, isNot(contains('SCAN tg')), reason: 'plan: $plan');
  });
}
