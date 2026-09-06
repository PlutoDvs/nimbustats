import 'package:flutter/material.dart';

/// The categorical colours charts assign to buckets.
///
/// Separate from [ThemeExtension]s carrying domain meaning: expense and income
/// have a *meaning* that must not change, whereas a series colour only has to
/// stay distinct and stable. Mixing the two would invite someone to reach for
/// the expense red because a slice happened to want red.
///
/// One list serves both themes. The colours sit in a luminance band chosen so
/// each clears WCAG 2.1 SC 1.4.11's 3:1 non-text contrast against a near-white
/// and a near-black surface alike -- cheaper to keep honest than two lists that
/// drift apart, and asserted in `chart_palette_test.dart` against both schemes.
@immutable
final class NimbusChartColors extends ThemeExtension<NimbusChartColors> {
  const NimbusChartColors({required this.series});

  /// Eight hues, spaced around the wheel rather than picked by eye, so that
  /// adjacent slices differ in hue and not only in lightness -- which is what
  /// keeps them apart for a red-green colour-blind reader.
  static const standard = NimbusChartColors(series: <Color>[
    Color(0xFFD44F46),
    Color(0xFFB36A2A),
    Color(0xFF8D7B21),
    Color(0xFF218E45),
    Color(0xFF208986),
    Color(0xFF307ECD),
    Color(0xFF9461DA),
    Color(0xFFD240A2),
  ]);

  final List<Color> series;

  static NimbusChartColors of(BuildContext context) {
    final ext = Theme.of(context).extension<NimbusChartColors>();
    if (ext == null) {
      // Same rule NimbusSemanticColors follows: a missing extension means the
      // app was not built with NimbusTheme, and returning a default palette
      // would hide that until somebody noticed the wrong colours.
      throw StateError(
        'NimbusChartColors is missing. Build the app with NimbusTheme.',
      );
    }
    return ext;
  }

  /// A colour per key, stable across rebuilds and independent of input order.
  ///
  /// Colour cannot follow position: buckets arrive ranked by amount, so a
  /// category would change colour whenever its rank moved, and comparing two
  /// months side by side -- which is the point of half this phase -- would be
  /// misleading rather than merely ugly.
  ///
  /// Nor can it be a plain hash of the key: with eight colours and six
  /// categories, the birthday problem makes a collision more likely than not,
  /// and two same-coloured slices in one pie is worse than either failure. So
  /// each key *prefers* a slot derived from a stable hash, and collisions fall
  /// through to the next free one. That keeps assignment distinct whenever
  /// there are enough colours, while a key keeps its preferred slot as long as
  /// nothing else claims it first.
  Map<String, Color> assign(Iterable<String> keys) {
    final unique = keys.toSet().toList()..sort();
    final preferred = {
      for (final key in unique) key: _stableHash(key) % series.length,
    };

    final taken = <int>{};
    final assigned = <String, Color>{};
    for (final key in unique) {
      if (taken.add(preferred[key]!)) assigned[key] = series[preferred[key]!];
    }
    for (final key in unique) {
      if (assigned.containsKey(key)) continue;
      // Past the palette's size, repeats are unavoidable; starting a fresh
      // cycle is what keeps the loop below terminating.
      if (taken.length >= series.length) taken.clear();
      var slot = preferred[key]!;
      while (taken.contains(slot)) {
        slot = (slot + 1) % series.length;
      }
      taken.add(slot);
      assigned[key] = series[slot];
    }
    return assigned;
  }

  /// FNV-1a, written out rather than using `String.hashCode`, which Dart does
  /// not promise to keep stable across runs. A category that changed colour
  /// when the app restarted would be a bug nobody could reproduce on demand.
  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  @override
  NimbusChartColors copyWith({List<Color>? series}) =>
      NimbusChartColors(series: series ?? this.series);

  @override
  NimbusChartColors lerp(ThemeExtension<NimbusChartColors>? other, double t) {
    // The palette is identical in both themes, so there is nothing to cross-
    // fade. Snapping to the target keeps a chart's colours from passing
    // through muddy intermediates during a theme change.
    if (other is! NimbusChartColors) return this;
    return t < 0.5 ? this : other;
  }
}
