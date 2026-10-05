import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/tracker_providers.dart';

/// Moves `trackerTodayProvider` to the new day while a tracker screen is
/// open: at local midnight, and whenever the app returns to the foreground.
/// A phone left on the tab overnight must not keep showing yesterday's
/// totals.
///
/// The timer lives in this widget's state rather than in a provider, so it
/// ends with the screen that needs it.
class TrackerDayRollover extends ConsumerStatefulWidget {
  const TrackerDayRollover({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TrackerDayRollover> createState() =>
      _TrackerDayRolloverState();
}

class _TrackerDayRolloverState extends ConsumerState<TrackerDayRollover> {
  Timer? _midnight;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _rollOver);
    _schedule();
  }

  /// Arms a timer for just past the next local midnight.
  ///
  /// Computed from the wall clock each time rather than as a fixed 24 hours.
  /// A daylight-saving night (23 or 25 hours) then shifts only one firing,
  /// and the re-arm after it lands on the true midnight.
  void _schedule() {
    _midnight?.cancel();
    final clock = ref.read(trackerClockProvider);
    final local = clock.toLocal(clock.nowUtc());
    final sinceMidnight = Duration(
      hours: local.hour,
      minutes: local.minute,
      seconds: local.second,
      milliseconds: local.millisecond,
    );
    _midnight = Timer(
      const Duration(days: 1) - sinceMidnight + const Duration(seconds: 1),
      _rollOver,
    );
  }

  void _rollOver() {
    ref.read(trackerTodayProvider.notifier).refresh();
    _schedule();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
