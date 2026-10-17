import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift_dev/api/migrations_native.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../generated/schema.dart';
import 'support/backup_fixture.dart';

void main() {
  late BackupFixture source; // the phone that exported
  late BackupFixture target; // the phone that restores
  setUp(() {
    source = BackupFixture.open();
    target = BackupFixture.open(busyTimeout: const Duration(milliseconds: 100));
  });
  tearDown(() async {
    await source.close();
    await target.close();
  });

  /// Exports [from] and prepares the file on [to].
  Future<PreparedRestore> carry(BackupFixture from, BackupFixture to) async {
    final out = from.path('out.nimbus');
    await from.service.exportTo(out, 'correct horse');
    return to.service.prepare(out, 'correct horse');
  }

  Future<Object?> pragma(AppDatabase db, String name) async =>
      (await db.customSelect('PRAGMA $name').getSingle()).data.values.single;

  test('written, exported and restored into a fresh install: the row is there '
      '(the brief DoD, on the host)', () async {
    final id = await source.addExpense(); // never checkpointed, never closed
    await target.db.settingsDao.get('open'); // a fresh install: schema only

    await target.service.restore(await carry(source, target));

    expect(await target.db.transactionsDao.byId(id), isNotNull);
    expect(await pragma(target.db, 'journal_mode'), 'wal');
    expect(await pragma(target.db, 'integrity_check'), 'ok');
  });

  test("open streams on the live database see the restored rows", () async {
    await source.db.settingsDao.put('who', 'backup');
    await target.db.settingsDao.put('who', 'original');
    final seen = expectLater(
        target.db.settingsDao.watchAll().map((all) => all['who']),
        emitsThrough('backup'));

    await target.service.restore(await carry(source, target));
    await seen;
  });

  test('local_date_key travels with the data, whatever the zone', () async {
    // Stamped two days after its UTC instant. No zone on Earth computes that,
    // so a restore that recomputed keys could not reproduce it.
    final id = await source.addExpense(
      occurredAtUtc: DateTime.utc(2026, 3, 20, 12),
      on: DateKey.fromParts(2026, 3, 22),
    );
    await target.service.restore(await carry(source, target));
    expect((await target.db.transactionsDao.byId(id))!.localDateKey,
        DateKey.fromParts(2026, 3, 22));
  });

  group('undo', () {
    test('puts back what the restore replaced, and keeps what it replaced',
        () async {
      await source.db.settingsDao.put('who', 'backup');
      await target.db.settingsDao.put('who', 'original');
      expect(target.service.canUndo, isFalse);

      await target.service.restore(await carry(source, target));
      expect(target.service.canUndo, isTrue);

      await target.service.undo();
      expect(await target.db.settingsDao.get('who'), 'original');
      expect(target.service.canUndo, isTrue); // a swap: the copy now redoes
      expect(File('${target.preRestorePath}.part').existsSync(), isFalse);
      expect(target.cacheFiles(), isEmpty);
    });

    test('a late undo is undoable: nothing entered since is lost', () async {
      await source.db.settingsDao.put('who', 'backup');
      await target.db.settingsDao.put('who', 'original');
      await target.service.restore(await carry(source, target));
      await target.db.settingsDao.put('later', 'X'); // months of entries

      await target.service.undo();
      expect(await target.db.settingsDao.get('who'), 'original');
      expect(await target.db.settingsDao.get('later'), isNull);
      expect(target.service.canUndo, isTrue);

      await target.service.undo();
      expect(await target.db.settingsDao.get('who'), 'backup');
      expect(await target.db.settingsDao.get('later'), 'X');
    });

    test('an undo copy from an older schema migrates (v32)', () async {
      await target.db.settingsDao.put('who', 'original');
      final v32 = await SchemaVerifier(GeneratedHelper()).schemaAt(32);
      addTearDown(v32.close);
      v32.rawDatabase
        ..execute('PRAGMA user_version = 32')
        ..execute("INSERT INTO settings (key, value) VALUES ('from', 'v32')")
        ..execute('VACUUM INTO ?', [target.preRestorePath]);

      await target.service.undo();
      expect(await pragma(target.db, 'user_version'), target.db.schemaVersion);
      expect(await target.db.settingsDao.get('from'), 'v32');
      expect(target.cacheFiles(), isEmpty);
    });

    test('a failed undo changes nothing', () async {
      await target.db.settingsDao.put('who', 'original');
      // SQLite's backup refuses another page size: the swap cannot happen.
      sqlite3.open(target.preRestorePath)
        ..execute('PRAGMA page_size = 8192')
        ..execute('CREATE TABLE t (x)')
        ..close();
      final copy = File(target.preRestorePath).readAsBytesSync();

      await expectLater(target.service.undo(), throwsA(isA<CorruptBackup>()));
      expect(await target.db.settingsDao.get('who'), 'original');
      expect(await pragma(target.db, 'integrity_check'), 'ok');
      expect(target.service.canUndo, isTrue);
      expect(File(target.preRestorePath).readAsBytesSync(), copy);
      expect(File('${target.preRestorePath}.part').existsSync(), isFalse);
      expect(target.cacheFiles(), isEmpty);
    });

    test('a second restore replaces the copy: undo goes back one step',
        () async {
      await target.db.settingsDao.put('who', 'original');
      await source.db.settingsDao.put('who', 'first');
      await target.service.restore(await carry(source, target));
      await source.db.settingsDao.put('who', 'second');
      await target.service.restore(await carry(source, target));

      await target.service.undo();
      expect(await target.db.settingsDao.get('who'), 'first');
    });
  });

  group('one backup operation at a time (13b)', () {
    /// Restored over 'original', then 'later' = X entered since.
    Future<void> restoreThenWrite() async {
      await source.db.settingsDao.put('who', 'backup');
      await target.db.settingsDao.put('who', 'original');
      await target.service.restore(await carry(source, target));
      await target.db.settingsDao.put('later', 'X');
    }

    /// The undo copy's value for [key], read from the file itself.
    String? copied(String key) {
      final copy = sqlite3.open(target.preRestorePath, mode: OpenMode.readOnly);
      try {
        final rows =
            copy.select('SELECT value FROM settings WHERE key = ?', [key]);
        return rows.isEmpty ? null : rows.single['value'] as String;
      } finally {
        copy.close();
      }
    }

    test('two undos at once lose nothing: the second swaps back', () async {
      await restoreThenWrite();

      await Future.wait([target.service.undo(), target.service.undo()]);

      expect(await target.db.settingsDao.get('who'), 'backup');
      expect(await target.db.settingsDao.get('later'), 'X');
      expect(copied('who'), 'original');
      expect(copied('later'), isNull);
      expect(target.service.canUndo, isTrue);
    });

    test('an undo overlapping a sweep keeps the swap', () async {
      await restoreThenWrite();
      var undone = false;
      final undo = target.service.undo().whenComplete(() => undone = true);
      // Sweep once the undo has staged its copy: the window the race needs.
      while (!undone && target.cacheFiles().isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(undone, isFalse, reason: 'the sweep must overlap the undo');

      await Future.wait([undo, target.service.sweep()]);

      expect(await target.db.settingsDao.get('who'), 'original');
      expect(copied('who'), 'backup');
      expect(copied('later'), 'X');
    });

    test('a failed operation does not wedge the lock, and its caller gets the '
        'error', () async {
      // SQLite's backup refuses another page size: the undo fails.
      sqlite3.open(target.preRestorePath)
        ..execute('PRAGMA page_size = 8192')
        ..execute('CREATE TABLE t (x)')
        ..close();
      final out = target.path('out.nimbus');

      final undo = target.service.undo();
      final sweep = target.service.sweep();
      final export = target.service.exportTo(out, 'correct horse');

      await expectLater(undo, throwsA(isA<CorruptBackup>()));
      await sweep;
      await export;
      expect(File(out).existsSync(), isTrue);
    });
  });

  group('a restore that fails midway leaves the live database as it was', () {
    setUp(() => target.db.settingsDao.put('who', 'original'));

    Future<void> expectUntouched() async {
      expect(await target.db.settingsDao.get('who'), 'original');
      expect(await pragma(target.db, 'integrity_check'), 'ok');
      expect(target.service.canUndo, isFalse);
      expect(File('${target.preRestorePath}.part').existsSync(), isFalse);
    }

    test('the swap itself fails: SQLite refuses another page size (R1)',
        () async {
      // prepare() refuses this file, so it is built by hand to reach the
      // backup step, which SQLite rejects before writing a page.
      sqlite3.open(target.path('odd.sqlite'))
        ..execute('PRAGMA page_size = 8192')
        ..execute('CREATE TABLE t (x)')
        ..close();
      final prepared = PreparedRestore(
          path: target.path('odd.sqlite'), createdAt: DateTime.utc(2026));

      await expectLater(
          target.service.restore(prepared), throwsA(isA<SqliteException>()));
      await expectUntouched();
      expect(File(prepared.path).existsSync(), isFalse);
    });

    test('the undo copy cannot be written (R4)', () async {
      Directory('${target.preRestorePath}.part').createSync();
      final prepared = await carry(source, target);

      await expectLater(
          target.service.restore(prepared), throwsA(isA<SqliteException>()));
      expect(await target.db.settingsDao.get('who'), 'original');
      expect(target.service.canUndo, isFalse);
      expect(File(prepared.path).existsSync(), isFalse);
    });

    test('a failed restore keeps the previous undo copy (R4)', () async {
      await source.db.settingsDao.put('who', 'first');
      await target.service.restore(await carry(source, target));
      sqlite3.open(target.path('odd.sqlite'))
        ..execute('PRAGMA page_size = 8192')
        ..execute('CREATE TABLE t (x)')
        ..close();

      await expectLater(
          target.service.restore(PreparedRestore(
              path: target.path('odd.sqlite'), createdAt: DateTime.utc(2026))),
          throwsA(isA<SqliteException>()));
      await target.service.undo();
      expect(await target.db.settingsDao.get('who'), 'original');
    });
  });

  test('a missing live file fails the restore instead of being created',
      () async {
    await target.db.settingsDao.put('who', 'original');
    final prepared = await carry(source, target);
    final misconfigured = BackupService(
      db: target.db,
      livePath: target.path('missing.sqlite'),
      cacheDir: target.path('cache'),
      preRestorePath: target.preRestorePath,
      kdf: fastKdf,
    );

    await expectLater(
        misconfigured.restore(prepared), throwsA(isA<SqliteException>()));

    expect(File(target.path('missing.sqlite')).existsSync(), isFalse);
    expect(File(prepared.path).existsSync(), isFalse);
    expect(await target.db.settingsDao.get('who'), 'original');
    expect(misconfigured.canUndo, isFalse);
  });

  test('a writer holding the lock delays the swap, which then lands whole (R1)',
      () async {
    await source.db.settingsDao.put('who', 'backup');
    await target.db.settingsDao.put('who', 'original');
    final prepared = await carry(source, target);
    // The drain engine mid-write, on its own connection.
    final writer = sqlite3.open(target.livePath)..execute('BEGIN IMMEDIATE');

    final restoring = target.service.restore(prepared);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    writer
      ..execute('COMMIT')
      ..close();
    await restoring;

    expect(await target.db.settingsDao.get('who'), 'backup');
  });

  test('databaseBytes is the file Auto Backup copies after its checkpoint',
      () async {
    await target.addExpense();
    await target.db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    expect(await target.service.databaseBytes(),
        File(target.livePath).lengthSync());
  });

  test('sweep deletes stale plaintext and picked copies, and only those',
      () async {
    final cache = Directory(target.service.cacheDir)..createSync(recursive: true);
    for (final name in const [
      'export-a.sqlite',
      'import-b.sqlite',
      'import-b.sqlite-wal',
      'picked-c.nimbus',
      'notes.txt',
    ]) {
      File('${cache.path}/$name').writeAsStringSync('x');
    }
    Directory('${cache.path}/out').createSync();
    File('${cache.path}/out/nimbustats-20261017-0930.nimbus').writeAsStringSync('x');
    File('${target.preRestorePath}.part').writeAsStringSync('x');

    await target.service.sweep();

    expect(target.cacheFiles()..sort(), ['notes.txt', 'out']);
    expect(File('${cache.path}/out/nimbustats-20261017-0930.nimbus').existsSync(),
        isTrue);
    expect(File('${target.preRestorePath}.part').existsSync(), isFalse);
  });

  test('no passphrase or derived byte reaches a print, an error or a toString',
      () async {
    const passphrase = 'hygiene-passphrase-7042';
    final printed = <String>[];
    final errors = <String>[];
    final out = source.path('out.nimbus');

    await runZoned(
      () async {
        await source.addExpense();
        await source.service.exportTo(out, passphrase);
        final damaged = source.path('damaged.nimbus');
        final bytes = File(out).readAsBytesSync();
        File(damaged).writeAsBytesSync(bytes..[bytes.length - 40] ^= 0x01);
        for (final (file, typed) in [(out, 'not-$passphrase'), (damaged, passphrase)]) {
          try {
            await target.service.prepare(file, typed);
          } on Object catch (error, stack) {
            errors
              ..add('$error')
              ..add('$stack');
          }
        }
        await target.service.restore(await target.service.prepare(out, passphrase));
      },
      zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line)),
    );

    final header = BackupHeader.decode(File(out).readAsBytesSync());
    final keys = await deriveBackupKeys(passphrase, header.kdf, header.salt);
    String hex(List<int> bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final secrets = [
      passphrase,
      normalizePassphrase(passphrase),
      for (final bytes in [keys.check, await keys.encryption.extractBytes()]) ...[
        bytes.toString(),
        hex(bytes),
        base64.encode(bytes),
      ],
    ];
    expect(errors, hasLength(4)); // both failures happened, message and stack
    for (final text in [...printed, ...errors]) {
      for (final secret in secrets) {
        expect(text, isNot(contains(secret)));
      }
    }
  });
}
