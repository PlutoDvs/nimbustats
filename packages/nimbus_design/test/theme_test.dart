import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_design/nimbus_design.dart';

/// WCAG 2.1 relative luminance. Written out rather than pulled from a package
/// so the contrast assertions below depend on nothing that can drift.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('tokens', () {
    test('the spacing scale is strictly ascending', () {
      const scale = [
        NimbusTokens.space1,
        NimbusTokens.space2,
        NimbusTokens.space3,
        NimbusTokens.space4,
        NimbusTokens.space6,
        NimbusTokens.space8,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]),
            reason: 'spacing step $i must be larger than the one before it');
      }
    });

    test('the minimum tap target meets the platform accessibility floor', () {
      // Material and the Android accessibility guidelines both put this at 48.
      // Anything smaller is a defect on a phone held one-handed.
      expect(NimbusTokens.minTapTarget, greaterThanOrEqualTo(48.0));
      expect(NimbusTokens.chipHeight, greaterThanOrEqualTo(44.0));
    });

    test('tree indentation is capped so a six-level tree still fits', () {
      // Screen contract D4: indentation must degrade rather than push a deep
      // node off the side of the screen.
      expect(NimbusTokens.maxTreeIndentDepth, lessThanOrEqualTo(4));
      expect(
        NimbusTokens.indentPerLevel * NimbusTokens.maxTreeIndentDepth,
        lessThanOrEqualTo(64.0),
      );
    });
  });

  group('contrast', () {
    // Screen contract 1.4: contrast is part of the definition of done for every
    // screen, so it is asserted once here rather than eyeballed per screen.
    void assertReadable(String name, Color foreground, Color background) {
      expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5),
          reason: '$name must meet WCAG AA against its surface');
    }

    void assertSchemeReadable(ColorScheme scheme, NimbusSemanticColors s) {
      assertReadable('expense', s.expense, scheme.surface);
      assertReadable('income', s.income, scheme.surface);
      assertReadable('necessityNeeded', s.necessityNeeded, scheme.surface);
      assertReadable('necessityOptional', s.necessityOptional, scheme.surface);
      assertReadable(
          'necessityAvoidable', s.necessityAvoidable, scheme.surface);
      assertReadable('satisfactionGlad', s.satisfactionGlad, scheme.surface);
      assertReadable(
          'satisfactionNeutral', s.satisfactionNeutral, scheme.surface);
      assertReadable(
          'satisfactionRegret', s.satisfactionRegret, scheme.surface);
      assertReadable('onSurface', scheme.onSurface, scheme.surface);
    }

    test('light semantic colours are readable on the light surface', () {
      assertSchemeReadable(NimbusColors.lightScheme, NimbusColors.lightSemantics);
    });

    test('dark semantic colours are readable on the dark surface', () {
      assertSchemeReadable(NimbusColors.darkScheme, NimbusColors.darkSemantics);
    });

    test('expense and income differ by more than hue alone', () {
      // Screen contract D6: direction must be distinguishable without relying
      // on colour. The colours still have to differ for users who do see them,
      // but the rows additionally carry a sign or arrow -- asserted where those
      // widgets are built, not here.
      final light = NimbusColors.lightSemantics;
      expect(_contrast(light.expense, light.income), greaterThan(1.2),
          reason: 'expense and income must not be near-identical in value');
    });
  });

  group('theme', () {
    test('light and dark themes carry the semantic extension', () {
      expect(
        NimbusTheme.light().extension<NimbusSemanticColors>(),
        isNotNull,
        reason: 'screens read semantic colours through the extension',
      );
      expect(NimbusTheme.dark().extension<NimbusSemanticColors>(), isNotNull);
    });

    test('themes use Material 3 and the seeded scheme', () {
      final light = NimbusTheme.light();
      expect(light.useMaterial3, isTrue);
      expect(light.colorScheme.brightness, Brightness.light);
      expect(NimbusTheme.dark().colorScheme.brightness, Brightness.dark);
    });

    test('the type ramp is complete and ascending in the display sizes', () {
      final text = NimbusTheme.light().textTheme;
      for (final style in [
        text.displaySmall,
        text.headlineMedium,
        text.titleLarge,
        text.titleMedium,
        text.bodyLarge,
        text.bodyMedium,
        text.labelLarge,
        text.labelSmall,
      ]) {
        expect(style, isNotNull);
        expect(style!.fontSize, isNotNull);
      }
      expect(text.displaySmall!.fontSize!,
          greaterThan(text.headlineMedium!.fontSize!));
      expect(text.headlineMedium!.fontSize!,
          greaterThan(text.titleLarge!.fontSize!));
      expect(text.bodyLarge!.fontSize!, greaterThan(text.labelSmall!.fontSize!));
    });

    test('the font fallback stack can render Persian', () {
      // No font is bundled, so Persian rendering depends on the platform
      // fallback list being present. Naming it explicitly is what keeps a
      // future refactor from silently dropping it and leaving Farsi users
      // looking at tofu.
      final fallback =
          NimbusTheme.light().textTheme.bodyMedium!.fontFamilyFallback;
      expect(fallback, isNotNull);
      expect(fallback, contains('Noto Naskh Arabic'));
    });

    test('the semantic extension resolves to the palette it was built from', () {
      expect(
        NimbusTheme.dark().extension<NimbusSemanticColors>()!.expense,
        NimbusColors.darkSemantics.expense,
      );
    });

    testWidgets('NimbusSemanticColors.of resolves from a BuildContext',
        (tester) async {
      // Every screen calls this; a null return would otherwise show up as a
      // crash deep inside a widget tree.
      late NimbusSemanticColors resolved;
      await tester.pumpWidget(MaterialApp(
        theme: NimbusTheme.light(),
        home: Builder(builder: (context) {
          resolved = NimbusSemanticColors.of(context);
          return const SizedBox.shrink();
        }),
      ));
      expect(resolved.income, NimbusColors.lightSemantics.income);
    });

    testWidgets('a theme built without NimbusTheme fails loudly', (tester) async {
      // Not a fallback: a missing extension means the app was built without
      // NimbusTheme, and returning defaults would hide that until a designer
      // noticed the wrong red in a screenshot.
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Builder(builder: (context) {
          expect(() => NimbusSemanticColors.of(context), throwsStateError);
          return const SizedBox.shrink();
        }),
      ));
    });
  });
}
