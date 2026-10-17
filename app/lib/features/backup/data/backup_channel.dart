import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dart's half of `com.nimbustats.app/backup` (Phase 7 spec §6): Save to…,
/// Share… and opening a file, all through Android's own pickers.
///
/// Every test replaces it with `FakeBackupChannel`. An I/O failure arrives as
/// a [PlatformException], never as a quiet null.
class BackupChannel {
  BackupChannel([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel(name);

  static const name = 'com.nimbustats.app/backup';

  final MethodChannel _channel;

  /// Copies [path] into a document the user creates. False when they
  /// cancelled the picker.
  Future<bool> saveDocument(String path) async {
    final saved =
        await _channel.invokeMethod<bool>('saveDocument', {'path': path});
    if (saved == null) {
      throw PlatformException(
          code: 'null-reply', message: 'saveDocument answered null');
    }
    return saved;
  }

  /// Opens the share sheet on [path], which must be in the cache's
  /// `backup/out/` folder: the only one `FileProvider` serves.
  Future<void> shareFile(String path) =>
      _channel.invokeMethod<void>('shareFile', {'path': path});

  /// The file the user picked, copied into the cache. Null when they
  /// cancelled.
  Future<String?> openDocument() =>
      _channel.invokeMethod<String>('openDocument');
}

final backupChannelProvider = Provider<BackupChannel>((ref) => BackupChannel());
