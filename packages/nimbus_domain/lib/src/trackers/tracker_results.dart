import 'running_timer.dart';
import 'tracker_entry.dart';

/// What logging an entry did.
///
/// Expected outcomes are results, not exceptions. A second "done" on the same
/// day is a normal double-tap, and a caller has to handle it, not catch it.
sealed class LogResult {
  const LogResult();
}

final class EntryLogged extends LogResult {
  const EntryLogged(this.entry);

  final TrackerEntry entry;

  @override
  String toString() => 'EntryLogged($entry)';
}

/// A boolean tracker already holds a live "done" for that day; nothing was
/// written.
final class AlreadyDoneToday extends LogResult {
  const AlreadyDoneToday();

  @override
  String toString() => 'AlreadyDoneToday()';
}

sealed class TimerStartResult {
  const TimerStartResult();
}

final class TimerStarted extends TimerStartResult {
  const TimerStarted(this.timer);

  final RunningTimer timer;
}

/// A timer was already running; its start is unchanged.
final class TimerAlreadyRunning extends TimerStartResult {
  const TimerAlreadyRunning();
}

sealed class TimerStopResult {
  const TimerStopResult();
}

final class TimerStopped extends TimerStopResult {
  const TimerStopped(this.entry);

  final TrackerEntry entry;
}

/// No timer was running -- typically the second tap of a double-tap on stop.
final class TimerNotRunning extends TimerStopResult {
  const TimerNotRunning();
}

/// Stopped under a second after it started, or with the clock set back past
/// its start: the timer is cleared and nothing is logged. A 0:00 entry is
/// noise, not data.
final class TimerDiscarded extends TimerStopResult {
  const TimerDiscarded();
}

/// The outcome of a write that can meet a boolean tracker's once-per-day
/// rule: an edit that moves an entry to another day, or an undo that restores
/// one.
enum DayWrite { written, dayAlreadyDone }
