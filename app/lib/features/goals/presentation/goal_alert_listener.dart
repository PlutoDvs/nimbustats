import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../trackers/presentation/widgets/tracker_day_rollover.dart';
import '../application/goal_format.dart';
import '../application/goal_providers.dart';
import '../application/goal_watcher.dart';
import '../routes.dart';

/// Shows each goal alert as a snackbar, until Phase 6 makes them
/// notifications (spec §4.2). It also keeps the goals' today current: the
/// trackers' [TrackerDayRollover] moves `trackerTodayProvider`, which is
/// `goalTodayProvider`, at local midnight and on every resume, and it is
/// mounted here for as long as the shell is.
///
/// It sits on the shell, which is mounted for as long as the app runs, so
/// `trackers/` and `transactions/` stay untouched.
///
/// Snackbars go through the root `ScaffoldMessenger`, which queues them. An
/// alert caused on a pushed screen, such as the add-expense screen or a
/// tracker's detail, waits behind that screen's own "Saved" or Undo. It then
/// shows on whatever screen is up.
class GoalAlertListener extends ConsumerStatefulWidget {
  const GoalAlertListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GoalAlertListener> createState() => _GoalAlertListenerState();
}

class _GoalAlertListenerState extends ConsumerState<GoalAlertListener> {
  late final GoalWatcher _watcher;
  late final StreamSubscription<GoalAlert> _alerts;

  @override
  void initState() {
    super.initState();
    // `read`, never `watch`: a provider whose only listener is a
    // TickerMode-paused widget under a pushed route pauses its subscriptions.
    _watcher = ref.read(goalWatcherProvider);
    _alerts = _watcher.alerts.listen(_show);
    _watcher.start();
  }

  void _show(GoalAlert alert) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final router = GoRouter.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: Key('goal-alert-${alert.goalId}'),
        content: Text(
          ref
              .read(goalFormatProvider)
              .alertMessage(l10n, alert, _periodOf(alert.goalId)),
        ),
        // A snackbar with an action otherwise stays until something replaces
        // it, and the next alert would queue behind it unseen.
        persist: false,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(NimbusTokens.space4),
        action: SnackBarAction(
          label: l10n.goalsAlertView,
          onPressed: () => router.push(goalDetailRoute(alert.goalId)),
        ),
      ),
    );
  }

  /// The goal's period type, for the wording. A goal deleted since its
  /// alert fired reads plainly, through the message's `other` case.
  String _periodOf(String goalId) {
    for (final read in ref.read(goalsProvider).value ?? const <GoalRead>[]) {
      if (read case GoalReadable(:final goal) when goal.id == goalId) {
        return goal.period.storedName;
      }
    }
    return 'other';
  }

  @override
  void dispose() {
    unawaited(_alerts.cancel());
    // The watcher outlives this widget in its provider. Its debounce timer
    // must not (Contract note 1).
    _watcher.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TrackerDayRollover(child: widget.child);
}
