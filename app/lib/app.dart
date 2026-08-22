import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import 'bootstrap/app_router.dart';
import 'l10n/app_localizations.dart';

class NimbuStatsApp extends ConsumerWidget {
  const NimbuStatsApp({
    super.key,
    this.initialLocation,
    this.overrideLocale,
  });

  /// Set by tests, and by the Phase 6 home-screen widget's deep link. Null
  /// means "start at the router's default".
  final String? initialLocation;

  /// Set by tests only. The running app takes its locale from settings, wired
  /// in Task 15.
  final Locale? overrideLocale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider(initialLocation));
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: NimbusTheme.light(),
      darkTheme: NimbusTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Persian by default so right-to-left is the path exercised every day,
      // rather than a mode that breaks the first time someone switches to it.
      locale: overrideLocale ?? const Locale('fa'),
      routerConfig: router,
    );
  }
}
