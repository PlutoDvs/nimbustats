import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/transactions/data/transaction_draft.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';

import '../../../support/harness.dart';

/// Food (Groceries, Dining) and Transport, plus Uncategorized.
Future<AppDatabase> categorisedDb() async {
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

/// A day in the month the dashboard opens on: the Jalali month containing
/// today, because Jalali is the app's default calendar.
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

/// Groceries 1000, Dining 500, Transport 250: 1750 this month.
/// Returns the three transactions' ids in that order.
Future<List<String>> seedSpending(
  AppDatabase db, {
  List<String> diningTags = const [],
  List<String> transportTags = const [],
}) async {
  final repo =
      TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman);
  Future<String> add(String category, int amount, int day, List<String> tags) async =>
      (await repo.add(TransactionDraft(
        amount: Money(amount),
        direction: TxDirection.expense,
        categoryId: category,
        occurredAtUtc: dayInThisMonth(day).toUtc(),
        tagIds: tags,
      )))
          .id;

  return [
    await add('seed-groceries', 1000, 1, const []),
    await add('seed-dining', 500, 2, diningTags),
    await add('seed-transport', 250, 3, transportTags),
  ];
}

/// A realistic phone viewport, 360x800 logical. The default test surface is
/// shorter than any phone this ships on, and lists do not build below it.
void usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Pumps the app on [db] at phone size and opens Analytics.
Future<void> openAnalytics(
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
}

/// Switches Analytics to the tab keyed [tabKey]. The tab bar scrolls, so the
/// tab is brought into view first -- a tap outside the viewport lands on
/// nothing and silently leaves the current tab showing.
Future<void> showTab(WidgetTester tester, String tabKey) async {
  final tab = find.byKey(Key(tabKey));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view inside the current analytics tab.
///
/// Never tester.ensureVisible here: that aligns the target to the start of
/// every scrollable above it -- TabBarView's horizontal page view included --
/// and the page view then snaps to the next tab before a tap lands.
/// keepVisibleAtEnd scrolls only when the target is off-screen, so an
/// already-visible page never moves sideways.
Future<void> revealInTab(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
  );
  await tester.pumpAndSettle();
}

/// Persian digits with the U+066C separator: the app's default settings
/// locale is fa, and money follows settings, not the widget-tree locale.
const total1750 = '۱٬۷۵۰'; // 1,750
const total1000 = '۱٬۰۰۰'; // 1,000
const total750 = '۷۵۰'; // 750

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

/// A stored view as the database holds it.
typedef StoredView = ({
  String id,
  String name,
  String chart,
  String periodType,
  int periodCount,
  Map<String, Object?> spec,
});

/// Live saved views in dashboard order, read with a plain query: awaiting a
/// drift stream inside a widget test's fake clock can stall.
Future<List<StoredView>> storedViews(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT id, name, chart_type, period_type, period_count, '
          'spec_json FROM saved_views WHERE deleted_at IS NULL '
          'ORDER BY sort_order')
      .get();
  return [
    for (final row in rows)
      (
        id: row.read<String>('id'),
        name: row.read<String>('name'),
        chart: row.read<String>('chart_type'),
        periodType: row.read<String>('period_type'),
        periodCount: row.read<int>('period_count'),
        spec: jsonDecode(row.read<String>('spec_json')) as Map<String, Object?>,
      ),
  ];
}
