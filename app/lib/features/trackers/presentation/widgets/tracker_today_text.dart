import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';

/// What a tracker has done today, in its own terms: "3 today", "Done today",
/// "0.75 L today", "1:30 today". The tab's tiles and the detail header say it
/// the same way.
class TrackerTodayText extends ConsumerWidget {
  const TrackerTodayText({
    super.key,
    required this.tracker,
    required this.total,
    this.style,
  });

  final Tracker tracker;
  final double total;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final format = ref.watch(trackerFormatProvider);
    final text = switch (tracker.type) {
      TrackerType.boolean => TrackerValues.isDone(total)
          ? l10n.trackerDoneToday
          : l10n.trackerNotDoneToday,
      _ => l10n.trackerTodayTotal(format.total(tracker, total)),
    };
    return Text(text, style: style);
  }
}
