import 'package:meta/meta.dart';

import '../calendar/date_key.dart';
import 'goal_amount.dart';
import 'goal_status.dart';

/// What a fixed-range goal still needs per month to reach its target.
@immutable
final class RequiredRate {
  const RequiredRate(this.perMonth, this.monthsLeft);

  /// Never below zero. Money is rounded up: it is a minimum to set aside.
  final GoalAmount perMonth;

  /// Calendar months from today's to the range's last, both counted, in the
  /// goal's calendar.
  final int monthsLeft;

  @override
  bool operator ==(Object other) =>
      other is RequiredRate &&
      other.perMonth == perMonth &&
      other.monthsLeft == monthsLeft;

  @override
  int get hashCode => Object.hash(perMonth, monthsLeft);

  @override
  String toString() => 'RequiredRate($perMonth x $monthsLeft months)';
}

/// Where the period is heading. Information only: no status reads it.
@immutable
final class Projection {
  const Projection({required this.projectedEnd, this.requiredRate});

  /// The period's value at its end if the pace so far holds.
  final GoalAmount projectedEnd;

  /// For a fixed range while it is open; null otherwise.
  final RequiredRate? requiredRate;

  @override
  bool operator ==(Object other) =>
      other is Projection &&
      other.projectedEnd == projectedEnd &&
      other.requiredRate == requiredRate;

  @override
  int get hashCode => Object.hash(projectedEnd, requiredRate);

  @override
  String toString() => 'Projection(end $projectedEnd, $requiredRate)';
}

/// How a goal stands for one period: the answer `assess` gives.
@immutable
final class GoalProgress {
  const GoalProgress({
    required this.period,
    required this.current,
    required this.target,
    required this.status,
    required this.fractionOfTarget,
    required this.projection,
  });

  final DateRange period;
  final GoalAmount current;
  final GoalAmount target;
  final GoalStatus status;

  /// [current] / [target]: a ratio, so a double even for money. Negative for
  /// negative net savings; [double.infinity] once a zero target is passed.
  final double fractionOfTarget;

  final Projection projection;

  @override
  bool operator ==(Object other) =>
      other is GoalProgress &&
      other.period == period &&
      other.current == current &&
      other.target == target &&
      other.status == status &&
      other.fractionOfTarget == fractionOfTarget &&
      other.projection == projection;

  @override
  int get hashCode => Object.hash(
      period, current, target, status, fractionOfTarget, projection);

  @override
  String toString() =>
      'GoalProgress(${status.name}, $current of $target over $period, '
      '$projection)';
}
