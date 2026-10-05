import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late TrackerRepository repo;
  late Tracker cig;
  late Tracker g;

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    await useEnglishDigits(db);
    repo = repositoryFor(db, fake);
    [cig, g] = await repo.createAll([cigarettes, gym]);
  });
  tearDown(() => db.close());

  Future<void> openTab(WidgetTester tester) => pumpApp(tester,
      database: db,
      initialLocation: trackersRoute,
      overrides: trackerOverrides(fake));

  Finder action(Tracker t) => find.byKey(Key('tracker-action-${t.id}'));
  Future<int> count(Tracker t) async =>
      (await repo.entriesPage(t.id, limit: 1000)).items.length;

  group('counter', () {
    testWidgets('one tap adds one cigarette and says so', (tester) async {
      await openTab(tester);
      await tester.tap(action(cig));
      await tester.pumpAndSettle();

      expect(await count(cig), 1);
      expect(textIn(tester, Key('tracker-total-${cig.id}')), '1 today');
      expect(find.text('Cigarettes · 1 today'), findsOneWidget);
    });

    testWidgets('a tap fires a light haptic', (tester) async {
      final haptics = captureHaptics(tester);
      await openTab(tester);
      await tester.tap(action(cig));
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('each tap replaces the snackbar instead of queueing behind it',
        (tester) async {
      await openTab(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(action(cig));
        await tester.pumpAndSettle();
      }
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Cigarettes · 3 today'), findsOneWidget);
    });

    testWidgets("the snackbar leaves the first tracker's button uncovered",
        (tester) async {
      // The list is anchored to the bottom and every tap shows a snackbar
      // there. If the two overlapped, the second tap of a run would land on
      // the snackbar -- on its Undo, even -- instead of on +1.
      await openTab(tester);
      await tester.tap(action(cig));
      await tester.pumpAndSettle();

      final snackBar = tester.getRect(find.byType(SnackBar));
      expect(snackBar.overlaps(tester.getRect(action(cig))), isFalse,
          reason: 'snackbar $snackBar, button ${tester.getRect(action(cig))}');
    });

    testWidgets('the undo bar leaves after its five seconds', (tester) async {
      await openTab(tester);
      await tester.tap(action(cig));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('undo removes exactly the entry that tap logged',
        (tester) async {
      await openTab(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(action(cig));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(await count(cig), 2);
      expect(textIn(tester, Key('tracker-total-${cig.id}')), '2 today');
    });
  });

  group('boolean', () {
    testWidgets('a tap marks gym done for today, with a medium haptic',
        (tester) async {
      final haptics = captureHaptics(tester);
      await openTab(tester);
      await tester.tap(action(g));
      await tester.pumpAndSettle();

      expect(textIn(tester, Key('tracker-total-${g.id}')), 'Done today');
      expect(find.text('Gym · done today'), findsOneWidget);
      expect(haptics, ['HapticFeedbackType.mediumImpact']);
    });

    testWidgets('a tap on a done gym takes it back, and undo restores it',
        (tester) async {
      await openTab(tester);
      await tester.tap(action(g));
      await tester.pumpAndSettle();
      await tester.tap(action(g));
      await tester.pumpAndSettle();

      expect(textIn(tester, Key('tracker-total-${g.id}')), 'Not done today');
      expect(find.text('Gym · not done today'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(textIn(tester, Key('tracker-total-${g.id}')), 'Done today');
      expect(await count(g), 1);
    });

    testWidgets('a double-tap logs done once', (tester) async {
      await openTab(tester);
      // No pump between the taps: the second lands before the tile has
      // rebuilt as done, exactly as a fast double-tap would.
      await tester.tap(action(g));
      await tester.tap(action(g));
      await tester.pumpAndSettle();

      expect(await count(g), 1);
      expect(textIn(tester, Key('tracker-total-${g.id}')), 'Done today');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the buttons say what they do to a screen reader',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openTab(tester);

    expect(
        tester.getSemantics(action(cig)),
        isSemantics(
            label: 'Add one to Cigarettes', isButton: true, hasTapAction: true));
    expect(tester.getSemantics(action(g)),
        isSemantics(label: 'Mark Gym done', isButton: true));

    await tester.tap(action(g));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(action(g)),
        isSemantics(label: 'Mark Gym not done'));
    semantics.dispose();
  });

  testWidgets('the action is at least a minimum tap target', (tester) async {
    await openTab(tester);
    final size = tester.getSize(action(cig));
    expect(size.width, greaterThanOrEqualTo(NimbusTokens.minTapTarget));
    expect(size.height, greaterThanOrEqualTo(NimbusTokens.minTapTarget));
  });

  testWidgets('a failure right after a logged tap is still said',
      (tester) async {
    // The first tap's undo bar is up when the second write fails. The
    // failure must replace it, not queue behind it where nobody sees it.
    await openTab(tester);
    await tester.tap(action(cig));
    await tester.pumpAndSettle();
    await db.customStatement(
        'CREATE TEMP TRIGGER fail_entry BEFORE INSERT ON tracker_entries '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END");

    Object? caught;
    await runZonedGuarded(() async {
      await tester.tap(action(cig));
      await tester.pumpAndSettle();
    }, (error, stack) => caught = error);

    expect(find.text('Could not save. Try again.'), findsOneWidget);
    expect(caught, isNotNull);
  });

  testWidgets('a failed write says so and still reaches the error handler',
      (tester) async {
    // A write failure injected where SQLite itself would raise one.
    await db.customStatement(
        'CREATE TEMP TRIGGER fail_entry BEFORE INSERT ON tracker_entries '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END");
    await openTab(tester);

    // Caught here because it comes from a detached future the tap never
    // awaits, which is how it reaches the framework's handler in the app.
    Object? caught;
    await runZonedGuarded(() async {
      await tester.tap(action(cig));
      await tester.pumpAndSettle();
    }, (error, stack) => caught = error);

    expect(find.text('Could not save. Try again.'), findsOneWidget);
    expect(caught, isNotNull);
    expect(await count(cig), 0);
  });
}
