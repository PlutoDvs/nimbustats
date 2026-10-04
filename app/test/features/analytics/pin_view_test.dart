import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';

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

/// The Breakdown tab's pin sheet, opened over the starter cards -- one of
/// which already carries the name the sheet suggests.
Future<AppDatabase> openPinOverStarters(WidgetTester tester) async {
  final db = await categorisedDb();
  addTearDown(db.close);
  await pinStarters(db);
  await openAnalytics(tester, db);
  await showTab(tester, 'analytics-tab-breakdown');
  await tester.tap(find.byKey(const Key('pin-breakdown')));
  await tester.pumpAndSettle();
  return db;
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

  testWidgets('pinning under a name a card already has warns, but saves',
      (tester) async {
    // D14: the Breakdown tab suggests "Spending by category", which the
    // breakdown starter already carries, and two cards titled alike cannot be
    // told apart on the dashboard. The sheet says so and leaves the choice to
    // the user, rather than refusing or picking a name for them.
    final db = await openPinOverStarters(tester);

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('view-name-field')))
          .controller!
          .text,
      'Spending by category',
    );
    expect(find.text('A card on the dashboard already has this name'),
        findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('view-name-save')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('view-name-save')));
    await tester.pumpAndSettle();

    final names = (await storedViews(db)).map((v) => v.name).toList();
    expect(names, hasLength(3));
    expect(names.where((n) => n == 'Spending by category'), hasLength(2));
  });

  testWidgets('the warning clears once no card has the name', (tester) async {
    await openPinOverStarters(tester);

    await tester.enterText(
        find.byKey(const Key('view-name-field')), 'Groceries vs rent');
    await tester.pump();

    expect(find.byKey(const Key('view-name-taken')), findsNothing);
  });

  testWidgets('a name differing only in case and outer spaces still warns',
      (tester) async {
    // The sheet saves the name trimmed, and a reader takes "spending BY
    // category" for the same title as the card's.
    await openPinOverStarters(tester);

    await tester.enterText(
        find.byKey(const Key('view-name-field')), '  spending BY category ');
    await tester.pump();

    expect(find.byKey(const Key('view-name-taken')), findsOneWidget);
  });

  testWidgets('a failed pin says so', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    // A write failure part-way through the pin insert, injected where SQLite
    // itself would raise one.
    await db.customStatement(
        'CREATE TEMP TRIGGER fail_saved_view BEFORE INSERT ON saved_views '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END");
    await openAnalytics(tester, db);
    await showTab(tester, 'analytics-tab-breakdown');

    // The failure still has to reach the framework's error handler rather
    // than vanish once the snackbar has shown it -- caught here directly
    // because it comes from a detached future the button never awaits. The
    // whole flow has to run inside one zone: PinButton._pin is started by the
    // first tap, so that is where its error's zone is fixed, not the second.
    Object? caught;
    await runZonedGuarded(() async {
      await tester.tap(find.byKey(const Key('pin-breakdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('view-name-save')));
      await tester.pumpAndSettle();
    }, (error, stack) => caught = error);

    expect(find.text('Could not save the change'), findsOneWidget);
    expect(find.text('Pinned to the dashboard'), findsNothing);
    expect(await storedViews(db), isEmpty);
    expect(caught, isNotNull);
  });
}
