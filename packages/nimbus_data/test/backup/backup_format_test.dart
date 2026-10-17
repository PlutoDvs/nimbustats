import 'dart:typed_data';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

void main() {
  BackupHeader sample({
    int schemaVersion = 40,
    KdfParams kdf = KdfParams.standard,
  }) =>
      BackupHeader(
        schemaVersion: schemaVersion,
        createdAt: DateTime.utc(2026, 10, 17, 9, 30),
        kdf: kdf,
        salt: Uint8List.fromList(List.generate(16, (i) => i)),
        nonce: Uint8List.fromList(List.generate(12, (i) => 100 + i)),
        keyCheck: Uint8List.fromList(List.generate(16, (i) => 200 + i)),
      );

  test('a header is 76 bytes and reads back field for field', () {
    final bytes = sample().encode();
    expect(bytes, hasLength(BackupHeader.length));
    expect(String.fromCharCodes(bytes.sublist(0, 8)), 'NIMBUSBK');

    final back = BackupHeader.decode(bytes);
    expect(back.schemaVersion, 40);
    expect(back.createdAt, DateTime.utc(2026, 10, 17, 9, 30));
    expect(back.createdAt.isUtc, isTrue);
    expect(back.kdf, KdfParams.standard);
    expect(back.salt, sample().salt);
    expect(back.nonce, sample().nonce);
    expect(back.keyCheck, sample().keyCheck);
  });

  test('the layout is big-endian at the offsets spec §2.1 fixes', () {
    final data = ByteData.sublistView(sample().encode());
    expect(data.getUint16(8), 1);
    expect(data.getUint32(10), 40);
    expect(data.getUint64(14),
        DateTime.utc(2026, 10, 17, 9, 30).millisecondsSinceEpoch);
    expect(data.getUint8(22), 1);
    expect(data.getUint32(23), KdfParams.standard.memoryKiB);
    expect(data.getUint32(27), KdfParams.standard.iterations);
    expect(data.getUint8(31), KdfParams.standard.parallelism);
    expect(data.getUint8(32), 0); // salt[0]
    expect(data.getUint8(48), 100); // nonce[0]
    expect(data.getUint8(60), 200); // key check[0]
  });

  test('decode reads only the header of a longer file', () {
    final file = Uint8List.fromList([...sample().encode(), 1, 2, 3]);
    expect(BackupHeader.decode(file).schemaVersion, 40);
  });

  group('not a backup', () {
    test('shorter than the header', () {
      expect(() => BackupHeader.decode(sample().encode().sublist(0, 75)),
          throwsA(isA<NotABackup>()));
    });
    test('an empty file', () {
      expect(() => BackupHeader.decode(Uint8List(0)),
          throwsA(isA<NotABackup>()));
    });
    test('wrong magic', () {
      expect(() => BackupHeader.decode(sample().encode()..[0] = 0x58),
          throwsA(isA<NotABackup>()));
    });
  });

  group('unsupported', () {
    test('a newer format version', () {
      final bytes = sample().encode();
      ByteData.sublistView(bytes).setUint16(8, 2);
      expect(() => BackupHeader.decode(bytes),
          throwsA(isA<UnsupportedFormat>()));
    });
    test('an unknown key derivation', () {
      expect(() => BackupHeader.decode(sample().encode()..[22] = 2),
          throwsA(isA<UnsupportedFormat>()));
    });
    test('key-derivation settings past what a phone can run (R6)', () {
      for (final kdf in const [
        KdfParams(memoryKiB: 512 * 1024, iterations: 3, parallelism: 1),
        KdfParams(memoryKiB: 65536, iterations: 0, parallelism: 1),
        KdfParams(memoryKiB: 65536, iterations: 17, parallelism: 1),
        KdfParams(memoryKiB: 65536, iterations: 3, parallelism: 0),
        KdfParams(memoryKiB: 65536, iterations: 3, parallelism: 9),
        KdfParams(memoryKiB: 15, iterations: 1, parallelism: 2),
      ]) {
        expect(() => BackupHeader.decode(sample(kdf: kdf).encode()),
            throwsA(isA<UnsupportedFormat>()),
            reason: '$kdf');
      }
    });
    test('schema version 0', () {
      expect(() => BackupHeader.decode(sample(schemaVersion: 0).encode()),
          throwsA(isA<UnsupportedFormat>()));
    });
  });

  test('the file name is local time in ASCII digits', () {
    expect(backupFileName(DateTime(2026, 3, 5, 7, 9)),
        'nimbustats-20260305-0709.nimbus');
  });

  test('an error names its kind and fixed facts, nothing else', () {
    expect(const NotABackup().toString(),
        'NotABackup: not a NimbuStats backup file');
    expect(const NewerSchema(backup: 41, app: 40).toString(),
        'NewerSchema: backup v41, app v40');
    expect(const WrongPassphrase().toString(), 'WrongPassphrase');
  });
}
