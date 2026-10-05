import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../database/app_database.dart';
import 'tracker_entries_dao.dart';

/// A tracker as the repository hands it over for insertion.
typedef NewTracker = ({
  String id,
  String name,
  String iconKey,
  int color,
  TrackerType type,
  String? unit,
  double? perTapValue,
});

/// Trackers and their running timers.
///
/// Reads return the domain [Tracker], never drift's row. The app layer may not
/// depend on drift, and this is the one place a row becomes a value.
class TrackersDao {
  TrackersDao(this._db);

  final AppDatabase _db;

  /// Appends [trackers] after every existing one, in the order given, as one
  /// transaction: the presets arrive together or not at all.
  Future<void> insertAll(List<NewTracker> trackers) =>
      _db.transaction(() async {
        final highest = _db.trackers.sortOrder.max();
        final top = await (_db.selectOnly(_db.trackers)..addColumns([highest]))
            .map((row) => row.read(highest))
            .getSingle();
        var next = (top ?? -1) + 1;
        final now = _now();
        for (final tracker in trackers) {
          await _db.into(_db.trackers).insert(TrackersCompanion.insert(
                id: tracker.id,
                name: tracker.name,
                iconKey: tracker.iconKey,
                color: tracker.color,
                type: tracker.type,
                unit: Value(tracker.unit),
                perTapValue: Value(tracker.perTapValue),
                sortOrder: Value(next++),
                createdAt: now,
                updatedAt: now,
              ));
        }
      });

  /// A live tracker, archived or not, or null.
  Future<Tracker?> byId(String id) async {
    final row = await _byId(id).getSingleOrNull();
    return row == null ? null : _toTracker(row);
  }

  Stream<Tracker?> watchById(String id) => _byId(id)
      .watchSingleOrNull()
      .map((row) => row == null ? null : _toTracker(row));

  /// Live trackers in the user's order: the unarchived ones for the tab, or
  /// the archived ones for the manager's section. Exposed so a test can assert
  /// its plan uses `idx_trackers_live`.
  SimpleSelectStatement<$TrackersTable, TrackerRow> liveQuery({
    required bool archived,
  }) =>
      _db.select(_db.trackers)
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.archived.equals(archived))
        ..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.id),
        ]);

  Stream<List<Tracker>> watchLive({required bool archived}) =>
      liveQuery(archived: archived)
          .watch()
          .map((rows) => rows.map(_toTracker).toList());

  /// Rewrites a tracker's editable fields in one statement, so an edit is
  /// never half-applied. The type is not among them: it is fixed at creation.
  /// The repository checks that [unit] and [perTapValue] fit the type.
  Future<void> updateTracker(
    String id, {
    required String name,
    required String iconKey,
    required int color,
    String? unit,
    double? perTapValue,
  }) async {
    final written =
        await (_db.update(_db.trackers)..where((t) => t.id.equals(id)))
            .write(TrackersCompanion(
      name: Value(name),
      iconKey: Value(iconKey),
      color: Value(color),
      unit: Value(unit),
      perTapValue: Value(perTapValue),
      updatedAt: Value(_now()),
    ));
    _expectOne(written, id);
  }

  Future<void> setArchived(String id, bool archived) async {
    final written =
        await (_db.update(_db.trackers)..where((t) => t.id.equals(id)))
            .write(TrackersCompanion(
      archived: Value(archived),
      updatedAt: Value(_now()),
    ));
    _expectOne(written, id);
  }

  /// Makes [ids] the stored order: each tracker's position becomes its sort
  /// order. One transaction, so no two trackers ever claim the same slot.
  Future<void> reorder(List<String> ids) => _db.transaction(() async {
        final now = _now();
        for (final (index, id) in ids.indexed) {
          final written =
              await (_db.update(_db.trackers)..where((t) => t.id.equals(id)))
                  .write(TrackersCompanion(
            sortOrder: Value(index),
            updatedAt: Value(now),
          ));
          _expectOne(written, id);
        }
      });

  /// Starts [id]'s timer at [startedAtUtcMs], unless one is already running.
  ///
  /// One conditional UPDATE, `WHERE timer_started_at_utc IS NULL`, so of two
  /// racing starts exactly one writes. That is the brief's "one running timer
  /// per tracker", held by the data layer.
  ///
  /// False when nothing was written: a timer was already running, or [id] is
  /// not a live duration tracker.
  Future<bool> startTimer(String id, int startedAtUtcMs) async {
    final written = await (_db.update(_db.trackers)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.type.equalsValue(TrackerType.duration))
          ..where((t) => t.timerStartedAtUtc.isNull()))
        .write(TrackersCompanion(
      timerStartedAtUtc: Value(startedAtUtcMs),
      updatedAt: Value(_now()),
    ));
    return written == 1;
  }

  /// Ends the timer that started at [startedAtUtcMs] and logs [entry], or
  /// logs nothing when [entry] is null. One transaction, so a timer is never
  /// cleared without its entry or logged while still running.
  ///
  /// Compare-and-clear: the column is cleared only if it still holds
  /// [startedAtUtcMs]. Two racing stops read the same start; the first clears
  /// it and logs, and the second matches nothing and logs nothing.
  ///
  /// False when the timer was no longer running from that start.
  Future<bool> finishTimer(
    String id, {
    required int startedAtUtcMs,
    required NewTrackerEntry? entry,
  }) =>
      _db.transaction(() async {
        final cleared = await (_db.update(_db.trackers)
              ..where((t) => t.id.equals(id))
              ..where((t) => t.timerStartedAtUtc.equals(startedAtUtcMs)))
            .write(TrackersCompanion(
          timerStartedAtUtc: const Value(null),
          updatedAt: Value(_now()),
        ));
        if (cleared != 1) return false;
        if (entry != null) {
          final logged = await _db.trackerEntriesDao.insertEntry(entry);
          if (logged is! EntryLogged) {
            // A duration entry never carries the once-per-day flag, so this
            // is a caller's bug. Throwing rolls the clear back with it.
            throw StateError('a timer entry was refused: $logged');
          }
        }
        return true;
      });

  SimpleSelectStatement<$TrackersTable, TrackerRow> _byId(String id) =>
      _db.select(_db.trackers)
        ..where((t) => t.id.equals(id))
        ..where((t) => t.deletedAt.isNull());

  static Tracker _toTracker(TrackerRow row) {
    final start = row.timerStartedAtUtc;
    return Tracker(
      id: row.id,
      name: row.name,
      iconKey: row.iconKey,
      color: row.color,
      type: row.type,
      unit: row.unit,
      perTapValue: row.perTapValue,
      archived: row.archived,
      sortOrder: row.sortOrder,
      timerStartedAtUtc: start == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
    );
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  /// A write that matched nothing is a caller holding a stale id. Saying so
  /// beats reporting success for an archive that archived nothing.
  static void _expectOne(int written, String id) {
    if (written != 1) throw StateError('no tracker "$id"');
  }
}
