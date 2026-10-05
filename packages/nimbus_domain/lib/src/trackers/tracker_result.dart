import 'package:meta/meta.dart';

import '../analytics/analytics_result.dart';

/// One row of a tracker answer.
@immutable
final class TrackerBucket {
  const TrackerBucket({
    required this.key,
    required this.value,
    required this.count,
  });

  /// `TotalKey`, `TrackerKey`, `PeriodKey`, `HourOfDayKey` or
  /// `DayOfWeekKey`, following the query's `TrackerGroupBy`.
  final BucketKey key;

  /// The aggregate's answer for this bucket: the sum for `Aggregate.sum`, the
  /// entry count for `Aggregate.count`, and so on. Unlike Phase 3's
  /// `Bucket.money`, a double can hold a count, so a count is not left at
  /// zero.
  final double value;

  /// How many entries fell in this bucket, whatever the aggregate.
  final int count;

  @override
  bool operator ==(Object other) =>
      other is TrackerBucket &&
      other.key == key &&
      other.value == value &&
      other.count == count;

  @override
  int get hashCode => Object.hash(key, value, count);

  @override
  String toString() => 'TrackerBucket($key, $value, n=$count)';
}

/// The answer to one `TrackerQuerySpec`.
///
/// No tracker dimension lets an entry land in two buckets, so [sum] and
/// [count] are the buckets' own, added up. There is no separate true total to
/// report, as Phase 3 must for tags.
@immutable
final class TrackerResult {
  const TrackerResult({
    required this.buckets,
    required this.sum,
    required this.count,
  });

  final List<TrackerBucket> buckets;

  /// The sum of every matched entry's value, whatever the aggregate.
  final double sum;

  /// How many entries matched.
  final int count;

  @override
  String toString() =>
      'TrackerResult(${buckets.length} buckets, sum $sum, n=$count)';
}
