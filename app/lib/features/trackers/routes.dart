import 'package:go_router/go_router.dart';

import 'presentation/tracker_manager_screen.dart';
import 'presentation/trackers_screen.dart';

const trackersRoute = '/trackers';

/// Pushed over the shell: managing trackers owns the whole screen.
const trackerManagerRoute = '/trackers/manage';

/// A nav-shell destination, so it keeps the bottom bar.
final trackerShellRoutes = <RouteBase>[
  GoRoute(
    path: trackersRoute,
    name: 'trackers',
    builder: (context, state) => const TrackersScreen(),
  ),
];

/// This feature's full-screen routes, composed by `app_router.dart`.
final trackerRoutes = <RouteBase>[
  GoRoute(
    path: trackerManagerRoute,
    name: 'tracker-manager',
    builder: (context, state) => const TrackerManagerScreen(),
  ),
];
