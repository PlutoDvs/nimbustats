import 'package:go_router/go_router.dart';

import 'presentation/goal_detail_screen.dart';
import 'presentation/goal_editor_screen.dart';
import 'presentation/goals_screen.dart';

const goalsRoute = '/goals';

/// Declared before the detail's `:id` route, which would otherwise match it.
const newGoalRoute = '/goals/new';

/// Where a card opens: [id]'s detail screen, pushed over the shell.
String goalDetailRoute(String id) => '$goalsRoute/$id';

String editGoalRoute(String id) => '$goalsRoute/$id/edit';

/// A nav-shell destination, so it keeps the bottom bar.
final goalShellRoutes = <RouteBase>[
  GoRoute(
    path: goalsRoute,
    name: 'goals',
    builder: (context, state) => const GoalsScreen(),
  ),
];

/// This feature's full-screen routes, composed by `app_router.dart`. The
/// editor and the detail screen own the whole screen. A nav bar under a
/// half-written goal would be an exit that silently discards it.
final goalRoutes = <RouteBase>[
  GoRoute(
    path: newGoalRoute,
    name: 'goal-new',
    builder: (context, state) => const GoalEditorScreen(),
  ),
  GoRoute(
    path: '$goalsRoute/:id/edit',
    name: 'goal-edit',
    builder: (context, state) =>
        GoalEditorScreen(id: state.pathParameters['id']!),
  ),
  GoRoute(
    path: '$goalsRoute/:id',
    name: 'goal',
    builder: (context, state) =>
        GoalDetailScreen(id: state.pathParameters['id']!),
  ),
];
