import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/dashboard_fixture.dart';

Future<void> pinAndSave(WidgetTester tester, String pinKey) async {
  // The previous pin's "Pinned" snackbar sits over the bottom of the screen
  // for four seconds; a pin scrolled into view there would miss the tap.
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
      .clearSnackBars();
  await tester.pumpAndSettle();
  final pin = find.byKey(Key(pinKey));
  await revealInTab(tester, pin);
  await tester.tap(pin);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('view-name-save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pinning a drilled-in breakdown saves it under the crumb name',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openAnalytics(tester, db);
    await showTab(tester, 'analytics-tab-breakdown');
    await tester.tap(find.byKey(const Key('breakdown-row-seed-food')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pin-breakdown')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('view-name-field')))
          .controller!
          .text,
      'Food',
    );
    // The sheet says what the card will cover before anything is saved.
    expect(find.text('Shows whichever month the dashboard is on'),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('view-name-save')));
    await tester.pumpAndSettle();

    final views = await storedViews(db);
    final foodPath = (await db.categoriesDao.byId('seed-food'))!.path;
    expect(views, hasLength(1));
    expect(views.single.name, 'Food');
    expect(views.single.chart, 'breakdown');
    expect((views.single.periodType, views.single.periodCount), ('month', 1));
    final filters = views.single.spec['filters']! as Map<String, Object?>;
    expect(filters['categorySubtreePaths'], [foodPath]);
    expect(filters.containsKey('dateRange'), isFalse);
    expect(find.text('Pinned to the dashboard'), findsOneWidget);
  });

  testWidgets('each tab and pattern chart pins its own kind of chart',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openAnalytics(tester, db);

    await showTab(tester, 'analytics-tab-trends');
    await pinAndSave(tester, 'pin-trend');
    await showTab(tester, 'analytics-tab-crosstab');
    await pinAndSave(tester, 'pin-crossTab');
    await showTab(tester, 'analytics-tab-patterns');
    await pinAndSave(tester, 'pin-hourOfDay');
    await pinAndSave(tester, 'pin-dayOfWeek');
    await pinAndSave(tester, 'pin-reflection');

    final views = await storedViews(db);
    expect(views.map((v) => v.chart),
        ['trend', 'crossTab', 'hourOfDay', 'dayOfWeek', 'reflection']);
    expect(views.first.name, 'Last 6 months');
    expect(views.first.periodCount, 6);
    expect(views.skip(1).map((v) => v.periodCount), everyElement(1));
  });

  testWidgets('a blank name cannot be saved', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await openAnalytics(tester, db);
    await showTab(tester, 'analytics-tab-breakdown');
    await tester.tap(find.byKey(const Key('pin-breakdown')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('view-name-field')), '   ');
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('view-name-save')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('dismissing the sheet pins nothing', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await openAnalytics(tester, db);
    await showTab(tester, 'analytics-tab-breakdown');
    await tester.tap(find.byKey(const Key('pin-breakdown')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await storedViews(db), isEmpty);
  });
}
