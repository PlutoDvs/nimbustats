import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/transactions/data/transaction_draft.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';

import '../../support/harness.dart';

/// Food splits into Groceries and Dining; Transport stands alone. Two levels
/// is the minimum that can tell a rollup apart from a leaf listing.
Future<AppDatabase> seededDb() async {
  final db = AppDatabase.openInMemory();
  await CategorySeeder(db).seedIfEmpty(
    roots: const [
      SeedCategoryNode(id: 'seed-food', name: 'Food', children: [
        SeedCategoryNode(id: 'seed-groceries', name: 'Groceries'),
        SeedCategoryNode(id: 'seed-dining', name: 'Dining'),
      ]),
      SeedCategoryNode(id: 'seed-transport', name: 'Transport'),
    ],
    uncategorizedName: 'Uncategorized',
  );
  return db;
}

/// A day inside the period the screen opens on.
///
/// Derived from the app's active calendar rather than DateTime.now().month:
/// the app defaults to Jalali, and anchoring a fixture to a Gregorian month
/// puts rows outside the period on screen for reasons unrelated to the code
/// under test.
DateTime dayInThisMonth(int offset) {
  const calendar = JalaliCalendar();
  final period = calendar.periodContaining(
    DateKey.fromDateTime(DateTime.now()),
    PeriodType.month,
  );
  final start = period.startInclusive.toDateTime();
  return DateTime(start.year, start.month, start.day, 10)
      .add(Duration(days: offset));
}

Future<void> seedSpending(
  AppDatabase db, {
  bool groceriesUnconfirmed = false,
}) async {
  final repo =
      TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman);
  Future<void> add(String category, int amount,
          {int day = 2, bool confirmed = true}) =>
      repo.add(TransactionDraft(
        amount: Money(amount),
        direction: TxDirection.expense,
        categoryId: category,
        occurredAtUtc: dayInThisMonth(day).toUtc(),
        isConfirmed: confirmed,
      ));

  await add('seed-groceries', 1000, confirmed: !groceriesUnconfirmed);
  await add('seed-dining', 500, day: 3);
  await add('seed-transport', 250, day: 4);
}

/// 300 on Transport five days before this month starts, i.e. in the month
/// before it: a month back with something in it, so the body draws a total
/// instead of the empty state.
Future<void> seedLastMonth(AppDatabase db) async {
  final repo =
      TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman);
  await repo.add(TransactionDraft(
    amount: Money(300),
    direction: TxDirection.expense,
    categoryId: 'seed-transport',
    occurredAtUtc: dayInThisMonth(-5).toUtc(),
  ));
}

/// A realistic phone viewport, 360x800 logical.
///
/// The default 800x600 test surface is shorter than any phone this ships on,
/// and a ListView does not build rows below the fold -- so on the default
/// surface a `findsNothing` cannot tell "filtered out" from "not built yet",
/// which is exactly what the drill-down assertions turn on.
void usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> openBreakdown(WidgetTester tester, AppDatabase db) async {
  usePhoneViewport(tester);
  await pumpApp(tester, database: db);
  await tester.tap(find.descendant(
    of: find.byKey(const Key('nav-bar')),
    matching: find.text('Analytics'),
  ));
  await tester.pumpAndSettle();
  // Analytics opens on the dashboard; Breakdown is the next tab.
  await tester.tap(find.byKey(const Key('analytics-tab-breakdown')));
  await tester.pumpAndSettle();
}

/// Persian digits with the U+066C separator, because the app's default
/// settings locale is fa and the money formatter follows the settings rather
/// than the widget-tree locale. Latin values are named for the reader.
const total1750 = '۱٬۷۵۰'; // 1,750
const total1500 = '۱٬۵۰۰'; // 1,500
const total750 = '۷۵۰'; // 750
const amount250 = '۲۵۰'; // 250

/// The text of a keyed widget, so an amount is compared exactly rather than
/// by a substring search that a different row could satisfy.
String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('an empty period says so rather than drawing an empty pie',
      (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await openBreakdown(tester, db);

    expect(find.byType(NimbusEmptyState), findsOneWidget);
    expect(find.byType(PieChart), findsNothing);
  });

  testWidgets('top-level categories roll their children up', (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openBreakdown(tester, db);

    // Food is 1000 + 500 rolled up from its two children, not a leaf of its
    // own -- no transaction is filed directly against it.
    expect(find.byKey(const Key('breakdown-row-seed-food')), findsOneWidget);
    expect(find.byKey(const Key('breakdown-row-seed-transport')),
        findsOneWidget);
    expect(find.byKey(const Key('breakdown-row-seed-groceries')), findsNothing);
    expect(textOf(tester, 'breakdown-amount-seed-food'), total1500);
    expect(textOf(tester, 'breakdown-amount-seed-transport'), amount250);
  });

  testWidgets('the header shows the true total, not the sum of slices',
      (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openBreakdown(tester, db);

    expect(textOf(tester, 'breakdown-total-amount'), total1750);
  });

  testWidgets('a category breakdown draws a pie', (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openBreakdown(tester, db);

    expect(find.byType(PieChart), findsOneWidget);
  });

  testWidgets('categories do not overlap, so no disclosure is shown',
      (tester) async {
    // The banner has to be absent here to mean anything when it appears on a
    // tag chart. A screen that always warns is a screen nobody reads.
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openBreakdown(tester, db);

    expect(find.byType(NimbusDisclosureBanner), findsNothing);
  });

  testWidgets('tapping a category drills into its children', (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openBreakdown(tester, db);

    await tester.tap(find.byKey(const Key('breakdown-row-seed-food')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('breakdown-row-seed-groceries')),
        findsOneWidget);
    expect(find.byKey(const Key('breakdown-row-seed-dining')), findsOneWidget);
    expect(find.byKey(const Key('breakdown-row-seed-transport')), findsNothing);
    // The total follows the drill-down: inside Food it is Food's total.
    expect(textOf(tester, 'breakdown-total-amount'), total1500);
  });

  testWidgets('the breadcrumb walks back out', (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openBreakdown(tester, db);

    await tester.tap(find.byKey(const Key('breakdown-row-seed-food')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('breakdown-crumb-root')), findsOneWidget);

    await tester.tap(find.byKey(const Key('breakdown-crumb-root')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('breakdown-row-seed-transport')),
        findsOneWidget);
  });

  testWidgets('a leaf category does not pretend to drill further',
      (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openBreakdown(tester, db);

    await tester.tap(find.byKey(const Key('breakdown-row-seed-transport')));
    await tester.pumpAndSettle();

    // Transport has no children, so the view must stay put rather than
    // dropping to an empty level the user has to back out of.
    expect(find.byKey(const Key('breakdown-row-seed-food')), findsOneWidget);
    expect(find.byType(NimbusEmptyState), findsNothing);
  });

  testWidgets('the confirmed-only toggle changes the numbers', (tester) async {
    // The brief requires this decision to be visible rather than buried in a
    // default, and the same everywhere: unconfirmed captures are counted
    // unless the user says otherwise.
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db, groceriesUnconfirmed: true);
    await openBreakdown(tester, db);

    expect(textOf(tester, 'breakdown-total-amount'), total1750);

    await tester.tap(find.byKey(const Key('breakdown-confirmed-only')));
    await tester.pumpAndSettle();

    expect(textOf(tester, 'breakdown-total-amount'), total750);
  });

  testWidgets('an archived category still appears in history', (tester) async {
    // Archived is a picker concern. Removing it from results would silently
    // shrink last month's spending the moment somebody tidied their tree.
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    await db.categoriesDao.setArchivedSubtree('seed-transport', true);
    await openBreakdown(tester, db);

    expect(find.byKey(const Key('breakdown-row-seed-transport')),
        findsOneWidget);
  });

  testWidgets('the period can be moved and the total follows', (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openBreakdown(tester, db);

    await tester.tap(find.byKey(const Key('breakdown-period-previous')));
    await tester.pumpAndSettle();

    expect(find.byType(NimbusEmptyState), findsOneWidget);
  });

  testWidgets('on the current month the total is captioned "This month"',
      (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openBreakdown(tester, db);

    expect(textOf(tester, 'breakdown-total-label'), 'This month');
  });

  testWidgets('a month back, the total is captioned with the month it covers',
      (tester) async {
    // The caption sits under a month bar that names the month. Left as a
    // constant "This month" it claimed a past month's total was the current
    // month's -- the one line on the screen that was simply false.
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    await seedLastMonth(db);
    await openBreakdown(tester, db);

    await tester.tap(find.byKey(const Key('breakdown-period-previous')));
    await tester.pumpAndSettle();

    expect(textOf(tester, 'breakdown-total-label'),
        textOf(tester, 'breakdown-period-label'));
  });

  testWidgets('the breakdown renders right-to-left in Persian',
      (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    usePhoneViewport(tester);
    await pumpApp(tester, database: db, locale: const Locale('fa'));
    await tester.tap(find.descendant(
      of: find.byKey(const Key('nav-bar')),
      matching: find.byIcon(Icons.insights_outlined),
    ));
    await tester.pumpAndSettle();
    // Analytics opens on the dashboard; Breakdown is the next tab.
    await tester.tap(find.byKey(const Key('analytics-tab-breakdown')));
    await tester.pumpAndSettle();

    expect(
      Directionality.of(tester.element(find.byKey(const Key('breakdown-total')))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}
