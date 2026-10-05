import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../routes.dart';
import 'tracker_action_button.dart';
import 'tracker_today_text.dart';

/// One tracker on the tab: its icon, its name and today's total.
class TrackerTile extends StatelessWidget {
  const TrackerTile({super.key, required this.tracker, required this.total});

  final Tracker tracker;
  final double total;

  @override
  Widget build(BuildContext context) => ListTile(
        key: Key('tracker-tile-${tracker.id}'),
        minTileHeight: NimbusTokens.minTapTarget + NimbusTokens.space6,
        leading: ExcludeSemantics(
          child: Icon(nimbusIconFor(tracker.iconKey),
              color: Color(tracker.color)),
        ),
        title: Text(tracker.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => context.push(trackerLocation(tracker.id)),
        subtitle: TrackerTodayText(
          key: Key('tracker-total-${tracker.id}'),
          tracker: tracker,
          total: total,
        ),
        trailing: TrackerActionButton(tracker: tracker, total: total),
      );
}
