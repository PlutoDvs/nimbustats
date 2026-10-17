import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../notifications/application/outside_errors.dart';
import '../../settings/application/settings_providers.dart';
import '../application/backup_controller.dart';
import '../application/backup_providers.dart';
import 'backup_messages.dart';
import 'export_sheet.dart';
import 'restore_sheet.dart';

/// The settings screen's "Backup" section (spec §5.1).
///
/// It shows:
/// - when the last export was handed off;
/// - Export and Restore;
/// - Undo, while an undo copy exists;
/// - the warning near Auto Backup's cap (ruling R7);
/// - what a backup holds.
///
/// States: loading, error, empty (never exported) and populated.
class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  Object? _reportedError;

  @override
  void initState() {
    super.initState();
    // A crash mid-export or mid-restore leaves plaintext in the cache (spec
    // §3.3). Nothing is in flight here: each flow is a modal sheet that
    // blocks navigation while it works.
    unawaited(reportingFailure('backup', 'while sweeping stale backup files',
        ref.read(backupControllerProvider).sweep));
  }

  // Both sheets go on the root navigator, over the shell's navigation bar:
  // from inside the shell, a tap on the bar would swap the page under a
  // working sheet and take the sheet with it.
  Future<void> _export() => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        enableDrag: false,
        builder: (_) => const ExportSheet(),
      );

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(backupControllerProvider);
    final PickedBackup? picked;
    try {
      picked = await controller.pick();
    } on Object catch (error, stack) {
      final text = backupErrorText(l10n, error);
      if (text == null) reportBackupFailure(error, stack, 'while opening a backup file');
      messenger.showSnackBar(SnackBar(content: Text(text ?? l10n.backupRestoreFailed)));
      return;
    }
    if (picked == null) return;
    final chosen = picked;
    if (mounted) {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        enableDrag: false,
        builder: (_) => RestoreSheet(picked: chosen),
      );
    }
    // Reached when the sheet closed without restoring. A restore restarts
    // the app instead, and has deleted the copy already.
    await reportingFailure('backup', 'while deleting a picked backup',
        () async => controller.discard(chosen.path));
  }

  Future<void> _undo() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(backupControllerProvider).undo();
    } on Object catch (error, stack) {
      reportBackupFailure(error, stack, 'while undoing a restore');
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupUndoFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Once per error: a refresh keeps the old one while it loads, and a
    // retry that fails again brings a new one.
    ref.listen(backupStatusProvider, (_, next) {
      if (next.hasError && !identical(next.error, _reportedError)) {
        _reportedError = next.error;
        reportBackupFailure(next.error!, next.stackTrace ?? StackTrace.empty,
            'while reading the backup status');
      }
    });
    final status = ref.watch(backupStatusProvider);

    final Widget body;
    if (!status.hasError && !status.hasValue) {
      body = const SizedBox(
        key: Key('backup-loading'),
        height: 3 * 72,
        child: NimbusLoadingList(rows: 3),
      );
    } else {
      body = _rows(context, l10n, status);
    }

    return Column(
      key: const Key('backup-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              NimbusTokens.space4, NimbusTokens.space4, NimbusTokens.space4, 0),
          child: Text(l10n.backupTitle,
              style: Theme.of(context).textTheme.titleSmall),
        ),
        body,
      ],
    );
  }

  /// The section's rows. A status that did not read is an error in place of
  /// the rows that need it; Export and Restore need none of it (M5).
  Widget _rows(BuildContext context, AppLocalizations l10n,
      AsyncValue<BackupStatus> async) {
    final small = Theme.of(context).textTheme.bodySmall;
    final status = async.hasError ? null : async.requireValue;
    final last = status?.lastExport;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == null)
          NimbusErrorState(
            key: const Key('backup-error'),
            title: l10n.backupLoadFailed,
            retryLabel: l10n.commonRetry,
            detail: async.error.toString(),
            onRetry: () => ref.invalidate(backupStatusProvider),
          )
        else ...[
          ListTile(
            key: const Key('backup-last-export'),
            leading: const Icon(Icons.history),
            title: Text(last == null
                ? l10n.backupNeverExported
                : l10n.backupLastExport(whenLabel(last, ref.watch(calendarProvider),
                    persianDigits: ref.watch(moneyFormatterProvider).persianDigits))),
          ),
          if (status.databaseBytes > autoBackupWarnBytes)
            ListTile(
              key: const Key('backup-size-warning'),
              leading: const Icon(Icons.warning_amber_outlined),
              title: Text(l10n.backupSizeWarning),
            ),
        ],
        ListTile(
          key: const Key('backup-export'),
          leading: const Icon(Icons.upload_file_outlined),
          title: Text(l10n.backupExport),
          onTap: () => unawaited(_export()),
        ),
        ListTile(
          key: const Key('backup-restore'),
          leading: const Icon(Icons.settings_backup_restore),
          title: Text(l10n.backupRestore),
          onTap: () => unawaited(_restore()),
        ),
        if (status != null && status.canUndo)
          ListTile(
            key: const Key('backup-undo'),
            leading: const Icon(Icons.undo),
            title: Text(status.undoRedoes
                ? l10n.backupRedoRestore
                : l10n.backupUndoRestore),
            onTap: () => unawaited(_undo()),
          ),
        Padding(
          padding: const EdgeInsets.all(NimbusTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: NimbusTokens.space2,
            children: [
              Text(l10n.backupIncluded, style: small),
              Text(l10n.backupNotIncluded, style: small),
              Text(l10n.backupForgottenPassphrase, style: small),
            ],
          ),
        ),
      ],
    );
  }
}
