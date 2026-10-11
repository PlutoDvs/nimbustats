import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/goal_providers.dart';
import 'goal_preview.dart';

/// A goal's closed periods, newest first: met, exceeded or missed, each named
/// in the goal's own calendar (spec §5.2).
///
/// A sliver, built lazily, so years of a daily goal's history cost what is
/// on screen (screen contract §1.5). The cache serves the periods.
class GoalHistoryList extends ConsumerWidget {
  const GoalHistoryList({super.key, required this.goal, this.tracker});

  final Goal goal;
  final Tracker? tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(goalHistoryProvider(goal));
    if (history.hasError) {
      return SliverToBoxAdapter(
        child: Row(
          key: const Key('goal-history-error'),
          children: [
            Expanded(child: Text(l10n.goalsHistoryErrorTitle)),
            TextButton(
              onPressed: () => ref.invalidate(goalHistoryProvider(goal)),
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      );
    }
    if (!history.hasValue) {
      return SliverToBoxAdapter(
        child: Container(
          key: const Key('goal-history-loading'),
          height: NimbusTokens.minTapTarget,
          decoration: BoxDecoration(
            color: NimbusSemanticColors.of(context).skeleton,
            borderRadius: NimbusTokens.borderRadiusSm,
          ),
        ),
      );
    }
    final outcomes = history.requireValue.outcomes;
    if (outcomes.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NimbusTokens.space2),
          child: Text(l10n.goalsHistoryEmpty,
              key: const Key('goal-history-empty')),
        ),
      );
    }
    return SliverList.builder(
      itemCount: outcomes.length,
      itemBuilder: (context, index) {
        // Oldest first from the service; newest first on screen.
        final outcome = outcomes[outcomes.length - 1 - index];
        return GoalOutcomeRow(
          key: Key('goal-history-${outcome.period.startInclusive.value}'),
          goal: goal,
          outcome: outcome,
          tracker: tracker,
        );
      },
    );
  }
}
