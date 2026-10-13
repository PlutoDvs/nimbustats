import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../transactions/routes.dart';
import '../data/notification_prefs.dart';
import '../data/outside_channel.dart';
import 'notification_providers.dart';
import 'permission_request.dart';

/// The daily reminder's switch and time (spec §5, §8).
///
/// The database is the source of truth, and native keeps a copy so its
/// receivers can re-arm without Dart. Every change saves first, then pushes
/// that copy. [push] re-sends it at start and after a language switch, so
/// the text is always in the app's language.
final class ReminderController {
  ReminderController(this._ref);

  final Ref _ref;

  NotificationPrefsRepository get _prefs =>
      _ref.read(notificationPrefsRepositoryProvider);

  /// Asks for the permission in context. If granted, it saves the reminder
  /// as on and arms it. If denied, it leaves it off. Returns whether it is
  /// on.
  Future<bool> enable(AppLocalizations l10n) async {
    final granted = await askForNotifications(
        _ref.read(outsideChannelProvider),
        library: 'reminder');
    if (!granted) return false;
    final minute = (await _prefs.load()).reminderMinuteOfDay;
    await _prefs.setReminder(enabled: true, minuteOfDay: minute);
    await _send(l10n, enabled: true, minuteOfDay: minute);
    return true;
  }

  Future<void> disable(AppLocalizations l10n) async {
    final minute = (await _prefs.load()).reminderMinuteOfDay;
    await _prefs.setReminder(enabled: false, minuteOfDay: minute);
    await _send(l10n, enabled: false, minuteOfDay: minute);
  }

  Future<void> setTime(AppLocalizations l10n, int minuteOfDay) async {
    final enabled = (await _prefs.load()).reminderEnabled;
    await _prefs.setReminder(enabled: enabled, minuteOfDay: minuteOfDay);
    if (enabled) await _send(l10n, enabled: true, minuteOfDay: minuteOfDay);
  }

  Future<void> push(AppLocalizations l10n) async {
    final prefs = await _prefs.load();
    await _send(l10n,
        enabled: prefs.reminderEnabled,
        minuteOfDay: prefs.reminderMinuteOfDay);
  }

  Future<void> _send(
    AppLocalizations l10n, {
    required bool enabled,
    required int minuteOfDay,
  }) =>
      _ref.read(outsideChannelProvider).setReminder(
            enabled: enabled,
            minuteOfDay: minuteOfDay,
            text: l10n.notificationsReminderText,
            route: addTransactionRoute,
          );
}

final reminderControllerProvider =
    Provider<ReminderController>(ReminderController.new);
