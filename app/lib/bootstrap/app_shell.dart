import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/analytics/routes.dart';
import '../features/settings/routes.dart';
import '../features/transactions/routes.dart';
import '../l10n/app_localizations.dart';

/// The persistent bottom navigation around the app's top-level destinations.
///
/// Only these three live inside the shell. Full-screen tasks -- adding an
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

    return Scaffold(
      body: child,
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
    );
  }
}
