import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/transactions/data/transaction_draft.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';

import '../../support/harness.dart';

/// Three expenses at known hours, with two of them reflected on:
///
///   1000  10:00  needed / glad
///    500  14:00  avoidable / regret
///    250  22:00  neither set
Future<AppDatabase> seeded() async {
  final db = AppDatabase.openInMemory();
  await CategorySeeder(db).seedIfEmpty(
    roots: const [SeedCategoryNode(id: 'seed-food', name: 'Food')],
    uncategorizedName: 'Uncategorized',
  );

  final repo =
      TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman);
  Future<void> add(
    int amount,
    int hour, {
    Necessity? necessity,
    Satisfaction? satisfaction,
  }) =>
      repo.add(TransactionDraft(
        amount: Money(amount),
        direction: TxDirection.expense,
        categoryId: 'seed-food',
        occurredAtUtc: dayInThisMonth(hour).toUtc(),
        necessity: necessity,
        satisfaction: satisfaction,
      ));

  await add(1000, 10,
      necessity: Necessity.needed, satisfaction: Satisfaction.glad);
  await add(500, 14,
      necessity: Necessity.avoidable, satisfaction: Satisfaction.regret);
  await add(250, 22);
  return db;
}

DateTime dayInThisMonth(int hour) {
  const calendar = JalaliCalendar();
  final period = calendar.periodContaining(
    DateKey.fromDateTime(DateTime.now()),
    PeriodType.month,
  );
  final start = period.startInclusive.toDateTime();
  return DateTime(start.year, start.month, start.day, hour)
      .add(const Duration(days: 1));
}

void usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> openPatterns(
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
  final tab = find.byKey(const Key('analytics-tab-patterns'));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

BarChartData barsOf(WidgetTester tester, String key) =>
    tester.widget<BarChart>(find.byKey(Key(key))).data;

double valueAt(BarChartData data, int x) =>
    data.barGroups.firstWhere((g) => g.x == x).barRods.first.toY;

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('every hour of the day has a bar', (tester) async {
    // The engine returns buckets only for hours that matched rows. A chart
    // that plotted those would put three bars side by side and imply spending
    // happens at every hour of the day.
    final db = await seeded();
    addTearDown(db.close);
    await openPatterns(tester, db);

    final data = barsOf(tester, 'patterns-hour-chart');
    expect(data.barGroups, hasLength(24));
    expect(valueAt(data, 10), 1000);
    expect(valueAt(data, 14), 500);
    expect(valueAt(data, 22), 250);
    expect(valueAt(data, 3), 0, reason: 'a quiet hour is zero, not missing');
  });

  testWidgets('every day of the week has a bar', (tester) async {
    final db = await seeded();
    addTearDown(db.close);
    await openPatterns(tester, db);

    expect(barsOf(tester, 'patterns-weekday-chart').barGroups, hasLength(7));
  });

  testWidgets('the week starts on the day the settings say', (tester) async {
    // Iran's week starts on Saturday and that is the app default. A chart that
    // started on Monday would shift every bar by two days in a way that reads
    // as data rather than as a bug.
    final db = await seeded();
    addTearDown(db.close);
    await openPatterns(tester, db);

    expect(textOf(tester, 'patterns-weekday-label-0'), 'Sat');
    expect(textOf(tester, 'patterns-weekday-label-6'), 'Fri');
  });

  testWidgets('the reflection matrix keeps its unset row and column',
      (tester) async {
    // Phase 1 deliberately keeps both axes off the add-expense path, so most
    // spending is unreflected. Dropping those cells would hide the majority of
    // the data and make the matrix look complete.
    final db = await seeded();
    addTearDown(db.close);
    await openPatterns(tester, db);

    expect(textOf(tester, 'patterns-reflection-needed-glad'), '۱٬۰۰۰');
    expect(textOf(tester, 'patterns-reflection-avoidable-regret'), '۵۰۰');
    expect(textOf(tester, 'patterns-reflection-unset-unset'), '۲۵۰');
  });

  testWidgets('these dimensions do not overlap, so nothing is disclosed',
      (tester) async {
    // An hour, a weekday and a reflection cell each hold a transaction once.
    // A banner here would train people to ignore the one on the tag matrix.
    final db = await seeded();
    addTearDown(db.close);
    await openPatterns(tester, db);

    expect(find.byType(NimbusDisclosureBanner), findsNothing);
  });

  testWidgets('an empty period says so rather than drawing empty axes',
      (tester) async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    await CategorySeeder(db).seedIfEmpty(
      roots: const [SeedCategoryNode(id: 'seed-food', name: 'Food')],
      uncategorizedName: 'Uncategorized',
    );
    await openPatterns(tester, db);

    expect(find.byType(NimbusEmptyState), findsOneWidget);
    expect(find.byKey(const Key('patterns-hour-chart')), findsNothing);
  });

  testWidgets('patterns render right-to-left in Persian', (tester) async {
    final db = await seeded();
    addTearDown(db.close);
    await openPatterns(tester, db, locale: const Locale('fa'));

    expect(
      Directionality.of(
          tester.element(find.byKey(const Key('patterns-hour-chart')))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}
