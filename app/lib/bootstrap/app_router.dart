import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/categories/routes.dart';
import '../features/payment_methods/routes.dart';
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
  final router = GoRouter(
    initialLocation: initialLocation ?? '/',
    routes: <RouteBase>[
      // Feature route lists are appended here, one per line, as each lands:
      //   ...settingsRoutes       (Task 15)
      //   ...onboardingRoutes     (Task 15)
      ...transactionRoutes,
      ...categoryRoutes,
      ...tagRoutes,
      ...paymentMethodRoutes,
    ],
    errorBuilder: (context, state) => const RouteNotFoundScreen(),
  );
  ref.onDispose(router.dispose);
  return router;
});

/// The router's error state.
///
/// Localized copy arrives in Task 15, when the settings feature adds the ARB
/// keys; until then this renders an icon and nothing else rather than a
/// hardcoded English string, because "no hardcoded UI text, ever" has no
/// exception for screens users are not supposed to reach.
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const Key('router-error'),
        body: Center(
          child: Icon(
            Icons.explore_off_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
}
