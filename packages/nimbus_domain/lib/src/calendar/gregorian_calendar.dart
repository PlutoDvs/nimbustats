import 'calendar.dart';
import 'date_key.dart';

final class GregorianCalendar implements AppCalendar {
  const GregorianCalendar();

  @override
  CalendarKind get kind => CalendarKind.gregorian;

  @override
  CalendarParts partsOf(DateKey key) =>
      (year: key.year, month: key.month, day: key.day);

  @override
  DateKey keyOf(int year, int month, int day) =>
      DateKey.fromParts(year, month, day);

  @override
  int monthsPerYear() => 12;

  @override
  int monthLength(int year, int month) => DateTime.utc(year, month + 1, 0).day;

  @override
  DateRange periodContaining(
    DateKey key,
    PeriodType type, {
    int firstDayOfWeek = DateTime.monday,
  }) {
    switch (type) {
      case PeriodType.day:
        return DateRange(key, key);
      case PeriodType.week:
        final offset = (key.weekday - firstDayOfWeek + 7) % 7;
        final start = key.addDays(-offset);
        return DateRange(start, start.addDays(6));
      case PeriodType.month:
        return DateRange(
          DateKey.fromParts(key.year, key.month, 1),
          DateKey.fromParts(
              key.year, key.month, monthLength(key.year, key.month)),
        );
      case PeriodType.quarter:
        final firstMonth = ((key.month - 1) ~/ 3) * 3 + 1;
        final lastMonth = firstMonth + 2;
        return DateRange(
          DateKey.fromParts(key.year, firstMonth, 1),
          DateKey.fromParts(
              key.year, lastMonth, monthLength(key.year, lastMonth)),
        );
      case PeriodType.year:
        return DateRange(
          DateKey.fromParts(key.year, 1, 1),
          DateKey.fromParts(key.year, 12, 31),
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
        return periodContaining(
          DateKey.fromParts(start.year + delta, start.month, 1),
          PeriodType.year,
        );
    }
  }

  DateRange _shiftByMonths(
      DateKey start, int delta, int step, PeriodType type) {
    final totalMonths = (start.year * 12 + (start.month - 1)) + delta * step;
    final year = totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    return periodContaining(DateKey.fromParts(year, month, 1), type);
  }
}
