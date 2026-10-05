// drift exports a GroupBy of its own; this file means the domain's.
import 'package:drift/drift.dart' hide GroupBy;
import 'package:nimbus_domain/nimbus_domain.dart';

/// SQL fragments for one group-by dimension.
typedef GroupFragment = ({
  /// Columns added to the SELECT list, aliased so the engine can read them.
  String selectSql,

  /// The GROUP BY expression.
  String groupSql,

  /// Extra FROM/JOIN text, empty for most dimensions.
  String joinSql,
  List<Variable<Object>> variables,
});

abstract final class GroupExpressions {
  /// Builds the fragment for [dimension].
  ///
  /// [span] and [calendar] are required for period grouping and ignored
  /// otherwise: period boundaries are computed in Dart, never by SQL.
  static GroupFragment forDimension(
    GroupBy dimension, {
    DateRange? span,
    AppCalendar? calendar,
  }) =>
      switch (dimension) {
        GroupByNone() => (
            selectSql: '0 AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        GroupByMerchant() => (
            selectSql: 't.merchant AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        GroupByPaymentMethod() => (
            selectSql: 't.payment_method_id AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        GroupByReflection() => (
            selectSql: 't.necessity AS bucket, t.satisfaction AS bucket2',
            groupSql: 'bucket, bucket2',
            joinSql: '',
            variables: const [],
          ),
        GroupByHourOfDay() => (
            selectSql: '${hourOfDaySql('t')} AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        GroupByDayOfWeek() => (
            selectSql: '${dayOfWeekSql('t')} AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        GroupByCategory(:final depth) => _categoryFragment(depth),
        GroupByTag() => (
            selectSql: 'tg.id AS bucket, tg.path AS bucket2',
            groupSql: 'bucket, bucket2',
            joinSql: ' JOIN transaction_tags tt ON tt.transaction_id = t.id'
                ' JOIN tags tg ON tg.id = tt.tag_id AND tg.deleted_at IS NULL',
            variables: const [],
          ),
        GroupByPeriod(:final period) =>
          _periodFragment(period, span, calendar, alias: 't'),
        GroupByTagCrossCategory(:final depth) =>
          _tagCrossCategoryFragment(depth),
      };

  /// Builds the fragment for a tracker query's [dimension], against
  /// `tracker_entries` aliased as `te`.
  ///
  /// The dimensions trackers share with transactions -- hour, weekday,
  /// period -- come from the same expressions as [forDimension], so a
  /// tracker's hours and an expense's hours cannot be computed two ways.
  static GroupFragment forTrackerDimension(
    TrackerGroupBy dimension, {
    DateRange? span,
    AppCalendar? calendar,
  }) =>
      switch (dimension) {
        TrackerGroupByNone() => (
            selectSql: '0 AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        TrackerGroupByTracker() => (
            selectSql: 'te.tracker_id AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        // A local day is the same day in every calendar, so this needs
        // neither a range nor a calendar: only the key stamped at write time.
        TrackerGroupByDay() => (
            selectSql: 'te.local_date_key AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        TrackerGroupByPeriod(:final period) =>
          _periodFragment(period, span, calendar, alias: 'te'),
        TrackerGroupByHourOfDay() => (
            selectSql: '${hourOfDaySql('te')} AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        TrackerGroupByDayOfWeek() => (
            selectSql: '${dayOfWeekSql('te')} AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
      };

  /// A row's local hour, 0..23, from its UTC instant and the offset stamped
  /// on it: integer arithmetic on an absolute instant, no calendar involved.
  ///
  /// [alias] names the table: `t` for transactions, `te` for tracker entries.
  /// Both carry `occurred_at_utc` and `tz_offset_minutes`, so one expression
  /// serves both.
  static String hourOfDaySql(String alias) =>
      'CAST((($alias.occurred_at_utc + $alias.tz_offset_minutes*60000)'
      '/3600000) % 24 AS INTEGER)';

  /// A row's local weekday as SQLite's `%w` counts it, 0 = Sunday; the engine
  /// maps it to an ISO weekday.
  ///
  /// strftime is permitted here and nowhere else: the seven-day cycle is
  /// identical in both calendars, so no calendar decision is being made.
  static String dayOfWeekSql(String alias) => "CAST(strftime('%w', "
      '($alias.occurred_at_utc + $alias.tz_offset_minutes*60000)/1000, '
      "'unixepoch') AS INTEGER)";

  /// Groups on the ancestor category at [depth], not on the leaf.
  ///
  /// Without this the `depth` argument would be decorative: every query would
  /// bucket by leaf category and a caller asking for a top-level breakdown
  /// would silently get a fully-expanded one. That is the nested-rollup trap
  /// the phase brief names -- wrong numbers, no error.
  ///
  /// The ancestor is found by prefix match on the materialized path, which is
  /// exact for this format: paths are slash-terminated, so `a.path` is a
  /// prefix of `c.path` if and only if `a` is `c` or one of its ancestors.
  /// `min(c.depth, ?)` is what makes a category shallower than the requested
  /// depth bucket at its own depth instead of vanishing from the result.
  static GroupFragment _categoryFragment(int depth) => (
        selectSql: 'a.id AS bucket, a.path AS bucket2',
        groupSql: 'bucket, bucket2',
        joinSql: ' JOIN categories c ON c.id = t.category_id'
            ' JOIN categories a ON a.deleted_at IS NULL'
            ' AND a.depth = min(c.depth, ?)'
            ' AND substr(c.path, 1, length(a.path)) = a.path',
        variables: [Variable.withInt(depth)],
      );

  /// Tag x category in one statement.
  ///
  /// Both joins of the single-axis fragments, side by side: the tag join
  /// multiplies each transaction by its tags, and the ancestor self-join rolls
  /// the category up exactly as [_categoryFragment] does. The row
  /// multiplication is the intended behaviour here rather than a bug -- it is
  /// what a cross-tab is -- and it is why the caller must disclose that the
  /// cells do not reconcile with the total.
  ///
  /// Four aliases because each axis carries an id and a path: the id keys the
  /// cell and the path is what a drill-down needs to filter a subtree.
  static GroupFragment _tagCrossCategoryFragment(int depth) => (
        selectSql: 'tg.id AS bucket, tg.path AS bucket2, '
            'a.id AS bucket3, a.path AS bucket4',
        groupSql: 'bucket, bucket2, bucket3, bucket4',
        joinSql: ' JOIN transaction_tags tt ON tt.transaction_id = t.id'
            ' JOIN tags tg ON tg.id = tt.tag_id AND tg.deleted_at IS NULL'
            ' JOIN categories c ON c.id = t.category_id'
            ' JOIN categories a ON a.deleted_at IS NULL'
            ' AND a.depth = min(c.depth, ?)'
            ' AND substr(c.path, 1, length(a.path)) = a.path',
        variables: [Variable.withInt(depth)],
      );

  /// A CASE ladder over `local_date_key`, with every bound computed in Dart by
  /// [PeriodBoundaries] and passed as a variable.
  ///
  /// This is what keeps the "never do calendar math in SQL" rule: SQLite is
  /// only ever asked whether an integer falls between two other integers.
  static GroupFragment _periodFragment(
      PeriodType period, DateRange? span, AppCalendar? calendar,
      {required String alias}) {
    if (span == null || calendar == null) {
      throw ArgumentError('grouping by period needs a bounded date range: '
          'without one there is no finite set of periods to enumerate');
    }
    final periods = PeriodBoundaries.series(period, span, calendar);
    final buffer = StringBuffer('CASE');
    final variables = <Variable<Object>>[];
    for (var i = 0; i < periods.length; i++) {
      buffer.write(' WHEN $alias.local_date_key BETWEEN ? AND ? THEN $i');
      variables
        ..add(Variable.withInt(periods[i].startInclusive.value))
        ..add(Variable.withInt(periods[i].endInclusive.value));
    }
    buffer.write(' END AS bucket');
    return (
      selectSql: buffer.toString(),
      groupSql: 'bucket',
      joinSql: '',
      variables: variables,
    );
  }

  /// The period ranges a CASE index refers back to, so the engine can rebuild
  /// a `PeriodKey`. Must be called with the same arguments as [forDimension].
  static List<DateRange> periodsOf(
          PeriodType period, DateRange span, AppCalendar calendar) =>
      PeriodBoundaries.series(period, span, calendar);
}
