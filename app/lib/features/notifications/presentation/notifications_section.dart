import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/application/settings_providers.dart';
import '../application/notification_providers.dart';
import '../application/outside_errors.dart';
import '../application/reminder_controller.dart';
import '../data/notification_prefs.dart';
import '../data/outside_channel.dart';

/// The settings screen's "Notifications" section (spec §8): the daily
/// reminder and its time, the detail switch, and a row that says when
/// Android is blocking notifications.
///
/// States: loading (the keys not read yet), error (the read failed),
/// populated. There is no empty state.
class NotificationsSection extends ConsumerStatefulWidget {
  const NotificationsSection({super.key});

  @override
  ConsumerState<NotificationsSection> createState() =>
      _NotificationsSectionState();
}

class _NotificationsSectionState extends ConsumerState<NotificationsSection> {
  late final OutsideChannel _channel;
  late final AppLifecycleListener _lifecycle;

  /// Whether Android lets the app post; null until first asked.
  bool? _enabled;

  /// A denial just now: the row shows even though the reminder stayed off.
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _channel = ref.read(outsideChannelProvider);
    // Re-checked on resume: the user may have just come back from Android's
    // notification settings.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_recheck()));
    unawaited(_recheck());
  }

  Future<void> _recheck() async {
    final enabled = await reportingFailure('reminder',
        'while checking whether notifications are enabled',
        _channel.notificationsEnabled);
    if (!mounted || enabled == null) return;
    setState(() {
      _enabled = enabled;
      if (enabled) _denied = false;
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Runs one change. A failure is reported under `reminder` and the user is
  /// told, as the rest of the settings screen does. Returns null on failure.
  Future<T?> _change<T>(String what, Future<T> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).settingsSaveFailed;
    try {
      return await action();
    } on Object catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'reminder',
        context: ErrorDescription(what),
      ));
      messenger.showSnackBar(SnackBar(content: Text(failed)));
      return null;
    }
  }

  Future<void> _toggleReminder(bool on) async {
    final l10n = AppLocalizations.of(context);
    final reminder = ref.read(reminderControllerProvider);
    if (!on) {
      await _change('while switching the reminder off',
          () => reminder.disable(l10n));
      if (mounted) setState(() => _denied = false);
      return;
    }
    final enabled = await _change(
        'while switching the reminder on', () => reminder.enable(l10n));
    if (!mounted) return;
    setState(() => _denied = enabled == false);
    await _recheck();
  }

  Future<void> _pickTime(int minuteOfDay) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    await _change(
      'while setting the reminder time',
      () => ref
          .read(reminderControllerProvider)
          .setTime(l10n, picked.hour * 60 + picked.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final prefs = ref.watch(notificationPrefsProvider);

    final Widget body;
    if (prefs.hasError) {
      body = NimbusErrorState(
        key: const Key('notifications-error'),
        title: l10n.notificationsLoadFailed,
        retryLabel: l10n.commonRetry,
        detail: prefs.error.toString(),
        onRetry: () => ref.invalidate(notificationPrefsProvider),
      );
    } else if (!prefs.hasValue) {
      body = const SizedBox(
        key: Key('notifications-loading'),
        height: 3 * 72,
        child: NimbusLoadingList(rows: 3),
      );
    } else {
      body = _rows(context, l10n, prefs.requireValue);
    }

    return Column(
      key: const Key('notifications-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              NimbusTokens.space4, NimbusTokens.space4, NimbusTokens.space4, 0),
          child: Text(l10n.notificationsSettingsTitle,
              style: theme.textTheme.titleSmall),
        ),
        body,
      ],
    );
  }

  Widget _rows(
      BuildContext context, AppLocalizations l10n, NotificationPrefs prefs) {
    final persian = ref.watch(moneyFormatterProvider).persianDigits;
    final time = _time(prefs.reminderMinuteOfDay, persian: persian);
    final blocked =
        _denied || (prefs.reminderEnabled && _enabled == false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('notifications-reminder'),
          title: Text(l10n.notificationsSettingsReminder),
          value: prefs.reminderEnabled,
          onChanged: (on) => unawaited(_toggleReminder(on)),
        ),
        if (prefs.reminderEnabled)
          ListTile(
            key: const Key('notifications-reminder-time'),
            title: Text(l10n.notificationsSettingsReminderTime),
            trailing: Text(time),
            onTap: () => unawaited(_pickTime(prefs.reminderMinuteOfDay)),
          ),
        SwitchListTile(
          key: const Key('notifications-details'),
          title: Text(l10n.notificationsSettingsDetails),
          subtitle: Text(l10n.notificationsSettingsDetailsHint),
          value: prefs.showDetails,
          onChanged: (on) => unawaited(_change(
              'while saving the detail setting',
              () => ref
                  .read(notificationPrefsRepositoryProvider)
                  .setShowDetails(on))),
        ),
        if (blocked)
          ListTile(
            key: const Key('notifications-blocked'),
            leading: const Icon(Icons.notifications_off_outlined),
            title: Text(l10n.notificationsBlocked),
            trailing: TextButton(
              key: const Key('notifications-open-settings'),
              onPressed: () => unawaited(reportingFailure('reminder',
                  'while opening notification settings',
                  _channel.openNotificationSettings)),
              child: Text(l10n.notificationsOpenSettings),
            ),
          ),
      ],
    );
  }

  /// 24-hour, in the settings' digits (spec §8).
  static String _time(int minuteOfDay, {required bool persian}) {
    String two(int v) => v.toString().padLeft(2, '0');
    final latin = '${two(minuteOfDay ~/ 60)}:${two(minuteOfDay % 60)}';
    return persian ? Digits.toPersian(latin) : latin;
  }
}
