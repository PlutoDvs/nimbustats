import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';

/// One step of the drill-down trail.
///
/// Carries the path as well as the id because the filter is a *subtree* match
/// -- drilling into Food must include everything under it, not only rows filed
/// directly against Food, which is usually none of them.
final class CategoryCrumb {
  const CategoryCrumb({
    required this.id,
    required this.path,
    required this.name,
  });

  final String id;
  final String path;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is CategoryCrumb &&
      other.id == id &&
      other.path == path &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, path, name);

  @override
  String toString() => 'CategoryCrumb($id)';
}

/// What the breakdown is currently asking.
///
/// Deliberately holds the *question*, not the answer. The answer comes from
/// `analyticsResultProvider(spec)`, which is keyed on the spec's value
/// equality, so returning to a level the user already visited reuses the query
/// rather than issuing it again.
final class BreakdownView {
  const BreakdownView({
    required this.period,
    this.trail = const [],
    this.confirmedOnly = false,
  });

  final DateRange period;
  final List<CategoryCrumb> trail;

  /// False by default: unconfirmed captures are counted unless the user says
  /// otherwise, and the same default has to hold everywhere -- a dashboard
  /// that includes them beside a goal that does not is indefensible.
  final bool confirmedOnly;

  /// The trail's length *is* the depth to group at. Empty trail means group at
  /// depth 0, the roots; inside Food, group its children at depth 1.
  int get depth => trail.length;

  QuerySpec get spec => QuerySpec(
        filters: QueryFilters(
          dateRange: period,
          // A spending breakdown. Income in the same pie would make the
          // slices meaningless rather than merely mixed.
          direction: MoneyDirection.expense,
          categorySubtreePaths:
              trail.isEmpty ? const [] : [trail.last.path],
          confirmedOnly: confirmedOnly,
        ),
        groupBy: GroupByCategory(depth),
        aggregate: Aggregate.sum,
      );

  BreakdownView copyWith({
    DateRange? period,
    List<CategoryCrumb>? trail,
    bool? confirmedOnly,
  }) =>
      BreakdownView(
        period: period ?? this.period,
        trail: trail ?? this.trail,
        confirmedOnly: confirmedOnly ?? this.confirmedOnly,
      );
}

class BreakdownController extends Notifier<BreakdownView> {
  @override
  BreakdownView build() {
    // Watched: switching calendars has to re-anchor the period, because a
    // Jalali month is not a Gregorian one and the screen would otherwise keep
    // showing a range that no longer matches the labels around it.
    final calendar = ref.watch(calendarProvider);
    return BreakdownView(
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

  /// Drills one level in. The caller decides whether a category *has* a level
  /// below it; descending into a leaf would drop the user onto an empty screen
  /// they have to back out of.
  void drillInto(CategoryCrumb crumb) =>
      state = state.copyWith(trail: [...state.trail, crumb]);

  /// Truncates the trail to [length]. Zero returns to the roots.
  void popTo(int length) =>
      state = state.copyWith(trail: state.trail.take(length).toList());

  void setConfirmedOnly({required bool value}) =>
      state = state.copyWith(confirmedOnly: value);
}

final breakdownControllerProvider =
    NotifierProvider<BreakdownController, BreakdownView>(
        BreakdownController.new);
