import 'package:go_router/go_router.dart';

import 'presentation/settings_screen.dart';

const settingsRoute = '/settings';

final settingsRoutes = <RouteBase>[
  GoRoute(
    path: settingsRoute,
    name: 'settings',
    builder: (context, state) => const SettingsScreen(),
  ),
];
