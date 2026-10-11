import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/provider_retry.dart';
import 'package:nimbustats/features/analytics/application/analytics_providers.dart';
import 'package:nimbustats/features/goals/application/goal_providers.dart';
import 'package:nimbustats/features/goals/application/goal_watcher.dart';
import 'package:nimbustats/features/settings/application/settings_providers.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';

import '../trackers/support/tracker_fixture.dart';
import 'support/goal_test_app.dart';

/// The watcher as the app runs it: real providers over a test database, on
/// the real clock for timing (the debounce is a real 300 ms), standing on
/// the fake's date.
void main() {
  late FakeClock fake;
  late AppDatabase db;
  late GoalService service;
  late List<GoalAlert> alerts;
  ProviderContainer? started;

  const day5 = DateKey(20261005);
  const day6 = DateKey(20261006);

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    service = goalServiceFor(db, fake.clock.today);
    alerts = [];
    started = null;
    await seedCategories(db);
  });
  tearDown(() async {
    started?.dispose();
    await db.close();
  });

  ProviderContainer container() => started!;

  /// The app's providers over the test database, wired as main() wires
  /// them, with the watcher started and its alerts collected.
  Future<GoalWatcher> start() async {
    final c = ProviderContainer(retry: nimbusNoRetry, overrides: [
      appDatabaseProvider.overrideWithValue(db),
      ...trackerOverrides(fake),
    ]);
    started = c;
    // Settings first, so their first emission is not mistaken for a
    // calendar switch.
    final settings = c.listen(settingsProvider, (_, __) {});
    addTearDown(settings.close);
    await c.read(settingsProvider.future);
    final watcher = c.read(goalWatcherProvider);
    final subscription = watcher.alerts.listen(alerts.add);
    addTearDown(subscription.cancel);
    watcher.start();
    return watcher;
  }

  /// Waits on the real clock until [done]: drift and the debounce settle in
  /// their own time.
  Future<void> until(bool Function() done, String what) async {
    for (var i = 0; i < 300; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('timed out waiting for $what');
  }

  /// Long enough for a debounce and an evaluation to have happened, for
  /// asserting that something did *not*.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 700));

  List<int> percents() => [for (final alert in alerts) alert.percent];

  test('a crossing made while the app was closed alerts once, at start',
      () async {
    await service.save(spendingCap()); // the baseline: nothing spent
    await spend(db, 850000, day5); // a background SMS capture, say
    final watcher = await start();
    await until(() => alerts.length == 1, 'the start-up alert');
    expect(alerts.single.goalId, 'cap');
    expect(alerts.single.percent, 80);

    // The app starts again: nothing new crossed, so nothing alerts.
    watcher
      ..stop()
      ..start();
    await settle();
    expect(alerts, hasLength(1));
  });

  test('a burst of writes inside the debounce is evaluated once', () async {
    await service.save(spendingCap());
    await start();
    await settle();

    await spend(db, 850000, day5);
    // Shorter than the debounce, longer than an evaluation: without the
    // debounce the first write alone would alert at 80.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await spend(db, 200000, day5);
    await until(() => alerts.isNotEmpty, 'the alert');
    await settle();

    expect(percents(), [100], reason: 'one evaluation, one alert at the top');
  });

  test("a calendar switch keeps each goal's own calendar and re-fires nothing",
      () async {
    // Review Focus 2. 2026-09-25 is inside the Jalali month that holds
    // today (1405/07 starts on 09-23) but outside Gregorian October, so a
    // goal that took the app's new calendar would lose this spending.
    final mehr =
        const JalaliCalendar().periodContaining(day5, PeriodType.month);
    await service.save(spendingCap());
    await spend(db, 850000, const DateKey(20260925));
    await start();
    await until(() => alerts.length == 1, 'the start-up alert');

    await SettingsRepository(db.settingsDao).save(
        AppSettings.defaults.copyWith(calendarKind: CalendarKind.gregorian));
    await until(
        () =>
            container().read(analyticsEngineProvider).calendar
                is GregorianCalendar,
        'the engine to take the new calendar');
    await spend(db, 10000, day5);
    await settle();
    expect(percents(), [80], reason: 'the rebuilt engine must not re-fire');

    final progress =
        container().listen(goalProgressProvider(spendingCap()), (_, __) {});
    addTearDown(progress.close);
    await until(
        () =>
            progress.read().value?.current == const MoneyAmount(Money(860000)),
        "the progress in the goal's own month");
    expect(progress.read().requireValue.period, mehr);

    await spend(db, 200000, day5);
    await until(() => alerts.length == 2, 'the 100% crossing');
    expect(percents(), [80, 100]);
  });

  test('the first crossing on a new day alerts again', () async {
    // Review Focus 3: yesterday's alert state belongs to yesterday's row.
    final daily = spendingCap(
        id: 'daily',
        name: 'Coffee',
        target: 100000,
        period: PeriodType.day,
        alerts: const [100]);
    await service.save(daily);
    await start();
    await settle();
    await spend(db, 120000, day5);
    await until(() => alerts.length == 1, "today's crossing");

    fake.advance(const Duration(days: 1));
    container().read(goalTodayProvider.notifier).refresh();
    await settle();
    expect(alerts, hasLength(1), reason: 'a new day starts from nothing');

    await spend(db, 120000, day6);
    await until(() => alerts.length == 2, "the new day's crossing");
    expect(alerts.last.period, const DateRange(day6, day6));
  });

  test('a new day is evaluated without waiting for a write', () async {
    // Spending dated tomorrow, entered today. Nothing writes at midnight, so
    // only the day change itself can find the crossing.
    await service.save(spendingCap(
        id: 'daily',
        name: 'Coffee',
        target: 100000,
        period: PeriodType.day,
        alerts: const [100]));
    await spend(db, 120000, day6);
    await start();
    await settle();
    expect(alerts, isEmpty);

    fake.advance(const Duration(days: 1));
    container().read(goalTodayProvider.notifier).refresh();
    await until(() => alerts.length == 1, "the new day's evaluation");
    expect(alerts.single.period, const DateRange(day6, day6));
  });

  test('a paused goal never alerts', () async {
    await service.save(spendingCap());
    await service.setActive(spendingCap(), false);
    await spend(db, 950000, day5);
    await start();
    await settle();
    expect(alerts, isEmpty);
  });

  test('a tracker entry evaluates tracker goals', () async {
    final trackers = repositoryFor(db, fake);
    final cig = await trackers.create(cigarettes);
    await service.save(habitGoal(cig, id: 'smoke', target: 2, alerts: const [100]));
    await start();
    await settle();

    await trackers.logEntry(cig.id);
    await trackers.logEntry(cig.id);
    await until(() => alerts.length == 1, 'the limit reached');
    expect(alerts.single.goalId, 'smoke');
    expect(alerts.single.direction, GoalDirection.atMost);
  });

  test('stop drops a pending evaluation; start picks the crossing up',
      () async {
    await service.save(spendingCap());
    final watcher = await start();
    await settle();

    await spend(db, 850000, day5);
    watcher.stop();
    await settle();
    expect(alerts, isEmpty, reason: 'a stopped watcher evaluates nothing');

    watcher.start();
    await until(() => alerts.length == 1, 'the start-up evaluation');
    expect(percents(), [80]);
  });

  test('start and stop are counted: the old holder letting go keeps the new',
      () async {
    // A router rebuild mounts the new listener (start) before the old one
    // disposes (stop). Ruling A-C5.
    await service.save(spendingCap());
    final watcher = await start(); // holder 1
    await settle();
    watcher
      ..start() // holder 2
      ..stop(); // holder 1 lets go

    await spend(db, 850000, day5);
    await until(() => alerts.length == 1, 'the alert with one holder left');
    expect(percents(), [80]);

    watcher.stop(); // the last holder
    await spend(db, 200000, day5);
    await settle();
    expect(alerts, hasLength(1), reason: 'nobody holds the watcher now');
  });

  test("a goal's progress re-runs on a write and keeps its value meanwhile",
      () async {
    await service.save(spendingCap());
    await start();
    final states = <AsyncValue<GoalProgress>>[];
    final subscription = container().listen(
        goalProgressProvider(spendingCap()), (_, next) => states.add(next),
        fireImmediately: true);
    addTearDown(subscription.close);
    await until(() => states.last.hasValue, 'the first answer');
    expect(states.last.requireValue.current, const MoneyAmount(Money(0)));

    await spend(db, 300000, day5);
    await until(
        () =>
            states.last.value?.current == const MoneyAmount(Money(300000)),
        'the re-run');
    final first = states.indexWhere((state) => state.hasValue);
    expect([for (final state in states.skip(first)) if (!state.hasValue) state],
        isEmpty,
        reason: 'the card would flash its skeleton: $states');
  });
}
