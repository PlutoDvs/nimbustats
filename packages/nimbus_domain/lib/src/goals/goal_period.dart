import 'package:meta/meta.dart';

import '../calendar/calendar.dart';
import '../calendar/date_key.dart';

const _fixedRangeName = 'fixedRange';

/// When a goal applies: every calendar period of one type, or one fixed range.
///
/// Maps one-to-one onto `goals.period`, `start_date` and `end_date`. A
/// combination those columns could hold but that means nothing -- a month
/// with an end date, a range without one -- cannot be built.
@immutable
sealed class GoalPeriod {
  const GoalPeriod();

  /// Reads the stored columns back.
  ///
  /// Throws [FormatException] on an unknown name, an end date on a recurring
  /// period, a fixed range without one, or a range that ends before it starts.
  factory GoalPeriod.fromStored(String period, int startDate, int? endDate) {
    if (period == _fixedRangeName) {
      if (endDate == null) {
        throw const FormatException('a fixed range needs an end date');
      }
      if (endDate < startDate) {
        throw FormatException(
            'a fixed range ends ($endDate) before it starts ($startDate)');
      }
      return FixedRangePeriod(DateRange(DateKey(startDate), DateKey(endDate)));
    }
    for (final type in PeriodType.values) {
      if (type.name != period) continue;
      if (endDate != null) {
        throw FormatException(
            'a recurring "$period" goal has no end date, got $endDate');
      }
      return RecurringPeriod(type, DateKey(startDate));
    }
    throw FormatException('unknown goal period "$period"');
  }

  /// `goals.period`: a [PeriodType] name, or `fixedRange`.
  String get storedName;

  /// `goals.start_date`.
  DateKey get startDate;

  /// `goals.end_date`: null for a recurring period.
  DateKey? get endDate;
}

/// Every [type] period, from the one containing [since].
final class RecurringPeriod extends GoalPeriod {
  const RecurringPeriod(this.type, this.since);

  final PeriodType type;

  /// History starts with the period containing this day.
  final DateKey since;

  @override
  String get storedName => type.name;

  @override
  DateKey get startDate => since;

  @override
  DateKey? get endDate => null;

  @override
  bool operator ==(Object other) =>
      other is RecurringPeriod && other.type == type && other.since == since;

  @override
  int get hashCode => Object.hash(type, since);

  @override
  String toString() => 'RecurringPeriod(${type.name} since $since)';
}

/// One period: [range], for a target such as savings by a date.
final class FixedRangePeriod extends GoalPeriod {
  /// Throws [ArgumentError] when [range] ends before it starts.
  FixedRangePeriod(this.range) {
    if (range.endInclusive < range.startInclusive) {
      throw ArgumentError.value(range, 'range', 'ends before it starts');
    }
  }

  final DateRange range;

  @override
  String get storedName => _fixedRangeName;

  @override
  DateKey get startDate => range.startInclusive;

  @override
  DateKey get endDate => range.endInclusive;

  @override
  bool operator ==(Object other) =>
      other is FixedRangePeriod && other.range == range;

  @override
  int get hashCode => Object.hash(_fixedRangeName, range);

  @override
  String toString() => 'FixedRangePeriod($range)';
}
