import 'package:meta/meta.dart';

import '../analytics/aggregate.dart';
import '../analytics/json_support.dart';
import '../calendar/date_key.dart';
import 'tracker_group_by.dart';

/// One question about trackers: which trackers, over which days, bucketed
/// how, computing what.
///
/// The tracker counterpart of `QuerySpec`, answered by the same
/// `AnalyticsEngine`. Pure and serializable, because Phase 5 stores one as a
/// tracker goal's scope: a field that does not survive a JSON round trip
/// would change what a goal measures.
@immutable
final class TrackerQuerySpec {
  /// Throws [ArgumentError] when [trackerIds] is empty. "Every tracker" is not
  /// a question: litres and cigarettes do not add up.
  TrackerQuerySpec({
    required List<String> trackerIds,
    this.dateRange,
    required this.groupBy,
    required this.aggregate,
  }) : trackerIds = List.unmodifiable(trackerIds) {
    if (trackerIds.isEmpty) {
      throw ArgumentError.value(
          trackerIds, 'trackerIds', 'name at least one tracker');
    }
  }

  /// Throws [FormatException] on anything malformed, never guesses: a dropped
  /// or defaulted field would quietly change what a stored goal measures.
  factory TrackerQuerySpec.fromJson(Map<String, Object?> json) =>
      TrackerQuerySpec(
        trackerIds: _idsOf(json['trackerIds']),
        dateRange: _rangeOf(json['dateRange']),
        groupBy:
            TrackerGroupBy.fromJson(jsonMapOf(json['groupBy'], 'groupBy')),
        aggregate: _aggregateOf(json['aggregate']),
      );

  /// Unmodifiable, in the order given. Equality compares them in that order.
  final List<String> trackerIds;
  final DateRange? dateRange;
  final TrackerGroupBy groupBy;
  final Aggregate aggregate;

  Map<String, Object?> toJson() => {
        'trackerIds': trackerIds,
        if (dateRange != null)
          'dateRange': {
            'start': dateRange!.startInclusive.value,
            'end': dateRange!.endInclusive.value,
          },
        'groupBy': groupBy.toJson(),
        'aggregate': aggregate.name,
      };

  /// This question over [range] instead; null makes it undated.
  TrackerQuerySpec withDateRange(DateRange? range) => TrackerQuerySpec(
        trackerIds: trackerIds,
        dateRange: range,
        groupBy: groupBy,
        aggregate: aggregate,
      );

  static List<String> _idsOf(Object? raw) {
    if (raw is! List || raw.isEmpty || raw.any((id) => id is! String)) {
      throw FormatException(
          'trackerIds needs a non-empty list of strings, got "$raw"');
    }
    return raw.cast<String>();
  }

  static DateRange? _rangeOf(Object? raw) {
    if (raw == null) return null;
    final map = jsonMapOf(raw, 'dateRange');
    final start = map['start'];
    final end = map['end'];
    if (start is! int || end is! int) {
      // Both ends are required. Defaulting one would quietly widen or narrow
      // every answer computed from the stored spec.
      throw FormatException('dateRange needs int start and end, got '
          '"$start" and "$end"');
    }
    return DateRange(DateKey(start), DateKey(end));
  }

  static Aggregate _aggregateOf(Object? raw) {
    for (final value in Aggregate.values) {
      if (value.name == raw) return value;
    }
    throw FormatException('unknown aggregate "$raw"');
  }

  @override
  bool operator ==(Object other) =>
      other is TrackerQuerySpec &&
      _sameIds(other.trackerIds, trackerIds) &&
      other.dateRange == dateRange &&
      other.groupBy == groupBy &&
      other.aggregate == aggregate;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(trackerIds), dateRange, groupBy, aggregate);

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'TrackerQuerySpec($trackerIds, $groupBy, ${aggregate.name})';
}
