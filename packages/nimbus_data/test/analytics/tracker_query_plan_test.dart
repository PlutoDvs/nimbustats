import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';

void main() {
  late AppDatabase db;
  late AnalyticsEngine engine;

  setUp(() {
    db = openTestDatabase();
    engine = AnalyticsEngine(db, calendar: const JalaliCalendar());
  });
  tearDown(() => db.close());

  /// The plan of the statement the engine will actually run.
  Future<String> planFor(TrackerQuerySpec spec) async {
    final compiled = engine.compileTracker(spec);
    final rows = await db
        .customSelect('EXPLAIN QUERY PLAN ${compiled.sql}',
            variables: compiled.variables)
        .get();
    return rows.map((r) => r.data['detail']).join(' | ');
  }

  // SQLite names an aliased table by its alias, so a full pass reads
  // "SCAN te", with or without an index after it.
  final scansEntries = matches(RegExp(r'SCAN te\b'));

  const today = DateRange(DateKey(20261005), DateKey(20261005));
  const mehr = DateRange(DateKey(20260923), DateKey(20261022));
  const year = DateRange(DateKey(20260321), DateKey(20270320));

  // Every shape the app issues (Tasks 6, 8, 9 and 10).
  final shapes = <String, TrackerQuerySpec>{
    "today's totals by tracker": TrackerQuerySpec(
        trackerIds: ['cig', 'water', 'gym'],
        dateRange: today,
        groupBy: const TrackerGroupByTracker(),
        aggregate: Aggregate.sum),
    'a range by day': TrackerQuerySpec(
        trackerIds: ['cig'],
        dateRange: mehr,
        groupBy: const TrackerGroupByDay(),
        aggregate: Aggregate.sum),
    'the whole history by day': TrackerQuerySpec(
        trackerIds: ['cig'],
        groupBy: const TrackerGroupByDay(),
        aggregate: Aggregate.count),
    'a range by hour': TrackerQuerySpec(
        trackerIds: ['cig'],
        dateRange: mehr,
        groupBy: const TrackerGroupByHourOfDay(),
        aggregate: Aggregate.sum),
    'a range by weekday': TrackerQuerySpec(
        trackerIds: ['cig'],
        dateRange: mehr,
        groupBy: const TrackerGroupByDayOfWeek(),
        aggregate: Aggregate.sum),
    'a year by month': TrackerQuerySpec(
        trackerIds: ['cig'],
        dateRange: year,
        groupBy: TrackerGroupByPeriod(PeriodType.month),
        aggregate: Aggregate.sum),
  };

  for (final MapEntry(key: name, value: spec) in shapes.entries) {
    test('$name seeks the tracker-day index', () async {
      final plan = await planFor(spec);
      expect(plan, contains('idx_tracker_entries_tracker_day'),
          reason: 'every tap re-runs the open tracker queries; one that '
              "walks a tracker's whole history slows with every day "
              'logged.\nPlan was: $plan');
      expect(plan, isNot(scansEntries), reason: 'plan: $plan');
    });
  }

  test('the whole history by day reads in index order, with no sort',
      () async {
    final plan = await planFor(shapes['the whole history by day']!);
    expect(plan, isNot(contains('TEMP B-TREE')), reason: plan);
  });
}
