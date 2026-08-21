import 'package:flutter/material.dart';

import '../tokens.dart';

/// The app's one destructive-action affordance.
///
/// "Undo, never confirm" is an interaction rule, so there is deliberately no
/// confirmation-dialog counterpart to this function anywhere in the codebase --
/// `app/test/ux_rules_test.dart` asserts that none appears.
SnackBar nimbusUndoSnackBar({
  required String message,
  required String undoLabel,
  required VoidCallback onUndo,
  Duration duration = const Duration(seconds: 5),
}) =>
    SnackBar(
      content: Text(message),
      duration: duration,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(NimbusTokens.space4),
      action: SnackBarAction(label: undoLabel, onPressed: onUndo),
    );
