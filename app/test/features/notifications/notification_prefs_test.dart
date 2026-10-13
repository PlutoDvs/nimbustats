import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/notifications/data/notification_prefs.dart';
import 'package:nimbustats/features/settings/data/settings_keys.dart';

void main() {
  late AppDatabase db;
  late NotificationPrefsRepository prefs;
  late List<FlutterErrorDetails> reported;
  FlutterExceptionHandler? previous;

  setUp(() {
    db = AppDatabase.openInMemory();
    prefs = NotificationPrefsRepository(db.settingsDao);
    reported = [];
    previous = FlutterError.onError;
    FlutterError.onError = reported.add;
  });
  tearDown(() async {
    FlutterError.onError = previous;
    await db.close();
  });

  test('absent keys read as off, 21:00, discreet', () async {
    expect(await prefs.load(), NotificationPrefs.defaults);
    expect(NotificationPrefs.defaults.reminderMinuteOfDay, 1260);
    expect(reported, isEmpty);
  });

  test('saved values read back', () async {
    await prefs.setReminder(enabled: true, minuteOfDay: 450);
    await prefs.setShowDetails(true);
    expect(
      await prefs.load(),
      const NotificationPrefs(
          reminderEnabled: true, reminderMinuteOfDay: 450, showDetails: true),
    );
  });

  test('a value that does not parse is reported and reads as its default; '
      'saving repairs it', () async {
    await db.settingsDao.put(SettingsKeys.reminderMinuteOfDay, '25:00');
    await db.settingsDao.put(SettingsKeys.notificationDetail, 'yes');

    final read = await prefs.load();
    expect(read.reminderMinuteOfDay, 1260);
    expect(read.showDetails, isFalse);
    expect(reported.map((e) => e.library), ['reminder', 'reminder']);

    await prefs.setReminder(enabled: false, minuteOfDay: 600);
    expect((await prefs.load()).reminderMinuteOfDay, 600);
  });

  test('a reset leaves these keys alone (spec §8)', () {
    expect(SettingsKeys.appSettings, isNot(contains(SettingsKeys.reminderEnabled)));
    expect(SettingsKeys.appSettings,
        isNot(contains(SettingsKeys.reminderMinuteOfDay)));
    expect(SettingsKeys.appSettings,
        isNot(contains(SettingsKeys.notificationDetail)));
  });

  test('a minute outside the day is refused before it is written', () {
    expect(() => prefs.setReminder(enabled: true, minuteOfDay: 1440),
        throwsArgumentError);
  });
}
