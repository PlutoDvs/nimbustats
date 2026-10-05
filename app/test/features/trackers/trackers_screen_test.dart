import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/application/tracker_providers.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  setUp(() => fake = FakeClock());

  Future<void> openTab(WidgetTester tester, AppDatabase db,
          {Locale locale = const Locale('en')}) =>
      pumpApp(tester,
          database: db,
          initialLocation: trackersRoute,
          locale: locale,
          overrides: trackerOverrides(fake));

  Future<AppDatabase> freshDb() async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    return db;
  }

  testWidgets('loading shows a skeleton, never a spinner', (tester) async {
    final never = StreamController<List<Tracker>>();
    addTearDown(never.close);
    await pumpApp(tester, initialLocation: trackersRoute, overrides: [
      ...trackerOverrides(fake),
      trackersProvider.overrideWith((ref) => never.stream),
    ]);

    expect(find.byType(NimbusLoadingList), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the error state retries and hides the raw exception',
      (tester) async {
    await pumpApp(tester, initialLocation: trackersRoute, overrides: [
      ...trackerOverrides(fake),
      trackersProvider.overrideWith(
          (ref) => Stream<List<Tracker>>.error(Exception('boom'))),
    ]);

    expect(find.byType(NimbusErrorState), findsOneWidget);
    expect(find.text('Could not load trackers'), findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('the empty state explains trackers and offers four presets',
      (tester) async {
    await openTab(tester, await freshDb());

    expect(find.text('Track more than money'), findsOneWidget);
    for (final (slug, name) in const [
      ('water', 'Water'),
      ('cigarettes', 'Cigarettes'),
      ('gym', 'Gym'),
      ('sleep', 'Sleep'),
    ]) {
      expect(
          find.descendant(
              of: find.byKey(Key('tracker-preset-$slug')),
              matching: find.text(name)),
          findsOneWidget);
    }
    // Nothing chosen yet, so nothing to add.
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('tracker-presets-add')))
            .onPressed,
        isNull);
  });

  testWidgets('choosing presets creates exactly those, in their order',
      (tester) async {
    final db = await freshDb();
    await openTab(tester, db);

    await tester.tap(find.byKey(const Key('tracker-preset-gym')));
    await tester.tap(find.byKey(const Key('tracker-preset-water')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tracker-presets-add')));
    await tester.pumpAndSettle();

    final stored =
        await firstOf(tester, repositoryFor(db, fake).watchTrackers());
    expect(stored.map((t) => t.name), ['Water', 'Gym']);
    expect(stored.first.unit, 'L');
    expect(stored.first.perTapValue, 0.25);
    expect(find.byKey(Key('tracker-tile-${stored.first.id}')), findsOneWidget);
    expect(find.text('Track more than money'), findsNothing);
  });

  testWidgets('the presets are offered in Persian in Persian', (tester) async {
    await openTab(tester, await freshDb(), locale: const Locale('fa'));
    for (final name in ['آب', 'سیگار', 'باشگاه', 'خواب']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
  });

  group('populated', () {
    testWidgets("each tile shows today's total in the tracker's own terms",
        (tester) async {
      final db = await freshDb();
      await useEnglishDigits(db);
      final repo = repositoryFor(db, fake);
      final [cig, g, w, s] = await repo.createAll([cigarettes, gym, water, sleep]);
      for (var i = 0; i < 3; i++) {
        await repo.logEntry(cig.id);
        await repo.logEntry(w.id);
      }
      await repo.logEntry(cig.id,
          at: fake.nowUtc.subtract(const Duration(days: 1))); // yesterday
      await repo.addDuration(s.id, const Duration(minutes: 90));

      await openTab(tester, db);

      expect(textIn(tester, Key('tracker-total-${cig.id}')), '3 today');
      expect(textIn(tester, Key('tracker-total-${g.id}')), 'Not done today');
      expect(textIn(tester, Key('tracker-total-${w.id}')), '0.75 L today');
      expect(textIn(tester, Key('tracker-total-${s.id}')), '1:30 today');
    });

    testWidgets('Persian digits, right to left, in Persian', (tester) async {
      final db = await freshDb();
      final repo = repositoryFor(db, fake);
      final cig = await repo.create(cigarettes);
      for (var i = 0; i < 3; i++) {
        await repo.logEntry(cig.id);
      }

      await openTab(tester, db, locale: const Locale('fa'));

      expect(textIn(tester, Key('tracker-total-${cig.id}')), 'امروز ۳');
      expect(
          Directionality.of(
              tester.element(find.byKey(Key('tracker-tile-${cig.id}')))),
          TextDirection.rtl);
    });

    testWidgets('the first tracker sits lowest, in the bottom third',
        (tester) async {
      final db = await freshDb();
      final [cig, g, w] =
          await repositoryFor(db, fake).createAll([cigarettes, gym, water]);

      await openTab(tester, db);

      double centreOf(Tracker t) =>
          tester.getCenter(find.byKey(Key('tracker-tile-${t.id}'))).dy;
      final height =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(centreOf(cig), greaterThan(centreOf(g)));
      expect(centreOf(g), greaterThan(centreOf(w)));
      expect(centreOf(cig), greaterThan(height * 2 / 3));
    });

    testWidgets('archived trackers stay off the tab', (tester) async {
      final db = await freshDb();
      final repo = repositoryFor(db, fake);
      final [cig, g] = await repo.createAll([cigarettes, gym]);
      await repo.archive(g.id);

      await openTab(tester, db);

      expect(find.byKey(Key('tracker-tile-${cig.id}')), findsOneWidget);
      expect(find.byKey(Key('tracker-tile-${g.id}')), findsNothing);
    });
  });

  group('dynamic type', () {
    // Screen contract §1.4. Set on the platform dispatcher rather than in a
    // local MediaQuery, so it reaches the real tree the way a device-wide
    // setting does -- the approach card_previews_test.dart takes.
    testWidgets('a populated tab at twice the font size overflows nothing',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final db = await freshDb();
      await useEnglishDigits(db);
      final repo = repositoryFor(db, fake);
      final [_, _, w, _] =
          await repo.createAll([cigarettes, gym, water, sleep]);
      await repo.logEntry(w.id, value: 1234.5);

      await openTab(tester, db);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the Persian empty state at twice the font size overflows '
        'nothing', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openTab(tester, await freshDb(), locale: const Locale('fa'));

      expect(tester.takeException(), isNull);
    });
  });

  group('a new day', () {
    testWidgets('at local midnight the totals move to the new day',
        (tester) async {
      fake = FakeClock(nowUtc: DateTime.utc(2026, 10, 5, 20, 29, 30)); // 23:59:30
      final db = await freshDb();
      await useEnglishDigits(db);
      final repo = repositoryFor(db, fake);
      final cig = await repo.create(cigarettes);
      for (var i = 0; i < 3; i++) {
        await repo.logEntry(cig.id);
      }
      await openTab(tester, db);
      expect(textIn(tester, Key('tracker-total-${cig.id}')), '3 today');

      fake.advance(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(textIn(tester, Key('tracker-total-${cig.id}')), '0 today');
    });

    testWidgets('coming back to the app on a new day shows the new day',
        (tester) async {
      final db = await freshDb();
      await useEnglishDigits(db);
      final repo = repositoryFor(db, fake);
      final cig = await repo.create(cigarettes);
      await repo.logEntry(cig.id);
      await repo.logEntry(cig.id);
      await openTab(tester, db);
      expect(textIn(tester, Key('tracker-total-${cig.id}')), '2 today');

      fake.advance(const Duration(days: 1));
      await backgroundAndResume(tester);
      await tester.pumpAndSettle();

      expect(textIn(tester, Key('tracker-total-${cig.id}')), '0 today');
    });
  });
}
