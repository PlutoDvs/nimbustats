import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';
import 'package:nimbustats/features/trackers/application/tracker_insights_controller.dart';
import 'package:nimbustats/features/trackers/application/tracker_providers.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late TrackerRepository repo;

  const october = DateRange(DateKey(20261001), DateKey(20261031));

  setUp(() {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    repo = repositoryFor(db, fake);
  });
  tearDown(() => db.close());

  /// English digits and the Gregorian calendar: October 2026 is the month on
  /// screen, with concrete numbers to assert.
  Future<void> useGregorianEnglish({int? firstDayOfWeek}) =>
      SettingsRepository(db.settingsDao).save(AppSettings.defaults.copyWith(
          locale: const Locale('en'),
          calendarKind: CalendarKind.gregorian,
          firstDayOfWeek:
              firstDayOfWeek ?? AppSettings.defaults.firstDayOfWeek));

  Future<void> openInsights(WidgetTester tester, String id,
      {Locale locale = const Locale('en'),
      List<Override> overrides = const []}) async {
    await pumpApp(tester,
        database: db,
        initialLocation: trackerLocation(id),
        locale: locale,
        overrides: [...trackerOverrides(fake), ...overrides]);
    await tester.tap(find.byKey(const Key('tracker-tab-insights')));
    await tester.pumpAndSettle();
  }

  Future<void> logDaysAgo(Tracker tracker, int daysAgo, {double? value}) =>
      repo.logEntry(tracker.id,
          value: value, at: fake.nowUtc.subtract(Duration(days: daysAgo)));

  List<double> barsOf(WidgetTester tester, String key) => [
        for (final group in tester
            .widget<BarChart>(find.descendant(
                of: find.byKey(Key(key)), matching: find.byType(BarChart)))
            .data
            .barGroups)
          group.barRods.single.toY,
      ];

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('Insights opens on this month, with the quick log kept',
      (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);

    await openInsights(tester, cig.id);

    expect(textOf(tester, 'tracker-range-label'), '2026/10');
    expect(find.byKey(const Key('tracker-quick-log')), findsOneWidget);
  });

  testWidgets('a month draws a bar a day and says the total and the average',
      (tester) async {
    await useGregorianEnglish();
    final w = await repo.create(water);
    for (var i = 0; i < 3; i++) {
      await logDaysAgo(w, 0);
    }
    await logDaysAgo(w, 2, value: 0.5);

    await openInsights(tester, w.id);

    final bars = barsOf(tester, 'tracker-history-chart');
    expect(bars, hasLength(31));
    expect(bars[2], 0.5);
    expect(bars[4], 0.75);
    // 1.25 L over the five days of October begun so far.
    expect(textOf(tester, 'tracker-history-caption'),
        '1.25 L in all · 0.25 L a day');
  });

  testWidgets('a boolean says on how many days it was done', (tester) async {
    await useGregorianEnglish();
    final g = await repo.create(gym);
    await logDaysAgo(g, 0);
    await logDaysAgo(g, 2);

    await openInsights(tester, g.id);

    expect(textOf(tester, 'tracker-history-caption'), 'Done on 2 of 5 days');
  });

  testWidgets('a week draws seven days and a year twelve months',
      (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    await openInsights(tester, cig.id);

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    // Saturday-first, so Monday the 5th is the third bar.
    expect(textOf(tester, 'tracker-range-label'), '2026/10/03 – 2026/10/09');
    expect(barsOf(tester, 'tracker-history-chart'),
        [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0]);

    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'tracker-range-label'), '2026');
    final months = barsOf(tester, 'tracker-history-chart');
    expect(months, hasLength(12));
    expect(months[9], 1);
  });

  testWidgets('earlier and later move the range, never past today',
      (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    await openInsights(tester, cig.id);

    IconButton next() =>
        tester.widget<IconButton>(find.byKey(const Key('tracker-range-next')));
    expect(next().onPressed, isNull);

    await tester.tap(find.byKey(const Key('tracker-range-previous')));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'tracker-range-label'), '2026/09');
    expect(next().onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('tracker-range-next')));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'tracker-range-label'), '2026/10');
  });

  testWidgets('a range with nothing in it says so', (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    await openInsights(tester, cig.id);

    await tester.tap(find.byKey(const Key('tracker-range-previous')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tracker-history-empty')), findsOneWidget);
  });

  testWidgets('a tracker never logged shows one empty state', (tester) async {
    final cig = await repo.create(cigarettes);

    await openInsights(tester, cig.id);

    expect(find.byKey(const Key('tracker-insights-empty')), findsOneWidget);
    expect(find.byKey(const Key('tracker-history-chart')), findsNothing);
  });

  testWidgets('the chart loads on its own', (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    final never = Completer<TrackerResult>();

    await openInsights(tester, cig.id, overrides: [
      trackerResultProvider(TrackerQueries.byDay(cig.id, october))
          .overrideWith((ref) => never.future),
    ]);

    expect(find.byKey(const Key('tracker-history-loading')), findsOneWidget);
    expect(find.byKey(const Key('tracker-range-label')), findsOneWidget);
  });

  testWidgets('a failed chart retries and hides the raw exception',
      (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);

    await openInsights(tester, cig.id, overrides: [
      trackerResultProvider(TrackerQueries.byDay(cig.id, october)).overrideWith(
          (ref) => Future<TrackerResult>.error(Exception('boom'))),
    ]);

    expect(
        find.descendant(
            of: find.byKey(const Key('tracker-history-error')),
            matching: find.byType(NimbusErrorState)),
        findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
  });

  testWidgets('the chart speaks its numbers', (tester) async {
    final semantics = tester.ensureSemantics();
    await useGregorianEnglish();
    final w = await repo.create(water);
    for (var i = 0; i < 3; i++) {
      await logDaysAgo(w, 0);
    }
    await logDaysAgo(w, 2, value: 0.5);

    await openInsights(tester, w.id);

    expect(
        find.bySemanticsLabel(
            'Water, 2026/10: 1.25 L in all; most on 2026/10/05, 0.75 L'),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets('switching the calendar re-anchors the range', (tester) async {
    // Review Focus 5.
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    await openInsights(tester, cig.id);
    expect(textOf(tester, 'tracker-range-label'), '1405/07');

    // A settings write made while the app is watching the stream needs the
    // fake clock pumped for it to finish; runAsync alone waits forever.
    var saved = false;
    final save = useGregorianEnglish().then((_) => saved = true);
    for (var i = 0; i < 200 && !saved; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await save;
    await tester.pumpAndSettle();

    expect(textOf(tester, 'tracker-range-label'), '2026/10');
    expect(barsOf(tester, 'tracker-history-chart'), hasLength(31));
  });

  testWidgets('Persian digits on the range', (tester) async {
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);

    await openInsights(tester, cig.id, locale: const Locale('fa'));

    expect(textOf(tester, 'tracker-range-label'), '۱۴۰۵/۰۷');
  });

  testWidgets('at twice the font size Insights overflows nothing',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await useGregorianEnglish();
    final w = await repo.create(water);
    await logDaysAgo(w, 0, value: 1234.5);

    await openInsights(tester, w.id);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the range controls are full-size tap targets', (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    await openInsights(tester, cig.id);

    for (final finder in [
      find.byKey(const Key('tracker-range-previous')),
      find.byKey(const Key('tracker-range-next')),
      find.byType(SegmentedButton<TrackerRangeKind>),
    ]) {
      expect(tester.getSize(finder).height,
          greaterThanOrEqualTo(NimbusTokens.minTapTarget),
          reason: '$finder');
    }
  });
}
