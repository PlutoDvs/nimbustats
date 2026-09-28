import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/tags/data/tag_repository.dart';
import 'package:nimbustats/features/transactions/data/transaction_draft.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';

import '../../support/harness.dart';

/// Hand-computed from these rows, at category depth 0:
///
///   1000  dining (under food)  tags: travel, work
///    500  transport            tags: travel
///    250  dining               tags: none
///
///            food   transport   row total
///   travel   1000         500        1500
///   work     1000           -        1000
///
/// True total 1750. The cells sum to 2500 and the untagged 250 is in none of
/// them, so the matrix cannot be reconciled with the total by arithmetic.
typedef Fixture = ({AppDatabase db, String travel, String work});

Future<Fixture> seeded() async {
  final db = AppDatabase.openInMemory();
  await CategorySeeder(db).seedIfEmpty(
    roots: const [
      SeedCategoryNode(id: 'seed-food', name: 'Food', children: [
        SeedCategoryNode(id: 'seed-dining', name: 'Dining'),
      ]),
      SeedCategoryNode(id: 'seed-transport', name: 'Transport'),
    ],
    uncategorizedName: 'Uncategorized',
  );

  final tags = TagRepository(db.tagsDao);
  final travel = await tags.create(name: 'Travel');
  final work = await tags.create(name: 'Work');

  final repo =
      TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman);
  Future<void> add(int amount, String category, List<String> tagIds) =>
      repo.add(TransactionDraft(
        amount: Money(amount),
        direction: TxDirection.expense,
        categoryId: category,
        occurredAtUtc: dayInThisMonth().toUtc(),
        tagIds: tagIds,
      ));

  await add(1000, 'seed-dining', [travel, work]);
  await add(500, 'seed-transport', [travel]);
  await add(250, 'seed-dining', const []);

  return (db: db, travel: travel, work: work);
}

DateTime dayInThisMonth() {
  const calendar = JalaliCalendar();
  final period = calendar.periodContaining(
    DateKey.fromDateTime(DateTime.now()),
    PeriodType.month,
  );
  final start = period.startInclusive.toDateTime();
  return DateTime(start.year, start.month, start.day, 10)
      .add(const Duration(days: 1));
}

void usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> openCrossTab(
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
  final tab = find.byKey(const Key('analytics-tab-crosstab'));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('the total is captioned "This month", the only month it shows',
      (tester) async {
    // This tab has no period control: it is always the current month, so the
    // caption that a past month made false is right here and must stay.
    final f = await seeded();
    addTearDown(f.db.close);
    await openCrossTab(tester, f.db);

    expect(textOf(tester, 'crosstab-total-label'), 'This month');
  });

  testWidgets('a cell holds the amount for its tag and category',
      (tester) async {
    final f = await seeded();
    addTearDown(f.db.close);
    await openCrossTab(tester, f.db);

    expect(textOf(tester, 'crosstab-cell-${f.travel}-seed-food'), '۱٬۰۰۰');
    expect(textOf(tester, 'crosstab-cell-${f.travel}-seed-transport'), '۵۰۰');
    expect(textOf(tester, 'crosstab-cell-${f.work}-seed-food'), '۱٬۰۰۰');
  });

  testWidgets('a pair with no spending is blank, not a zero', (tester) async {
    // Work was never spent on transport. A zero there would read as "measured
    // and found to be nothing", which is a different claim from "never".
    final f = await seeded();
    addTearDown(f.db.close);
    await openCrossTab(tester, f.db);

    expect(find.byKey(Key('crosstab-cell-${f.work}-seed-transport')),
        findsNothing);
  });

  testWidgets('the disclosure is always shown here', (tester) async {
    // Not conditional on the data. A tag axis always overlaps, and a matrix
    // whose cells sum past the total without saying so is the trap the phase
    // brief opens with.
    final f = await seeded();
    addTearDown(f.db.close);
    await openCrossTab(tester, f.db);

    expect(find.byType(NimbusDisclosureBanner), findsOneWidget);
  });

  testWidgets('the header total counts each transaction once', (tester) async {
    final f = await seeded();
    addTearDown(f.db.close);
    await openCrossTab(tester, f.db);

    // 1750, not the 2500 the cells add up to.
    expect(textOf(tester, 'crosstab-total-amount'), '۱٬۷۵۰');
  });

  testWidgets('a row total is the tag total, and is shown', (tester) async {
    // Honest: within one tag's row the categories are disjoint, so a
    // transaction is counted once across it.
    final f = await seeded();
    addTearDown(f.db.close);
    await openCrossTab(tester, f.db);

    expect(textOf(tester, 'crosstab-row-total-${f.travel}'), '۱٬۵۰۰');
    expect(textOf(tester, 'crosstab-row-total-${f.work}'), '۱٬۰۰۰');
  });

  testWidgets('no column totals are offered', (tester) async {
    // Deliberately absent. Down a category column the same transaction appears
    // once per tag it carries, so a column total would be double counted --
    // and it would sit in a row of otherwise trustworthy numbers.
    final f = await seeded();
    addTearDown(f.db.close);
    await openCrossTab(tester, f.db);

    expect(find.byKey(const Key('crosstab-column-total-seed-food')),
        findsNothing);
  });

  testWidgets('an empty period says so rather than drawing an empty grid',
      (tester) async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    await CategorySeeder(db).seedIfEmpty(
      roots: const [SeedCategoryNode(id: 'seed-food', name: 'Food')],
      uncategorizedName: 'Uncategorized',
    );
    await openCrossTab(tester, db);

    expect(find.byType(NimbusEmptyState), findsOneWidget);
  });

  testWidgets('the matrix renders right-to-left in Persian', (tester) async {
    final f = await seeded();
    addTearDown(f.db.close);
    await openCrossTab(tester, f.db, locale: const Locale('fa'));

    expect(
      Directionality.of(
          tester.element(find.byKey(const Key('crosstab-total-amount')))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}
