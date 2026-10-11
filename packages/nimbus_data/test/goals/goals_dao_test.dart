import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';

void main() {
  late AppDatabase db;
  late GoalsDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = db.goalsDao;
  });
  tearDown(() => db.close());

  // One of each shape the editor makes. Between them they set every
  // column: both target columns, all three period shapes, both calendars,
  // both week starts, custom alert percents, and a paused goal.
  final goals = [
    Goal(
      id: 'g1',
      name: 'Dining out',
      metric: GoalMetric.moneySum,
      scope: MoneyScope(QueryFilters(
        direction: MoneyDirection.expense,
        categorySubtreePaths: const ['/food/dining/'],
        tags: TagsAny(const ['/trip/']),
      )),
      direction: GoalDirection.atMost,
      target: const MoneyAmount(Money(5000000)),
      period: const RecurringPeriod(PeriodType.month, DateKey(20260321)),
      calendar: CalendarKind.jalali,
      weekStart: DateTime.saturday,
      alertPercents: const [50, 80, 100],
    ),
    Goal(
      id: 'g2',
      name: 'Cigarettes',
      metric: GoalMetric.trackerCount,
      scope: TrackerScope('cig'),
      direction: GoalDirection.atMost,
      target: const QuantityAmount(0),
      period: const RecurringPeriod(PeriodType.day, DateKey(20260105)),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.monday,
    ),
    Goal(
      id: 'g3',
      name: 'Water',
      metric: GoalMetric.trackerSum,
      scope: TrackerScope('water'),
      direction: GoalDirection.atLeast,
      target: const QuantityAmount(14.5),
      period: const RecurringPeriod(PeriodType.week, DateKey(20260105)),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.monday,
    ),
    Goal(
      id: 'g4',
      name: 'Car',
      metric: GoalMetric.netSavings,
      scope: MoneyScope(const QueryFilters()),
      direction: GoalDirection.atLeast,
      target: const MoneyAmount(Money(250000000)),
      period: FixedRangePeriod(
          const DateRange(DateKey(20260321), DateKey(20270320))),
      calendar: CalendarKind.jalali,
      weekStart: DateTime.saturday,
      active: false,
    ),
  ];

  for (final goal in goals) {
    test('${goal.name} survives a round trip', () async {
      await dao.upsert(goal);

      expect(await dao.byId(goal.id),
          isA<GoalReadable>().having((r) => r.goal, 'goal', goal));
    });
  }

  Future<int> createdAt(String id) async => (await db
          .customSelect("SELECT created_at AS c FROM goals WHERE id = '$id'")
          .getSingle())
      .read<int>('c');

  test('upserting an existing id rewrites it in place', () async {
    await dao.upsert(goals.first);
    final created = await createdAt('g1');

    await dao.upsert(goals.first.copyWith(name: 'Eating out'));

    expect(((await dao.byId('g1'))! as GoalReadable).goal.name, 'Eating out');
    expect(await createdAt('g1'), created);
    expect(await dao.watchAll().first, hasLength(1));
  });

  test('watchAll lists live goals by id; delete and restore move one out '
      'and back', () async {
    await dao.upsert(goals[1]);
    await dao.upsert(goals[0]);
    expect([for (final r in await dao.watchAll().first) r.id], ['g1', 'g2']);

    await dao.softDelete('g1');
    expect([for (final r in await dao.watchAll().first) r.id], ['g2']);
    expect(await dao.byId('g1'), isNull);

    await dao.restore('g1');
    expect([for (final r in await dao.watchAll().first) r.id], ['g1', 'g2']);
  });

  test('setActive writes the flag', () async {
    await dao.upsert(goals.first);

    await dao.setActive('g1', false);

    expect(((await dao.byId('g1'))! as GoalReadable).goal.active, isFalse);
  });

  test('a write to an id that does not exist throws', () async {
    await expectLater(dao.setActive('nope', true), throwsStateError);
    await expectLater(dao.softDelete('nope'), throwsStateError);
    await expectLater(dao.restore('nope'), throwsStateError);
  });

  // Each corrupts g1 in one way. None may default; each becomes an
  // unreadable row that still carries the goal's name for its card.
  final malformed = <String, Map<String, Object?>>{
    'an unknown metric': {'metric': 'moneyMax'},
    'an unknown direction': {'direction': 'sideways'},
    'an unknown calendar': {'calendar': 'lunar'},
    'a scope that is not JSON': {'scope_json': '{'},
    'a scope of an unknown type': {'scope_json': '{"type":"stocks"}'},
    'both targets set': {'target_quantity': 1.5},
    'no target': {'target_minor': null},
    'a quantity target on a money metric': {
      'target_minor': null,
      'target_quantity': 5000.0,
    },
    'alert percents that are not a list': {'alert_percents': '80'},
    'an unknown period': {'period': 'fortnight'},
  };
  for (final MapEntry(key: what, value: columns) in malformed.entries) {
    test('$what makes the row unreadable, not a guess', () async {
      await dao.upsert(goals.first);
      for (final MapEntry(key: column, value: value) in columns.entries) {
        await db.customStatement(
            'UPDATE goals SET $column = ? WHERE id = ?', [value, 'g1']);
      }

      expect(
        await dao.byId('g1'),
        isA<GoalUnreadable>()
            .having((r) => r.id, 'id', 'g1')
            .having((r) => r.name, 'name', 'Dining out')
            .having((r) => r.error, 'error', isA<FormatException>()),
      );
    });
  }

  test('an unreadable row leaves the others readable', () async {
    await dao.upsert(goals[0]);
    await dao.upsert(goals[1]);
    await db.customStatement(
        "UPDATE goals SET metric = 'moneyMax' WHERE id = 'g1'");

    final all = await dao.watchAll().first;

    expect(all[0], isA<GoalUnreadable>());
    expect(all[1], isA<GoalReadable>().having((r) => r.goal, 'goal', goals[1]));
  });
}
