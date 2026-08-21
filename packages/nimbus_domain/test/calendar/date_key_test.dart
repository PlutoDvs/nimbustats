import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('DateKey', () {
    test('encodes and decodes yyyymmdd', () {
      final key = DateKey.fromParts(2026, 8, 20);
      expect(key.value, 20260820);
      expect((key.year, key.month, key.day), (2026, 8, 20));
    });

    test('round-trips through DateTime', () {
      final key = DateKey.fromParts(2026, 2, 28);
      expect(DateKey.fromDateTime(key.toDateTime()), key);
    });

    test('adds days across a month boundary', () {
      expect(DateKey.fromParts(2026, 1, 31).addDays(1),
          DateKey.fromParts(2026, 2, 1));
    });

    test('adds days across a leap day', () {
      expect(DateKey.fromParts(2024, 2, 28).addDays(1),
          DateKey.fromParts(2024, 2, 29));
      expect(DateKey.fromParts(2024, 2, 28).addDays(2),
          DateKey.fromParts(2024, 3, 1));
    });

    test('counts days between keys', () {
      expect(
          DateKey.fromParts(2026, 1, 1)
              .daysUntil(DateKey.fromParts(2026, 1, 31)),
          30);
    });

    test('counts backwards as a negative span', () {
      expect(
          DateKey.fromParts(2026, 1, 31)
              .daysUntil(DateKey.fromParts(2026, 1, 1)),
          -30);
    });

    test('spans a leap year exactly', () {
      expect(
          DateKey.fromParts(2024, 1, 1).daysUntil(DateKey.fromParts(2025, 1, 1)),
          366);
      expect(
          DateKey.fromParts(2025, 1, 1).daysUntil(DateKey.fromParts(2026, 1, 1)),
          365);
    });

    test('steps one day at a time across a decade', () {
      // Walks 2020-01-01 to 2030-01-01, leap years included. Also the only
      // guard against day arithmetic drifting back onto local time: on a host
      // that observes DST, a duration-based daysUntil truncates a 23-hour day
      // to zero and this test fails on that day.
      var key = DateKey.fromParts(2020, 1, 1);
      for (var i = 0; i < 3653; i++) {
        final next = key.addDays(1);
        expect(key.daysUntil(next), 1, reason: 'stepping from $key');
        key = next;
      }
      expect(key, DateKey.fromParts(2030, 1, 1));
    });

    test('sorts chronologically as integers', () {
      expect(
          DateKey.fromParts(2026, 1, 2)
              .compareTo(DateKey.fromParts(2026, 1, 10)),
          lessThan(0));
    });

    test('rejects impossible parts instead of encoding them', () {
      expect(() => DateKey.fromParts(2026, 13, 1), throwsA(isA<AssertionError>()));
      expect(() => DateKey.fromParts(2026, 1, 32), throwsA(isA<AssertionError>()));
      expect(() => DateKey.fromParts(2026, 0, 1), throwsA(isA<AssertionError>()));
    });
  });

  group('DateRange', () {
    test('contains its endpoints', () {
      final range =
          DateRange(DateKey.fromParts(2026, 8, 1), DateKey.fromParts(2026, 8, 31));
      expect(range.contains(DateKey.fromParts(2026, 8, 1)), isTrue);
      expect(range.contains(DateKey.fromParts(2026, 8, 31)), isTrue);
      expect(range.contains(DateKey.fromParts(2026, 9, 1)), isFalse);
      expect(range.dayCount, 31);
    });

    test('a single day is one day long', () {
      final day = DateKey.fromParts(2026, 8, 20);
      expect(DateRange(day, day).dayCount, 1);
    });
  });

  group('GregorianCalendar', () {
    const cal = GregorianCalendar();

    test('month lengths include February in a leap year', () {
      expect(cal.monthLength(2026, 2), 28);
      expect(cal.monthLength(2024, 2), 29);
      expect(cal.monthLength(2026, 8), 31);
    });

    test('month period spans the whole month', () {
      final range =
          cal.periodContaining(DateKey.fromParts(2026, 8, 20), PeriodType.month);
      expect(range.startInclusive, DateKey.fromParts(2026, 8, 1));
      expect(range.endInclusive, DateKey.fromParts(2026, 8, 31));
    });

    test('week period respects the configured first day', () {
      // 2026-08-20 is a Thursday. With Monday(1) as first day the week is 17..23.
      final monday = cal.periodContaining(
        DateKey.fromParts(2026, 8, 20),
        PeriodType.week,
        firstDayOfWeek: DateTime.monday,
      );
      expect(monday.startInclusive, DateKey.fromParts(2026, 8, 17));
      expect(monday.endInclusive, DateKey.fromParts(2026, 8, 23));

      // With Saturday(6) as first day the week is 15..21.
      final saturday = cal.periodContaining(
        DateKey.fromParts(2026, 8, 20),
        PeriodType.week,
        firstDayOfWeek: DateTime.saturday,
      );
      expect(saturday.startInclusive, DateKey.fromParts(2026, 8, 15));
      expect(saturday.endInclusive, DateKey.fromParts(2026, 8, 21));
    });

    test('quarter and year periods', () {
      final q = cal.periodContaining(
          DateKey.fromParts(2026, 8, 20), PeriodType.quarter);
      expect(q.startInclusive, DateKey.fromParts(2026, 7, 1));
      expect(q.endInclusive, DateKey.fromParts(2026, 9, 30));

      final y =
          cal.periodContaining(DateKey.fromParts(2026, 8, 20), PeriodType.year);
      expect(y.startInclusive, DateKey.fromParts(2026, 1, 1));
      expect(y.endInclusive, DateKey.fromParts(2026, 12, 31));
    });

    test('shifts a month period backwards across a year boundary', () {
      final jan =
          cal.periodContaining(DateKey.fromParts(2026, 1, 15), PeriodType.month);
      final dec = cal.shiftPeriod(jan, PeriodType.month, -1);
      expect(dec.startInclusive, DateKey.fromParts(2025, 12, 1));
      expect(dec.endInclusive, DateKey.fromParts(2025, 12, 31));
    });

    test('shifting a week keeps the configured first day', () {
      final saturdayWeek = cal.periodContaining(
        DateKey.fromParts(2026, 8, 20),
        PeriodType.week,
        firstDayOfWeek: DateTime.saturday,
      );
      final next = cal.shiftPeriod(saturdayWeek, PeriodType.week, 1);
      expect(next.startInclusive, DateKey.fromParts(2026, 8, 22));
      expect(next.endInclusive, DateKey.fromParts(2026, 8, 28));
    });
  });
}
