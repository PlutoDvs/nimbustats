import '../calendar/calendar.dart';
import '../calendar/date_key.dart';
import '../calendar/gregorian_calendar.dart';
import '../calendar/jalali_calendar.dart';

/// Turns a captured date-like run into a [DateKey].
///
/// The year decides the calendar, not the user's active setting: no Jalali
/// year is 2026 and no Gregorian year is 1403, so trusting the active
/// calendar for an unambiguous year would place the transaction six centuries
/// away. Anything genuinely ambiguous — a two-digit year, a two-part date —
/// throws, and the matcher falls back to the message's receipt date, which is
/// right far more often than a guess.
abstract final class DateParser {
  static const _gregorian = GregorianCalendar();
  static const _jalali = JalaliCalendar();

  static final _separator = RegExp(r'[/-]');

  static DateKey parse(String captured, {required AppCalendar calendar}) {
    final parts = captured.trim().split(_separator);
    if (parts.length != 3) {
      throw FormatException('expected three date components', captured);
    }

    final numbers = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null) throw FormatException('not a date', captured);
      numbers.add(value);
    }

    final int year;
    final int month;
    final int day;
    if (parts.first.length == 4) {
      year = numbers[0];
      month = numbers[1];
      day = numbers[2];
    } else if (parts.last.length == 4) {
      day = numbers[0];
      month = numbers[1];
      year = numbers[2];
    } else {
      throw FormatException('no four-digit year to anchor the date', captured);
    }

    if (month < 1 || month > 12 || day < 1 || day > 31) {
      throw FormatException('date component out of range', captured);
    }

    return _calendarFor(year, calendar).keyOf(year, month, day);
  }

  static AppCalendar _calendarFor(int year, AppCalendar active) {
    if (year >= 1900 && year <= 2200) return _gregorian;
    if (year >= 1200 && year <= 1500) return _jalali;
    return active;
  }
}
