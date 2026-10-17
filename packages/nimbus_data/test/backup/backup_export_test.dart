import 'dart:io';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/backup_fixture.dart';

void main() {
  late BackupFixture f;
  setUp(() => f = BackupFixture.open(clock: () => DateTime.utc(2026, 10, 17, 9, 30)));
  tearDown(() => f.close());

  /// The snapshot a decrypted [payload] holds, unzipped and opened.
  Database openPayload(List<int> payload) {
    final path = f.path('payload.sqlite');
    File(path).writeAsBytesSync(gzip.decode(payload));
    return sqlite3.open(path, mode: OpenMode.readOnly);
  }

  test('a row committed but never checkpointed is in the export (the WAL trap)',
      () async {
    final id = await f.addExpense();
    // Still connected and never closed: the row is in the -wal file.
    expect(File('${f.livePath}-wal').lengthSync(), greaterThan(0));

    await f.service.exportTo(f.path('out.nimbus'), 'correct horse');

    final payload = await openBackup(
        File(f.path('out.nimbus')).readAsBytesSync(), 'correct horse');
    final snapshot = openPayload(payload);
    addTearDown(snapshot.close);
    expect(snapshot.select('SELECT id FROM transactions').map((r) => r['id']),
        [id]);
  });

  test('the header records the snapshot schema, the time and the KDF',
      () async {
    await f.service.exportTo(f.path('out.nimbus'), 'correct horse');
    final header = await f.service.readHeader(f.path('out.nimbus'));
    expect(header.schemaVersion, f.db.schemaVersion);
    expect(header.createdAt, DateTime.utc(2026, 10, 17, 9, 30));
    expect(header.kdf, fastKdf);
  });

  test('the plaintext snapshot never outlives the export', () async {
    await f.service.exportTo(f.path('out.nimbus'), 'correct horse');
    expect(f.cacheFiles(), isEmpty);
  });

  test('a failed export leaves no plaintext either', () async {
    // The out path is a folder, so the write fails after the snapshot exists.
    Directory(f.path('out.nimbus')).createSync();
    await expectLater(f.service.exportTo(f.path('out.nimbus'), 'correct horse'),
        throwsA(isA<FileSystemException>()));
    expect(f.cacheFiles(), isEmpty);
  });

  group('readHeader', () {
    test('refuses a newer schema before any passphrase is asked for',
        () async {
      File(f.path('newer.nimbus')).writeAsBytesSync(await sealBackup(
        payload: [0],
        passphrase: 'p',
        schemaVersion: f.db.schemaVersion + 1,
        createdAt: DateTime.utc(2026),
        kdf: fastKdf,
      ));
      await expectLater(
        f.service.readHeader(f.path('newer.nimbus')),
        throwsA(isA<NewerSchema>()
            .having((e) => e.backup, 'backup', f.db.schemaVersion + 1)
            .having((e) => e.app, 'app', f.db.schemaVersion)),
      );
    });

    test('a file that is not a backup', () async {
      File(f.path('photo.jpg')).writeAsBytesSync(List.filled(500, 0xFF));
      await expectLater(f.service.readHeader(f.path('photo.jpg')),
          throwsA(isA<NotABackup>()));
    });

    test('an empty file', () async {
      File(f.path('empty.nimbus')).writeAsBytesSync(const []);
      await expectLater(f.service.readHeader(f.path('empty.nimbus')),
          throwsA(isA<NotABackup>()));
    });
  });
}
