import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../l10n/app_localizations.dart';

import 'app_shell.dart';
import 'first_run.dart';

import '../features/analytics/routes.dart';
import '../features/categories/routes.dart';
import '../features/onboarding/routes.dart';
import '../features/payment_methods/routes.dart';
import '../features/settings/routes.dart';
import '../features/tags/routes.dart';
import '../features/transactions/routes.dart';

/// Composes the per-feature route lists into the app's router.
///
/// There is deliberately no central switch statement: each feature owns a
/// `routes.dart` exporting its own `List<RouteBase>`, and adding a feature adds
/// exactly one line here. Two phases adding different features therefore append
/// different lines and merge cleanly, which is the whole point of the rule in
/// CONVENTIONS.md section 3.
///
/// Keyed by initial location so tests and the Phase 6 home-screen widget can
/// start the app somewhere other than the root without a second router.
final appRouterProvider =
    Provider.family<GoRouter, String?>((ref, initialLocation) {
  final isFirstRunComplete = ref.watch(firstRunCompleteProvider);
  // Latched: categories are only ever soft-deleted, so once first run has
  // happened it stays happened, and every later navigation skips the query.
  var firstRunComplete = false;

  final router = GoRouter(
    initialLocation: initialLocation ?? '/',
    // The first-run gate. Until the category tree exists, every location but
    // onboarding sends the user there -- deep links included -- because
    // anything past it that saves a transaction fails its foreign key.
    // Onboarding itself stays reachable afterwards; only the way in is gated.
    redirect: (context, state) {
      if (firstRunComplete || state.matchedLocation == onboardingRoute) {
        return null;
      }
      return isFirstRunComplete().then(
        (complete) {
          firstRunComplete = complete;
          return complete ? null : onboardingRoute;
        },
        onError: (Object error, StackTrace stack) {
          // go_router turns a redirect exception into its "route not found"
          // screen and keeps only the message, so it is reported here, with
          // its stack, before being passed on.
          FlutterError.reportError(FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'first-run gate',
            context: ErrorDescription('while checking whether first run '
                'has happened'),
          ));
          Error.throwWithStackTrace(error, stack);
        },
      );
    },
    routes: <RouteBase>[
      // The nav-shell destinations. A feature contributes at most one, and
      // whether a screen belongs here or below is the whole distinction: these
      // keep the bottom bar, everything below covers it.
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: <RouteBase>[
          ...transactionShellRoutes,
          ...analyticsShellRoutes,
          ...settingsShellRoutes,
        ],
      ),
      // Full-screen routes, pushed over the shell. Appended one per line as
      // each feature lands:
      ...transactionRoutes,
      ...categoryRoutes,
      ...tagRoutes,
      ...paymentMethodRoutes,
      ...onboardingRoutes,
      ...analyticsRoutes,
    ],
    errorBuilder: (context, state) => const RouteNotFoundScreen(),
  );
  ref.onDispose(router.dispose);
  return router;
});

/// The router's error state.
///
/// Copy arrived with the settings feature's ARB keys (deferred item D5). It
/// renders a title and a way back, because a dead end with no exit is worse
/// than the wrong screen.
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      key: const Key('router-error'),
      body: NimbusEmptyState(
        icon: Icons.explore_off_outlined,
        title: l10n.routeNotFoundTitle,
        message: l10n.routeNotFoundBody,
        actionLabel: l10n.routeNotFoundGoHome,
        onAction: () => context.go(transactionListRoute),
      ),
    );
  }
}
