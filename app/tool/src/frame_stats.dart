/// Frame- and query-timing arithmetic for `tool/frame_timings.dart`.
///
/// Pure, so the numbers the device criteria are judged on can be tested
/// exactly, away from the device that produces them.
library;

/// One frame, as Flutter itself reported it.
///
/// Build is the UI thread's work (build, layout, paint); raster is the raster
/// thread turning that into pixels. They overlap across frames, so each is
/// held to the frame budget on its own -- the same reading as `FrameTiming`
/// and DevTools' frame chart.
///
/// Start delay is how late the UI thread began the frame after the vsync
/// asked for it. Work that blocks the UI isolate *between* frames -- a
/// database query on that isolate, say -- leaves build and raster untouched
/// and shows only here.
final class FrameSample {
  const FrameSample({
    required this.buildMicros,
    required this.rasterMicros,
    required this.startDelayMicros,
  });

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
      startDelayMicros: micros('vsyncOverhead'),
    );
  }

  final int buildMicros;
  final int rasterMicros;
  final int startDelayMicros;
}

/// Summary of one measured quantity across a run, against [budgetMicros].
final class PhaseStats {
  PhaseStats._(List<int> micros, {required this.budgetMicros})
      : averageMicros = micros.reduce((a, b) => a + b) / micros.length,
        p50Micros = _nearestRank(micros, 50),
        p90Micros = _nearestRank(micros, 90),
        p99Micros = _nearestRank(micros, 99),
        worstMicros = micros.reduce((a, b) => a > b ? a : b),
        overBudget = micros.where((m) => m > budgetMicros).length;

  final int budgetMicros;
  final double averageMicros;
  final int p50Micros;
  final int p90Micros;
  final int p99Micros;
  final int worstMicros;

  /// Samples that exceeded [budgetMicros]. One exactly on it is within.
  final int overBudget;

  /// Nearest-rank: the smallest value with at least [percent] % of the
  /// samples at or below it. Always a value that was actually measured, never
  /// an interpolation between two samples.
  static int _nearestRank(List<int> micros, int percent) {
    final sorted = [...micros]..sort();
    final rank = (percent * sorted.length / 100).ceil();
    return sorted[rank - 1];
  }

  Map<String, Object> toJson() => {
        'budgetMicros': budgetMicros,
        'averageMicros': averageMicros,
        'p50Micros': p50Micros,
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
        build = PhaseStats._([for (final s in samples) s.buildMicros],
            budgetMicros: budgetMicros),
        raster = PhaseStats._([for (final s in samples) s.rasterMicros],
            budgetMicros: budgetMicros),
        startDelay = PhaseStats._(
            [for (final s in samples) s.startDelayMicros],
            budgetMicros: budgetMicros),
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
  final PhaseStats startDelay;

  /// Frames over budget in build, raster, or both -- each counted once. Start
  /// delay is judged separately: it is the time before the frame, not in it.
  final int overBudgetEither;

  double get withinBudgetShare => (count - overBudgetEither) / count;

  Map<String, Object> toJson() => {
        'budgetMicros': budgetMicros,
        'count': count,
        'overBudgetEither': overBudgetEither,
        'withinBudgetShare': withinBudgetShare,
        'build': build.toJson(),
        'raster': raster.toJson(),
        'startDelay': startDelay.toJson(),
      };
}

/// One analytics query, as the app reported it.
final class QuerySample {
  const QuerySample({required this.micros, required this.label});

  /// From the payload of a `Nimbus.Query` VM service event, which the app's
  /// analytics query path posts in debug and profile builds
  /// (`analytics_providers.dart`, `queryTimingProvider`).
  factory QuerySample.fromEvent(Map<String, Object?> data) {
    final micros = data['micros'];
    if (micros is! int) {
      throw FormatException('Nimbus.Query event without "micros"', data);
    }
    final spec = data['spec'];
    final groupBy = spec is Map ? spec['groupBy'] : null;
    final kind = groupBy is Map ? groupBy['kind'] : null;
    if (groupBy is! Map || kind is! String) {
      // Named, a slow query says which chart asked it; unnamed, it says only
      // that something was slow.
      throw FormatException('Nimbus.Query event without a spec.groupBy', data);
    }
    final parameters = [
      for (final MapEntry(:key, :value) in groupBy.entries)
        if (key != 'kind') '$value',
    ];
    return QuerySample(
      micros: micros,
      label: parameters.isEmpty ? kind : '$kind(${parameters.join(', ')})',
    );
  }

  final int micros;

  /// The query's group-by dimension and its parameters, e.g. `period(month)`.
  final String label;

  Map<String, Object> toJson() => {'micros': micros, 'label': label};
}

/// A run's analytics queries against the 100 ms budget.
final class QueryStats {
  QueryStats._(List<QuerySample> samples)
      : count = samples.length,
        micros = PhaseStats._([for (final s in samples) s.micros],
            budgetMicros: budgetMicros),
        slowest = ([...samples]..sort((a, b) => b.micros.compareTo(a.micros)))
            .take(5)
            .toList();

  /// Throws on an empty run, as [FrameStats.of] does.
  factory QueryStats.of(List<QuerySample> samples) {
    if (samples.isEmpty) {
      throw ArgumentError.value(samples, 'samples',
          'no queries were recorded -- a release build, or nothing asked one');
    }
    return QueryStats._(samples);
  }

  /// A tenth of a second: about where a response stops reading as immediate.
  static const budgetMicros = 100000;

  final int count;
  final PhaseStats micros;

  /// Up to five, slowest first.
  final List<QuerySample> slowest;

  Map<String, Object> toJson() => {
        'count': count,
        ...micros.toJson(),
        'slowest': [for (final q in slowest) q.toJson()],
      };
}
