import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/fake_measurer.dart';

MoneyAmount rials(int minor) => MoneyAmount(Money(minor));
DateRange range(int start, int end) => DateRange(DateKey(start), DateKey(end));

// Computed with JalaliCalendar.keyOf:
//   Shahrivar 1405 = 2026-08-23 .. 2026-09-22
//   Mehr 1405      = 2026-09-23 .. 2026-10-22 (30 Mehr = 2026-10-22)
final shahrivar = range(20260823, 20260922);
final mehr = range(20260923, 20261022);

void main() {
  // A Jalali cap of 10 000 a month.
  final cap = Goal(
    id: 'cap',
    name: 'Dining out',
    metric: GoalMetric.moneySum,
    scope: MoneyScope(const QueryFilters(direction: MoneyDirection.expense)),
    direction: GoalDirection.atMost,
    target: rials(10000),
    period: const RecurringPeriod(PeriodType.month, DateKey(20260101)),
    calendar: CalendarKind.jalali,
    weekStart: DateTime.saturday,
  );
  final daily = <DateKey, GoalAmount>{
    const DateKey(20260920): rials(4000), // 29 Shahrivar
    const DateKey(20260923): rials(3000), // 1 Mehr
    const DateKey(20261010): rials(6000), // 18 Mehr
  };

  test('evaluate measures the period it is given, then assesses it', () async {
    final measurer = FakeMeasurer(daily);
    final engine = GoalEngine(measurer, today: () => const DateKey(20261010));
    final progress = await engine.evaluate(cap, shahrivar);
    expect(measurer.measured, [
      (metric: GoalMetric.moneySum, scope: cap.scope, range: shahrivar),
    ]);
    expect(progress,
        assess(cap, shahrivar, rials(4000), const DateKey(20261010)));
    expect(progress.status, GoalStatus.met);
  });

  test("evaluateCurrent measures the goal's current period, in its calendar",
      () async {
    final engine =
        GoalEngine(FakeMeasurer(daily), today: () => const DateKey(20261010));
    final progress = await engine.evaluateCurrent(cap);
    // Mehr, not October: the goal is Jalali whatever the app shows.
    expect(progress.period, mehr);
    expect(progress.current, rials(9000));
    expect(progress.status, GoalStatus.atRisk);
  });

  test('today is read once, so an evaluation cannot straddle midnight',
      () async {
    // The clock turns from 30 Mehr to 1 Aban between two reads. Read twice,
    // Mehr would be measured and then assessed as if it had closed: met,
    // instead of at risk.
    final days = [const DateKey(20261022), const DateKey(20261023)];
    var reads = 0;
    final engine =
        GoalEngine(FakeMeasurer(daily), today: () => days[reads++]);
    final progress = await engine.evaluateCurrent(cap);
    expect(reads, 1);
    expect(progress.period, mehr);
    expect(progress.status, GoalStatus.atRisk);
  });

  test('a measurer failure reaches the caller', () async {
    // Never a silent zero: a cap reading zero after a database error would
    // tell the user they are under budget.
    final failure = Exception('database is locked');
    final engine = GoalEngine(FakeMeasurer(daily, failure: failure),
        today: () => const DateKey(20261010));
    await expectLater(engine.evaluateCurrent(cap), throwsA(same(failure)));
  });
}
