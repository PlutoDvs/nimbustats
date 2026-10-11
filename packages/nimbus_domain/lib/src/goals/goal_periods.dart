import '../analytics/period_boundaries.dart';
import '../calendar/calendar.dart';
import '../calendar/date_key.dart';
import '../calendar/gregorian_calendar.dart';
import '../calendar/jalali_calendar.dart';
import 'goal.dart';
import 'goal_period.dart';

/// A goal's periods, in the goal's own calendar and week start.
///
/// Every range comes from [PeriodBoundaries]; there is no period arithmetic
/// here. The calendar is the goal's, not the app's, so switching the app to
/// Gregorian does not move a Jalali budget's month.
abstract final class GoalPeriods {
  /// The two-case switch, kept here so Phase 0's `calendar/` is not modified.
  static AppCalendar calendarFor(CalendarKind kind) => switch (kind) {
        CalendarKind.gregorian => const GregorianCalendar(),
        CalendarKind.jalali => const JalaliCalendar(),
      };

  /// The period containing [today]. A fixed range is its own period, before,
  /// during and after it.
  static DateRange current(Goal goal, DateKey today) => switch (goal.period) {
        RecurringPeriod(:final type) => PeriodBoundaries.forPeriod(
            type, today, calendarFor(goal.calendar),
            firstDayOfWeek: goal.weekStart),
        FixedRangePeriod(:final range) => range,
      };

  /// The closed periods, oldest first: from the one containing `since` up to,
  /// not including, the current one.
  ///
  /// Empty for a recurring goal that starts after [today], and always empty
  /// for a fixed range, which is one period with no history behind it.
  static List<DateRange> closed(Goal goal, DateKey today) =>
      switch (goal.period) {
        RecurringPeriod(:final type, :final since) when since <= today =>
          PeriodBoundaries.series(
              type, DateRange(since, today), calendarFor(goal.calendar),
              firstDayOfWeek: goal.weekStart)
            // The last period in the series contains today: the current one.
            ..removeLast(),
        _ => const <DateRange>[],
      };
}
