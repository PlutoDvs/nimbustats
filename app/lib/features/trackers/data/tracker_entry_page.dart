import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

/// Where the last history page stopped: a position in the ordering, not a
/// row offset, so it stays valid when entries are logged around it.
final class TrackerEntryCursor {
  const TrackerEntryCursor({required this.occurredAtUtc, required this.id});

  factory TrackerEntryCursor.of(TrackerEntry entry) =>
      TrackerEntryCursor(occurredAtUtc: entry.occurredAtUtc, id: entry.id);

  final DateTime occurredAtUtc;
  final String id;

  TrackerEntryCursorRow get row => (occurredAtUtc: occurredAtUtc, id: id);

  @override
  bool operator ==(Object other) =>
      other is TrackerEntryCursor &&
      other.occurredAtUtc == occurredAtUtc &&
      other.id == id;

  @override
  int get hashCode => Object.hash(occurredAtUtc, id);

  @override
  String toString() => 'TrackerEntryCursor($occurredAtUtc, $id)';
}

/// One page of a tracker's history.
final class TrackerEntryPage {
  const TrackerEntryPage({required this.items, required this.cursor});

  final List<TrackerEntry> items;

  /// Where to continue from, or null when this was the last page.
  final TrackerEntryCursor? cursor;

  bool get hasMore => cursor != null;
}
