import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:test/test.dart';

void main() {
  group('library behaviour pins', () {
    // shamsi_date converts through julianDayNumber, so Gregorian <-> Jalali is
    // exact integer arithmetic with no DateTime and no time zone in the path.
    // These pins run before anything is built on the library.

    test('Nowruz 1403 is 2024-03-20, both directions', () {
      final g = Jalali(1403, 1, 1).toGregorian();
      expect((g.year, g.month, g.day), (2024, 3, 20));

      final j = Gregorian(2024, 3, 20).toJalali();
      expect((j.year, j.month, j.day), (1403, 1, 1));
    });

    test('conversion round-trips for a decade of dates', () {
      var key = DateKey.fromParts(2020, 1, 1);
      final end = DateKey.fromParts(2030, 1, 1);
      while (key < end) {
        final j = Gregorian(key.year, key.month, key.day).toJalali();
        final back = j.toGregorian();
        expect((back.year, back.month, back.day), (key.year, key.month, key.day),
            reason: 'round-trip of $key');
        key = key.addDays(1);
      }
    });

    test('monthLength agrees with differencing consecutive month starts', () {
      // JalaliCalendar derives month length by differencing rather than
      // calling monthLength, so that it cannot disagree with the conversion.
      // This pin fails loudly if the library's two code paths ever diverge.
      for (var y = 1395; y <= 1425; y++) {
        for (var m = 1; m <= 12; m++) {
          final start = Jalali(y, m, 1);
          final next = m == 12 ? Jalali(y + 1, 1, 1) : Jalali(y, m + 1, 1);
          expect(next.julianDayNumber - start.julianDayNumber, start.monthLength,
              reason: 'Jalali $y/$m');
        }
      }
    });

    test('Jalali weekDay is Saturday-first, not ISO', () {
      // 2026-08-20 is a Thursday (ISO 4). Jalali counts Saturday as 1, so the
      // same day is 6. Period code must use DateKey.weekday, which is ISO.
      final j = Gregorian(2026, 8, 20).toJalali();
      expect(j.weekDay, 6);
      expect(DateKey.fromParts(2026, 8, 20).weekday, DateTime.thursday);
    });
  });

  group('JalaliCalendar', () {
    const cal = JalaliCalendar();

    test('reports the Jalali parts of a Gregorian key', () {
      final parts = cal.partsOf(DateKey.fromParts(2024, 3, 20));
      expect(parts, (year: 1403, month: 1, day: 1));
    });

    test('builds a key from Jalali parts', () {
      expect(cal.keyOf(1403, 1, 1), DateKey.fromParts(2024, 3, 20));
    });

    test('first six months are 31 days, next five are 30', () {
      for (var m = 1; m <= 6; m++) {
        expect(cal.monthLength(1403, m), 31, reason: 'month $m');
      }
      for (var m = 7; m <= 11; m++) {
        expect(cal.monthLength(1403, m), 30, reason: 'month $m');
      }
    });

    test('Esfand is 29 or 30 days depending on the leap year', () {
      expect(cal.monthLength(1403, 12), anyOf(29, 30));
      final lengths = {
        for (var y = 1400; y <= 1410; y++) y: cal.monthLength(y, 12),
      };
      expect(lengths.values.toSet(), containsAll(<int>[29, 30]));
    });

    test('month period spans a whole Jalali month, not a Gregorian one', () {
      final range =
          cal.periodContaining(cal.keyOf(1403, 1, 15), PeriodType.month);
      expect(range.startInclusive, cal.keyOf(1403, 1, 1));
      expect(range.endInclusive, cal.keyOf(1403, 1, 31));
      expect(range.dayCount, 31);
    });

    test('year period spans the whole Jalali year', () {
      final range =
          cal.periodContaining(cal.keyOf(1403, 6, 10), PeriodType.year);
      expect(range.startInclusive, cal.keyOf(1403, 1, 1));
      expect(cal.partsOf(range.endInclusive).year, 1403);
      expect(cal.partsOf(range.endInclusive).month, 12);
      expect(range.dayCount, anyOf(365, 366));
    });

    test('week defaults to starting Saturday', () {
      final explicit = cal.periodContaining(
        DateKey.fromParts(2026, 8, 20),
        PeriodType.week,
        firstDayOfWeek: DateTime.saturday,
      );
      expect(explicit.startInclusive, DateKey.fromParts(2026, 8, 15));
      expect(explicit.dayCount, 7);

      // Omitting the argument must give the same week -- that is the default.
      final implicit =
          cal.periodContaining(DateKey.fromParts(2026, 8, 20), PeriodType.week);
      expect(implicit, explicit);
    });

    test('shifts a month period across the Jalali year boundary', () {
      final farvardin =
          cal.periodContaining(cal.keyOf(1403, 1, 10), PeriodType.month);
      final esfand = cal.shiftPeriod(farvardin, PeriodType.month, -1);
      expect(cal.partsOf(esfand.startInclusive), (year: 1402, month: 12, day: 1));
    });

    test('shifting a month keeps a full Jalali month, leap Esfand included', () {
      var range = cal.periodContaining(cal.keyOf(1402, 1, 1), PeriodType.month);
      for (var i = 0; i < 36; i++) {
        final parts = cal.partsOf(range.startInclusive);
        expect(parts.day, 1, reason: 'shift $i started mid-month');
        expect(range.dayCount, cal.monthLength(parts.year, parts.month),
            reason: 'shift $i length');
        range = cal.shiftPeriod(range, PeriodType.month, 1);
      }
    });

    test('quarters group three Jalali months', () {
      final range =
          cal.periodContaining(cal.keyOf(1403, 5, 2), PeriodType.quarter);
      expect(cal.partsOf(range.startInclusive).month, 4);
      expect(cal.partsOf(range.endInclusive).month, 6);
    });
  });
}
