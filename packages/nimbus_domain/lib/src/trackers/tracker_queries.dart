import '../analytics/aggregate.dart';
import '../calendar/calendar.dart';
import '../calendar/date_key.dart';
import 'tracker_group_by.dart';
import 'tracker_query_spec.dart';

/// The tracker questions the app asks, worded in one place.
///
/// Every screen that shows a tracker number asks through one of these, so the
/// tab, the snackbar and the detail screen cannot word one question two ways.
/// Two wordings would be two cache entries and two queries for one answer.
abstract final class TrackerQueries {
  /// One bucket per day of [range] that has entries: the week and month
  /// charts.
  static TrackerQuerySpec byDay(String trackerId, DateRange range) =>
      TrackerQuerySpec(
        trackerIds: [trackerId],
        dateRange: range,
        groupBy: const TrackerGroupByDay(),
        aggregate: Aggregate.sum,
      );

  /// One bucket per calendar month of [range] that has entries: the year
  /// chart. Months come from the engine's calendar, so a Jalali year shows
  /// Jalali months.
  static TrackerQuerySpec byMonth(String trackerId, DateRange range) =>
      TrackerQuerySpec(
        trackerIds: [trackerId],
        dateRange: range,
        groupBy: TrackerGroupByPeriod(PeriodType.month),
        aggregate: Aggregate.sum,
      );

  /// Each of [trackerIds]' totals on [day]: the tab. A tracker with nothing
  /// logged that day has no bucket.
  static TrackerQuerySpec dayTotals(List<String> trackerIds, DateKey day) =>
      TrackerQuerySpec(
        trackerIds: trackerIds,
        dateRange: DateRange(day, day),
        groupBy: const TrackerGroupByTracker(),
        aggregate: Aggregate.sum,
      );

  /// One tracker's total on [day]: the snackbar after a tap, and the detail
  /// header.
  static TrackerQuerySpec dayTotal(String trackerId, DateKey day) =>
      TrackerQuerySpec(
        trackerIds: [trackerId],
        dateRange: DateRange(day, day),
        groupBy: const TrackerGroupByNone(),
        aggregate: Aggregate.sum,
      );

  /// Every day [trackerId] was ever logged, one bucket each: the streaks'
  /// input. Undated on purpose, because the longest streak can be anywhere.
  static TrackerQuerySpec loggedDays(String trackerId) => TrackerQuerySpec(
        trackerIds: [trackerId],
        groupBy: const TrackerGroupByDay(),
        aggregate: Aggregate.count,
      );
}
