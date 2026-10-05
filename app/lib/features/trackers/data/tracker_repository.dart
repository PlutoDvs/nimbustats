import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import 'tracker_clock.dart';
import 'tracker_draft.dart';
import 'tracker_entry_page.dart';

/// The single write path for trackers and their entries.
///
/// Every entry in this app is written here: the tab's one-tap buttons, the
/// detail screen, and Phase 6's home-screen widget, which writes through this
/// and nothing else. That keeps three things in one place instead of three:
/// - the per-type default value;
/// - the boolean once-per-day flag;
/// - the local date key and the UTC offset, both taken at write time.
final class TrackerRepository {
  /// Positional to keep the DAOs private, as `TransactionRepository` does.
  const TrackerRepository(
      this._trackers, this._entries, this._engine, this._clock);

  final TrackersDao _trackers;
  final TrackerEntriesDao _entries;

  /// Every total this repository reads comes from Phase 3's engine. The DAOs
  /// hold no aggregate of their own.
  final AnalyticsEngine _engine;
  final TrackerClock _clock;

  // --- reads ---------------------------------------------------------------

  /// Live, unarchived trackers in the user's order: the tab.
  Stream<List<Tracker>> watchTrackers() => _trackers.watchLive(archived: false);

  /// Live archived trackers: the manager's "Archived" section.
  Stream<List<Tracker>> watchArchived() => _trackers.watchLive(archived: true);

  Stream<Tracker?> watchTracker(String id) => _trackers.watchById(id);

  /// One tracker's total for [day], read once: the snackbar after a tap.
  Future<double> totalOn(String trackerId, DateKey day) async =>
      (await _engine.runTracker(TrackerQueries.dayTotal(trackerId, day))).sum;

  /// Fires after any entry write, so a loaded history can reload.
  Stream<void> entryChanges() => _entries.changes();

  DateKey today() => _clock.today();

  /// One history page, newest first.
  ///
  /// Asks for one row more than requested. That row is never returned; it is
  /// how this knows whether a next page exists, rather than guessing from
  /// `items.length == limit`, which is wrong exactly when the total is a
  /// multiple of the page size.
  Future<TrackerEntryPage> entriesPage(
    String trackerId, {
    TrackerEntryCursor? after,
    int limit = 40,
  }) async {
    final rows =
        await _entries.pageAfter(trackerId, after: after?.row, limit: limit + 1);
    final hasMore = rows.length > limit;
    final items = hasMore ? rows.take(limit).toList() : rows;
    return TrackerEntryPage(
      items: items,
      cursor: hasMore ? TrackerEntryCursor.of(items.last) : null,
    );
  }

  // --- trackers -------------------------------------------------------------

  Future<Tracker> create(TrackerDraft draft) async =>
      (await createAll([draft])).single;

  /// Creates [drafts] in order, after every existing tracker, in one
  /// transaction.
  Future<List<Tracker>> createAll(List<TrackerDraft> drafts) async {
    final rows = [for (final draft in drafts) _validNew(draft)];
    await _trackers.insertAll(rows);
    return [for (final row in rows) await _require(row.id)];
  }

  /// Rewrites a tracker's name, look and -- for a quantity -- its unit and
  /// per-tap amount. Its type cannot change (see [TrackerType]).
  Future<void> update(
    String id, {
    required String name,
    required String iconKey,
    required int color,
    String? unit,
    double? perTapValue,
  }) async {
    final tracker = await _require(id);
    final cleanUnit = _validUnit(unit);
    TrackerValues.checkDefinition(tracker.type,
        unit: cleanUnit, perTapValue: perTapValue);
    await _trackers.updateTracker(id,
        name: _validName(name),
        iconKey: iconKey,
        color: color,
        unit: cleanUnit,
        perTapValue: perTapValue);
  }

  Future<void> archive(String id) => _trackers.setArchived(id, true);

  Future<void> unarchive(String id) => _trackers.setArchived(id, false);

  Future<void> reorder(List<String> ids) => _trackers.reorder(ids);

  // --- entries --------------------------------------------------------------

  /// Logs one entry: by default what one tap logs (1, or the per-tap amount).
  ///
  /// [at] defaults to now. Returns [AlreadyDoneToday] instead of writing when
  /// a boolean tracker already holds that day. Throws [ArgumentError] for a
  /// value that does not fit the type, or for a duration tracker without a
  /// value -- a duration's taps go through [startTimer] and [stopTimer].
  Future<LogResult> logEntry(
    String trackerId, {
    double? value,
    DateTime? at,
    String? note,
  }) async {
    final tracker = await _require(trackerId);
    final amount = value ??
        TrackerValues.perTap(tracker.type, perTapValue: tracker.perTapValue) ??
        (throw ArgumentError.value(value, 'value',
            'a duration tracker logs through its timer or addDuration'));
    if (!TrackerValues.isValid(tracker.type, amount)) {
      throw ArgumentError.value(
          amount, 'value', 'not a valid ${tracker.type.name} entry');
    }
    final atUtc = (at ?? _clock.nowUtc()).toUtc();
    return _entries.insertEntry((
      id: Ids.newId(),
      trackerId: trackerId,
      value: amount,
      occurredAtUtc: atUtc,
      // The local date where the device is now, not the UTC one. A glass of
      // water at 01:00 in Tehran belongs to that day even though it is still
      // yesterday in UTC.
      localDateKey: _clock.localDateOf(atUtc),
      tzOffsetMinutes: _clock.offsetMinutesOf(atUtc),
      note: _validNote(note),
      oncePerDay: tracker.type == TrackerType.boolean,
    ));
  }

  /// Takes back today's "done" on a boolean tracker. Returns what to restore
  /// for an undo.
  Future<List<String>> clearToday(String trackerId) =>
      _entries.softDeleteOn(trackerId, _clock.today());

  Future<TimerStartResult> startTimer(String trackerId) async {
    final tracker = await _require(trackerId);
    _expectType(tracker, TrackerType.duration);
    final startMs = _clock.nowUtc().millisecondsSinceEpoch;
    final started = await _trackers.startTimer(trackerId, startMs);
    return started
        ? TimerStarted(RunningTimer(
            DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true)))
        : const TimerAlreadyRunning();
  }

  /// Stops the running timer and logs the session.
  ///
  /// The entry is stamped at the start (a night's sleep belongs to the evening
  /// it began) and holds whole seconds. A session under a second is discarded:
  /// the timer is cleared and nothing is logged.
  Future<TimerStopResult> stopTimer(String trackerId) async {
    final tracker = await _require(trackerId);
    _expectType(tracker, TrackerType.duration);
    final timer = tracker.runningTimer;
    if (timer == null) return const TimerNotRunning();

    final startMs = timer.startedAtUtc.millisecondsSinceEpoch;
    final elapsed = timer.elapsed(_clock.nowUtc());
    if (elapsed.inSeconds < 1) {
      final cleared = await _trackers.finishTimer(trackerId,
          startedAtUtcMs: startMs, entry: null);
      return cleared ? const TimerDiscarded() : const TimerNotRunning();
    }

    final entryId = Ids.newId();
    final finished = await _trackers.finishTimer(
      trackerId,
      startedAtUtcMs: startMs,
      entry: (
        id: entryId,
        trackerId: trackerId,
        value: TrackerValues.secondsOf(elapsed),
        occurredAtUtc: timer.startedAtUtc,
        localDateKey: _clock.localDateOf(timer.startedAtUtc),
        tzOffsetMinutes: _clock.offsetMinutesOf(timer.startedAtUtc),
        note: null,
        oncePerDay: false,
      ),
    );
    // Lost a race with another stop: that one logged the session.
    if (!finished) return const TimerNotRunning();
    final logged = await _entries.byId(entryId);
    if (logged == null) {
      throw StateError('timer entry $entryId was not persisted');
    }
    return TimerStopped(logged);
  }

  /// Logs a session the user forgot to time, ending now unless [startedAt]
  /// says when it began.
  Future<LogResult> addDuration(
    String trackerId,
    Duration duration, {
    DateTime? startedAt,
  }) async {
    final tracker = await _require(trackerId);
    _expectType(tracker, TrackerType.duration);
    final seconds = TrackerValues.secondsOf(duration);
    if (!TrackerValues.isValid(TrackerType.duration, seconds)) {
      throw ArgumentError.value(
          duration, 'duration', 'a session lasts at least a second');
    }
    final start = (startedAt ?? _clock.nowUtc().subtract(duration)).toUtc();
    return _entries.insertEntry((
      id: Ids.newId(),
      trackerId: trackerId,
      value: seconds,
      occurredAtUtc: start,
      localDateKey: _clock.localDateOf(start),
      tzOffsetMinutes: _clock.offsetMinutesOf(start),
      note: null,
      oncePerDay: false,
    ));
  }

  /// Writes an edited entry.
  ///
  /// The local date and the offset are recomputed only when the time changed.
  /// Editing a note after a flight must not move the entry to another day or
  /// hour, while moving the time is a new write and takes the device's date
  /// and offset now.
  Future<DayWrite> updateEntry(TrackerEntry edited) async {
    final current = await _entries.byId(edited.id);
    if (current == null) throw StateError('no tracker entry "${edited.id}"');
    final tracker = await _require(current.trackerId);
    if (!TrackerValues.isValid(tracker.type, edited.value)) {
      throw ArgumentError.value(
          edited.value, 'value', 'not a valid ${tracker.type.name} entry');
    }
    final atUtc = edited.occurredAtUtc.toUtc();
    return _entries.updateEntry(
      edited.id,
      value: edited.value,
      occurredAtUtc: atUtc,
      localDateKey: atUtc == current.occurredAtUtc
          ? current.localDateKey
          : _clock.localDateOf(atUtc),
      tzOffsetMinutes: atUtc == current.occurredAtUtc
          ? null
          : _clock.offsetMinutesOf(atUtc),
      note: _validNote(edited.note),
    );
  }

  Future<void> deleteEntry(String id) => _entries.softDelete(id);

  Future<DayWrite> restoreEntries(List<String> ids) => _entries.restore(ids);

  // --- validation -----------------------------------------------------------

  NewTracker _validNew(TrackerDraft draft) {
    final unit = _validUnit(draft.unit);
    TrackerValues.checkDefinition(draft.type,
        unit: unit, perTapValue: draft.perTapValue);
    return (
      id: Ids.newId(),
      name: _validName(draft.name),
      iconKey: draft.iconKey,
      color: draft.color,
      type: draft.type,
      unit: unit,
      perTapValue: draft.perTapValue,
    );
  }

  Future<Tracker> _require(String id) async =>
      await _trackers.byId(id) ?? (throw StateError('no tracker "$id"'));

  static void _expectType(Tracker tracker, TrackerType type) {
    if (tracker.type != type) {
      throw ArgumentError.value(tracker.type, 'tracker.type',
          'expected a ${type.name} tracker');
    }
  }

  static String _validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'a tracker needs a name');
    }
    return trimmed;
  }

  static String? _validUnit(String? unit) {
    final trimmed = unit?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _validNote(String? note) {
    final trimmed = note?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
