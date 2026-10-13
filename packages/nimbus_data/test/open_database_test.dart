import 'dart:io';
import 'dart:isolate';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

void main() {
  test('openInMemory returns a usable database', () async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    // A read against a real table proves the schema was created, not merely
    // that a connection object exists.
    expect(await db.settingsDao.get('absent'), isNull);
  });

  test('two in-memory databases do not share rows', () async {
    // Every test gets its own connection, so tests never leak into each other
    // and can run in any order.
    final a = AppDatabase.openInMemory();
    final b = AppDatabase.openInMemory();
    addTearDown(a.close);
    addTearDown(b.close);

    await a.settingsDao.put('key', 'from-a');
    expect(await b.settingsDao.get('key'), isNull);
  });

  test('openAtPath creates the file and persists across a reopen', () async {
    // This is the factory the app uses. The point of it living here rather
    // than in the app layer is that `app` then needs no drift or sqlite3
    // dependency of its own -- asserted by test/architecture_test.dart.
    final dir = Directory.systemTemp.createTempSync('nimbus_open_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}nimbustats.sqlite';

    final first = AppDatabase.openAtPath(path);
    await first.settingsDao.put('currency_code', 'IRT');
    await first.close();

    expect(File(path).existsSync(), isTrue);

    final second = AppDatabase.openAtPath(path);
    addTearDown(second.close);
    expect(await second.settingsDao.get('currency_code'), 'IRT');
  });

  test('foreign keys are enforced on a file-backed database', () async {
    // beforeOpen turns on the pragma. If that ever regressed, the cascade that
    // cleans up transaction_tags would silently stop working -- and orphaned
    // join rows are the kind of corruption nobody notices for months.
    final dir = Directory.systemTemp.createTempSync('nimbus_fk_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db =
        AppDatabase.openAtPath('${dir.path}${Platform.pathSeparator}fk.sqlite');
    addTearDown(db.close);

    final rows = await db.customSelect('PRAGMA foreign_keys').get();
    expect(rows.single.data.values.first, 1);
  });

  group('a file-backed database shared with a second engine (Phase 6)', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('nimbus_wal_test');
      path = '${dir.path}${Platform.pathSeparator}nimbustats.sqlite';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Object?> pragma(AppDatabase db, String name) async =>
        (await db.customSelect('PRAGMA $name').get()).single.data.values.first;

    test('runs in WAL mode with a five-second busy timeout', () async {
      final db = AppDatabase.openAtPath(path);
      addTearDown(db.close);
      await db.settingsDao.put('k', 'v');

      expect(await pragma(db, 'journal_mode'), 'wal');
      expect(await pragma(db, 'busy_timeout'), 5000);
      // The file Phase 7's backup must checkpoint, and device checks copy.
      expect(File('$path-wal').existsSync(), isTrue);
    });

    test('a second engine writing at the same time waits rather than fails',
        () async {
      // The app engine opens (and migrates) first, as it does at start.
      final app = AppDatabase.openAtPath(path);
      addTearDown(app.close);
      await app.settingsDao.get('warm');

      // A real second isolate, like the headless drain engine: each opens its
      // own SQLite connection, so the two write transactions truly overlap.
      final drain = Isolate.run(() => _writeSettings(path, 'drain', 200));
      await _writeSettingsOn(app, 'app', 200);
      await drain;

      final keys = (await app.settingsDao.getAll()).keys;
      expect(keys.where((k) => k.startsWith('app-')), hasLength(200));
      expect(keys.where((k) => k.startsWith('drain-')), hasLength(200));
    });
  });
}

/// Opens its own connection to [path] and writes [count] settings, one
/// transaction each: what the headless drain engine does to the same file.
Future<void> _writeSettings(String path, String prefix, int count) async {
  final db = AppDatabase.openAtPath(path);
  try {
    await _writeSettingsOn(db, prefix, count);
  } finally {
    await db.close();
  }
}

Future<void> _writeSettingsOn(AppDatabase db, String prefix, int count) async {
  for (var i = 0; i < count; i++) {
    await db.transaction(() => db.settingsDao.put('$prefix-$i', '$i'));
  }
}
