import 'package:nimbus_domain/nimbus_domain.dart';

/// A [GoalMeasurer] over a fixed day-by-day table, recording what it is
/// asked.
///
/// [measure] folds the same table [measureDaily] serves, so the two cannot
/// disagree the way two hand-written answers could.
final class FakeMeasurer implements GoalMeasurer {
  FakeMeasurer(this.daily, {this.failure});

  final Map<DateKey, GoalAmount> daily;

  /// Thrown by every call when set.
  final Exception? failure;

  /// Every [measure] call, in order.
  final measured = <({GoalMetric metric, GoalScope scope, DateRange range})>[];

  @override
  Future<GoalAmount> measure(
      GoalMetric metric, GoalScope scope, DateRange range) async {
    measured.add((metric: metric, scope: scope, range: range));
    final failure = this.failure;
    if (failure != null) throw failure;
    final zero = metric.isMoney
        ? const MoneyAmount(Money.zero)
        : const QuantityAmount(0);
    return foldDaily(daily, [range], zero).single;
  }

  @override
  Future<Map<DateKey, GoalAmount>> measureDaily(
      GoalMetric metric, GoalScope scope, DateRange span) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    return {
      for (final MapEntry(:key, :value) in daily.entries)
        if (span.contains(key)) key: value,
    };
  }
}
