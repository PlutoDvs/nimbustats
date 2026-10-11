import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/routes.dart';
import 'package:nimbustats/features/transactions/data/transaction_draft.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';

import '../../../support/harness.dart';
import '../../trackers/support/tracker_fixture.dart';

/// What every goals test stands on:
/// - categories to scope by;
/// - money moved on a chosen day;
/// - a service that writes goals the way the app does;
/// - one goal of each kind.

/// Food (with Dining) and Transport, plus the Uncategorized row every
/// transaction may fall back to.
Future<void> seedCategories(AppDatabase db) async {
  await CategorySeeder(db).seedIfEmpty(
    roots: const [
      SeedCategoryNode(id: 'seed-food', name: 'Food', children: [
        SeedCategoryNode(id: 'seed-dining', name: 'Dining'),
      ]),
      SeedCategoryNode(id: 'seed-transport', name: 'Transport'),
    ],
    uncategorizedName: 'Uncategorized',
  );
}

/// The seeded categories' materialized paths (`/rootId/childId/`).
const foodPath = '/seed-food/';
const diningPath = '/seed-food/seed-dining/';
const transportPath = '/seed-transport/';

/// One expense of [amount] on [day].
Future<void> spend(AppDatabase db, int amount, DateKey day,
        {String category = 'seed-dining'}) =>
    _record(db, amount, day, TxDirection.expense, category);

/// One income of [amount] on [day]: what a savings target counts up.
Future<void> earn(AppDatabase db, int amount, DateKey day) => _record(
    db, amount, day, TxDirection.income, SystemCategoryIds.uncategorized);

Future<void> _record(AppDatabase db, int amount, DateKey day,
    TxDirection direction, String category) async {
  await TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman)
      .add(TransactionDraft(
    amount: Money(amount),
    direction: direction,
    categoryId: category,
    // Noon UTC is the same date in every zone from UTC-11 to UTC+11, so the
    // repository's local date key cannot move it to the day next door.
    occurredAtUtc: DateTime.utc(day.year, day.month, day.day, 12),
  ));
}

/// A service over [db] whose today is [today], built as the app builds
/// `goalServiceProvider`. The engine's calendar is irrelevant here: a goal
/// hands it plain date keys.
GoalService goalServiceFor(AppDatabase db, DateKey Function() today) =>
    GoalService(
      db,
      GoalEngine(
        EngineGoalMeasurer(
            db, AnalyticsEngine(db, calendar: const JalaliCalendar())),
        today: today,
      ),
    );

/// A monthly cap on Dining, in the app's default calendar.
Goal spendingCap({
  String id = 'cap',
  String name = 'Dining out',
  int target = 1000000,
  List<String> paths = const [diningPath],
  PeriodType period = PeriodType.month,
  DateKey since = const DateKey(20260101),
  CalendarKind calendar = CalendarKind.jalali,
  List<int> alerts = Goal.defaultAlertPercents,
}) =>
    Goal(
      id: id,
      name: name,
      metric: GoalMetric.moneySum,
      scope: MoneyScope(QueryFilters(
          direction: MoneyDirection.expense, categorySubtreePaths: paths)),
      direction: GoalDirection.atMost,
      target: MoneyAmount(Money(target)),
      period: RecurringPeriod(period, since),
      calendar: calendar,
      weekStart: DateTime.saturday,
      alertPercents: alerts,
    );

/// A habit limit (the default) or a habit goal over [tracker].
Goal habitGoal(
  Tracker tracker, {
  String id = 'habit',
  GoalMetric metric = GoalMetric.trackerCount,
  GoalDirection direction = GoalDirection.atMost,
  double target = 5,
  PeriodType period = PeriodType.day,
  DateKey since = const DateKey(20260101),
  List<int> alerts = Goal.defaultAlertPercents,
}) =>
    Goal(
      id: id,
      name: tracker.name,
      metric: metric,
      scope: TrackerScope(tracker.id),
      direction: direction,
      target: QuantityAmount(target),
      period: RecurringPeriod(period, since),
      calendar: CalendarKind.jalali,
      weekStart: DateTime.saturday,
      alertPercents: alerts,
    );

/// Six million by the end of March 2027, Gregorian: six months from
/// 2026-10-05, October included.
Goal savingsTarget({
  String id = 'savings',
  String name = 'Car',
  int target = 6000000,
  DateRange range = const DateRange(DateKey(20261001), DateKey(20270331)),
}) =>
    Goal(
      id: id,
      name: name,
      metric: GoalMetric.netSavings,
      scope: MoneyScope(const QueryFilters()),
      direction: GoalDirection.atLeast,
      target: MoneyAmount(Money(target)),
      period: FixedRangePeriod(range),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.saturday,
    );

/// Pumps the real app at [location], standing on [fake]'s today.
Future<AppDatabase> pumpGoals(
  WidgetTester tester,
  AppDatabase db,
  FakeClock fake, {
  String location = goalsRoute,
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
  void Function(ProviderContainer container)? onContainer,
}) =>
    pumpApp(tester,
        database: db,
        initialLocation: location,
        locale: locale,
        overrides: [...trackerOverrides(fake), ...overrides],
        onContainer: onContainer);

/// A goals row whose scope is not JSON, which the list must show as
/// unreadable, with a delete, rather than crash on it or default it (spec
/// §1). The column names are spec §1's, created in Task 1: check them with
/// `PRAGMA table_info(goals)` if this insert fails.
Future<void> insertUnreadableGoal(AppDatabase db,
        {String id = 'bad', String name = 'Broken'}) =>
    db.customStatement(
      'INSERT INTO goals (id, created_at, updated_at, name, metric, '
      'scope_json, direction, target_minor, target_quantity, period, '
      'calendar, week_start, start_date, end_date, alert_percents, active) '
      "VALUES (?, 0, 0, ?, 'moneySum', '{not json', 'atMost', 1000, NULL, "
      "'month', 'jalali', 6, 20260101, NULL, '[80,100]', 1)",
      [id, name],
    );
