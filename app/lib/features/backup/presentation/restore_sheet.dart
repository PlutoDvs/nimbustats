import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/application/settings_providers.dart';
import '../application/backup_controller.dart';
import 'backup_messages.dart';
import 'backup_sheet_parts.dart';

/// Restore, in one sheet (spec §5.3): which backup, what restoring does, the
/// passphrase, and then the work.
///
/// Its button is the commitment. Undo follows the restore instead of a
/// confirmation preceding it ("undo, never confirm", ruling R2).
class RestoreSheet extends ConsumerStatefulWidget {
  const RestoreSheet({super.key, required this.picked});

  final PickedBackup picked;

  @override
  ConsumerState<RestoreSheet> createState() => _RestoreSheetState();
}

class _RestoreSheetState extends ConsumerState<RestoreSheet> {
  final _passphrase = TextEditingController();
  var _working = false;

  /// A wrong passphrase, under the field. The sheet stays, to try again.
  String? _wrong;

  /// Any other failure. Only closing is left.
  String? _failed;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    if (_working) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _working = true;
      _wrong = null;
    });
    try {
      // On success the app restarts onto the restored data, and this sheet
      // goes with it.
      await ref
          .read(backupControllerProvider)
          .restore(widget.picked, _passphrase.text);
    } on WrongPassphrase {
      if (!mounted) return;
      setState(() {
        _working = false;
        _wrong = l10n.backupWrongPassphrase;
      });
    } on Object catch (error, stack) {
      final text = backupErrorText(l10n, error);
      if (text == null) reportBackupFailure(error, stack, 'while restoring a backup');
      if (!mounted) return;
      setState(() {
        _working = false;
        _failed = text ?? l10n.backupRestoreFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final when = whenLabel(widget.picked.header.createdAt, ref.watch(calendarProvider),
        persianDigits: ref.watch(moneyFormatterProvider).persianDigits);
    final open = !_working && _failed == null;
    return PopScope(
      // Not mid-swap: closing would not stop it, only hide its outcome.
      canPop: !_working,
      child: BackupSheetFrame(
        title: l10n.backupRestore,
        children: [
          Text(l10n.backupRestoreFrom(when), key: const Key('backup-restore-from')),
          Text(l10n.backupRestoreReplaces),
          PassphraseField(
            key: const Key('backup-restore-passphrase'),
            controller: _passphrase,
            label: l10n.backupPassphrase,
            error: _wrong,
            enabled: open,
          ),
          if (_working) BackupProgress(label: l10n.backupDecrypting),
          if (_failed case final failed?) BackupSheetError(failed),
          FilledButton(
            key: const Key('backup-restore-go'),
            onPressed: open ? () => unawaited(_restore()) : null,
            child: Text(l10n.backupRestoreAction),
          ),
        ],
      ),
    );
  }
}
