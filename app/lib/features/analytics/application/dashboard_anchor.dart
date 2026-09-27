import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';
import 'period_label.dart';

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

/// `1405/07` for one month, `1405/02 – 1405/07` for a window.
String viewPeriodLabel(
  DateRange range,
  AppCalendar calendar, {
  required bool persianDigits,
}) {
  final first = periodLabel(range, calendar, persianDigits: persianDigits);
  final last = periodLabel(
    DateRange(range.endInclusive, range.endInclusive),
    calendar,
    persianDigits: persianDigits,
  );
  return first == last ? first : '$first – $last';
}
