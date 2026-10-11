import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';

/// Runs a goal write. If it fails, it says so and rethrows.
///
/// This is the rule the saved-view and tracker writes follow. A failed local
/// write is rare, but when it happens the user hears about it instead of
/// watching a tap do nothing, and the error still reaches the framework's
/// error handler. It takes its dependencies rather than a context, so it can
/// finish after the widget that started it is gone.
Future<void> reportingGoalFailure({
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required Future<void> Function() write,
}) async {
  try {
    await write();
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(l10n.goalsWriteFailed)));
    rethrow;
  }
}

/// Deletes the goal [id], then offers to undo it (screen contract §1.3:
/// undo, never confirm). The undo restores and re-baselines, so the goal
/// does not alert about a crossing made while it was gone.
Future<void> deleteGoalWithUndo({
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required GoalService service,
  required String id,
}) async {
  await reportingGoalFailure(
      messenger: messenger, l10n: l10n, write: () => service.delete(id));
  messenger.showSnackBar(nimbusUndoSnackBar(
    message: l10n.goalsDeleted,
    undoLabel: l10n.commonUndo,
    onUndo: () => unawaited(reportingGoalFailure(
        messenger: messenger, l10n: l10n, write: () => service.restore(id))),
  ));
}
