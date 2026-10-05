import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_providers.dart';

/// One titled chart on the Insights tab, with its own four states.
///
/// Its own, so one slow or failed query does not blank the charts beside it.
/// The states are keyed `tracker-<sectionKey>-loading|error|empty`.
class TrackerChartSection extends ConsumerWidget {
  const TrackerChartSection({
    super.key,
    required this.sectionKey,
    required this.title,
    required this.spec,
    required this.builder,
  });

  final String sectionKey;
  final String title;
  final TrackerQuerySpec spec;

  /// Draws the populated state. Called only with a result that has buckets.
  final Widget Function(BuildContext context, TrackerResult result) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = ref.watch(trackerResultProvider(spec));

    final Widget body;
    if (result.hasError) {
      body = KeyedSubtree(
        key: Key('tracker-$sectionKey-error'),
        child: NimbusErrorState(
          title: l10n.trackerInsightsErrorTitle,
          retryLabel: l10n.commonRetry,
          detail: result.error.toString(),
          onRetry: () => ref.invalidate(trackerResultProvider(spec)),
        ),
      );
    } else if (!result.hasValue) {
      // A skeleton the chart's height, never a spinner: the space the chart
      // will take is held, so nothing jumps when it arrives.
      body = Container(
        key: Key('tracker-$sectionKey-loading'),
        height: 180,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: NimbusTokens.borderRadiusMd,
        ),
      );
    } else if (result.requireValue.buckets.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: NimbusTokens.space6),
        child: Text(
          l10n.trackerInsightsNothingLogged,
          key: Key('tracker-$sectionKey-empty'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    } else {
      body = builder(context, result.requireValue);
    }

    return Padding(
      padding: const EdgeInsets.only(top: NimbusTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: NimbusTokens.space2),
          body,
        ],
      ),
    );
  }
}
