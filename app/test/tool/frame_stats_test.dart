import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/frame_stats.dart';

/// The summariser behind `tool/frame_timings.dart`, which measures the
/// "list holds 60 fps" criterion on a real device. It turns Flutter's own
/// per-frame timings into the numbers that criterion is judged on, so it is
/// held to exact values rather than to "looks plausible".
void main() {
  FrameSample frame(int buildMicros, int rasterMicros) =>
      FrameSample(buildMicros: buildMicros, rasterMicros: rasterMicros);

  test('averages and nearest-rank percentiles are exact', () {
    final stats = FrameStats.of([
      for (var i = 1; i <= 10; i++) frame(i * 1000, 2000),
    ]);

    expect(stats.count, 10);
    expect(stats.build.averageMicros, 5500);
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
    });

    test('rejects a payload without timings instead of reading it as zero',
        () {
      expect(() => FrameSample.fromEvent({'number': 1, 'raster': 10}),
          throwsFormatException);
    });
  });
}
