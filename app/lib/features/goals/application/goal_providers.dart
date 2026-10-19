import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../bootstrap/database_provider.dart';
import '../../analytics/application/analytics_providers.dart';
import '../../trackers/application/tracker_providers.dart';

/// One day for the whole app: the trackers' (imported read-only), moved by
/// `TrackerDayRollover`. Until the shell's `GoalAlertListener` mounts that
/// rollover, a goal left open overnight is not told the day changed.
final goalTodayProvider = trackerTodayProvider;

/// The goals' one way into and out of the database.
///
/// It is rebuilt when the engine is (a calendar switch rebuilds it) and when
/// the day moves. The engine's `today` is therefore always
/// [goalTodayProvider]'s, and the watcher, the cards and the detail screen
/// agree on one day.
///
/// A calendar switch changes nothing a goal measures. Each goal computes its
/// periods in its own calendar and hands the engine plain date keys (spec,
/// finding 2).
final goalServiceProvider = Provider<GoalService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final today = ref.watch(goalTodayProvider);
  return GoalService(
    db,
    GoalEngine(
      EngineGoalMeasurer(db, ref.watch(analyticsEngineProvider)),
      // A value, not a provider read: a service still held across a rebuild
      // must not reach for a ref that has gone.
      today: () => today,
    ),
  );
});

/// Every live goal, active and paused, oldest first.
///
/// A row that does not parse arrives as [GoalUnreadable] rather than as an
/// error, so one bad row costs one card, not the tab. Kept alive: the
/// shell's watcher reads it for as long as the app runs.
final goalsProvider = StreamProvider<List<GoalRead>>(
    (ref) => ref.watch(appDatabaseProvider).goalsDao.watchAll());

/// The goal a tracker shows progress toward, on its tile and on the
/// home-screen widget: the first active goal on [trackerId] whose current
/// period is open [today], or null.
///
/// shortcut: one goal per tracker is shown, the oldest; others stay on the
/// Goals tab. Upgrade if trackers commonly carry more than one goal.
Goal? trackerGoal(Iterable<GoalRead> goals, String trackerId, DateKey today) {
  for (final read in goals) {
    if (read case GoalReadable(:final goal)) {
      final scope = goal.scope;
      if (goal.active &&
          scope is TrackerScope &&
          scope.trackerId == trackerId &&
          GoalPeriods.current(goal, today).contains(today)) {
        return goal;
      }
    }
  }
  return null;
}

/// [trackerGoal] for one tracker, following goal writes and the day.
final trackerGoalProvider =
    Provider.autoDispose.family<Goal?, String>((ref, trackerId) => trackerGoal(
          ref.watch(goalsProvider).value ?? const [],
          trackerId,
          ref.watch(goalTodayProvider),
        ));

/// Re-runs the provider behind [ref] whenever a write could move [goal]'s
/// numbers. For a money goal that is a transaction, category or tag write;
/// for a tracker goal, a tracker entry write. Mirrors
/// `analyticsResultProvider` and `trackerResultProvider`.
void _rerunOnWrites(Ref ref, Goal goal) {
  final engine = ref.watch(analyticsEngineProvider);
  final writes =
      goal.scope is TrackerScope ? engine.trackerChanges() : engine.changes();
  final subscription = writes.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
}

/// One goal's current period, measured live. The current period is never
/// served from the cache (spec §3).
///
/// Keyed on the goal itself, which has value equality, so an edited goal is
/// a new question.
///
/// Screens read `hasError`, `hasValue` and `requireValue` directly. Each of
/// these keeps the previous value through both a write's re-run and a reload
/// (a calendar switch, a new day). 4b's `deriveKeepingValue` exists for
/// *derived* views, and nothing here derives.
final goalProgressProvider =
    FutureProvider.autoDispose.family<GoalProgress, Goal>((ref, goal) {
  final service = ref.watch(goalServiceProvider);
  _rerunOnWrites(ref, goal);
  return service.engine.evaluateCurrent(goal);
});

/// One goal's closed periods and streaks, served from the self-healing
/// cache (spec §3).
final goalHistoryProvider =
    FutureProvider.autoDispose.family<GoalHistoryResult, Goal>((ref, goal) {
  final service = ref.watch(goalServiceProvider);
  _rerunOnWrites(ref, goal);
  return service.history(goal);
});

/// What a draft would have said over its last closed periods, and its
/// current progress (spec §5.3). The editor asks once its form has settled
/// for ~300 ms. The debounce lives in the editor's widget state, so no
/// provider timer outlives the screen.
final goalPreviewProvider = FutureProvider.autoDispose
    .family<GoalPreview, Goal>(
        (ref, draft) => ref.watch(goalServiceProvider).preview(draft));
