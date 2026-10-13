import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbustats/features/notifications/application/notification_providers.dart';
import 'package:nimbustats/features/notifications/data/notification_prefs.dart';
import 'package:nimbustats/features/settings/data/settings_keys.dart';

import '../../support/harness.dart';
import '../trackers/support/tracker_fixture.dart';
import 'support/fake_outside_channel.dart';

void main() {
  late AppDatabase db;
  late FakeOutsideChannel outside;

  setUp(() {
    db = AppDatabase.openInMemory();
    outside = FakeOutsideChannel();
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester,
      {Locale locale = const Locale('en'), List<Override> overrides = const []}) async {
    // Digits follow the *settings* locale (AppSettings.persianDigits), whose
    // default is fa. An English test saves English so its times read 21:00.
    if (locale.languageCode == 'en') await useEnglishDigits(db);
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        outside: outside,
        initialLocation: '/settings',
        locale: locale,
        overrides: overrides);
    await tester.scrollUntilVisible(
        find.byKey(const Key('notifications-section')), 200);
    await tester.pumpAndSettle();
  }

  bool switchOn(WidgetTester tester, String key) =>
      tester.widget<SwitchListTile>(find.byKey(Key(key))).value;

  testWidgets('switching the reminder on asks, saves and arms; the time shows',
      (tester) async {
    await open(tester);
    expect(find.byKey(const Key('notifications-reminder-time')), findsNothing);

    await tester.tap(find.byKey(const Key('notifications-reminder')));
    await tester.pumpAndSettle();

    expect(outside.permissionRequests, 1);
    expect(await db.settingsDao.get(SettingsKeys.reminderEnabled), 'true');
    expect(outside.reminders.last.enabled, isTrue);
    expect(switchOn(tester, 'notifications-reminder'), isTrue);
    expect(find.text('21:00'), findsOneWidget);
  });

  testWidgets('a denied permission leaves it off and shows the blocked row; '
      '"Open settings" opens Android\'s', (tester) async {
    outside
      ..grant = false
      ..enabled = false;
    await open(tester);

    await tester.tap(find.byKey(const Key('notifications-reminder')));
    await tester.pumpAndSettle();

    expect(switchOn(tester, 'notifications-reminder'), isFalse);
    expect(outside.reminders.where((r) => r.enabled), isEmpty);
    expect(find.byKey(const Key('notifications-blocked')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notifications-open-settings')));
    await tester.pumpAndSettle();
    expect(outside.settingsOpened, 1);
  });

  testWidgets('a reminder left on while notifications are blocked shows the '
      'row', (tester) async {
    await NotificationPrefsRepository(db.settingsDao)
        .setReminder(enabled: true, minuteOfDay: 1260);
    outside.enabled = false;
    await open(tester);

    expect(find.byKey(const Key('notifications-blocked')), findsOneWidget);
  });

  testWidgets('a new time is saved and re-armed', (tester) async {
    await NotificationPrefsRepository(db.settingsDao)
        .setReminder(enabled: true, minuteOfDay: 1260);
    await open(tester);

    await tester.tap(find.byKey(const Key('notifications-reminder-time')));
    await tester.pumpAndSettle();
    // The picker's text-input mode: two fields, hour then minute.
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '07');
    await tester.enterText(find.byType(TextField).at(1), '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(await db.settingsDao.get(SettingsKeys.reminderMinuteOfDay), '450');
    expect(outside.reminders.last.minuteOfDay, 450);
    expect(find.text('07:30'), findsOneWidget);
  });

  testWidgets('the details switch persists', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('notifications-details')));
    await tester.pumpAndSettle();

    expect(await db.settingsDao.get(SettingsKeys.notificationDetail), 'true');
    expect(switchOn(tester, 'notifications-details'), isTrue);
  });

  testWidgets('loading, then error with a retry', (tester) async {
    final never = StreamController<NotificationPrefs>();
    addTearDown(never.close);
    await open(tester, overrides: [
      notificationPrefsProvider.overrideWith((ref) => never.stream),
    ]);
    expect(find.byKey(const Key('notifications-loading')), findsOneWidget);

    never.addError(StateError('disk'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notifications-error')), findsOneWidget);
    expect(find.byType(NimbusErrorState), findsOneWidget);
  });

  testWidgets('Persian: the section reads in Persian with Persian digits',
      (tester) async {
    await NotificationPrefsRepository(db.settingsDao)
        .setReminder(enabled: true, minuteOfDay: 1260);
    await open(tester, locale: const Locale('fa'));

    expect(find.text('اعلان‌ها'), findsOneWidget);
    expect(find.text('۲۱:۰۰'), findsOneWidget);
  });

  testWidgets('every control is a 48 dp target', (tester) async {
    await NotificationPrefsRepository(db.settingsDao)
        .setReminder(enabled: true, minuteOfDay: 1260);
    outside.enabled = false;
    await open(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });
}
