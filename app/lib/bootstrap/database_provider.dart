import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

/// The application database.
///
/// Deliberately unimplemented at declaration: `main` overrides it with a
/// database opened at the real path, and every test overrides it with an
/// in-memory one.
///
/// A default here would be a hardcoded fallback that masks a bootstrap
/// failure. The app would start, write to somewhere that is not the user's
/// database, and look entirely correct until the day their data was not there.
/// Throwing turns that into a crash on the first read, which is loud, local,
/// and fixable.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw StateError(
    'appDatabaseProvider was read without being overridden. '
    'main() overrides it after opening the database; tests override it with '
    'AppDatabase.openInMemory().',
  );
});
