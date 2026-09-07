import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/analytics/application/trends_controller.dart';
import 'package:nimbustats/features/transactions/data/transaction_draft.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';

import '../../support/harness.dart';

Future<AppDatabase> seededDb() async {
  final db = AppDatabase.openInMemory();
  await CategorySeeder(db).seedIfEmpty(
    roots: const [SeedCategoryNode(id: 'seed-food', name: 'Food')],
    uncategorizedName: 'Uncategorized',
  );
  return db;
}

/// A day inside the Jalali month [monthsAgo] before the current one.
///
/// Built through the calendar rather than by subtracting 30 days: months are
/// not a fixed length in either calendar, and "roughly a month ago" lands in
/// the wrong bucket often enough to make a trend test flaky by date.
DateTime dayInMonth(int monthsAgo) {
  const calendar = JalaliCalendar();
  var period = calendar.periodContaining(
    DateKey.fromDateTime(DateTime.now()),
    PeriodType.month,
  );
  if (monthsAgo > 0) {
    period = calendar.shiftPeriod(period, PeriodType.month, -monthsAgo);
  }
  final start = period.startInclusive.toDateTime();
  // The second day, so a month boundary never rounds the fixture out of its
  // own period.
  return DateTime(start.year, start.month, start.day, 10)
      .add(const Duration(days: 1));
}

Future<void> addExpense(AppDatabase db, int amount, int monthsAgo) =>
    TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman).add(
      TransactionDraft(
        amount: Money(amount),
        direction: TxDirection.expense,
        categoryId: 'seed-food',
        occurredAtUtc: dayInMonth(monthsAgo).toUtc(),
      ),
    );

void usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> openTrends(
  WidgetTester tester,
  AppDatabase db, {
  Locale locale = const Locale('en'),
}) async {
  usePhoneViewport(tester);
  await pumpApp(tester, database: db, locale: locale);
  await tester.tap(find.descendant(
    of: find.byKey(const Key('nav-bar')),
    matching: find.byIcon(Icons.insights_outlined),
  ));
  await tester.pumpAndSettle();
  // The tab bar scrolls, so a later tab can sit outside the viewport --
  // tapping it there lands on nothing and silently leaves the first tab
  // showing, which reads as a broken screen rather than a missed tap.
  final tab = find.byKey(const Key('analytics-tab-trends'));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

LineChartData chartData(WidgetTester tester) =>
    tester.widget<LineChart>(find.byKey(const Key('trends-chart'))).data;

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('analytics offers both a breakdown and a trend', (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    usePhoneViewport(tester);
    await pumpApp(tester, database: db);
    await tester.tap(find.descendant(
      of: find.byKey(const Key('nav-bar')),
      matching: find.byIcon(Icons.insights_outlined),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('analytics-tab-breakdown')), findsOneWidget);
    expect(find.byKey(const Key('analytics-tab-trends')), findsOneWidget);
    // Breakdown is the landing tab: it answers "where did it go", which is the
    // question somebody opening analytics has. Asserted on the period bar
    // rather than the total, because the total only exists once there is
    // spending and this database deliberately has none.
    expect(find.byKey(const Key('breakdown-period-label')), findsOneWidget);
  });

  testWidgets('a month with no spending is a zero, not a gap', (tester) async {
    // The engine returns buckets only for periods that matched rows. A chart
    // that plotted those directly would draw a line straight from March to
    // June and call the quiet months a trend.
    final db = await seededDb();
    addTearDown(db.close);
    await addExpense(db, 1000, 0);
    await addExpense(db, 500, 3);
    await openTrends(tester, db);

    final spots = chartData(tester).lineBarsData.single.spots;
    expect(spots, hasLength(TrendsView.defaultPeriodCount));
    // Oldest first, so the last point is the current month.
    expect(spots.last.y, 1000);
    expect(spots[spots.length - 4].y, 500);
    expect(spots[spots.length - 2].y, 0,
        reason: 'a month with no rows is zero spending, not a missing point');
  });

  testWidgets('the trend covers a fixed window of periods', (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await addExpense(db, 1000, 0);
    await openTrends(tester, db);

    expect(chartData(tester).lineBarsData.single.spots,
        hasLength(TrendsView.defaultPeriodCount));
  });

  testWidgets('the comparison names both periods and the change',
      (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await addExpense(db, 1000, 0);
    await addExpense(db, 500, 1);
    await openTrends(tester, db);

    expect(textOf(tester, 'trends-comparison-current'), '۱٬۰۰۰'); // 1,000
    expect(textOf(tester, 'trends-comparison-previous'), '۵۰۰'); // 500
    // Doubling is +100%, and the sign has to be there: "100%" alone reads as
    // "spent the same".
    expect(textOf(tester, 'trends-comparison-delta'), contains('۱۰۰'));
    expect(textOf(tester, 'trends-comparison-delta'), contains('+'));
  });

  testWidgets('a fall in spending reads as a fall', (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await addExpense(db, 250, 0);
    await addExpense(db, 500, 1);
    await openTrends(tester, db);

    expect(textOf(tester, 'trends-comparison-delta'), contains('−'));
    expect(textOf(tester, 'trends-comparison-delta'), contains('۵۰'));
  });

  testWidgets('no baseline is said in words, not as a division',
      (tester) async {
    // Last month zero makes the percentage undefined. Infinity% or NaN% on a
    // user's screen is the kind of thing that gets screenshotted.
    final db = await seededDb();
    addTearDown(db.close);
    await addExpense(db, 1000, 0);
    await openTrends(tester, db);

    // Asserted as the localized sentence rather than "no % sign", so the
    // assertion keeps its teeth if the percent glyph ever changes.
    expect(textOf(tester, 'trends-comparison-delta'), 'No spending to compare');
  });

  testWidgets('an empty database says so instead of drawing a flat line',
      (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await openTrends(tester, db);

    expect(find.byType(NimbusEmptyState), findsOneWidget);
    expect(find.byKey(const Key('trends-chart')), findsNothing);
  });

  test('an axis label is compact and follows the settings digits', () {
    // Tested as a function rather than by reaching into fl_chart's TitleMeta:
    // what must hold is that the label goes through the app's formatter, so
    // an axis cannot end up in Latin digits beside Persian amounts. Coupling
    // the assertion to the chart library's internals would test fl_chart.
    const persian = MoneyFormatter(currency: Currency.toman, persianDigits: true);
    expect(trendsAxisLabel(1000, persian), '۱K');
    expect(trendsAxisLabel(0, persian), '۰');

    const latin = MoneyFormatter(currency: Currency.toman, persianDigits: false);
    expect(trendsAxisLabel(1500000, latin), '1.5M');
  });

  testWidgets('the trend renders right-to-left in Persian', (tester) async {
    final db = await seededDb();
    addTearDown(db.close);
    await addExpense(db, 1000, 0);
    await openTrends(tester, db, locale: const Locale('fa'));

    expect(
      Directionality.of(tester.element(find.byKey(const Key('trends-chart')))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}
