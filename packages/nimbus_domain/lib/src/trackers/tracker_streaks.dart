import 'package:meta/meta.dart';

import '../calendar/date_key.dart';

/// How a tracker's logged days run: the current streak, the longest, and how
/// long since the last entry.
@immutable
final class TrackerStreaks {
  const TrackerStreaks({
    required this.current,
    required this.longest,
    this.daysSinceLast,
  });

  /// Reads the streaks off the days in [loggedDays], as of [today].
  ///
  /// - A logged day has at least one live entry; for a boolean tracker, a
  ///   "done".
  /// - [current] is the run of consecutive logged days ending today, or
  ///   ending yesterday while today has nothing yet: a day is not missed until
  ///   it is over.
  /// - [longest] is the longest run anywhere, so never less than [current].
  /// - [daysSinceLast] is 0 when today is logged, and null when nothing ever
  ///   was.
  ///
  /// Days after [today] are ignored. The entry sheet should not produce them,
  /// and a clock set back must not turn into a streak. No calendar is needed:
  /// consecutive days are consecutive in every calendar.
  factory TrackerStreaks.of(Iterable<DateKey> loggedDays,
      {required DateKey today}) {
    final days =
        loggedDays.where((day) => day <= today).toSet().toList()..sort();
    if (days.isEmpty) return const TrackerStreaks(current: 0, longest: 0);

    var run = 1;
    var longest = 1;
    for (var i = 1; i < days.length; i++) {
      run = days[i - 1].addDays(1) == days[i] ? run + 1 : 1;
      if (run > longest) longest = run;
    }
    // `run` now holds the run that ends on the last logged day.
    final sinceLast = days.last.daysUntil(today);
    return TrackerStreaks(
      current: sinceLast <= 1 ? run : 0,
      longest: longest,
      daysSinceLast: sinceLast,
    );
  }

  final int current;
  final int longest;
  final int? daysSinceLast;

  @override
  bool operator ==(Object other) =>
      other is TrackerStreaks &&
      other.current == current &&
      other.longest == longest &&
      other.daysSinceLast == daysSinceLast;

  @override
  int get hashCode => Object.hash(current, longest, daysSinceLast);

  @override
  String toString() =>
      'TrackerStreaks(current $current, longest $longest, '
      'since last $daysSinceLast)';
}
