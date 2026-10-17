import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'backup_crypto.dart';
import 'backup_errors.dart';
import 'backup_format.dart';

/// A decrypted, migrated and checked backup, waiting in the cache for
/// [BackupService.restore] (spec §3.2).
final class PreparedRestore {
  const PreparedRestore({required this.path, required this.createdAt});

  final String path;

  /// When the backup was made, for the restore sheet and its snackbar.
  final DateTime createdAt;
}

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

  /// Decrypts [path] into the cache, brings it to today's schema and checks
  /// it. The live database is not touched (spec §3.2).
  ///
  /// On any failure the decrypted file is deleted before the error leaves.
  Future<PreparedRestore> prepare(String path, String passphrase) async {
    final header = await readHeader(path);
    final temp = _temp('import');
    try {
      await _unseal(path, temp, passphrase);
      await _migrateAndCheck(temp);
      return PreparedRestore(path: temp, createdAt: header.createdAt);
    } on Object {
      await _deleteDatabase(temp);
      rethrow;
    }
  }

  /// Deletes a prepared file the user decided not to restore.
  Future<void> discard(PreparedRestore prepared) =>
      _deleteDatabase(prepared.path);

  /// Opens [path] once through [AppDatabase.openAtPath], so an older backup
  /// runs the same migrations every install runs, and then checks it.
  ///
  /// A failure while opening or migrating is left as it is (ruling R8). The
  /// content passed authentication, so such a failure is a bug, not damage.
  /// In debug builds drift warns about a second AppDatabase. This one has its
  /// own file and executor, which is not the race that warning is about.
  Future<void> _migrateAndCheck(String path) async {
    final imported = AppDatabase.openAtPath(path);
    try {
      final check = await imported.customSelect('PRAGMA integrity_check').get();
      if (check.length != 1 || check.single.data.values.single != 'ok') {
        throw const CorruptBackup('integrity check failed');
      }
      // SQLite's backup cannot copy into a WAL database of another page size.
      if (await _pragma(imported, 'page_size') != await _pragma(_db, 'page_size')) {
        throw const CorruptBackup('page size differs');
      }
    } finally {
      await imported.close();
    }
  }

  static Future<int> _pragma(AppDatabase db, String name) async =>
      (await db.customSelect('PRAGMA $name').getSingle()).data.values.single
          as int;

  static Future<void> _deleteDatabase(String path) async {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      await _delete('$path$suffix');
    }
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

/// Opens the backup at [backupPath] and writes its database to [outPath], in
/// an isolate (spec §3.2).
///
/// Throws [WrongPassphrase] or [CorruptBackup] before writing anything.
Future<void> _unseal(String backupPath, String outPath, String passphrase) =>
    Isolate.run(() async {
      // shortcut: whole file in memory, upgrade to chunked encryption when a database passes ~50 MB
      final file = File(backupPath).readAsBytesSync();
      final payload = await openBackup(file, passphrase);
      final List<int> plain;
      try {
        plain = gzip.decode(payload);
      } on FormatException {
        throw const CorruptBackup('payload is not gzip');
      }
      if (!_isSqlite(plain) ||
          _userVersion(plain) != BackupHeader.decode(file).schemaVersion) {
        throw const CorruptBackup('payload does not match its header');
      }
      File(outPath).writeAsBytesSync(plain, flush: true);
    });

bool _isSqlite(List<int> bytes) =>
    bytes.length >= 100 &&
    String.fromCharCodes(bytes.sublist(0, 16)) == 'SQLite format 3\u0000';
