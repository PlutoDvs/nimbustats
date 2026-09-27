import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  const gregorian = GregorianCalendar();
  const jalali = JalaliCalendar();

  test('one month is the month containing the anchor', () {
    expect(
      ViewPeriod(PeriodType.month, 1).resolve(const DateKey(20260215), gregorian),
      DateRange(const DateKey(20260201), const DateKey(20260228)),
    );
  });

  test('six Gregorian months end with the anchor month and cross the year', () {
    expect(
      ViewPeriod(PeriodType.month, 6).resolve(const DateKey(20260215), gregorian),
      DateRange(const DateKey(20250901), const DateKey(20260228)),
    );
  });

  test('six Jalali months cross Nowruz in Jalali months, not Gregorian ones',
      () {
    // Anchored in Farvardin 1405, the window runs Aban 1404 .. Farvardin 1405.
    // Expected keys come from the calendar's own (separately tested)
    // conversion, so this asserts the window arithmetic, not the conversion.
    expect(
      ViewPeriod(PeriodType.month, 6).resolve(jalali.keyOf(1405, 1, 15), jalali),
      DateRange(jalali.keyOf(1404, 8, 1), jalali.keyOf(1405, 1, 31)),
    );
  });

  test('a week starts on the given first day', () {
    // 2026-09-27 is a Sunday.
    final week = ViewPeriod(PeriodType.week, 1);
    expect(
      week.resolve(const DateKey(20260927), gregorian,
          firstDayOfWeek: DateTime.saturday),
      DateRange(const DateKey(20260926), const DateKey(20261002)),
    );
    expect(
      week.resolve(const DateKey(20260927), gregorian,
          firstDayOfWeek: DateTime.monday),
      DateRange(const DateKey(20260921), const DateKey(20260927)),
    );
  });

  test('a count below one is a caller error', () {
    expect(() => ViewPeriod(PeriodType.month, 0), throwsArgumentError);
  });

  test('stored values parse, and bad ones are format errors', () {
    expect(ViewPeriod.fromStored('month', 6), ViewPeriod(PeriodType.month, 6));
    expect(() => ViewPeriod.fromStored('fortnight', 1),
        throwsA(isA<FormatException>()));
    // In stored data a zero count is corruption, not a caller's mistake.
    expect(() => ViewPeriod.fromStored('month', 0),
        throwsA(isA<FormatException>()));
  });

  test('periods compare by value', () {
    expect(ViewPeriod(PeriodType.month, 6), ViewPeriod(PeriodType.month, 6));
    expect(ViewPeriod(PeriodType.month, 6).hashCode,
        ViewPeriod(PeriodType.month, 6).hashCode);
    expect(ViewPeriod(PeriodType.month, 6),
        isNot(ViewPeriod(PeriodType.month, 1)));
  });
}
