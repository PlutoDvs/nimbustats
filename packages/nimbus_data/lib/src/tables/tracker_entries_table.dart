import 'package:drift/drift.dart';

import '../database/columns.dart';
import '../database/converters.dart';
import 'trackers_table.dart';

/// One logged increment.
///
/// Five cigarettes are five rows with five timestamps, never a daily total:
/// that is what makes time-of-day patterns free in 4b, and collapsing to a
/// total would be a one-way loss.
///
/// The four indexes:
/// - `idx_tracker_entries_day` leads with the date, because its main reader
///   is today's totals -- every tracker's entries for one day, grouped by
///   tracker.
/// - `idx_tracker_entries_history` serves the detail screen's newest-first
///   keyset pages.
/// - `idx_tracker_entries_once_per_day` is the boolean rule: one live "done"
///   per tracker per day, so a fast double-tap cannot log it twice.
/// - `idx_tracker_entries_tracker_day` serves every engine query (4b): one
///   tracker, or a short list of them, over a range of days. Tracker first,
///   because every such query names its trackers.
///
/// A partial index can only test this table's own columns, and the type lives
/// on `trackers`. So the repository copies "this tracker is boolean" onto each
/// entry as [oncePerDay]. The type is fixed at creation, so the copy cannot
/// drift from it.
@DataClassName('TrackerEntryRow')
@TableIndex(
    name: 'idx_tracker_entries_day', columns: {#localDateKey, #trackerId})
@TableIndex(name: 'idx_tracker_entries_history', columns: {
  #trackerId,
  IndexedColumn(#occurredAtUtc, orderBy: OrderingMode.desc),
  IndexedColumn(#id, orderBy: OrderingMode.desc),
})
@TableIndex(
    name: 'idx_tracker_entries_tracker_day',
    columns: {#trackerId, #localDateKey})
@TableIndex.sql('CREATE UNIQUE INDEX idx_tracker_entries_once_per_day '
    'ON tracker_entries (tracker_id, local_date_key) '
    'WHERE once_per_day = 1 AND deleted_at IS NULL')
class TrackerEntries extends Table with BaseColumns {
  TextColumn get trackerId => text().references(Trackers, #id)();

  /// What this entry logs: 1 for a counter or a boolean, the amount for a
  /// quantity, whole seconds for a duration.
  ///
  /// The one deliberate `double` in this project -- 2.5 litres is a real
  /// quantity. It is NOT a precedent for money, which is always `int` minor
  /// units (see `MoneyConverter`). A reader reaching for `real()` on an amount
  /// column should stop here.
  RealColumn get value => real()();

  IntColumn get occurredAtUtc => integer()();

  /// Local Gregorian yyyymmdd, computed when the entry is written from the
  /// device's local date at that moment. Never recomputed on read: an entry
  /// logged before a flight belongs to the day it was logged on.
  IntColumn get localDateKey => integer().map(const DateKeyConverter())();

  TextColumn get note => text().nullable()();

  /// The device's UTC offset when the entry was logged, in minutes: what turns
  /// [occurredAtUtc] back into the local hour the entry happened at.
  ///
  /// Stamped at write time like [localDateKey], and for the same reason: an
  /// entry logged before a flight keeps the hour it was logged at. It mirrors
  /// `transactions.tz_offset_minutes`, and the engine's hour-of-day and
  /// weekday buckets read both the same way.
  IntColumn get tzOffsetMinutes => integer().withDefault(const Constant(0))();

  /// True on a boolean tracker's entries; the once-per-day index tests it.
  BoolColumn get oncePerDay => boolean().withDefault(const Constant(false))();
}
