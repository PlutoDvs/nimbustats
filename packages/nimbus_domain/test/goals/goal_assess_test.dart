import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

MoneyAmount rials(int minor) => MoneyAmount(Money(minor));
QuantityAmount count(double n) => QuantityAmount(n);
DateRange range(int start, int end) => DateRange(DateKey(start), DateKey(end));

/// A cap of 10 000 a month: atMost, money.
Goal cap({
  int since = 20260101,
  List<int> alertPercents = Goal.defaultAlertPercents,
  GoalAmount? target,
}) =>
    Goal(
      id: 'cap',
      name: 'Dining out',
      metric: GoalMetric.moneySum,
      scope: MoneyScope(const QueryFilters(direction: MoneyDirection.expense)),
      direction: GoalDirection.atMost,
      target: target ?? rials(10000),
      period: RecurringPeriod(PeriodType.month, DateKey(since)),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.saturday,
      alertPercents: alertPercents,
    );

/// Seven sessions a week, so the pace is one a day: atLeast, a quantity.
Goal reading({int since = 20260101}) => Goal(
      id: 'reading',
      name: 'Reading',
      metric: GoalMetric.trackerCount,
      scope: TrackerScope('reading'),
      direction: GoalDirection.atLeast,
      target: count(7),
      period: RecurringPeriod(PeriodType.week, DateKey(since)),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.saturday,
    );

/// Save 1 000 000 between two dates: atLeast, money, may go negative.
Goal savings(DateRange between) => Goal(
      id: 'savings',
      name: 'Laptop',
      metric: GoalMetric.netSavings,
      scope: MoneyScope(const QueryFilters()),
      direction: GoalDirection.atLeast,
      target: rials(1000000),
      period: FixedRangePeriod(between),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.saturday,
    );

GoalStatus statusOf(
        Goal goal, DateRange period, GoalAmount current, int today) =>
    assess(goal, period, current, DateKey(today)).status;

void main() {
  final october = range(20261001, 20261031);
  // Saturday 2026-10-10 to Friday 2026-10-16.
  final week = range(20261010, 20261016);

  group('atMost', () {
    test('below the lowest alert percent while open is on track', () {
      final progress =
          assess(cap(), october, rials(7999), const DateKey(20261010));
      expect(progress.status, GoalStatus.onTrack);
      expect(progress.period, october);
      expect(progress.current, rials(7999));
      expect(progress.target, rials(10000));
      expect(progress.fractionOfTarget, 0.7999);
    });

    test('at the lowest alert percent while open is at risk', () {
      expect(
          statusOf(cap(), october, rials(8000), 20261010), GoalStatus.atRisk);
    });

    test('exactly at the cap is within it: at risk while open, met once closed',
        () {
      expect(statusOf(cap(), october, rials(10000), 20261010),
          GoalStatus.atRisk);
      expect(statusOf(cap(), october, rials(10000), 20261101), GoalStatus.met);
    });

    test('over the cap is exceeded, open or closed', () {
      expect(statusOf(cap(), october, rials(10001), 20261010),
          GoalStatus.exceeded);
      expect(statusOf(cap(), october, rials(10001), 20261105),
          GoalStatus.exceeded);
    });

    test('a closed period within the cap is met', () {
      expect(statusOf(cap(), october, rials(9000), 20261101), GoalStatus.met);
    });

    test('the status reads the amount, never the pace', () {
      // Half the cap on day one projects far past it. Rent paid on the first
      // would otherwise hold the month at risk all month.
      expect(statusOf(cap(), october, rials(5000), 20261001),
          GoalStatus.onTrack);
    });

    test('the lowest alert percent sets the warning line', () {
      final early = cap(alertPercents: [50, 100]);
      expect(statusOf(early, october, rials(4999), 20261010),
          GoalStatus.onTrack);
      expect(
          statusOf(early, october, rials(5000), 20261010), GoalStatus.atRisk);
    });

    test('a zero target: nothing is fine, anything at all is exceeded', () {
      // "Zero cigarettes today" -- no division by zero anywhere.
      final none = Goal(
        id: 'cig',
        name: 'Cigarettes',
        metric: GoalMetric.trackerCount,
        scope: TrackerScope('cig'),
        direction: GoalDirection.atMost,
        target: count(0),
        period: const RecurringPeriod(PeriodType.day, DateKey(20260101)),
        calendar: CalendarKind.gregorian,
        weekStart: DateTime.saturday,
      );
      final today = range(20261010, 20261010);
      final clean = assess(none, today, count(0), const DateKey(20261010));
      expect(clean.status, GoalStatus.onTrack);
      expect(clean.fractionOfTarget, 0);
      expect(statusOf(none, today, count(0), 20261011), GoalStatus.met);
      final one = assess(none, today, count(1), const DateKey(20261010));
      expect(one.status, GoalStatus.exceeded);
      expect(one.fractionOfTarget, double.infinity);
    });
  });

  group('atLeast', () {
    test('day one with nothing yet is on track', () {
      // No full day has passed, so no pace has been missed.
      expect(statusOf(reading(), week, count(0), 20261010), GoalStatus.onTrack);
    });

    test('behind pace is at risk; exactly on pace is on track', () {
      // Tuesday: three full days (Sat, Sun, Mon) are behind us, so the pace
      // is 7 x 3 / 7 = 3 sessions.
      expect(statusOf(reading(), week, count(2), 20261013), GoalStatus.atRisk);
      expect(statusOf(reading(), week, count(3), 20261013), GoalStatus.onTrack);
    });

    test('reaching the target is met, before or after the period ends', () {
      expect(statusOf(reading(), week, count(7), 20261013), GoalStatus.met);
      expect(statusOf(reading(), week, count(8), 20261020), GoalStatus.met);
      // Over the target while the period is still open, and exactly at it
      // once closed (spec section 6 grid cells).
      expect(statusOf(reading(), week, count(9), 20261013), GoalStatus.met);
      expect(statusOf(reading(), week, count(7), 20261017), GoalStatus.met);
    });

    test('a closed period short of the target is missed, not exceeded', () {
      // "Exceeded" is a cap's failure. A minimum that fell short was missed.
      expect(statusOf(reading(), week, count(6), 20261017), GoalStatus.missed);
    });
  });

  group('quantity tolerance', () {
    // Summed in Dart on purpose. Logged in this order the litres add up to
    // 0.9999999999999999 (0.7 + 0.1 + 0.2 happens to give exactly 1.0).
    final litre = QuantityAmount(0.2 + 0.7 + 0.1);
    Goal water(GoalDirection direction, double target, PeriodType type) => Goal(
          id: 'water',
          name: 'Water',
          metric: GoalMetric.trackerSum,
          scope: TrackerScope('water'),
          direction: direction,
          target: count(target),
          period: RecurringPeriod(type, const DateKey(20260101)),
          calendar: CalendarKind.gregorian,
          weekStart: DateTime.saturday,
        );

    test('0.2 + 0.7 + 0.1 of a 1 L atLeast goal is met, as the alert says',
        () {
      expect(litre.value, isNot(1.0));
      final goal = water(GoalDirection.atLeast, 1, PeriodType.day);
      final day = range(20261010, 20261010);
      expect(litre.reaches(goal.target, 100), isTrue);
      expect(assess(goal, day, litre, const DateKey(20261011)).status,
          GoalStatus.met);
      expect(assess(goal, day, litre, const DateKey(20261010)).status,
          GoalStatus.met);
    });

    test('0.1 + 0.2 against a 0.3 L atMost limit is not exceeded', () {
      final goal = water(GoalDirection.atMost, 0.3, PeriodType.day);
      final day = range(20261010, 20261010);
      final sum = QuantityAmount(0.1 + 0.2);
      expect(sum.value, isNot(0.3));
      expect(assess(goal, day, sum, const DateKey(20261010)).status,
          GoalStatus.atRisk);
      expect(assess(goal, day, sum, const DateKey(20261011)).status,
          GoalStatus.met);
    });
  });

  group('both directions', () {
    test('nothing has started before the period or the goal begins', () {
      final laptop = savings(range(20261101, 20270331));
      expect(statusOf(laptop, range(20261101, 20270331), rials(0), 20261010),
          GoalStatus.notStarted);
      // A cap starting on the 20th has not started on the 15th, although its
      // month has.
      final late = cap(since: 20261020);
      expect(statusOf(late, october, rials(9000), 20261015),
          GoalStatus.notStarted);
      expect(statusOf(late, october, rials(9000), 20261020), GoalStatus.atRisk);
      // Not started wins over any amount, even one at or over the cap.
      expect(statusOf(late, october, rials(10000), 20261015),
          GoalStatus.notStarted);
      expect(statusOf(late, october, rials(12000), 20261015),
          GoalStatus.notStarted);
    });

    test('a goal made mid-period counts the whole period', () {
      // A cap made on the 15th covers the month, so what was spent on the
      // 3rd counts: the month is what the budget covers.
      final made15th = cap(since: 20261015);
      const today = DateKey(20261015);
      final period = GoalPeriods.current(made15th, today);
      expect(period, october);
      expect(assess(made15th, period, rials(9000), today).status,
          GoalStatus.atRisk);
      // The pace counts from the period's start too: a weekly goal made on a
      // Tuesday with nothing logged is already three sessions behind.
      expect(statusOf(reading(since: 20261013), week, count(0), 20261013),
          GoalStatus.atRisk);
    });

    test('an empty period is zero, and the table still applies', () {
      expect(statusOf(cap(), october, rials(0), 20261101), GoalStatus.met);
      expect(statusOf(reading(), week, count(0), 20261017), GoalStatus.missed);
    });

    test('negative net savings follows the same rules', () {
      final laptop = savings(october);
      final progress =
          assess(laptop, october, rials(-200000), const DateKey(20261010));
      expect(progress.status, GoalStatus.atRisk);
      expect(progress.fractionOfTarget, -0.2);
      expect(statusOf(laptop, october, rials(-200000), 20261101),
          GoalStatus.missed);
    });
  });

  group('projection', () {
    GoalAmount projectedEnd(
            Goal goal, DateRange period, GoalAmount current, int today) =>
        assess(goal, period, current, DateKey(today)).projection.projectedEnd;
    RequiredRate? requiredRate(
            Goal goal, DateRange period, GoalAmount current, int today) =>
        assess(goal, period, current, DateKey(today)).projection.requiredRate;

    test('an open period projects its pace to the end', () {
      // Ten days of October, today included, at 1 000 a day: 31 000.
      expect(
          assess(cap(), october, rials(10000), const DateKey(20261010))
              .projection,
          Projection(projectedEnd: rials(31000)));
    });

    test('a money projection rounds half away from zero', () {
      // Two days into a seven-day range: 5 x 7 / 2 = 17.5, and -17.5.
      final thisWeek = savings(week);
      expect(projectedEnd(thisWeek, week, rials(5), 20261011), rials(18));
      expect(projectedEnd(thisWeek, week, rials(-5), 20261011), rials(-18));
    });

    test('a quantity projection is not rounded', () {
      // 2.5 sessions in two days of a seven-day week.
      expect(projectedEnd(reading(), week, count(2.5), 20261011), count(8.75));
    });

    test('not started projects zero; closed projects what happened', () {
      // The cap starting on the 20th has 9 000 in its month already, but has
      // not started: nothing is projected from before it began.
      expect(projectedEnd(cap(since: 20261020), october, rials(9000), 20261015),
          rials(0));
      expect(projectedEnd(cap(), october, rials(9000), 20261101), rials(9000));
    });

    test('a projection past the cap does not change the status', () {
      // Information only: 5 000 on day one projects to 155 000.
      final progress =
          assess(cap(), october, rials(5000), const DateKey(20261001));
      expect(progress.projection.projectedEnd, rials(155000));
      expect(progress.status, GoalStatus.onTrack);
    });

    test('months left count the current one, across New Year', () {
      // 15 December 2026 to 28 February 2027 touches three Gregorian months.
      // 1 000 000 / 3 rounds up: a minimum to set aside.
      final between = range(20261101, 20270228);
      final laptop = savings(between);
      expect(requiredRate(laptop, between, rials(0), 20261215),
          RequiredRate(rials(333334), 3));
      // On the last day, what is left is due this month.
      expect(requiredRate(laptop, between, rials(400000), 20270228),
          RequiredRate(rials(600000), 1));
    });

    test("months left are counted in the goal's calendar", () {
      // 1 Dey 1404 (2025-12-22) to 10 Ordibehesht 1405 (2026-04-30), seen on
      // 25 Esfand 1404 (2026-03-16): Esfand, Farvardin and Ordibehesht are
      // three Jalali months, but the same days touch only March and April.
      final between = range(20251222, 20260430);
      final gregorian = savings(between);
      final jalali = gregorian.copyWith(calendar: CalendarKind.jalali);
      expect(requiredRate(jalali, between, rials(100000), 20260316),
          RequiredRate(rials(300000), 3));
      expect(requiredRate(gregorian, between, rials(100000), 20260316),
          RequiredRate(rials(450000), 2));
    });

    test('the required rate is zero once the target is passed', () {
      final between = range(20261101, 20270228);
      final progress = assess(
          savings(between), between, rials(1200000), const DateKey(20261215));
      expect(progress.status, GoalStatus.met);
      expect(progress.projection.requiredRate, RequiredRate(rials(0), 3));
    });

    test('only an open fixed range has a required rate', () {
      final between = range(20261101, 20270228);
      final laptop = savings(between);
      expect(requiredRate(laptop, between, rials(0), 20261010), isNull,
          reason: 'not started');
      expect(requiredRate(laptop, between, rials(0), 20270301), isNull,
          reason: 'closed');
      expect(requiredRate(cap(), october, rials(0), 20261010), isNull,
          reason: 'recurring');
    });
  });
}
