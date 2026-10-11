import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/application/goal_providers.dart';
import 'package:nimbustats/features/goals/routes.dart';

import '../trackers/support/tracker_fixture.dart';
import 'support/goal_test_app.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late GoalService service;

  /// A Gregorian monthly cap on Dining since July, while the app keeps its
  /// default Jalali calendar, so every period name on screen must be
  /// Gregorian (spec §5.2).
  final cap = spendingCap(
      calendar: CalendarKind.gregorian, since: const DateKey(20260701));

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    service = goalServiceFor(db, fake.clock.today);
    await seedCategories(db);
  });
  tearDown(() => db.close());

  /// July over the cap; August and September under it; 300K so far in
  /// October.
  Future<void> seedHistory() async {
    await service.save(cap);
    await spend(db, 1200000, const DateKey(20260715));
    await spend(db, 400000, const DateKey(20260815));
    await spend(db, 900000, const DateKey(20260915));
    await spend(db, 300000, const DateKey(20261002));
  }

  Future<void> openDetail(WidgetTester tester,
          {Locale locale = const Locale('en'),
          List<Override> overrides = const []}) =>
      pumpGoals(tester, db, fake,
          location: goalDetailRoute('cap'),
          locale: locale,
          overrides: overrides);

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  /// Lets the app's providers dispose, so a test can open a second screen.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  Finder historyRow(int start, String text) => find.descendant(
      of: find.byKey(Key('goal-history-$start')), matching: find.text(text));

  testWidgets(
      'this period: the amounts in full, the status in words, the bar and '
      'the pace', (tester) async {
    await useEnglishDigits(db);
    await seedHistory();

    await openDetail(tester);

    expect(textOf(tester, 'goal-detail-amounts'), '300,000 of 1,000,000');
    expect(
        find.descendant(
            of: find.byKey(const Key('goal-detail-status')),
            matching: find.text('On track')),
        findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(find.descendant(
                of: find.byKey(const Key('goal-detail-bar')),
                matching: find.byType(LinearProgressIndicator)))
            .value,
        closeTo(0.3, 1e-9));
    // 300,000 over the five days of October so far, carried to 31 days.
    expect(textOf(tester, 'goal-detail-pace'),
        'At this pace: 1,860,000 by 2026/10/31');
  });

  testWidgets(
      "history runs newest first, named in the goal's own calendar, with its "
      'streak', (tester) async {
    await useEnglishDigits(db);
    await seedHistory();

    await openDetail(tester);

    expect(historyRow(20260901, '2026/09'), findsOneWidget);
    expect(historyRow(20260901, 'Met'), findsOneWidget);
    expect(historyRow(20260801, '400,000'), findsOneWidget);
    expect(historyRow(20260701, 'Over the limit'), findsOneWidget);
    expect(
        tester.getTopLeft(find.byKey(const Key('goal-history-20260901'))).dy,
        lessThan(tester
            .getTopLeft(find.byKey(const Key('goal-history-20260701')))
            .dy));
    expect(textOf(tester, 'goal-detail-streak'),
        '2 periods met in a row · best 2');
  });

  testWidgets('a goal with no finished period says so', (tester) async {
    await service.save(spendingCap(since: const DateKey(20261005)));

    await openDetail(tester);

    expect(find.byKey(const Key('goal-history-empty')), findsOneWidget);
    expect(find.text('No finished periods yet'), findsOneWidget);
    expect(find.byKey(const Key('goal-detail-streak')), findsNothing,
        reason: 'no streak to speak of');
  });

  testWidgets('a skeleton while the goals load', (tester) async {
    final never = StreamController<List<GoalRead>>();
    addTearDown(never.close);

    await openDetail(tester,
        overrides: [goalsProvider.overrideWith((ref) => never.stream)]);

    expect(find.byKey(const Key('goal-detail-loading')), findsOneWidget);
  });

  testWidgets('a failed read offers a retry and hides the raw error',
      (tester) async {
    await openDetail(tester, overrides: [
      goalsProvider.overrideWith(
          (ref) => Stream<List<GoalRead>>.error(Exception('boom'))),
    ]);

    expect(find.byKey(const Key('goal-detail-error')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
  });

  testWidgets('a failed history says so in its place; the rest stands',
      (tester) async {
    await useEnglishDigits(db);
    await seedHistory();

    await openDetail(tester, overrides: [
      goalHistoryProvider(cap).overrideWith(
          (ref) => Future<GoalHistoryResult>.error(Exception('boom'))),
    ]);

    expect(find.byKey(const Key('goal-history-error')), findsOneWidget);
    expect(find.text('Could not load the history'), findsOneWidget);
    expect(textOf(tester, 'goal-detail-amounts'), '300,000 of 1,000,000');
    expect(find.text('Exception: boom'), findsNothing);
  });

  testWidgets('a goal that is gone says so and offers the way back',
      (tester) async {
    await openDetail(tester);

    expect(find.byKey(const Key('goal-detail-gone')), findsOneWidget);
    expect(find.text('This goal is gone'), findsOneWidget);
  });

  testWidgets('pause stops the evaluation and keeps the history; resume '
      'restarts it', (tester) async {
    await useEnglishDigits(db);
    await seedHistory();
    await openDetail(tester);

    await tester.tap(find.byKey(const Key('goal-detail-pause')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const Key('goal-detail-status')),
            matching: find.text('Paused')),
        findsOneWidget);
    expect(find.byKey(const Key('goal-detail-bar')), findsNothing,
        reason: 'a paused goal is not evaluated');
    expect(find.byTooltip('Resume'), findsOneWidget);
    expect(find.byKey(const Key('goal-history-20260901')), findsOneWidget,
        reason: 'its history stands');

    await tester.tap(find.byKey(const Key('goal-detail-pause')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const Key('goal-detail-status')),
            matching: find.text('On track')),
        findsOneWidget);
  });

  testWidgets('delete returns to the list, with an undo that brings it back',
      (tester) async {
    await useEnglishDigits(db);
    await seedHistory();
    await pumpGoals(tester, db, fake);
    await tester.tap(find.byKey(const Key('goal-card-cap')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-detail')), findsOneWidget);

    await tester.tap(find.byKey(const Key('goal-detail-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goals-empty')), findsOneWidget,
        reason: 'back on the list, without it');
    expect(find.text('Goal deleted'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-card-cap')), findsOneWidget);
  });

  testWidgets(
      "Persian: right to left, Persian digits, and still the goal's own "
      'calendar', (tester) async {
    await seedHistory();

    await openDetail(tester, locale: const Locale('fa'));

    expect(Directionality.of(tester.element(find.byKey(const Key('goal-detail')))),
        TextDirection.rtl);
    expect(textOf(tester, 'goal-detail-amounts'), '۳۰۰٬۰۰۰ از ۱٬۰۰۰٬۰۰۰');
    expect(historyRow(20260901, '۲۰۲۶/۰۹'), findsOneWidget);
  });

  testWidgets('at twice the font size nothing overflows', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await seedHistory();

    await openDetail(tester, locale: const Locale('fa'));

    expect(tester.takeException(), isNull);
  });

  testWidgets("the bar speaks its goal's name and its percent",
      (tester) async {
    final handle = tester.ensureSemantics();
    await useEnglishDigits(db);
    await seedHistory();

    await openDetail(tester);

    final data = tester
        .getSemantics(find.byType(LinearProgressIndicator))
        .getSemanticsData();
    expect(data.label, 'Dining out');
    expect(data.value, '30%');
    handle.dispose();
  });

  testWidgets(
      'a fixed range not yet begun, or already over, has no pace to speak of',
      (tester) async {
    await service.save(savingsTarget(
        id: 'later',
        range: const DateRange(DateKey(20261101), DateKey(20270331))));
    await service.save(savingsTarget(
        id: 'over',
        range: const DateRange(DateKey(20260601), DateKey(20260930))));

    for (final id in ['later', 'over']) {
      await pumpGoals(tester, db, fake, location: goalDetailRoute(id));
      expect(find.byKey(const Key('goal-detail-amounts')), findsOneWidget,
          reason: '$id is evaluated');
      expect(find.byKey(const Key('goal-detail-pace')), findsNothing,
          reason: '$id has no open period today');
      await unmount(tester);
    }
  });

  testWidgets(
      'an unreadable goal, and one whose tracker is deleted, show the problem '
      'card with Delete', (tester) async {
    await insertUnreadableGoal(db);
    final trackers = repositoryFor(db, fake);
    final w = await trackers.create(water);
    await service.save(habitGoal(w,
        id: 'water',
        metric: GoalMetric.trackerSum,
        direction: GoalDirection.atLeast,
        target: 2));
    await db.customStatement(
        'UPDATE trackers SET deleted_at = 1 WHERE id = ?', [w.id]);

    for (final id in ['bad', 'water']) {
      await pumpGoals(tester, db, fake, location: goalDetailRoute(id));
      expect(find.byKey(Key('goal-problem-$id')), findsOneWidget);
      expect(find.byKey(Key('goal-delete-$id')), findsOneWidget);
      await unmount(tester);
    }
  });

  testWidgets('a failed progress load says so, and Retry runs it again',
      (tester) async {
    await useEnglishDigits(db);
    await seedHistory();
    var calls = 0;

    await openDetail(tester, overrides: [
      goalProgressProvider(cap).overrideWith((ref) async {
        if (++calls == 1) throw Exception('boom');
        return ref.read(goalServiceProvider).engine.evaluateCurrent(cap);
      }),
    ]);

    expect(find.byKey(const Key('goal-detail-progress-error')), findsOneWidget);
    expect(find.text('Could not work out this goal'), findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);

    await tester.tap(find.descendant(
        of: find.byKey(const Key('goal-detail-progress-error')),
        matching: find.text('Retry')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.byKey(const Key('goal-detail-progress-error')), findsNothing);
    expect(textOf(tester, 'goal-detail-amounts'), '300,000 of 1,000,000');
  });
}
