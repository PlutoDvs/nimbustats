import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../data/tracker_repository.dart';
import 'tracker_write.dart';

/// What a tap on a tracker does, wherever it happens: the tab or the detail
/// screen's quick-log bar.
///
/// Holds its dependencies rather than a BuildContext. The write and its
/// snackbar finish after the frame that started them, and the widget may be
/// gone by then.
final class TrackerLogger {
  const TrackerLogger({
    required this.messenger,
    required this.l10n,
    required this.repository,
    required this.format,
    required this.tracker,
  });

  final ScaffoldMessengerState messenger;
  final AppLocalizations l10n;
  final TrackerRepository repository;
  final TrackerFormat format;
  final Tracker tracker;

  /// Logs one tap, or [value] as a custom amount, and says so with an undo.
  ///
  /// The haptic fires before the write. Logging is optimistic, and for a
  /// one-tap counter the haptic is the whole of the feedback (brief trap).
  Future<void> log({double? value}) async {
    unawaited(tracker.type == TrackerType.boolean
        ? HapticFeedback.mediumImpact()
        : HapticFeedback.lightImpact());
    final result =
        await _write(() => repository.logEntry(tracker.id, value: value));
    switch (result) {
      case EntryLogged(:final entry):
        final total = await repository.totalOn(tracker.id, entry.localDateKey);
        _showUndo(
          tracker.type == TrackerType.boolean
              ? l10n.trackerMarkedDone(tracker.name)
              : l10n.trackerLoggedToday(
                  tracker.name, format.total(tracker, total)),
          () => repository.deleteEntry(entry.id),
        );
      case AlreadyDoneToday():
        // A double-tap on "done". The first tap's entry already holds the
        // day, and the tile shows it.
        break;
    }
  }

  /// A boolean tracker's tap: done when it is not, not done when it is.
  Future<void> toggleDone({required bool done}) async {
    if (!done) return log();
    unawaited(HapticFeedback.mediumImpact());
    final cleared = await _write(() => repository.clearToday(tracker.id));
    _showUndo(
      l10n.trackerMarkedNotDone(tracker.name),
      // DayWrite.dayAlreadyDone here means the day was marked done again in
      // the meantime, which is what the undo wanted anyway.
      () => repository.restoreEntries(cleared),
    );
  }

  /// A duration tracker's tap: start when idle, stop when running.
  ///
  /// Start says nothing more: the tile turns into a ticking timer, which is
  /// the confirmation. Stop names the session it logged rather than today's
  /// total. The entry is stamped at the start, so it can belong to yesterday,
  /// and "today" would then be false.
  Future<void> toggleTimer() async {
    unawaited(HapticFeedback.mediumImpact());
    if (tracker.runningTimer == null) {
      // TimerAlreadyRunning is the second tap of a double-tap; the stored
      // start is already on screen either way.
      await _write(() => repository.startTimer(tracker.id));
      return;
    }
    final result = await _write(() => repository.stopTimer(tracker.id));
    switch (result) {
      case TimerStopped(:final entry):
        _showUndo(
          l10n.trackerTimerLogged(tracker.name,
              format.duration(TrackerValues.durationOf(entry.value))),
          () => repository.deleteEntry(entry.id),
        );
      case TimerDiscarded():
        messenger
          ..removeCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.trackerTimerDiscarded)));
      case TimerNotRunning():
        // The second tap of a double-tap on stop; the first logged it.
        break;
    }
  }

  Future<T> _write<T>(Future<T> Function() write) =>
      reportingTrackerFailure(messenger: messenger, l10n: l10n, write: write);

  /// Shows [message] with an undo, replacing whatever snackbar is up, so
  /// rapid taps leave one snackbar with the latest total rather than a queue.
  void _showUndo(String message, Future<Object?> Function() undo) {
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(nimbusUndoSnackBar(
        message: message,
        undoLabel: l10n.commonUndo,
        onUndo: () => unawaited(_write(undo)),
      ));
  }
}
