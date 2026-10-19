import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../goals/application/goal_format.dart';
import '../../../goals/application/goal_providers.dart';
import '../../routes.dart';
import 'tracker_action_button.dart';
import 'tracker_today_text.dart';

/// One tracker on the tab: its icon, its name and today's total, or its
/// goal's progress when it has one.
class TrackerTile extends ConsumerWidget {
  const TrackerTile({super.key, required this.tracker, required this.total});

  final Tracker tracker;
  final double total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = ref.watch(trackerGoalProvider(tracker.id));
    final progress = goal == null
        ? null
        : ref.watch(goalProgressProvider(goal)).value;
    final format = ref.watch(goalFormatProvider);

    return ListTile(
      key: Key('tracker-tile-${tracker.id}'),
      minTileHeight: NimbusTokens.minTapTarget + NimbusTokens.space6,
      leading: ExcludeSemantics(
        child:
            Icon(nimbusIconFor(tracker.iconKey), color: Color(tracker.color)),
      ),
      title: Text(tracker.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => context.push(trackerLocation(tracker.id)),
      subtitle: KeyedSubtree(
        key: Key('tracker-total-${tracker.id}'),
        // A running timer keeps its ticking time; it is what a timer
        // user is watching.
        child: progress == null || tracker.runningTimer != null
            ? TrackerTodayText(tracker: tracker, total: total)
            : Text(
                AppLocalizations.of(context).goalsProgressOf(
                  format.amount(progress.current, tracker: tracker),
                  format.amount(progress.target, tracker: tracker),
                ),
              ),
      ),
      trailing: TrackerActionButton(tracker: tracker, total: total),
    );
  }
}
