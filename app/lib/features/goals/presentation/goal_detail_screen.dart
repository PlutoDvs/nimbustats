import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../trackers/application/tracker_providers.dart';
import '../application/goal_format.dart';
import '../application/goal_kind.dart';
import '../application/goal_providers.dart';
import '../routes.dart';
import 'widgets/goal_card.dart';
import 'widgets/goal_history_list.dart';
import 'widgets/goal_inline_states.dart';
import 'widgets/goal_write.dart';

/// One goal: where this period stands and at what pace, its streak, and
/// its closed periods (spec §5.2). Edit, pause or resume, and delete with an
/// undo.
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final goals = ref.watch(goalsProvider);
    if (goals.hasError) {
      return Scaffold(
        appBar: AppBar(),
        body: NimbusErrorState(
          key: const Key('goal-detail-error'),
          title: l10n.goalsErrorTitle,
          retryLabel: l10n.commonRetry,
          detail: goals.error.toString(),
          onRetry: () => ref.invalidate(goalsProvider),
        ),
      );
    }
    if (!goals.hasValue) {
      return Scaffold(
        appBar: AppBar(),
        body: const NimbusLoadingList(key: Key('goal-detail-loading')),
      );
    }
    final read =
        goals.requireValue.where((read) => read.id == id).firstOrNull;
    if (read == null) {
      // A stale link: Phase 6's notification can hold a deleted goal's id.
      return Scaffold(
        appBar: AppBar(),
        body: NimbusEmptyState(
          key: const Key('goal-detail-gone'),
          icon: Icons.search_off,
          title: l10n.goalsNotFoundTitle,
          message: l10n.goalsNotFoundBody,
          actionLabel: l10n.navGoals,
          onAction: () => context.go(goalsRoute),
        ),
      );
    }
    return switch (read) {
      GoalUnreadable(:final name) => _ProblemScaffold(name: name, read: read),
      GoalReadable(:final goal) => switch (goal.scope) {
          TrackerScope(:final trackerId) =>
            _TrackerGoalDetail(goal: goal, trackerId: trackerId),
          MoneyScope() => _Detail(goal: goal),
        },
    };
  }
}

/// A goal that cannot be shown, with the Goals tab's own card and its Edit
/// and Delete. Either its tracker was deleted or its row does not parse.
class _ProblemScaffold extends StatelessWidget {
  const _ProblemScaffold({required this.name, required this.read});

  final String name;
  final GoalRead read;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: ListView(
          padding: const EdgeInsets.all(NimbusTokens.space4),
          children: [GoalCard(read: read)],
        ),
      );
}

class _TrackerGoalDetail extends ConsumerWidget {
  const _TrackerGoalDetail({required this.goal, required this.trackerId});

  final Goal goal;
  final String trackerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracker = ref.watch(trackerByIdProvider(trackerId));
    if (tracker.hasError) {
      return Scaffold(
        appBar: AppBar(),
        body: NimbusErrorState(
          title: l10n.goalsErrorTitle,
          retryLabel: l10n.commonRetry,
          detail: tracker.error.toString(),
          onRetry: () => ref.invalidate(trackerByIdProvider(trackerId)),
        ),
      );
    }
    if (!tracker.hasValue) {
      return Scaffold(appBar: AppBar(), body: const NimbusLoadingList());
    }
    final found = tracker.requireValue;
    // Deleted: the same card as on the tab (Review Focus 5).
    if (found == null) {
      return _ProblemScaffold(name: goal.name, read: GoalReadable(goal));
    }
    return _Detail(goal: goal, tracker: found);
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.goal, this.tracker});

  final Goal goal;
  final Tracker? tracker;

  /// Resume re-baselines (spec §4.3), so the goal does not alert about what
  /// crossed while it was paused. Pause writes only the flag.
  Future<void> _toggle(BuildContext context, WidgetRef ref) =>
      reportingGoalFailure(
        messenger: ScaffoldMessenger.of(context),
        l10n: AppLocalizations.of(context),
        write: () =>
            ref.read(goalServiceProvider).setActive(goal, !goal.active),
      );

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    await deleteGoalWithUndo(
      messenger: ScaffoldMessenger.of(context),
      l10n: AppLocalizations.of(context),
      service: ref.read(goalServiceProvider),
      id: goal.id,
    );
    // Back to the list, where the undo shows and the goal returns on Undo.
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(goalsRoute);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(goal.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const Key('goal-detail-edit'),
            tooltip: l10n.goalsEdit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push(editGoalRoute(goal.id)),
          ),
          IconButton(
            key: const Key('goal-detail-pause'),
            tooltip: goal.active ? l10n.goalsPause : l10n.goalsResume,
            icon: Icon(goal.active
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline),
            onPressed: () => unawaited(_toggle(context, ref)),
          ),
          IconButton(
            key: const Key('goal-detail-delete'),
            tooltip: l10n.commonDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => unawaited(_delete(context, ref)),
          ),
        ],
      ),
      body: CustomScrollView(
        key: const Key('goal-detail'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(NimbusTokens.space4),
            sliver: SliverList.list(children: [
              if (goal.active)
                _Current(goal: goal, tracker: tracker)
              else
                const GoalStatusLine(
                    key: Key('goal-detail-status'), status: null),
              // A fixed range has one period, so no streak.
              if (goal.period is RecurringPeriod) _Streak(goal: goal),
              // Nor history: its one period is the current one.
              if (goal.period is RecurringPeriod) ...[
                const SizedBox(height: NimbusTokens.space4),
                Text(l10n.goalsHistoryTitle,
                    style: theme.textTheme.titleMedium),
              ],
            ]),
          ),
          if (goal.period is RecurringPeriod)
            SliverPadding(
              padding:
                  const EdgeInsets.symmetric(horizontal: NimbusTokens.space4),
              sliver: GoalHistoryList(goal: goal, tracker: tracker),
            ),
        ],
      ),
    );
  }
}

/// This period: the amounts in full (D1, a detail view), the status, the bar
/// or the run-rate, and the pace.
class _Current extends ConsumerWidget {
  const _Current({required this.goal, this.tracker});

  final Goal goal;
  final Tracker? tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = ref.watch(goalProgressProvider(goal));
    if (progress.hasError) {
      return GoalInlineError(
        key: const Key('goal-detail-progress-error'),
        message: l10n.goalsCardErrorTitle,
        onRetry: () => ref.invalidate(goalProgressProvider(goal)),
      );
    }
    if (!progress.hasValue) {
      return const GoalInlineSkeleton(key: Key('goal-detail-progress-loading'));
    }
    final value = progress.requireValue;
    final format = ref.watch(goalFormatProvider);
    final today = ref.watch(goalTodayProvider);
    final savings = kindOf(goal) == GoalKind.savingsTarget;
    final runRate = savings ? format.runRate(l10n, value) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.goalsProgressOf(format.amount(value.current, tracker: tracker),
              format.amount(value.target, tracker: tracker)),
          key: const Key('goal-detail-amounts'),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: NimbusTokens.space2),
        GoalStatusLine(key: const Key('goal-detail-status'), status: value.status),
        if (!savings) ...[
          const SizedBox(height: NimbusTokens.space2),
          GoalProgressBar(
              key: const Key('goal-detail-bar'), goal: goal, progress: value),
        ],
        if (runRate != null) ...[
          const SizedBox(height: NimbusTokens.space2),
          Text(runRate, key: const Key('goal-detail-run-rate')),
        ],
        // The pace is information only: an at-most status ignores it (spec
        // §2). Shown while the period is open, when there is a pace to
        // speak of.
        if (value.period.contains(today)) ...[
          const SizedBox(height: NimbusTokens.space2),
          Text(
            l10n.goalsPace(
              format.amount(value.projection.projectedEnd, tracker: tracker),
              format.date(goal.calendar, value.period.endInclusive),
            ),
            key: const Key('goal-detail-pace'),
          ),
        ],
      ],
    );
  }
}

class _Streak extends ConsumerWidget {
  const _Streak({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(goalHistoryProvider(goal));
    // The history below shows its own loading and error states, once.
    if (!history.hasValue) return const SizedBox.shrink();
    final streaks = history.requireValue.streaks;
    if (streaks.best == 0) return const SizedBox.shrink();
    final format = ref.watch(goalFormatProvider);
    return Padding(
      padding: const EdgeInsets.only(top: NimbusTokens.space2),
      child: Text(
        AppLocalizations.of(context).goalsStreak(streaks.current,
            format.digits(streaks.current), format.digits(streaks.best)),
        key: const Key('goal-detail-streak'),
      ),
    );
  }
}
