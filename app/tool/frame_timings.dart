/// Measures frame and query timings on a real device.
///
/// The hardware criteria are judged on a phone, never an emulator, against a
/// database seeded by the debug-only demo tile. This drives the app with real
/// touch input over adb and records Flutter's own per-frame build, raster and
/// start-delay times, plus the analytics queries the app reports, from the
/// running app.
///
/// Scenarios:
/// - `scroll` (default): vertical flings, down then back up -- the
///   transaction list, or a dashboard of cards.
/// - `months`: taps the month bar's previous button N times, then next N
///   times -- the dashboard or Breakdown, which re-query on every step.
/// - `tabs`: horizontal swipes across the analytics tabs, N forward then N
///   back.
///
/// 1. Start a profile build on the device, on the screen to measure, screen
///    unlocked: `flutter run --profile -d SERIAL`, and copy the address from
///    its "Dart VM service is listening on http://..." line.
/// 2. From `app/`:
///    `dart run tool/frame_timings.dart --vm-service ADDRESS --serial SERIAL`
///
/// Exits non-zero, with the reason, when it cannot measure -- adb failing, the
/// VM service unreachable, a button it cannot find, or no frames arriving (a
/// locked screen renders nothing). A run that measured nothing never prints a
/// result.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'src/frame_stats.dart';
import 'src/ui_dump.dart';

Future<void> main(List<String> args) async {
  final _Options options;
  try {
    options = _Options.parse(args);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln(_Options.usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  try {
    final (frames, queries) = await _measure(options);
    _report(frames, queries, options);
  } on _MeasurementFailed catch (e) {
    stderr.writeln('frame_timings: ${e.message}');
    exitCode = 1;
  }
}

enum _Scenario { scroll, months, tabs }

Future<(FrameStats, QueryStats?)> _measure(_Options options) async {
  final screen = await _screenSize(options);
  // Looked up before recording starts: a uiautomator dump is heavy, and
  // taking one mid-run would be measured as the app's own jank.
  final drive = switch (options.scenario) {
    _Scenario.scroll => () => _scroll(options, screen),
    _Scenario.months => await _monthSteps(options),
    _Scenario.tabs => () => _tabSwipes(options, screen),
  };

  final VmService service;
  try {
    service = await vmServiceConnectUri(options.vmService.toString());
  } on Object catch (e) {
    throw _MeasurementFailed('cannot reach the VM service at '
        '${options.vmService}: $e');
  }

  final frames = <FrameSample>[];
  final queries = <QuerySample>[];
  var recording = false;
  final subscription = service.onExtensionEvent.listen((event) {
    if (!recording) return;
    final data = event.extensionData!.data;
    switch (event.extensionKind) {
      case 'Flutter.Frame':
        frames.add(FrameSample.fromEvent(data));
      case 'Nimbus.Query':
        queries.add(QuerySample.fromEvent(data));
    }
  });

  try {
    await service.streamListen(EventStreams.kExtension);
    recording = true;
    await drive();
    // Frames are reported in batches, shortly after they are drawn.
    await Future<void>.delayed(const Duration(seconds: 1));
  } finally {
    recording = false;
    await subscription.cancel();
    await service.dispose();
  }

  final FrameStats frameStats;
  try {
    frameStats = FrameStats.of(frames);
  } on ArgumentError catch (e) {
    throw _MeasurementFailed('${e.message}');
  }

  if (queries.isEmpty) {
    // Stepping months and switching tabs always ask the database something,
    // so silence there means the timings are not reaching this tool -- a
    // release build, or the wrong screen -- not that queries were free.
    if (options.scenario != _Scenario.scroll) {
      throw _MeasurementFailed('no Nimbus.Query events arrived during '
          '"${options.scenario.name}": is this a profile build, open on the '
          'screen being measured?');
    }
    return (frameStats, null);
  }
  return (frameStats, QueryStats.of(queries));
}

/// Down through the list, which is also what makes it page in more rows at
/// the 80 % mark, then back up over rows that are already built.
Future<void> _scroll(_Options options, _Size screen) async {
  for (var i = 0; i < options.swipes; i++) {
    await _swipe(options, screen, down: true);
  }
  for (var i = 0; i < options.swipes; i++) {
    await _swipe(options, screen, down: false);
  }
}

/// Finds the month bar's two buttons now, and returns the run that taps them.
Future<Future<void> Function()> _monthSteps(_Options options) async {
  await _adb(options, ['shell', 'uiautomator', 'dump', _dumpPath]);
  final xml = await _adb(options, ['exec-out', 'cat', _dumpPath]);
  ScreenPoint only(String label) => switch (centresOf(xml, label)) {
        [final point] => point,
        [] => throw _MeasurementFailed('no "$label" button on screen; open '
            'the dashboard or Breakdown, or pass its label with '
            '--previous-label / --next-label'),
        final many => throw _MeasurementFailed('${many.length} "$label" '
            'buttons on screen; refusing to guess which one to tap'),
      };
  final previous = only(options.previousLabel);
  final next = only(options.nextLabel);

  return () async {
    for (final point in [
      for (var i = 0; i < options.swipes; i++) previous,
      for (var i = 0; i < options.swipes; i++) next,
    ]) {
      await _adb(options, ['shell', 'input', 'tap', '${point.x}', '${point.y}']);
      await Future<void>.delayed(_settle);
    }
  };
}

/// Forward across the tabs, then back. A swipe past the last tab moves
/// nothing, so N beyond the tab count adds idle frames, not tab changes.
///
/// The swipe runs along [_Options.swipeY]: a row where every tab has
/// something that ignores sideways drags. Mid-screen, the cross-tab's grid
/// scrolls sideways itself and takes the swipe, so the run never got past it.
Future<void> _tabSwipes(_Options options, _Size screen) async {
  final y = options.swipeY ?? screen.height * 3 ~/ 10;
  final left = screen.width ~/ 5;
  final right = screen.width * 4 ~/ 5;
  // Moving the finger left reveals the next tab.
  for (final (from, to) in [
    for (var i = 0; i < options.swipes; i++) (right, left),
    for (var i = 0; i < options.swipes; i++) (left, right),
  ]) {
    await _adb(options,
        ['shell', 'input', 'swipe', '$from', '$y', '$to', '$y', '150']);
    await Future<void>.delayed(_settle);
  }
}

const _dumpPath = '/sdcard/nimbus-ui.xml';

/// Time for an input's work -- queries, then frames -- to finish before the
/// next one.
const _settle = Duration(milliseconds: 800);

/// A fling across the middle half of the screen, then time for it to settle.
Future<void> _swipe(_Options options, _Size screen,
    {required bool down}) async {
  final x = screen.width ~/ 2;
  final low = screen.height * 3 ~/ 4;
  final high = screen.height ~/ 4;
  // Moving the finger up scrolls the list down.
  final (from, to) = down ? (low, high) : (high, low);
  await _adb(options,
      ['shell', 'input', 'swipe', '$x', '$from', '$x', '$to', '150']);
  await Future<void>.delayed(_settle);
}

Future<_Size> _screenSize(_Options options) async {
  final output = await _adb(options, ['shell', 'wm', 'size']);
  // "Physical size: 1080x2400", possibly followed by an "Override size" line,
  // which is the one actually in effect.
  final sizes = RegExp(r'(\d+)x(\d+)').allMatches(output).toList();
  if (sizes.isEmpty) {
    throw _MeasurementFailed('cannot read the screen size from: $output');
  }
  final last = sizes.last;
  return (width: int.parse(last[1]!), height: int.parse(last[2]!));
}

Future<String> _adb(_Options options, List<String> args) async {
  final ProcessResult result;
  try {
    result =
        await Process.run(options.adb, ['-s', options.serial, ...args]);
  } on ProcessException catch (e) {
    throw _MeasurementFailed('cannot run adb (${e.message}); pass its path '
        'with --adb, e.g. --adb C:/dev/android-sdk/platform-tools/adb.exe');
  }
  if (result.exitCode != 0) {
    throw _MeasurementFailed('adb ${args.join(' ')} exited '
        '${result.exitCode}: ${result.stderr}');
  }
  return result.stdout as String;
}

void _report(FrameStats stats, QueryStats? queries, _Options options) {
  String ms(num micros) => (micros / 1000).toStringAsFixed(2);
  String row(String name, PhaseStats phase) => '${name.padRight(7)}'
      '${ms(phase.averageMicros).padLeft(6)}  '
      '${ms(phase.p90Micros).padLeft(6)}  '
      '${ms(phase.p99Micros).padLeft(6)}  '
      '${ms(phase.worstMicros).padLeft(6)}  ${phase.overBudget}';
  final steps = switch (options.scenario) {
    _Scenario.scroll => 'swipes',
    _Scenario.months => 'month steps',
    _Scenario.tabs => 'tab swipes',
  };

  stdout
    ..writeln('${options.scenario.name}: ${stats.count} frames over '
        '${options.swipes * 2} $steps; '
        'budget ${ms(FrameStats.budgetMicros)} ms (60 fps)')
    ..writeln('          avg     p90     p99   worst  over budget')
    ..writeln(row('build', stats.build))
    ..writeln(row('raster', stats.raster))
    ..writeln(row('start', stats.startDelay))
    ..writeln('within budget: '
        '${(stats.withinBudgetShare * 100).toStringAsFixed(1)} % '
        '(${stats.overBudgetEither} frames over in build or raster)');

  if (queries == null) {
    stdout.writeln('queries: none reported');
  } else {
    final q = queries.micros;
    stdout
      ..writeln('queries: ${queries.count}; '
          'budget ${ms(QueryStats.budgetMicros)} ms')
      ..writeln('  p50 ${ms(q.p50Micros)}  p99 ${ms(q.p99Micros)}  '
          'worst ${ms(q.worstMicros)}  over budget ${q.overBudget}')
      ..writeln('  slowest: ${[
        for (final s in queries.slowest) '${s.label} ${ms(s.micros)}'
      ].join(', ')}');
  }

  final out = options.out;
  if (out != null) {
    File(out).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'serial': options.serial,
      'scenario': options.scenario.name,
      'swipes': options.swipes,
      'measuredAt': DateTime.now().toUtc().toIso8601String(),
      ...stats.toJson(),
      'queries': queries?.toJson(),
    }));
    stdout.writeln('written to $out');
  }
}

typedef _Size = ({int width, int height});

final class _MeasurementFailed implements Exception {
  const _MeasurementFailed(this.message);
  final String message;
}

final class _Options {
  const _Options({
    required this.vmService,
    required this.serial,
    required this.adb,
    required this.scenario,
    required this.swipes,
    required this.previousLabel,
    required this.nextLabel,
    required this.swipeY,
    required this.out,
  });

  static const usage = 'usage: dart run tool/frame_timings.dart '
      '--vm-service <http://127.0.0.1:PORT/TOKEN=/> --serial <adb serial> '
      '[--adb path/to/adb] [--scenario scroll|months|tabs] [--swipes 20] '
      '[--previous-label "Previous month"] [--next-label "Next month"] '
      '[--swipe-y PX] [--out results.json]';

  /// The WebSocket form of the address `flutter run` prints.
  final Uri vmService;
  final String serial;

  /// Not assumed to be on PATH: the SDK's platform-tools often is not.
  final String adb;
  final _Scenario scenario;

  /// Inputs per direction: swipes, month steps, or tab swipes.
  final int swipes;

  /// The month bar's buttons as a screen reader names them: their tooltips,
  /// in the app's language. The defaults are the English ones.
  final String previousLabel;
  final String nextLabel;

  /// The screen row, in pixels, that `tabs` swipes along. Defaults to 30 % of
  /// the screen's height: below the tab bar, on the tabs' headers and
  /// switches, above the content that scrolls sideways.
  final int? swipeY;
  final String? out;

  static _Options parse(List<String> args) {
    final values = <String, String>{};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith('--') || i + 1 >= args.length) {
        throw FormatException('unexpected argument: $arg');
      }
      values[arg.substring(2)] = args[++i];
    }
    const known = {
      'vm-service',
      'serial',
      'adb',
      'scenario',
      'swipes',
      'previous-label',
      'next-label',
      'swipe-y',
      'out',
    };
    final unknown = values.keys.where((k) => !known.contains(k));
    if (unknown.isNotEmpty) {
      throw FormatException('unknown option: --${unknown.first}');
    }

    String require(String key) =>
        values[key] ?? (throw FormatException('missing --$key'));
    final swipes = int.tryParse(values['swipes'] ?? '20');
    if (swipes == null || swipes < 1) {
      throw FormatException('--swipes must be a positive integer');
    }
    final swipeYText = values['swipe-y'];
    final swipeY = swipeYText == null ? null : int.tryParse(swipeYText);
    if (swipeYText != null && (swipeY == null || swipeY < 0)) {
      throw FormatException('--swipe-y must be a pixel row, 0 or more');
    }
    final scenarioName = values['scenario'] ?? _Scenario.scroll.name;
    final scenario = _Scenario.values
            .where((s) => s.name == scenarioName)
            .firstOrNull ??
        (throw FormatException('--scenario must be one of '
            '${_Scenario.values.map((s) => s.name).join(', ')}'));

    return _Options(
      vmService: _webSocketUri(require('vm-service')),
      serial: require('serial'),
      adb: values['adb'] ?? 'adb',
      scenario: scenario,
      swipes: swipes,
      previousLabel: values['previous-label'] ?? 'Previous month',
      nextLabel: values['next-label'] ?? 'Next month',
      swipeY: swipeY,
      out: values['out'],
    );
  }

  /// `http://127.0.0.1:PORT/TOKEN=/` becomes `ws://127.0.0.1:PORT/TOKEN=/ws`.
  static Uri _webSocketUri(String address) {
    final uri = Uri.parse(address);
    if (uri.scheme == 'ws' || uri.scheme == 'wss') return uri;
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw FormatException('--vm-service must be an http or ws address');
    }
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      path: '${path}ws',
    );
  }
}
