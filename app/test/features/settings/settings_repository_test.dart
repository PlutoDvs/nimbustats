import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_keys.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase.openInMemory();
    repo = SettingsRepository(db.settingsDao);
  });

  tearDown(() => db.close());

  test('an empty database yields the documented defaults', () async {
    final settings = await repo.load();
    // First run is a normal state, not an error: absent keys take defaults.
    expect(settings, AppSettings.defaults);
    expect(settings.currency, Currency.toman);
    expect(settings.calendarKind, CalendarKind.jalali);
    expect(settings.locale, const Locale('fa'));
    expect(settings.firstDayOfWeek, DateTime.saturday);
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.onboardingCompleted, isFalse);
  });

  test('every field round-trips through the database', () async {
    const written = AppSettings(
      currency: Currency.usd,
      calendarKind: CalendarKind.gregorian,
      locale: Locale('en'),
      firstDayOfWeek: DateTime.monday,
      themeMode: ThemeMode.dark,
      onboardingCompleted: true,
    );
    await repo.save(written);
    expect(await repo.load(), written);
  });

  test('a stored value that cannot be parsed throws rather than defaulting',
      () async {
    // Absent means "first run". Present-but-invalid means the database is
    // wrong, and silently substituting a default there would hide corruption
    // behind an app that merely renders the wrong calendar.
    await db.settingsDao.put(SettingsKeys.calendarKind, 'martian');
    await expectLater(
      repo.load(),
      throwsA(isA<SettingsFormatException>()
          .having((e) => e.key, 'key', SettingsKeys.calendarKind)
          .having((e) => e.value, 'value', 'martian')),
    );
  });

  test('an unknown currency code throws and names the key', () async {
    await db.settingsDao.put(SettingsKeys.currencyCode, 'XYZ');
    await expectLater(
      repo.load(),
      throwsA(isA<SettingsFormatException>()
          .having((e) => e.key, 'key', SettingsKeys.currencyCode)),
    );
  });

  test('a locale with no ARB bundle throws instead of falling back', () async {
    // Falling back to English here would look like a working app to everyone
    // except the user whose language silently vanished.
    await db.settingsDao.put(SettingsKeys.localeCode, 'de');
    await expectLater(
      repo.load(),
      throwsA(isA<SettingsFormatException>()
          .having((e) => e.key, 'key', SettingsKeys.localeCode)),
    );
  });

  test('a first day of week outside ISO 1-7 throws', () async {
    await db.settingsDao.put(SettingsKeys.firstDayOfWeek, '9');
    await expectLater(repo.load(), throwsA(isA<SettingsFormatException>()));
  });

  test('a non-numeric first day of week throws', () async {
    await db.settingsDao.put(SettingsKeys.firstDayOfWeek, 'monday');
    await expectLater(repo.load(), throwsA(isA<SettingsFormatException>()));
  });

  test('a non-boolean flag throws', () async {
    await db.settingsDao.put(SettingsKeys.onboardingCompleted, 'yes');
    await expectLater(repo.load(), throwsA(isA<SettingsFormatException>()));
  });

  test('resetToDefaults recovers from a corrupt value', () async {
    await db.settingsDao.put(SettingsKeys.themeMode, 'chartreuse');
    await expectLater(repo.load(), throwsA(isA<SettingsFormatException>()));
    await repo.resetToDefaults();
    expect(await repo.load(), AppSettings.defaults);
  });

  test('the exception explains how to recover', () async {
    await db.settingsDao.put(SettingsKeys.themeMode, 'chartreuse');
    try {
      await repo.load();
      fail('expected a SettingsFormatException');
    } on SettingsFormatException catch (e) {
      // An operator reading this in a crash report should not have to guess.
      expect(e.toString(), contains(SettingsKeys.themeMode));
      expect(e.toString(), contains('chartreuse'));
      expect(e.toString().toLowerCase(), contains('reset'));
    }
  });

  test('watch emits the current settings and then every change', () async {
    final seen = <AppSettings>[];
    final sub = repo.watch().listen(seen.add);
    addTearDown(sub.cancel);

    await pumpEventQueue();
    await repo.save(AppSettings.defaults.copyWith(themeMode: ThemeMode.light));
    await pumpEventQueue();

    expect(seen.first, AppSettings.defaults);
    expect(seen.last.themeMode, ThemeMode.light);
  });

  group('derived values', () {
    test('the Jalali setting produces a Jalali calendar', () {
      expect(AppSettings.defaults.calendar, isA<JalaliCalendar>());
      expect(
        AppSettings.defaults
            .copyWith(calendarKind: CalendarKind.gregorian)
            .calendar,
        isA<GregorianCalendar>(),
      );
    });

    test('Persian digits follow the locale, not the calendar', () {
      // Screen contract 8: a user may read `en` and keep the Jalali calendar,
      // and both combinations must render correctly.
      const enJalali = AppSettings(
        currency: Currency.toman,
        calendarKind: CalendarKind.jalali,
        locale: Locale('en'),
        firstDayOfWeek: DateTime.saturday,
        themeMode: ThemeMode.system,
        onboardingCompleted: true,
      );
      expect(enJalali.persianDigits, isFalse);
      expect(enJalali.calendar, isA<JalaliCalendar>());
      expect(AppSettings.defaults.persianDigits, isTrue);
    });

    test('the money formatter matches currency and digit style', () {
      final formatter = AppSettings.defaults.moneyFormatter;
      expect(formatter.currency, Currency.toman);
      expect(formatter.format(const Money(1234567)), '۱٬۲۳۴٬۵۶۷');
    });

    test('a Latin-locale formatter groups with commas', () {
      final formatter = AppSettings.defaults
          .copyWith(locale: const Locale('en'))
          .moneyFormatter;
      expect(formatter.format(const Money(1234567)), '1,234,567');
    });
  });

  group('value semantics', () {
    test('equal field sets compare equal', () {
      expect(AppSettings.defaults, AppSettings.defaults.copyWith());
      expect(AppSettings.defaults.hashCode,
          AppSettings.defaults.copyWith().hashCode);
    });

    test('a single differing field breaks equality', () {
      // The round-trip test compares whole values, so this has to be true for
      // that test to mean anything.
      expect(AppSettings.defaults,
          isNot(AppSettings.defaults.copyWith(themeMode: ThemeMode.dark)));
      expect(AppSettings.defaults,
          isNot(AppSettings.defaults.copyWith(onboardingCompleted: true)));
    });
  });
}
