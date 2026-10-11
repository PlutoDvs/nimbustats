import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/goal_kind.dart';

/// A new goal starts here: four kinds, each a sentence the user recognises.
/// The four kinds are one formula, and the user never needs to know it
/// (screen contract §7.2).
class GoalKindTiles extends StatelessWidget {
  const GoalKindTiles({super.key, required this.onChosen});

  final ValueChanged<GoalKind> onChosen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Four tiles, all built, so each is found however large the text.
    return SingleChildScrollView(
      key: const Key('goal-kind-tiles'),
      padding: const EdgeInsets.all(NimbusTokens.space4),
      child: Column(
        children: [
          for (final kind in GoalKind.values)
            Card(
              child: ListTile(
                key: Key('goal-kind-${kind.name}'),
                minTileHeight: NimbusTokens.minTapTarget + NimbusTokens.space6,
                leading: ExcludeSemantics(
                  child: Icon(switch (kind) {
                    GoalKind.spendingCap => Icons.shopping_bag_outlined,
                    GoalKind.habitLimit => Icons.do_not_disturb_on_outlined,
                    GoalKind.habitGoal => Icons.trending_up,
                    GoalKind.savingsTarget => Icons.savings_outlined,
                  }),
                ),
                title: Text(switch (kind) {
                  GoalKind.spendingCap => l10n.goalsKindSpendingCap,
                  GoalKind.habitLimit => l10n.goalsKindHabitLimit,
                  GoalKind.habitGoal => l10n.goalsKindHabitGoal,
                  GoalKind.savingsTarget => l10n.goalsKindSavingsTarget,
                }),
                subtitle: Text(switch (kind) {
                  GoalKind.spendingCap => l10n.goalsKindSpendingCapHint,
                  GoalKind.habitLimit => l10n.goalsKindHabitLimitHint,
                  GoalKind.habitGoal => l10n.goalsKindHabitGoalHint,
                  GoalKind.savingsTarget => l10n.goalsKindSavingsTargetHint,
                }),
                onTap: () => onChosen(kind),
              ),
            ),
        ],
      ),
    );
  }
}
