import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../bootstrap/database_provider.dart';
import '../data/app_settings.dart';
import '../data/settings_repository.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider).settingsDao),
);

/// The single source of truth for how the app renders.
///
/// A stream rather than a one-shot read, so changing the calendar or the
/// locale in settings re-renders the app without a restart.
final settingsProvider = StreamProvider<AppSettings>((ref) {
  // Riverpod 3 auto-disposes by default. Settings are read by every screen for
  // the entire life of the app, so letting this tear down and re-subscribe to
  // a SQLite stream each time the last watcher rebuilds is pure churn -- and
  // it makes a plain `read` race against disposal.
  ref.keepAlive();
  return ref.watch(settingsRepositoryProvider).watch();
});

/// Derived views, so a screen watches the narrowest thing it needs and a theme
/// change does not rebuild a list that only cares about the currency.
///
/// The `?? defaults` in each is **not** a fallback masking an error. While the
/// stream has not yet produced its first value the app still has to render,
/// and these are the same values a first run would write. A real failure -- a
/// [SettingsFormatException] from a corrupt row -- leaves [settingsProvider]
/// in its error state, which the settings screen surfaces with a reset action;
/// these keep the rest of the app usable in the meantime rather than taking
/// every screen down over one bad row.
final currencyProvider = Provider<Currency>((ref) =>
    ref.watch(settingsProvider).value?.currency ??
    AppSettings.defaults.currency);

final calendarProvider = Provider<AppCalendar>((ref) =>
    ref.watch(settingsProvider).value?.calendar ??
    AppSettings.defaults.calendar);

final localeProvider = Provider<Locale>((ref) =>
    ref.watch(settingsProvider).value?.locale ??
    AppSettings.defaults.locale);

final themeModeProvider = Provider<ThemeMode>((ref) =>
    ref.watch(settingsProvider).value?.themeMode ??
    AppSettings.defaults.themeMode);

final firstDayOfWeekProvider = Provider<int>((ref) =>
    ref.watch(settingsProvider).value?.firstDayOfWeek ??
    AppSettings.defaults.firstDayOfWeek);

final moneyFormatterProvider = Provider<MoneyFormatter>((ref) =>
    ref.watch(settingsProvider).value?.moneyFormatter ??
    AppSettings.defaults.moneyFormatter);
