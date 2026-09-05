import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbustats/features/settings/data/settings_keys.dart';

import '../../support/harness.dart';

void main() {
  testWidgets('changing the calendar re-renders without a restart',
      (tester) async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    await pumpApp(
      tester,
      database: db,
      seedFirstRun: true,
      initialLocation: '/settings',
    );

    await tester.tap(find.byKey(const Key('settings-calendar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar-gregorian')));
    await tester.pumpAndSettle();

    expect(await db.settingsDao.get(SettingsKeys.calendarKind), 'gregorian');
    // The control reflects what the database now holds, without a restart.
    expect(find.text('Gregorian'), findsOneWidget);
  });

  testWidgets('changing the locale switches direction live', (tester) async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    // No locale override: this test is about the locale, so the app has to
    // take it from settings the way the shipped app does.
    await pumpApp(
      tester,
      database: db,
      seedFirstRun: true,
      initialLocation: '/settings',
      locale: null,
    );

    expect(
      Directionality.of(tester.element(find.byType(Scaffold).first)),
      TextDirection.rtl,
    );

    await tester.tap(find.byKey(const Key('settings-locale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('locale-en')));
    await tester.pumpAndSettle();

    expect(
      Directionality.of(tester.element(find.byType(Scaffold).first)),
      TextDirection.ltr,
    );
  });

  testWidgets('a corrupt setting surfaces with a reset action', (tester) async {
    // A value the database holds but the app cannot parse. Replacing it with a
    // default would hide that the user's data is wrong.
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    await db.settingsDao.put(SettingsKeys.themeMode, 'chartreuse');

    await pumpApp(tester, database: db, initialLocation: '/settings');
    expect(find.byType(NimbusErrorState), findsOneWidget);

    await tester.tap(find.text('Reset settings'));
    await tester.pumpAndSettle();

    expect(await db.settingsDao.get(SettingsKeys.themeMode), isNull);
    expect(find.byType(NimbusErrorState), findsNothing);
    expect(find.byKey(const Key('settings-theme')), findsOneWidget);
  });

  testWidgets('the entitlement label reads as a gift, not a countdown',
      (tester) async {
    await pumpApp(tester, seedFirstRun: true, initialLocation: '/settings');
    expect(find.text('Pro — free during early access'), findsOneWidget);
  });

  testWidgets('settings reaches the three managers', (tester) async {
    await pumpApp(tester, seedFirstRun: true, initialLocation: '/settings');

    // Scrolled to, not tapped blind: the nav shell took roughly a nav bar's
    // height off the viewport, and a ListView does not build what is below the
    // fold, so this tile is genuinely absent from the tree until scrolled into
    // view. That is what a user does too.
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-tags')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('settings-tags')));
    await tester.pumpAndSettle();
    expect(find.text('Tags'), findsWidgets);
  });
}
