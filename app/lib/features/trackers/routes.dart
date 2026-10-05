import 'package:go_router/go_router.dart';

import 'presentation/trackers_screen.dart';

const trackersRoute = '/trackers';

/// A nav-shell destination, so it keeps the bottom bar.
final trackerShellRoutes = <RouteBase>[
  GoRoute(
    path: trackersRoute,
    name: 'trackers',
    builder: (context, state) => const TrackersScreen(),
  ),
];
