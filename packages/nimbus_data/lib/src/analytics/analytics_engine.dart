// drift exports a GroupBy of its own; this file means the domain's.
import 'package:drift/drift.dart' hide GroupBy;
import 'package:nimbus_domain/nimbus_domain.dart';

import '../database/app_database.dart';
import 'analytics_predicates.dart';
import 'compiled_query.dart';
import 'group_expressions.dart';

/// Turns a [QuerySpec] into one SQL statement and its answer.
///
/// One engine, not two: a screen that needs a bespoke query is a missing
/// `QuerySpec` capability. A second query path beside this one is how the
/// numbers start disagreeing between two charts that should match.
///
/// Tracker questions come here too, as a [TrackerQuerySpec]: the same engine
/// over `tracker_entries`, with the same SQL for the dimensions the two
/// tables share.
final class AnalyticsEngine {
  AnalyticsEngine(this._db, {required this.calendar});

  final AppDatabase _db;

  /// The calendar every period boundary is computed in. Public because it is
  /// part of what this engine's answers mean, not an implementation detail.
  final AppCalendar calendar;

  CompiledQuery compile(QuerySpec spec) {
    final where = AnalyticsPredicates.whereClause(spec.filters);
    final group = GroupExpressions.forDimension(
      spec.groupBy,
      span: spec.filters.dateRange,
      calendar: calendar,
    );

    // Variable order must match placeholder order in the finished statement:
    // SELECT fragments first, then JOIN, then WHERE.
    final variables = <Variable<Object>>[
      ...group.variables,
      ...where.variables,
    ];

    final sql = 'SELECT ${group.selectSql}, '
        'COALESCE(SUM(t.amount), 0) AS total, '
        'COUNT(*) AS n, '
        'MIN(t.amount) AS low, MAX(t.amount) AS high, AVG(t.amount) AS mean '
        'FROM transactions t${group.joinSql} '
        'WHERE ${where.sql} '
        'GROUP BY ${group.groupSql} '
        'ORDER BY ${group.groupSql}';

    return CompiledQuery(sql: sql, variables: variables);
  }

  /// The statement for [spec]'s true total: its filters, ungrouped.
  ///
  /// It counts each transaction once, so it is deliberately not derived from
  /// the buckets -- on a tag dimension those overlap. It runs beside every
  /// grouped query, which makes it as hot as they are, so it is compiled here
  /// where its plan can be asserted rather than inline in [run].
  CompiledQuery compileTrueTotal(QuerySpec spec) {
    final where = AnalyticsPredicates.whereClause(spec.filters);
    return CompiledQuery(
      sql: 'SELECT COALESCE(SUM(t.amount), 0) AS total, COUNT(*) AS n '
          'FROM transactions t WHERE ${where.sql}',
      variables: where.variables,
    );
  }

  /// Fires whenever a table this engine reads is written.
  ///
  /// An answer is a snapshot; this is how a screen learns it went stale. The
  /// tables are every one a [QuerySpec] can reach: transactions and their tag
  /// links for the rows, categories and tags for the subtree paths a filter
  /// or a rollup resolves against. Settings and saved views are left out --
  /// neither changes what a spec means.
  Stream<void> changes() => _db
      .tableUpdates(TableUpdateQuery.onAllTables([
        _db.transactions,
        _db.transactionTags,
        _db.categories,
        _db.tags,
      ]))
      .map((_) {});

  Future<AnalyticsResult> run(QuerySpec spec) async {
    final compiled = compile(spec);
    final rows =
        await _db.customSelect(compiled.sql, variables: compiled.variables).get();

    final trueTotal = compileTrueTotal(spec);
    final trueRow = await _db
        .customSelect(trueTotal.sql, variables: trueTotal.variables)
        .getSingle();

    final periods = switch (spec.groupBy) {
      GroupByPeriod(:final period) =>
        GroupExpressions.periodsOf(period, spec.filters.dateRange!, calendar),
      _ => const <DateRange>[],
    };

    return AnalyticsResult(
      buckets: [
        for (final row in rows)
          Bucket(
            key: _keyOf(spec.groupBy, row, periods),
            money: _moneyOf(spec.aggregate, row),
            count: row.data['n']! as int,
          ),
      ],
      trueTotal: Money(trueRow.data['total']! as int),
      trueCount: trueRow.data['n']! as int,
      bucketsMayOverlap: spec.isTagDimension,
    );
  }

  /// The statement for a tracker question: [compile]'s counterpart over
  /// `tracker_entries`.
  ///
  /// Still one engine. The dimensions trackers share with transactions come
  /// from the same [GroupExpressions], and the soft-delete rule from the same
  /// [AnalyticsPredicates.notDeleted].
  CompiledQuery compileTracker(TrackerQuerySpec spec) {
    final group = GroupExpressions.forTrackerDimension(
      spec.groupBy,
      span: spec.dateRange,
      calendar: calendar,
    );
    final placeholders = List.filled(spec.trackerIds.length, '?').join(',');
    final conditions = <String>[
      AnalyticsPredicates.notDeleted('te'),
      'te.tracker_id IN ($placeholders)',
    ];
    // Variable order must match placeholder order in the finished statement:
    // SELECT fragments first, then WHERE.
    final variables = <Variable<Object>>[
      ...group.variables,
      ...spec.trackerIds.map(Variable.withString),
    ];
    final range = spec.dateRange;
    if (range != null) {
      conditions.add('te.local_date_key BETWEEN ? AND ?');
      variables
        ..add(Variable.withInt(range.startInclusive.value))
        ..add(Variable.withInt(range.endInclusive.value));
    }

    final sql = 'SELECT ${group.selectSql}, '
        'COALESCE(SUM(te.value), 0) AS total, '
        'COUNT(*) AS n, '
        'MIN(te.value) AS low, MAX(te.value) AS high, AVG(te.value) AS mean '
        'FROM tracker_entries te '
        'WHERE ${conditions.join(' AND ')} '
        'GROUP BY ${group.groupSql} '
        'ORDER BY ${group.groupSql}';
    return CompiledQuery(sql: sql, variables: variables);
  }

  /// Fires whenever a tracker entry is written. A spec names its trackers by
  /// id, so a write to `trackers` itself changes no answer.
  Stream<void> trackerChanges() => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.trackerEntries))
      .map((_) {});

  Future<TrackerResult> runTracker(TrackerQuerySpec spec) async {
    final compiled = compileTracker(spec);
    final rows = await _db
        .customSelect(compiled.sql, variables: compiled.variables)
        .get();

    final periods = switch (spec.groupBy) {
      TrackerGroupByPeriod(:final period) =>
        GroupExpressions.periodsOf(period, spec.dateRange!, calendar),
      _ => const <DateRange>[],
    };

    // No tracker dimension puts an entry in two buckets, so the totals are
    // the rows' own, added up -- no second statement.
    final buckets = <TrackerBucket>[];
    var sum = 0.0;
    var count = 0;
    for (final row in rows) {
      final n = row.data['n']! as int;
      sum += _real(row.data['total']);
      count += n;
      buckets.add(TrackerBucket(
        key: _trackerKeyOf(spec.groupBy, row, periods),
        value: _trackerValueOf(spec.aggregate, row),
        count: n,
      ));
    }
    return TrackerResult(buckets: buckets, sum: sum, count: count);
  }

  BucketKey _trackerKeyOf(
      TrackerGroupBy dimension, QueryRow row, List<DateRange> periods) {
    final bucket = row.data['bucket'];
    return switch (dimension) {
      TrackerGroupByNone() => const TotalKey(),
      TrackerGroupByTracker() => TrackerKey(bucket! as String),
      TrackerGroupByDay() => PeriodKey(
          DateRange(DateKey(bucket! as int), DateKey(bucket as int))),
      TrackerGroupByPeriod() => PeriodKey(periods[bucket! as int]),
      TrackerGroupByHourOfDay() => HourOfDayKey(bucket! as int),
      // SQLite's %w is 0=Sunday; ISO is 1=Monday..7=Sunday.
      TrackerGroupByDayOfWeek() =>
        DayOfWeekKey(bucket! as int == 0 ? DateTime.sunday : bucket as int),
    };
  }

  static double _trackerValueOf(Aggregate aggregate, QueryRow row) =>
      switch (aggregate) {
        Aggregate.sum => _real(row.data['total']),
        Aggregate.count => (row.data['n']! as int).toDouble(),
        Aggregate.min => _real(row.data['low']),
        Aggregate.max => _real(row.data['high']),
        Aggregate.average => _real(row.data['mean']),
      };

  /// SQLite hands a REAL back as a double, but it may store a whole value as
  /// an integer, and an aggregate over those can come back as an int.
  static double _real(Object? raw) => (raw! as num).toDouble();

  BucketKey _keyOf(GroupBy dimension, QueryRow row, List<DateRange> periods) {
    final bucket = row.data['bucket'];
    return switch (dimension) {
      GroupByNone() => const TotalKey(),
      GroupByMerchant() => MerchantKey(bucket as String?),
      GroupByPaymentMethod() => PaymentMethodKey(bucket as String?),
      GroupByHourOfDay() => HourOfDayKey(bucket! as int),
      // SQLite's %w is 0=Sunday; ISO is 1=Monday..7=Sunday.
      GroupByDayOfWeek() =>
        DayOfWeekKey(bucket! as int == 0 ? DateTime.sunday : bucket as int),
      GroupByCategory() =>
        CategoryKey(bucket! as String, row.data['bucket2']! as String),
      GroupByTag() => TagKey(bucket! as String, row.data['bucket2']! as String),
      GroupByReflection() => ReflectionKey(
          necessity: _levelOf(NecessityLevel.values, bucket),
          satisfaction: _levelOf(SatisfactionLevel.values, row.data['bucket2']),
        ),
      GroupByPeriod() => PeriodKey(periods[bucket! as int]),
      GroupByTagCrossCategory() => TagCategoryKey(
          tagId: bucket! as String,
          tagPath: row.data['bucket2']! as String,
          categoryId: row.data['bucket3']! as String,
          categoryPath: row.data['bucket4']! as String,
        ),
    };
  }

  static T? _levelOf<T extends Enum>(List<T> values, Object? raw) {
    if (raw == null) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw StateError('unknown stored value "$raw"');
  }

  /// The converter does not apply to an aggregate, so every number is wrapped
  /// by hand and none of them spends a moment as a double.
  static Money _moneyOf(Aggregate aggregate, QueryRow row) =>
      switch (aggregate) {
        Aggregate.sum => Money(row.data['total']! as int),
        // For a count, the answer is Bucket.count; money is zero by contract.
        Aggregate.count => Money.zero,
        Aggregate.min => Money((row.data['low'] as int?) ?? 0),
        Aggregate.max => Money((row.data['high'] as int?) ?? 0),
        Aggregate.average => _moneyFromAverage(row.data['mean'] as double?),
      };

  /// Rounds half away from zero, once, at the last step.
  ///
  /// `AVG` is the only place SQL hands back a double. Dart's `round()` already
  /// rounds half away from zero, which is stated here so nobody "fixes" it to
  /// banker's rounding and quietly shifts every average by a minor unit.
  static Money _moneyFromAverage(double? mean) =>
      mean == null ? Money.zero : Money(mean.round());
}
