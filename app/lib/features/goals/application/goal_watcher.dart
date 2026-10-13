import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../analytics/application/analytics_providers.dart';
import 'goal_providers.dart';

/// Decides, while the app runs, that a goal has crossed one of its alert
/// percents (spec §4.1).
///
/// [alerts] is the stream Phase 6's `AlertRouter` subscribes to.
///
/// It evaluates every active goal's current period:
/// - once when [start]ed, for crossings made while the app was closed (a
///   background SMS capture, say);
/// - after a transaction, category or tag write, for money goals;
/// - after a tracker entry write, for tracker goals;
/// - when the day changes, because a new period may have begun.
/// - on [checkNow], after Phase 6's widget drain.
///
/// How it evaluates:
/// - Every trigger waits [debounce] for the next, so a burst of taps is
///   evaluated once.
/// - Every evaluation goes through `GoalService.check`, which records the
///   crossing in one transaction. A recomputation therefore never re-fires,
///   and two evaluators cannot fire one crossing twice.
/// - Closed periods never alert.
///
/// It is a plain class held by [goalWatcherProvider], which never rebuilds.
/// The watcher follows its inputs with `ref.listen`, never `ref.watch`, so
/// one [alerts] stream lasts the life of the app. A calendar switch rebuilds
/// the engine, and the watcher moves its write subscriptions to the new one.
final class GoalWatcher {
  GoalWatcher(this._ref, {this.debounce = const Duration(milliseconds: 300)});

  final Ref _ref;
  final Duration debounce;

  final _alerts = StreamController<GoalAlert>.broadcast();
  final _following = <ProviderSubscription<Object?>>[];
  StreamSubscription<void>? _moneyWrites;
  StreamSubscription<void>? _trackerWrites;
  Timer? _pending;
  var _moneyDue = false;
  var _trackersDue = false;
  var _holders = 0;

  /// Every crossing, once.
  Stream<GoalAlert> get alerts => _alerts.stream;

  /// Takes a hold on the watcher. The first hold starts watching, and
  /// evaluates every goal as soon as the goals have loaded; later holds only
  /// count. Every [start] is paired with one [stop].
  ///
  /// Counted because a router rebuild mounts the new shell's listener (start)
  /// before the old one disposes (stop); a flag would end up stopped.
  void start() {
    if (_holders++ > 0) return;
    _following.addAll([
      _ref.listen<AnalyticsEngine>(
          analyticsEngineProvider, (_, engine) => _follow(engine),
          fireImmediately: true),
      _ref.listen<AsyncValue<List<GoalRead>>>(goalsProvider, (previous, next) {
        // A failed goals stream leaves nothing to evaluate, so every alert
        // would stop with no signal off the Goals tab. Say so, once per
        // failure.
        if (next.hasError && !(previous?.hasError ?? false)) {
          FlutterError.reportError(FlutterErrorDetails(
            exception: next.error!,
            stack: next.stackTrace,
            library: 'goal watcher',
            context: ErrorDescription('while watching the goals'),
          ));
        }
        // The first list is the start-up evaluation. Later lists come from
        // edits, which re-baseline silently (spec §4.3), so they have
        // nothing to say.
        if (next.hasValue && !(previous?.hasValue ?? false)) {
          _due(money: true, trackers: true);
        }
      }, fireImmediately: true),
      _ref.listen<DateKey>(
          goalTodayProvider, (_, __) => _due(money: true, trackers: true)),
    ]);
  }

  /// Lets go of one hold. The last one stops watching and drops an
  /// evaluation that has not begun; [start] resumes. Never goes below zero.
  ///
  /// The shell calls this when it unmounts. The debounce timer lives here,
  /// in a provider that outlives the widget tree, and would otherwise run on
  /// after the screen that shows the alerts has gone.
  void stop() {
    if (_holders == 0 || --_holders > 0) return;
    _teardown();
  }

  /// Evaluates every active goal's current period now, and completes when
  /// that evaluation has. Any alert is on [alerts] by then (spec §2.5).
  ///
  /// For Phase 6's drain. The headless engine never [start]s the watcher, and
  /// a drain in the app engine should not wait out the debounce. A debounced
  /// evaluation already pending is folded into this one: it would evaluate a
  /// subset of the same goals. Two checks of one crossing still alert once,
  /// because `GoalService.check` records it in one transaction.
  Future<void> checkNow() {
    _pending?.cancel();
    _pending = null;
    _moneyDue = true;
    _trackersDue = true;
    return _evaluate();
  }

  void _teardown() {
    for (final subscription in _following) {
      subscription.close();
    }
    _following.clear();
    _pending?.cancel();
    _pending = null;
    _moneyDue = false;
    _trackersDue = false;
    unawaited(_moneyWrites?.cancel());
    unawaited(_trackerWrites?.cancel());
    _moneyWrites = null;
    _trackerWrites = null;
  }

  /// Tears down whatever the holders held, and closes [alerts].
  Future<void> dispose() async {
    _holders = 0;
    _teardown();
    await _alerts.close();
  }

  void _follow(AnalyticsEngine engine) {
    unawaited(_moneyWrites?.cancel());
    unawaited(_trackerWrites?.cancel());
    _moneyWrites = engine.changes().listen((_) => _due(money: true));
    _trackerWrites =
        engine.trackerChanges().listen((_) => _due(trackers: true));
  }

  void _due({bool money = false, bool trackers = false}) {
    _moneyDue |= money;
    _trackersDue |= trackers;
    _pending?.cancel();
    _pending = Timer(debounce, () => unawaited(_evaluate()));
  }

  Future<void> _evaluate() async {
    _pending = null;
    final money = _moneyDue;
    final trackers = _trackersDue;
    _moneyDue = false;
    _trackersDue = false;
    final service = _ref.read(goalServiceProvider);
    // A one-shot read, not goalsProvider: when this provider is read again
    // Riverpod deactivates the watcher's listens, and the paused stream
    // behind goalsProvider then serves a stale list off the Goals tab.
    final List<GoalRead> reads;
    try {
      reads = await service.goals();
    } on Object catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'goal watcher',
        context: ErrorDescription('while reading the goals'),
      ));
      return;
    }
    final goals = [
      for (final read in reads)
        if (read case GoalReadable(:final goal)
            when goal.active &&
                (goal.scope is TrackerScope ? trackers : money))
          goal,
    ];
    if (goals.isEmpty) return;
    // Issued together. drift runs them on its one connection, so there is
    // no parallelism to cap (spec §3, Concurrency).
    final results =
        await Future.wait([for (final goal in goals) _check(service, goal)]);
    for (final alert in results) {
      // An alert recorded after the shell let go has no one to show it. Its
      // state is already written, and Phase 6 will listen for the life of
      // the app.
      if (alert != null && !_alerts.isClosed) _alerts.add(alert);
    }
  }

  /// One goal's check. A failure is reported and costs that goal only.
  Future<GoalAlert?> _check(GoalService service, Goal goal) async {
    try {
      return await service.check(goal);
    } on Object catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'goal watcher',
        context: ErrorDescription('while checking goal ${goal.id}'),
      ));
      return null;
    }
  }
}

/// The app's one [GoalWatcher]. The shell's `GoalAlertListener` starts it
/// and shows its alerts, and Phase 6 subscribes to the same stream.
///
/// It watches nothing, so it never rebuilds and its [GoalWatcher.alerts]
/// stream is never replaced under a subscriber.
final goalWatcherProvider = Provider<GoalWatcher>((ref) {
  final watcher = GoalWatcher(ref);
  ref.onDispose(() => unawaited(watcher.dispose()));
  return watcher;
});
