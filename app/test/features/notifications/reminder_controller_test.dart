import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/provider_retry.dart';
import 'package:nimbustats/features/notifications/application/reminder_controller.dart';
import 'package:nimbustats/features/notifications/data/notification_prefs.dart';
import 'package:nimbustats/features/notifications/data/outside_channel.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

import 'support/fake_outside_channel.dart';

void main() {
  late AppDatabase db;
  late FakeOutsideChannel outside;
  late ReminderController reminder;
  late NotificationPrefsRepository prefs;
  final en = lookupAppLocalizations(const Locale('en'));

  setUp(() {
    db = AppDatabase.openInMemory();
    outside = FakeOutsideChannel();
    prefs = NotificationPrefsRepository(db.settingsDao);
    final c = ProviderContainer(retry: nimbusNoRetry, overrides: [
      appDatabaseProvider.overrideWithValue(db),
      outsideChannelProvider.overrideWithValue(outside),
    ]);
    addTearDown(c.dispose);
    reminder = c.read(reminderControllerProvider);
  });
  tearDown(() => db.close());

  test('switching on asks, then saves and arms at 21:00 with the text and '
      'the add route', () async {
    expect(await reminder.enable(en), isTrue);

    expect(outside.permissionRequests, 1);
    expect((await prefs.load()).reminderEnabled, isTrue);
    expect(outside.reminders.single, (
      enabled: true,
      minuteOfDay: 1260,
      text: 'Anything to log today?',
      route: '/add',
    ));
  });

  test('a denied permission leaves it off and arms nothing', () async {
    outside
      ..grant = false
      ..enabled = false;
    expect(await reminder.enable(en), isFalse);

    expect((await prefs.load()).reminderEnabled, isFalse);
    expect(outside.reminders.where((r) => r.enabled), isEmpty);
  });

  test('a new time is saved, and re-armed only while the reminder is on',
      () async {
    await reminder.setTime(en, 450);
    expect((await prefs.load()).reminderMinuteOfDay, 450);
    expect(outside.reminders, isEmpty, reason: 'off: nothing to arm');

    await reminder.enable(en);
    await reminder.setTime(en, 480);
    expect(outside.reminders.last.minuteOfDay, 480);
    expect(outside.reminders.last.enabled, isTrue);
  });

  test('switching off saves it and cancels the alarm', () async {
    await reminder.enable(en);
    await reminder.disable(en);

    expect((await prefs.load()).reminderEnabled, isFalse);
    expect(outside.reminders.last.enabled, isFalse);
  });

  test('push hands native the stored config, worded in the given language',
      () async {
    await prefs.setReminder(enabled: true, minuteOfDay: 1200);
    await reminder.push(lookupAppLocalizations(const Locale('fa')));

    expect(outside.reminders.single.minuteOfDay, 1200);
    expect(outside.reminders.single.text, 'امروز چیزی برای ثبت دارید؟');
  });
}
