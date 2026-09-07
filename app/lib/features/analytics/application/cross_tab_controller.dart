import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';

/// What the tag x category matrix is asking.
final class CrossTabView {
  const CrossTabView({
    required this.period,
    this.depth = 0,
    this.confirmedOnly = false,
  });

  final DateRange period;

  /// Category axis depth. Fixed at the roots for now: a matrix is already two
  /// dimensions on a phone screen, and expanding the category axis multiplies
  /// its columns before there is anywhere to put them.
  final int depth;

  final bool confirmedOnly;

  QuerySpec get spec => QuerySpec(
        filters: QueryFilters(
          dateRange: period,
          direction: MoneyDirection.expense,
          confirmedOnly: confirmedOnly,
        ),
        groupBy: GroupByTagCrossCategory(depth),
        aggregate: Aggregate.sum,
      );

  CrossTabView copyWith({
    DateRange? period,
    int? depth,
    bool? confirmedOnly,
  }) =>
      CrossTabView(
        period: period ?? this.period,
        depth: depth ?? this.depth,
        confirmedOnly: confirmedOnly ?? this.confirmedOnly,
      );
}

class CrossTabController extends Notifier<CrossTabView> {
  @override
  CrossTabView build() {
    final calendar = ref.watch(calendarProvider);
    return CrossTabView(
      period: calendar.periodContaining(
        DateKey.fromDateTime(DateTime.now()),
        PeriodType.month,
      ),
    );
  }

  void shiftPeriod(int delta) {
    final calendar = ref.read(calendarProvider);
    state = state.copyWith(
      period: calendar.shiftPeriod(state.period, PeriodType.month, delta),
    );
  }

  void setConfirmedOnly({required bool value}) =>
      state = state.copyWith(confirmedOnly: value);
}

final crossTabControllerProvider =
    NotifierProvider<CrossTabController, CrossTabView>(CrossTabController.new);
