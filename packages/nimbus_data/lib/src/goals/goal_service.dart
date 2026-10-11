import 'package:nimbus_domain/nimbus_domain.dart';

import '../database/app_database.dart';
import 'goal_period_results_dao.dart';
import 'goals_dao.dart';

/// A goal's closed periods with their outcomes, oldest first, and the
/// streaks they make.
final class GoalHistoryResult {
  const GoalHistoryResult(this.outcomes, this.streaks);

  final List<PeriodOutcome> outcomes;
  final GoalStreaks streaks;

  @override
  String toString() => 'GoalHistoryResult(${outcomes.length} periods, '
      'streak ${streaks.current}/${streaks.best})';
}

/// What the editor shows beside a draft (goals design §5.3).
final class GoalPreview {
  const GoalPreview(this.recent, this.current);

  final List<PeriodOutcome> recent;
  final GoalProgress current;
}

/// Goals' data-layer service. It owns the per-period cache, re-baselining
/// and alert recording, which share one transaction boundary (plan
/// Decision 1).
///
/// The Goals tab asks for several histories at once (`Future.wait`). drift
/// runs them on its one connection, so there is no parallelism to cap.
final class GoalService {
  GoalService(this._db, this.engine);

  final AppDatabase _db;

  /// Must measure through the same [AppDatabase] as this service. [save]
  /// measures inside a drift transaction, and a transaction routes only its
  /// own database's statements.
  final GoalEngine engine;

  GoalsDao get _goals => _db.goalsDao;
  GoalPeriodResultsDao get _results => _db.goalPeriodResultsDao;

  /// Closed periods, oldest first, served from the cache where the
  /// watermark matches (spec §3). The current period is never served from
  /// the cache: it is measured live, and its row only holds alert state.
  Future<GoalHistoryResult> history(Goal goal) async {
    final today = engine.today();
    final periods = GoalPeriods.closed(goal, today);
    if (periods.isEmpty) {
      return const GoalHistoryResult(<PeriodOutcome>[], GoalStreaks.none);
    }
    // Read before measuring. A write that lands mid-measure then leaves the
    // rows stamped with the older watermark, so the next load recomputes
    // them. Read after, it would stamp old values as current for ever.
    final watermark = await _watermark(goal);
    final values = <DateRange, GoalAmount>{
      for (final row in await _results.forGoal(goal.id))
        if (row.watermark == watermark && row.value != null)
          row.period: row.value!,
    };
    final stale = [
      for (final period in periods)
        if (!values.containsKey(period)) period,
    ];
    if (stale.isNotEmpty) {
      final measured = await _measured(goal, stale);
      // Controller ruling D-C4. One transaction: the per-period inserts
      // commit together, and the write happens only if the stored goal still
      // equals the [goal] measured. Edits do not move the watermark, so
      // values of another definition (an edit that landed mid-measure, or a
      // stale caller) would otherwise be served to the stored goal. Comparing
      // content, not a row stamp, closes every ordering. The measured values
      // are still right for the [goal] the caller passed.
      await _db.transaction(() async {
        final stored = await _goals.byId(goal.id);
        if (stored is! GoalReadable || stored.goal != goal) return;
        await _results.writeValues(
          goal.id,
          [
            for (final (i, period) in stale.indexed)
              (period: period, value: measured[i]),
          ],
          watermark,
        );
      });
      for (final (i, period) in stale.indexed) {
        values[period] = measured[i];
      }
    }
    final outcomes = [
      for (final period in periods)
        _outcome(goal, period, values[period]!, today),
    ];
    return GoalHistoryResult(outcomes, GoalStreaks.of(outcomes));
  }

  /// Every live goal as stored now, one read.
  Future<List<GoalRead>> goals() => _goals.all();

  /// Evaluates the current period and records a crossing. Returns null,
  /// writing nothing, for a paused goal, a period that is not open, or a
  /// [goal] that is no longer what is stored (an edit, pause or delete
  /// landed since the caller read it).
  Future<GoalAlert?> check(Goal goal) async {
    if (!goal.active) return null;
    final today = engine.today();
    final period = GoalPeriods.current(goal, today);
    // Only an open period alerts. A fixed range not yet begun, or already
    // over, is as closed as last month is (spec §4.1).
    if (!period.contains(today)) return null;
    final progress = await engine.evaluate(goal, period);
    // A recurring goal whose `since` is after today has not begun.
    if (progress.status == GoalStatus.notStarted) return null;
    // Same content guard as [history]. Inside the crossing's own
    // transaction (a savepoint), so no edit can land between the check and
    // the write; an old definition must not write over the new baseline.
    return _db.transaction(() async {
      final stored = await _goals.byId(goal.id);
      if (stored is! GoalReadable || stored.goal != goal) return null;
      return _results.recordCrossing(goal, progress);
    });
  }

  /// Upsert, drop the cache, evaluate, baseline: one transaction (§4.3).
  Future<void> save(Goal goal) => _db.transaction(() async {
        await _goals.upsert(goal);
        await _rebaseline(goal);
      });

  /// Resuming re-baselines; pausing writes only the flag.
  Future<void> setActive(Goal goal, bool active) async {
    if (!active) return _goals.setActive(goal.id, false);
    await _db.transaction(() async {
      await _goals.setActive(goal.id, true);
      await _rebaseline(goal.copyWith(active: true));
    });
  }

  Future<void> delete(String id) => _goals.softDelete(id);

  /// Restores and re-baselines, because progress may have moved while the
  /// goal was deleted (plan Decision 8). An unreadable row is only
  /// restored: there is no goal to evaluate, and its card offers only
  /// Delete.
  Future<void> restore(String id) => _db.transaction(() async {
        await _goals.restore(id);
        final read = await _goals.byId(id);
        if (read is GoalReadable) await _rebaseline(read.goal);
      });

  /// The draft's last [periods] closed periods and its current progress.
  /// No cache, and no writes: a draft has no row to cache under.
  Future<GoalPreview> preview(Goal draft, {int periods = 3}) async {
    final today = engine.today();
    final current =
        await engine.evaluate(draft, GoalPeriods.current(draft, today));
    final recent = switch (draft.period) {
      FixedRangePeriod() => const <PeriodOutcome>[],
      RecurringPeriod(:final type) =>
        await _recent(draft, type, current.period, periods, today),
    };
    return GoalPreview(recent, current);
  }

  /// The [count] periods before [current], as if the draft had started
  /// early enough to have them. A new draft's `since` is today, so it has
  /// no closed periods of its own.
  Future<List<PeriodOutcome>> _recent(Goal draft, PeriodType type,
      DateRange current, int count, DateKey today) async {
    final calendar = GoalPeriods.calendarFor(draft.calendar);
    final since = calendar.shiftPeriod(current, type, -count).startInclusive;
    final early = draft.copyWith(period: RecurringPeriod(type, since));
    final closed = GoalPeriods.closed(early, today);
    final values = await _measured(early, closed);
    return [
      for (final (i, period) in closed.indexed)
        _outcome(early, period, values[i], today),
    ];
  }

  /// Spec §4.3. Drop the goal's cached rows -- after an edit their period
  /// keys may not be this goal's any more -- then record whatever the
  /// current period already reaches as alerted, without an alert. A paused
  /// goal is not evaluated; resuming re-baselines it.
  Future<void> _rebaseline(Goal goal) async {
    await _results.deleteForGoal(goal.id);
    if (!goal.active) return;
    await _results.setBaseline(goal, await engine.evaluateCurrent(goal));
  }

  Future<int> _watermark(Goal goal) => switch (goal.scope) {
        MoneyScope() => _results.moneyWatermark(),
        TrackerScope(:final trackerId) => _results.trackerWatermark(trackerId),
      };

  /// One daily measurement over the span [periods] cover, folded into one
  /// value per period.
  Future<List<GoalAmount>> _measured(
      Goal goal, List<DateRange> periods) async {
    if (periods.isEmpty) return const <GoalAmount>[];
    final daily = await engine.measurer.measureDaily(goal.metric, goal.scope,
        DateRange(periods.first.startInclusive, periods.last.endInclusive));
    return foldDaily(daily, periods, goal.target.zero);
  }

  static PeriodOutcome _outcome(
          Goal goal, DateRange period, GoalAmount value, DateKey today) =>
      PeriodOutcome(period, value, assess(goal, period, value, today).status);
}
