import 'package:meta/meta.dart';

import '../calendar/date_key.dart';
import 'goal.dart';
import 'goal_amount.dart';
import 'goal_direction.dart';
import 'goal_progress.dart';

/// A goal crossed one of its alert percents. Data only: the app words it.
@immutable
final class GoalAlert {
  const GoalAlert({
    required this.goalId,
    required this.goalName,
    required this.period,
    required this.percent,
    required this.direction,
    required this.progress,
  });

  final String goalId;
  final String goalName;
  final DateRange period;
  final int percent;
  final GoalDirection direction;
  final GoalProgress progress;

  @override
  bool operator ==(Object other) =>
      other is GoalAlert &&
      other.goalId == goalId &&
      other.goalName == goalName &&
      other.period == period &&
      other.percent == percent &&
      other.direction == direction &&
      other.progress == progress;

  @override
  int get hashCode =>
      Object.hash(goalId, goalName, period, percent, direction, progress);

  @override
  String toString() =>
      'GoalAlert($goalId, $percent% ${direction.name}, $period)';
}

/// What `crossing` decided: the alert to show, if any, and the period's new
/// alert state to store.
@immutable
final class CrossingResult {
  const CrossingResult(this.alert, this.lastAlerted);

  final GoalAlert? alert;
  final int? lastAlerted;

  @override
  bool operator ==(Object other) =>
      other is CrossingResult &&
      other.alert == alert &&
      other.lastAlerted == lastAlerted;

  @override
  int get hashCode => Object.hash(alert, lastAlerted);

  @override
  String toString() => 'CrossingResult($alert, last $lastAlerted)';
}

/// The highest of [goal]'s alert percents that [current] reaches against its
/// target, or null below them all. Decided only through `GoalAmount.reaches`:
/// money compares exactly, quantities with its relative tolerance, and a zero
/// target is reached, at every percent, by anything above zero.
int? reachedPercent(Goal goal, GoalAmount current) {
  for (final percent in goal.alertPercents.reversed) {
    if (current.reaches(goal.target, percent)) return percent;
  }
  return null;
}

/// Whether [progress] crosses a new alert percent, given the period's
/// [lastAlerted] state (null: nothing recorded).
///
/// - Reached above the state: one alert, for the highest percent reached. A
///   jump from 70% to 105% alerts once, at 100.
/// - Otherwise no alert, and the state follows what is reached: the same
///   level leaves it as it was, so recomputation never re-fires, and a drop
///   lowers it, so a genuine re-crossing warns again.
CrossingResult crossing(Goal goal, GoalProgress progress, int? lastAlerted) {
  final reached = reachedPercent(goal, progress.current);
  if (reached == null || (lastAlerted != null && reached <= lastAlerted)) {
    return CrossingResult(null, reached);
  }
  return CrossingResult(
    GoalAlert(
      goalId: goal.id,
      goalName: goal.name,
      period: progress.period,
      percent: reached,
      direction: goal.direction,
      progress: progress,
    ),
    reached,
  );
}
