import 'date_key.dart';

enum CalendarKind { gregorian, jalali }

enum PeriodType { day, week, month, quarter, year }

/// Year/month/day in a specific calendar system.
typedef CalendarParts = ({int year, int month, int day});

/// Every period calculation in the app goes through this interface.
///
/// "This month" is a different range in Jalali than in Gregorian, so goals,
/// budgets, and chart buckets must all be computed in the user's active
/// calendar rather than converted after the fact.
abstract interface class AppCalendar {
  CalendarKind get kind;

  /// Decomposes a Gregorian [DateKey] into this calendar's parts.
  CalendarParts partsOf(DateKey key);

  /// Builds a Gregorian [DateKey] from this calendar's parts.
  DateKey keyOf(int year, int month, int day);

  int monthLength(int year, int month);

  int monthsPerYear();

  DateRange periodContaining(
    DateKey key,
    PeriodType type, {
    int firstDayOfWeek,
  });

  DateRange shiftPeriod(DateRange range, PeriodType type, int delta);
}
