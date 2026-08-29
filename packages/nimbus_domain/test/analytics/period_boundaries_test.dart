import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  const jalali = JalaliCalendar();
  const gregorian = GregorianCalendar();

  group('forPeriod', () {
    test('a Gregorian month runs first to last', () {
      final range = PeriodBoundaries.forPeriod(
          PeriodType.month, const DateKey(20260815), gregorian);
      expect(range.startInclusive, const DateKey(20260801));
      expect(range.endInclusive, const DateKey(20260831));
    });

    test('a Jalali month is not a Gregorian month', () {
      // The whole reason period math never happens in SQL.
      final range = PeriodBoundaries.forPeriod(
          PeriodType.month, const DateKey(20260815), jalali);
      expect(range,
          isNot(DateRange(const DateKey(20260801), const DateKey(20260831))));
      final start = jalali.partsOf(range.startInclusive);
      final end = jalali.partsOf(range.endInclusive);
      expect(start.day, 1);
      expect(start.month, end.month,
          reason: 'a month range must not straddle two Jalali months');
      expect(end.day, jalali.monthLength(end.year, end.month));
    });

    test('a Jalali year boundary does not leak into the next year', () {
      // Esfand is month 12; the day after its last is 1 Farvardin.
      final esfand = jalali.keyOf(1404, 12, 15);
      final range =
          PeriodBoundaries.forPeriod(PeriodType.month, esfand, jalali);
      final start = jalali.partsOf(range.startInclusive);
      final end = jalali.partsOf(range.endInclusive);
      expect(start.year, 1404);
      expect(start.month, 12);
      expect(end.year, 1404);
      expect(end.month, 12);
    });

    test('a Jalali year runs Farvardin 1 to the last day of Esfand', () {
      final range = PeriodBoundaries.forPeriod(
          PeriodType.year, jalali.keyOf(1404, 6, 10), jalali);
      expect(jalali.partsOf(range.startInclusive).month, 1);
      expect(jalali.partsOf(range.startInclusive).day, 1);
      expect(jalali.partsOf(range.endInclusive).month, 12);
      expect(jalali.partsOf(range.endInclusive).year, 1404);
    });

    test('a day period is a single day', () {
      final range = PeriodBoundaries.forPeriod(
          PeriodType.day, const DateKey(20260815), gregorian);
      expect(range.startInclusive, const DateKey(20260815));
      expect(range.endInclusive, const DateKey(20260815));
      expect(range.dayCount, 1);
    });

    test('a week honours firstDayOfWeek', () {
      // Iran's week starts Saturday. Defaulting to Monday would shift every
      // weekly chart by two days and nobody would see it as a bug.
      final saturdayWeek = PeriodBoundaries.forPeriod(
          PeriodType.week, const DateKey(20260815), gregorian,
          firstDayOfWeek: DateTime.saturday);
      expect(saturdayWeek.startInclusive.weekday, DateTime.saturday);
      expect(saturdayWeek.dayCount, 7);

      final mondayWeek = PeriodBoundaries.forPeriod(
          PeriodType.week, const DateKey(20260815), gregorian,
          firstDayOfWeek: DateTime.monday);
      expect(mondayWeek.startInclusive.weekday, DateTime.monday);
      expect(mondayWeek, isNot(saturdayWeek));
    });

    test('the default first day of the week is Saturday', () {
      final explicit = PeriodBoundaries.forPeriod(
          PeriodType.week, const DateKey(20260815), gregorian,
          firstDayOfWeek: DateTime.saturday);
      final byDefault = PeriodBoundaries.forPeriod(
          PeriodType.week, const DateKey(20260815), gregorian);
      expect(byDefault, explicit);
    });

    test('a quarter covers three months in either calendar', () {
      for (final calendar in <AppCalendar>[gregorian, jalali]) {
        final range = PeriodBoundaries.forPeriod(
            PeriodType.quarter, const DateKey(20260815), calendar);
        expect(range.dayCount, greaterThan(80));
        expect(range.dayCount, lessThan(95),
            reason: 'a quarter in ${calendar.kind.name} was ${range.dayCount} '
                'days');
      }
    });
  });

  group('series', () {
    test('consecutive months tile the span without gaps or overlap', () {
      final span = DateRange(const DateKey(20260101), const DateKey(20260331));
      final periods =
          PeriodBoundaries.series(PeriodType.month, span, gregorian);
      expect(periods, hasLength(3));
      expect(periods.first.startInclusive, const DateKey(20260101));
      expect(periods.last.endInclusive, const DateKey(20260331));
      for (var i = 1; i < periods.length; i++) {
        expect(periods[i].startInclusive, periods[i - 1].endInclusive.addDays(1),
            reason: 'gap or overlap between period ${i - 1} and $i');
      }
    });

    test('a span shorter than one period yields exactly one period', () {
      final span = DateRange(const DateKey(20260810), const DateKey(20260812));
      final periods =
          PeriodBoundaries.series(PeriodType.month, span, gregorian);
      expect(periods, hasLength(1));
    });

    test('the series is oldest first', () {
      final span = DateRange(const DateKey(20260101), const DateKey(20260601));
      final periods =
          PeriodBoundaries.series(PeriodType.month, span, gregorian);
      for (var i = 1; i < periods.length; i++) {
        expect(periods[i].startInclusive.value,
            greaterThan(periods[i - 1].startInclusive.value));
      }
    });

    test('a Jalali series crosses the new year correctly', () {
      // Esfand 1404 into Farvardin 1405 -- the case that breaks naive
      // month-plus-one arithmetic.
      final span =
          DateRange(jalali.keyOf(1404, 12, 1), jalali.keyOf(1405, 1, 28));
      final periods = PeriodBoundaries.series(PeriodType.month, span, jalali);
      expect(periods, hasLength(2));
      expect(jalali.partsOf(periods.first.startInclusive).month, 12);
      expect(jalali.partsOf(periods.first.startInclusive).year, 1404);
      expect(jalali.partsOf(periods.last.startInclusive).month, 1);
      expect(jalali.partsOf(periods.last.startInclusive).year, 1405);
    });
  });
}
