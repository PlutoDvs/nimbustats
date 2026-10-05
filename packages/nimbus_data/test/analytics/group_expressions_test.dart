import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  const janFeb = DateRange(DateKey(20260101), DateKey(20260228));

  group("Phase 3's transaction fragments are unchanged", () {
    // Pinned as text: the alias refactor must not move a character of the SQL
    // that Phase 3's plan tests and device measurements were made on.
    test('hour of day', () {
      expect(GroupExpressions.forDimension(const GroupByHourOfDay()).selectSql,
          'CAST(((t.occurred_at_utc + t.tz_offset_minutes*60000)/3600000) '
          '% 24 AS INTEGER) AS bucket');
    });

    test('day of week', () {
      expect(GroupExpressions.forDimension(const GroupByDayOfWeek()).selectSql,
          "CAST(strftime('%w', (t.occurred_at_utc + t.tz_offset_minutes*60000)"
          "/1000, 'unixepoch') AS INTEGER) AS bucket");
    });

    test('period', () {
      final fragment = GroupExpressions.forDimension(
          const GroupByPeriod(PeriodType.month),
          span: janFeb,
          calendar: const GregorianCalendar());
      expect(
          fragment.selectSql,
          'CASE WHEN t.local_date_key BETWEEN ? AND ? THEN 0 '
          'WHEN t.local_date_key BETWEEN ? AND ? THEN 1 END AS bucket');
      expect(fragment.variables.map((v) => v.value),
          [20260101, 20260131, 20260201, 20260228]);
    });
  });

  group('tracker fragments read tracker_entries as te', () {
    test('hour and weekday share the transaction arithmetic', () {
      expect(
          GroupExpressions.forTrackerDimension(const TrackerGroupByHourOfDay())
              .selectSql,
          'CAST(((te.occurred_at_utc + te.tz_offset_minutes*60000)/3600000) '
          '% 24 AS INTEGER) AS bucket');
      expect(
          GroupExpressions.forTrackerDimension(const TrackerGroupByDayOfWeek())
              .selectSql,
          "CAST(strftime('%w', (te.occurred_at_utc + "
          "te.tz_offset_minutes*60000)/1000, 'unixepoch') AS INTEGER) "
          'AS bucket');
    });

    test('a period walks the same Dart-computed ladder', () {
      final fragment = GroupExpressions.forTrackerDimension(
          TrackerGroupByPeriod(PeriodType.month),
          span: janFeb,
          calendar: const GregorianCalendar());
      expect(
          fragment.selectSql,
          'CASE WHEN te.local_date_key BETWEEN ? AND ? THEN 0 '
          'WHEN te.local_date_key BETWEEN ? AND ? THEN 1 END AS bucket');
      expect(fragment.variables.map((v) => v.value),
          [20260101, 20260131, 20260201, 20260228]);
    });

    test('a period without a range is refused', () {
      expect(
          () => GroupExpressions.forTrackerDimension(
              TrackerGroupByPeriod(PeriodType.month),
              calendar: const GregorianCalendar()),
          throwsArgumentError);
    });

    test('day, tracker and none need no calendar', () {
      expect(
          GroupExpressions.forTrackerDimension(const TrackerGroupByDay())
              .selectSql,
          'te.local_date_key AS bucket');
      expect(
          GroupExpressions.forTrackerDimension(const TrackerGroupByTracker())
              .selectSql,
          'te.tracker_id AS bucket');
      expect(
          GroupExpressions.forTrackerDimension(const TrackerGroupByNone())
              .selectSql,
          '0 AS bucket');
    });

    test('every tracker fragment groups by its bucket and joins nothing', () {
      for (final dimension in <TrackerGroupBy>[
        const TrackerGroupByNone(),
        const TrackerGroupByTracker(),
        const TrackerGroupByDay(),
        TrackerGroupByPeriod(PeriodType.month),
        const TrackerGroupByHourOfDay(),
        const TrackerGroupByDayOfWeek(),
      ]) {
        final fragment = GroupExpressions.forTrackerDimension(dimension,
            span: janFeb, calendar: const GregorianCalendar());
        expect(fragment.groupSql, 'bucket', reason: '$dimension');
        expect(fragment.joinSql, isEmpty, reason: '$dimension');
      }
    });
  });
}
