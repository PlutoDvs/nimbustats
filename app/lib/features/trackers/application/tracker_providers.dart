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

/// [source]'s state with [derive] applied to its value, keeping any value the
/// source still carries: the derivation behind every view over
/// [trackerResultProvider].
///
/// - An error if the source has one.
/// - The derived value whenever the source has a value, even while it is
///   being asked again.
/// - Loading only when the source has neither: a question asked for the
///   first time.
///
/// `AsyncValue.whenData` gets only half of this right. A write invalidates
/// the question, and that refresh carries the previous answer as data, which
/// whenData keeps. But a change to something the question watches (the
/// calendar, which rebuilds the engine) is a reload, whose state is loading
/// *with* the previous answer, and whenData turns that into a bare loading
/// with none (Riverpod 3.4.2, `async_value.dart`). The screens would then
/// blank to their skeletons.
///
/// A question asked for the first time has nothing to keep. A view that must
/// bridge that too, such as a new day's question, keeps its own last value
/// (see [TrackerTotals]).
AsyncValue<R> deriveKeepingValue<T, R>(
    AsyncValue<T> source, R Function(T value) derive) {
  if (source.hasError) return AsyncError<R>(source.error!, source.stackTrace!);
  if (!source.hasValue) return AsyncLoading<R>();
  try {
    return AsyncData(derive(source.requireValue));
  } catch (error, stackTrace) {
    // As whenData does: a derivation that throws is this view's error, which
    // the screens show with a retry, rather than an exception thrown out of
    // every widget that watches it.
    return AsyncError<R>(error, stackTrace);
  }
}

/// Every tab tracker's total for today, keyed by tracker id. A tracker with
/// nothing logged today has no key.
///
/// Once it has a map it always has one, so the tab never blanks to its
/// skeleton after it has shown totals:
/// - A write re-runs today's question, and a calendar switch reloads it.
///   Both keep the previous answer ([deriveKeepingValue]).
/// - A new day, or a change to the tab's trackers (added, archived,
///   unarchived, deleted or reordered: the ids are compared in order), is a
///   new question with no answer yet. The last map stays until the new one
///   lands, as 4a's stream did. On a new day that means yesterday's totals
///   for the length of one query.
/// - It is not auto-disposed, which is 4a's lifetime. Switching tabs
///   unmounts the Trackers tab, and the map must still be here when the user
///   comes back.
///
/// It holds one question at a time, never one per day. Each question is a
/// member of the auto-disposed [trackerResultProvider], and a question this
/// stops watching (yesterday's, or the old id list's) is released.
class TrackerTotals extends Notifier<AsyncValue<Map<String, double>>> {
  @override
  AsyncValue<Map<String, double>> build() {
    final asked = _ask();
    if (asked.hasValue || asked.hasError) return asked;
    // The state before this rebuild: the last map, if there was one.
    final last = stateOrNull;
    return last != null && last.hasValue && !last.hasError ? last : asked;
  }

  AsyncValue<Map<String, double>> _ask() {
    final today = ref.watch(trackerTodayProvider);
    final trackers = ref.watch(trackersProvider);
    if (trackers.hasError) {
      return AsyncError(trackers.error!, trackers.stackTrace!);
    }
    if (!trackers.hasValue) return const AsyncLoading();
    final ids = [for (final tracker in trackers.requireValue) tracker.id];
    if (ids.isEmpty) return const AsyncData({});
    return deriveKeepingValue(
        ref.watch(trackerResultProvider(TrackerQueries.dayTotals(ids, today))),
        (result) => {
              for (final bucket in result.buckets)
                if (bucket.key case TrackerKey(:final trackerId))
                  trackerId: bucket.value,
            });
  }
}

final trackerTotalsProvider =
    NotifierProvider<TrackerTotals, AsyncValue<Map<String, double>>>(
        TrackerTotals.new);

/// One tracker's total for today, archived or not: the detail header. The
/// tab's totals cover only the tab's trackers.
///
/// A write's re-run and a calendar switch keep the total
/// ([deriveKeepingValue]). A new day is a new question with no answer yet;
/// the detail screen bridges that with the last total it showed.
final trackerDayTotalProvider =
    Provider.autoDispose.family<AsyncValue<double>, String>((ref, id) =>
        deriveKeepingValue(
            ref.watch(trackerResultProvider(
                TrackerQueries.dayTotal(id, ref.watch(trackerTodayProvider)))),
            (result) => result.sum));

/// The manager's "Archived" section.
final archivedTrackersProvider = StreamProvider<List<Tracker>>(
    (ref) => ref.watch(trackerRepositoryProvider).watchArchived());

/// One live tracker, archived or not, or null once it no longer exists: the
/// detail screen.
final trackerByIdProvider = StreamProvider.autoDispose.family<Tracker?, String>(
    (ref, id) => ref.watch(trackerRepositoryProvider).watchTracker(id));

/// A tracker's streaks as of today, read from every day it was ever logged.
///
/// A synchronous view over [trackerResultProvider]. A write's re-run and a
/// calendar switch keep the streaks ([deriveKeepingValue]). A new day keeps
/// them too, because it is not a new question: the days ever logged are
/// asked once, and only `today` moves, so the streaks re-derive at once.
final trackerStreaksProvider =
    Provider.autoDispose.family<AsyncValue<TrackerStreaks>, String>((ref, id) {
  final today = ref.watch(trackerTodayProvider);
  return deriveKeepingValue(
      ref.watch(trackerResultProvider(TrackerQueries.loggedDays(id))),
      (result) => TrackerStreaks.of([
            for (final bucket in result.buckets)
              if (bucket.key case PeriodKey(:final range)) range.startInclusive,
          ], today: today));
});
