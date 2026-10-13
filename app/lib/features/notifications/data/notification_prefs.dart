import 'package:flutter/foundation.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../settings/data/settings_keys.dart';

/// The reminder and the notification detail level (spec §5, §8).
@immutable
final class NotificationPrefs {
  const NotificationPrefs({
    required this.reminderEnabled,
    required this.reminderMinuteOfDay,
    required this.showDetails,
  });

  /// Off; 21:00; discreet.
  static const defaults = NotificationPrefs(
    reminderEnabled: false,
    reminderMinuteOfDay: 1260,
    showDetails: false,
  );

  final bool reminderEnabled;

  /// Minutes after local midnight, 0..1439.
  final int reminderMinuteOfDay;

  /// Goal names and amounts in alert notifications. The lock screen gets the
  /// discreet text either way.
  final bool showDetails;

  @override
  bool operator ==(Object other) =>
      other is NotificationPrefs &&
      other.reminderEnabled == reminderEnabled &&
      other.reminderMinuteOfDay == reminderMinuteOfDay &&
      other.showDetails == showDetails;

  @override
  int get hashCode =>
      Object.hash(reminderEnabled, reminderMinuteOfDay, showDetails);

  @override
  String toString() => 'NotificationPrefs(reminder: $reminderEnabled at '
      '$reminderMinuteOfDay, details: $showDetails)';
}

/// Typed access to the three notification keys.
///
/// Unlike `SettingsRepository`, a value that does not parse does not fail
/// the read. It is reported, and reads as its default: a broken reminder
/// setting must not take the settings screen down, and saving a new value
/// repairs it (spec §8).
final class NotificationPrefsRepository {
  const NotificationPrefsRepository(this._dao);

  final SettingsDao _dao;

  Future<NotificationPrefs> load() async => parse(await _dao.getAll());

  Stream<NotificationPrefs> watch() => _dao.watchAll().map(parse);

  Future<void> setReminder({
    required bool enabled,
    required int minuteOfDay,
  }) async {
    if (minuteOfDay < 0 || minuteOfDay >= 1440) {
      throw ArgumentError.value(
          minuteOfDay, 'minuteOfDay', 'minutes after midnight, 0..1439');
    }
    await _dao.put(SettingsKeys.reminderEnabled, '$enabled');
    await _dao.put(SettingsKeys.reminderMinuteOfDay, '$minuteOfDay');
  }

  Future<void> setShowDetails(bool value) =>
      _dao.put(SettingsKeys.notificationDetail, '$value');

  static NotificationPrefs parse(Map<String, String> raw) => NotificationPrefs(
        reminderEnabled: _read(raw, SettingsKeys.reminderEnabled,
            NotificationPrefs.defaults.reminderEnabled, _bool),
        reminderMinuteOfDay: _read(raw, SettingsKeys.reminderMinuteOfDay,
            NotificationPrefs.defaults.reminderMinuteOfDay, _minute),
        showDetails: _read(raw, SettingsKeys.notificationDetail,
            NotificationPrefs.defaults.showDetails, _bool),
      );

  static T _read<T>(
    Map<String, String> raw,
    String key,
    T fallback,
    T? Function(String) parse,
  ) {
    final value = raw[key];
    if (value == null) return fallback;
    final parsed = parse(value);
    if (parsed != null) return parsed;
    FlutterError.reportError(FlutterErrorDetails(
      exception: FormatException('setting "$key" does not parse', value),
      library: 'reminder',
      context: ErrorDescription('while reading the notification settings; '
          'it reads as its default until a new value is saved'),
    ));
    return fallback;
  }

  static bool? _bool(String value) => switch (value) {
        'true' => true,
        'false' => false,
        _ => null,
      };

  static int? _minute(String value) {
    final parsed = int.tryParse(value);
    return parsed != null && parsed >= 0 && parsed < 1440 ? parsed : null;
  }
}
