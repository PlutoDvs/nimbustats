import 'package:go_router/go_router.dart';

import 'presentation/payment_method_manager_screen.dart';

const paymentMethodManagerRoute = '/payment-methods';

/// This feature's routes, composed into the app router by `app_router.dart`.
final paymentMethodRoutes = <RouteBase>[
  GoRoute(
    path: paymentMethodManagerRoute,
    name: 'payment-methods',
    builder: (context, state) => const PaymentMethodManagerScreen(),
  ),
];
