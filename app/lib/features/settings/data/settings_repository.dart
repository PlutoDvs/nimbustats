import 'package:flutter/material.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import 'app_settings.dart';
import 'settings_keys.dart';

/// Raised when a value *present* in the database cannot be parsed.
///
/// Deliberately distinct from an absent key, which is the ordinary first-run
/// state and yields a documented default. Substituting a default for an
/// unparseable stored value would turn database corruption into an app that
/// quietly renders the wrong calendar, and nobody would ever find out why.
final class SettingsFormatException implements Exception {
  const SettingsFormatException(this.key, this.value);

  final String key;
  final String value;

  @override
  String toString() =>
      'SettingsFormatException: setting "$key" holds unparseable value '
      '"$value". Reset settings to defaults to recover.';
}

/// Typed access to the key/value `settings` table.
final class SettingsRepository {
  const SettingsRepository(this._dao);

  final SettingsDao _dao;

  Future<AppSettings> load() async => _parse(await _dao.getAll());

  /// Emits the current settings, then again on every change.
  ///
  /// A stream rather than a one-shot read, because changing the calendar or
  /// the locale has to re-render the app without a restart.
  Stream<AppSettings> watch() => _dao.watchAll().map(_parse);

  Future<void> save(AppSettings settings) async {
    await _dao.put(SettingsKeys.currencyCode, settings.currency.code);
    await _dao.put(SettingsKeys.calendarKind, settings.calendarKind.name);
    await _dao.put(SettingsKeys.localeCode, settings.locale.languageCode);
    await _dao.put(
        SettingsKeys.firstDayOfWeek, settings.firstDayOfWeek.toString());
    await _dao.put(SettingsKeys.themeMode, settings.themeMode.name);
    await _dao.put(SettingsKeys.onboardingCompleted,
        settings.onboardingCompleted.toString());
  }

  /// The recovery path from a corrupt value. An absent key reads back as its
  /// default, so deleting is enough -- there is nothing to rewrite.
  ///
  /// Only the keys `AppSettings` is read from. The install's own record --
  /// the founding-user stamp above all -- is not a setting, and resetting how
  /// the app looks must not erase it.
  Future<void> resetToDefaults() => _dao.deleteKeys(SettingsKeys.appSettings);

  AppSettings _parse(Map<String, String> raw) => AppSettings(
        currency: _read(raw, SettingsKeys.currencyCode,
            AppSettings.defaults.currency, _parseCurrency),
        calendarKind: _read(raw, SettingsKeys.calendarKind,
            AppSettings.defaults.calendarKind, _parseCalendar),
        locale: _read(raw, SettingsKeys.localeCode,
            AppSettings.defaults.locale, _parseLocale),
        firstDayOfWeek: _read(raw, SettingsKeys.firstDayOfWeek,
            AppSettings.defaults.firstDayOfWeek, _parseWeekday),
        themeMode: _read(raw, SettingsKeys.themeMode,
            AppSettings.defaults.themeMode, _parseThemeMode),
        onboardingCompleted: _read(raw, SettingsKeys.onboardingCompleted,
            AppSettings.defaults.onboardingCompleted, _parseBool),
      );

  /// Absent takes [fallback]; present-but-unparseable throws. That distinction
  /// is the whole point of this class.
  T _read<T>(
    Map<String, String> raw,
    String key,
    T fallback,
    T? Function(String) parse,
  ) {
    final value = raw[key];
    if (value == null) return fallback;
    final parsed = parse(value);
    if (parsed == null) throw SettingsFormatException(key, value);
    return parsed;
  }

  static Currency? _parseCurrency(String value) {
    for (final currency in Currency.all) {
      if (currency.code == value) return currency;
    }
    return null;
  }

  static CalendarKind? _parseCalendar(String value) =>
      _byName(CalendarKind.values, value);

  static ThemeMode? _parseThemeMode(String value) =>
      _byName(ThemeMode.values, value);

  static Locale? _parseLocale(String value) =>
      AppSettings.supportedLanguageCodes.contains(value) ? Locale(value) : null;

  static int? _parseWeekday(String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) return null;
    // ISO weekdays only. A number outside 1-7 would silently shift every week
    // boundary in the app.
    return (parsed >= DateTime.monday && parsed <= DateTime.sunday)
        ? parsed
        : null;
  }

  static bool? _parseBool(String value) => switch (value) {
        'true' => true,
        'false' => false,
        // Anything else -- 'yes', '1', '' -- is a value this app never wrote,
        // so it is corruption rather than a synonym to be helpful about.
        _ => null,
      };

  static T? _byName<T extends Enum>(List<T> values, String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
