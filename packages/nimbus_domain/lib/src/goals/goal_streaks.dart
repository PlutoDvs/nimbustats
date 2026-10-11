import 'package:meta/meta.dart';

import '../calendar/date_key.dart';
import 'goal_amount.dart';
import 'goal_status.dart';

/// How one closed period ended: its value and the status `assess` gave it.
@immutable
final class PeriodOutcome {
  const PeriodOutcome(this.period, this.value, this.status);

  final DateRange period;
  final GoalAmount value;
  final GoalStatus status;

  @override
  bool operator ==(Object other) =>
      other is PeriodOutcome &&
      other.period == period &&
      other.value == value &&
      other.status == status;

  @override
  int get hashCode => Object.hash(period, value, status);

  @override
  String toString() => 'PeriodOutcome($period, $value, ${status.name})';
}

/// Runs of `met` periods in a recurring goal's history.
@immutable
final class GoalStreaks {
  const GoalStreaks({required this.current, required this.best});

  /// Reads [outcomes]: closed periods only, oldest first. [current] is the
  /// run of `met` ending at the most recent one; [best] the longest anywhere,
  /// so never less than [current].
  factory GoalStreaks.of(List<PeriodOutcome> outcomes) {
    var run = 0;
    var best = 0;
    for (final outcome in outcomes) {
      run = outcome.status == GoalStatus.met ? run + 1 : 0;
      if (run > best) best = run;
    }
    return GoalStreaks(current: run, best: best);
  }

  static const none = GoalStreaks(current: 0, best: 0);

  final int current;
  final int best;

  @override
  bool operator ==(Object other) =>
      other is GoalStreaks && other.current == current && other.best == best;

  @override
  int get hashCode => Object.hash(current, best);

  @override
  String toString() => 'GoalStreaks(current $current, best $best)';
}
