import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/application/goal_editor_controller.dart';
import 'package:nimbustats/features/goals/application/goal_kind.dart';
import 'package:nimbustats/features/goals/application/goal_providers.dart';
import 'package:nimbustats/features/goals/routes.dart';
import 'package:nimbustats/features/tags/application/tag_providers.dart';
import 'package:nimbustats/features/tags/data/tag_repository.dart';
import 'package:nimbustats/features/tags/data/tag_tree.dart';
import 'package:nimbustats/features/trackers/application/tracker_providers.dart';
import 'package:nimbustats/features/trackers/data/tracker_draft.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';

import '../notifications/support/fake_outside_channel.dart';
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

  ProviderContainer? opened;

  Future<void> openNew(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    // A tree replaced by the next pump leaves its container's auto-dispose
    // timers pending, so the test would end with a timer still scheduled.
    // Each editor is closed and its container disposed before the next opens.
    if (opened != null) {
      await tester.pumpWidget(const SizedBox());
      opened!.dispose();
    }
    await pumpGoals(
      tester,
      db,
      fake,
      location: newGoalRoute,
      locale: locale,
      onContainer: (container) => opened = container,
    );
  }

  Future<void> choose(WidgetTester tester, GoalKind kind) async {
    await tester.tap(find.byKey(Key('goal-kind-${kind.name}')));
    await tester.pumpAndSettle();
  }

  Future<void> pickTracker(WidgetTester tester, Tracker tracker) async {
    await tapVisible(tester, find.byKey(const Key('goal-tracker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('goal-tracker-option-${tracker.id}')));
    await tester.pumpAndSettle();
  }

  String nameText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('goal-name')))
      .controller!
      .text;

  VoidCallback? save(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('goal-save'))).onPressed;

  bool chip(WidgetTester tester, String key) =>
      switch (tester.widget(find.byKey(Key(key)))) {
        ChoiceChip(:final selected) => selected,
        FilterChip(:final selected) => selected,
        final other => throw StateError('$key is a ${other.runtimeType}'),
      };

  Future<Goal> savedGoal(WidgetTester tester) async =>
      ((await firstOf(tester, db.goalsDao.watchAll())).single as GoalReadable)
          .goal;

  test('each rule refuses the draft, and a clear draft builds the goal', () {
    const money = MoneyFormatter(
      currency: Currency.toman,
      persianDigits: false,
    );
    final cap = GoalEditorState(
      id: 'g',
      kind: GoalKind.spendingCap,
      name: 'Dining',
      nameEdited: true,
      targetText: '500,000',
      categoryPaths: const [diningPath],
      tags: null,
      baseFilters: const QueryFilters(direction: MoneyDirection.expense),
      tracker: null,
      period: PeriodType.month,
      since: day5,
      start: day5,
      end: day5,
      calendar: CalendarKind.jalali,
      weekStart: DateTime.saturday,
      alertPercents: Goal.defaultAlertPercents,
      active: true,
    );
    expect(goalEditorErrors(cap, money), isEmpty);
    expect(
      goalDraft(cap, money),
      spendingCap(id: 'g', name: 'Dining', target: 500000, since: day5),
    );

    expect(goalEditorErrors(cap.copyWith(name: '  '), money), {
      GoalEditorError.nameBlank,
    });
    expect(goalEditorErrors(cap.copyWith(targetText: ''), money), {
      GoalEditorError.targetMissing,
    });
    expect(goalEditorErrors(cap.copyWith(targetText: 'abc'), money), {
      GoalEditorError.targetInvalid,
    });
    expect(
      goalEditorErrors(cap.copyWith(targetText: '0'), money),
      isEmpty,
      reason: 'zero is a legitimate cap',
    );

    final savings = cap.copyWith(
      kind: GoalKind.savingsTarget,
      baseFilters: const QueryFilters(),
      end: day5.addDays(-1),
    );
    expect(goalEditorErrors(savings, money), {GoalEditorError.endBeforeStart});
    expect(
      goalEditorErrors(savings.copyWith(end: day5, targetText: '0'), money),
      {GoalEditorError.targetZero},
    );

    final habit = cap.copyWith(kind: GoalKind.habitLimit, targetText: '3');
    expect(goalEditorErrors(habit, money), {GoalEditorError.trackerMissing});
    expect(goalDraft(habit, money), isNull);
  });

  testWidgets('a new goal starts with its kind; a cap starts monthly, on all '
      'expenses, alerting at 80 and 100', (tester) async {
    await openNew(tester);
    for (final kind in GoalKind.values) {
      expect(find.byKey(Key('goal-kind-${kind.name}')), findsOneWidget);
    }

    await choose(tester, GoalKind.spendingCap);

    expect(nameText(tester), 'All expenses');
    expect(chip(tester, 'goal-period-month'), isTrue);
    expect(chip(tester, 'goal-alert-80'), isTrue);
    expect(chip(tester, 'goal-alert-100'), isTrue);
    expect(chip(tester, 'goal-alert-50'), isFalse);
    expect(
      tester
          .widget<SegmentedButton<CalendarKind>>(
            find.byKey(const Key('goal-calendar')),
          )
          .selected,
      {CalendarKind.jalali},
      reason: 'from the settings',
    );
    expect(save(tester), isNull, reason: 'no amount yet');
  });

  testWidgets('the other kinds start daily, weekly, or on a dated range', (
    tester,
  ) async {
    await useEnglishDigits(db);
    for (final (kind, period) in const [
      (GoalKind.habitLimit, 'day'),
      (GoalKind.habitGoal, 'week'),
    ]) {
      await openNew(tester);
      await choose(tester, kind);
      expect(chip(tester, 'goal-period-$period'), isTrue, reason: kind.name);
    }

    await openNew(tester);
    await choose(tester, GoalKind.savingsTarget);
    expect(nameText(tester), 'Savings target');
    expect(
      find.byKey(const Key('goal-period-month')),
      findsNothing,
      reason: 'a range, not a period',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('goal-start')),
        matching: find.text('1405/07/13'),
      ),
      findsOneWidget,
    );
    expect(find.text('The end must not be before the start'), findsNothing);
  });

  testWidgets('a blank name says so and keeps Save disabled', (tester) async {
    await openNew(tester);
    await choose(tester, GoalKind.spendingCap);
    await tester.enterText(find.byKey(const Key('tx-amount-field')), '500000');
    await tester.pump();
    expect(save(tester), isNotNull);

    await tester.enterText(find.byKey(const Key('goal-name')), '   ');
    await tester.pump();

    expect(find.text('Give the goal a name'), findsOneWidget);
    expect(save(tester), isNull);
  });

  testWidgets('a target too large to hold says so; the form stays up', (
    tester,
  ) async {
    // D25 triage: int.parse threw inside build, and the form became an
    // ErrorWidget.
    await openNew(tester);
    await choose(tester, GoalKind.spendingCap);
    await tester.enterText(find.byKey(const Key('tx-amount-field')), '9' * 20);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Enter a number'), findsOneWidget);
    expect(save(tester), isNull);
  });

  testWidgets('a habit goal refuses zero; a habit limit saves it', (
    tester,
  ) async {
    // Zero is a legitimate limit, "zero cigarettes" (screen contract §7.2).
    final cig = await trackers.create(cigarettes);
    await openNew(tester);
    await choose(tester, GoalKind.habitGoal);
    await pickTracker(tester, cig);
    await tester.enterText(find.byKey(const Key('goal-target')), '0');
    await tester.pump();
    expect(find.text('The goal must be more than zero'), findsOneWidget);
    expect(save(tester), isNull);

    await openNew(tester);
    await choose(tester, GoalKind.habitLimit);
    await pickTracker(tester, cig);
    await tester.enterText(find.byKey(const Key('goal-target')), '0');
    await tester.pump();
    expect(find.text('The goal must be more than zero'), findsNothing);
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();

    final goal = await savedGoal(tester);
    expect(goal.name, 'Cigarettes');
    expect(goal.metric, GoalMetric.trackerCount);
    expect(goal.direction, GoalDirection.atMost);
    expect(goal.target, const QuantityAmount(0));
    expect(goal.period, const RecurringPeriod(PeriodType.day, day5));
    expect(
      find.byKey(Key('goal-card-${goal.id}')),
      findsOneWidget,
      reason: 'back on the list',
    );
  });

  testWidgets('a counter or boolean habit refuses a fraction; a quantity '
      'keeps one', (tester) async {
    // 2.5 cigarettes or 2.5 gym days is no target: their entries count
    // whole times and days.
    final cig = await trackers.create(cigarettes);
    final g = await trackers.create(gym);
    final w = await trackers.create(water);
    for (final (kind, tracker) in [
      (GoalKind.habitLimit, cig),
      (GoalKind.habitGoal, g),
    ]) {
      await openNew(tester);
      await choose(tester, kind);
      await pickTracker(tester, tracker);
      await tester.enterText(find.byKey(const Key('goal-target')), '2.5');
      await tester.pump();
      expect(find.text('Enter a whole number'), findsOneWidget,
          reason: tracker.name);
      expect(find.text('Enter a number'), findsNothing, reason: tracker.name);
      expect(save(tester), isNull, reason: tracker.name);
    }

    await openNew(tester);
    await choose(tester, GoalKind.habitGoal);
    await pickTracker(tester, w);
    await tester.enterText(find.byKey(const Key('goal-target')), '2.5');
    await tester.pump();
    expect(find.text('Enter a whole number'), findsNothing, reason: 'litres');
    expect(find.text('Enter a number'), findsNothing, reason: 'litres');
    expect(save(tester), isNotNull);
  });

  testWidgets('a habit without a tracker says so; choosing one names it', (
    tester,
  ) async {
    final cig = await trackers.create(cigarettes);
    await openNew(tester);
    await choose(tester, GoalKind.habitLimit);
    expect(
      find.descendant(
        of: find.byKey(const Key('goal-tracker')),
        matching: find.text('Choose a tracker'),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('goal-target')), '5');
    await tester.pump();
    expect(save(tester), isNull);

    await pickTracker(tester, cig);

    expect(find.text('Choose a tracker'), findsNothing);
    expect(nameText(tester), 'Cigarettes');
    expect(
      find.text('Times'),
      findsOneWidget,
      reason: "a counter's target is a number of times",
    );
    expect(save(tester), isNotNull);
  });

  testWidgets("the preview shows the last three periods' outcomes and this "
      "period's progress", (tester) async {
    await useEnglishDigits(db);
    await spend(db, 500000, const DateKey(20260715));
    await spend(db, 1500000, const DateKey(20260815));
    await spend(db, 900000, const DateKey(20260915));
    await spend(db, 200000, const DateKey(20261002));
    await openNew(tester);
    await choose(tester, GoalKind.spendingCap);
    await tester.enterText(find.byKey(const Key('tx-amount-field')), '1000000');
    await tapVisible(tester, find.text('Gregorian'));
    // The preview runs once the last change has settled, ~300 ms on.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    // The form's fields hold Scrollables of their own, so drag the form
    // itself rather than "the" Scrollable.
    await tester.dragUntilVisible(
      find.byKey(const Key('goal-preview-current')),
      find.byKey(const Key('goal-editor')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    Finder row(int start, String text) => find.descendant(
      of: find.byKey(Key('goal-preview-$start')),
      matching: find.text(text),
    );
    expect(row(20260701, '2026/07'), findsOneWidget);
    expect(row(20260701, 'Met'), findsOneWidget);
    expect(row(20260801, 'Over the limit'), findsOneWidget);
    expect(row(20260901, 'Met'), findsOneWidget);
    expect(find.text('This period: 200,000 of 1,000,000'), findsOneWidget);
  });

  testWidgets('a saved cap keeps its category and tags; the list shows it', (
    tester,
  ) async {
    final work = await TagRepository(db.tagsDao).findOrCreate('Work');
    await pumpGoals(tester, db, fake);
    await tester.tap(find.byKey(const Key('goals-new')));
    await tester.pumpAndSettle();
    await choose(tester, GoalKind.spendingCap);

    await tester.tap(find.byKey(const Key('goal-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-category-seed-dining')));
    await tester.pumpAndSettle();
    expect(
      nameText(tester),
      'Dining',
      reason: 'the name follows the scope until the user types one',
    );

    await tester.tap(find.byKey(const Key('goal-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('tag-option-${work.id}')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tag-picker-done')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('tx-amount-field')), '2000000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('goals-list')),
      findsOneWidget,
      reason: 'back on the list',
    );
    final goal = await savedGoal(tester);
    expect(goal.name, 'Dining');
    expect(
      goal.scope,
      MoneyScope(
        QueryFilters(
          direction: MoneyDirection.expense,
          categorySubtreePaths: const [diningPath],
          tags: TagsAny([work.path]),
        ),
      ),
    );
    expect(goal.target, const MoneyAmount(Money(2000000)));
    expect(goal.period, const RecurringPeriod(PeriodType.month, day5));
    expect(goal.calendar, CalendarKind.jalali, reason: 'from the settings');
    expect(goal.weekStart, DateTime.saturday, reason: 'from the settings');
    expect(goal.alertPercents, const [80, 100]);
    expect(find.byKey(Key('goal-card-${goal.id}')), findsOneWidget);
  });

  testWidgets(
    'a duration goal whose tracker was deleted asks for the target again '
    'rather than reading its seconds as minutes',
    (tester) async {
      await useEnglishDigits(db);
      final old = await trackers.create(sleep);
      // The app has no tracker delete yet; sync or a restore can produce one.
      await service.save(
        habitGoal(
          old,
          metric: GoalMetric.trackerSum,
          direction: GoalDirection.atLeast,
          target: 28800,
          period: PeriodType.week,
        ),
      );
      await db.customStatement(
        'UPDATE trackers SET deleted_at = 1 WHERE id = ?',
        [old.id],
      );
      final nap = await trackers.create(
        const TrackerDraft(
          name: 'Nap',
          iconKey: 'bedtime',
          color: 0xFF4527A0,
          type: TrackerType.duration,
        ),
      );

      await pumpGoals(tester, db, fake, location: editGoalRoute('habit'));
      await pickTracker(tester, nap);

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('goal-target')))
            .controller!
            .text,
        isEmpty,
        reason: 'the old number was seconds; minutes must be typed afresh',
      );
      await tester.enterText(find.byKey(const Key('goal-target')), '8');
      await tester.pump();
      await tester.tap(find.byKey(const Key('goal-save')));
      await tester.pumpAndSettle();

      expect(
        (await savedGoal(tester)).target,
        const QuantityAmount(480),
        reason: '8 minutes in seconds, not 28800 x 60',
      );
    },
  );

  testWidgets('a tag created inside the picker is kept in the filter', (
    tester,
  ) async {
    // The tag map is left stale, as it is in the instant after a tag is
    // created, so only a fresh read of the tags can find the new one.
    await pumpGoals(
      tester,
      db,
      fake,
      location: newGoalRoute,
      overrides: [
        tagNodesByIdProvider.overrideWithValue(
          const AsyncData(<String, TagNode>{}),
        ),
      ],
    );
    await choose(tester, GoalKind.spendingCap);

    await tester.tap(find.byKey(const Key('goal-tags')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tag-picker-search')), 'Fresh');
    await tester.pump();
    await tester.tap(find.byKey(const Key('tag-create-inline')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('tag-picker-done')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('tx-amount-field')), '2000000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();

    final fresh = (await tester.runAsync(
      () => TagRepository(db.tagsDao).findOrCreate('Fresh'),
    ))!;
    final scope = (await savedGoal(tester)).scope as MoneyScope;
    expect(scope.filters.tags, TagsAny([fresh.path]));
  });

  testWidgets('a tag already in the filter stays when the reads omit it', (
    tester,
  ) async {
    // Archived tags are not offered by the fresh read, and the tag map is
    // stale here, so only the filter's own stored path can keep it.
    final repo = TagRepository(db.tagsDao);
    final old = (await tester.runAsync(() => repo.findOrCreate('Old')))!;
    await tester.runAsync(() => repo.archive(old.id));
    await tester.runAsync(
      () => service.save(
        Goal(
          id: 'cap',
          name: 'Dining out',
          metric: GoalMetric.moneySum,
          scope: MoneyScope(
            QueryFilters(
              direction: MoneyDirection.expense,
              categorySubtreePaths: const [diningPath],
              tags: TagsAny([old.path]),
            ),
          ),
          direction: GoalDirection.atMost,
          target: const MoneyAmount(Money(1000000)),
          period: const RecurringPeriod(PeriodType.month, day5),
          calendar: CalendarKind.jalali,
          weekStart: DateTime.saturday,
        ),
      ),
    );
    await pumpGoals(
      tester,
      db,
      fake,
      location: editGoalRoute('cap'),
      overrides: [
        tagNodesByIdProvider.overrideWithValue(
          const AsyncData(<String, TagNode>{}),
        ),
      ],
    );

    await tester.tap(find.byKey(const Key('goal-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tag-picker-done')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();

    final scope = (await savedGoal(tester)).scope as MoneyScope;
    expect(scope.filters.tags, TagsAny([old.path]));
  });

  testWidgets('a failed save says so, keeps the form and the error reaches '
      'the zone', (tester) async {
    await openNew(tester);
    await choose(tester, GoalKind.spendingCap);
    await tester.enterText(find.byKey(const Key('tx-amount-field')), '500000');
    await tester.enterText(find.byKey(const Key('goal-name')), 'Eat less');
    await tester.pump();
    await db.customStatement(
      'CREATE TEMP TRIGGER fail_goal BEFORE INSERT ON goals '
      "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END",
    );

    // The rethrow comes from a detached future the tap never awaits, which
    // is how it reaches the framework's handler in the app.
    Object? caught;
    await runZonedGuarded(() async {
      await tester.tap(find.byKey(const Key('goal-save')));
      await tester.pumpAndSettle();
    }, (error, stack) => caught = error);

    expect(caught, isNotNull);
    expect(find.text('Could not save the goal'), findsOneWidget);
    expect(find.byKey(const Key('goal-editor')), findsOneWidget);
    expect(nameText(tester), 'Eat less');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('tx-amount-field')))
          .controller!
          .text,
      isNotEmpty,
    );
    expect(save(tester), isNotNull);
  });

  testWidgets('editing a goal opens its own form, and saving keeps the goal', (
    tester,
  ) async {
    await useEnglishDigits(db);
    await service.save(spendingCap());

    await pumpGoals(tester, db, fake, location: editGoalRoute('cap'));

    expect(
      find.byKey(const Key('goal-kind-spendingCap')),
      findsNothing,
      reason: "an existing goal's kind is derived, not asked",
    );
    expect(nameText(tester), 'Dining out');
    expect(
      find.descendant(
        of: find.byKey(const Key('goal-category')),
        matching: find.text('Dining'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('tx-amount-field')))
          .controller!
          .text,
      '1,000,000',
    );

    await tester.enterText(find.byKey(const Key('tx-amount-field')), '1200000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();

    expect(await savedGoal(tester), spendingCap(target: 1200000));
  });

  group('editing a goal that is still loading or failed to load', () {
    testWidgets('the goals list loading shows the skeleton', (tester) async {
      final never = StreamController<List<GoalRead>>();
      addTearDown(never.close);

      await pumpGoals(tester, db, fake,
          location: editGoalRoute('cap'),
          overrides: [goalsProvider.overrideWith((ref) => never.stream)]);

      expect(find.byType(NimbusLoadingList), findsOneWidget);
      expect(find.byKey(const Key('goal-save')), findsNothing);
    });

    testWidgets('a failed goals read says so, hides the raw error, and Retry '
        'reads again and shows the form', (tester) async {
      await useEnglishDigits(db);
      await service.save(spendingCap());
      var calls = 0;

      await pumpGoals(tester, db, fake, location: editGoalRoute('cap'),
          overrides: [
            goalsProvider.overrideWith((ref) {
              if (++calls == 1) {
                return Stream<List<GoalRead>>.error(Exception('boom'));
              }
              return db.goalsDao.watchAll();
            }),
          ]);

      expect(find.text('Could not load your goals'), findsOneWidget);
      expect(find.text('Exception: boom'), findsNothing);
      expect(find.byKey(const Key('goal-save')), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(nameText(tester), 'Dining out');
    });

    testWidgets("the goal's tracker loading shows the skeleton", (tester) async {
      final w = await trackers.create(water);
      await service.save(habitGoal(w, id: 'water'));
      final never = StreamController<Tracker?>();
      addTearDown(never.close);

      await pumpGoals(tester, db, fake,
          location: editGoalRoute('water'),
          overrides: [
            trackerByIdProvider(w.id).overrideWith((ref) => never.stream),
          ]);

      expect(find.byType(NimbusLoadingList), findsOneWidget);
      expect(find.byKey(const Key('goal-save')), findsNothing);
    });

    testWidgets("a failed tracker read says so, hides the raw error, and "
        'Retry reads again and shows the form', (tester) async {
      final w = await trackers.create(water);
      await service.save(habitGoal(w, id: 'water'));
      var calls = 0;

      await pumpGoals(tester, db, fake,
          location: editGoalRoute('water'),
          overrides: [
            trackerByIdProvider(w.id).overrideWith((ref) {
              if (++calls == 1) return Stream<Tracker?>.error(Exception('boom'));
              return Stream.value(w);
            }),
          ]);

      expect(find.text('Could not load your goals'), findsOneWidget);
      expect(find.text('Exception: boom'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.byKey(const Key('goal-save')), findsOneWidget);
    });
  });

  testWidgets('Persian: right to left, Persian digits on the chips', (
    tester,
  ) async {
    await openNew(tester, locale: const Locale('fa'));
    await choose(tester, GoalKind.spendingCap);

    expect(
      Directionality.of(tester.element(find.byKey(const Key('goal-editor')))),
      TextDirection.rtl,
    );
    expect(nameText(tester), 'همهٔ هزینه‌ها');
    expect(
      find.descendant(
        of: find.byKey(const Key('goal-alert-80')),
        matching: find.text('۸۰٪'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the kind tiles and every kind form meet the 48 dp tap target',
      (tester) async {
    final handle = tester.ensureSemantics();
    await openNew(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    for (final kind in GoalKind.values) {
      await openNew(tester);
      await choose(tester, kind);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline),
          reason: kind.name);
    }
    handle.dispose();
  });

  testWidgets('at twice the font size no form overflows', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await openNew(tester, locale: const Locale('fa'));
    expect(tester.takeException(), isNull, reason: 'the kind tiles');
    for (final kind in GoalKind.values) {
      await openNew(tester, locale: const Locale('fa'));
      await choose(tester, kind);
      expect(tester.takeException(), isNull, reason: kind.name);
    }
  });

  group('the notification permission (Phase 6, spec §4.2)', () {
    Future<void> saveACap(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('goals-new')));
      await tester.pumpAndSettle();
      await choose(tester, GoalKind.spendingCap);
      await tester.enterText(
          find.byKey(const Key('tx-amount-field')), '2000000');
      await tester.pump();
      await tester.tap(find.byKey(const Key('goal-save')));
      await tester.pumpAndSettle();
    }

    testWidgets("the first goal's save asks, once", (tester) async {
      final outside = FakeOutsideChannel();
      await pumpGoals(tester, db, fake, outside: outside);
      await saveACap(tester);

      expect(outside.permissionRequests, 1);
      expect(find.byKey(const Key('goals-list')), findsOneWidget,
          reason: 'the save still closes the editor');
    });

    testWidgets("a later goal's save does not ask", (tester) async {
      await service.save(spendingCap());
      final outside = FakeOutsideChannel();
      await pumpGoals(tester, db, fake, outside: outside);
      await saveACap(tester);

      expect(outside.permissionRequests, 0);
    });
  });
}
