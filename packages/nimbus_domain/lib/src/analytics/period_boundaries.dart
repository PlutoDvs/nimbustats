import '../calendar/calendar.dart';
import '../calendar/date_key.dart';

/// The one place a period becomes a key range.
///
/// [AppCalendar] already does the arithmetic; this type exists so the engine,
/// the trends screen and Phase 5's goal evaluation all enter through the same
/// door with the same week rule, rather than three callers reaching into the
/// calendar and disagreeing about which day a week starts on.
///
/// Period boundaries are computed here, in the active calendar, and converted
/// to `DateKey` integers before any SQL is generated. SQLite has no idea what
/// a Jalali month is, and `strftime` on `local_date_key` would silently answer
/// the Gregorian question instead.
abstract final class PeriodBoundaries {
  /// Iran's week starts on Saturday. Defaulting to Monday would shift every
  /// weekly chart by two days in a way that looks like data, not like a bug.
  static const defaultFirstDayOfWeek = DateTime.saturday;

  static DateRange forPeriod(
    PeriodType period,
    DateKey anchor,
    AppCalendar calendar, {
    int firstDayOfWeek = defaultFirstDayOfWeek,
  }) =>
      calendar.periodContaining(anchor, period, firstDayOfWeek: firstDayOfWeek);

  /// Consecutive periods covering [span], oldest first.
  ///
  /// The first period is the one containing `span.startInclusive`, so a span
  /// that begins mid-month yields a first bucket covering that whole month --
  /// which is what a trend chart wants, and why the caller supplies the span
  /// rather than a count.
  static List<DateRange> series(
    PeriodType period,
    DateRange span,
    AppCalendar calendar, {
    int firstDayOfWeek = defaultFirstDayOfWeek,
  }) {
    final periods = <DateRange>[];
    var current = forPeriod(period, span.startInclusive, calendar,
        firstDayOfWeek: firstDayOfWeek);

    while (current.startInclusive <= span.endInclusive) {
      periods.add(current);
      final next = calendar.shiftPeriod(current, period, 1);
      if (next.startInclusive <= current.startInclusive) {
        // shiftPeriod must move forward. Looping forever on a calendar bug
        // would hang the UI with no clue why.
        throw StateError('shiftPeriod did not advance past $current');
      }
      current = next;
    }
    return periods;
  }
}
