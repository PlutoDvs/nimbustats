import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';

/// The date every dashboard card is resolved against. Today, until moved.
class DashboardAnchor extends Notifier<DateKey> {
  @override
  DateKey build() => DateKey.fromDateTime(DateTime.now());

  void shift(int months) =>
      state = shiftMonths(state, months, ref.read(calendarProvider));
}

final dashboardAnchorProvider =
    NotifierProvider<DashboardAnchor, DateKey>(DashboardAnchor.new);

/// [anchor] moved by whole months in [calendar]: the first day of the month
/// [months] away. A month at a time because every pin source is monthly; a
/// smaller step would change nothing on screen.
DateKey shiftMonths(DateKey anchor, int months, AppCalendar calendar) =>
    calendar
        .shiftPeriod(
          calendar.periodContaining(anchor, PeriodType.month),
          PeriodType.month,
          months,
        )
        .startInclusive;

/// [view]'s question with the dates it covers when the dashboard is on
/// [anchor].
///
/// The only way a card gets a runnable spec. A stored spec has no dates, and
/// run as-is it would total the whole history under a one-month label.
QuerySpec resolvedSpec(
  SavedView view,
  DateKey anchor,
  AppCalendar calendar, {
  required int firstDayOfWeek,
}) =>
    view.spec.withDateRange(
      view.period.resolve(anchor, calendar, firstDayOfWeek: firstDayOfWeek),
    );

/// The periods a trend view plots: its resolved window, cut into the periods
/// it groups by.
List<DateRange> trendPeriods(
  QuerySpec resolved,
  AppCalendar calendar, {
  required int firstDayOfWeek,
}) {
  final groupBy = resolved.groupBy;
  if (groupBy is! GroupByPeriod) {
    throw ArgumentError.value(groupBy, 'resolved', 'a trend groups by period');
  }
  return PeriodBoundaries.series(
    groupBy.period,
    resolved.filters.dateRange!,
    calendar,
    firstDayOfWeek: firstDayOfWeek,
  );
}
