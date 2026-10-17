import 'dart:typed_data';

import 'backup_errors.dart';

/// The Argon2id settings a file was sealed with (spec §2.2).
///
/// They travel in the file's header, so changing [standard] never breaks an
/// older file.
final class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// What new exports use. Fixed after the Galaxy A53 measurement (plan
  /// Task 14): the strongest setting that derives in about 2 s there.
  static const standard = KdfParams(
    memoryKiB: 65536,
    iterations: 3,
    parallelism: 1,
  );

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      other.memoryKiB == memoryKiB &&
      other.iterations == iterations &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(memoryKiB, iterations, parallelism);

  @override
  String toString() =>
      'KdfParams(${memoryKiB}KiB, t=$iterations, p=$parallelism)';
}

/// The fixed 76-byte header of a `.nimbus` file (spec §2.1).
///
/// Integers are big-endian. The whole header is the AES-GCM associated data,
/// so changing any byte of it, such as lowering the schema version, fails
/// authentication.
final class BackupHeader {
  const BackupHeader({
    required this.schemaVersion,
    required this.createdAt,
    required this.kdf,
    required this.salt,
    required this.nonce,
    required this.keyCheck,
  });

  static const length = 76;
  static const formatVersion = 1;
  static const saltLength = 16;
  static const nonceLength = 12;
  static const keyCheckLength = 16;

  static const _magic = 'NIMBUSBK';
  static const _argon2id = 1;

  // The file is untrusted input (ruling R6). Without a ceiling, a crafted
  // header could ask Argon2id for gigabytes and crash the app before the
  // passphrase is even checked.
  static const _maxMemoryKiB = 256 * 1024;
  static const _maxIterations = 16;
  static const _maxParallelism = 8;

  /// The payload's `PRAGMA user_version`.
  final int schemaVersion;

  /// When the export was made, in UTC.
  final DateTime createdAt;
  final KdfParams kdf;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List keyCheck;

  Uint8List encode() {
    final bytes = Uint8List(length)..setAll(0, _magic.codeUnits);
    ByteData.sublistView(bytes)
      ..setUint16(8, formatVersion)
      ..setUint32(10, schemaVersion)
      ..setUint64(14, createdAt.millisecondsSinceEpoch)
      ..setUint8(22, _argon2id)
      ..setUint32(23, kdf.memoryKiB)
      ..setUint32(27, kdf.iterations)
      ..setUint8(31, kdf.parallelism);
    return bytes
      ..setAll(32, salt)
      ..setAll(48, nonce)
      ..setAll(60, keyCheck);
  }

  /// Reads the header at the start of [file].
  ///
  /// Throws [NotABackup] or [UnsupportedFormat].
  static BackupHeader decode(Uint8List file) {
    if (file.length < length) throw const NotABackup();
    for (var i = 0; i < _magic.length; i++) {
      if (file[i] != _magic.codeUnitAt(i)) throw const NotABackup();
    }
    final data = ByteData.sublistView(file, 0, length);
    final version = data.getUint16(8);
    if (version != formatVersion) {
      throw UnsupportedFormat('format version $version');
    }
    final kdfId = data.getUint8(22);
    if (kdfId != _argon2id) throw UnsupportedFormat('key derivation $kdfId');
    final kdf = KdfParams(
      memoryKiB: data.getUint32(23),
      iterations: data.getUint32(27),
      parallelism: data.getUint8(31),
    );
    if (kdf.parallelism < 1 ||
        kdf.parallelism > _maxParallelism ||
        kdf.memoryKiB < 8 * kdf.parallelism ||
        kdf.memoryKiB > _maxMemoryKiB ||
        kdf.iterations < 1 ||
        kdf.iterations > _maxIterations) {
      throw const UnsupportedFormat('key derivation settings out of range');
    }
    final schemaVersion = data.getUint32(10);
    if (schemaVersion < 1) throw const UnsupportedFormat('schema version 0');
    // DateTime holds +-8.64e15 ms; getUint64 is negative with the top bit set.
    final createdMs = data.getUint64(14);
    if (createdMs < 0 || createdMs > 8640000000000000) {
      throw const UnsupportedFormat('created-at out of range');
    }
    return BackupHeader(
      schemaVersion: schemaVersion,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdMs, isUtc: true),
      kdf: kdf,
      salt: Uint8List.fromList(file.sublist(32, 48)),
      nonce: Uint8List.fromList(file.sublist(48, 60)),
      keyCheck: Uint8List.fromList(file.sublist(60, 76)),
    );
  }
}

/// `nimbustats-YYYYMMDD-HHmm.nimbus`, in ASCII digits, Gregorian and the
/// device's local time (spec §2.1), so the name reads and sorts the same in
/// any language.
String backupFileName(DateTime local) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'nimbustats-${local.year.toString().padLeft(4, '0')}'
      '${two(local.month)}${two(local.day)}-'
      '${two(local.hour)}${two(local.minute)}.nimbus';
}
