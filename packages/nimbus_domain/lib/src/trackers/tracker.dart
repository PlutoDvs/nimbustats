import 'package:meta/meta.dart';

import 'running_timer.dart';
import 'tracker_type.dart';

/// A tracker: what it is called, how it looks, what it counts.
///
/// [type] is fixed at creation (see [TrackerType]). [unit] and [perTapValue]
/// belong to quantity trackers only, and [timerStartedAtUtc] to duration
/// trackers only. The repository refuses any other combination when writing,
/// so this type does not re-check rows it is built from.
@immutable
final class Tracker {
  const Tracker({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.color,
    required this.type,
    this.unit,
    this.perTapValue,
    required this.archived,
    required this.sortOrder,
    this.timerStartedAtUtc,
  });

  final String id;
  final String name;

  /// A `nimbusIcons` key.
  final String iconKey;

  /// ARGB, as categories and payment methods store it.
  final int color;
  final TrackerType type;
  final String? unit;
  final double? perTapValue;
  final bool archived;
  final int sortOrder;

  /// The persisted start of a running timer, or null when none runs.
  final DateTime? timerStartedAtUtc;

  RunningTimer? get runningTimer {
    final start = timerStartedAtUtc;
    return start == null ? null : RunningTimer(start);
  }

  @override
  bool operator ==(Object other) =>
      other is Tracker &&
      other.id == id &&
      other.name == name &&
      other.iconKey == iconKey &&
      other.color == color &&
      other.type == type &&
      other.unit == unit &&
      other.perTapValue == perTapValue &&
      other.archived == archived &&
      other.sortOrder == sortOrder &&
      other.timerStartedAtUtc == timerStartedAtUtc;

  @override
  int get hashCode => Object.hash(id, name, iconKey, color, type, unit,
      perTapValue, archived, sortOrder, timerStartedAtUtc);

  @override
  String toString() => 'Tracker($id, $name, ${type.name})';
}
