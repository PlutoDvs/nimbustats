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

/// The value-axis step for a [type] tracker whose highest bar is [peak], on
/// an axis with room for [intervals] steps. Null leaves the step to fl_chart.
///
/// Left to itself, fl_chart picks a "round" step from the axis height alone.
/// For a boolean (peak 1) that is 0.5, half a "done"; for a counter at 2,
/// halves again; for an hour, 1000 seconds, labelled 0:16 and 0:33. So:
/// - A boolean or a counter steps in whole numbers, 1, 2 or 5 times a power
///   of ten, and never below 1.
/// - A duration steps in 15 or 30 minutes, or in whole hours.
/// - Each takes the smallest such step that fits [peak] in [intervals]
///   steps, the count fl_chart itself aims for, so the axis never carries
///   more labels than it did.
///
/// An amount keeps fl_chart's step: with 0.25 L a tap, a fraction is a real
/// value.
double? valueAxisStep(TrackerType type, double peak,
        {required int intervals}) =>
    switch (type) {
      TrackerType.boolean || TrackerType.counter =>
        _wholeStep(peak / intervals),
      TrackerType.duration => _durationStep(peak / intervals),
      TrackerType.quantity => null,
    };

/// The smallest of 1, 2, 5, 10, 20, 50, ... that is at least [atLeast].
double _wholeStep(double atLeast) {
  var power = 1.0;
  while (power * 10 < atLeast) {
    power *= 10;
  }
  for (final multiple in const [1, 2, 5]) {
    if (multiple * power >= atLeast) return multiple * power;
  }
  return 10 * power;
}

/// The smallest of 15 minutes, 30 minutes or a whole number of hours that
/// is at least [atLeast] seconds. A duration's value is in seconds.
double _durationStep(double atLeast) {
  const quarterHour = 15 * 60.0;
  const halfHour = 30 * 60.0;
  const hour = 60 * 60.0;
  if (atLeast <= quarterHour) return quarterHour;
  if (atLeast <= halfHour) return halfHour;
  return (atLeast / hour).ceil() * hour;
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

/// The twenty-four hour bars, quiet hours included.
List<double> hourBars(TrackerResult result) {
  final byHour = <int, double>{
    for (final bucket in result.buckets)
      if (bucket.key case HourOfDayKey(:final hour)) hour: bucket.value,
  };
  return [for (var hour = 0; hour < 24; hour++) byHour[hour] ?? 0];
}

/// The seven weekday bars, in [order]: the user's week, as Phase 3's
/// `weekdaysFrom` lists it. Iran's week starts on Saturday, and ISO order
/// would shift every bar by two days in a way that reads as data.
List<double> weekdayBars(TrackerResult result, List<int> order) {
  final byWeekday = <int, double>{
    for (final bucket in result.buckets)
      if (bucket.key case DayOfWeekKey(:final weekday)) weekday: bucket.value,
  };
  return [for (final weekday in order) byWeekday[weekday] ?? 0];
}
