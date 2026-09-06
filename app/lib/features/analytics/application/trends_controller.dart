import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';

/// A y-axis label: compact, and in whichever digits the settings ask for.
///
/// A top-level function rather than a closure inside the chart so it can be
/// tested directly. What matters is that the label goes through the app's
/// formatter at all -- an axis in Latin digits beside Persian amounts is the
/// failure, and asserting it through fl_chart's TitleMeta would be testing
/// fl_chart instead.
String trendsAxisLabel(double value, MoneyFormatter formatter) =>
    formatter.formatCompact(Money(value.round()));

/// What the trend is asking: a fixed window of consecutive periods.
final class TrendsView {
  const TrendsView({required this.periods, this.confirmedOnly = false});

  /// Six months is a window a person can hold in their head, and it fits a
  /// phone's width without the axis labels colliding.
  static const defaultPeriodCount = 6;

  /// Oldest first, so the newest point is the one at the right in LTR -- and
  /// the chart's own mirroring handles RTL without reversing the data.
  final List<DateRange> periods;

  final bool confirmedOnly;

  DateRange get span => DateRange(
        periods.first.startInclusive,
        periods.last.endInclusive,
      );

  DateRange get current => periods.last;

  /// Null when the window is a single period, which the default never is but
  /// a caller could ask for.
  DateRange? get previous =>
      periods.length >= 2 ? periods[periods.length - 2] : null;

  QuerySpec get spec => QuerySpec(
        filters: QueryFilters(
          dateRange: span,
          direction: MoneyDirection.expense,
          confirmedOnly: confirmedOnly,
        ),
        groupBy: const GroupByPeriod(PeriodType.month),
        aggregate: Aggregate.sum,
      );

  TrendsView copyWith({List<DateRange>? periods, bool? confirmedOnly}) =>
      TrendsView(
        periods: periods ?? this.periods,
        confirmedOnly: confirmedOnly ?? this.confirmedOnly,
      );
}

class TrendsController extends Notifier<TrendsView> {
  @override
  TrendsView build() {
    final calendar = ref.watch(calendarProvider);
    final current = calendar.periodContaining(
      DateKey.fromDateTime(DateTime.now()),
      PeriodType.month,
    );
    final oldest = calendar.shiftPeriod(
      current,
      PeriodType.month,
      -(TrendsView.defaultPeriodCount - 1),
    );
    return TrendsView(
      // Through PeriodBoundaries rather than by stepping the calendar here, so
      // the trend's periods are built by the same door the engine's bucketing
      // uses. Two callers deriving periods separately is how a chart ends up
      // one bucket out of step with its own axis.
      periods: PeriodBoundaries.series(
        PeriodType.month,
        DateRange(oldest.startInclusive, current.endInclusive),
        calendar,
      ),
    );
  }

  void setConfirmedOnly({required bool value}) =>
      state = state.copyWith(confirmedOnly: value);
}

final trendsControllerProvider =
    NotifierProvider<TrendsController, TrendsView>(TrendsController.new);
