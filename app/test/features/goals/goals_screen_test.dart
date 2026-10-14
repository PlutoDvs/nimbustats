import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/application/goal_providers.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';

import '../trackers/support/tracker_fixture.dart';
import 'support/goal_test_app.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late GoalService service;
  late TrackerRepository trackers;

  const day5 = DateKey(20261005);

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    service = goalServiceFor(db, fake.clock.today);
    trackers = repositoryFor(db, fake);
    await seedCategories(db);
  });
  tearDown(() => db.close());

  Finder inCard(String id, Finder matching) =>
      find.descendant(of: find.byKey(Key('goal-card-$id')), matching: matching);

  double barOf(WidgetTester tester, String id) => tester
      .widget<LinearProgressIndicator>(
          inCard(id, find.byType(LinearProgressIndicator)))
      .value!;

  testWidgets('goals show a skeleton while they load', (tester) async {
    final never = StreamController<List<GoalRead>>();
    addTearDown(never.close);

    await pumpGoals(tester, db, fake,
        overrides: [goalsProvider.overrideWith((ref) => never.stream)]);

    expect(find.byKey(const Key('goals-loading')), findsOneWidget);
  });

  testWidgets('with no goals the tab says what a goal is and offers one',
      (tester) async {
    await pumpGoals(tester, db, fake);

    expect(find.byKey(const Key('goals-empty')), findsOneWidget);
    expect(find.text('No goals yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'New goal'), findsOneWidget);
    expect(find.byKey(const Key('goals-new')), findsOneWidget,
        reason: 'and in the app bar, for when goals exist');
  });

  testWidgets('a failed read says so, retries, and hides the raw error',
      (tester) async {
    // The shell's watcher reports a failed goals stream once (Task 10).
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);

    await pumpGoals(tester, db, fake, overrides: [
      goalsProvider.overrideWith(
          (ref) => Stream<List<GoalRead>>.error(Exception('boom'))),
    ]);
    expect(reports, hasLength(1));

    expect(find.byKey(const Key('goals-error')), findsOneWidget);
    expect(find.text('Could not load your goals'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
  });

  testWidgets("a goal whose numbers fail says so on its own card",
      (tester) async {
    await service.save(spendingCap());

    await pumpGoals(tester, db, fake, overrides: [
      goalProgressProvider(spendingCap()).overrideWith(
          (ref) => Future<GoalProgress>.error(Exception('boom'))),
    ]);

    expect(inCard('cap', find.text('Could not work out this goal')),
        findsOneWidget);
    expect(inCard('cap', find.widgetWithText(TextButton, 'Retry')),
        findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
  });

  testWidgets('a spending cap shows its status in words and an icon, and a bar',
      (tester) async {
    await useEnglishDigits(db);
    await service.save(spendingCap());
    await spend(db, 850000, day5);

    await pumpGoals(tester, db, fake);

    expect(inCard('cap', find.text('Dining out')), findsOneWidget);
    expect(inCard('cap', find.text('At risk')), findsOneWidget);
    expect(inCard('cap', find.byIcon(Icons.warning_amber_rounded)),
        findsOneWidget);
    expect(inCard('cap', find.text('850K of 1M')), findsOneWidget);
    expect(barOf(tester, 'cap'), closeTo(0.85, 1e-9));
  });

  testWidgets('a habit limit fills toward its limit, a habit goal toward its goal',
      (tester) async {
    await useEnglishDigits(db);
    final cig = await trackers.create(cigarettes);
    final g = await trackers.create(gym);
    await service.save(habitGoal(cig, id: 'smoke', target: 10));
    await service.save(habitGoal(g,
        id: 'gym',
        direction: GoalDirection.atLeast,
        target: 4,
        period: PeriodType.week));
    for (var i = 0; i < 3; i++) {
      await trackers.logEntry(cig.id);
    }
    await trackers.logEntry(g.id);

    await pumpGoals(tester, db, fake);

    expect(inCard('smoke', find.text('3 of 10')), findsOneWidget);
    expect(barOf(tester, 'smoke'), closeTo(0.3, 1e-9));
    expect(barOf(tester, 'gym'), closeTo(0.25, 1e-9));
  });

  testWidgets('a savings target says what it needs a month, with no bar',
      (tester) async {
    // 6M by 2027-03-31 with 600K saved: 5.4M over the six months October to
    // March, 900K a month (spec §2, requiredRate).
    await useEnglishDigits(db);
    await service.save(savingsTarget());
    await earn(db, 600000, const DateKey(20261002));

    await pumpGoals(tester, db, fake);

    expect(inCard('savings', find.text('900K/month for 6 more months')),
        findsOneWidget);
    expect(inCard('savings', find.byType(LinearProgressIndicator)),
        findsNothing);
  });

  testWidgets('paused goals sit apart, under Paused', (tester) async {
    final fuel = spendingCap(id: 'fuel', name: 'Fuel', paths: const [transportPath]);
    await service.save(spendingCap());
    await service.save(fuel);
    await service.setActive(fuel, false);

    await pumpGoals(tester, db, fake);

    final header =
        tester.getTopLeft(find.byKey(const Key('goals-paused-header'))).dy;
    expect(tester.getTopLeft(find.byKey(const Key('goal-card-cap'))).dy,
        lessThan(header));
    expect(tester.getTopLeft(find.byKey(const Key('goal-card-fuel'))).dy,
        greaterThan(header));
    expect(inCard('fuel', find.text('Paused')), findsOneWidget);
    expect(inCard('fuel', find.byType(LinearProgressIndicator)), findsNothing);
  });

  testWidgets(
      "an archived tracker's goal reads normally; a deleted one's offers "
      'Edit and Delete', (tester) async {
    // Review Focus 5: archiving is not deletion.
    await useEnglishDigits(db);
    final cig = await trackers.create(cigarettes);
    final w = await trackers.create(water);
    await service.save(habitGoal(cig, id: 'smoke', target: 10));
    await service.save(habitGoal(w,
        id: 'water',
        metric: GoalMetric.trackerSum,
        direction: GoalDirection.atLeast,
        target: 2));
    await trackers.logEntry(cig.id);
    await trackers.archive(cig.id);
    // The app has no tracker delete yet; sync or a restore can produce one.
    await db.customStatement(
        'UPDATE trackers SET deleted_at = 1 WHERE id = ?', [w.id]);

    await pumpGoals(tester, db, fake);

    expect(inCard('smoke', find.text('1 of 10')), findsOneWidget);
    expect(inCard('smoke', find.byType(LinearProgressIndicator)),
        findsOneWidget);
    expect(find.byKey(const Key('goal-problem-water')), findsOneWidget);
    expect(find.text("This goal's tracker was deleted"), findsOneWidget);
    expect(find.byKey(const Key('goal-edit-water')), findsOneWidget);
    expect(find.byKey(const Key('goal-delete-water')), findsOneWidget);
  });

  testWidgets('an unreadable goal can be deleted, and the delete undone',
      (tester) async {
    await insertUnreadableGoal(db);

    await pumpGoals(tester, db, fake);
    expect(find.byKey(const Key('goal-problem-bad')), findsOneWidget);
    expect(find.text('This goal could not be read'), findsOneWidget);
    expect(find.byKey(const Key('goal-edit-bad')), findsNothing,
        reason: 'there is nothing readable to edit');

    await tester.tap(find.byKey(const Key('goal-delete-bad')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-card-bad')), findsNothing);
    expect(find.byKey(const Key('goals-empty')), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-card-bad')), findsOneWidget);
  });

  testWidgets('a card reads as one sentence: name, progress, status',
      (tester) async {
    final handle = tester.ensureSemantics();
    await useEnglishDigits(db);
    await service.save(spendingCap());
    await spend(db, 850000, day5);

    await pumpGoals(tester, db, fake);

    expect(find.bySemanticsLabel('Dining out, 850K of 1M, At risk'),
        findsOneWidget);
    handle.dispose();
  });

  testWidgets('a savings card reads as one sentence ending in its run-rate',
      (tester) async {
    final handle = tester.ensureSemantics();
    await useEnglishDigits(db);
    await service.save(savingsTarget());
    await earn(db, 600000, const DateKey(20261002));

    await pumpGoals(tester, db, fake);

    expect(
        find.bySemanticsLabel(
            'Car, 600K of 6M, On track, 900K/month for 6 more months'),
        findsOneWidget);
    handle.dispose();
  });

  testWidgets('Persian: right to left, Persian digits and words',
      (tester) async {
    // No useEnglishDigits: the default settings write Persian digits.
    await service.save(spendingCap());
    await spend(db, 850000, day5);

    await pumpGoals(tester, db, fake, locale: const Locale('fa'));

    expect(Directionality.of(tester.element(find.byKey(const Key('goal-card-cap')))),
        TextDirection.rtl);
    expect(inCard('cap', find.text('۸۵۰K از ۱M')), findsOneWidget);
    expect(inCard('cap', find.text('در خطر')), findsOneWidget);
  });

  testWidgets('every tap target is at least 48 dp, problem cards included',
      (tester) async {
    // Tall enough that the lazy list builds every card.
    tester.view.physicalSize = const Size(800, 4000);
    addTearDown(tester.view.resetPhysicalSize);
    final handle = tester.ensureSemantics();
    await useEnglishDigits(db);
    final trackers = repositoryFor(db, fake);
    final cig = await trackers.create(cigarettes);
    final w = await trackers.create(water);
    await service.save(spendingCap());
    await service.save(habitGoal(cig, id: 'smoke', target: 10));
    await service.save(habitGoal(cig,
        id: 'gym',
        metric: GoalMetric.trackerSum,
        direction: GoalDirection.atLeast,
        target: 4));
    await service.save(savingsTarget());
    await service.save(habitGoal(w,
        id: 'water',
        metric: GoalMetric.trackerSum,
        direction: GoalDirection.atLeast,
        target: 2));
    await db.customStatement(
        'UPDATE trackers SET deleted_at = 1 WHERE id = ?', [w.id]);
    await insertUnreadableGoal(db);
    final fuel =
        spendingCap(id: 'fuel', name: 'Fuel', paths: const [transportPath]);
    await service.save(fuel);
    await service.setActive(fuel, false);
    final failing = spendingCap(id: 'failing', name: 'Failing');
    await service.save(failing);

    await pumpGoals(tester, db, fake, overrides: [
      goalProgressProvider(failing).overrideWith(
          (ref) => Future<GoalProgress>.error(Exception('boom'))),
    ]);

    expect(find.byKey(const Key('goal-edit-water')), findsOneWidget);
    expect(find.byKey(const Key('goal-delete-bad')), findsOneWidget);
    expect(inCard('failing', find.widgetWithText(TextButton, 'Retry')),
        findsOneWidget);
    expect(find.byKey(const Key('goal-card-fuel')), findsOneWidget,
        reason: 'the paused card is built, so the guideline sees it');
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('at twice the font size the tab overflows nothing',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await service.save(
        spendingCap(name: 'A forty character name, for case D2 ok'));
    await service.save(savingsTarget());
    await spend(db, 850000, day5);

    await pumpGoals(tester, db, fake, locale: const Locale('fa'));

    expect(tester.takeException(), isNull);
  });

  testWidgets('at twice the font size the problem, unreadable and paused '
      'cards overflow nothing', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // 800 x 2000 logical: tall enough that the list lays out every card.
    tester.view.physicalSize = const Size(2400, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    final w = await trackers.create(water);
    await service.save(habitGoal(w,
        id: 'water',
        metric: GoalMetric.trackerSum,
        direction: GoalDirection.atLeast,
        target: 2));
    await db.customStatement(
        'UPDATE trackers SET deleted_at = 1 WHERE id = ?', [w.id]);
    await insertUnreadableGoal(db);
    final fuel =
        spendingCap(id: 'fuel', name: 'Fuel', paths: const [transportPath]);
    await service.save(fuel);
    await service.setActive(fuel, false);

    await pumpGoals(tester, db, fake);

    expect(find.byKey(const Key('goal-problem-water')), findsOneWidget);
    expect(find.byKey(const Key('goal-problem-bad')), findsOneWidget);
    expect(inCard('fuel', find.text('Paused')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
