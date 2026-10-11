import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/goal_fixture.dart';

void main() {
  late GoalFixture f;
  late _CountingMeasurer measurer;
  late GoalService service;
  late DateKey today;

  setUp(() async {
    f = await GoalFixture.open();
    measurer = _CountingMeasurer(f.measurer);
    today = const DateKey(20260210);
    service = GoalService(f.db, GoalEngine(measurer, today: () => today));
  });
  tearDown(() => f.db.close());

  DateRange range(int start, int end) =>
      DateRange(DateKey(start), DateKey(end));

  PeriodOutcome spent(int start, int end, int minor, GoalStatus status) =>
      PeriodOutcome(range(start, end), MoneyAmount(Money(minor)), status);

  Future<CachedPeriod?> rowFor(Goal goal, DateRange period) async {
    for (final row in await f.db.goalPeriodResultsDao.forGoal(goal.id)) {
      if (row.period == period) return row;
    }
    return null;
  }

  group('history', () {
    final goal = moneyGoal(
        period: const RecurringPeriod(PeriodType.month, DateKey(20251001)));

    // Against the 10 000 cap: October and November met, December over,
    // January met. Today is 10 February.
    Future<void> seed() async {
      await f.expense(1000, const DateKey(20251010));
      await f.expense(4000, const DateKey(20251110));
      await f.expense(12000, const DateKey(20251205));
      await f.expense(3000, const DateKey(20260115));
    }

    final expected = [
      spent(20251001, 20251031, 1000, GoalStatus.met),
      spent(20251101, 20251130, 4000, GoalStatus.met),
      spent(20251201, 20251231, 12000, GoalStatus.exceeded),
      spent(20260101, 20260131, 3000, GoalStatus.met),
    ];

    test('a first load measures every closed period with one daily query '
        'and caches it', () async {
      await seed();
      await service.save(goal);

      final result = await service.history(goal);

      expect(result.outcomes, expected);
      expect(result.streaks, const GoalStreaks(current: 1, best: 2));
      expect(measurer.dailySpans, [range(20251001, 20260131)]);
      final watermark = await f.db.goalPeriodResultsDao.moneyWatermark();
      for (final outcome in expected) {
        final row = await rowFor(goal, outcome.period);
        expect(row?.value, outcome.value);
        expect(row?.watermark, watermark);
      }
    });

    test('a second load with nothing written is served from the cache',
        () async {
      await seed();
      await service.save(goal);
      final first = await service.history(goal);

      final second = await service.history(goal);

      expect(measurer.dailySpans, hasLength(1));
      expect(second.outcomes, first.outcomes);
      expect(second.streaks, first.streaks);
    });

    test('any money write, even out of scope, makes the cache stale',
        () async {
      await seed();
      await service.save(goal);
      await ageMoneyRows(f.db);
      await service.history(goal);

      await f.expense(500, const DateKey(20260205), category: 'rent');
      final again = await service.history(goal);

      expect(measurer.dailySpans,
          [range(20251001, 20260131), range(20251001, 20260131)]);
      expect(again.outcomes, expected);
    });

    test('a period that closes after the last load is measured alone',
        () async {
      await seed();
      await service.save(goal);
      await ageMoneyRows(f.db);
      await service.history(goal);

      today = const DateKey(20260310);
      final later = await service.history(goal);

      expect(measurer.dailySpans.last, range(20260201, 20260228));
      expect(later.outcomes,
          [...expected, spent(20260201, 20260228, 0, GoalStatus.met)]);
    });
  });

  group('alert state', () {
    // Monthly from 1 January 2026, cap 10 000, alerts at 80 and 100.
    final goal = moneyGoal();
    const january = DateRange(DateKey(20260101), DateKey(20260131));

    test('a stale recompute keeps the alert its period already gave',
        () async {
      today = const DateKey(20260115);
      await service.save(goal);
      await f.expense(8500, const DateKey(20260110));
      expect((await service.check(goal))?.percent, 80);

      today = const DateKey(20260210);
      await ageMoneyRows(f.db);
      await service.history(goal);
      await f.expense(100, const DateKey(20260205), category: 'rent');
      await service.history(goal);

      final row = await rowFor(goal, january);
      expect(measurer.dailySpans, hasLength(2),
          reason: 'January was measured, then recomputed');
      expect(row!.value, const MoneyAmount(Money(8500)));
      expect(row.watermark, greaterThan(1));
      expect(row.lastAlerted, 80);
    });

    test('history never alerts: a closed period over its cap leaves no '
        'alert state', () async {
      await service.save(goal);
      await f.expense(50000, const DateKey(20260110));

      final result = await service.history(goal);

      expect(result.outcomes.single.status, GoalStatus.exceeded);
      expect((await rowFor(goal, january))!.lastAlerted, isNull);
      expect(await service.check(goal), isNull, reason: 'February is empty');
    });

    test('a fixed range that is over does not alert', () async {
      final savings = netSavingsGoal(january, target: 1000);
      await service.save(savings);
      await f.income(5000, const DateKey(20260110));

      expect(await service.check(savings), isNull);
      expect((await rowFor(savings, january))!.lastAlerted, isNull);
    });

    test('saving records what the goal already reaches, without an alert',
        () async {
      today = const DateKey(20260115);
      await f.expense(8500, const DateKey(20260110));
      await service.save(goal);

      expect(await service.check(goal), isNull);
      await f.expense(1500, const DateKey(20260112));
      expect((await service.check(goal))?.percent, 100);
    });

    test('an edit drops the cache and re-baselines without an alert',
        () async {
      today = const DateKey(20260115);
      final older = goal.copyWith(
          period: const RecurringPeriod(PeriodType.month, DateKey(20251201)));
      await f.expense(3000, const DateKey(20251205));
      await f.expense(8500, const DateKey(20260110));
      await service.save(older);
      await service.history(older);

      final tighter = older.copyWith(target: const MoneyAmount(Money(5000)));
      await service.save(tighter);

      expect(await service.check(tighter), isNull);
      final rows = await f.db.goalPeriodResultsDao.forGoal(goal.id);
      expect(rows.single.period, january,
          reason: "December's cached row went with the edit");
      expect(rows.single.lastAlerted, 100);
    });

    test('a paused goal is not checked and writes nothing', () async {
      today = const DateKey(20260115);
      final paused = goal.copyWith(active: false);
      await service.save(paused);
      await f.expense(9000, const DateKey(20260110));

      expect(await service.check(paused), isNull);
      expect(await f.db.goalPeriodResultsDao.forGoal(goal.id), isEmpty);
    });

    test('resuming re-baselines', () async {
      today = const DateKey(20260115);
      await service.save(goal);
      await service.setActive(goal, false);
      await f.expense(9000, const DateKey(20260110));

      await service.setActive(goal, true);

      expect(await service.check(goal), isNull);
      expect((await rowFor(goal, january))!.lastAlerted, 80);
    });

    test('restoring a deleted goal re-baselines', () async {
      today = const DateKey(20260115);
      await service.save(goal);
      await service.delete(goal.id);
      expect(await f.db.goalsDao.byId(goal.id), isNull);
      await f.expense(9000, const DateKey(20260110));

      await service.restore(goal.id);

      expect(await f.db.goalsDao.byId(goal.id), isA<GoalReadable>());
      expect(await service.check(goal), isNull);
    });
  });

  group("periods are the goal's, not the engine's", () {
    test('across the Gregorian new year', () async {
      final goal = moneyGoal(
          period: const RecurringPeriod(PeriodType.month, DateKey(20251115)));
      await f.expense(1000, const DateKey(20251231));
      await f.expense(2000, const DateKey(20260101));
      await service.save(goal);

      expect((await service.history(goal)).outcomes, [
        spent(20251101, 20251130, 0, GoalStatus.met),
        spent(20251201, 20251231, 1000, GoalStatus.met),
        spent(20260101, 20260131, 2000, GoalStatus.met),
      ]);
    });

    test('across Nowruz in a Jalali goal', () async {
      // Bahman 1404 is 21 Jan - 19 Feb 2026. Esfand 1404 has 29 days, 20 Feb
      // - 20 Mar. Farvardin 1405 is 21 Mar - 20 Apr. The engine's calendar
      // is Gregorian: goals hand it plain days.
      today = const DateKey(20260425);
      final goal = moneyGoal(
          calendar: CalendarKind.jalali,
          period: const RecurringPeriod(PeriodType.month, DateKey(20260215)));
      await f.expense(1000, const DateKey(20260320));
      await f.expense(2000, const DateKey(20260321));
      await service.save(goal);

      expect((await service.history(goal)).outcomes, [
        spent(20260121, 20260219, 0, GoalStatus.met),
        spent(20260220, 20260320, 1000, GoalStatus.met),
        spent(20260321, 20260420, 2000, GoalStatus.met),
      ]);
    });

    test("a weekly history starts its weeks on the goal's week start",
        () async {
      today = const DateKey(20260121);
      const since = RecurringPeriod(PeriodType.week, DateKey(20260105));
      final monday =
          moneyGoal(id: 'monday', period: since, weekStart: DateTime.monday);
      final saturday = moneyGoal(
          id: 'saturday', period: since, weekStart: DateTime.saturday);
      // Saturday 10 and Sunday 11 January 2026.
      await f.expense(1000, const DateKey(20260110));
      await f.expense(500, const DateKey(20260111));
      await service.save(monday);
      await service.save(saturday);

      expect((await service.history(monday)).outcomes, [
        spent(20260105, 20260111, 1500, GoalStatus.met),
        spent(20260112, 20260118, 0, GoalStatus.met),
      ]);
      expect((await service.history(saturday)).outcomes, [
        spent(20260103, 20260109, 0, GoalStatus.met),
        spent(20260110, 20260116, 1500, GoalStatus.met),
      ]);
    });
  });

  group('history racing an edit', () {
    test('a save that lands mid-measure leaves no stale cache for the edit',
        () async {
      const since = RecurringPeriod(PeriodType.month, DateKey(20251001));
      final old = moneyGoal(period: since);
      final edited = old.copyWith(
          scope: MoneyScope(const QueryFilters(
              direction: MoneyDirection.expense,
              categorySubtreePaths: ['/rent/'])));
      await f.expense(1000, const DateKey(20251010));
      await f.expense(7000, const DateKey(20251010), category: 'rent');
      await service.save(old);
      // Age the row so the edit's stamp differs from it even within a
      // millisecond.
      await f.db.customStatement('UPDATE goals SET updated_at = 1');
      measurer.beforeFirstDaily = () => service.save(edited);

      final raced = await service.history(old);
      final after = await service.history(edited);

      expect(raced.outcomes.first.value, const MoneyAmount(Money(1000)),
          reason: 'the caller asked about the old definition');
      expect(after.outcomes.first.value, const MoneyAmount(Money(7000)),
          reason: 'the edit must not be served the previous definition cache');
    });
  });

  group('preview', () {
    test("shows a new draft's last three closed periods and writes nothing",
        () async {
      await f.expense(4000, const DateKey(20251110));
      await f.expense(12000, const DateKey(20251205));
      await f.expense(3000, const DateKey(20260115));
      await f.expense(2000, const DateKey(20260205));
      final draft = moneyGoal(period: RecurringPeriod(PeriodType.month, today));

      final preview = await service.preview(draft);

      expect(preview.recent, [
        spent(20251101, 20251130, 4000, GoalStatus.met),
        spent(20251201, 20251231, 12000, GoalStatus.exceeded),
        spent(20260101, 20260131, 3000, GoalStatus.met),
      ]);
      expect(preview.current.period, range(20260201, 20260228));
      expect(preview.current.current, const MoneyAmount(Money(2000)));
      expect(measurer.dailySpans, [range(20251101, 20260131)]);
      expect(await f.db.goalsDao.watchAll().first, isEmpty);
      expect(await f.db.goalPeriodResultsDao.forGoal(draft.id), isEmpty);
    });

    test('a fixed range has no recent periods', () async {
      await f.income(5000, const DateKey(20260110));

      final preview =
          await service.preview(netSavingsGoal(range(20260101, 20261231)));

      expect(preview.recent, isEmpty);
      expect(preview.current.current, const MoneyAmount(Money(5000)));
    });
  });
}

/// Delegates, and records each measureDaily span. This is how a test tells
/// a history served from the cache from a computed one.
final class _CountingMeasurer implements GoalMeasurer {
  _CountingMeasurer(this._inner);

  final GoalMeasurer _inner;
  final dailySpans = <DateRange>[];

  /// Runs once, before the first measureDaily delegates: a write that lands
  /// while history is measuring.
  Future<void> Function()? beforeFirstDaily;

  @override
  Future<GoalAmount> measure(
          GoalMetric metric, GoalScope scope, DateRange range) =>
      _inner.measure(metric, scope, range);

  @override
  Future<Map<DateKey, GoalAmount>> measureDaily(
      GoalMetric metric, GoalScope scope, DateRange span) async {
    dailySpans.add(span);
    final hook = beforeFirstDaily;
    beforeFirstDaily = null;
    if (hook != null) await hook();
    return _inner.measureDaily(metric, scope, span);
  }
}
