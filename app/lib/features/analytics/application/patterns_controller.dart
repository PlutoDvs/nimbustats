import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';

/// What the pattern charts are asking.
///
/// One period and three dimensions over it: hour of day, day of week, and the
/// reflection matrix. They share a period because they are three views of the
/// same question -- when and how this month's spending happened -- and three
/// independent period controls on one tab would be three ways to get them out
/// of step with each other.
final class PatternsView {
  const PatternsView({required this.period, this.confirmedOnly = false});

  final DateRange period;
  final bool confirmedOnly;

  QueryFilters get _filters => QueryFilters(
        dateRange: period,
        direction: MoneyDirection.expense,
        confirmedOnly: confirmedOnly,
      );

  QuerySpec get hourSpec => QuerySpec(
        filters: _filters,
        groupBy: const GroupByHourOfDay(),
        aggregate: Aggregate.sum,
      );

  QuerySpec get weekdaySpec => QuerySpec(
        filters: _filters,
        groupBy: const GroupByDayOfWeek(),
        aggregate: Aggregate.sum,
      );

  QuerySpec get reflectionSpec => QuerySpec(
        filters: _filters,
        groupBy: const GroupByReflection(),
        aggregate: Aggregate.sum,
      );

  PatternsView copyWith({DateRange? period, bool? confirmedOnly}) =>
      PatternsView(
        period: period ?? this.period,
        confirmedOnly: confirmedOnly ?? this.confirmedOnly,
      );
}

class PatternsController extends Notifier<PatternsView> {
  @override
  PatternsView build() {
    final calendar = ref.watch(calendarProvider);
    return PatternsView(
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

final patternsControllerProvider =
    NotifierProvider<PatternsController, PatternsView>(PatternsController.new);

/// The seven ISO weekdays in the order the user's week runs.
///
/// The engine answers in ISO numbering (1 = Monday), but Iran's week starts on
/// Saturday and that is the app's default. Rendering ISO order would shift
/// every bar by two days in a way that reads as data rather than as a bug.
List<int> weekdaysFrom(int firstDayOfWeek) =>
    [for (var i = 0; i < 7; i++) (firstDayOfWeek - 1 + i) % 7 + 1];
