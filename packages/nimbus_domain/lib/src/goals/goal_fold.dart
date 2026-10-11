import '../calendar/date_key.dart';
import 'goal_amount.dart';

/// One amount per period in [periods], in the same order: the sum of
/// [daily]'s entries that fall in it.
///
/// History is measured by day and folded here, in Dart, because the engine's
/// week grouping cannot honour a goal's own week start. Days with no entry
/// contribute nothing, so a period without data is [zero], which also fixes
/// the subtype of an empty answer. Each period's days are walked once, so the
/// cost is the days covered, not days times periods.
List<GoalAmount> foldDaily(Map<DateKey, GoalAmount> daily,
        List<DateRange> periods, GoalAmount zero) =>
    [for (final period in periods) _sumOver(daily, period, zero)];

GoalAmount _sumOver(
    Map<DateKey, GoalAmount> daily, DateRange period, GoalAmount zero) {
  var total = zero;
  for (var day = period.startInclusive;
      day <= period.endInclusive;
      day = day.addDays(1)) {
    final amount = daily[day];
    if (amount != null) total += amount;
  }
  return total;
}
