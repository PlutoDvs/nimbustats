import 'package:meta/meta.dart';

import '../calendar/calendar.dart';
import '../calendar/date_key.dart';
import 'period_boundaries.dart';

/// The window a saved view covers, relative to a date chosen when it is drawn.
///
/// A `QuerySpec`'s date range is absolute, so a view pinned as "this month"
/// would otherwise stay on the month it was pinned. This is the relative
/// half: the last [count] periods of [type], ending with the one containing
/// whatever date the dashboard is showing.
@immutable
final class ViewPeriod {
  ViewPeriod(this.type, this.count) {
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'must be at least 1');
    }
  }

  /// Parses the two stored columns.
  ///
  /// Throws [FormatException] for anything unusable, a count below one
  /// included: in stored data that is corruption rather than a caller's
  /// mistake, and the saved-views DAO turns format errors into an unreadable
  /// card instead of a crash.
  factory ViewPeriod.fromStored(String type, int count) {
    for (final value in PeriodType.values) {
      if (value.name == type) {
        if (count < 1) {
          throw FormatException('period count must be at least 1, got $count');
        }
        return ViewPeriod(value, count);
      }
    }
    throw FormatException('unknown period type "$type"');
  }

  final PeriodType type;
  final int count;

  /// The [count] periods of [type] ending with the one containing [anchor].
  DateRange resolve(
    DateKey anchor,
    AppCalendar calendar, {
    int firstDayOfWeek = PeriodBoundaries.defaultFirstDayOfWeek,
  }) {
    // Through PeriodBoundaries, so a card's range is cut by the same door as
    // the engine's bucketing and the trends tab.
    final newest = PeriodBoundaries.forPeriod(type, anchor, calendar,
        firstDayOfWeek: firstDayOfWeek);
    final oldest =
        count == 1 ? newest : calendar.shiftPeriod(newest, type, -(count - 1));
    return DateRange(oldest.startInclusive, newest.endInclusive);
  }

  @override
  bool operator ==(Object other) =>
      other is ViewPeriod && other.type == type && other.count == count;

  @override
  int get hashCode => Object.hash(type, count);

  @override
  String toString() => 'ViewPeriod(${type.name} x $count)';
}
