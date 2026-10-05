import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// Runs a tracker write. If it fails, says so and rethrows.
///
/// The rule the saved-view writes follow: a failed local write is rare, but
/// when it happens the user hears about it instead of watching a tap do
/// nothing, and the error still reaches the framework's error handler.
///
/// Takes its dependencies rather than a context, so it can finish after the
/// widget that started it is gone.
Future<T> reportingTrackerFailure<T>({
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required Future<T> Function() write,
}) async {
  try {
    return await write();
  } on Object {
    // Replaces whatever is up -- typically the last tap's undo bar -- rather
    // than queueing behind it, where a failure would go unseen.
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.trackerWriteFailed)));
    rethrow;
  }
}
