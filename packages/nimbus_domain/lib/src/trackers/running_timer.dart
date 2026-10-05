import 'package:meta/meta.dart';

/// A duration tracker's timer while it runs: when it started, and nothing
/// else.
///
/// The start is persisted the moment the timer starts (the tracker's
/// `timer_started_at_utc`), and elapsed time is always computed from it. So a
/// process death, a reboot or a timezone change cannot lose or warp a running
/// timer: nothing about it is held only in memory.
@immutable
final class RunningTimer {
  RunningTimer(this.startedAtUtc) {
    if (!startedAtUtc.isUtc) {
      throw ArgumentError.value(startedAtUtc, 'startedAtUtc', 'must be UTC');
    }
  }

  final DateTime startedAtUtc;

  /// Time since the start, never negative: a device clock set back past the
  /// start reads as zero rather than as a negative session.
  Duration elapsed(DateTime nowUtc) {
    final elapsed = nowUtc.toUtc().difference(startedAtUtc);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  @override
  bool operator ==(Object other) =>
      other is RunningTimer && other.startedAtUtc == startedAtUtc;

  @override
  int get hashCode => startedAtUtc.hashCode;

  @override
  String toString() => 'RunningTimer($startedAtUtc)';
}
