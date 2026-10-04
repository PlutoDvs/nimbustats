import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/frame_stats.dart';

/// The summariser behind `tool/frame_timings.dart`, which measures the
/// "list holds 60 fps" criterion on a real device. It turns Flutter's own
/// per-frame timings into the numbers that criterion is judged on, so it is
/// held to exact values rather than to "looks plausible".
void main() {
  FrameSample frame(int buildMicros, int rasterMicros,
          [int startDelayMicros = 0]) =>
      FrameSample(
        buildMicros: buildMicros,
        rasterMicros: rasterMicros,
        startDelayMicros: startDelayMicros,
      );

  test('averages and nearest-rank percentiles are exact', () {
    final stats = FrameStats.of([
      for (var i = 1; i <= 10; i++) frame(i * 1000, 2000),
    ]);

    expect(stats.count, 10);
    expect(stats.build.averageMicros, 5500);
    expect(stats.build.p50Micros, 5000); // rank ceil(0.50 * 10) = 5
    expect(stats.build.p90Micros, 9000); // rank ceil(0.90 * 10) = 9
    expect(stats.build.p99Micros, 10000); // rank ceil(0.99 * 10) = 10
    expect(stats.build.worstMicros, 10000);
    expect(stats.raster.averageMicros, 2000);
    expect(stats.raster.worstMicros, 2000);
  });

  test('over-budget frames are counted per phase, and once for either', () {
    final stats = FrameStats.of([
      frame(10000, 18000), // raster over
      frame(17000, 1000), // build over
      frame(5000, 1000), // on budget
      frame(20000, 19000), // both over: one frame, not two
    ]);

    expect(stats.build.overBudget, 2);
    expect(stats.raster.overBudget, 2);
    expect(stats.overBudgetEither, 3);
    expect(stats.withinBudgetShare, 0.25);
  });

  test('a frame of exactly one sixtieth of a second is on budget', () {
    expect(FrameStats.budgetMicros, 16667);
    final stats = FrameStats.of([frame(16667, 16667), frame(16668, 1000)]);
    expect(stats.build.overBudget, 1);
    expect(stats.raster.overBudget, 0);
  });

  test('a late frame start is judged on its own, apart from build and raster',
      () {
    // A query blocking the UI isolate between frames makes the next frame
    // start late without making its build any slower: only the start delay
    // shows it.
    final stats = FrameStats.of([
      frame(1000, 1000, 200),
      frame(1000, 1000, 40000),
      frame(1000, 1000, 16667),
    ]);

    expect(stats.startDelay.overBudget, 1);
    expect(stats.startDelay.worstMicros, 40000);
    expect(stats.overBudgetEither, 0,
        reason: 'build and raster were on budget in every frame');
  });

  test('a run that saw no frames is an error, not a perfect score', () {
    // Screen off, wrong screen, or the VM service stream never delivered:
    // every one of those produces zero frames, and zero frames has no
    // over-budget frames in it.
    expect(() => FrameStats.of(const []), throwsArgumentError);
  });

  group('FrameSample.fromEvent', () {
    test('reads the Flutter.Frame payload', () {
      final sample = FrameSample.fromEvent({
        'number': 42,
        'startTime': 123456789,
        'elapsed': 20000,
        'build': 4100,
        'raster': 6200,
        'vsyncOverhead': 300,
      });
      expect(sample.buildMicros, 4100);
      expect(sample.rasterMicros, 6200);
      expect(sample.startDelayMicros, 300);
    });

    test('rejects a payload without its start delay', () {
      expect(
          () => FrameSample.fromEvent({'build': 4100, 'raster': 6200}),
          throwsFormatException);
    });

    test('rejects a payload without timings instead of reading it as zero',
        () {
      expect(() => FrameSample.fromEvent({'number': 1, 'raster': 10}),
          throwsFormatException);
    });
  });

  group('queries', () {
    QuerySample query(int micros, [String label = 'none']) =>
        QuerySample(micros: micros, label: label);

    test('percentiles, worst, and the five slowest, slowest first', () {
      final stats = QueryStats.of([
        for (final ms in [5, 80, 12, 140, 30, 9, 101]) query(ms * 1000, '$ms'),
      ]);

      expect(stats.count, 7);
      expect(stats.micros.p50Micros, 30000); // rank ceil(0.50 * 7) = 4
      expect(stats.micros.p99Micros, 140000);
      expect(stats.micros.worstMicros, 140000);
      expect([for (final q in stats.slowest) q.label],
          ['140', '101', '80', '30', '12']);
    });

    test('a query of exactly 100 ms is on budget', () {
      expect(QueryStats.budgetMicros, 100000);
      final stats = QueryStats.of([query(100000), query(100001)]);
      expect(stats.micros.overBudget, 1);
    });

    test('a run that saw no queries is an error, not a perfect score', () {
      expect(() => QueryStats.of(const []), throwsArgumentError);
    });

    group('QuerySample.fromEvent', () {
      test('reads the Nimbus.Query payload and names the dimension', () {
        final sample = QuerySample.fromEvent({
          'micros': 4321,
          'spec': {
            'filters': <String, Object?>{},
            'groupBy': {'kind': 'period', 'period': 'month'},
            'aggregate': 'sum',
          },
        });
        expect(sample.micros, 4321);
        expect(sample.label, 'period(month)');
      });

      test('a dimension without parameters is named by its kind alone', () {
        final sample = QuerySample.fromEvent({
          'micros': 1,
          'spec': {
            'groupBy': {'kind': 'hourOfDay'},
          },
        });
        expect(sample.label, 'hourOfDay');
      });

      test('rejects a payload without its time instead of reading it as zero',
          () {
        expect(
            () => QuerySample.fromEvent({
                  'spec': {
                    'groupBy': {'kind': 'none'},
                  },
                }),
            throwsFormatException);
      });

      test('rejects a payload without a spec to name it by', () {
        expect(() => QuerySample.fromEvent({'micros': 1}),
            throwsFormatException);
      });
    });
  });
}
