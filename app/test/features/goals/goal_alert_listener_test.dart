import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/application/goal_providers.dart';
import 'package:nimbustats/features/trackers/data/tracker_clock.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import '../trackers/support/tracker_fixture.dart';
import 'support/goal_test_app.dart';

void main() {
  const day5 = DateKey(20261005);

  /// The watcher's 300 ms debounce, and the evaluation after it.
  Future<void> letTheWatcherRun(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  /// A snackbar's four seconds, and its exit.
  Future<void> letASnackbarGo(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  group('on the real clock', () {
    // The add-expense screen and the tracker's quick log stamp "now", so
    // these goals stand on the real today too.
    late AppDatabase db;
    late GoalService service;
    const clock = TrackerClock();

    setUp(() {
      db = AppDatabase.openInMemory();
      service = goalServiceFor(db, clock.today);
    });
    tearDown(() => db.close());

    testWidgets(
        "a crossing from the add-expense screen alerts once, after its own "
        "'Saved'", (tester) async {
      // Review Focus 4.
      await useEnglishDigits(db);
      await service.save(spendingCap(
          id: 'all', name: 'Everything', paths: const [], since: clock.today()));
      await pumpApp(tester, database: db, seedFirstRun: true);

      await tester.tap(find.byKey(const Key('tx-add-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '900000');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();
      await letTheWatcherRun(tester);

      const message = "Everything: 90% of this month's limit";
      expect(find.text('Saved'), findsOneWidget,
          reason: "the save's own snackbar is not cut short");
      expect(find.text(message), findsNothing, reason: 'the alert waits');

      await letASnackbarGo(tester);
      expect(find.text('Saved'), findsNothing);
      expect(find.text(message), findsOneWidget);

      await letASnackbarGo(tester);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing, reason: 'shown once, only');
    });

    testWidgets("a crossing from a tracker's detail waits behind its Undo",
        (tester) async {
      await useEnglishDigits(db);
      final trackers = TrackerRepository(db.trackersDao, db.trackerEntriesDao,
          AnalyticsEngine(db, calendar: const JalaliCalendar()), clock);
      final cig = await trackers.create(cigarettes);
      await service.save(habitGoal(cig,
          id: 'smoke', target: 1, alerts: const [100], since: clock.today()));
      await pumpApp(tester, database: db, initialLocation: trackersRoute);
      await tester.tap(find.byKey(Key('tracker-tile-${cig.id}')));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
          of: find.byKey(const Key('tracker-quick-log')),
          matching: find.byType(InkWell)));
      await tester.pumpAndSettle();
      await letTheWatcherRun(tester);

      // One log against a limit of one is exactly the cap: reached, not over.
      const message = "Cigarettes: reached today's limit";
      expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget,
          reason: "the tap's undo stays in reach");
      expect(find.text(message), findsNothing);

      // The undo bar's five seconds.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
    });
  });

  group('on a fake clock', () {
    late FakeClock fake;
    late AppDatabase db;
    late GoalService service;

    setUp(() async {
      fake = FakeClock();
      db = AppDatabase.openInMemory();
      service = goalServiceFor(db, fake.clock.today);
      await seedCategories(db);
    });
    tearDown(() => db.close());

    testWidgets('crossings made while the app was closed queue, each once',
        (tester) async {
      await useEnglishDigits(db);
      await service.save(spendingCap());
      await service.save(
          spendingCap(id: 'fuel', name: 'Fuel', paths: const [transportPath]));
      await spend(db, 850000, day5);
      await spend(db, 1200000, day5, category: 'seed-transport');

      await pumpGoals(tester, db, fake);
      await letTheWatcherRun(tester);

      const dining = "Dining out: 85% of this month's limit";
      const fuel = "Fuel: over this month's limit";
      expect(find.text(dining), findsOneWidget);
      expect(find.text(fuel), findsNothing, reason: 'queued behind the first');

      await letASnackbarGo(tester);
      expect(find.text(dining), findsNothing);
      expect(find.text(fuel), findsOneWidget);

      await letASnackbarGo(tester);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text(dining), findsNothing);
      expect(find.text(fuel), findsNothing);
    });

    testWidgets("View opens the goal's detail", (tester) async {
      await useEnglishDigits(db);
      await service.save(spendingCap());
      await spend(db, 850000, day5);
      await pumpGoals(tester, db, fake);
      await letTheWatcherRun(tester);

      await tester.tap(find.widgetWithText(SnackBarAction, 'View'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('goal-detail')), findsOneWidget);
    });

    testWidgets("the goals' day moves at midnight and on resume",
        (tester) async {
      late ProviderContainer container;
      await pumpGoals(tester, db, fake, onContainer: (c) => container = c);
      expect(container.read(goalTodayProvider), day5);

      // 12:30 in Tehran: midnight is eleven and a half hours away.
      fake.advance(const Duration(hours: 12));
      await tester.pump(const Duration(hours: 12));
      expect(container.read(goalTodayProvider), const DateKey(20261006));

      fake.advance(const Duration(days: 1));
      await backgroundAndResume(tester);
      expect(container.read(goalTodayProvider), const DateKey(20261007));
    });
  });
}
