import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../database/app_database.dart';
import '../seed/ids.dart';
import 'goal_amount_columns.dart';

/// One period of one goal as cached: its value, the watermark it was
/// computed at, and the alert state beside them.
final class CachedPeriod {
  const CachedPeriod({
    required this.period,
    required this.value,
    required this.watermark,
    this.lastAlerted,
  });

  final DateRange period;

  /// Null when never computed. That is the current period's row, which
  /// exists only to hold [lastAlerted].
  final GoalAmount? value;

  /// The watermark [value] was computed at. Null means stale.
  final int? watermark;

  /// The highest alert percent already announced for [period].
  final int? lastAlerted;

  @override
  String toString() =>
      'CachedPeriod($period, $value, at $watermark, alerted $lastAlerted)';
}

/// `goal_period_results`: the per-period cache behind history and streaks,
/// and the alert state that stops a crossing from alerting twice.
///
/// The two kinds of column are never written together. [writeValues]
/// touches only the value and the watermark; [recordCrossing] and
/// [setBaseline] touch only the alert state. A cache rewrite therefore never
/// forgets an alert already shown (goals design, departure 2).
final class GoalPeriodResultsDao {
  GoalPeriodResultsDao(this._db);

  final AppDatabase _db;

  /// The goal's rows, oldest period first.
  Future<List<CachedPeriod>> forGoal(String goalId) async {
    final rows = await (_db.select(_db.goalPeriodResults)
          ..where((t) => t.goalId.equals(goalId))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.periodStart)]))
        .get();
    return [
      for (final row in rows)
        CachedPeriod(
          period: DateRange(row.periodStart, row.periodEnd),
          // Both null is legitimate here (a row that only holds alert
          // state); the helper rejects it, so decide it first.
          value: row.currentMinor == null && row.currentQuantity == null
              ? null
              : amountFromColumns(
                  row.currentMinor, row.currentQuantity, 'current'),
          watermark: row.sourceWatermark,
          lastAlerted: row.lastAlertedPercent,
        ),
    ];
  }

  /// Upserts each row's value and [watermark] by (goal, period start), in
  /// one transaction. `last_alerted_percent` is never written here.
  Future<void> writeValues(
    String goalId,
    List<({DateRange period, GoalAmount value})> rows,
    int watermark,
  ) =>
      _db.transaction(() async {
        final now = _now();
        for (final row in rows) {
          final value = amountToColumns(row.value);
          await _db.into(_db.goalPeriodResults).insert(
                GoalPeriodResultsCompanion.insert(
                  id: Ids.newId(),
                  goalId: goalId,
                  periodStart: row.period.startInclusive,
                  periodEnd: row.period.endInclusive,
                  currentMinor: Value(value.minor),
                  currentQuantity: Value(value.quantity),
                  sourceWatermark: Value(watermark),
                  createdAt: now,
                  updatedAt: now,
                ),
                onConflict: DoUpdate(
                  (_) => GoalPeriodResultsCompanion(
                    periodEnd: Value(row.period.endInclusive),
                    currentMinor: Value(value.minor),
                    currentQuantity: Value(value.quantity),
                    sourceWatermark: Value(watermark),
                    updatedAt: Value(now),
                  ),
                  target: _periodKey,
                ),
              );
        }
      });

  /// A hard delete, unlike every user-facing delete. These rows are a cache
  /// and the alert state beside it, and the re-baseline that follows
  /// rebuilds them (spec §4.3). A soft-deleted row would keep its
  /// (goal, period) key and collide with the row the re-baseline writes.
  Future<void> deleteForGoal(String goalId) => (_db.delete(_db.goalPeriodResults)
        ..where((t) => t.goalId.equals(goalId)))
      .go();

  /// Reads the period's alert state, runs [crossing] and writes the new
  /// state, in one transaction, and returns the alert, if any.
  ///
  /// The transaction is what lets two evaluations of one crossing -- the
  /// app's and, from Phase 6, a background isolate's -- alert once. drift
  /// runs a transaction alone on its connection, so the second call reads
  /// what the first wrote. There is no parallelism to cap. A second
  /// connection, Phase 6's isolate, is Phase 6's to verify.
  Future<GoalAlert?> recordCrossing(Goal goal, GoalProgress progress) =>
      _db.transaction(() async {
        final row = await (_db.select(_db.goalPeriodResults)
              ..where((t) => t.goalId.equals(goal.id))
              ..where((t) =>
                  t.periodStart.equalsValue(progress.period.startInclusive))
              ..where((t) => t.deletedAt.isNull()))
            .getSingleOrNull();
        final last = row?.lastAlertedPercent;
        final result = crossing(goal, progress, last);
        if (result.lastAlerted != last) {
          await _writeAlerted(goal.id, progress.period, result.lastAlerted);
        }
        return result.alert;
      });

  /// Records whatever [progress] already reaches as alerted, with no alert:
  /// the re-baseline after a create, an edit, a resume or a restore
  /// (spec §4.3).
  Future<void> setBaseline(Goal goal, GoalProgress progress) => _writeAlerted(
      goal.id, progress.period, reachedPercent(goal, progress.current));

  /// The latest write to anything a money goal reads (spec §3):
  /// transactions, categories and tags.
  ///
  /// Deleted rows are included on purpose, unlike every other query in this
  /// package. A soft delete is a write, and the row it stamps is exactly the
  /// one a live-only maximum would not see.
  ///
  /// It is table-wide, not limited to the goal's scope. An edit that takes a
  /// transaction *out* of a goal's category moves no in-scope maximum, and a
  /// category move changes what a subtree matches without touching a
  /// transaction. Tag links need no term of their own: the repository's
  /// save path rewrites the transaction row with them (plan Decision 5).
  ///
  /// shortcut: wall-clock stamps, so a write stamped at or before the
  /// stored maximum (a clock set back, or the same millisecond) does not
  /// move it; and a hard delete leaves no stamp, though
  /// `TransactionsDao.deleteTransaction` has no caller. The next ordinary
  /// write or any goal edit heals it. Upgrade to a write counter if a user
  /// report traces back to either.
  Future<int> moneyWatermark() async {
    final row = await _db
        .customSelect('SELECT MAX(m) AS m FROM ('
            'SELECT MAX(updated_at) AS m FROM transactions '
            'UNION ALL SELECT MAX(updated_at) FROM categories '
            'UNION ALL SELECT MAX(updated_at) FROM tags)')
        .getSingle();
    return row.read<int?>('m') ?? 0;
  }

  /// The latest write to [trackerId]'s entries, deleted ones included, for
  /// the reason [moneyWatermark] gives. A write to `trackers` itself changes
  /// no measurement, since a goal names its tracker by id. Same shortcut as
  /// [moneyWatermark]; entries are only ever soft-deleted.
  Future<int> trackerWatermark(String trackerId) async {
    final row = await _db.customSelect(
      'SELECT MAX(updated_at) AS m FROM tracker_entries WHERE tracker_id = ?',
      variables: [Variable.withString(trackerId)],
    ).getSingle();
    return row.read<int?>('m') ?? 0;
  }

  /// Upserts only the alert state of (goal, period).
  Future<void> _writeAlerted(String goalId, DateRange period, int? percent) {
    final now = _now();
    return _db.into(_db.goalPeriodResults).insert(
          GoalPeriodResultsCompanion.insert(
            id: Ids.newId(),
            goalId: goalId,
            periodStart: period.startInclusive,
            periodEnd: period.endInclusive,
            lastAlertedPercent: Value(percent),
            createdAt: now,
            updatedAt: now,
          ),
          onConflict: DoUpdate(
            (_) => GoalPeriodResultsCompanion(
              lastAlertedPercent: Value(percent),
              updatedAt: Value(now),
            ),
            target: _periodKey,
          ),
        );
  }

  /// The UNIQUE (goal_id, period_start) index every write upserts against.
  List<Column<Object>> get _periodKey =>
      [_db.goalPeriodResults.goalId, _db.goalPeriodResults.periodStart];

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}
