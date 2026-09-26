/// Measures the transaction list's frame timings on a real device.
///
/// Phase 1's "list holds 60 fps" criterion is judged on hardware, against a
/// database of 5,000+ transactions (the debug-only demo tile seeds one). This
/// drives the list with real touch input over adb and records Flutter's own
/// per-frame build and raster times from the running app.
///
/// 1. Start a profile build on the device, open on the list, screen unlocked:
///    `flutter run --profile -d SERIAL`, and copy the address from its
///    "Dart VM service is listening on http://..." line.
/// 2. From `app/`:
///    `dart run tool/frame_timings.dart --vm-service ADDRESS --serial SERIAL`
///
/// Exits non-zero, with the reason, when it cannot measure -- adb failing, the
/// VM service unreachable, or no frames arriving (a locked screen renders
/// nothing). A run that measured nothing never prints a result.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'src/frame_stats.dart';

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
    final stats = await _measure(options);
    _report(stats, options);
  } on _MeasurementFailed catch (e) {
    stderr.writeln('frame_timings: ${e.message}');
    exitCode = 1;
  }
}

Future<FrameStats> _measure(_Options options) async {
  final screen = await _screenSize(options);

  final VmService service;
  try {
    service = await vmServiceConnectUri(options.vmService.toString());
  } on Object catch (e) {
    throw _MeasurementFailed('cannot reach the VM service at '
        '${options.vmService}: $e');
  }

  final samples = <FrameSample>[];
  var recording = false;
  final subscription = service.onExtensionEvent.listen((event) {
    if (!recording || event.extensionKind != 'Flutter.Frame') return;
    samples.add(FrameSample.fromEvent(event.extensionData!.data));
  });

  try {
    await service.streamListen(EventStreams.kExtension);
    recording = true;
    // Down through the list, which is also what makes it page in more rows at
    // the 80 % mark, then back up over rows that are already built.
    for (var i = 0; i < options.swipes; i++) {
      await _swipe(options, screen, down: true);
    }
    for (var i = 0; i < options.swipes; i++) {
      await _swipe(options, screen, down: false);
    }
    // Frames are reported in batches, shortly after they are drawn.
    await Future<void>.delayed(const Duration(seconds: 1));
  } finally {
    recording = false;
    await subscription.cancel();
    await service.dispose();
  }

  try {
    return FrameStats.of(samples);
  } on ArgumentError catch (e) {
    throw _MeasurementFailed('${e.message}');
  }
}

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
  await Future<void>.delayed(const Duration(milliseconds: 800));
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

void _report(FrameStats stats, _Options options) {
  String ms(num micros) => (micros / 1000).toStringAsFixed(2);
  final budget = ms(FrameStats.budgetMicros);
  stdout
    ..writeln('${stats.count} frames over ${options.swipes * 2} swipes; '
        'budget $budget ms (60 fps)')
    ..writeln('          avg     p90     p99   worst  over budget')
    ..writeln('build  ${ms(stats.build.averageMicros).padLeft(6)}  '
        '${ms(stats.build.p90Micros).padLeft(6)}  '
        '${ms(stats.build.p99Micros).padLeft(6)}  '
        '${ms(stats.build.worstMicros).padLeft(6)}  ${stats.build.overBudget}')
    ..writeln('raster ${ms(stats.raster.averageMicros).padLeft(6)}  '
        '${ms(stats.raster.p90Micros).padLeft(6)}  '
        '${ms(stats.raster.p99Micros).padLeft(6)}  '
        '${ms(stats.raster.worstMicros).padLeft(6)}  ${stats.raster.overBudget}')
    ..writeln('within budget: '
        '${(stats.withinBudgetShare * 100).toStringAsFixed(1)} % '
        '(${stats.overBudgetEither} frames over in build or raster)');

  final out = options.out;
  if (out != null) {
    File(out).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'serial': options.serial,
      'swipes': options.swipes,
      'measuredAt': DateTime.now().toUtc().toIso8601String(),
      ...stats.toJson(),
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
    required this.swipes,
    required this.out,
  });

  static const usage = 'usage: dart run tool/frame_timings.dart '
      '--vm-service <http://127.0.0.1:PORT/TOKEN=/> --serial <adb serial> '
      '[--adb path/to/adb] [--swipes 20] [--out results.json]';

  /// The WebSocket form of the address `flutter run` prints.
  final Uri vmService;
  final String serial;

  /// Not assumed to be on PATH: the SDK's platform-tools often is not.
  final String adb;
  final int swipes;
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
    const known = {'vm-service', 'serial', 'adb', 'swipes', 'out'};
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

    return _Options(
      vmService: _webSocketUri(require('vm-service')),
      serial: require('serial'),
      adb: values['adb'] ?? 'adb',
      swipes: swipes,
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
