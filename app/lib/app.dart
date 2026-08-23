import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import 'bootstrap/app_router.dart';
import 'features/settings/application/settings_providers.dart';
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

  /// Set by tests only, and only where the test is not about the locale
  /// itself. Left null, the app takes its locale from settings.
  final Locale? overrideLocale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider(initialLocation));
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: NimbusTheme.light(),
      darkTheme: NimbusTheme.dark(),
      // Watched rather than read: changing the theme in settings re-renders
      // the app without a restart, which is the same guarantee the locale and
      // the calendar make.
      themeMode: ref.watch(themeModeProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // From settings, so switching language flips direction live. Persian is
      // the default so right-to-left is the path exercised every day, rather
      // than a mode that breaks the first time someone switches to it.
      locale: overrideLocale ?? ref.watch(localeProvider),
      routerConfig: router,
    );
  }
}
