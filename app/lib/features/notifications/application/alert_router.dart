import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../goals/application/goal_format.dart';
import '../../goals/application/goal_providers.dart';
import '../../goals/application/goal_watcher.dart';
import '../../goals/routes.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/data/app_settings.dart';
import '../../settings/data/settings_repository.dart';
import '../../trackers/application/tracker_format.dart';
import '../data/outside_channel.dart';
import 'notification_providers.dart';
import 'outside_errors.dart';

/// Decides *where* each goal alert is shown, never *whether* (spec §4.3).
/// Phase 5 decided that.
///
/// It is the only subscriber to the watcher's alerts. That gives one
/// decision point, so no alert is shown twice or missed at a lifecycle
/// boundary:
/// - In the foreground, the alert goes to [foregroundAlerts], which the
///   shell's `GoalAlertListener` shows as Phase 5's snackbar.
/// - Otherwise, including the headless drain engine, it is posted as a
///   notification. The tag is `goal:<id>`, so a 100% replaces that goal's
///   80%. The text is discreet unless the user turned details on. The lock
///   screen always gets the discreet text, and a tap opens the goal.
///
/// A failed post is reported, not retried. Phase 5 has already recorded the
/// crossing, by design (spec §9).
final class AlertRouter {
  AlertRouter(this._ref) {
    _subscription = _ref.read(goalWatcherProvider).alerts.listen(_route);
  }

  final Ref _ref;
  late final StreamSubscription<GoalAlert> _subscription;
  final _foreground = StreamController<GoalAlert>.broadcast();
  final _posting = <Future<void>>{};

  Stream<GoalAlert> get foregroundAlerts => _foreground.stream;

  /// Completes once every notification already being posted has been. The
  /// headless drain waits on this before its engine is destroyed.
  Future<void> idle() => Future.wait(List.of(_posting));

  void _route(GoalAlert alert) {
    if (_ref.read(isForegroundProvider)()) {
      _foreground.add(alert);
      return;
    }
    final post = reportingFailure('alert router',
        'while posting the alert for goal ${alert.goalId}', () => _post(alert));
    _posting.add(post);
    unawaited(post.whenComplete(() => _posting.remove(post)));
  }

  /// Reads the settings once, here, rather than through the settings stream.
  /// The headless engine posts before that stream has emitted, and would
  /// otherwise word the alert in the default language.
  Future<void> _post(GoalAlert alert) async {
    // As SnapshotWriter does: one corrupt setting reads as the defaults, and
    // the settings screen surfaces it with its reset (settings_providers.dart),
    // so it costs no alert and is not reported twice.
    final settings = await _ref
        .read(settingsRepositoryProvider)
        .load()
        .onError<SettingsFormatException>((_, __) => AppSettings.defaults);
    final prefs = await _ref.read(notificationPrefsRepositoryProvider).load();
    final l10n = lookupAppLocalizations(settings.locale);
    final discreet = l10n.notificationsAlertDiscreet;
    final text = prefs.showDetails
        ? GoalFormat(
            money: settings.moneyFormatter,
            trackers: TrackerFormat(
              localeTag: settings.locale.languageCode,
              persianDigits: settings.persianDigits,
              calendar: settings.calendar,
            ),
          ).alertMessage(l10n, alert, await _periodOf(alert.goalId))
        : discreet;
    await _ref.read(outsideChannelProvider).postAlert(
          tag: 'goal:${alert.goalId}',
          text: text,
          publicText: discreet,
          route: goalDetailRoute(alert.goalId),
        );
  }

  /// The goal's period type, for the wording, as `GoalAlertListener` finds
  /// it. A goal deleted since reads plainly, through the message's `other`
  /// case.
  Future<String> _periodOf(String goalId) async {
    for (final read in await _ref.read(goalServiceProvider).goals()) {
      if (read case GoalReadable(:final goal) when goal.id == goalId) {
        return goal.period.storedName;
      }
    }
    return 'other';
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _foreground.close();
  }
}

/// Created once per engine, before the watcher starts or checks, so no alert
/// is emitted with no one routing it.
final alertRouterProvider = Provider<AlertRouter>((ref) {
  final router = AlertRouter(ref);
  ref.onDispose(() => unawaited(router.dispose()));
  return router;
});
