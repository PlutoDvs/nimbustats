import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../application/tracker_providers.dart';
import 'widgets/tracker_day_rollover.dart';
import 'widgets/tracker_presets_empty.dart';
import 'widgets/tracker_tile.dart';

/// The Trackers tab: every tracker with today's total and its one-tap action.
class TrackersScreen extends ConsumerWidget {
  const TrackersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final trackers = ref.watch(trackersProvider);
    final totals = ref.watch(trackerTotalsProvider);

    // hasError and hasValue rather than a switch on the AsyncValue subtype: a
    // refresh carries the previous value, and blanking the list to a skeleton
    // between two emissions reads as a flicker.
    final Widget body;
    if (trackers.hasError || totals.hasError) {
      body = NimbusErrorState(
        title: l10n.trackerErrorTitle,
        retryLabel: l10n.commonRetry,
        detail: (trackers.error ?? totals.error).toString(),
        onRetry: () {
          ref.invalidate(trackersProvider);
          ref.invalidate(trackerTotalsProvider);
        },
      );
    } else if (!trackers.hasValue || !totals.hasValue) {
      body = const NimbusLoadingList(rows: 4);
    } else if (trackers.requireValue.isEmpty) {
      body = const TrackerPresetsEmpty();
    } else {
      final list = trackers.requireValue;
      final today = totals.requireValue;
      body = ListView.builder(
        key: const Key('trackers-list'),
        // Anchored to the bottom: the first trackers sit in thumb reach above
        // the nav bar (screen contract §1.3, one-handed reach).
        reverse: true,
        // The bottom is kept clear for the undo snackbar every tap shows (a
        // floating one, up to two lines). Without the gap it would sit over
        // the first tracker's button, and the second tap of a run would land
        // on the snackbar instead of on +1.
        padding: const EdgeInsets.only(
          top: NimbusTokens.space2,
          bottom: NimbusTokens.minTapTarget * 2,
        ),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final tracker = list[index];
          return TrackerTile(tracker: tracker, total: today[tracker.id] ?? 0);
        },
      );
    }

    return TrackerDayRollover(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.trackerScreenTitle)),
        body: body,
      ),
    );
  }
}
