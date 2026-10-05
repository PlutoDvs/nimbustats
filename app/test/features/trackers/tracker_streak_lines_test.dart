import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/application/tracker_providers.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late TrackerRepository repo;

  setUp(() {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    repo = repositoryFor(db, fake);
  });
  tearDown(() => db.close());

  Future<void> openDetail(WidgetTester tester, String id,
          {Locale locale = const Locale('en'),
          List<Override> overrides = const []}) =>
      pumpApp(tester,
          database: db,
          initialLocation: trackerLocation(id),
          locale: locale,
          overrides: [...trackerOverrides(fake), ...overrides]);

  /// One entry [daysAgo] days before the fake's now, on that local day.
  Future<void> logDaysAgo(Tracker tracker, int daysAgo) => repo.logEntry(
      tracker.id,
      at: fake.nowUtc.subtract(Duration(days: daysAgo)));

  /// The keyed Text's own string. The fixture's textIn looks for a Text below
  /// the key, and these keys sit on the Text itself.
  String line(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('a run that includes today', (tester) async {
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    for (final days in [2, 1, 0]) {
      await logDaysAgo(cig, days);
    }

    await openDetail(tester, cig.id);

    expect(line(tester, 'tracker-streak'), '3 days in a row · best 3');
    expect(line(tester, 'tracker-last-entry'), 'Last entry: today');
  });

  testWidgets('one day reads in the singular', (tester) async {
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);

    await openDetail(tester, cig.id);

    expect(line(tester, 'tracker-streak'), '1 day in a row · best 1');
  });

  testWidgets("today with nothing yet keeps yesterday's run", (tester) async {
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 2);
    await logDaysAgo(cig, 1);

    await openDetail(tester, cig.id);

    expect(line(tester, 'tracker-streak'), '2 days in a row · best 2');
    expect(line(tester, 'tracker-last-entry'), 'Last entry: yesterday');
  });

  testWidgets('a broken run leaves only the best', (tester) async {
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 6);
    await logDaysAgo(cig, 5);

    await openDetail(tester, cig.id);

    expect(line(tester, 'tracker-streak'), 'Best: 2 days');
    expect(line(tester, 'tracker-last-entry'), 'Last entry: 5 days ago');
  });

  testWidgets("a boolean's done days make its streak", (tester) async {
    await useEnglishDigits(db);
    final g = await repo.create(gym);
    await logDaysAgo(g, 1);
    await logDaysAgo(g, 0);

    await openDetail(tester, g.id);

    expect(line(tester, 'tracker-streak'), '2 days in a row · best 2');
  });

  testWidgets('a tracker never logged shows neither line', (tester) async {
    final cig = await repo.create(cigarettes);

    await openDetail(tester, cig.id);

    expect(find.byKey(const Key('tracker-streak')), findsNothing);
    expect(find.byKey(const Key('tracker-last-entry')), findsNothing);
  });

  testWidgets('a tap moves both lines', (tester) async {
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 1);
    await openDetail(tester, cig.id);
    expect(line(tester, 'tracker-last-entry'), 'Last entry: yesterday');

    await tester.tap(find.descendant(
        of: find.byKey(const Key('tracker-quick-log')),
        matching: find.byType(InkWell)));
    await tester.pumpAndSettle();

    expect(line(tester, 'tracker-streak'), '2 days in a row · best 2');
    expect(line(tester, 'tracker-last-entry'), 'Last entry: today');
  });

  testWidgets('left open across midnight, today becomes yesterday',
      (tester) async {
    // Review Focus 4.
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    await openDetail(tester, cig.id);
    expect(line(tester, 'tracker-last-entry'), 'Last entry: today');

    fake.advance(const Duration(days: 1));
    await backgroundAndResume(tester);
    await tester.pumpAndSettle();

    expect(line(tester, 'tracker-last-entry'), 'Last entry: yesterday');
    expect(line(tester, 'tracker-streak'), '1 day in a row · best 1');
  });

  testWidgets('Persian digits and words', (tester) async {
    final cig = await repo.create(cigarettes);
    for (final days in [2, 1, 0]) {
      await logDaysAgo(cig, days);
    }

    await openDetail(tester, cig.id, locale: const Locale('fa'));

    expect(line(tester, 'tracker-streak'), '۳ روز پشت سر هم · بهترین ۳');
    expect(line(tester, 'tracker-last-entry'), 'آخرین ثبت: امروز');
  });

  testWidgets('a failed streak says so, with a retry', (tester) async {
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);

    await openDetail(tester, cig.id, overrides: [
      trackerResultProvider(TrackerQueries.loggedDays(cig.id)).overrideWith(
          (ref) => Future<TrackerResult>.error(Exception('boom'))),
    ]);

    expect(find.byKey(const Key('tracker-streak-error')), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets('at twice the font size the header overflows nothing',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    for (final days in [2, 1, 0]) {
      await logDaysAgo(cig, days);
    }

    await openDetail(tester, cig.id);

    expect(tester.takeException(), isNull);
  });
}
