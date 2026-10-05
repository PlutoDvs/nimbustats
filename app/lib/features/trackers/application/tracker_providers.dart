import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../bootstrap/database_provider.dart';
import '../../analytics/application/analytics_providers.dart';
import '../data/tracker_clock.dart';
import '../data/tracker_repository.dart';

/// The clock every tracker read and write goes through. Tests override it to
/// stand at a chosen instant, in a chosen timezone.
final trackerClockProvider =
    Provider<TrackerClock>((ref) => const TrackerClock());

final trackerRepositoryProvider = Provider<TrackerRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TrackerRepository(db.trackersDao, db.trackerEntriesDao,
      ref.watch(analyticsEngineProvider), ref.watch(trackerClockProvider));
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

/// The answer to one tracker question, keyed on the question itself.
///
/// Mirrors Phase 3's `analyticsResultProvider`. It is auto-disposed, and
/// re-run whenever the engine reports a tracker entry write, so a total never
/// outlives the tap that changed it. Two widgets asking the same question
/// share one query, because `TrackerQuerySpec` has value equality.
final trackerResultProvider =
    FutureProvider.autoDispose.family<TrackerResult, TrackerQuerySpec>(
  (ref, spec) async {
    final engine = ref.watch(analyticsEngineProvider);
    final changes = engine.trackerChanges().listen((_) => ref.invalidateSelf());
    ref.onDispose(changes.cancel);
    return engine.runTracker(spec);
  },
);

/// Every tab tracker's total for today, keyed by tracker id. A tracker with
/// nothing logged today has no key.
///
/// A synchronous view over [trackerResultProvider] rather than a future that
/// awaits two others: it re-derives the moment either input changes, with no
/// `ref` used after an await. A refresh keeps the previous value, so the tab
/// does not flicker to a skeleton between a tap and its new total.
final trackerTotalsProvider =
    Provider.autoDispose<AsyncValue<Map<String, double>>>((ref) {
  final today = ref.watch(trackerTodayProvider);
  final trackers = ref.watch(trackersProvider);
  if (trackers.hasError) {
    return AsyncError(trackers.error!, trackers.stackTrace!);
  }
  if (!trackers.hasValue) return const AsyncLoading();
  final ids = [for (final tracker in trackers.requireValue) tracker.id];
  if (ids.isEmpty) return const AsyncData({});
  return ref
      .watch(trackerResultProvider(TrackerQueries.dayTotals(ids, today)))
      .whenData((result) => {
            for (final bucket in result.buckets)
              if (bucket.key case TrackerKey(:final trackerId))
                trackerId: bucket.value,
          });
});

/// One tracker's total for today, archived or not: the detail header. The
/// tab's totals cover only the tab's trackers.
final trackerDayTotalProvider =
    Provider.autoDispose.family<AsyncValue<double>, String>((ref, id) => ref
        .watch(trackerResultProvider(
            TrackerQueries.dayTotal(id, ref.watch(trackerTodayProvider))))
        .whenData((result) => result.sum));

/// The manager's "Archived" section.
final archivedTrackersProvider = StreamProvider<List<Tracker>>(
    (ref) => ref.watch(trackerRepositoryProvider).watchArchived());

/// One live tracker, archived or not, or null once it no longer exists: the
/// detail screen.
final trackerByIdProvider = StreamProvider.autoDispose.family<Tracker?, String>(
    (ref, id) => ref.watch(trackerRepositoryProvider).watchTracker(id));

/// A tracker's streaks as of today, read from every day it was ever logged.
///
/// Synchronous over [trackerResultProvider], like [trackerTotalsProvider], and
/// it re-derives on the day rolling over as well as on a write.
final trackerStreaksProvider =
    Provider.autoDispose.family<AsyncValue<TrackerStreaks>, String>((ref, id) {
  final today = ref.watch(trackerTodayProvider);
  return ref
      .watch(trackerResultProvider(TrackerQueries.loggedDays(id)))
      .whenData((result) => TrackerStreaks.of([
            for (final bucket in result.buckets)
              if (bucket.key case PeriodKey(:final range)) range.startInclusive,
          ], today: today));
});
