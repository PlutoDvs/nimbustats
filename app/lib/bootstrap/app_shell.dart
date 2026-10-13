import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/analytics/routes.dart';
import '../features/goals/presentation/goal_alert_listener.dart';
import '../features/goals/routes.dart';
import '../features/notifications/presentation/notifications_bridge.dart';
import '../features/settings/routes.dart';
import '../features/trackers/routes.dart';
import '../features/transactions/routes.dart';
import '../features/widget/presentation/widget_sync.dart';
import '../l10n/app_localizations.dart';

/// The persistent bottom navigation around the app's top-level destinations.
///
/// Only these five live inside the shell. Full-screen tasks -- adding an
/// expense, editing a category -- are pushed over it, because a nav bar under
/// a half-finished draft offers an exit that silently discards it.
///
/// Settings sits here for a reason beyond symmetry: it was registered and
/// tested from Phase 1 with nothing in the running app navigating to it, so
/// settings and the category and tag managers behind it were unreachable.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  /// Index order is the bar's order. Home stays first: Phase 1's "any expense
  /// in five seconds" is measured from a cold start landing there.
  static const destinations = <String>[
    transactionListRoute,
    trackersRoute,
    goalsRoute,
    analyticsRoute,
    settingsRoute,
  ];

  /// `/` is a prefix of every other route, so it can only be matched by
  /// falling through -- checking it first would select Home everywhere.
  static int indexOf(String location) {
    for (var i = destinations.length - 1; i >= 1; i--) {
      if (location.startsWith(destinations[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final index = indexOf(GoRouterState.of(context).uri.path);

    // Goal alerts show over whichever screen is up, queued behind any
    // snackbar already showing. Mounted here because the shell is mounted
    // for as long as the app runs (spec §4.2).
    // Phase 6: Android's notification channels follow the app's language,
    // and a notification tap opens its route (ruling R6).
    // The home-screen widget's snapshot follows the data (Phase 6).
    return NotificationsBridge(
      child: WidgetSync(
        child: GoalAlertListener(
          child: Scaffold(
            body: child,
            // Home's add button lives on this Scaffold, not on the list's. Snackbars
            // show on the outermost Scaffold, and a Scaffold only lifts its *own*
            // FAB clear of its snackbar -- on the list's Scaffold the button sat
            // under "saved" for four seconds after every capture, so a second
            // expense meant waiting or missing the tap.
            floatingActionButton: index == 0
                ? FloatingActionButton(
                    key: const Key('tx-add-fab'),
                    // Its only name: a bare icon reaches a screen reader as
                    // "Button". The same string titles the screen it opens.
                    tooltip: l10n.addExpense,
                    onPressed: () => context.push(addTransactionRoute),
                    child: const Icon(Icons.add),
                  )
                : null,
            bottomNavigationBar: NavigationBar(
              key: const Key('nav-bar'),
              selectedIndex: index,
              // `go`, not `push`: destinations replace one another rather than
              // stacking, so the back button leaves the app instead of walking a
              // history of tab taps.
              onDestinationSelected: (i) => context.go(destinations[i]),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.receipt_long_outlined),
                  selectedIcon: const Icon(Icons.receipt_long),
                  label: l10n.navHome,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.checklist_outlined),
                  selectedIcon: const Icon(Icons.checklist),
                  label: l10n.navTrackers,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.flag_outlined),
                  selectedIcon: const Icon(Icons.flag),
                  label: l10n.navGoals,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.insights_outlined),
                  selectedIcon: const Icon(Icons.insights),
                  label: l10n.navAnalytics,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: l10n.navSettings,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
