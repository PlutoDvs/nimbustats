import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../../l10n/app_localizations.dart';
import '../application/backup_controller.dart';
import 'backup_messages.dart';
import 'backup_sheet_parts.dart';

/// Export, in one sheet (spec §5.2): the passphrase twice, the work, then
/// where the file goes. Steps of a sheet rather than dialogs (ruling R2):
/// "undo, never confirm" keeps dialogs out of the app.
class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key});

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

enum _Step { passphrase, working, destination }

class _ExportSheetState extends ConsumerState<ExportSheet> {
  final _passphrase = TextEditingController();
  final _repeat = TextEditingController();
  var _step = _Step.passphrase;
  String? _error;
  String? _path;

  @override
  void dispose() {
    _passphrase.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _encrypt() async {
    final l10n = AppLocalizations.of(context);
    final passphrase = _passphrase.text;
    final problem = passphrase.runes.length < minPassphraseRunes
        ? l10n.backupPassphraseTooShort
        // Compared as the key derivation will see them, so the two entries
        // may use different digit sets.
        : normalizePassphrase(passphrase) != normalizePassphrase(_repeat.text)
            ? l10n.backupPassphraseMismatch
            : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _step = _Step.working;
      _error = null;
    });
    try {
      final path = await ref.read(backupControllerProvider).export(passphrase);
      if (!mounted) return;
      setState(() {
        _path = path;
        _step = _Step.destination;
      });
    } on Object catch (error, stack) {
      reportBackupFailure(error, stack, 'while exporting');
      if (!mounted) return;
      setState(() {
        _step = _Step.passphrase;
        _error = l10n.backupExportFailed;
      });
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // False: the picker was cancelled. Not an error, so the choice stays.
      if (!await ref.read(backupControllerProvider).save(_path!)) return;
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupSaved)));
    } on Object catch (error, stack) {
      reportBackupFailure(error, stack, 'while saving a backup');
      if (mounted) setState(() => _error = l10n.backupSaveFailed);
    }
  }

  Future<void> _share() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(backupControllerProvider).share(_path!);
      navigator.pop();
    } on Object catch (error, stack) {
      reportBackupFailure(error, stack, 'while sharing a backup');
      if (mounted) setState(() => _error = l10n.backupShareFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final working = _step == _Step.working;
    return PopScope(
      // Not while the file is being written: closing would orphan the work.
      canPop: !working,
      child: BackupSheetFrame(
        title: l10n.backupExport,
        children: switch (_step) {
          _Step.destination => [
              Text(l10n.backupChooseDestination),
              ListTile(
                key: const Key('backup-save'),
                leading: const Icon(Icons.save_alt),
                title: Text(l10n.backupSave),
                onTap: () => unawaited(_save()),
              ),
              ListTile(
                key: const Key('backup-share'),
                leading: const Icon(Icons.share_outlined),
                title: Text(l10n.backupShare),
                onTap: () => unawaited(_share()),
              ),
              if (_error != null)
                Text(_error!,
                    key: const Key('backup-sheet-error'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          _Step.passphrase || _Step.working => [
              PassphraseField(
                key: const Key('backup-passphrase'),
                controller: _passphrase,
                label: l10n.backupPassphrase,
                helper: l10n.backupPassphraseHint,
                enabled: !working,
              ),
              PassphraseField(
                key: const Key('backup-passphrase-repeat'),
                controller: _repeat,
                label: l10n.backupPassphraseRepeat,
                error: _error,
                enabled: !working,
              ),
              if (working) BackupProgress(label: l10n.backupEncrypting),
              FilledButton(
                key: const Key('backup-encrypt'),
                onPressed: working ? null : () => unawaited(_encrypt()),
                child: Text(l10n.backupExportAction),
              ),
            ],
        },
      ),
    );
  }
}
