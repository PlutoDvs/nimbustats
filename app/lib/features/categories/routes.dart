import 'package:go_router/go_router.dart';

import 'presentation/category_manager_screen.dart';

const categoryManagerRoute = '/categories';

/// This feature's routes, composed into the app router by `app_router.dart`.
///
/// Owned here rather than declared centrally so that two phases adding two
/// features append two different lines and merge cleanly.
final categoryRoutes = <RouteBase>[
  GoRoute(
    path: categoryManagerRoute,
    name: 'categories',
    builder: (context, state) => const CategoryManagerScreen(),
  ),
];
