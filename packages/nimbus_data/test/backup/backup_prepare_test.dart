import 'dart:convert';
import 'dart:io';

import 'package:drift_dev/api/migrations_native.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../generated/schema.dart';
import 'support/backup_fixture.dart';

void main() {
  late BackupFixture f;
  setUp(() => f = BackupFixture.open());
  tearDown(() => f.close());

  Future<String> exported() async {
    final out = f.path('out.nimbus');
    await f.service.exportTo(out, 'correct horse');
    return out;
  }

  /// Seals [database]'s bytes under a header claiming [schemaVersion].
  Future<String> sealAs(String database, int schemaVersion) async {
    final out = f.path('sealed.nimbus');
    File(out).writeAsBytesSync(await sealBackup(
      payload: gzip.encode(File(database).readAsBytesSync()),
      passphrase: 'correct horse',
      schemaVersion: schemaVersion,
      createdAt: DateTime.utc(2025),
      kdf: fastKdf,
    ));
    return out;
  }

  /// One value from a prepared file, read without the app's migrations.
  Object? read(PreparedRestore prepared, String sql) {
    final db = sqlite3.open(prepared.path, mode: OpenMode.readOnly);
    try {
      return db.select(sql).single.values.first;
    } finally {
      db.close();
    }
  }

  test('the golden v1 file still restores (format compatibility)', () async {
    // Never regenerated: a change that stops this file from opening has
    // broken every backup users already have.
    const fixture = 'test/fixtures/backup_v1.nimbus';
    final header = await f.service.readHeader(fixture);
    expect(header.createdAt, DateTime.utc(2026, 10, 17, 12));
    expect(header.kdf,
        const KdfParams(memoryKiB: 1024, iterations: 1, parallelism: 1));

    // Sealed as 'رمز-پشتیبان-۱۴۰۵'; typed here on an Arabic keyboard with
    // Latin digits.
    final prepared = await f.service.prepare(fixture, 'رمز-پشتيبان-1405');
    addTearDown(() => f.service.discard(prepared));
    expect(prepared.createdAt, DateTime.utc(2026, 10, 17, 12));
    expect(read(prepared, "SELECT value FROM settings WHERE key = 'fixture'"),
        'golden v1');
    expect(read(prepared, 'PRAGMA user_version'), f.db.schemaVersion);
  });

  test("an older backup migrates to today's schema (v32)", () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final v32 = await verifier.schemaAt(32);
    addTearDown(v32.close);
    v32.rawDatabase
      ..execute('PRAGMA user_version = 32')
      ..execute("INSERT INTO settings (key, value) VALUES ('from', 'v32')")
      ..execute('VACUUM INTO ?', [f.path('v32.sqlite')]);

    final prepared =
        await f.service.prepare(await sealAs(f.path('v32.sqlite'), 32), 'correct horse');
    addTearDown(() => f.service.discard(prepared));
    expect(read(prepared, 'PRAGMA user_version'), f.db.schemaVersion);
    expect(read(prepared, "SELECT value FROM settings WHERE key = 'from'"), 'v32');
  });

  test('discard deletes the prepared file', () async {
    final prepared = await f.service.prepare(await exported(), 'correct horse');
    await f.service.discard(prepared);
    expect(File(prepared.path).existsSync(), isFalse);
  });

  group('a file that must not restore leaves nothing behind', () {
    Future<void> refused(String file, Matcher error,
        [String passphrase = 'correct horse']) async {
      await expectLater(f.service.prepare(file, passphrase), throwsA(error));
      expect(f.cacheFiles(), isEmpty);
    }

    test('a wrong passphrase', () async {
      await refused(await exported(), isA<WrongPassphrase>(), 'correct horse?');
    });

    test('a flipped ciphertext byte', () async {
      final out = await exported();
      final bytes = File(out).readAsBytesSync();
      bytes[bytes.length - 40] ^= 0x01;
      File(out).writeAsBytesSync(bytes);
      await refused(out, isA<CorruptBackup>());
    });

    test('a file cut in half', () async {
      final out = await exported();
      final bytes = File(out).readAsBytesSync();
      File(out).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      await refused(out, isA<CorruptBackup>());
    });

    test('a payload that is not gzip', () async {
      final out = f.path('bad.nimbus');
      File(out).writeAsBytesSync(await sealBackup(
        payload: utf8.encode('not gzip'),
        passphrase: 'correct horse',
        schemaVersion: f.db.schemaVersion,
        createdAt: DateTime.utc(2026),
        kdf: fastKdf,
      ));
      await refused(out, isA<CorruptBackup>());
    });

    test('a payload that is not a database', () async {
      File(f.path('hello.txt')).writeAsStringSync('hello');
      await refused(await sealAs(f.path('hello.txt'), f.db.schemaVersion),
          isA<CorruptBackup>());
    });

    test('a payload whose schema differs from its header', () async {
      await f.db.customStatement('VACUUM INTO ?', [f.path('snap.sqlite')]);
      await refused(await sealAs(f.path('snap.sqlite'), f.db.schemaVersion - 1),
          isA<CorruptBackup>());
    });

    test('a database with another page size', () async {
      sqlite3.open(f.path('odd.sqlite'))
        ..execute('PRAGMA page_size = 8192')
        ..execute('CREATE TABLE t (x)')
        ..execute('PRAGMA user_version = ${f.db.schemaVersion}')
        ..close();
      await refused(await sealAs(f.path('odd.sqlite'), f.db.schemaVersion),
          isA<CorruptBackup>());
    });
  });
}
