import 'package:meta/meta.dart';

import '../calendar/date_key.dart';

/// One logged increment of a tracker.
///
/// [value]'s meaning depends on the tracker's type (see `TrackerValues`).
/// [localDateKey] is the local day the entry was written on, not one derived
/// from [occurredAtUtc] on read: an entry logged before a flight keeps its day.
@immutable
final class TrackerEntry {
  const TrackerEntry({
    required this.id,
    required this.trackerId,
    required this.value,
    required this.occurredAtUtc,
    required this.localDateKey,
    this.note,
  });

  final String id;
  final String trackerId;
  final double value;
  final DateTime occurredAtUtc;
  final DateKey localDateKey;
  final String? note;

  @override
  bool operator ==(Object other) =>
      other is TrackerEntry &&
      other.id == id &&
      other.trackerId == trackerId &&
      other.value == value &&
      other.occurredAtUtc == occurredAtUtc &&
      other.localDateKey == localDateKey &&
      other.note == note;

  @override
  int get hashCode =>
      Object.hash(id, trackerId, value, occurredAtUtc, localDateKey, note);

  @override
  String toString() => 'TrackerEntry($id, $trackerId, $value, $localDateKey)';
}
