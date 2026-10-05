import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../bootstrap/database_provider.dart';
import '../data/tracker_clock.dart';
import '../data/tracker_repository.dart';

/// The clock every tracker read and write goes through. Tests override it to
/// stand at a chosen instant, in a chosen timezone.
final trackerClockProvider =
    Provider<TrackerClock>((ref) => const TrackerClock());

final trackerRepositoryProvider = Provider<TrackerRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TrackerRepository(
      db.trackersDao, db.trackerEntriesDao, ref.watch(trackerClockProvider));
});

/// Today's local date, as the tracker screens see it.
///
/// Not re-read on every build: a screen left open overnight has to be told
/// the day changed. `TrackerDayRollover` does that at local midnight and on
/// every resume.
class TrackerToday extends Notifier<DateKey> {
  @override
  DateKey build() => ref.watch(trackerClockProvider).today();

  /// Re-reads the clock. Changes nothing until the date has moved, so a resume
  /// at noon rebuilds nothing.
  void refresh() {
    final today = ref.read(trackerClockProvider).today();
    if (today != state) state = today;
  }
}

final trackerTodayProvider =
    NotifierProvider<TrackerToday, DateKey>(TrackerToday.new);

/// The tab's trackers: live, unarchived, in the user's order.
final trackersProvider = StreamProvider<List<Tracker>>(
    (ref) => ref.watch(trackerRepositoryProvider).watchTrackers());

/// Every tracker's total for today, keyed by tracker id.
final trackerTotalsProvider = StreamProvider<Map<String, double>>((ref) => ref
    .watch(trackerRepositoryProvider)
    .watchTotals(ref.watch(trackerTodayProvider)));

/// The manager's "Archived" section.
final archivedTrackersProvider = StreamProvider<List<Tracker>>(
    (ref) => ref.watch(trackerRepositoryProvider).watchArchived());
