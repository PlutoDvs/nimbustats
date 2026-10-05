import 'package:flutter/foundation.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import 'tracker_format.dart';
import 'tracker_insights_controller.dart';

/// One bar of the history chart: a day, or a month in the year view.
@immutable
final class TrackerBar {
  const TrackerBar(this.period, this.value);

  final DateRange period;
  final double value;

  @override
  bool operator ==(Object other) =>
      other is TrackerBar && other.period == period && other.value == value;

  @override
  int get hashCode => Object.hash(period, value);

  @override
  String toString() => 'TrackerBar($period, $value)';
}

/// Every bar the history chart draws for [view], quiet ones included.
///
/// The engine answers only the days or months that have entries. Plotting
/// those alone would put a sparse month's bars side by side and read as a
/// habit kept every day.
List<TrackerBar> historyBars(
    TrackerInsightsView view, TrackerResult result, AppCalendar calendar) {
  final byStart = <DateKey, double>{
    for (final bucket in result.buckets)
      if (bucket.key case PeriodKey(:final range))
        range.startInclusive: bucket.value,
  };
  final periods = view.kind == TrackerRangeKind.year
      ? PeriodBoundaries.series(PeriodType.month, view.range, calendar)
      : [
          for (var day = view.range.startInclusive;
              day <= view.range.endInclusive;
              day = day.addDays(1))
            DateRange(day, day),
        ];
  return [
    for (final period in periods)
      TrackerBar(period, byStart[period.startInclusive] ?? 0),
  ];
}

/// How many days of [range] have begun by [today]: what a per-day average
/// divides by, so the days still ahead do not dilute it.
int elapsedDays(DateRange range, DateKey today) {
  if (today < range.startInclusive) return 0;
  final end = today < range.endInclusive ? today : range.endInclusive;
  return range.startInclusive.daysUntil(end) + 1;
}

/// The index of the highest bar, the earliest one on a tie.
int peakIndex(List<double> values) {
  var peak = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > values[peak]) peak = i;
  }
  return peak;
}

/// The range as the range bar and the spoken summaries name it:
/// `1405/07/11 – 1405/07/17` for a week, `1405/07` for a month, `1405` for a
/// year. Numeric, as Phase 3's period labels are.
String rangeLabel(TrackerInsightsView view, TrackerFormat format) =>
    switch (view.kind) {
      TrackerRangeKind.week => '${format.date(view.range.startInclusive)} – '
          '${format.date(view.range.endInclusive)}',
      TrackerRangeKind.month => format.month(view.range.startInclusive),
      TrackerRangeKind.year => format.year(view.range.startInclusive),
    };
