import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_design/nimbus_design.dart';

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  const palette = NimbusChartColors.standard;

  group('series colours', () {
    test('every colour is distinguishable from both surfaces', () {
      // WCAG 2.1 SC 1.4.11: a chart slice is a non-text graphical object, so
      // the bar is 3:1, not the 4.5:1 that theme_test.dart holds text to.
      // Asserting 4.5 here would force the palette pale enough to hurt.
      //
      // One palette serves both themes deliberately: these sit in a luminance
      // band that clears the bar against a near-white and a near-black surface
      // alike, which is cheaper to keep honest than two lists that drift.
      for (final (i, colour) in palette.series.indexed) {
        expect(_contrast(colour, NimbusColors.lightScheme.surface),
            greaterThanOrEqualTo(3.0),
            reason: 'series[$i] vanishes on the light surface');
        expect(_contrast(colour, NimbusColors.darkScheme.surface),
            greaterThanOrEqualTo(3.0),
            reason: 'series[$i] vanishes on the dark surface');
      }
    });

    test('no two series colours are the same', () {
      expect(palette.series.toSet(), hasLength(palette.series.length));
    });

    test('there are enough colours for a realistic breakdown', () {
      // A top-level category breakdown is the common case and rarely exceeds
      // this. Fewer colours would mean routine repeats in the default chart.
      expect(palette.series.length, greaterThanOrEqualTo(8));
    });
  });

  group('assignment', () {
    test('the same keys always get the same colours', () {
      // A category that changes colour between two openings of the same chart
      // reads as a different category.
      final first = palette.assign(['food', 'rent', 'travel']);
      final second = palette.assign(['food', 'rent', 'travel']);
      expect(first, second);
    });

    test('input order does not change the answer', () {
      // Buckets arrive ranked by amount, so the order changes whenever the
      // data does. Colour must not follow rank.
      expect(
        palette.assign(['travel', 'food', 'rent']),
        palette.assign(['rent', 'travel', 'food']),
      );
    });

    test('colours are distinct while there are enough of them', () {
      final keys = List.generate(palette.series.length, (i) => 'key$i');
      final assigned = palette.assign(keys);
      expect(assigned, hasLength(keys.length));
      expect(assigned.values.toSet(), hasLength(keys.length),
          reason: 'two adjacent slices sharing a colour is unreadable');
    });

    test('more keys than colours still assigns every key', () {
      final keys = List.generate(palette.series.length * 2 + 3, (i) => 'k$i');
      final assigned = palette.assign(keys);
      expect(assigned, hasLength(keys.length));
      expect(assigned.values.every(palette.series.contains), isTrue);
    });

    test('a duplicate key is not a second entry', () {
      expect(palette.assign(['a', 'b', 'a']), hasLength(2));
    });

    test('no keys is an empty map, not a crash', () {
      expect(palette.assign(const []), isEmpty);
    });
  });

  group('theme lookup', () {
    testWidgets('the palette is on the theme NimbusTheme builds',
        (tester) async {
      late NimbusChartColors found;
      await tester.pumpWidget(MaterialApp(
        theme: NimbusTheme.light(),
        home: Builder(builder: (context) {
          found = NimbusChartColors.of(context);
          return const SizedBox();
        }),
      ));
      expect(found.series, palette.series);
    });

    testWidgets('a theme without it throws rather than inventing colours',
        (tester) async {
      // Same rule NimbusSemanticColors follows: a missing extension means the
      // app was built without NimbusTheme, and quietly returning defaults
      // hides that until somebody notices the wrong colours in a screenshot.
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Builder(builder: (context) {
          expect(() => NimbusChartColors.of(context), throwsStateError);
          return const SizedBox();
        }),
      ));
    });
  });
}
