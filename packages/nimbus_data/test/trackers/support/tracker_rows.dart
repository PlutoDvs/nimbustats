import 'package:drift/drift.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

/// 2026-10-05 09:00 UTC, the instant most rows here are logged at.
final morning = DateTime.utc(2026, 10, 5, 9);
const today = DateKey(20261005);

NewTracker newTracker(
  String id,
  TrackerType type, {
  String? unit,
  double? perTapValue,
}) =>
    (
      id: id,
      name: id,
      iconKey: 'tag',
      color: 0xFF1565C0,
      type: type,
      unit: unit,
      perTapValue: perTapValue,
    );

NewTrackerEntry newEntry(
  String id,
  String trackerId, {
  double value = 1,
  DateTime? at,
  DateKey day = today,
  String? note,
  bool oncePerDay = false,
  int tzOffsetMinutes = 210,
}) =>
    (
      id: id,
      trackerId: trackerId,
      value: value,
      occurredAtUtc: at ?? morning,
      localDateKey: day,
      note: note,
      oncePerDay: oncePerDay,
      tzOffsetMinutes: tzOffsetMinutes,
    );

/// The offset stored on [entryId], read in SQL: no domain type carries it.
Future<int> offsetOf(AppDatabase db, String entryId) async {
  final row = await db.customSelect(
    'SELECT tz_offset_minutes AS o FROM tracker_entries WHERE id = ?',
    variables: [Variable.withString(entryId)],
  ).getSingle();
  return row.read<int>('o');
}

/// Live rows for [trackerId], counted in SQL so the test does not lean on the
/// DAO it is checking.
Future<int> liveEntries(AppDatabase db, String trackerId) async {
  final row = await db.customSelect(
    'SELECT COUNT(*) AS n FROM tracker_entries '
    'WHERE tracker_id = ? AND deleted_at IS NULL',
    variables: [Variable.withString(trackerId)],
  ).getSingle();
  return row.read<int>('n');
}

/// The query plan of [query], joined into one string.
Future<String> planOf(
    AppDatabase db, Query<HasResultSet, dynamic> query) async {
  final compiled = query.constructQuery();
  final rows = await db.customSelect(
    'EXPLAIN QUERY PLAN ${compiled.sql}',
    variables: compiled.boundVariables
        .map<Variable<Object>>(
            (v) => v is int ? Variable<int>(v) : Variable<String>('$v'))
        .toList(),
  ).get();
  return rows.map((r) => r.read<String>('detail')).join(' | ');
}
