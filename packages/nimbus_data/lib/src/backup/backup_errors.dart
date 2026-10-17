/// Why a backup file cannot be restored (Phase 7 spec §2.4), checked in
/// declaration order.
///
/// None carries the passphrase or anything derived from it, so `toString` is
/// safe to log or report.
sealed class BackupException implements Exception {
  const BackupException();
}

/// Shorter than the header, or not starting with the magic bytes.
final class NotABackup extends BackupException {
  const NotABackup();

  @override
  String toString() => 'NotABackup: not a NimbuStats backup file';
}

/// A format version or key-derivation setting this app cannot read.
final class UnsupportedFormat extends BackupException {
  const UnsupportedFormat(this.reason);

  final String reason;

  @override
  String toString() => 'UnsupportedFormat: $reason';
}

/// Made by an app with a newer schema. Restoring it would corrupt data in
/// ways no migration can repair, so it is refused before the passphrase is
/// asked for.
final class NewerSchema extends BackupException {
  const NewerSchema({required this.backup, required this.app});

  final int backup;
  final int app;

  @override
  String toString() => 'NewerSchema: backup v$backup, app v$app';
}

/// The passphrase derives a key-check value that differs from the file's.
final class WrongPassphrase extends BackupException {
  const WrongPassphrase();

  @override
  String toString() => 'WrongPassphrase';
}

/// The passphrase is right but the content fails a check: damaged, or
/// tampered with.
final class CorruptBackup extends BackupException {
  const CorruptBackup(this.reason);

  final String reason;

  @override
  String toString() => 'CorruptBackup: $reason';
}
