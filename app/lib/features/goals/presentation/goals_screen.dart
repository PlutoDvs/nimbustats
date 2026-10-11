import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../application/goal_providers.dart';
import '../routes.dart';
import 'widgets/goal_card.dart';

/// The Goals tab: every goal and where it stands this period (screen
/// contract §7.1). Paused goals sit apart, under their own header.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final goals = ref.watch(goalsProvider);

    // hasError and hasValue rather than a switch on the subtype: a refresh
    // carries the previous list, and blanking to a skeleton between two
    // emissions reads as a flicker.
    final Widget body;
    if (goals.hasError) {
      body = NimbusErrorState(
        key: const Key('goals-error'),
        title: l10n.goalsErrorTitle,
        retryLabel: l10n.commonRetry,
        detail: goals.error.toString(),
        onRetry: () => ref.invalidate(goalsProvider),
      );
    } else if (!goals.hasValue) {
      body = const NimbusLoadingList(key: Key('goals-loading'), rows: 4);
    } else if (goals.requireValue.isEmpty) {
      body = NimbusEmptyState(
        key: const Key('goals-empty'),
        icon: Icons.flag_outlined,
        title: l10n.goalsEmptyTitle,
        message: l10n.goalsEmptyBody,
        actionLabel: l10n.goalsNew,
        onAction: () => context.push(newGoalRoute),
      );
    } else {
      bool paused(GoalRead read) => read is GoalReadable && !read.goal.active;
      final all = goals.requireValue;
      final resting = [for (final read in all) if (paused(read)) read];
      body = ListView(
        key: const Key('goals-list'),
        padding: const EdgeInsets.all(NimbusTokens.space4),
        children: [
          for (final read in all)
            if (!paused(read)) GoalCard(key: ValueKey(read.id), read: read),
          if (resting.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: NimbusTokens.space2),
              child: Text(
                l10n.goalsPausedSection,
                key: const Key('goals-paused-header'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final read in resting)
              GoalCard(key: ValueKey(read.id), read: read),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.goalsScreenTitle),
        actions: [
          IconButton(
            key: const Key('goals-new'),
            tooltip: l10n.goalsNew,
            icon: const Icon(Icons.add),
            onPressed: () => context.push(newGoalRoute),
          ),
        ],
      ),
      body: body,
    );
  }
}
