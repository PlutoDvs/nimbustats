import 'package:flutter/widgets.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';

/// Gregorian and Latin digits, so a backup test can spell out the times it
/// expects.
Future<void> useGregorianEnglish(AppDatabase db) =>
    SettingsRepository(db.settingsDao).save(AppSettings.defaults.copyWith(
        locale: const Locale('en'), calendarKind: CalendarKind.gregorian));
