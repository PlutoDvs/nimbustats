import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:path/path.dart' as p;

import '../data/backup_channel.dart';
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
    if (saved) _recordExport();
    return saved;
  }

  Future<void> share(String path) async {
    await _channel.shareFile(path);
    _recordExport();
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
  /// [WrongPassphrase] keeps the copy, so the sheet can ask again.
  Future<void> restore(PickedBackup picked, String passphrase) async {
    final service = await _service;
    final prepared = await service.prepare(picked.path, passphrase);
    await service.restore(prepared);
    discard(picked.path);
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

  Future<void> undo() async {
    await (await _service).undo();
    _ref.read(appRestartProvider)(const RestoreUndone());
  }

  void _recordExport() {
    _ref.read(backupStateStoreProvider).recordExport(DateTime.now().toUtc());
    _ref.invalidate(backupStatusProvider);
  }
}

final backupControllerProvider =
    Provider<BackupController>(BackupController.new);
