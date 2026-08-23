import 'package:go_router/go_router.dart';

import 'presentation/add_transaction_screen.dart';

const addTransactionRoute = '/add';

/// The detail route's prefix. The `:id` segment is appended where the route is
/// declared; Phase 6's widget deep-links to `$transactionDetailRoute/<id>`.
const transactionDetailRoute = '/tx';

/// This feature's routes, composed into the app router by `app_router.dart`.
final transactionRoutes = <RouteBase>[
  GoRoute(
    path: addTransactionRoute,
    name: 'tx-add',
    builder: (context, state) => AddTransactionScreen(
      // Phase 6's widget deep link. Parsed here so it works the day the widget
      // ships rather than requiring this screen to change then.
      initialAmount: state.uri.queryParameters['amount'],
    ),
  ),
];
