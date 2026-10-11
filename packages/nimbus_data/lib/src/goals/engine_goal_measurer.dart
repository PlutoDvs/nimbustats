import 'package:nimbus_domain/nimbus_domain.dart';

import '../analytics/analytics_engine.dart';
import '../database/app_database.dart';

/// [GoalMeasurer] over Phase 3's [AnalyticsEngine] (goals design §3).
///
/// This file holds the codebase's only switches on [GoalMetric]: what a
/// metric reads is decided here, once, and nothing upstream branches on it.
/// Every number comes from the engine, so a goal and a chart over the same
/// rows cannot disagree: deleted rows out, unconfirmed captures in.
///
/// Statements run one after another. drift serializes every statement on
/// its one connection, so issuing them together would only queue them.
final class EngineGoalMeasurer implements GoalMeasurer {
  EngineGoalMeasurer(this._db, this._engine);

  /// Read only to re-resolve stored paths ([_filtersNow]).
  final AppDatabase _db;
  final AnalyticsEngine _engine;

  /// Days per money query in [measureDaily].
  ///
  /// The engine buckets money by day with a CASE ladder, one branch per day,
  /// so one query over a span costs rows x days: a three-year history would
  /// test every row against a thousand ranges. A window of about a month
  /// keeps it at rows x 31, for a few more statements. Each
  /// `AnalyticsEngine.run` also issues a second statement for the true total,
  /// so a window costs 2 statements (4 for net savings, which runs income and
  /// expense). Tracker entries group by their stored day key directly and
  /// need no windows.
  static const _window = 31;

  @override
  Future<GoalAmount> measure(
          GoalMetric metric, GoalScope scope, DateRange range) async =>
      switch (metric) {
        GoalMetric.moneySum =>
          MoneyAmount((await _money(scope, range)).trueTotal),
        GoalMetric.txnCount =>
          QuantityAmount((await _money(scope, range)).trueCount.toDouble()),
        GoalMetric.trackerSum => QuantityAmount(
            (await _tracker(scope, range, const TrackerGroupByNone())).sum),
        GoalMetric.trackerCount => QuantityAmount(
            (await _tracker(scope, range, const TrackerGroupByNone()))
                .count
                .toDouble()),
        GoalMetric.netSavings => MoneyAmount(
            (await _money(scope, range, MoneyDirection.income)).trueTotal -
                (await _money(scope, range, MoneyDirection.expense))
                    .trueTotal),
      };

  @override
  Future<Map<DateKey, GoalAmount>> measureDaily(
          GoalMetric metric, GoalScope scope, DateRange span) async =>
      switch (metric) {
        GoalMetric.moneySum => <DateKey, GoalAmount>{
            for (final bucket in await _moneyDays(scope, span))
              _dayOf(bucket.key): MoneyAmount(bucket.money),
          },
        GoalMetric.txnCount => <DateKey, GoalAmount>{
            for (final bucket in await _moneyDays(scope, span))
              _dayOf(bucket.key): QuantityAmount(bucket.count.toDouble()),
          },
        GoalMetric.trackerSum => <DateKey, GoalAmount>{
            for (final bucket
                in (await _tracker(scope, span, const TrackerGroupByDay()))
                    .buckets)
              _dayOf(bucket.key): QuantityAmount(bucket.value),
          },
        GoalMetric.trackerCount => <DateKey, GoalAmount>{
            for (final bucket
                in (await _tracker(scope, span, const TrackerGroupByDay()))
                    .buckets)
              _dayOf(bucket.key): QuantityAmount(bucket.count.toDouble()),
          },
        GoalMetric.netSavings => _net(
            await _moneyDays(scope, span, MoneyDirection.income),
            await _moneyDays(scope, span, MoneyDirection.expense)),
      };

  /// One ungrouped money query. Its true total and count count each
  /// transaction once.
  Future<AnalyticsResult> _money(GoalScope scope, DateRange range,
          [MoneyDirection? direction]) async =>
      _engine.run(QuerySpec(
        filters: (await _filtersNow(scope, direction)).withDateRange(range),
        groupBy: const GroupByNone(),
        aggregate: Aggregate.sum,
      ));

  /// Money by day over [span], in windows of [_window] days. Each bucket's
  /// money is the day's sum, and its count the day's rows.
  Future<List<Bucket>> _moneyDays(GoalScope scope, DateRange span,
      [MoneyDirection? direction]) async {
    final filters = await _filtersNow(scope, direction);
    final buckets = <Bucket>[];
    for (var start = span.startInclusive;
        start <= span.endInclusive;
        start = start.addDays(_window)) {
      final last = start.addDays(_window - 1);
      final window =
          DateRange(start, last < span.endInclusive ? last : span.endInclusive);
      final result = await _engine.run(QuerySpec(
        filters: filters.withDateRange(window),
        groupBy: const GroupByPeriod(PeriodType.day),
        aggregate: Aggregate.sum,
      ));
      buckets.addAll(result.buckets);
    }
    return buckets;
  }

  Future<TrackerResult> _tracker(
          GoalScope scope, DateRange range, TrackerGroupBy groupBy) =>
      _engine.runTracker(TrackerQuerySpec(
        trackerIds: [_trackerIdOf(scope)],
        dateRange: range,
        groupBy: groupBy,
        aggregate: Aggregate.sum,
      ));

  /// Income minus expense, day by day. A day with only one of the two still
  /// has data.
  static Map<DateKey, GoalAmount> _net(
      List<Bucket> income, List<Bucket> expense) {
    final net = <DateKey, Money>{
      for (final bucket in income) _dayOf(bucket.key): bucket.money,
    };
    for (final bucket in expense) {
      final day = _dayOf(bucket.key);
      net[day] = (net[day] ?? Money.zero) - bucket.money;
    }
    return {
      for (final MapEntry(:key, :value) in net.entries) key: MoneyAmount(value),
    };
  }

  /// A day bucket's day. Both engine paths key a day as a one-day
  /// [PeriodKey].
  static DateKey _dayOf(BucketKey key) =>
      (key as PeriodKey).range.startInclusive;

  /// The scope's filters, with every stored category and tag path
  /// re-resolved to where its node is now, and with [direction] if given.
  ///
  /// A goal stores materialized paths, and moving a node rewrites its path,
  /// so the stored one would match nothing and a cap would read zero for
  /// ever (Review Focus 1). A path's last segment is its node's own id, so
  /// the node is looked up by that id.
  ///
  /// The lookup ignores deleted_at, as `CategoriesDao.byId` does: it asks
  /// where the node is, not whether it is live. Whether a deleted node's rows
  /// count stays the engine's rule. A soft-deleted category's live expenses
  /// still count, as they do in Analytics; a soft-deleted tag matches
  /// nothing. An id with no row at all keeps its stored path, which matches
  /// nothing.
  ///
  /// The filters are rebuilt through JSON, which Phase 3 keeps lossless. A
  /// filter field added to QueryFilters later is therefore carried over
  /// rather than silently dropped -- and a dropped filter widens the goal.
  Future<QueryFilters> _filtersNow(
      GoalScope scope, MoneyDirection? direction) async {
    final stored = _filtersOf(scope);
    final json = stored.toJson();
    final categories = stored.categorySubtreePaths;
    if (categories.isNotEmpty) {
      json['categorySubtreePaths'] = _relocated(categories,
          await _categoryPaths(categories.map(_leafId).toList()));
    }
    final tags = stored.tags;
    if (tags != null) {
      json['tags'] = {
        ...tags.toJson(),
        'paths': _relocated(tags.subtreePaths,
            await _tagPaths(tags.subtreePaths.map(_leafId).toList())),
      };
    }
    if (direction != null) {
      json['direction'] = direction.name;
    }
    return QueryFilters.fromJson(json);
  }

  Future<Map<String, String>> _categoryPaths(List<String> ids) async => {
        for (final row in await (_db.select(_db.categories)
              ..where((t) => t.id.isIn(ids)))
            .get())
          row.id: row.path,
      };

  Future<Map<String, String>> _tagPaths(List<String> ids) async => {
        for (final row
            in await (_db.select(_db.tags)..where((t) => t.id.isIn(ids))).get())
          row.id: row.path,
      };

  static List<String> _relocated(List<String> stored, Map<String, String> now) =>
      [for (final path in stored) now[_leafId(path)] ?? path];

  static String _leafId(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty);
    return segments.isEmpty ? path : segments.last;
  }

  static QueryFilters _filtersOf(GoalScope scope) => switch (scope) {
        MoneyScope(:final filters) => filters,
        TrackerScope() => throw ArgumentError.value(
            scope, 'scope', 'a money metric needs a money scope'),
      };

  static String _trackerIdOf(GoalScope scope) => switch (scope) {
        TrackerScope(:final trackerId) => trackerId,
        MoneyScope() => throw ArgumentError.value(
            scope, 'scope', 'a tracker metric needs a tracker scope'),
      };
}
