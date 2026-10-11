import '../calendar/date_key.dart';
import 'goal.dart';
import 'goal_assess.dart';
import 'goal_measurer.dart';
import 'goal_periods.dart';
import 'goal_progress.dart';

/// Measures a goal over a period and assesses the result: the brief's
/// `evaluate`, which the app calls now and Phase 6's background evaluation
/// calls later.
///
/// A service, not a value: it has no equality.
final class GoalEngine {
  /// [_today] is passed as `today:`.
  GoalEngine(this.measurer, {required this._today});

  final GoalMeasurer measurer;
  final DateKey Function() _today;

  /// The day goals are evaluated as of: the app's one clock.
  DateKey today() => _today();

  /// [goal]'s progress over [period], as of today.
  Future<GoalProgress> evaluate(Goal goal, DateRange period) =>
      _evaluate(goal, period, today());

  /// [goal]'s progress over its current period.
  ///
  /// Reads today once, before measuring, so a call that straddles midnight
  /// measures and assesses the same day's period.
  Future<GoalProgress> evaluateCurrent(Goal goal) {
    final day = today();
    return _evaluate(goal, GoalPeriods.current(goal, day), day);
  }

  Future<GoalProgress> _evaluate(
      Goal goal, DateRange period, DateKey day) async {
    final current = await measurer.measure(goal.metric, goal.scope, period);
    return assess(goal, period, current, day);
  }
}
