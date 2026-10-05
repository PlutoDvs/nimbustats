import '../analytics/aggregate.dart';
import '../calendar/date_key.dart';
import 'tracker_group_by.dart';
import 'tracker_query_spec.dart';

/// The tracker questions the app asks, worded in one place.
///
/// Every screen that shows a tracker number asks through one of these, so the
/// tab, the snackbar and the detail screen cannot word one question two ways.
/// Two wordings would be two cache entries and two queries for one answer.
abstract final class TrackerQueries {
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
