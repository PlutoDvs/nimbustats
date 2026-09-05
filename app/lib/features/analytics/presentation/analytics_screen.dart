import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';

/// The analytics destination.
///
/// This lands with its `empty` state only. The breakdown chart, its
/// drill-down, and the loading and error states arrive in the next task; the
/// empty state is not a placeholder for them, because a database with no
/// transactions has to render something honest either way.
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      key: const Key('analytics-screen'),
      appBar: AppBar(title: Text(l10n.navAnalytics)),
      body: NimbusEmptyState(
        icon: Icons.insights_outlined,
        title: l10n.analyticsEmptyTitle,
        message: l10n.analyticsEmptyBody,
      ),
    );
  }
}
