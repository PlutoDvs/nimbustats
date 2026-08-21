import 'package:shamsi_date/shamsi_date.dart';

import 'calendar.dart';
import 'date_key.dart';

/// The Jalali (Shamsi) calendar, the primary calendar for `fa` users.
///
/// Conversion goes through `shamsi_date`'s civil constructors rather than
/// `DateTime`: those convert via Julian day number, so the path is exact
/// integer arithmetic with no time zone in it. `test/calendar/
/// jalali_calendar_test.dart` pins that behaviour.
final class JalaliCalendar implements AppCalendar {
  const JalaliCalendar();

  @override
  CalendarKind get kind => CalendarKind.jalali;

  @override
  CalendarParts partsOf(DateKey key) {
    final j = Gregorian(key.year, key.month, key.day).toJalali();
    return (year: j.year, month: j.month, day: j.day);
  }

  @override
  DateKey keyOf(int year, int month, int day) {
    final g = Jalali(year, month, day).toGregorian();
    return DateKey.fromParts(g.year, g.month, g.day);
  }

  @override
  int monthsPerYear() => 12;

  @override
  int monthLength(int year, int month) {
    // Differenced from consecutive month starts rather than read off the
    // library's own helper, so it cannot disagree with the conversion the rest
    // of this class uses. A pin test asserts the two agree.
    final start = keyOf(year, month, 1);
    final nextStart =
        month == 12 ? keyOf(year + 1, 1, 1) : keyOf(year, month + 1, 1);
    return start.daysUntil(nextStart);
  }

  @override
  DateRange periodContaining(
    DateKey key,
    PeriodType type, {
    int firstDayOfWeek = DateTime.saturday,
  }) {
    final parts = partsOf(key);
    switch (type) {
      case PeriodType.day:
        return DateRange(key, key);
      case PeriodType.week:
        // DateKey.weekday is ISO (Mon=1..Sun=7). Jalali.weekDay is
        // Saturday-first and would be off by two here.
        final offset = (key.weekday - firstDayOfWeek + 7) % 7;
        final start = key.addDays(-offset);
        return DateRange(start, start.addDays(6));
      case PeriodType.month:
        return _monthRange(parts.year, parts.month);
      case PeriodType.quarter:
        final firstMonth = ((parts.month - 1) ~/ 3) * 3 + 1;
        final lastMonth = firstMonth + 2;
        return DateRange(
          keyOf(parts.year, firstMonth, 1),
          _monthRange(parts.year, lastMonth).endInclusive,
        );
      case PeriodType.year:
        return DateRange(
          keyOf(parts.year, 1, 1),
          _monthRange(parts.year, 12).endInclusive,
        );
    }
  }

  @override
  DateRange shiftPeriod(DateRange range, PeriodType type, int delta) {
    final start = range.startInclusive;
    switch (type) {
      case PeriodType.day:
        return periodContaining(start.addDays(delta), type);
      case PeriodType.week:
        // The range already starts on the caller's configured first day of
        // week, so realigning on that weekday preserves their configuration.
        return periodContaining(start.addDays(7 * delta), type,
            firstDayOfWeek: start.weekday);
      case PeriodType.month:
        return _shiftByMonths(start, delta, 1, PeriodType.month);
      case PeriodType.quarter:
        return _shiftByMonths(start, delta, 3, PeriodType.quarter);
      case PeriodType.year:
        final parts = partsOf(start);
        return periodContaining(
            keyOf(parts.year + delta, 1, 1), PeriodType.year);
    }
  }

  DateRange _monthRange(int year, int month) => DateRange(
        keyOf(year, month, 1),
        keyOf(year, month, monthLength(year, month)),
      );

  DateRange _shiftByMonths(
      DateKey start, int delta, int step, PeriodType type) {
    final parts = partsOf(start);
    final totalMonths = (parts.year * 12 + (parts.month - 1)) + delta * step;
    final year = totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    return periodContaining(keyOf(year, month, 1), type);
  }
}
