import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/goal_fixture.dart';

/// The brief's definition of done: goal_period_results is a cache. Drop
/// every row, and history, streaks and progress come back identical.
void main() {
  late GoalFixture f;
  late GoalService service;
  const today = DateKey(20260210);

  setUp(() async {
    f = await GoalFixture.open();
    service = GoalService(f.db, GoalEngine(f.measurer, today: () => today));
  });
  tearDown(() => f.db.close());

  Future<void> expectSurvivesTheDrop(Goal goal) async {
    await service.save(goal);
    final computed = await service.history(goal);
    final cached = await service.history(goal);
    final progress = await service.engine.evaluateCurrent(goal);
    expect(computed.outcomes, isNotEmpty);

    await f.db.customStatement('DELETE FROM goal_period_results');

    final rebuilt = await service.history(goal);
    expect(cached.outcomes, computed.outcomes);
    expect(cached.streaks, computed.streaks);
    expect(rebuilt.outcomes, computed.outcomes);
    expect(rebuilt.streaks, computed.streaks);
    expect(await service.engine.evaluateCurrent(goal), progress);
    expect(await f.db.goalPeriodResultsDao.forGoal(goal.id),
        hasLength(computed.outcomes.length),
        reason: 'the history rebuilt a row per closed period');
  }

  test('a money goal', () async {
    await f.expense(1000, const DateKey(20251010));
    await f.expense(12000, const DateKey(20251105));
    await f.expense(4000, const DateKey(20251220));
    await f.expense(9000, const DateKey(20260131));
    await f.expense(2500, const DateKey(20260203));

    await expectSurvivesTheDrop(moneyGoal(
        period: const RecurringPeriod(PeriodType.month, DateKey(20251001))));
  });

  test('a tracker goal', () async {
    // Saturday weeks from 3 Jan; the current week is 7 - 13 Feb.
    for (final (day, litres) in const [
      (20260105, 0.5), (20260106, 0.75), (20260108, 1.0),
      (20260111, 0.25),
      (20260118, 1.5), (20260120, 0.5),
      (20260126, 0.25),
      (20260201, 2.25),
      (20260208, 0.5),
    ]) {
      await f.log('water', DateKey(day), value: litres);
    }

    await expectSurvivesTheDrop(trackerGoal('water',
        metric: GoalMetric.trackerSum,
        direction: GoalDirection.atLeast,
        target: 2,
        period: const RecurringPeriod(PeriodType.week, DateKey(20260103))));
  });
}
