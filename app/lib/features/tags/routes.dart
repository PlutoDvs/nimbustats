import 'package:go_router/go_router.dart';

import 'presentation/tag_manager_screen.dart';

const tagManagerRoute = '/tags';

/// This feature's routes, composed into the app router by `app_router.dart`.
final tagRoutes = <RouteBase>[
  GoRoute(
    path: tagManagerRoute,
    name: 'tags',
    builder: (context, state) => const TagManagerScreen(),
  ),
];
