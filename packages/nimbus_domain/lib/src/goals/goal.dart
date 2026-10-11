import 'dart:convert';

import 'package:meta/meta.dart';

import '../calendar/calendar.dart';
import 'goal_amount.dart';
import 'goal_direction.dart';
import 'goal_metric.dart';
import 'goal_period.dart';
import 'goal_scope.dart';

/// One goal: [metric] over [scope] each [period], compared to [target] in
/// [direction].
///
/// A combination that means nothing is refused at construction with an
/// [ArgumentError], so nothing downstream has to ask. The editor checks the
/// user-facing rules first and shows them inline; this is the backstop.
@immutable
final class Goal {
  /// Throws [ArgumentError] when:
  /// - [name] is blank;
  /// - [scope] is not a `TrackerScope` for a tracker metric, or not a
  ///   `MoneyScope` for any other;
  /// - [target] is not a `MoneyAmount` for a money metric, or not a
  ///   `QuantityAmount` for any other;
  /// - [metric] is `netSavings` and the filters name a direction (it reads
  ///   both);
  /// - [target] is negative, or zero on `atLeast` ("zero cigarettes" is a
  ///   real limit; "reach zero" is not a goal);
  /// - [alertPercents] is empty, not strictly ascending, or outside 1..100;
  /// - [weekStart] is not an ISO weekday, `DateTime.monday`..`sunday`.
  Goal({
    required this.id,
    required this.name,
    required this.metric,
    required this.scope,
    required this.direction,
    required this.target,
    required this.period,
    required this.calendar,
    required this.weekStart,
    List<int> alertPercents = defaultAlertPercents,
    this.active = true,
  }) : alertPercents = List.unmodifiable(alertPercents) {
    _validate();
  }

  static const defaultAlertPercents = <int>[80, 100];

  final String id;
  final String name;
  final GoalMetric metric;
  final GoalScope scope;
  final GoalDirection direction;
  final GoalAmount target;
  final GoalPeriod period;

  /// The goal's own calendar, copied from settings at creation. Switching the
  /// app's calendar later does not move this goal's periods.
  final CalendarKind calendar;

  /// ISO weekday a weekly period starts on, copied from settings at creation.
  final int weekStart;

  /// Whole percents, strictly ascending. Unmodifiable.
  final List<int> alertPercents;

  /// False when paused: not evaluated, no alerts.
  final bool active;

  void _validate() {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be blank');
    }
    final scope = this.scope;
    if (metric.isTrackerMetric != (scope is TrackerScope)) {
      throw ArgumentError.value(scope, 'scope',
          '${metric.name} does not measure over this kind of scope');
    }
    if (metric.isMoney != (target is MoneyAmount)) {
      throw ArgumentError.value(target, 'target',
          '${metric.name} does not measure this kind of amount');
    }
    if (metric == GoalMetric.netSavings &&
        scope is MoneyScope &&
        scope.filters.direction != null) {
      throw ArgumentError.value(scope, 'scope',
          'net savings reads income and expense, so it takes no direction');
    }
    if (target.isNegative) {
      throw ArgumentError.value(target, 'target', 'must not be negative');
    }
    if (target.isZero && direction == GoalDirection.atLeast) {
      throw ArgumentError.value(
          target, 'target', 'a target to reach must be above zero');
    }
    if (alertPercents.isEmpty) {
      throw ArgumentError.value(
          alertPercents, 'alertPercents', 'needs at least one percent');
    }
    for (var i = 0; i < alertPercents.length; i++) {
      final percent = alertPercents[i];
      if (percent < 1 || percent > 100) {
        throw ArgumentError.value(
            alertPercents, 'alertPercents', '$percent is outside 1..100');
      }
      if (i > 0 && percent <= alertPercents[i - 1]) {
        throw ArgumentError.value(alertPercents, 'alertPercents',
            'must be strictly ascending, without duplicates');
      }
    }
    if (weekStart < DateTime.monday || weekStart > DateTime.sunday) {
      throw ArgumentError.value(
          weekStart, 'weekStart', 'must be an ISO weekday, 1..7');
    }
  }

  /// This goal with the named fields replaced, validated like a new one.
  Goal copyWith({
    String? name,
    GoalMetric? metric,
    GoalScope? scope,
    GoalDirection? direction,
    GoalAmount? target,
    GoalPeriod? period,
    CalendarKind? calendar,
    int? weekStart,
    List<int>? alertPercents,
    bool? active,
  }) =>
      Goal(
        id: id,
        name: name ?? this.name,
        metric: metric ?? this.metric,
        scope: scope ?? this.scope,
        direction: direction ?? this.direction,
        target: target ?? this.target,
        period: period ?? this.period,
        calendar: calendar ?? this.calendar,
        weekStart: weekStart ?? this.weekStart,
        alertPercents: alertPercents ?? this.alertPercents,
        active: active ?? this.active,
      );

  /// Reads `goals.alert_percents`. Throws [FormatException] on anything that
  /// is not a JSON list of ints. Range and order are the constructor's to
  /// check.
  static List<int> alertPercentsFromJson(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List || decoded.any((percent) => percent is! int)) {
      throw FormatException(
          'alert percents need a JSON list of ints, got "$raw"');
    }
    return List<int>.unmodifiable(decoded);
  }

  static String alertPercentsToJson(List<int> percents) =>
      jsonEncode(percents);

  @override
  bool operator ==(Object other) =>
      other is Goal &&
      other.id == id &&
      other.name == name &&
      other.metric == metric &&
      other.scope == scope &&
      other.direction == direction &&
      other.target == target &&
      other.period == period &&
      other.calendar == calendar &&
      other.weekStart == weekStart &&
      _samePercents(other.alertPercents, alertPercents) &&
      other.active == active;

  @override
  int get hashCode => Object.hash(id, name, metric, scope, direction, target,
      period, calendar, weekStart, Object.hashAll(alertPercents), active);

  static bool _samePercents(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'Goal($id, "$name", ${metric.name} ${direction.name} '
      '$target, $period, ${calendar.name}${active ? '' : ', paused'})';
}
