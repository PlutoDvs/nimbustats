import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// Runs a saved-view write; if it fails, says so and rethrows.
///
/// The rule the add-expense screen follows: a failed local write is rare,
/// but when it happens the user hears about it instead of watching a tap do
/// nothing, and the error still reaches the framework's error handler.
/// Takes its dependencies rather than a context, so it can run after the
/// widget that started it is gone.
Future<void> reportingFailure({
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required Future<void> Function() write,
}) async {
  try {
    await write();
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(l10n.savedViewSaveFailed)));
    rethrow;
  }
}
