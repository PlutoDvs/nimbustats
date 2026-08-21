import 'package:flutter/widgets.dart';

/// Spacing, radii, motion, and the dimensional floors every screen obeys.
///
/// PROVISIONAL. These values are derived from the screen contract's constraints
/// rather than from a Claude Design token sheet, which does not exist yet. They
/// are named rather than inlined precisely so that swapping in a real sheet is
/// an edit to this file and `colors.dart`, not a sweep across every screen.
abstract final class NimbusTokens {
  // A 4pt base scale. The gaps (no space5, no space7) are deliberate: a scale
  // with every integer step is not a scale, it is a licence to eyeball.
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space6 = 24.0;
  static const space8 = 32.0;

  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 20.0;

  static const BorderRadius borderRadiusSm =
      BorderRadius.all(Radius.circular(radiusSm));
  static const BorderRadius borderRadiusMd =
      BorderRadius.all(Radius.circular(radiusMd));
  static const BorderRadius borderRadiusLg =
      BorderRadius.all(Radius.circular(radiusLg));

  /// Minimum tap target. Primary actions sit in the bottom third of the screen
  /// so they stay within one-handed reach.
  static const minTapTarget = 48.0;

  /// Category chips in the add flow are tapped more than anything else in the
  /// app, so they get a target comfortably above the floor rather than at it.
  static const chipHeight = 44.0;

  static const elevationCard = 0.0;
  static const elevationSheet = 3.0;

  /// Screen contract D4: a six-level category tree must stay legible. Indent
  /// stops growing after this many levels and the breadcrumb carries the rest.
  static const maxTreeIndentDepth = 4;
  static const indentPerLevel = 16.0;

  /// Motion. Fast is for state the user caused directly (a chip selecting);
  /// normal is for surfaces arriving.
  static const durationFast = Duration(milliseconds: 120);
  static const durationNormal = Duration(milliseconds: 200);
  static const curveStandard = Curves.easeOutCubic;
}
