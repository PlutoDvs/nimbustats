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

  testWidgets('the first-day options are localized, not English literals',
      (tester) async {
    // These were hardcoded 'Sat'/'Sun'/'Mon' string literals from Phase 1, so
    // a Persian user picking their first day of week read English. Persian is
    // the app's default locale, which is what made it worth its own fix.
    await pumpApp(tester,
        seedFirstRun: true,
        initialLocation: '/settings',
        locale: const Locale('fa'));

    await tester.tap(find.byKey(const Key('settings-first-day')));
    await tester.pumpAndSettle();

    expect(find.text('Sat'), findsNothing);
    expect(find.text('شنبه'), findsWidgets);
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

  group('demo data', () {
    Future<void> tapSeed(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings-debug-seed')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('settings-debug-seed')));
      await tester.pumpAndSettle();
    }

    testWidgets('says so when there is nothing to attach rows to',
        (tester) async {
      // Found on a device: with no categories the button did nothing at all,
      // which reads as broken rather than as "not possible yet".
      await pumpApp(tester, initialLocation: '/settings');

      await tapSeed(tester);

      expect(find.text('No categories yet, so no demo data was added.'),
          findsOneWidget);
    });

    testWidgets('seeds even when settings is the first screen opened',
        (tester) async {
      // Nothing on the settings screen watches the category tree, so on a
      // launch straight into settings the tree may not have loaded when the
      // button is tapped. Reading it as empty would refuse to seed a database
      // that has a full tree.
      final db = await pumpApp(tester,
          seedFirstRun: true, initialLocation: '/settings');

      await tapSeed(tester);

      final rows = await db
          .customSelect('SELECT COUNT(*) AS c, '
              'SUM(payment_method_id IS NOT NULL) AS paid, '
              '(SELECT COUNT(DISTINCT transaction_id) FROM transaction_tags) '
              'AS tagged FROM transactions')
          .getSingle();
      expect(rows.data['c'], 5000);
      // The tile hands the seeder what the database holds: rows with no
      // payment method or no tags would leave those charts measuring nothing.
      expect(rows.data['paid'], greaterThan(0));
      expect(rows.data['tagged'], 5000);
    });
  });
}
