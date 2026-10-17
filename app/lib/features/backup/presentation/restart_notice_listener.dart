import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/application/settings_providers.dart';
import '../application/backup_controller.dart';
import '../application/restart.dart';
import 'backup_messages.dart';

/// Shows, once, why the app just restarted (spec §5.3): a restore, an undone
/// restore or a redone one, each with Undo.
///
/// It wraps the shell's body, under the shell's Scaffold, so it is up
/// whenever Home is.
class RestartNoticeListener extends ConsumerStatefulWidget {
  const RestartNoticeListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RestartNoticeListener> createState() =>
      _RestartNoticeListenerState();
}

class _RestartNoticeListenerState extends ConsumerState<RestartNoticeListener> {
  RestartNotice? _pending;

  @override
  void initState() {
    super.initState();
    _pending = ref.read(restartNoticeProvider);
    if (_pending == null) return;
    // After the restored settings load (ruling R12): the message speaks
    // their language and calendar, not the defaults'.
    ref.listenManual(settingsProvider, (_, next) {
      if (next.hasValue || next.hasError) _showOnce();
    }, fireImmediately: true);
  }

  void _showOnce() {
    final notice = _pending;
    if (notice == null) return;
    _pending = null;
    // After the frame that applies the restored locale.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final messenger = ScaffoldMessenger.of(context);
      // Every swap can be swapped back, so each notice offers Undo.
      messenger.showSnackBar(nimbusUndoSnackBar(
        message: switch (notice) {
          BackupRestored(:final backupCreatedAt) => l10n.backupRestored(
              whenLabel(backupCreatedAt, ref.read(calendarProvider),
                  persianDigits: ref.read(moneyFormatterProvider).persianDigits)),
          RestoreUndone() => l10n.backupRestoreUndone,
          RestoreRedone() => l10n.backupRestoreRedone,
        },
        undoLabel: l10n.commonUndo,
        onUndo: () => unawaited(_undo(messenger, l10n)),
      ));
    });
  }

  Future<void> _undo(
      ScaffoldMessengerState messenger, AppLocalizations l10n) async {
    try {
      await ref.read(backupControllerProvider).undo();
    } on Object catch (error, stack) {
      reportBackupFailure(error, stack, 'while undoing a restore');
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupUndoFailed)));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
