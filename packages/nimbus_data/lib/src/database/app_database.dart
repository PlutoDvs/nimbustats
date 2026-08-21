import 'package:drift/drift.dart';

import '../tables/settings_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        // No onUpgrade at v1: there is nothing to upgrade from. drift's default
        // throws when a version bump arrives without a strategy, so a future
        // phase that raises schemaVersion and forgets the migration fails
        // loudly on open rather than quietly running against the wrong schema.
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Built once per database. Cheap either way, but a DAO is a handle, not a
  /// value -- handing out a fresh one per property read invites callers to
  /// assume identity that would not hold.
  late final SettingsDao settingsDao = SettingsDao(this);
}

/// Application settings. Reads return null for an absent key rather than
/// throwing: "not configured yet" is a normal state on first run, not an error.
class SettingsDao {
  SettingsDao(this._db);

  final AppDatabase _db;

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> put(String key, String value) =>
      _db.into(_db.settings).insertOnConflictUpdate(
            SettingsCompanion.insert(key: key, value: value),
          );
}
