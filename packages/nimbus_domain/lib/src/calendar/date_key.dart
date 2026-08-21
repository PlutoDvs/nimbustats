import 'package:meta/meta.dart';

/// A local calendar date encoded as `yyyymmdd`.
///
/// Stored on every transaction so period queries are an indexed integer range
/// scan. Because Jalali and Gregorian dates are in bijection, one Gregorian
/// key serves both calendars: period boundaries are computed in the active
/// calendar and then converted to keys.
///
/// All day arithmetic runs against UTC midnight. A local `DateTime` is the
/// wrong instrument for it: across a daylight-saving transition two adjacent
/// local midnights are 23 or 25 hours apart, and `Duration.inDays` truncates
/// that to 0 or 1 day. UTC has no such transitions, and a date carries no time
/// zone to begin with.
@immutable
final class DateKey implements Comparable<DateKey> {
  const DateKey(this.value);

  factory DateKey.fromParts(int year, int month, int day) {
    assert(month >= 1 && month <= 12, 'month out of range: $month');
    assert(day >= 1 && day <= 31, 'day out of range: $day');
    return DateKey(year * 10000 + month * 100 + day);
  }

  factory DateKey.fromDateTime(DateTime local) =>
      DateKey.fromParts(local.year, local.month, local.day);

  final int value;

  int get year => value ~/ 10000;
  int get month => (value ~/ 100) % 100;
  int get day => value % 100;

  /// ISO weekday, `DateTime.monday` (1) through `DateTime.sunday` (7).
  int get weekday => _utcMidnight().weekday;

  /// Local midnight, for display and interop. Not for day arithmetic — use
  /// [addDays] and [daysUntil], which are daylight-saving-proof.
  DateTime toDateTime() => DateTime(year, month, day);

  DateTime _utcMidnight() => DateTime.utc(year, month, day);

  DateKey addDays(int days) =>
      DateKey.fromDateTime(DateTime.utc(year, month, day + days));

  int daysUntil(DateKey other) =>
      other._utcMidnight().difference(_utcMidnight()).inDays;

  @override
  int compareTo(DateKey other) => value.compareTo(other.value);

  bool operator <(DateKey other) => value < other.value;
  bool operator <=(DateKey other) => value <= other.value;
  bool operator >(DateKey other) => value > other.value;
  bool operator >=(DateKey other) => value >= other.value;

  @override
  bool operator ==(Object other) => other is DateKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DateKey($value)';
}

/// An inclusive span of dates.
@immutable
final class DateRange {
  const DateRange(this.startInclusive, this.endInclusive);

  final DateKey startInclusive;
  final DateKey endInclusive;

  bool contains(DateKey key) => key >= startInclusive && key <= endInclusive;

  int get dayCount => startInclusive.daysUntil(endInclusive) + 1;

  @override
  bool operator ==(Object other) =>
      other is DateRange &&
      other.startInclusive == startInclusive &&
      other.endInclusive == endInclusive;

  @override
  int get hashCode => Object.hash(startInclusive, endInclusive);

  @override
  String toString() => 'DateRange($startInclusive..$endInclusive)';
}
