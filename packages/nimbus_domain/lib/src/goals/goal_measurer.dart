import '../calendar/date_key.dart';
import 'goal_amount.dart';
import 'goal_metric.dart';
import 'goal_scope.dart';

/// The port a goal is measured through.
///
/// `nimbus_data` implements it over Phase 3's `AnalyticsEngine`, and that
/// implementation is the one place that switches on [GoalMetric]. Answers are
/// `MoneyAmount`s when `metric.isMoney`, `QuantityAmount`s otherwise.
abstract interface class GoalMeasurer {
  /// [metric] over [scope] across [range], as one amount.
  Future<GoalAmount> measure(
      GoalMetric metric, GoalScope scope, DateRange range);

  /// The same, one amount per day across [span]. Days with no data are
  /// absent from the map; `foldDaily` counts them as zero.
  Future<Map<DateKey, GoalAmount>> measureDaily(
      GoalMetric metric, GoalScope scope, DateRange span);
}
