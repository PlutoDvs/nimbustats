import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../application/tracker_providers.dart';

/// "Running · 0:12:05", computed from the persisted start on every tick.
///
/// Ticks once a second, and only while this widget is mounted: a timer tile
/// scrolled off the list stops costing anything. The time shown is always
/// now minus the stored start, never a count kept here, so a tick that is late
/// or missed changes nothing.
class TrackerElapsedText extends ConsumerStatefulWidget {
  const TrackerElapsedText({super.key, required this.timer, this.style});

  final RunningTimer timer;
  final TextStyle? style;

  @override
  ConsumerState<TrackerElapsedText> createState() => _TrackerElapsedTextState();
}

class _TrackerElapsedTextState extends ConsumerState<TrackerElapsedText> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker =
        Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed =
        widget.timer.elapsed(ref.watch(trackerClockProvider).nowUtc());
    return Text(
      AppLocalizations.of(context)
          .trackerTimerRunning(ref.watch(trackerFormatProvider).elapsed(elapsed)),
      style: widget.style,
    );
  }
}
