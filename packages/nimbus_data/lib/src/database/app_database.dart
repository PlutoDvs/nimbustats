import 'package:drift/drift.dart';

import '../tables/categories_table.dart';
import '../tables/settings_table.dart';
import '../tables/tags_table.dart';
import '../tree/materialized_path.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Settings, Categories, Tags])
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
  late final CategoriesDao categoriesDao = CategoriesDao(this);
  late final TagsDao tagsDao = TagsDao(this);
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

/// The category tree.
///
/// [TagsDao] is the same shape against the `tags` table. The duplication is
/// deliberate: the algorithm lives once in [MaterializedPath], and what is
/// repeated here is drift's per-table typed plumbing, which cannot be shared
/// without casting away the types that make it worth using.
class CategoriesDao {
  CategoriesDao(this._db);

  final AppDatabase _db;

  Future<Category?> byId(String id) =>
      (_db.select(_db.categories)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// The live-subtree query, exposed so callers can compose further filters on
  /// it and so a test can assert its query plan still uses the path index.
  SimpleSelectStatement<$CategoriesTable, Category> subtreeQuery(String path) =>
      _db.select(_db.categories)
        ..where((t) => t.path.isBiggerOrEqualValue(path))
        ..where((t) =>
            t.path.isSmallerThanValue(MaterializedPath.subtreeUpperBound(path)))
        ..where((t) => t.deletedAt.isNull());

  Future<void> insertNode({
    required String id,
    required String name,
    required String? parentId,
    String iconKey = 'tag',
    int color = 0xFF9E9E9E,
  }) async {
    String path;
    if (parentId == null) {
      path = MaterializedPath.childPath(null, id);
    } else {
      final parent = await byId(parentId);
      if (parent == null) {
        throw ArgumentError.value(parentId, 'parentId', 'No such category');
      }
      path = MaterializedPath.childPath(parent.path, id);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            id: id,
            name: name,
            parentId: Value(parentId),
            path: path,
            depth: MaterializedPath.depthOf(path),
            iconKey: Value(iconKey),
            color: Value(color),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<List<Category>> subtreeOf(String id) async {
    final node = await byId(id);
    if (node == null) return const [];
    return subtreeQuery(node.path).get();
  }

  /// Authoritative but slower. Used as the oracle in tests to prove the
  /// materialized path stays correct.
  ///
  /// This walks parent links and ignores `deletedAt`, so it agrees with
  /// [subtreeOf] only while nothing is soft-deleted. Once soft delete is in
  /// use the two answer different questions -- whether a deleted node hides
  /// its descendants -- and that choice has to be made explicitly.
  Future<List<String>> descendantIdsViaCte(String id) async {
    final rows = await _db.customSelect(
      '''
      WITH RECURSIVE tree(id) AS (
        SELECT id FROM categories WHERE id = ?1
        UNION ALL
        SELECT c.id FROM categories c JOIN tree t ON c.parent_id = t.id
      )
      SELECT id FROM tree
      ''',
      variables: [Variable<String>(id)],
    ).get();
    return rows.map((r) => r.read<String>('id')).toList();
  }

  Future<void> move(String id, String? newParentId) async {
    final node = await byId(id);
    if (node == null) throw ArgumentError.value(id, 'id', 'No such category');

    String newParentPath;
    if (newParentId == null) {
      newParentPath = '/';
    } else {
      final parent = await byId(newParentId);
      if (parent == null) {
        throw ArgumentError.value(
            newParentId, 'newParentId', 'No such category');
      }
      if (parent.id == node.id ||
          MaterializedPath.isDescendant(
            path: parent.path,
            ancestorPath: node.path,
          )) {
        throw ArgumentError.value(
          newParentId,
          'newParentId',
          'Cannot move a node beneath its own descendant',
        );
      }
      newParentPath = parent.path;
    }

    final oldPath = node.path;
    final newPath = MaterializedPath.childPath(newParentPath, id);

    await _db.transaction(() async {
      // Deliberately not filtering deletedAt here: a soft-deleted descendant
      // still needs its path rewritten, or restoring it later would strand it
      // under a path that no longer exists.
      final affected = await (_db.select(_db.categories)
            ..where((t) => t.path.isBiggerOrEqualValue(oldPath))
            ..where((t) => t.path.isSmallerThanValue(
                MaterializedPath.subtreeUpperBound(oldPath))))
          .get();
      final now = DateTime.now().millisecondsSinceEpoch;
      // One statement per affected row. A single UPDATE using substr() would
      // be one round trip instead of N, but a category subtree is small and a
      // move is a rare, user-initiated action -- not worth the readability.
      for (final row in affected) {
        final rewritten = MaterializedPath.reparent(
          path: row.path,
          oldAncestorPath: oldPath,
          newAncestorPath: newPath,
        );
        await (_db.update(_db.categories)..where((t) => t.id.equals(row.id)))
            .write(
          CategoriesCompanion(
            path: Value(rewritten),
            depth: Value(MaterializedPath.depthOf(rewritten)),
            parentId: row.id == id ? Value(newParentId) : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }
}

/// The tag tree. See [CategoriesDao] for why this is a near-copy.
class TagsDao {
  TagsDao(this._db);

  final AppDatabase _db;

  Future<Tag?> byId(String id) =>
      (_db.select(_db.tags)..where((t) => t.id.equals(id))).getSingleOrNull();

  SimpleSelectStatement<$TagsTable, Tag> subtreeQuery(String path) =>
      _db.select(_db.tags)
        ..where((t) => t.path.isBiggerOrEqualValue(path))
        ..where((t) =>
            t.path.isSmallerThanValue(MaterializedPath.subtreeUpperBound(path)))
        ..where((t) => t.deletedAt.isNull());

  Future<void> insertNode({
    required String id,
    required String name,
    required String? parentId,
    String iconKey = 'tag',
    int color = 0xFF9E9E9E,
  }) async {
    String path;
    if (parentId == null) {
      path = MaterializedPath.childPath(null, id);
    } else {
      final parent = await byId(parentId);
      if (parent == null) {
        throw ArgumentError.value(parentId, 'parentId', 'No such tag');
      }
      path = MaterializedPath.childPath(parent.path, id);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.tags).insert(
          TagsCompanion.insert(
            id: id,
            name: name,
            parentId: Value(parentId),
            path: path,
            depth: MaterializedPath.depthOf(path),
            iconKey: Value(iconKey),
            color: Value(color),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<List<Tag>> subtreeOf(String id) async {
    final node = await byId(id);
    if (node == null) return const [];
    return subtreeQuery(node.path).get();
  }

  /// The same oracle as [CategoriesDao.descendantIdsViaCte], with the same
  /// caveat about soft-deleted nodes.
  Future<List<String>> descendantIdsViaCte(String id) async {
    final rows = await _db.customSelect(
      '''
      WITH RECURSIVE tree(id) AS (
        SELECT id FROM tags WHERE id = ?1
        UNION ALL
        SELECT child.id FROM tags child JOIN tree t ON child.parent_id = t.id
      )
      SELECT id FROM tree
      ''',
      variables: [Variable<String>(id)],
    ).get();
    return rows.map((r) => r.read<String>('id')).toList();
  }

  Future<void> move(String id, String? newParentId) async {
    final node = await byId(id);
    if (node == null) throw ArgumentError.value(id, 'id', 'No such tag');

    String newParentPath;
    if (newParentId == null) {
      newParentPath = '/';
    } else {
      final parent = await byId(newParentId);
      if (parent == null) {
        throw ArgumentError.value(newParentId, 'newParentId', 'No such tag');
      }
      if (parent.id == node.id ||
          MaterializedPath.isDescendant(
            path: parent.path,
            ancestorPath: node.path,
          )) {
        throw ArgumentError.value(
          newParentId,
          'newParentId',
          'Cannot move a node beneath its own descendant',
        );
      }
      newParentPath = parent.path;
    }

    final oldPath = node.path;
    final newPath = MaterializedPath.childPath(newParentPath, id);

    await _db.transaction(() async {
      final affected = await (_db.select(_db.tags)
            ..where((t) => t.path.isBiggerOrEqualValue(oldPath))
            ..where((t) => t.path.isSmallerThanValue(
                MaterializedPath.subtreeUpperBound(oldPath))))
          .get();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in affected) {
        final rewritten = MaterializedPath.reparent(
          path: row.path,
          oldAncestorPath: oldPath,
          newAncestorPath: newPath,
        );
        await (_db.update(_db.tags)..where((t) => t.id.equals(row.id))).write(
          TagsCompanion(
            path: Value(rewritten),
            depth: Value(MaterializedPath.depthOf(rewritten)),
            parentId: row.id == id ? Value(newParentId) : const Value.absent(),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }
}
