import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../analytics/application/analytics_providers.dart';
import '../../goals/application/goal_providers.dart';
import '../../notifications/application/outside_errors.dart';
import '../../notifications/data/outside_channel.dart';
import '../../settings/application/settings_providers.dart';
import '../../trackers/application/tracker_providers.dart';
import '../application/drain_service.dart';

/// Keeps the home-screen widget's snapshot current while the app runs
/// (spec §6.1). It rewrites the snapshot 300 ms after the last of these:
/// - start-up (after the first frame, never on the cold-start path);
/// - resume;
/// - a transaction, category or tag write (the chips);
/// - a tracker entry write (today's totals);
/// - a goal write (a tracker's goal progress);
/// - a change to the tab's trackers;
/// - a settings change (language, currency).
///
/// It also drains the buffer after the first frame, on every resume, and when
/// native asks (drainNow).
///
/// It sits on the shell (ruling R6): the widget is empty until first run is
/// done, and so is the database it reads.
class WidgetSync extends ConsumerStatefulWidget {
  const WidgetSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WidgetSync> createState() => _WidgetSyncState();
}

class _WidgetSyncState extends ConsumerState<WidgetSync> {
  static const _debounce = Duration(milliseconds: 300);

  late final AppLifecycleListener _lifecycle;
  late final DrainService _drain;
  late final OutsideChannel _channel;
  late final Future<bool> Function() _onDrainNow;
  final _writes = <StreamSubscription<void>>[];
  Timer? _pending;

  @override
  void initState() {
    super.initState();
    _drain = ref.read(drainServiceProvider);
    _channel = ref.read(outsideChannelProvider);
    // Native's drain job hands a live app engine the work (spec §2.4). A
    // closure of this shell's own: every shell's `_drain.run` tear-off is
    // equal, which would let an old shell unregister a newer one's.
    _onDrainNow = () async {
      try {
        return await _drain.run();
      } on Object catch (error, stack) {
        // The channel turns a throw into an error reply without reporting
        // it. Rethrown, because that reply sends native to the headless
        // engine.
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'widget drain',
          context: ErrorDescription('while draining for native (drainNow)'),
        ));
        rethrow;
      }
    };
    _channel.onDrainNow = _onDrainNow;
    _lifecycle = AppLifecycleListener(onResume: () {
      _drainNow();
      _changed();
    });
    ref.listenManual<AnalyticsEngine>(
      analyticsEngineProvider,
      (_, engine) => _follow(engine),
      fireImmediately: true,
    );
    ref.listenManual(trackersProvider, (_, __) => _changed());
    ref.listenManual(goalsProvider, (_, __) => _changed());
    ref.listenManual(settingsProvider, (_, __) => _changed());
    // After the first frame, never before it: cold start stays in budget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainNow();
      _changed();
    });
  }

  void _follow(AnalyticsEngine engine) {
    for (final subscription in _writes) {
      unawaited(subscription.cancel());
    }
    _writes
      ..clear()
      ..add(engine.changes().listen((_) => _changed()))
      ..add(engine.trackerChanges().listen((_) => _changed()));
    _changed();
  }

  void _changed() {
    _pending?.cancel();
    _pending = Timer(_debounce, () => unawaited(_write()));
  }

  void _drainNow() => unawaited(reportingFailure(
      'widget drain', 'while draining the widget buffer', _drain.run));

  Future<void> _write() => reportingFailure('widget drain',
      'while writing the widget snapshot', _drain.refreshSnapshot);

  @override
  void dispose() {
    _pending?.cancel();
    for (final subscription in _writes) {
      unawaited(subscription.cancel());
    }
    _lifecycle.dispose();
    // A newer shell may have registered its own drain already.
    if (identical(_channel.onDrainNow, _onDrainNow)) _channel.onDrainNow = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
