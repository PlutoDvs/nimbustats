import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import 'backup_errors.dart';
import 'backup_format.dart';

/// The fewest runes an export's passphrase may have (spec §2.3).
const minPassphraseRunes = 8;

const _tagLength = 16;

/// Spec §2.3, part of format version 1. The same visible passphrase typed on
/// a Persian or an Arabic keyboard, in any digit set, derives the same key.
/// Nothing is trimmed: a space is part of the passphrase.
String normalizePassphrase(String passphrase) => Digits.toLatin(passphrase)
    .replaceAll('ي', 'ی') // Arabic yeh -> Persian yeh
    .replaceAll('ك', 'ک'); // Arabic kaf -> Persian keheh

/// The two keys one passphrase derives (spec §2.2).
///
/// A class rather than a record, so that printing one shows nothing.
final class BackupKeys {
  BackupKeys._(this.encryption, this.check);

  final SecretKey encryption;
  final Uint8List check;

  @override
  String toString() => 'BackupKeys(...)';
}

Future<BackupKeys> deriveBackupKeys(
    String passphrase, KdfParams kdf, List<int> salt) async {
  final master = await Argon2id(
    memory: kdf.memoryKiB,
    iterations: kdf.iterations,
    parallelism: kdf.parallelism,
    hashLength: 32,
  ).deriveKey(
    secretKey: SecretKey(utf8.encode(normalizePassphrase(passphrase))),
    nonce: salt,
  );
  final encryption = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
      .deriveKey(secretKey: master, info: utf8.encode('nimbus-backup v1 enc'));
  final check = await Hkdf(hmac: Hmac.sha256(), outputLength: 16)
      .deriveKey(secretKey: master, info: utf8.encode('nimbus-backup v1 check'));
  return BackupKeys._(encryption, Uint8List.fromList(await check.extractBytes()));
}

/// Seals [payload] into a whole `.nimbus` file: header, ciphertext, tag.
Future<Uint8List> sealBackup({
  required List<int> payload,
  required String passphrase,
  required int schemaVersion,
  required DateTime createdAt,
  KdfParams kdf = KdfParams.standard,
}) async {
  final random = Random.secure();
  Uint8List randomBytes(int count) =>
      Uint8List.fromList([for (var i = 0; i < count; i++) random.nextInt(256)]);
  final salt = randomBytes(BackupHeader.saltLength);
  final keys = await deriveBackupKeys(passphrase, kdf, salt);
  final header = BackupHeader(
    schemaVersion: schemaVersion,
    createdAt: createdAt.toUtc(),
    kdf: kdf,
    salt: salt,
    nonce: randomBytes(BackupHeader.nonceLength),
    keyCheck: keys.check,
  );
  final headerBytes = header.encode();
  final box = await AesGcm.with256bits().encrypt(
    payload,
    secretKey: keys.encryption,
    nonce: header.nonce,
    aad: headerBytes,
  );
  return (BytesBuilder(copy: false)
        ..add(headerBytes)
        ..add(box.cipherText)
        ..add(box.mac.bytes))
      .takeBytes();
}

/// Opens a whole `.nimbus` file and returns its payload.
///
/// The key-check value is what tells a wrong passphrase from damage (spec
/// §2.2). A mismatch is [WrongPassphrase]. A match whose GCM tag then fails
/// is [CorruptBackup].
Future<Uint8List> openBackup(Uint8List file, String passphrase) async {
  final header = BackupHeader.decode(file);
  final keys = await deriveBackupKeys(passphrase, header.kdf, header.salt);
  if (!_same(keys.check, header.keyCheck)) throw const WrongPassphrase();
  if (file.length < BackupHeader.length + _tagLength) {
    throw const CorruptBackup('truncated');
  }
  try {
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(
        Uint8List.sublistView(file, BackupHeader.length, file.length - _tagLength),
        nonce: header.nonce,
        mac: Mac(Uint8List.sublistView(file, file.length - _tagLength)),
      ),
      secretKey: keys.encryption,
      aad: Uint8List.sublistView(file, 0, BackupHeader.length),
    );
    return clear is Uint8List ? clear : Uint8List.fromList(clear);
  } on SecretBoxAuthenticationError {
    throw const CorruptBackup('authentication failed');
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
