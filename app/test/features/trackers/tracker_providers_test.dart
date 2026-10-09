import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/provider_retry.dart';
import 'package:nimbustats/features/analytics/application/analytics_providers.dart';
import 'package:nimbustats/features/settings/application/settings_providers.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';
import 'package:nimbustats/features/trackers/application/tracker_providers.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';

import 'support/tracker_fixture.dart';

/// The three views derived from `trackerResultProvider`, as the screens see
/// them. Once a view has shown a value it must never drop back to "no value":
/// each screen draws its skeleton (or, for the streak lines, nothing) for a
/// state without one, and that reads as a flicker.
void main() {
  late FakeClock fake;
  late AppDatabase db;
  late TrackerRepository repo;
  late ProviderContainer container;
  late Tracker cig;

  const day5 = DateKey(20261005);
  const day6 = DateKey(20261006);

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    repo = repositoryFor(db, fake);
    cig = await repo.create(cigarettes);
    await repo.logEntry(cig.id);
    await repo.logEntry(cig.id);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// The app's providers over the test database, wired as main() wires them.
  Future<void> start([List<Override> overrides = const []]) async {
    container = ProviderContainer(retry: nimbusNoRetry, overrides: [
      appDatabaseProvider.overrideWithValue(db),
      ...trackerOverrides(fake),
      ...overrides,
    ]);
    // Settings first, so their first emission is not mistaken for a reload.
    final settings = container.listen(settingsProvider, (_, __) {});
    addTearDown(settings.close);
    await container.read(settingsProvider.future);
  }

  /// Waits on the real clock until [done]: drift's streams and queries
  /// settle in their own time.
  Future<void> until(bool Function() done, String what) async {
    for (var i = 0; i < 500; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    fail('timed out waiting for $what');
  }

  /// Every state [provider] passes through, from the first, held by a
  /// listener as a screen holds it.
  List<AsyncValue<T>> record<T>(ProviderListenable<AsyncValue<T>> provider) {
    final states = <AsyncValue<T>>[];
    final subscription = container.listen(
        provider, (_, next) => states.add(next),
        fireImmediately: true);
    addTearDown(subscription.close);
    return states;
  }

  /// Once [states] had a value, every later state still has one.
  void expectNeverLosesItsValue(List<AsyncValue<Object?>> states) {
    final first = states.indexWhere((state) => state.hasValue);
    expect(first, isNot(-1), reason: 'never had a value: $states');
    expect(
      [for (final state in states.skip(first)) if (!state.hasValue) state],
      isEmpty,
      reason: 'a state after the first value had none: $states',
    );
  }

  // One case per derived view: the view, the question it asks, and whether a
  // value shows the two entries logged in setUp.
  final views = <String,
      (
        ProviderListenable<AsyncValue<Object?>> Function(),
        TrackerQuerySpec Function(),
        bool Function(Object?),
      )>{
    "the tab's totals": (
      () => trackerTotalsProvider,
      () => TrackerQueries.dayTotals([cig.id], day5),
      (value) => (value! as Map<String, double>)[cig.id] == 2,
    ),
    "the detail header's day total": (
      () => trackerDayTotalProvider(cig.id),
      () => TrackerQueries.dayTotal(cig.id, day5),
      (value) => value == 2,
    ),
    'the streaks': (
      () => trackerStreaksProvider(cig.id),
      () => TrackerQueries.loggedDays(cig.id),
      (value) => (value! as TrackerStreaks).current == 1,
    ),
  };

  for (final MapEntry(key: name, value: (view, question, isLoaded))
      in views.entries) {
    group(name, () {
      test('keeps its value while a write re-runs its question', () async {
        await start();
        final source = record(trackerResultProvider(question()));
        final states = record(view());
        await until(() => states.last.hasValue && isLoaded(states.last.value),
            'the first answer');

        await repo.logEntry(cig.id);
        await until(() => source.any((state) => state.isRefreshing),
            'the write to re-run the question');
        await until(() => !source.last.isLoading, 'the re-run');
        await container.pump();

        expectNeverLosesItsValue(states);
      });

      test('keeps its value while a calendar switch reloads its question',
          () async {
        await start();
        final source = record(trackerResultProvider(question()));
        final states = record(view());
        await until(() => states.last.hasValue && isLoaded(states.last.value),
            'the first answer');

        await SettingsRepository(db.settingsDao).save(AppSettings.defaults
            .copyWith(calendarKind: CalendarKind.gregorian));
        await until(
            () => container.read(analyticsEngineProvider).calendar
                is GregorianCalendar,
            'the engine to take the new calendar');
        await until(() => source.any((state) => state.isReloading),
            'the question to reload');
        await until(() => !source.last.isLoading, 'the reload');
        await container.pump();

        expectNeverLosesItsValue(states);
        expect(isLoaded(states.last.value), isTrue);
      });
    });
  }

  group("the tab's totals", () {
    test('outlive their last listener, as the tab outlives a visit elsewhere',
        () async {
      // Leaving the tab unmounts it, and the totals lose their only listener.
      await start();
      final first = container.listen(trackerTotalsProvider, (_, __) {});
      await until(() => container.read(trackerTotalsProvider).hasValue,
          'the first answer');
      first.close();
      await container.pump();

      final states = record(trackerTotalsProvider);

      expect(states.first.value, {cig.id: 2.0},
          reason: 'coming back started from nothing: $states');
    });

    test("show the last map until a new day's totals land", () async {
      // A new day is a new question, which has no answer to carry. Held open
      // here, as it is on a slow device.
      final held = Completer<TrackerResult>();
      await start([
        trackerResultProvider(TrackerQueries.dayTotals([cig.id], day6))
            .overrideWith((ref) => held.future),
      ]);
      final states = record(trackerTotalsProvider);
      await until(() => states.last.hasValue, 'the first answer');

      fake.advance(const Duration(days: 1));
      container.read(trackerTodayProvider.notifier).refresh();
      await container.pump();
      expect(container.read(trackerTodayProvider), day6,
          reason: 'the day did roll over');
      expect(
          container
              .read(trackerResultProvider(
                  TrackerQueries.dayTotals([cig.id], day6)))
              .hasValue,
          isFalse,
          reason: "and the new day's totals are still being asked");

      expect(container.read(trackerTotalsProvider).value, {cig.id: 2.0});

      held.complete(const TrackerResult(buckets: [], sum: 0, count: 0));
      await until(() => states.last.value?.isEmpty ?? false,
          "the new day's map");
      expectNeverLosesItsValue(states);
    });

    test('show the last map while a changed tracker list is asked about',
        () async {
      // Adding, archiving or reordering a tracker changes the ids, and so
      // the question.
      await start();
      final states = record(trackerTotalsProvider);
      await until(() => states.last.hasValue, 'the first answer');

      final w = await repo.create(water);
      await until(() => container.read(trackersProvider).value?.length == 2,
          'the tab to list the new tracker');
      container.read(trackerTotalsProvider);
      final asked = TrackerQueries.dayTotals([
        for (final tracker in container.read(trackersProvider).requireValue)
          tracker.id,
      ], day5);
      expect(asked.trackerIds, contains(w.id));
      await until(() => container.read(trackerResultProvider(asked)).hasValue,
          'the new question to be answered');
      await container.pump();

      expectNeverLosesItsValue(states);
      expect(states.last.value, {cig.id: 2.0});
    });

    test("let the old day's question go once the new day's lands", () async {
      // Kept alive across tab visits, but not one question per day forever.
      await start();
      final states = record(trackerTotalsProvider);
      await until(() => states.last.hasValue, 'the first answer');
      final yesterday =
          trackerResultProvider(TrackerQueries.dayTotals([cig.id], day5));
      expect(container.exists(yesterday), isTrue);

      fake.advance(const Duration(days: 1));
      container.read(trackerTodayProvider.notifier).refresh();
      await until(() => states.last.value?.isEmpty ?? false,
          "the new day's map");
      await container.pump();

      expect(container.exists(yesterday), isFalse);
      expect(
          container.exists(trackerResultProvider(
              TrackerQueries.dayTotals([cig.id], day6))),
          isTrue);
    });
  });
}
