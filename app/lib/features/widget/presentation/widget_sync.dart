import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../analytics/application/analytics_providers.dart';
import '../../notifications/application/outside_errors.dart';
import '../../notifications/data/outside_channel.dart';
import '../../settings/application/settings_providers.dart';
import '../../trackers/application/tracker_providers.dart';
import '../application/snapshot_writer.dart';

/// Keeps the home-screen widget's snapshot current while the app runs
/// (spec §6.1). It rewrites the snapshot 300 ms after the last of these:
/// - start-up (after the first frame, never on the cold-start path);
/// - resume;
/// - a transaction, category or tag write (the chips);
/// - a tracker entry write (today's totals);
/// - a change to the tab's trackers;
/// - a settings change (language, currency).
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
  final _writes = <StreamSubscription<void>>[];
  Timer? _pending;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _changed);
    ref.listenManual<AnalyticsEngine>(
      analyticsEngineProvider,
      (_, engine) => _follow(engine),
      fireImmediately: true,
    );
    ref.listenManual(trackersProvider, (_, __) => _changed());
    ref.listenManual(settingsProvider, (_, __) => _changed());
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
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

  Future<void> _write() {
    // Read now: the write may finish after this widget is gone.
    final writer = ref.read(snapshotWriterProvider);
    final channel = ref.read(outsideChannelProvider);
    return reportingFailure(
      'widget drain',
      'while writing the widget snapshot',
      () async => channel.writeSnapshot(await writer.build()),
    );
  }

  @override
  void dispose() {
    _pending?.cancel();
    for (final subscription in _writes) {
      unawaited(subscription.cancel());
    }
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
