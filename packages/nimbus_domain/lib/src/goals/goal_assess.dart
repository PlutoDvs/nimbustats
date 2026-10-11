import '../analytics/period_boundaries.dart';
import '../calendar/calendar.dart';
import '../calendar/date_key.dart';
import 'goal.dart';
import 'goal_amount.dart';
import 'goal_direction.dart';
import 'goal_period.dart';
import 'goal_periods.dart';
import 'goal_progress.dart';
import 'goal_status.dart';

/// How [goal] stands for [period], given [current] measured over it, as of
/// [today]. Pure: the same inputs always give the same progress.
///
/// A goal made mid-period counts the whole period: a cap made on the 15th
/// shows what was already spent this month, because the month is what the
/// budget covers. [period] is used as given; nothing here trims it.
GoalProgress assess(
    Goal goal, DateRange period, GoalAmount current, DateKey today) {
  final position = _positionOf(goal, period, today);
  final fraction = current.ratioTo(goal.target);
  return GoalProgress(
    period: period,
    current: current,
    target: goal.target,
    status: _status(
      goal.direction,
      position,
      settled: _settled(goal.direction, current, goal.target),
      warned: _warned(goal, period, current, fraction, today),
    ),
    fractionOfTarget: fraction,
    projection: Projection(
      projectedEnd: _projectedEnd(position, period, current, today),
      requiredRate: _requiredRate(goal, position, period, current, today),
    ),
  );
}

/// `current / daysElapsedIncludingToday x daysInPeriod` while open. Nothing is
/// projected before the goal starts, and a closed period ends where it ended.
GoalAmount _projectedEnd(_Position position, DateRange period,
        GoalAmount current, DateKey today) =>
    switch (position) {
      _Position.notStarted => current.zero,
      _Position.open => current.scaledBy(
          period.dayCount, period.startInclusive.daysUntil(today) + 1),
      _Position.closed => current,
    };

/// What an open fixed range still needs each month, counting today's month
/// and the range's last in the goal's own calendar: Esfand to Ordibehesht is
/// three Jalali months but two Gregorian ones.
RequiredRate? _requiredRate(Goal goal, _Position position, DateRange period,
    GoalAmount current, DateKey today) {
  if (goal.period is! FixedRangePeriod || position != _Position.open) {
    return null;
  }
  final monthsLeft = PeriodBoundaries.series(
          PeriodType.month,
          DateRange(today, period.endInclusive),
          GoalPeriods.calendarFor(goal.calendar))
      .length;
  final perMonth = (goal.target - current).dividedUp(monthsLeft);
  return RequiredRate(
      perMonth.isNegative ? perMonth.zero : perMonth, monthsLeft);
}

enum _Position { notStarted, open, closed }

_Position _positionOf(Goal goal, DateRange period, DateKey today) {
  final since = goal.period.startDate;
  final starts =
      since > period.startInclusive ? since : period.startInclusive;
  if (today < starts) return _Position.notStarted;
  if (today > period.endInclusive) return _Position.closed;
  return _Position.open;
}

/// The one status rule, for both directions (spec §2's table).
///
/// [settled] is the event that decides a period before it ends: going over a
/// cap, reaching a goal. [warned] is an open period's warning sign. Each
/// direction names its own words for those outcomes and nothing else.
GoalStatus _status(
  GoalDirection direction,
  _Position position, {
  required bool settled,
  required bool warned,
}) {
  if (position == _Position.notStarted) return GoalStatus.notStarted;
  if (settled) {
    return switch (direction) {
      GoalDirection.atMost => GoalStatus.exceeded,
      GoalDirection.atLeast => GoalStatus.met,
    };
  }
  if (position == _Position.closed) {
    return switch (direction) {
      GoalDirection.atMost => GoalStatus.met,
      GoalDirection.atLeast => GoalStatus.missed,
    };
  }
  return warned ? GoalStatus.atRisk : GoalStatus.onTrack;
}

/// A cap is settled by going over it; a goal by reaching it. Exactly at a
/// cap is still within it.
bool _settled(GoalDirection direction, GoalAmount current, GoalAmount target) {
  // Both read the amount's own tolerance, the one the alert uses.
  return switch (direction) {
    GoalDirection.atMost => current.exceeds(target),
    GoalDirection.atLeast => current.reaches(target, 100),
  };
}

/// A cap warns once it reaches its lowest alert percent. It reads the
/// amount, never the pace: rent paid on day one would otherwise project past
/// the cap and hold the month at risk all month.
///
/// A goal warns when behind pace: `current < target x fullDaysElapsed /
/// daysInPeriod`, counting only days before today, so day one with nothing
/// yet is on track. Compared as fractions of the target: a ratio, not money.
bool _warned(Goal goal, DateRange period, GoalAmount current, double fraction,
        DateKey today) =>
    switch (goal.direction) {
      GoalDirection.atMost =>
        current.reaches(goal.target, goal.alertPercents.first),
      GoalDirection.atLeast =>
        fraction < period.startInclusive.daysUntil(today) / period.dayCount,
    };
