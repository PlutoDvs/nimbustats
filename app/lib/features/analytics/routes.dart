import 'package:go_router/go_router.dart';

import 'presentation/analytics_screen.dart';

const analyticsRoute = '/analytics';

/// A nav-shell destination rather than a pushed screen, so it keeps the bottom
/// bar and the user can leave it the way they arrived.
final analyticsShellRoutes = <RouteBase>[
  GoRoute(
    path: analyticsRoute,
    name: 'analytics',
    builder: (context, state) => const AnalyticsScreen(),
  ),
];
