import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../settings/application/settings_providers.dart';
import '../../application/analytics_providers.dart';
import '../../application/dashboard_anchor.dart';

/// One pinned view on the dashboard.
///
/// Each card resolves, loads and fails on its own. The dashboard is a list
/// of independent questions; one slow or broken answer must not hold up or
/// blank the others (screen contract §5.1).
class SavedViewCard extends StatelessWidget {
  const SavedViewCard({super.key, required this.entry, required this.anchor});

  final SavedViewEntry entry;
  final DateKey anchor;

  @override
  Widget build(BuildContext context) => Card(
        key: Key('saved-view-card-${entry.id}'),
        child: Padding(
          padding: const EdgeInsets.all(NimbusTokens.space4),
          child: switch (entry) {
            final SavedView view => _Readable(view: view, anchor: anchor),
            final UnreadableSavedView view => _Unreadable(view: view),
          },
        ),
      );
}

class _Readable extends ConsumerWidget {
  const _Readable({required this.view, required this.anchor});

  final SavedView view;
  final DateKey anchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final calendar = ref.watch(calendarProvider);
    final formatter = ref.watch(moneyFormatterProvider);
    final spec = resolvedSpec(view, anchor, calendar,
        firstDayOfWeek: ref.watch(firstDayOfWeekProvider));
    final result = ref.watch(analyticsResultProvider(spec));

    // hasError/hasValue rather than a switch over the AsyncValue subtypes:
    // while an answer re-runs after a write it is a loading value that still
    // holds the old answer, and the card should keep showing it.
    final data = result.hasError ? null : result.value;
    final total = data == null || data.trueCount == 0
        ? null
        : formatter.format(data.trueTotal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One node for a screen reader: name, period, total.
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      view.name,
                      key: Key('card-name-${view.id}'),
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: NimbusTokens.space2),
                  Text(
                    // resolvedSpec always sets the range.
                    viewPeriodLabel(spec.filters.dateRange!, calendar,
                        persianDigits: formatter.persianDigits),
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
              if (total != null)
                // Full format -- the total is the card's headline -- scaled
                // down rather than cut when a nine-digit amount meets a narrow
                // phone (degenerate case D1).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    total,
                    key: Key('card-total-${view.id}'),
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: NimbusTokens.space2),
        if (result.hasError)
          _CardError(
            id: view.id,
            error: result.error!,
            onRetry: () => ref.invalidate(analyticsResultProvider(spec)),
          )
        else if (data == null)
          const _CardSkeleton()
        else if (data.trueCount == 0)
          Text(
            l10n.dashboardCardEmpty,
            key: Key('card-empty-${view.id}'),
            style: theme.textTheme.bodyMedium,
          ),
      ],
    );
  }
}

class _CardError extends StatelessWidget {
  const _CardError({
    required this.id,
    required this.error,
    required this.onRetry,
  });

  final String id;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.dashboardCardError, key: Key('card-error-$id')),
              // What failed, not just that something did.
              Text('$error',
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
      ],
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('card-loading'),
        height: NimbusTokens.minTapTarget,
        decoration: BoxDecoration(
          color: NimbusSemanticColors.of(context).skeleton,
          borderRadius: NimbusTokens.borderRadiusSm,
        ),
      );
}

class _Unreadable extends StatelessWidget {
  const _Unreadable({required this.view});

  final UnreadableSavedView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          view.name,
          key: Key('card-name-${view.id}'),
          style: theme.textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: NimbusTokens.space2),
        Text(l10n.savedViewUnreadable, key: Key('card-unreadable-${view.id}')),
        Text('${view.error}',
            style: theme.textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
