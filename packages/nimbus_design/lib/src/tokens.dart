import 'package:flutter/widgets.dart';

/// Single source of truth for spacing, radii, and colour.
///
/// These are placeholders until the real token sheet lands; the point of naming
/// them now is that every screen references tokens rather than literals, so
/// swapping in the real values is one file.
abstract final class NimbusTokens {
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space6 = 24.0;
  static const space8 = 32.0;

  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 20.0;

  static const seed = Color(0xFF2E7D64);

  /// Minimum tap target. Primary actions sit in the bottom third of the screen
  /// so they stay within one-handed reach.
  static const minTapTarget = 48.0;
}
