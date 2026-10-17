import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

List<int> hex(String text) => [
      for (var i = 0; i < text.length; i += 2)
        int.parse(text.substring(i, i + 2), radix: 16),
    ];

/// Cheap settings (ruling R10). The header carries them, so every other step
/// is the production path.
const fast = KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

void main() {
  group('known answers', () {
    test('Argon2id, RFC 9106 §5.3', () async {
      final tag = await Argon2id(
              memory: 32, iterations: 3, parallelism: 4, hashLength: 32)
          .deriveKey(
        secretKey: SecretKey(List.filled(32, 0x01)),
        nonce: List.filled(16, 0x02),
        optionalSecret: List.filled(8, 0x03),
        associatedData: List.filled(12, 0x04),
      );
      expect(await tag.extractBytes(),
          hex('0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659'));
    });

    test('HKDF-SHA256, RFC 5869 test case 1', () async {
      final okm = await Hkdf(hmac: Hmac.sha256(), outputLength: 42).deriveKey(
        secretKey: SecretKey(hex('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b')),
        nonce: hex('000102030405060708090a0b0c'),
        info: hex('f0f1f2f3f4f5f6f7f8f9'),
      );
      expect(
          await okm.extractBytes(),
          hex('3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
              '34007208d5b887185865'));
    });

    test('AES-256-GCM, the GCM specification test case 16', () async {
      final box = await AesGcm.with256bits().encrypt(
        hex('d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72'
            '1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39'),
        secretKey: SecretKey(hex(
            'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308')),
        nonce: hex('cafebabefacedbaddecaf888'),
        aad: hex('feedfacedeadbeeffeedfacedeadbeefabaddad2'),
      );
      expect(
          box.cipherText,
          hex('522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa'
              '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662'));
      expect(box.mac.bytes, hex('76fc6ece0f4e1768cddf8853bb2d551b'));
    });
  });

  test('the derivation is pinned: normalise, Argon2id, then both HKDF infos',
      () async {
    final keys =
        await deriveBackupKeys('correct horse battery', fast, List.filled(16, 1));
    expect(keys.check, hex('2fcd19cee5eb70a6910c4fabe0f1bfbc'));
    expect(
        await keys.encryption.extractBytes(),
        hex('a00f2658241217974d17c6d9992cd892'
            'ceba7e1c79ae369d4edb5100f67649c7'));
  });

  group('passphrase normalisation, part of format v1', () {
    for (final (typed, normalised) in [
      ('رمزي', 'رمزی'), // Arabic yeh -> Persian yeh
      ('كتاب', 'کتاب'), // Arabic kaf -> Persian keheh
      ('۱۲۳٤٥٦', '123456'), // Persian and Arabic-Indic digits -> ASCII
      (' pass word ', ' pass word '), // nothing trimmed
      ('Pass', 'Pass'), // case kept
    ]) {
      test(typed, () => expect(normalizePassphrase(typed), normalised));
    }
  });

  group('seal and open', () {
    final created = DateTime.utc(2026, 10, 17, 9, 30);

    Future<Uint8List> seal(List<int> payload,
            [String passphrase = 'correct horse']) =>
        sealBackup(
          payload: payload,
          passphrase: passphrase,
          schemaVersion: 40,
          createdAt: created,
          kdf: fast,
        );

    test('round trip, with the header describing the file', () async {
      final file = await seal(utf8.encode('payload'));
      final header = BackupHeader.decode(file);
      expect(header.schemaVersion, 40);
      expect(header.createdAt, created);
      expect(header.kdf, fast);
      expect(file, hasLength(BackupHeader.length + 'payload'.length + 16));
      expect(utf8.decode(await openBackup(file, 'correct horse')), 'payload');
    });

    test('the same passphrase from another keyboard opens it', () async {
      final file = await seal([1, 2, 3], 'رمز-پشتیبان-۱۴۰۵');
      expect(await openBackup(file, 'رمز-پشتيبان-1405'), [1, 2, 3]);
    });

    test('two seals of one payload share no salt, nonce or ciphertext',
        () async {
      final a = await seal([1, 2, 3]);
      final b = await seal([1, 2, 3]);
      expect(a.sublist(32, 60), isNot(b.sublist(32, 60)));
      expect(a.sublist(BackupHeader.length),
          isNot(b.sublist(BackupHeader.length)));
    });

    test('a wrong passphrase is WrongPassphrase', () async {
      await expectLater(openBackup(await seal([1]), 'correct horse!'),
          throwsA(isA<WrongPassphrase>()));
    });

    test('a flipped ciphertext byte is CorruptBackup, not a wrong passphrase',
        () async {
      final file = await seal([1, 2, 3, 4]);
      file[BackupHeader.length + 1] ^= 0x01;
      await expectLater(openBackup(file, 'correct horse'),
          throwsA(isA<CorruptBackup>()));
    });

    test('a flipped header byte outside the key inputs is CorruptBackup',
        () async {
      // A created-at byte: authenticated as associated data, but not an
      // input to the key. A flipped salt, KDF or check byte changes the
      // derived check instead and reads as WrongPassphrase. Those two cases
      // cannot be told apart, and neither restores anything.
      final file = await seal([1, 2, 3]);
      file[20] ^= 0x01;
      await expectLater(openBackup(file, 'correct horse'),
          throwsA(isA<CorruptBackup>()));
    });

    test('a lowered schema version fails authentication', () async {
      final file = await seal([1, 2, 3]);
      ByteData.sublistView(file).setUint32(10, 39);
      await expectLater(openBackup(file, 'correct horse'),
          throwsA(isA<CorruptBackup>()));
    });

    test('a cut tail is CorruptBackup; a cut header is NotABackup', () async {
      final file = await seal([1, 2, 3]);
      await expectLater(
          openBackup(file.sublist(0, file.length - 1), 'correct horse'),
          throwsA(isA<CorruptBackup>()));
      await expectLater(
          openBackup(file.sublist(0, BackupHeader.length + 3), 'correct horse'),
          throwsA(isA<CorruptBackup>()));
      await expectLater(openBackup(file.sublist(0, 40), 'correct horse'),
          throwsA(isA<NotABackup>()));
    });

    test('derived keys never print', () async {
      final keys = await deriveBackupKeys('correct horse', fast, List.filled(16, 2));
      expect(keys.toString(), 'BackupKeys(...)');
    });
  });
}
