import 'package:go_router/go_router.dart';

import 'presentation/settings_screen.dart';

const settingsRoute = '/settings';

/// A nav-shell destination. It was a pushed route with no caller for two
/// phases, which is how it stayed unreachable while its tests passed.
final settingsShellRoutes = <RouteBase>[
  GoRoute(
    path: settingsRoute,
    name: 'settings',
    builder: (context, state) => const SettingsScreen(),
  ),
];
