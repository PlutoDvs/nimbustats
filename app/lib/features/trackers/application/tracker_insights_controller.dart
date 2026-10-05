import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';
import 'tracker_providers.dart';

/// How much history the Insights tab shows at once.
enum TrackerRangeKind {
  week(PeriodType.week),
  month(PeriodType.month),
  year(PeriodType.year);

  const TrackerRangeKind(this.period);

  /// The calendar period one range of this kind covers.
  final PeriodType period;
}

/// What the Insights tab is showing: one week, month or year of the active
/// calendar.
@immutable
final class TrackerInsightsView {
  const TrackerInsightsView({required this.kind, required this.range});

  final TrackerRangeKind kind;
  final DateRange range;

  @override
  bool operator ==(Object other) =>
      other is TrackerInsightsView && other.kind == kind && other.range == range;

  @override
  int get hashCode => Object.hash(kind, range);

  @override
  String toString() => 'TrackerInsightsView(${kind.name}, $range)';
}

/// The Insights tab's range.
///
/// The history chart and both patterns read this one range, because they are
/// three views of one question -- when this tracker's entries happened -- and
/// three controls would be three ways to get them out of step.
class TrackerInsightsController extends Notifier<TrackerInsightsView> {
  @override
  TrackerInsightsView build() {
    // Watched, so switching calendars or the week's first day re-anchors the
    // range: a Jalali month is not a Gregorian one.
    ref
      ..watch(calendarProvider)
      ..watch(firstDayOfWeekProvider);
    return _current(TrackerRangeKind.month);
  }

  /// Shows the range of [kind] that holds today.
  void select(TrackerRangeKind kind) => state = _current(kind);

  /// Moves the range by [delta] ranges of its kind, never past the one holding
  /// today: there is nothing to chart there.
  void shift(int delta) {
    final next = ref
        .read(calendarProvider)
        .shiftPeriod(state.range, state.kind.period, delta);
    if (next.startInclusive > ref.read(trackerTodayProvider)) return;
    state = TrackerInsightsView(kind: state.kind, range: next);
  }

  TrackerInsightsView _current(TrackerRangeKind kind) => TrackerInsightsView(
        kind: kind,
        range: ref.read(calendarProvider).periodContaining(
              ref.read(trackerTodayProvider),
              kind.period,
              firstDayOfWeek: ref.read(firstDayOfWeekProvider),
            ),
      );
}

/// Auto-disposed: the Insights tab keeps itself alive while its screen is up,
/// so the range lasts as long as the screen does and no longer.
final trackerInsightsProvider =
    NotifierProvider.autoDispose<TrackerInsightsController, TrackerInsightsView>(
        TrackerInsightsController.new);
