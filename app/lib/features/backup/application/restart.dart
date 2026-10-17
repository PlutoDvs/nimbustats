import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Why the app restarted, for the snackbar over Home (spec §5.3).
sealed class RestartNotice {
  const RestartNotice();
}

final class BackupRestored extends RestartNotice {
  const BackupRestored(this.backupCreatedAt);

  final DateTime backupCreatedAt;
}

final class RestoreUndone extends RestartNotice {
  const RestoreUndone();
}

/// An undo of an undo: the restored backup is back.
final class RestoreRedone extends RestartNotice {
  const RestoreRedone();
}

/// Rebuilds every provider over the same database, whose content a restore
/// just replaced in place.
///
/// `AppRestart` provides it. Reading it without that is a wiring bug, and
/// it throws, like `appDatabaseProvider`.
final appRestartProvider = Provider<void Function(RestartNotice notice)>(
  (ref) => throw StateError(
      'appRestartProvider was read without being overridden; AppRestart '
      'provides it.'),
);

/// The notice the current scope started with. Null on an ordinary start.
final restartNoticeProvider = Provider<RestartNotice?>((ref) => null);
