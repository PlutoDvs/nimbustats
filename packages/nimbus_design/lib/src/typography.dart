import 'package:flutter/material.dart';

/// The type ramp.
///
/// PROVISIONAL sizes, derived from the screen contract's density requirements.
/// No font file is bundled: Persian renders through the platform fallback
/// stack, which is named explicitly below so a refactor cannot silently drop it
/// and leave Farsi users looking at tofu. Bundling Vazirmatn is the obvious
/// upgrade, and is deliberately deferred to whichever phase has a real token
/// sheet to bundle it alongside.
abstract final class NimbusTypography {
  static const fontFamilyFallback = <String>[
    'Noto Naskh Arabic',
    'Noto Sans Arabic',
    'Roboto',
  ];

  static TextTheme textTheme(ColorScheme scheme) {
    TextStyle style(double size, FontWeight weight, double height) => TextStyle(
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: scheme.onSurface,
          fontFamilyFallback: fontFamilyFallback,
        );

    return TextTheme(
      // displaySmall is reserved for the one number a screen is actually
      // about: the amount on the add screen, the total on the list header.
      displaySmall: style(36, FontWeight.w600, 1.15),
      headlineMedium: style(28, FontWeight.w600, 1.2),
      titleLarge: style(22, FontWeight.w600, 1.25),
      titleMedium: style(16, FontWeight.w600, 1.3),
      bodyLarge: style(16, FontWeight.w400, 1.4),
      bodyMedium: style(14, FontWeight.w400, 1.4),
      labelLarge: style(14, FontWeight.w600, 1.2),
      labelMedium: style(12, FontWeight.w500, 1.2),
      labelSmall: style(11, FontWeight.w500, 1.2),
    );
  }
}
