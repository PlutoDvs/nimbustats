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

    // The true total counts each transaction once, so it is deliberately not
    // derived from the buckets -- on a tag dimension those overlap.
    final trueWhere = AnalyticsPredicates.whereClause(spec.filters);
    final trueRow = await _db.customSelect(
      'SELECT COALESCE(SUM(t.amount), 0) AS total, COUNT(*) AS n '
      'FROM transactions t WHERE ${trueWhere.sql}',
      variables: trueWhere.variables,
    ).getSingle();

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
