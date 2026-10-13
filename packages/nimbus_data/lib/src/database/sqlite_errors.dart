import 'package:sqlite3/common.dart' show SqlExtendedError, SqliteException;

/// SQLite refusing a row because its primary key is already taken -- by a
/// live row or a soft-deleted one.
///
/// Like `_isOncePerDayViolation` in tracker_entries_dao.dart, this matches the
/// [SqliteException] that `AppDatabase.openAtPath` and `openInMemory` throw,
/// because both run SQLite on the calling isolate. A database moved to a
/// background isolate throws drift's remote wrapper instead, and this must
/// then unwrap it.
bool isPrimaryKeyViolation(Object error) => switch (error) {
      SqliteException(:final extendedResultCode) =>
        extendedResultCode == SqlExtendedError.SQLITE_CONSTRAINT_PRIMARYKEY,
      _ => false,
    };
