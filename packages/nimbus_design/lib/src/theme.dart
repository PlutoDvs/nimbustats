import 'package:flutter/material.dart';

import 'chart_palette.dart';
import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';

abstract final class NimbusTheme {
  static ThemeData light() =>
      _base(NimbusColors.lightScheme, NimbusColors.lightSemantics);

  static ThemeData dark() =>
      _base(NimbusColors.darkScheme, NimbusColors.darkSemantics);

  static ThemeData _base(ColorScheme scheme, NimbusSemanticColors semantics) {
    final text = NimbusTypography.textTheme(scheme);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      textTheme: text,
      // The chart palette is identical in both themes -- it is banded to clear
      // non-text contrast against either surface -- so it is registered here
      // rather than passed in per scheme like the semantic colours.
      extensions: <ThemeExtension<dynamic>>[
        semantics,
        NimbusChartColors.standard,
      ],
      // Standard rather than compact: dynamic type is a stated requirement and
      // compact density fights it from the first notch of enlargement.
      visualDensity: VisualDensity.standard,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: NimbusTokens.borderRadiusMd,
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: text.labelLarge,
        shape: const RoundedRectangleBorder(
          borderRadius: NimbusTokens.borderRadiusLg,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize:
              const Size(NimbusTokens.minTapTarget, NimbusTokens.minTapTarget),
          shape: const RoundedRectangleBorder(
            borderRadius: NimbusTokens.borderRadiusMd,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: NimbusTokens.space2,
      ),
      cardTheme: const CardThemeData(
        elevation: NimbusTokens.elevationCard,
        shape: RoundedRectangleBorder(
          borderRadius: NimbusTokens.borderRadiusMd,
        ),
      ),
    );
  }
}
