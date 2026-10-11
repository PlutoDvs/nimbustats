import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/goal_format.dart';
import '../../application/goal_providers.dart';
import 'goal_card.dart';

/// What the draft would have said over its last closed periods, and where
/// this period stands, so a target is chosen against reality rather than
/// guessed (screen contract §7.2). Nothing while the draft cannot be saved.
class GoalPreviewPanel extends ConsumerWidget {
  const GoalPreviewPanel({super.key, required this.goal, this.tracker});

  /// The draft as it stood once the form settled; null while it is invalid.
  final Goal? goal;
  final Tracker? tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = goal;
    if (draft == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preview = ref.watch(goalPreviewProvider(draft));

    final Widget body;
    if (preview.hasError) {
      body = Row(
        key: const Key('goal-preview-error'),
        children: [
          Expanded(child: Text(l10n.goalsPreviewError)),
          TextButton(
            onPressed: () => ref.invalidate(goalPreviewProvider(draft)),
            child: Text(l10n.commonRetry),
          ),
        ],
      );
    } else if (!preview.hasValue) {
      body = Container(
        key: const Key('goal-preview-loading'),
        height: NimbusTokens.minTapTarget,
        decoration: BoxDecoration(
          color: NimbusSemanticColors.of(context).skeleton,
          borderRadius: NimbusTokens.borderRadiusSm,
        ),
      );
    } else {
      final value = preview.requireValue;
      final format = ref.watch(goalFormatProvider);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final outcome in value.recent)
            GoalOutcomeRow(
              key: Key('goal-preview-${outcome.period.startInclusive.value}'),
              goal: draft,
              outcome: outcome,
              tracker: tracker,
            ),
          Text(
            l10n.goalsPreviewCurrent(
              l10n.goalsProgressOf(
                format.amount(value.current.current, tracker: tracker),
                format.amount(value.current.target, tracker: tracker),
              ),
            ),
            key: const Key('goal-preview-current'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.goalsPreviewTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: NimbusTokens.space2),
        body,
      ],
    );
  }
}

/// One closed period: its name in the goal's calendar, its value, and how it
/// ended. Shared by the preview and the detail screen's history.
class GoalOutcomeRow extends ConsumerWidget {
  const GoalOutcomeRow({
    super.key,
    required this.goal,
    required this.outcome,
    this.tracker,
  });

  final Goal goal;
  final PeriodOutcome outcome;
  final Tracker? tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = ref.watch(goalFormatProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NimbusTokens.space2),
      child: Row(
        children: [
          Expanded(child: Text(format.period(goal, outcome.period))),
          Expanded(child: Text(format.amount(outcome.value, tracker: tracker))),
          Expanded(child: GoalStatusLine(status: outcome.status)),
        ],
      ),
    );
  }
}
