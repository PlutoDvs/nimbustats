import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../analytics/application/patterns_controller.dart'
    show weekdaysFrom;
import '../../../settings/application/settings_providers.dart';
import '../../application/tracker_format.dart';
import '../../application/tracker_insights_controller.dart';
import '../../application/tracker_insights_data.dart';
import '../../application/tracker_providers.dart';
import 'tracker_bar_chart.dart';
import 'tracker_chart_section.dart';
import 'tracker_range_bar.dart';

/// The Insights tab: one range control, then the charts that read it.
class TrackerInsights extends ConsumerStatefulWidget {
  const TrackerInsights({super.key, required this.tracker});

  final Tracker tracker;

  @override
  ConsumerState<TrackerInsights> createState() => _TrackerInsightsState();
}

class _TrackerInsightsState extends ConsumerState<TrackerInsights>
    with AutomaticKeepAliveClientMixin {
  // Kept alive so the range survives a visit to the History tab. The
  // controller is auto-disposed, and this subtree is what watches it.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final tracker = widget.tracker;

    // One empty state for a tracker never logged, rather than three empty
    // charts that each say so.
    final streaks = ref.watch(trackerStreaksProvider(tracker.id));
    if (streaks.hasValue && streaks.requireValue.daysSinceLast == null) {
      return NimbusEmptyState(
        key: const Key('tracker-insights-empty'),
        icon: Icons.insights,
        title: l10n.trackerInsightsEmptyTitle,
        message: l10n.trackerInsightsEmptyMessage,
      );
    }

    final view = ref.watch(trackerInsightsProvider);
    return ListView(
      key: const Key('tracker-insights'),
      padding: const EdgeInsets.all(NimbusTokens.space4),
      children: [
        const TrackerRangeBar(),
        _HistorySection(tracker: tracker, view: view),
        _HourSection(tracker: tracker, view: view),
        _WeekdaySection(tracker: tracker, view: view),
      ],
    );
  }
}

class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.tracker, required this.view});

  final Tracker tracker;
  final TrackerInsightsView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final format = ref.watch(trackerFormatProvider);
    final calendar = ref.watch(calendarProvider);
    final today = ref.watch(trackerTodayProvider);
    final year = view.kind == TrackerRangeKind.year;

    return TrackerChartSection(
      sectionKey: 'history',
      title: year ? l10n.trackerInsightsByMonth : l10n.trackerInsightsByDay,
      spec: year
          ? TrackerQueries.byMonth(tracker.id, view.range)
          : TrackerQueries.byDay(tracker.id, view.range),
      builder: (context, result) {
        final bars = historyBars(view, result, calendar);
        final values = [for (final bar in bars) bar.value];
        final peak = bars[peakIndex(values)];
        final days = elapsedDays(view.range, today);
        // A boolean's per-day average would be a fraction of a "done", so it
        // says on how many days it was done instead.
        final caption = tracker.type == TrackerType.boolean
            ? l10n.trackerInsightsDoneCaption(
                format.number(result.sum), format.digits(days))
            : l10n.trackerInsightsTotalCaption(
                format.total(tracker, result.sum),
                format.total(tracker, days == 0 ? 0 : result.sum / days));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TrackerBarChart(
              key: const Key('tracker-history-chart'),
              values: values,
              color: Color(tracker.color),
              labelEvery: view.kind == TrackerRangeKind.month ? 5 : 1,
              labelOf: (index) {
                final parts =
                    calendar.partsOf(bars[index].period.startInclusive);
                return format.digits(year ? parts.month : parts.day);
              },
              axisLabelOf: (value) => format.axis(tracker, value),
              semanticsLabel: l10n.trackerInsightsHistorySummary(
                tracker.name,
                rangeLabel(view, format),
                format.total(tracker, result.sum),
                year
                    ? format.month(peak.period.startInclusive)
                    : format.date(peak.period.startInclusive),
                format.total(tracker, peak.value),
              ),
            ),
            const SizedBox(height: NimbusTokens.space2),
            Text(caption,
                key: const Key('tracker-history-caption'),
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        );
      },
    );
  }
}

class _HourSection extends ConsumerWidget {
  const _HourSection({required this.tracker, required this.view});

  final Tracker tracker;
  final TrackerInsightsView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final format = ref.watch(trackerFormatProvider);

    return TrackerChartSection(
      sectionKey: 'hour',
      // A timed session is stamped when its timer starts, so a duration's
      // hours are start times, and the title says so.
      title: tracker.type == TrackerType.duration
          ? l10n.trackerInsightsByStartHour
          : l10n.trackerInsightsByHour,
      spec: TrackerQueries.byHour(tracker.id, view.range),
      builder: (context, result) {
        final values = hourBars(result);
        final peak = peakIndex(values);
        return TrackerBarChart(
          key: const Key('tracker-hour-chart'),
          values: values,
          color: Color(tracker.color),
          // Twenty-four labels do not fit; the shape is the message here.
          labelEvery: 6,
          labelOf: format.digits,
          labelKeyPrefix: 'tracker-hour-label',
          axisLabelOf: (value) => format.axis(tracker, value),
          semanticsLabel: l10n.trackerInsightsHourSummary(
            tracker.name,
            rangeLabel(view, format),
            format.time(DateTime.utc(2000, 1, 1, peak)),
            format.total(tracker, values[peak]),
          ),
        );
      },
    );
  }
}

class _WeekdaySection extends ConsumerWidget {
  const _WeekdaySection({required this.tracker, required this.view});

  final Tracker tracker;
  final TrackerInsightsView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final format = ref.watch(trackerFormatProvider);
    final order = weekdaysFrom(ref.watch(firstDayOfWeekProvider));

    return TrackerChartSection(
      sectionKey: 'weekday',
      title: l10n.trackerInsightsByWeekday,
      spec: TrackerQueries.byWeekday(tracker.id, view.range),
      builder: (context, result) {
        final values = weekdayBars(result, order);
        final peak = peakIndex(values);
        return TrackerBarChart(
          key: const Key('tracker-weekday-chart'),
          values: values,
          color: Color(tracker.color),
          labelOf: (index) => _weekdayName(l10n, order[index]),
          labelKeyPrefix: 'tracker-weekday-label',
          axisLabelOf: (value) => format.axis(tracker, value),
          semanticsLabel: l10n.trackerInsightsWeekdaySummary(
            tracker.name,
            rangeLabel(view, format),
            _weekdayName(l10n, order[peak]),
            format.total(tracker, values[peak]),
          ),
        );
      },
    );
  }
}

/// A weekday's name, from the shared `weekday*` strings.
///
/// Phase 3 has the same switch, private to its patterns screen, which 4b does
/// not edit.
String _weekdayName(AppLocalizations l10n, int isoWeekday) =>
    switch (isoWeekday) {
      DateTime.monday => l10n.weekdayMonday,
      DateTime.tuesday => l10n.weekdayTuesday,
      DateTime.wednesday => l10n.weekdayWednesday,
      DateTime.thursday => l10n.weekdayThursday,
      DateTime.friday => l10n.weekdayFriday,
      DateTime.saturday => l10n.weekdaySaturday,
      _ => l10n.weekdaySunday,
    };
