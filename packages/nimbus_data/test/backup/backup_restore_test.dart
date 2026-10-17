import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

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
    test('puts back what the restore replaced, once', () async {
      await source.db.settingsDao.put('who', 'backup');
      await target.db.settingsDao.put('who', 'original');
      expect(target.service.canUndo, isFalse);

      await target.service.restore(await carry(source, target));
      expect(target.service.canUndo, isTrue);

      await target.service.undo();
      expect(await target.db.settingsDao.get('who'), 'original');
      expect(target.service.canUndo, isFalse);
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
