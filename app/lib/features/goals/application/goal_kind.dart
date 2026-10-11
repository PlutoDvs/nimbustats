import 'package:nimbus_domain/nimbus_domain.dart';

/// The four goals the editor offers.
///
/// They are never stored. Storage and evaluation know only a metric, a
/// direction and a period, so neither `nimbus_domain` nor `nimbus_data` can
/// branch on a kind (the brief's grep criterion, Task 6's test). The kind
/// lives here, where the editor chooses defaults by it and the card chooses
/// a bar or a run-rate.
enum GoalKind {
  spendingCap,
  habitLimit,
  habitGoal,
  savingsTarget;

  /// A cap and a limit are at most; a habit goal and savings, at least.
  GoalDirection get direction => switch (this) {
        GoalKind.spendingCap || GoalKind.habitLimit => GoalDirection.atMost,
        GoalKind.habitGoal || GoalKind.savingsTarget => GoalDirection.atLeast,
      };

  /// The period a new goal of this kind starts with, or null for a fixed
  /// date range (spec §5.3).
  PeriodType? get defaultPeriod => switch (this) {
        GoalKind.spendingCap => PeriodType.month,
        GoalKind.habitLimit => PeriodType.day,
        GoalKind.habitGoal => PeriodType.week,
        GoalKind.savingsTarget => null,
      };

  bool get isHabit => this == GoalKind.habitLimit || this == GoalKind.habitGoal;
}

/// [goal]'s kind, read off its metric family and direction. A `txnCount`
/// goal, which the editor does not offer (spec, Out of scope), reads as a
/// spending cap.
GoalKind kindOf(Goal goal) => switch (goal.metric) {
      GoalMetric.netSavings => GoalKind.savingsTarget,
      GoalMetric.trackerSum || GoalMetric.trackerCount =>
        goal.direction == GoalDirection.atMost
            ? GoalKind.habitLimit
            : GoalKind.habitGoal,
      GoalMetric.moneySum || GoalMetric.txnCount => GoalKind.spendingCap,
    };

/// A habit's metric, which its tracker's type decides, so the editor has no
/// metric picker (spec §5.3).
///
/// - Counters and booleans count entries: one tap, one cigarette; one
///   "done", one day.
/// - Quantities and durations sum them: litres, seconds.
GoalMetric habitMetricFor(TrackerType type) => switch (type) {
      TrackerType.counter || TrackerType.boolean => GoalMetric.trackerCount,
      TrackerType.quantity || TrackerType.duration => GoalMetric.trackerSum,
    };
