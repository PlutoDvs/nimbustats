/// Frame-timing arithmetic for `tool/frame_timings.dart`.
///
/// Pure, so the numbers the "list holds 60 fps" criterion is judged on can be
/// tested exactly, away from the device that produces them.
library;

/// One frame, as Flutter itself reported it.
///
/// Build is the UI thread's work (build, layout, paint); raster is the raster
/// thread turning that into pixels. They overlap across frames, so each is
/// held to the frame budget on its own -- the same reading as `FrameTiming`
/// and DevTools' frame chart.
final class FrameSample {
  const FrameSample({required this.buildMicros, required this.rasterMicros});

  /// From the payload of a `Flutter.Frame` VM service event, which every
  /// debug and profile build posts once per frame
  /// (`flutter/lib/src/scheduler/binding.dart`, `_profileFramePostEvent`).
  factory FrameSample.fromEvent(Map<String, Object?> data) {
    int micros(String key) {
      final value = data[key];
      if (value is! int) {
        // Read as zero, a missing timing would pass as the fastest frame of
        // the run.
        throw FormatException('Flutter.Frame event without "$key"', data);
      }
      return value;
    }

    return FrameSample(
      buildMicros: micros('build'),
      rasterMicros: micros('raster'),
    );
  }

  final int buildMicros;
  final int rasterMicros;
}

/// Summary of one phase -- build or raster -- across a run.
final class PhaseStats {
  PhaseStats._(List<int> micros)
      : averageMicros = micros.reduce((a, b) => a + b) / micros.length,
        p90Micros = _nearestRank(micros, 90),
        p99Micros = _nearestRank(micros, 99),
        worstMicros = micros.reduce((a, b) => a > b ? a : b),
        overBudget = micros.where((m) => m > FrameStats.budgetMicros).length;

  final double averageMicros;
  final int p90Micros;
  final int p99Micros;
  final int worstMicros;

  /// Frames whose time in this phase exceeded [FrameStats.budgetMicros].
  final int overBudget;

  /// Nearest-rank: the smallest value with at least [percent] % of the
  /// samples at or below it. Always a value that was actually measured, never
  /// an interpolation between two frames.
  static int _nearestRank(List<int> micros, int percent) {
    final sorted = [...micros]..sort();
    final rank = (percent * sorted.length / 100).ceil();
    return sorted[rank - 1];
  }

  Map<String, Object> toJson() => {
        'averageMicros': averageMicros,
        'p90Micros': p90Micros,
        'p99Micros': p99Micros,
        'worstMicros': worstMicros,
        'overBudget': overBudget,
      };
}

/// A run's frames against the 60 fps budget.
final class FrameStats {
  FrameStats._(List<FrameSample> samples)
      : count = samples.length,
        build = PhaseStats._([for (final s in samples) s.buildMicros]),
        raster = PhaseStats._([for (final s in samples) s.rasterMicros]),
        overBudgetEither = samples
            .where((s) =>
                s.buildMicros > budgetMicros || s.rasterMicros > budgetMicros)
            .length;

  /// Throws on an empty run rather than summarising it: zero frames contain
  /// zero slow frames, and "no data" must never read as "perfect".
  factory FrameStats.of(List<FrameSample> samples) {
    if (samples.isEmpty) {
      throw ArgumentError.value(samples, 'samples',
          'no frames were recorded -- screen off, wrong screen, or no stream');
    }
    return FrameStats._(samples);
  }

  /// One sixtieth of a second, rounded up to whole microseconds, so a frame of
  /// exactly 16.667 ms is on budget.
  static const budgetMicros = 16667;

  final int count;
  final PhaseStats build;
  final PhaseStats raster;

  /// Frames over budget in build, raster, or both -- each counted once.
  final int overBudgetEither;

  double get withinBudgetShare => (count - overBudgetEither) / count;

  Map<String, Object> toJson() => {
        'budgetMicros': budgetMicros,
        'count': count,
        'overBudgetEither': overBudgetEither,
        'withinBudgetShare': withinBudgetShare,
        'build': build.toJson(),
        'raster': raster.toJson(),
      };
}
