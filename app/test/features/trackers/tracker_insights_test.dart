import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:nimbustats/features/trackers/presentation/tracker_detail_screen.dart';
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

  /// The value-axis labels a chart draws, bottom to top.
  List<String> axisLabelsOf(WidgetTester tester, String chartKey) => [
        for (final label in tester.widgetList<Text>(find.descendant(
            of: find.byKey(Key(chartKey)),
            matching: find.byWidgetPredicate((widget) =>
                widget is Text &&
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>)
                    .value
                    .startsWith('tracker-axis-label-')))))
          label.data!,
      ];

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

  group('the value axis steps in whole units', () {
    // Left to itself, fl_chart steps a 152-pixel axis in "round" fractions:
    // half a "done", half a cigarette, 1000 seconds.
    testWidgets('a boolean counts days done, never half of one',
        (tester) async {
      await useGregorianEnglish();
      final g = await repo.create(gym);
      await logDaysAgo(g, 0);
      await logDaysAgo(g, 2);

      await openInsights(tester, g.id);

      expect(axisLabelsOf(tester, 'tracker-history-chart'), ['0', '1'],
          reason: 'no 0.5');
    });

    testWidgets('a counter peaking at 2 steps by one', (tester) async {
      await useGregorianEnglish();
      final cig = await repo.create(cigarettes);
      await logDaysAgo(cig, 0);
      await logDaysAgo(cig, 0);
      await logDaysAgo(cig, 3);

      await openInsights(tester, cig.id);

      expect(axisLabelsOf(tester, 'tracker-history-chart'), ['0', '1', '2'],
          reason: 'no 0.5 or 1.5');
    });

    testWidgets('an hour steps in half hours', (tester) async {
      await useGregorianEnglish();
      final s = await repo.create(sleep);
      await repo.addDuration(s.id, const Duration(hours: 1));

      await openInsights(tester, s.id);

      expect(axisLabelsOf(tester, 'tracker-history-chart'),
          ['0:00', '0:30', '1:00'],
          reason: 'no 0:16, 0:33 or 0:50');
    });
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

  /// The screen's own loading view replaces the whole Scaffold, tabs and all,
  /// so the tabs being gone is the proof it is showing.
  bool screenIsLoading() =>
      find.byKey(const Key('tracker-tab-insights')).evaluate().isEmpty;

  testWidgets('a new day keeps the screen, the tab and the chosen range',
      (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    // The new day's total is a new question, so it has no earlier answer to
    // show while it loads. Held open here, as it is on a slow device.
    final never = Completer<TrackerResult>();
    await openInsights(tester, cig.id, overrides: [
      trackerResultProvider(
              TrackerQueries.dayTotal(cig.id, const DateKey(20261006)))
          .overrideWith((ref) => never.future),
    ]);
    await tester.tap(find.byKey(const Key('tracker-range-previous')));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'tracker-range-label'), '2026/09');

    // Local midnight: the rollover timer fires and today becomes the 6th.
    fake.advance(const Duration(days: 1));
    await tester.pump(const Duration(days: 1));
    await tester.pump();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackerDetailScreen)));
    expect(container.read(trackerTodayProvider), const DateKey(20261006),
        reason: 'the day did roll over');
    expect(container.read(trackerDayTotalProvider(cig.id)).isLoading, isTrue,
        reason: 'and the new day total is still being asked');

    expect(screenIsLoading(), isFalse,
        reason: 'the screen swapped for its loading view');
    expect(textOf(tester, 'tracker-range-label'), '2026/09');
    expect(find.byKey(const Key('tracker-quick-log')), findsOneWidget);
  });

  testWidgets('switching the calendar never replaces the screen with loading',
      (tester) async {
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    await openInsights(tester, cig.id);

    var frames = 0;
    var loadingFrames = 0;
    var saved = false;
    final save = useGregorianEnglish().then((_) => saved = true);
    for (var i = 0; i < 200 && !saved; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      frames++;
      if (screenIsLoading()) loadingFrames++;
    }
    await save;
    await tester.pumpAndSettle();

    expect(textOf(tester, 'tracker-range-label'), '2026/10');
    expect(loadingFrames, 0,
        reason: 'the screen showed its loading view in $loadingFrames of '
            '$frames frames');
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

  /// Scrolls the Insights list until [key] is on screen: the patterns sit
  /// below the history chart.
  Future<void> scrollTo(WidgetTester tester, String key) =>
      tester.scrollUntilVisible(find.byKey(Key(key)), 200,
          scrollable: find.descendant(
              of: find.byKey(const Key('tracker-insights')),
              matching: find.byType(Scrollable)));

  group('patterns', () {
    /// Two cigarettes now (12:30 in Tehran) and one at 07:30, all on Monday
    /// 5 October.
    Future<Tracker> cigarettesAtNoonAndDawn() async {
      final cig = await repo.create(cigarettes);
      await repo.logEntry(cig.id);
      await repo.logEntry(cig.id);
      await repo.logEntry(cig.id,
          at: fake.nowUtc.subtract(const Duration(hours: 5)));
      return cig;
    }

    testWidgets("the hours are local, from each entry's own offset",
        (tester) async {
      await useGregorianEnglish();
      final cig = await cigarettesAtNoonAndDawn();
      await openInsights(tester, cig.id);
      await scrollTo(tester, 'tracker-hour-chart');

      final hours = barsOf(tester, 'tracker-hour-chart');
      expect(hours, hasLength(24));
      expect(hours[12], 2);
      expect(hours[7], 1);
    });

    testWidgets("a duration's hours are its start times, and it says so",
        (tester) async {
      await useGregorianEnglish();
      final s = await repo.create(sleep);
      await repo.addDuration(s.id, const Duration(minutes: 30));
      await openInsights(tester, s.id);
      await scrollTo(tester, 'tracker-hour-chart');

      expect(find.text('Time of day · by start time'), findsOneWidget);
    });

    testWidgets("weekdays run in the user's week, Saturday first",
        (tester) async {
      await useGregorianEnglish();
      final cig = await cigarettesAtNoonAndDawn();
      await openInsights(tester, cig.id);
      await scrollTo(tester, 'tracker-weekday-chart');

      expect(barsOf(tester, 'tracker-weekday-chart'),
          [0.0, 0.0, 3.0, 0.0, 0.0, 0.0, 0.0]);
      expect(textOf(tester, 'tracker-weekday-label-0'), 'Sat');
    });

    testWidgets('a Monday week start moves Monday to the front',
        (tester) async {
      await useGregorianEnglish(firstDayOfWeek: DateTime.monday);
      final cig = await cigarettesAtNoonAndDawn();
      await openInsights(tester, cig.id);
      await scrollTo(tester, 'tracker-weekday-chart');

      expect(barsOf(tester, 'tracker-weekday-chart').first, 3);
      expect(textOf(tester, 'tracker-weekday-label-0'), 'Mon');
    });

    testWidgets('both patterns speak their peaks', (tester) async {
      final semantics = tester.ensureSemantics();
      await useGregorianEnglish();
      final cig = await cigarettesAtNoonAndDawn();
      await openInsights(tester, cig.id);

      await scrollTo(tester, 'tracker-hour-chart');
      expect(
          find.bySemanticsLabel(
              'Cigarettes by time of day, 2026/10: most around 12:00, 2'),
          findsOneWidget);
      await scrollTo(tester, 'tracker-weekday-chart');
      expect(
          find.bySemanticsLabel(
              'Cigarettes by day of week, 2026/10: most on Mon, 3'),
          findsOneWidget);
      semantics.dispose();
    });

    testWidgets("a failed pattern blanks only itself", (tester) async {
      await useGregorianEnglish();
      final cig = await cigarettesAtNoonAndDawn();
      await openInsights(tester, cig.id, overrides: [
        trackerResultProvider(TrackerQueries.byHour(cig.id, october))
            .overrideWith(
                (ref) => Future<TrackerResult>.error(Exception('boom'))),
      ]);

      expect(find.byKey(const Key('tracker-history-chart')), findsOneWidget);
      await scrollTo(tester, 'tracker-hour-error');
      expect(find.byKey(const Key('tracker-hour-error')), findsOneWidget);
    });
  });
}
