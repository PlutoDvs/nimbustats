import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';

import 'package:nimbustats/features/notifications/data/notification_prefs.dart';

import '../../support/harness.dart';
import 'support/fake_outside_channel.dart';

void main() {
  late AppDatabase db;
  late FakeOutsideChannel outside;

  setUp(() {
    db = AppDatabase.openInMemory();
    outside = FakeOutsideChannel();
  });
  tearDown(() => db.close());

  testWidgets('channels are named in the app language, and renamed after a '
      'language switch', (tester) async {
    // No locale override: the language comes from settings (fa by default).
    await pumpApp(
      tester,
      database: db,
      seedFirstRun: true,
      outside: outside,
      initialLocation: '/settings',
      locale: null,
    );

    expect(outside.channelTexts.last.alertsName, 'هشدارهای هدف');
    expect(outside.channelTexts.last.reminderName, 'یادآور روزانه');

    await tester.tap(find.byKey(const Key('settings-locale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('locale-en')));
    await tester.pumpAndSettle();

    expect(outside.channelTexts.last, (
      alertsName: 'Goal alerts',
      alertsDescription: 'Budget and limit warnings',
      reminderName: 'Daily reminder',
      reminderDescription: 'Your daily reminder to log',
    ));
  });

  testWidgets('the route a notification launched the app with opens after '
      'the first frame', (tester) async {
    outside.launchRoute = '/add';
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);

    expect(find.widgetWithText(AppBar, 'Add expense'), findsOneWidget);
    expect(outside.launchRoute, isNull, reason: 'taken once');
  });

  testWidgets('a notification tapped while the app runs opens its route', (
    tester,
  ) async {
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);
    expect(find.widgetWithText(AppBar, 'Add expense'), findsNothing);

    outside.tapRoute('/add');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Add expense'), findsOneWidget);
  });

  testWidgets('an armed reminder is re-pushed in the new language after a '
      'switch (Review Focus 5)', (tester) async {
    await NotificationPrefsRepository(db.settingsDao)
        .setReminder(enabled: true, minuteOfDay: 1260);
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        outside: outside,
        initialLocation: '/settings',
        locale: null);
    expect(outside.reminders.last.text, 'امروز چیزی برای ثبت دارید؟');

    await tester.tap(find.byKey(const Key('settings-locale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('locale-en')));
    await tester.pumpAndSettle();

    expect(outside.reminders.last, (
      enabled: true,
      minuteOfDay: 1260,
      text: 'Anything to log today?',
      route: '/add',
    ));
  });
}
