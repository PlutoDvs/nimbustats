import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:sqlite3/common.dart' show SqlExtendedError, SqliteException;

import '../database/app_database.dart';

/// An entry as the repository hands it over for insertion. [oncePerDay] is
/// true for a boolean tracker's entries; the repository sets it.
typedef NewTrackerEntry = ({
  String id,
  String trackerId,
  double value,
  DateTime occurredAtUtc,
  DateKey localDateKey,
  String? note,
  bool oncePerDay,

  /// The device's UTC offset when the entry was logged, in minutes.
  int tzOffsetMinutes,
});

/// A keyset cursor into one tracker's history: the last entry a page returned.
typedef TrackerEntryCursorRow = ({DateTime occurredAtUtc, String id});

/// Tracker entries: one row per increment, never a daily total.
class TrackerEntriesDao {
  TrackerEntriesDao(this._db);

  final AppDatabase _db;

  /// Inserts [entry], or reports that its day already holds a live "done".
  ///
  /// The once-per-day index does the deciding, not a read before the write. A
  /// read first would let two fast taps both see "not done" and both write.
  Future<LogResult> insertEntry(NewTrackerEntry entry) async {
    final now = _now();
    try {
      await _db.into(_db.trackerEntries).insert(
            TrackerEntriesCompanion.insert(
              id: entry.id,
              trackerId: entry.trackerId,
              value: entry.value,
              occurredAtUtc: entry.occurredAtUtc.millisecondsSinceEpoch,
              localDateKey: entry.localDateKey,
              note: Value(entry.note),
              oncePerDay: Value(entry.oncePerDay),
              tzOffsetMinutes: Value(entry.tzOffsetMinutes),
              createdAt: now,
              updatedAt: now,
            ),
          );
    } on Object catch (error) {
      if (_isOncePerDayViolation(error)) return const AlreadyDoneToday();
      rethrow;
    }
    final logged = await byId(entry.id);
    if (logged == null) {
      // A row that vanishes between insert and read did not commit, and
      // returning a fabricated entry would let the UI undo something that
      // does not exist.
      throw StateError('tracker entry ${entry.id} was not persisted');
    }
    return EntryLogged(logged);
  }

  /// A live entry, or null.
  Future<TrackerEntry?> byId(String id) async {
    final row = await (_db.select(_db.trackerEntries)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .getSingleOrNull();
    return row == null ? null : _toEntry(row);
  }

  /// Rewrites an entry's value, time, day and note, and its offset when
  /// [tzOffsetMinutes] is given. Null leaves the stored offset as it is:
  /// editing a note after a flight must not move the entry's hour.
  ///
  /// Returns [DayWrite.dayAlreadyDone], writing nothing, when the edit would
  /// put a second live "done" on one day.
  Future<DayWrite> updateEntry(
    String id, {
    required double value,
    required DateTime occurredAtUtc,
    required DateKey localDateKey,
    required String? note,
    required int? tzOffsetMinutes,
  }) async {
    try {
      final written = await (_db.update(_db.trackerEntries)
            ..where((t) => t.id.equals(id))
            ..where((t) => t.deletedAt.isNull()))
          .write(TrackerEntriesCompanion(
        value: Value(value),
        occurredAtUtc: Value(occurredAtUtc.millisecondsSinceEpoch),
        localDateKey: Value(localDateKey),
        note: Value(note),
        tzOffsetMinutes: tzOffsetMinutes == null
            ? const Value.absent()
            : Value(tzOffsetMinutes),
        updatedAt: Value(_now()),
      ));
      _expectOne(written, id);
      return DayWrite.written;
    } on Object catch (error) {
      if (_isOncePerDayViolation(error)) return DayWrite.dayAlreadyDone;
      rethrow;
    }
  }

  Future<void> softDelete(String id) async {
    final now = _now();
    final written = await (_db.update(_db.trackerEntries)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .write(TrackerEntriesCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
    _expectOne(written, id);
  }

  /// Soft-deletes [trackerId]'s live entries on [day] and returns their ids,
  /// so an undo restores exactly these. This is a boolean tracker's "not done
  /// any more".
  Future<List<String>> softDeleteOn(String trackerId, DateKey day) =>
      _db.transaction(() async {
        final rows = await (_db.select(_db.trackerEntries)
              ..where((t) => t.trackerId.equals(trackerId))
              ..where((t) => t.localDateKey.equals(day.value))
              ..where((t) => t.deletedAt.isNull()))
            .get();
        final ids = [for (final row in rows) row.id];
        if (ids.isEmpty) return ids;
        final now = _now();
        await (_db.update(_db.trackerEntries)..where((t) => t.id.isIn(ids)))
            .write(TrackerEntriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ));
        return ids;
      });

  /// The undo behind a delete: makes [ids] live again, all of them or none.
  ///
  /// Returns [DayWrite.dayAlreadyDone] when one of them would be a second live
  /// "done" on its day, because the user marked the day done again meanwhile.
  Future<DayWrite> restore(List<String> ids) async {
    try {
      await _db.transaction(() async {
        final now = _now();
        for (final id in ids) {
          final written = await (_db.update(_db.trackerEntries)
                ..where((t) => t.id.equals(id)))
              .write(TrackerEntriesCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ));
          _expectOne(written, id);
        }
      });
      return DayWrite.written;
    } on Object catch (error) {
      if (_isOncePerDayViolation(error)) return DayWrite.dayAlreadyDone;
      rethrow;
    }
  }

  /// Every tracker's total for [day]: one GROUP BY over one day, keyed by
  /// tracker id.
  ///
  /// This is the brief's "today's total from a DAO count", and the only
  /// aggregate in 4a. Anything with a range or another dimension waits for 4b
  /// and goes through `QuerySpec`.
  Stream<Map<String, double>> watchDayTotals(DateKey day) {
    final (:query, :total) = _dayTotals(day);
    return query.watch().map((rows) => _byTracker(rows, total));
  }

  /// [watchDayTotals], read once, for a caller that needs the number now --
  /// the snackbar after a tap. A subscription opened for one value would have
  /// to be cancelled, and its first value arrives on a timer rather than with
  /// the query.
  Future<Map<String, double>> dayTotals(DateKey day) async {
    final (:query, :total) = _dayTotals(day);
    return _byTracker(await query.get(), total);
  }

  Map<String, double> _byTracker(
          List<TypedResult> rows, Expression<double> total) =>
      {
        for (final row in rows)
          row.read(_db.trackerEntries.trackerId)!: row.read(total) ?? 0,
      };

  /// [watchDayTotals]'s statement, so a test can assert its plan.
  JoinedSelectStatement<$TrackerEntriesTable, TrackerEntryRow> dayTotalsQuery(
          DateKey day) =>
      _dayTotals(day).query;

  ({
    JoinedSelectStatement<$TrackerEntriesTable, TrackerEntryRow> query,
    Expression<double> total,
  }) _dayTotals(DateKey day) {
    final entries = _db.trackerEntries;
    final total = entries.value.sum();
    final query = _db.selectOnly(entries)
      ..addColumns([entries.trackerId, total])
      ..where(entries.localDateKey.equals(day.value) &
          entries.deletedAt.isNull())
      ..groupBy([entries.trackerId]);
    return (query: query, total: total);
  }

  /// One tracker's live entries, newest first, after [after].
  ///
  /// Keyset over `(occurred_at_utc DESC, id DESC)`, like the transaction list,
  /// and for the same reasons. Offset pages re-count skipped rows, and they
  /// repeat or drop rows when a write lands between two fetches. On a detail
  /// screen with a quick-log button, that is the normal case.
  ///
  /// Exposed so a test can assert the plan walks
  /// `idx_tracker_entries_history`.
  SimpleSelectStatement<$TrackerEntriesTable, TrackerEntryRow> historyQuery(
    String trackerId, {
    TrackerEntryCursorRow? after,
    int limit = 40,
  }) {
    final query = _db.select(_db.trackerEntries)
      ..where((t) => t.trackerId.equals(trackerId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.occurredAtUtc),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);
    if (after != null) {
      final at = after.occurredAtUtc.millisecondsSinceEpoch;
      query.where((t) =>
          t.occurredAtUtc.isSmallerThanValue(at) |
          (t.occurredAtUtc.equals(at) & t.id.isSmallerThanValue(after.id)));
    }
    return query;
  }

  Future<List<TrackerEntry>> pageAfter(
    String trackerId, {
    TrackerEntryCursorRow? after,
    int limit = 40,
  }) async =>
      [
        for (final row in await historyQuery(trackerId,
                after: after, limit: limit)
            .get())
          _toEntry(row),
      ];

  /// Fires after any write to tracker entries, so a loaded history knows to
  /// reload.
  Stream<void> changes() => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.trackerEntries))
      .map((_) {});

  static TrackerEntry _toEntry(TrackerEntryRow row) => TrackerEntry(
        id: row.id,
        trackerId: row.trackerId,
        value: row.value,
        occurredAtUtc:
            DateTime.fromMillisecondsSinceEpoch(row.occurredAtUtc, isUtc: true),
        localDateKey: row.localDateKey,
        note: row.note,
      );

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  static void _expectOne(int written, String id) {
    if (written != 1) throw StateError('no tracker entry "$id"');
  }
}

/// The once-per-day index refusing a write.
///
/// It is the only unique index on tracker_entries. The primary key's violation
/// has its own code (SQLITE_CONSTRAINT_PRIMARYKEY), so SQLITE_CONSTRAINT_UNIQUE
/// alone identifies this index.
///
/// This matches the [SqliteException] that `AppDatabase.openAtPath` and
/// `openInMemory` throw, because both run SQLite on the calling isolate. A
/// database moved to a background isolate throws drift's remote wrapper
/// instead, and this must then unwrap it -- or a double-tap on "done" turns
/// into a crash. Moving the database means extending this match first.
bool _isOncePerDayViolation(Object error) => switch (error) {
      SqliteException(:final extendedResultCode) =>
        extendedResultCode == SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE,
      _ => false,
    };
