import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'backup_crypto.dart';
import 'backup_errors.dart';
import 'backup_format.dart';

/// Export and restore of the whole database file (Phase 7 spec §3).
///
/// It treats the database as one file and never names a table, so a phase
/// that adds tables needs nothing here. The app injects every path.
class BackupService {
  BackupService({
    required this._db,
    required this.cacheDir,
    this._kdf = KdfParams.standard,
    this._clock = DateTime.now,
  });

  final AppDatabase _db;
  final KdfParams _kdf;
  final DateTime Function() _clock;

  /// Where plaintext temp files live. Android leaves the cache out of Auto
  /// Backup.
  final String cacheDir;

  static const _uuid = Uuid();

  /// Writes an encrypted export of the live database to [outPath].
  Future<void> exportTo(String outPath, String passphrase) async {
    final snapshot = _temp('export');
    try {
      // A consistent single-file copy holding every committed WAL frame,
      // taken while the drain engine stays connected. It replaces the
      // brief's "checkpoint, then copy" (spec, departures).
      await _db.customStatement('VACUUM INTO ?', [snapshot]);
      await _seal(snapshot, outPath, passphrase, _clock().toUtc(), _kdf);
    } finally {
      await _delete(snapshot);
    }
  }

  /// The header of the file at [path]. A newer schema is refused here,
  /// before any passphrase is asked for (spec §2.4).
  Future<BackupHeader> readHeader(String path) async {
    final file = await File(path).open();
    final Uint8List head;
    try {
      head = await file.read(BackupHeader.length);
    } finally {
      await file.close();
    }
    final header = BackupHeader.decode(head);
    if (header.schemaVersion > _db.schemaVersion) {
      throw NewerSchema(backup: header.schemaVersion, app: _db.schemaVersion);
    }
    return header;
  }

  String _temp(String kind) {
    Directory(cacheDir).createSync(recursive: true);
    return '$cacheDir${Platform.pathSeparator}$kind-${_uuid.v4()}.sqlite';
  }

  static Future<void> _delete(String path) async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }
}

/// Reads the snapshot, gzips and seals it, and writes [outPath], in an
/// isolate so that Argon2id and AES never block the UI (spec §3.1).
///
/// A top-level function, so that the closure captures only its arguments.
Future<void> _seal(String snapshot, String outPath, String passphrase,
        DateTime createdAt, KdfParams kdf) =>
    Isolate.run(() async {
      // shortcut: whole file in memory, upgrade to chunked encryption when a database passes ~50 MB
      final plain = File(snapshot).readAsBytesSync();
      final sealed = await sealBackup(
        payload: gzip.encode(plain),
        passphrase: passphrase,
        schemaVersion: _userVersion(plain),
        createdAt: createdAt,
        kdf: kdf,
      );
      File(outPath).writeAsBytesSync(sealed, flush: true);
    });

/// `PRAGMA user_version`, read from a database file's header: offset 60,
/// big-endian.
int _userVersion(List<int> database) =>
    ByteData.sublistView(Uint8List.fromList(database.sublist(60, 64)))
        .getUint32(0);
