import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../application/tracker_insights_controller.dart';
import '../../application/tracker_insights_data.dart';
import '../../application/tracker_providers.dart';

/// Week, month or year, and which one: the Insights tab's single control.
class TrackerRangeBar extends ConsumerWidget {
  const TrackerRangeBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(trackerInsightsProvider);
    final controller = ref.read(trackerInsightsProvider.notifier);
    final today = ref.watch(trackerTodayProvider);
    final format = ref.watch(trackerFormatProvider);
    // Back in time is "previous" whichever way the script runs, so the glyph
    // follows the direction, as Phase 3's MonthBar picks its own.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final holdsToday = view.range.endInclusive >= today;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<TrackerRangeKind>(
          segments: [
            ButtonSegment(
                value: TrackerRangeKind.week,
                label: Text(l10n.trackerRangeWeek)),
            ButtonSegment(
                value: TrackerRangeKind.month,
                label: Text(l10n.trackerRangeMonth)),
            ButtonSegment(
                value: TrackerRangeKind.year,
                label: Text(l10n.trackerRangeYear)),
          ],
          selected: {view.kind},
          showSelectedIcon: false,
          style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.padded),
          onSelectionChanged: (selection) =>
              controller.select(selection.single),
        ),
        Row(
          children: [
            IconButton(
              key: const Key('tracker-range-previous'),
              icon: Icon(rtl ? Icons.chevron_right : Icons.chevron_left),
              tooltip: l10n.trackerRangePrevious,
              onPressed: () => controller.shift(-1),
            ),
            Expanded(
              child: Center(
                child: Text(
                  rangeLabel(view, format),
                  key: const Key('tracker-range-label'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
            IconButton(
              key: const Key('tracker-range-next'),
              icon: Icon(rtl ? Icons.chevron_left : Icons.chevron_right),
              tooltip: l10n.trackerRangeNext,
              onPressed: holdsToday ? null : () => controller.shift(1),
            ),
          ],
        ),
      ],
    );
  }
}
