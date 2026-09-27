import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/saved_views_repository.dart';
import 'saved_view_write.dart';
import 'view_name_sheet.dart';

/// Removes [id] and offers undo.
///
/// Takes its dependencies rather than a context, so it can run after the
/// screen that asked has already closed.
Future<void> removeSavedView({
  required SavedViewsRepository repository,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required String id,
}) async {
  await reportingFailure(
    messenger: messenger,
    l10n: l10n,
    write: () => repository.remove(id),
  );
  // Undo, never confirm (screen contract §1.3).
  messenger.showSnackBar(nimbusUndoSnackBar(
    message: l10n.viewRemoved,
    undoLabel: l10n.commonUndo,
    onUndo: () => reportingFailure(
      messenger: messenger,
      l10n: l10n,
      write: () => repository.restore(id),
    ),
  ));
}

/// Asks for a new name and saves it; dismissing changes nothing.
Future<void> renameSavedView(
  BuildContext context, {
  required SavedViewsRepository repository,
  required String id,
  required String currentName,
}) async {
  final l10n = AppLocalizations.of(context);
  // Read before the sheet opens: the sheet's own await must not leave this
  // resolving a messenger from a context that has since been disposed.
  final messenger = ScaffoldMessenger.of(context);
  final name = await showViewNameSheet(
    context,
    title: l10n.renameView,
    initialName: currentName,
  );
  if (name == null) return;
  await reportingFailure(
    messenger: messenger,
    l10n: l10n,
    write: () => repository.rename(id, name),
  );
}
