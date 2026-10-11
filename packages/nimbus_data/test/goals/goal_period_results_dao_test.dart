import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/goal_fixture.dart';

void main() {
  late GoalFixture f;
  late GoalPeriodResultsDao dao;
  final goal = moneyGoal();
  final water = trackerGoal('water', metric: GoalMetric.trackerSum);
  const january = DateRange(DateKey(20260101), DateKey(20260131));
  const february = DateRange(DateKey(20260201), DateKey(20260228));
  const midJanuary = DateKey(20260115);

  GoalProgress spent(int minor) =>
      assess(goal, january, MoneyAmount(Money(minor)), midJanuary);

  setUp(() async {
    f = await GoalFixture.open();
    dao = f.db.goalPeriodResultsDao;
    // A period row references its goal.
    await f.db.goalsDao.upsert(goal);
    await f.db.goalsDao.upsert(water);
  });
  tearDown(() => f.db.close());

  Future<CachedPeriod?> rowFor(Goal g, DateRange period) async {
    for (final row in await dao.forGoal(g.id)) {
      if (row.period == period) return row;
    }
    return null;
  }

  test('values written are read back per period, oldest first', () async {
    await dao.writeValues(
        goal.id,
        [
          (period: february, value: const MoneyAmount(Money(700))),
          (period: january, value: const MoneyAmount(Money(1200))),
        ],
        42);
    await dao.writeValues(
        water.id, [(period: january, value: const QuantityAmount(2.5))], 7);

    final rows = await dao.forGoal(goal.id);

    expect([for (final r in rows) r.period], [january, february]);
    expect([for (final r in rows) r.value],
        [const MoneyAmount(Money(1200)), const MoneyAmount(Money(700))]);
    expect({for (final r in rows) r.watermark}, {42});
    expect((await dao.forGoal(water.id)).single.value,
        const QuantityAmount(2.5));
  });

  test('a value rewrite leaves the alert state alone', () async {
    expect(await dao.recordCrossing(goal, spent(8500)), isNotNull);

    await dao.writeValues(
        goal.id, [(period: january, value: const MoneyAmount(Money(9100)))], 99);

    final row = await rowFor(goal, january);
    expect(row!.value, const MoneyAmount(Money(9100)));
    expect(row.watermark, 99);
    expect(row.lastAlerted, 80);
  });

  test('a crossing alerts once; the same progress again does not', () async {
    expect((await dao.recordCrossing(goal, spent(8500)))?.percent, 80);
    expect(await dao.recordCrossing(goal, spent(8500)), isNull);
    expect((await dao.recordCrossing(goal, spent(10500)))?.percent, 100);
    expect((await rowFor(goal, january))!.lastAlerted, 100);
  });

  test('two evaluations of one crossing at once alert once', () async {
    // The app and, from Phase 6, a background isolate may evaluate the same
    // goal together. recordCrossing's transaction makes the second read the
    // first one's state.
    final alerts = await Future.wait([
      dao.recordCrossing(goal, spent(8500)),
      dao.recordCrossing(goal, spent(8500)),
    ]);

    expect(alerts.whereType<GoalAlert>(), hasLength(1));
    expect(alerts.whereType<GoalAlert>().single.percent, 80);
    expect((await rowFor(goal, january))!.lastAlerted, 80);
  });

  test('a baseline records the reached percent without an alert', () async {
    await dao.setBaseline(goal, spent(8500));

    expect((await rowFor(goal, january))!.lastAlerted, 80);
    expect(await dao.recordCrossing(goal, spent(8500)), isNull);
    expect((await dao.recordCrossing(goal, spent(10000)))?.percent, 100);
  });

  test("deleting one goal's rows leaves another's", () async {
    await dao.writeValues(
        goal.id, [(period: january, value: const MoneyAmount(Money(1)))], 1);
    await dao.writeValues(
        water.id, [(period: january, value: const QuantityAmount(1))], 1);

    await dao.deleteForGoal(goal.id);

    expect(await dao.forGoal(goal.id), isEmpty);
    expect(await dao.forGoal(water.id), hasLength(1));
  });
}
