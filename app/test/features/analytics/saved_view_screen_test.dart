import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/dashboard_fixture.dart';

Future<void> openCard(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('card-name-$id')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping a card opens its view full screen, over the shell',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, _) = await pinStarters(db);
    await openAnalytics(tester, db);

    await openCard(tester, breakdown);

    expect(textOf(tester, 'saved-view-title'), 'This month by category');
    expect(textOf(tester, 'breakdown-total-amount'), total1750);
    // On the dashboard's own month the caption still reads "This month": a
    // view's period resolved against today has to land on the same range the
    // tabs call the current month, or every card would show a number here.
    expect(textOf(tester, 'breakdown-total-label'), 'This month');
    expect(find.byKey(const Key('nav-bar')), findsNothing);
  });

  testWidgets(
      "it starts on the dashboard's month and moves without moving the dashboard",
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, _) = await pinStarters(db);
    await openAnalytics(tester, db);
    await tester.tap(find.byKey(const Key('dashboard-period-previous')));
    await tester.pumpAndSettle();
    final dashboardMonth = textOf(tester, 'dashboard-period-label');

    await openCard(tester, breakdown);
    expect(textOf(tester, 'saved-view-period-label'), dashboardMonth);
    expect(find.byKey(const Key('breakdown-total-amount')), findsNothing);

    await tester.tap(find.byKey(const Key('saved-view-period-next')));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'breakdown-total-amount'), total1750);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(textOf(tester, 'dashboard-period-label'), dashboardMonth);
  });

  testWidgets('opened on a past month, the total is captioned with that month',
      (tester) async {
    // The screen has one month bar shared across chart types, so the body it
    // draws must caption its total with the month the bar names.
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    await seedLastMonthSpending(db);
    final (breakdown, _) = await pinStarters(db);
    await openAnalytics(tester, db);
    await tester.tap(find.byKey(const Key('dashboard-period-previous')));
    await tester.pumpAndSettle();

    await openCard(tester, breakdown);

    expect(textOf(tester, 'breakdown-total-label'),
        textOf(tester, 'saved-view-period-label'));
  });

  testWidgets('a pinned breakdown does not drill past its level',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, _) = await pinStarters(db);
    await openAnalytics(tester, db);

    await openCard(tester, breakdown);

    expect(
      tester.widget<ListTile>(find.byKey(const Key('breakdown-row-seed-food'))).onTap,
      isNull,
    );
  });

  testWidgets('a trend view draws the full trend chart', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (_, trend) = await pinStarters(db);
    await openAnalytics(tester, db);

    await openCard(tester, trend);

    expect(find.byKey(const Key('trends-chart')), findsOneWidget);
  });

  testWidgets('rename from the full screen updates its title', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final (breakdown, _) = await pinStarters(db);
    await openAnalytics(tester, db);
    await openCard(tester, breakdown);

    await tester.tap(find.byKey(const Key('saved-view-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-view-menu-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('view-name-field')), 'Food watch');
    await tester.tap(find.byKey(const Key('view-name-save')));
    await tester.pumpAndSettle();

    expect(textOf(tester, 'saved-view-title'), 'Food watch');
  });

  testWidgets('remove from the full screen returns to the dashboard with undo',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final (breakdown, trend) = await pinStarters(db);
    await openAnalytics(tester, db);
    await openCard(tester, breakdown);

    await tester.tap(find.byKey(const Key('saved-view-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-view-menu-remove')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-tab')), findsOneWidget);
    expect(find.byKey(Key('saved-view-card-$breakdown')), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect((await storedViews(db)).map((v) => v.id), [breakdown, trend]);
  });
}
