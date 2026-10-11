import 'package:meta/meta.dart';

import '../analytics/json_support.dart';
import '../analytics/query_filters.dart';

/// What a goal measures over: matching transactions, or one tracker.
///
/// Stored as `goals.scope_json`. A scope holds filters, never a whole query:
/// the goal's metric decides the aggregate and its period decides the dates.
@immutable
sealed class GoalScope {
  const GoalScope();

  /// Reads `{"type":"money","filters":{...}}` or
  /// `{"type":"tracker","trackerId":"..."}`.
  ///
  /// Throws [FormatException] on an unknown type, a missing field, or money
  /// filters with a date range. Never defaults: a dropped filter widens what a
  /// goal measures, and a cap would then read under budget while the user is
  /// over.
  factory GoalScope.fromJson(Map<String, Object?> json) {
    switch (json['type']) {
      case 'money':
        final filters =
            QueryFilters.fromJson(jsonMapOf(json['filters'], 'filters'));
        if (filters.dateRange != null) {
          throw const FormatException(
              'a goal scope stores no date range; the period sets it');
        }
        return MoneyScope(filters);
      case 'tracker':
        final id = json['trackerId'];
        if (id is! String || id.isEmpty) {
          throw FormatException(
              'trackerId needs a non-empty string, got "$id"');
        }
        return TrackerScope(id);
      case final other:
        throw FormatException('unknown goal scope type "$other"');
    }
  }

  Map<String, Object?> toJson();
}

/// Transactions matching [filters]: Phase 3's lossless `QueryFilters`.
final class MoneyScope extends GoalScope {
  /// Throws [ArgumentError] when [filters] has a date range: the goal's
  /// period decides the dates, and a stored range would contradict it.
  MoneyScope(this.filters) {
    if (filters.dateRange != null) {
      throw ArgumentError.value(
          filters, 'filters', 'a goal scope has no date range');
    }
  }

  final QueryFilters filters;

  @override
  Map<String, Object?> toJson() =>
      {'type': 'money', 'filters': filters.toJson()};

  @override
  bool operator ==(Object other) =>
      other is MoneyScope && other.filters == filters;

  @override
  int get hashCode => Object.hash('money', filters);

  @override
  String toString() => 'MoneyScope(${filters.toJson()})';
}

/// One tracker's entries.
final class TrackerScope extends GoalScope {
  /// Throws [ArgumentError] when [trackerId] is empty.
  TrackerScope(this.trackerId) {
    if (trackerId.isEmpty) {
      throw ArgumentError.value(trackerId, 'trackerId', 'must not be empty');
    }
  }

  final String trackerId;

  @override
  Map<String, Object?> toJson() => {'type': 'tracker', 'trackerId': trackerId};

  @override
  bool operator ==(Object other) =>
      other is TrackerScope && other.trackerId == trackerId;

  @override
  int get hashCode => Object.hash('tracker', trackerId);

  @override
  String toString() => 'TrackerScope($trackerId)';
}
