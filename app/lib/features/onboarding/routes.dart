import 'package:go_router/go_router.dart';

import 'presentation/onboarding_screen.dart';

const onboardingRoute = '/onboarding';

final onboardingRoutes = <RouteBase>[
  GoRoute(
    path: onboardingRoute,
    name: 'onboarding',
    builder: (context, state) => const OnboardingScreen(),
  ),
];
