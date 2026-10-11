import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../trackers/application/tracker_providers.dart';
import '../../application/goal_format.dart';
import '../../application/goal_kind.dart';
import '../../application/goal_providers.dart';
import '../../routes.dart';
import 'goal_write.dart';

/// One goal on the Goals tab (spec §5.1).
///
/// It shows the name, the status as a word and an icon, and `current of
/// target` in the settings' digits. Caps and habits fill a bar toward their
/// target; a savings target states its run-rate instead. Two cards offer
/// actions in place of numbers:
/// - a goal whose tracker was deleted: Edit and Delete;
/// - a row that does not parse: Delete.
class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.read});

  final GoalRead read;

  @override
  Widget build(BuildContext context) => switch (read) {
        GoalUnreadable(:final id, :final name) => _ProblemCard(
            id: id,
            name: name,
            message: AppLocalizations.of(context).goalsUnreadableTitle,
            canEdit: false,
          ),
        GoalReadable(:final goal) => switch (goal.scope) {
            TrackerScope(:final trackerId) =>
              _TrackerGoalCard(goal: goal, trackerId: trackerId),
            MoneyScope() => _GoalBody(goal: goal),
          },
      };
}

/// A tracker goal's card. An archived tracker is still measured and shown
/// (archiving is not deletion). A deleted one turns the card into an error
/// with Edit and Delete, never a crash or a silent zero (Review Focus 5).
class _TrackerGoalCard extends ConsumerWidget {
  const _TrackerGoalCard({required this.goal, required this.trackerId});

  final Goal goal;
  final String trackerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracker = ref.watch(trackerByIdProvider(trackerId));
    if (tracker.hasError) {
      return _CardError(
          goal: goal,
          onRetry: () => ref.invalidate(trackerByIdProvider(trackerId)));
    }
    if (!tracker.hasValue) return _CardSkeleton(goal: goal);
    final found = tracker.requireValue;
    if (found == null) {
      return _ProblemCard(
        id: goal.id,
        name: goal.name,
        message: AppLocalizations.of(context).goalsTrackerMissingTitle,
        canEdit: true,
      );
    }
    return _GoalBody(goal: goal, tracker: found);
  }
}

class _GoalBody extends ConsumerWidget {
  const _GoalBody({required this.goal, this.tracker});

  final Goal goal;

  /// A habit's tracker, which decides how its numbers read.
  final Tracker? tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (!goal.active) {
      // Paused goals are not evaluated (spec §1).
      return _CardFrame(
        goal: goal,
        label: l10n.goalsCardPausedSemantics(goal.name),
        children: const [GoalStatusLine(status: null)],
      );
    }
    final progress = ref.watch(goalProgressProvider(goal));
    if (progress.hasError) {
      return _CardError(
          goal: goal, onRetry: () => ref.invalidate(goalProgressProvider(goal)));
    }
    if (!progress.hasValue) return _CardSkeleton(goal: goal);

    final value = progress.requireValue;
    final format = ref.watch(goalFormatProvider);
    final amounts = l10n.goalsProgressOf(
      format.compact(value.current, tracker: tracker),
      format.compact(value.target, tracker: tracker),
    );
    // Savings report a required run-rate, which a bar cannot show (screen
    // contract §7.1).
    final savings = kindOf(goal) == GoalKind.savingsTarget;
    final runRate = savings ? format.runRate(l10n, value) : null;
    return _CardFrame(
      goal: goal,
      label: l10n.goalsCardSemantics(
          goal.name, amounts, goalStatusText(l10n, value.status)),
      children: [
        GoalStatusLine(status: value.status),
        const SizedBox(height: NimbusTokens.space1),
        Text(amounts, key: Key('goal-amounts-${goal.id}')),
        if (!savings) ...[
          const SizedBox(height: NimbusTokens.space2),
          GoalProgressBar(goal: goal, progress: value),
        ],
        if (runRate != null)
          Text(runRate, key: Key('goal-run-rate-${goal.id}')),
      ],
    );
  }
}

/// The tappable card. A screen reader hears it as one sentence ([label]),
/// with one tap action, rather than as five loose fragments.
class _CardFrame extends StatelessWidget {
  const _CardFrame(
      {required this.goal, required this.label, required this.children});

  final Goal goal;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void open() => context.push(goalDetailRoute(goal.id));
    return Card(
      key: Key('goal-card-${goal.id}'),
      margin: const EdgeInsets.only(bottom: NimbusTokens.space2),
      child: Semantics(
        container: true,
        button: true,
        label: label,
        onTap: open,
        excludeSemantics: true,
        child: InkWell(
          onTap: open,
          borderRadius: NimbusTokens.borderRadiusMd,
          child: Padding(
            padding: const EdgeInsets.all(NimbusTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // D2: one line, ellipsised; the detail screen has it whole.
                Text(goal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: NimbusTokens.space2),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// While a card's numbers load: its name, and a static bar where the
/// numbers will be. Never a spinner (screen contract §1.1).
class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) => _CardFrame(
        goal: goal,
        label: goal.name,
        children: [
          Container(
            key: Key('goal-skeleton-${goal.id}'),
            height: NimbusTokens.space4,
            decoration: BoxDecoration(
              color: NimbusSemanticColors.of(context).skeleton,
              borderRadius: NimbusTokens.borderRadiusSm,
            ),
          ),
        ],
      );
}

/// One goal's numbers failed. It says so, with a retry, on that card only,
/// so one failure does not cost the tab.
class _CardError extends StatelessWidget {
  const _CardError({required this.goal, required this.onRetry});

  final Goal goal;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Plain(
      id: goal.id,
      name: goal.name,
      icon: Icons.error_outline,
      message: l10n.goalsCardErrorTitle,
      actions: [TextButton(onPressed: onRetry, child: Text(l10n.commonRetry))],
    );
  }
}

/// A goal that cannot be shown: its tracker was deleted, or its row does not
/// parse. Edit only when there is a goal to edit.
class _ProblemCard extends ConsumerWidget {
  const _ProblemCard({
    required this.id,
    required this.name,
    required this.message,
    required this.canEdit,
  });

  final String id;
  final String name;
  final String message;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return _Plain(
      id: id,
      name: name,
      icon: Icons.error_outline,
      message: message,
      messageKey: Key('goal-problem-$id'),
      actions: [
        if (canEdit)
          TextButton(
            key: Key('goal-edit-$id'),
            onPressed: () => context.push(editGoalRoute(id)),
            child: Text(l10n.goalsEdit),
          ),
        TextButton(
          key: Key('goal-delete-$id'),
          onPressed: () => unawaited(deleteGoalWithUndo(
            messenger: ScaffoldMessenger.of(context),
            l10n: l10n,
            service: ref.read(goalServiceProvider),
            id: id,
          )),
          child: Text(l10n.commonDelete),
        ),
      ],
    );
  }
}

/// A card that is not a tap target: a message and its own buttons, each
/// reachable by a screen reader.
class _Plain extends StatelessWidget {
  const _Plain({
    required this.id,
    required this.name,
    required this.icon,
    required this.message,
    required this.actions,
    this.messageKey,
  });

  final String id;
  final String name;
  final IconData icon;
  final String message;
  final List<Widget> actions;
  final Key? messageKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('goal-card-$id'),
      margin: const EdgeInsets.only(bottom: NimbusTokens.space2),
      child: Padding(
        padding: const EdgeInsets.all(NimbusTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: NimbusTokens.space2),
            Row(
              children: [
                ExcludeSemantics(
                    child: Icon(icon, color: theme.colorScheme.error)),
                const SizedBox(width: NimbusTokens.space2),
                Expanded(child: Text(message, key: messageKey)),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(spacing: NimbusTokens.space2, children: actions),
            ),
          ],
        ),
      ),
    );
  }
}

/// A status as an icon and a word, never colour alone. A null [status] is
/// a paused goal.
class GoalStatusLine extends StatelessWidget {
  const GoalStatusLine({super.key, required this.status});

  final GoalStatus? status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = this.status;
    final color = _statusColor(theme.colorScheme, status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(
            switch (status) {
              null => Icons.pause_circle_outline,
              GoalStatus.notStarted => Icons.schedule,
              GoalStatus.onTrack => Icons.check_circle_outline,
              GoalStatus.atRisk => Icons.warning_amber_rounded,
              GoalStatus.exceeded => Icons.error_outline,
              GoalStatus.met => Icons.emoji_events_outlined,
              GoalStatus.missed => Icons.highlight_off,
            },
            size: 18,
            color: color,
          ),
        ),
        const SizedBox(width: NimbusTokens.space1),
        // Flexible: a status wraps, at twice the font size, rather than
        // pushing past the card's edge.
        Flexible(
          child: Text(
            status == null
                ? l10n.goalsStatusPaused
                : goalStatusText(l10n, status),
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Fills toward the target from the reading side: from the right in
/// Persian. The bar names its goal and speaks its percent in the settings'
/// digits; the default would speak Latin digits in Persian.
class GoalProgressBar extends ConsumerWidget {
  const GoalProgressBar({super.key, required this.goal, required this.progress});

  final Goal goal;
  final GoalProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fraction = progress.fractionOfTarget;
    return LinearProgressIndicator(
      // Infinite for anything on a zero limit, which is simply full.
      value: fraction.isFinite ? fraction.clamp(0.0, 1.0).toDouble() : 1.0,
      minHeight: NimbusTokens.space2,
      borderRadius: NimbusTokens.borderRadiusSm,
      color: _statusColor(Theme.of(context).colorScheme, progress.status),
      semanticsLabel: goal.name,
      semanticsValue: ref.watch(goalFormatProvider).percent(fraction),
    );
  }
}

/// From the theme, never a raw colour. The word and the icon carry the
/// meaning; the colour only echoes it.
Color _statusColor(ColorScheme scheme, GoalStatus? status) => switch (status) {
      null || GoalStatus.notStarted => scheme.outline,
      GoalStatus.onTrack || GoalStatus.met => scheme.primary,
      GoalStatus.atRisk => scheme.tertiary,
      GoalStatus.exceeded || GoalStatus.missed => scheme.error,
    };
