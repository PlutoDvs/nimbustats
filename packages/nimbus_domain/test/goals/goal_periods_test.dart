import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

// Jalali dates below were computed with JalaliCalendar.keyOf, whose
// conversion test/calendar/jalali_calendar_test.dart pins:
//   Bahman 1404      = 2026-01-21 .. 2026-02-19 (30 days)
//   Esfand 1404      = 2026-02-20 .. 2026-03-20 (29 days: 1404 is not leap)
//   Farvardin 1405   = 2026-03-21 .. 2026-04-20 (31 days)
//   Mehr 1405        = 2026-09-23 .. 2026-10-22 (30 days)
//   29 Esfand 1404 (2026-03-20) is a Friday.

DateRange range(int start, int end) => DateRange(DateKey(start), DateKey(end));

void main() {
  /// A cap whose period, calendar and week start are the only things that
  /// vary here.
  Goal goal(
    GoalPeriod period, {
    CalendarKind calendar = CalendarKind.gregorian,
    int weekStart = DateTime.saturday,
  }) =>
      Goal(
        id: 'g1',
        name: 'Groceries',
        metric: GoalMetric.moneySum,
        scope: MoneyScope(const QueryFilters()),
        direction: GoalDirection.atMost,
        target: const MoneyAmount(Money(10000)),
        period: period,
        calendar: calendar,
        weekStart: weekStart,
      );
  RecurringPeriod monthly(int since) =>
      RecurringPeriod(PeriodType.month, DateKey(since));
  RecurringPeriod weekly(int since) =>
      RecurringPeriod(PeriodType.week, DateKey(since));

  test('calendarFor gives the calendar each kind names', () {
    for (final kind in CalendarKind.values) {
      expect(GoalPeriods.calendarFor(kind).kind, kind);
    }
  });

  group('current', () {
    test('a Jalali month turns over at Nowruz', () {
      final g = goal(monthly(20260101), calendar: CalendarKind.jalali);
      expect(GoalPeriods.current(g, const DateKey(20260320)),
          range(20260220, 20260320));
      expect(GoalPeriods.current(g, const DateKey(20260321)),
          range(20260321, 20260420));
    });

    test('a Gregorian month turns over at New Year', () {
      final g = goal(monthly(20260101));
      expect(GoalPeriods.current(g, const DateKey(20261231)),
          range(20261201, 20261231));
      expect(GoalPeriods.current(g, const DateKey(20270101)),
          range(20270101, 20270131));
    });

    test("the goal's own calendar decides its month", () {
      // Switching the app's calendar must not move a goal's period: the
      // calendar is the goal's field, read here, and nothing else is.
      expect(
          GoalPeriods.current(
              goal(monthly(20260101)), const DateKey(20261010)),
          range(20261001, 20261031));
      expect(
          GoalPeriods.current(
              goal(monthly(20260101), calendar: CalendarKind.jalali),
              const DateKey(20261010)),
          range(20260923, 20261022));
    });

    test('a Monday and a Saturday week start give different weeks', () {
      // 2026-12-31 is a Thursday; both weeks straddle the Gregorian new year.
      expect(
          GoalPeriods.current(
              goal(weekly(20261201), weekStart: DateTime.monday),
              const DateKey(20261231)),
          range(20261228, 20270103));
      expect(
          GoalPeriods.current(
              goal(weekly(20261201), weekStart: DateTime.saturday),
              const DateKey(20261231)),
          range(20261226, 20270101));
      // On 29 Esfand a Saturday week ends with the Jalali year; a Monday week
      // runs on into Farvardin.
      expect(
          GoalPeriods.current(
              goal(weekly(20260301),
                  calendar: CalendarKind.jalali, weekStart: DateTime.saturday),
              const DateKey(20260320)),
          range(20260314, 20260320));
      expect(
          GoalPeriods.current(
              goal(weekly(20260301),
                  calendar: CalendarKind.jalali, weekStart: DateTime.monday),
              const DateKey(20260320)),
          range(20260316, 20260322));
    });

    test('a fixed range is its own current period, whatever the day', () {
      final g = goal(FixedRangePeriod(range(20261101, 20270320)));
      for (final today in [20261010, 20261215, 20270401]) {
        expect(GoalPeriods.current(g, DateKey(today)),
            range(20261101, 20270320));
      }
    });
  });

  group('closed', () {
    test('Jalali months close in order across Nowruz', () {
      // Since 10 Bahman 1404; today is 5 Farvardin 1405.
      final g = goal(monthly(20260130), calendar: CalendarKind.jalali);
      expect(GoalPeriods.closed(g, const DateKey(20260325)),
          [range(20260121, 20260219), range(20260220, 20260320)]);
    });

    test('Gregorian months close in order across New Year', () {
      final g = goal(monthly(20261115));
      expect(GoalPeriods.closed(g, const DateKey(20270110)),
          [range(20261101, 20261130), range(20261201, 20261231)]);
    });

    test('the week start moves every closed week', () {
      // Since Sunday 2026-12-20; today is Saturday 2027-01-02.
      expect(
          GoalPeriods.closed(
              goal(weekly(20261220), weekStart: DateTime.monday),
              const DateKey(20270102)),
          [range(20261214, 20261220), range(20261221, 20261227)]);
      expect(
          GoalPeriods.closed(
              goal(weekly(20261220), weekStart: DateTime.saturday),
              const DateKey(20270102)),
          [range(20261219, 20261225), range(20261226, 20270101)]);
    });

    test('nothing has closed in the first period, or before the goal starts',
        () {
      final g = goal(monthly(20261015));
      expect(GoalPeriods.closed(g, const DateKey(20261031)), isEmpty);
      expect(GoalPeriods.closed(g, const DateKey(20261001)), isEmpty);
      expect(GoalPeriods.closed(g, const DateKey(20260901)), isEmpty);
    });

    test('a fixed range never has closed periods', () {
      // It is one period. Once it ends it is still the current one, closed.
      final g = goal(FixedRangePeriod(range(20261101, 20270320)));
      expect(GoalPeriods.closed(g, const DateKey(20270401)), isEmpty);
    });
  });
}
