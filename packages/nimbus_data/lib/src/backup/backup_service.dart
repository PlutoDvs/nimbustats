import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:sqlite3/sqlite3.dart';
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
    required this._livePath,
    required this.cacheDir,
    required this._preRestorePath,
    this._kdf = KdfParams.standard,
    this._clock = DateTime.now,
    this._busyTimeout = const Duration(milliseconds: 50),
  });

  final AppDatabase _db;
  final String _livePath;
  final String _preRestorePath;
  final KdfParams _kdf;
  final DateTime Function() _clock;

  /// How long each attempt of the swap blocks for a writer, such as the
  /// widget's drain engine, to release the database.
  ///
  /// Short, because Dart runs on Android's main thread here, and a long block
  /// is an ANR. `sqlite3` retries every 250 ms asynchronously until it holds
  /// the lock, and the swap remains one transaction.
  final Duration _busyTimeout;

  /// Where plaintext temp files live. Android leaves the cache out of Auto
  /// Backup.
  final String cacheDir;

  static const _uuid = Uuid();
  static const _tempPrefixes = ['export-', 'import-', 'picked-'];

  /// The undo copy while it is being written. It is renamed into place only
  /// after a swap succeeds (ruling R4).
  String get _partPath => '$_preRestorePath.part';

  /// Whether an undo copy exists: the last restore can be undone.
  bool get canUndo => File(_preRestorePath).existsSync();

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

  /// Swaps [prepared]'s content into the live database (spec §3.2 step 3).
  Future<void> restore(PreparedRestore prepared) => _swapIn(prepared.path);

  /// Swaps the live data with the undo copy. It never destroys data: the copy
  /// then holds what the undo replaced, so another undo puts that back.
  ///
  /// The copy is staged in the cache and brought to today's schema first, as
  /// an app update may have come between the restore and this undo. On any
  /// failure the live data and the copy stay as they were.
  Future<void> undo() async {
    final staged = _temp('import');
    try {
      await File(_preRestorePath).copy(staged);
      await _migrateAndCheck(staged);
    } on Object {
      await _deleteDatabase(staged);
      rethrow;
    }
    await _swapIn(staged);
  }

  /// Copies the live content aside as the next undo copy, then swaps
  /// [staged] in and deletes it.
  ///
  /// The swap is SQLite's online backup, one write transaction that commits
  /// whole or rolls back, so the drain engine's connection never sees half of
  /// it. Only a swap that happened replaces the previous undo copy (R4), and
  /// once it has, the copy and the streams are settled before the cleanup
  /// that may still fail.
  Future<void> _swapIn(String staged) async {
    try {
      await _delete(_partPath);
      await _db.customStatement('VACUUM INTO ?', [_partPath]);
      await _copyInto(staged);
    } on Object {
      await _delete(_partPath);
      await _deleteDatabase(staged);
      rethrow;
    }
    await File(_partPath).rename(_preRestorePath);
    _notifyAll();
    await _deleteDatabase(staged);
  }

  /// The database's size as Auto Backup will copy it, after the agent's
  /// checkpoint has emptied the WAL into the file (spec §4.3).
  Future<int> databaseBytes() async =>
      await _pragma(_db, 'page_count') * await _pragma(_db, 'page_size');

  /// Deletes plaintext a crash left behind mid-export or mid-restore (spec
  /// §3.3). Finished exports in `out/` stay: a share target may still be
  /// reading the latest.
  Future<void> sweep() async {
    final dir = Directory(cacheDir);
    if (dir.existsSync()) {
      for (final file in dir.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (_tempPrefixes.any(name.startsWith)) await file.delete();
      }
    }
    await _delete(_partPath);
  }

  /// SQLite's online backup from [source] onto the live file.
  ///
  /// `sqlite3` retries a busy lock every 250 ms until it gets it. With
  /// `nPage: -1` it writes nothing before then, so a concurrent writer delays
  /// the swap and never splits it (ruling R1).
  Future<void> _copyInto(String source) async {
    final from = sqlite3.open(source, mode: OpenMode.readOnly);
    try {
      // readWrite, not create: a wrong livePath must fail, not make a new file.
      final to = sqlite3.open(_livePath, mode: OpenMode.readWrite);
      try {
        to.execute('PRAGMA busy_timeout = ${_busyTimeout.inMilliseconds}');
        await from.backup(to, nPage: -1).drain<void>();
      } finally {
        to.close();
      }
    } finally {
      from.close();
    }
  }

  /// Every table changed underneath drift. Its open streams re-read, and
  /// none keeps a cached value from before the swap.
  void _notifyAll() => _db.notifyUpdates(
      {for (final table in _db.allTables) TableUpdate.onTable(table)});

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
