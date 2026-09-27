import 'package:go_router/go_router.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import 'presentation/analytics_screen.dart';
import 'presentation/saved_view_screen.dart';

const analyticsRoute = '/analytics';

/// The full-screen saved view's prefix. The `:id` segment is appended where
/// the route is declared.
const savedViewRoute = '/view';

/// Where a card opens: [id]'s view, starting on the dashboard's month.
String savedViewLocation(String id, DateKey anchor) =>
    '$savedViewRoute/$id?anchor=${anchor.value}';

/// A nav-shell destination rather than a pushed screen, so it keeps the bottom
/// bar and the user can leave it the way they arrived.
final analyticsShellRoutes = <RouteBase>[
  GoRoute(
    path: analyticsRoute,
    name: 'analytics',
    builder: (context, state) => const AnalyticsScreen(),
  ),
];

/// Pushed over the shell, like expense detail: a saved view owns the whole
/// screen, with its own month arrows.
final analyticsRoutes = <RouteBase>[
  GoRoute(
    path: '$savedViewRoute/:id',
    name: 'saved-view',
    builder: (context, state) {
      final anchor = state.uri.queryParameters['anchor'];
      return SavedViewScreen(
        id: state.pathParameters['id']!,
        // A malformed anchor throws rather than falling back to today: the
        // link is built by savedViewLocation, so a bad one is a bug to see.
        initialAnchor: anchor == null ? null : DateKey(int.parse(anchor)),
      );
    },
  ),
];
