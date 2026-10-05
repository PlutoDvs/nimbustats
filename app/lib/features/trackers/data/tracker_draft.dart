import 'package:nimbus_domain/nimbus_domain.dart';

/// A tracker about to be created: what the editor sheet and the presets hand
/// to `TrackerRepository.create`.
final class TrackerDraft {
  const TrackerDraft({
    required this.name,
    required this.iconKey,
    required this.color,
    required this.type,
    this.unit,
    this.perTapValue,
  });

  final String name;
  final String iconKey;
  final int color;
  final TrackerType type;
  final String? unit;
  final double? perTapValue;
}
