import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import 'l10n/app_localizations.dart';

void main() => runApp(const NimbuStatsApp());

/// Phase 0 shell. The home screen is deliberately a placeholder -- the real
/// screens arrive in Phase 1, against the contract in
/// docs/superpowers/screen-contract.md.
class NimbuStatsApp extends StatelessWidget {
  const NimbuStatsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: NimbusTheme.light(),
        darkTheme: NimbusTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Persian by default so right-to-left is the path exercised every day,
        // rather than a mode that breaks the first time someone switches to it.
        locale: const Locale('fa'),
        home: const Scaffold(body: Center(child: Text('NimbuStats'))),
      );
}
