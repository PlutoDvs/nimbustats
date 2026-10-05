import 'package:meta/meta.dart';

import '../calendar/calendar.dart';

/// The dimension a tracker query buckets its entries along.
///
/// Sealed and separate from Phase 3's `GroupBy`, which buckets transactions.
/// A tracker has no category, tag or merchant, and a type that cannot name
/// them cannot be asked for them: only time and the tracker itself are here.
@immutable
sealed class TrackerGroupBy {
  const TrackerGroupBy();

  /// Throws [FormatException] on anything it does not recognise. A stored
  /// spec read back wrong would change what a Phase 5 goal measures.
  factory TrackerGroupBy.fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'none' => const TrackerGroupByNone(),
        'tracker' => const TrackerGroupByTracker(),
        'day' => const TrackerGroupByDay(),
        'period' => TrackerGroupByPeriod(_periodOf(json['period'])),
        'hourOfDay' => const TrackerGroupByHourOfDay(),
        'dayOfWeek' => const TrackerGroupByDayOfWeek(),
        final other =>
          throw FormatException('unknown tracker group-by kind "$other"'),
      };

  /// Stable discriminator, also the JSON tag.
  String get kind;

  Map<String, Object?> toJson() => {'kind': kind};

  static PeriodType _periodOf(Object? raw) {
    for (final period in PeriodType.values) {
      if (period.name != raw) continue;
      if (period == PeriodType.day) {
        throw const FormatException(
            'a tracker groups by day with kind "day", not "period"');
      }
      return period;
    }
    throw FormatException('unknown period type "$raw"');
  }
}

/// One bucket holding everything the query matched.
final class TrackerGroupByNone extends TrackerGroupBy {
  const TrackerGroupByNone();
  @override
  String get kind => 'none';
  @override
  bool operator ==(Object other) => other is TrackerGroupByNone;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'TrackerGroupByNone()';
}

/// One bucket per tracker: the tab's totals.
final class TrackerGroupByTracker extends TrackerGroupBy {
  const TrackerGroupByTracker();
  @override
  String get kind => 'tracker';
  @override
  bool operator ==(Object other) => other is TrackerGroupByTracker;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'TrackerGroupByTracker()';
}

/// The local day an entry was written on, read from `local_date_key` itself.
///
/// Needs no date range and no calendar, because a local day is the same day
/// in Jalali and Gregorian. That is what lets the streaks read a tracker's
/// whole history, where a period ladder would need a bounded range and one
/// CASE arm per day.
final class TrackerGroupByDay extends TrackerGroupBy {
  const TrackerGroupByDay();
  @override
  String get kind => 'day';
  @override
  bool operator ==(Object other) => other is TrackerGroupByDay;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'TrackerGroupByDay()';
}

/// A calendar period -- week, month, quarter or year -- on Phase 3's
/// `PeriodBoundaries` ladder, so a Jalali month is a Jalali month.
///
/// Refuses [PeriodType.day]. [TrackerGroupByDay] answers that, and two ways to
/// ask for days would be two cache keys and two plans for one question.
final class TrackerGroupByPeriod extends TrackerGroupBy {
  TrackerGroupByPeriod(this.period) {
    if (period == PeriodType.day) {
      throw ArgumentError.value(
          period, 'period', 'group by TrackerGroupByDay for days');
    }
  }

  final PeriodType period;

  @override
  String get kind => 'period';
  @override
  Map<String, Object?> toJson() => {'kind': kind, 'period': period.name};
  @override
  bool operator ==(Object other) =>
      other is TrackerGroupByPeriod && other.period == period;
  @override
  int get hashCode => Object.hash(kind, period);
  @override
  String toString() => 'TrackerGroupByPeriod(${period.name})';
}

/// The local hour an entry happened at, from its instant and the offset it
/// was logged with.
final class TrackerGroupByHourOfDay extends TrackerGroupBy {
  const TrackerGroupByHourOfDay();
  @override
  String get kind => 'hourOfDay';
  @override
  bool operator ==(Object other) => other is TrackerGroupByHourOfDay;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'TrackerGroupByHourOfDay()';
}

/// The ISO weekday an entry happened on.
final class TrackerGroupByDayOfWeek extends TrackerGroupBy {
  const TrackerGroupByDayOfWeek();
  @override
  String get kind => 'dayOfWeek';
  @override
  bool operator ==(Object other) => other is TrackerGroupByDayOfWeek;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'TrackerGroupByDayOfWeek()';
}
