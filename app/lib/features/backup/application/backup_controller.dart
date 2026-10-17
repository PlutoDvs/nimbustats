import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:path/path.dart' as p;

import '../../notifications/application/outside_errors.dart';
import '../data/backup_channel.dart';
import '../data/backup_state_store.dart';
import 'backup_providers.dart';
import 'restart.dart';

/// A backup the user picked for restore: copied into the cache, its header
/// read.
typedef PickedBackup = ({String path, BackupHeader header});

/// The backup section's actions (spec §5).
///
/// Each one throws what went wrong. The sheets map the error to a message.
final class BackupController {
  BackupController(this._ref);

  final Ref _ref;

  Future<BackupService> get _service => _ref.read(backupServiceProvider.future);
  BackupChannel get _channel => _ref.read(backupChannelProvider);
  BackupStateStore get _store => _ref.read(backupStateStoreProvider);

  /// Deletes plaintext a crash left in the cache (spec §3.3).
  Future<void> sweep() async => (await _service).sweep();

  /// A fresh export in the cache's `out/` folder, the one Share may serve.
  /// Only the latest is kept.
  Future<String> export(String passphrase) async {
    final service = await _service;
    final out = Directory(p.join(service.cacheDir, 'out'));
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);
    final path = p.join(out.path, backupFileName(DateTime.now()));
    await service.exportTo(path, passphrase);
    return path;
  }

  /// False when the user cancelled the picker, which is not an error.
  Future<bool> save(String path) async {
    final saved = await _channel.saveDocument(path);
    if (saved) await _recordExport();
    return saved;
  }

  Future<void> share(String path) async {
    await _channel.shareFile(path);
    await _recordExport();
  }

  /// Null when the picker was cancelled. A header error (not a backup, a
  /// newer schema…) deletes the copy and rethrows.
  Future<PickedBackup?> pick() async {
    final path = await _channel.openDocument();
    if (path == null) return null;
    try {
      return (path: path, header: await (await _service).readHeader(path));
    } on Object {
      discard(path);
      rethrow;
    }
  }

  /// Decrypts, checks and swaps in [picked], then restarts the app onto it.
  ///
  /// [WrongPassphrase] keeps the copy, so the sheet can ask again. Once the
  /// swap happened, a failure after it is reported and the app still
  /// restarts onto the restored data.
  Future<void> restore(PickedBackup picked, String passphrase) async {
    final service = await _service;
    final prepared = await service.prepare(picked.path, passphrase);
    await service.restore(prepared);
    await reportingFailure('backup', 'while recording a restore',
        () async => _store.setUndoRedoes(false));
    await reportingFailure('backup', 'while deleting a restored backup file',
        () async => discard(picked.path));
    _ref.read(appRestartProvider)(BackupRestored(picked.header.createdAt));
  }

  /// Deletes a picked copy that will not be restored.
  ///
  /// Synchronous: one small file. An async delete would also never complete
  /// inside a widget test's fake clock.
  void discard(String picked) {
    final file = File(picked);
    if (file.existsSync()) file.deleteSync();
  }

  /// Swaps the live data with the undo copy, then restarts the app onto it.
  /// After an undo the copy holds what it replaced, so the next one redoes.
  Future<void> undo() async {
    final wasRedo = _store.undoRedoes();
    await (await _service).undo();
    // The swap happened: a failure recording it must not hide that.
    await reportingFailure('backup', 'while recording an undo',
        () async => _store.setUndoRedoes(!wasRedo));
    _ref.read(appRestartProvider)(
        wasRedo ? const RestoreRedone() : const RestoreUndone());
  }

  /// The hand-off already happened: a failure recording it is reported and
  /// does not turn it into a failed Save or Share.
  Future<void> _recordExport() async {
    await reportingFailure('backup', 'while recording an export',
        () async => _store.recordExport(DateTime.now().toUtc()));
    _ref.invalidate(backupStatusProvider);
  }
}

final backupControllerProvider =
    Provider<BackupController>(BackupController.new);
