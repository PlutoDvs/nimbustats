import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

MoneyAmount rials(int minor) => MoneyAmount(Money(minor));
QuantityAmount count(double n) => QuantityAmount(n);
DateRange range(int start, int end) => DateRange(DateKey(start), DateKey(end));

/// A tracker goal; [target] and [direction] are what vary.
Goal trackerGoal(String id, GoalDirection direction, double target,
        PeriodType type) =>
    Goal(
      id: id,
      name: id,
      metric: GoalMetric.trackerCount,
      scope: TrackerScope(id),
      direction: direction,
      target: count(target),
      period: RecurringPeriod(type, const DateKey(20260101)),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.saturday,
    );

void main() {
  final october = range(20261001, 20261031);
  // 10 000 a month, alerts at 80 and 100.
  final cap = Goal(
    id: 'cap',
    name: 'Dining out',
    metric: GoalMetric.moneySum,
    scope: MoneyScope(const QueryFilters(direction: MoneyDirection.expense)),
    direction: GoalDirection.atMost,
    target: rials(10000),
    period: const RecurringPeriod(PeriodType.month, DateKey(20260101)),
    calendar: CalendarKind.gregorian,
    weekStart: DateTime.saturday,
  );

  GoalProgress progressOf(Goal goal, GoalAmount current,
          {DateRange? period, int today = 20261010}) =>
      assess(goal, period ?? october, current, DateKey(today));
  CrossingResult crossCap(GoalAmount current, int? lastAlerted) =>
      crossing(cap, progressOf(cap, current), lastAlerted);

  test('the first crossing alerts once, at the percent reached', () {
    final progress = progressOf(cap, rials(8000));
    final result = crossing(cap, progress, null);
    expect(result.lastAlerted, 80);
    expect(
        result.alert,
        GoalAlert(
          goalId: 'cap',
          goalName: 'Dining out',
          period: october,
          percent: 80,
          direction: GoalDirection.atMost,
          progress: progress,
        ));
  });

  test('recomputing at the same level never re-fires', () {
    // Every save re-evaluates the current period. A crossing already
    // recorded stays recorded, however often the value is recomputed.
    expect(crossCap(rials(8000), 80), const CrossingResult(null, 80));
    expect(crossCap(rials(9500), 80), const CrossingResult(null, 80));
    expect(crossCap(rials(12000), 100), const CrossingResult(null, 100));
  });

  test('a drop below a threshold, then a genuine re-crossing, warns again', () {
    // The expense that crossed 80% was deleted; a later one crosses again.
    final dropped = crossCap(rials(7000), 80);
    expect(dropped, const CrossingResult(null, null));
    final again = crossCap(rials(8200), dropped.lastAlerted);
    expect(again.alert?.percent, 80);
    expect(again.lastAlerted, 80);
    // The same one level up: back under 100 lowers the state to 80.
    final back = crossCap(rials(9000), 100);
    expect(back, const CrossingResult(null, 80));
    expect(crossCap(rials(10000), back.lastAlerted).alert?.percent, 100);
  });

  test('a jump over two thresholds alerts once, at the highest', () {
    // 70% to 105% in one save: one alert, at 100, not one per threshold.
    final result = crossCap(rials(10500), null);
    expect(result.alert?.percent, 100);
    expect(result.lastAlerted, 100);
  });

  test('falling below every threshold resets to null, without an alert', () {
    expect(crossCap(rials(100), 100), const CrossingResult(null, null));
  });

  test('money is compared exactly at the threshold', () {
    expect(reachedPercent(cap, rials(7999)), isNull);
    expect(reachedPercent(cap, rials(8000)), 80);
    expect(reachedPercent(cap, rials(9999)), 80);
    expect(reachedPercent(cap, rials(10000)), 100);
  });

  test('a zero atMost target: anything at all reaches every percent', () {
    final none = trackerGoal('cig', GoalDirection.atMost, 0, PeriodType.day);
    final today = range(20261010, 20261010);
    expect(reachedPercent(none, count(0)), isNull);
    expect(reachedPercent(none, count(1)), 100);
    expect(
        crossing(none, progressOf(none, count(1), period: today), null)
            .alert
            ?.percent,
        100);
  });

  test('a crossing names the period it was assessed for', () {
    // Alert state belongs to one period's row, so the caller keys it by
    // progress.period; crossing itself carries no state across periods.
    // Yesterday's recorded 100 and today's empty state are separate inputs.
    final limit = trackerGoal('cig', GoalDirection.atMost, 10, PeriodType.day);
    final yesterday = range(20261009, 20261009);
    final today = range(20261010, 20261010);
    final last = crossing(limit,
        progressOf(limit, count(12), period: yesterday, today: 20261009), null);
    expect(last.lastAlerted, 100);
    final first = crossing(limit,
        progressOf(limit, count(8), period: today, today: 20261010), null);
    expect(first.alert?.percent, 80);
    expect(first.alert?.period, today);
  });

  test('a goal to reach alerts as it climbs, with its own direction', () {
    final gym = trackerGoal('gym', GoalDirection.atLeast, 5, PeriodType.week);
    final week = range(20261010, 20261016);
    final four = crossing(
        gym, progressOf(gym, count(4), period: week, today: 20261014), null);
    expect(four.alert?.percent, 80);
    expect(four.alert?.direction, GoalDirection.atLeast);
    final five = crossing(gym,
        progressOf(gym, count(5), period: week, today: 20261015),
        four.lastAlerted);
    expect(five.alert?.percent, 100);
  });
}
