import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../tables/categories_table.dart';
import '../tables/payment_methods_table.dart';
import '../tables/settings_table.dart';
import '../tables/tags_table.dart';
import '../tables/transaction_tags_table.dart';
import '../tables/transactions_table.dart';
import '../tree/materialized_path.dart';
// Used by the generated part, which resolves imports through this library.
import 'converters.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Settings,
    Categories,
    Tags,
    PaymentMethods,
    Transactions,
    TransactionTags,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the database stored at [path].
  ///
  /// The app layer owns *where* the file lives -- it is the only layer allowed
  /// to know the platform's directory conventions, and it has `path_provider`
  /// for the purpose. This factory owns *how* it is opened. Keeping
  /// [NativeDatabase] behind this boundary is what lets
  /// `test/architecture_test.dart` assert that `app` depends on neither
  /// `drift` nor `sqlite3`: a screen that could construct a database would
  /// make the "UI cannot import the database" rule decoration.
  factory AppDatabase.openAtPath(String path) =>
      AppDatabase(NativeDatabase(File(path)));

  /// An in-memory database, fresh per call.
  ///
  /// Lives here rather than in a test helper so the app package can build one
  /// for its own widget tests without taking on a `drift` dependency.
  factory AppDatabase.openInMemory() => AppDatabase(NativeDatabase.memory());

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
  late final TransactionsDao transactionsDao = TransactionsDao(this);
  late final PaymentMethodsDao paymentMethodsDao = PaymentMethodsDao(this);
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

  Future<Map<String, String>> getAll() async {
    final rows = await _db.select(_db.settings).get();
    return {for (final row in rows) row.key: row.value};
  }

  /// Emits the whole settings map on every change.
  ///
  /// Settings are a handful of rows, so re-reading all of them costs less than
  /// tracking which key moved -- and the app's typed view is derived from the
  /// whole map anyway.
  Stream<Map<String, String>> watchAll() =>
      _db.select(_db.settings).watch().map(
            (rows) => {for (final row in rows) row.key: row.value},
          );

  /// Drops every setting, returning the app to its documented defaults.
  ///
  /// The recovery path for a value that is present but unparseable, which the
  /// app refuses to silently replace.
  Future<void> clear() => _db.delete(_db.settings).go();
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
    int sortOrder = 0,
    String kind = 'expense',
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
            sortOrder: Value(sortOrder),
            kind: Value(kind),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// The live-category query behind both [allLive] and [watchAll], so a
  /// one-shot read and a stream can never disagree about what "live" means or
  /// what order rows arrive in.
  SimpleSelectStatement<$CategoriesTable, Category> _liveQuery({
    required bool includeArchived,
  }) {
    final query = _db.select(_db.categories)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.name),
      ]);
    if (!includeArchived) query.where((t) => t.archived.equals(false));
    return query;
  }

  /// Every live category, ordered the way a picker or a manager wants them.
  Future<List<Category>> allLive({bool includeArchived = true}) =>
      _liveQuery(includeArchived: includeArchived).get();

  /// [allLive] as a stream that re-emits after every write to the table.
  ///
  /// The manager screen and the category picker both watch rather than reload,
  /// so an edit made in one is visible in the other without either knowing the
  /// other exists.
  Stream<List<Category>> watchAll({bool includeArchived = true}) =>
      _liveQuery(includeArchived: includeArchived).watch();

  Future<void> rename(String id, String name) =>
      (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
        CategoriesCompanion(
          name: Value(name),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  /// Changes icon, colour, or both. An argument left null is left alone rather
  /// than cleared -- the recolour sheet and the icon picker are separate
  /// actions, and either must be able to write without knowing the other's
  /// current value.
  Future<void> updateAppearance(String id, {String? iconKey, int? color}) =>
      (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
        CategoriesCompanion(
          iconKey: iconKey == null ? const Value.absent() : Value(iconKey),
          color: color == null ? const Value.absent() : Value(color),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  /// Archives or unarchives [id] and every live descendant, returning the ids
  /// it touched so the caller can undo exactly that set.
  ///
  /// The subtree moves as one because a picker that hides Food while still
  /// offering Food > Dining is incoherent. Archiving is not deletion: these
  /// rows still resolve through [byId], so historical transactions keep their
  /// labels.
  Future<List<String>> setArchivedSubtree(String id, bool archived) async {
    final node = await byId(id);
    if (node == null) return const [];
    return _db.transaction(() async {
      final affected = await subtreeQuery(node.path).get();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in affected) {
        await (_db.update(_db.categories)..where((t) => t.id.equals(row.id)))
            .write(CategoriesCompanion(
          archived: Value(archived),
          updatedAt: Value(now),
        ));
      }
      return affected.map((r) => r.id).toList();
    });
  }

  /// Un-deletes exactly [ids] -- the set returned by [softDeleteSubtree].
  ///
  /// Takes the explicit set rather than re-deriving the subtree, because the
  /// subtree at undo time is not the subtree that was deleted: a child the
  /// user had deleted separately and earlier must stay deleted.
  Future<void> restoreAll(List<String> ids) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.categories)..where((t) => t.id.isIn(ids))).write(
      CategoriesCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Writes a dense 0..n-1 order over [orderedIds].
  ///
  /// Dense rather than sparse (10, 20, 30) on purpose: a sibling list is
  /// short, reordering is rare and user-initiated, and a dense sequence has no
  /// renumbering edge case to get wrong later.
  Future<void> reorderSiblings(String? parentId, List<String> orderedIds) =>
      _db.transaction(() async {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (var i = 0; i < orderedIds.length; i++) {
          await (_db.update(_db.categories)
                ..where((t) => t.id.equals(orderedIds[i])))
              .write(CategoriesCompanion(
            sortOrder: Value(i),
            updatedAt: Value(now),
          ));
        }
      });

  /// Live child count per parent id. One grouped query rather than N counts,
  /// because the manager screen needs every number at once and O(N) round
  /// trips over a tree is the wrong shape at any size.
  ///
  /// A parent with no live children is absent from the map rather than present
  /// with zero.
  Future<Map<String, int>> childCounts() async {
    final parent = _db.categories.parentId;
    final count = _db.categories.id.count();
    final query = _db.selectOnly(_db.categories)
      ..addColumns([parent, count])
      ..where(_db.categories.deletedAt.isNull() & parent.isNotNull())
      ..groupBy([parent]);
    final rows = await query.get();
    return {
      for (final row in rows) row.read(parent)!: row.read(count)!,
    };
  }

  /// Soft-deletes [id] and every live descendant, returning exactly the ids it
  /// touched so an undo can restore that set and nothing else.
  ///
  /// Rows already soft-deleted are excluded -- [subtreeQuery] filters them --
  /// because restoring them would resurrect something the user deleted
  /// separately and earlier.
  Future<List<String>> softDeleteSubtree(String id) async {
    final node = await byId(id);
    if (node == null) return const [];
    return _db.transaction(() async {
      final affected = await subtreeQuery(node.path).get();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in affected) {
        await (_db.update(_db.categories)..where((t) => t.id.equals(row.id)))
            .write(CategoriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ));
      }
      return affected.map((r) => r.id).toList();
    });
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

/// Payment methods.
///
/// Flat, unlike categories and tags: a payment method answers "where did this
/// go out from", and nothing in this app ever needs one nested inside another.
/// There are no balances and no reconciliation either, by design -- nothing
/// here has to be made to add up.
class PaymentMethodsDao {
  PaymentMethodsDao(this._db);

  final AppDatabase _db;

  Future<PaymentMethod?> byId(String id) =>
      (_db.select(_db.paymentMethods)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// The live query behind both [allLive] and [watchAll], so a one-shot read
  /// and a stream cannot disagree about what "live" means.
  SimpleSelectStatement<$PaymentMethodsTable, PaymentMethod> _liveQuery({
    required bool includeArchived,
  }) {
    final query = _db.select(_db.paymentMethods)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    if (!includeArchived) query.where((t) => t.archived.equals(false));
    return query;
  }

  Future<List<PaymentMethod>> allLive({bool includeArchived = true}) =>
      _liveQuery(includeArchived: includeArchived).get();

  Stream<List<PaymentMethod>> watchAll({bool includeArchived = true}) =>
      _liveQuery(includeArchived: includeArchived).watch();

  /// Inserts a method.
  ///
  /// [last4] is constrained to exactly four characters by the column itself,
  /// so a caller that bypasses the repository still cannot store a full card
  /// number. The repository is what makes sure those four characters are
  /// Latin digits.
  Future<void> insertMethod({
    required String id,
    required String name,
    required PaymentMethodKind kind,
    String? last4,
    int color = 0xFF9E9E9E,
    String iconKey = 'card',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.paymentMethods).insert(
          PaymentMethodsCompanion.insert(
            id: id,
            name: name,
            kind: kind,
            last4: Value(last4),
            color: Value(color),
            iconKey: Value(iconKey),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// Named [updateMethod] rather than `update` to pair with [insertMethod],
  /// and so it never reads as drift's own `update`.
  Future<void> updateMethod(
    String id, {
    String? name,
    PaymentMethodKind? kind,
    String? last4,
    int? color,
    String? iconKey,
  }) =>
      (_db.update(_db.paymentMethods)..where((t) => t.id.equals(id))).write(
        PaymentMethodsCompanion(
          name: name == null ? const Value.absent() : Value(name),
          kind: kind == null ? const Value.absent() : Value(kind),
          last4: last4 == null ? const Value.absent() : Value(last4),
          color: color == null ? const Value.absent() : Value(color),
          iconKey: iconKey == null ? const Value.absent() : Value(iconKey),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<void> setArchived(String id, bool archived) =>
      (_db.update(_db.paymentMethods)..where((t) => t.id.equals(id))).write(
        PaymentMethodsCompanion(
          archived: Value(archived),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<void> softDelete(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (_db.update(_db.paymentMethods)..where((t) => t.id.equals(id)))
        .write(PaymentMethodsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
  }

  Future<void> restoreAll(List<String> ids) async {
    if (ids.isEmpty) return;
    await (_db.update(_db.paymentMethods)..where((t) => t.id.isIn(ids))).write(
      PaymentMethodsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
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
    int sortOrder = 0,
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
            sortOrder: Value(sortOrder),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// The live-tag query behind both [allLive] and [watchAll]. See
  /// [CategoriesDao] for why the two share one builder.
  SimpleSelectStatement<$TagsTable, Tag> _liveQuery({
    required bool includeArchived,
  }) {
    final query = _db.select(_db.tags)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.name),
      ]);
    if (!includeArchived) query.where((t) => t.archived.equals(false));
    return query;
  }

  Future<List<Tag>> allLive({bool includeArchived = true}) =>
      _liveQuery(includeArchived: includeArchived).get();

  Stream<List<Tag>> watchAll({bool includeArchived = true}) =>
      _liveQuery(includeArchived: includeArchived).watch();

  Future<void> rename(String id, String name) =>
      (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
        TagsCompanion(
          name: Value(name),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<void> updateAppearance(String id, {String? iconKey, int? color}) =>
      (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
        TagsCompanion(
          iconKey: iconKey == null ? const Value.absent() : Value(iconKey),
          color: color == null ? const Value.absent() : Value(color),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  /// Archives or unarchives [id] and every live descendant, returning the ids
  /// it touched. See [CategoriesDao.setArchivedSubtree].
  Future<List<String>> setArchivedSubtree(String id, bool archived) async {
    final node = await byId(id);
    if (node == null) return const [];
    return _db.transaction(() async {
      final affected = await subtreeQuery(node.path).get();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in affected) {
        await (_db.update(_db.tags)..where((t) => t.id.equals(row.id)))
            .write(TagsCompanion(
          archived: Value(archived),
          updatedAt: Value(now),
        ));
      }
      return affected.map((r) => r.id).toList();
    });
  }

  /// Soft-deletes [id] and every live descendant, returning exactly the ids it
  /// touched. See [CategoriesDao.softDeleteSubtree].
  Future<List<String>> softDeleteSubtree(String id) async {
    final node = await byId(id);
    if (node == null) return const [];
    return _db.transaction(() async {
      final affected = await subtreeQuery(node.path).get();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in affected) {
        await (_db.update(_db.tags)..where((t) => t.id.equals(row.id)))
            .write(TagsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ));
      }
      return affected.map((r) => r.id).toList();
    });
  }

  Future<void> restoreAll(List<String> ids) async {
    if (ids.isEmpty) return;
    await (_db.update(_db.tags)..where((t) => t.id.isIn(ids))).write(
      TagsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> reorderSiblings(String? parentId, List<String> orderedIds) =>
      _db.transaction(() async {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (var i = 0; i < orderedIds.length; i++) {
          await (_db.update(_db.tags)
                ..where((t) => t.id.equals(orderedIds[i])))
              .write(TagsCompanion(
            sortOrder: Value(i),
            updatedAt: Value(now),
          ));
        }
      });

  /// Bumps a tag's usage counter by one.
  ///
  /// A single `SET usage_count = usage_count + 1` rather than a read, add, and
  /// write: two transactions tagged at once would otherwise both read the same
  /// value and one increment would vanish.
  Future<void> incrementUsage(String id) => _db.customUpdate(
        'UPDATE tags SET usage_count = usage_count + 1, updated_at = ?2 '
        'WHERE id = ?1',
        variables: [
          Variable<String>(id),
          Variable<int>(DateTime.now().millisecondsSinceEpoch),
        ],
        updates: {_db.tags},
      );

  /// Rebuilds every usage count from the join table, which is the truth.
  ///
  /// `usage_count` is a denormalised cache that exists so ranking suggestions
  /// does not join on every keystroke. A cache that cannot be rebuilt is a
  /// number nobody trusts, so this is the way back: tags with no links are set
  /// to zero rather than left at whatever they had drifted to.
  Future<void> recomputeUsageCounts() => _db.transaction(() async {
        final now = DateTime.now().millisecondsSinceEpoch;
        await _db.customUpdate(
          '''
          UPDATE tags SET usage_count = (
            SELECT COUNT(*) FROM transaction_tags WHERE tag_id = tags.id
          ), updated_at = ?1
          ''',
          variables: [Variable<int>(now)],
          updates: {_db.tags},
        );
      });

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

/// Transactions and their tag links.
class TransactionsDao {
  TransactionsDao(this._db);

  final AppDatabase _db;

  Future<void> insertTransaction({
    required String id,
    required TxDirection direction,
    required Money amount,
    required String currencyCode,
    required int occurredAtUtc,
    required DateKey localDateKey,
    required String categoryId,
    required TxSource source,
    bool isConfirmed = true,
    String? paymentMethodId,
    String? merchant,
    String? note,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            direction: direction,
            amount: amount,
            currencyCode: currencyCode,
            occurredAtUtc: occurredAtUtc,
            localDateKey: localDateKey,
            categoryId: categoryId,
            source: source,
            isConfirmed: Value(isConfirmed),
            paymentMethodId: Value(paymentMethodId),
            merchant: Value(merchant),
            note: Value(note),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<Transaction?> byId(String id) =>
      (_db.select(_db.transactions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// The period query, exposed so callers can compose further filters on it and
  /// so a test can assert its query plan still uses the date index.
  SimpleSelectStatement<$TransactionsTable, Transaction> inRangeQuery(
    DateRange range, {
    bool confirmedOnly = false,
  }) {
    final query = _db.select(_db.transactions)
      ..where((t) => t.localDateKey.isBetweenValues(
            range.startInclusive.value,
            range.endInclusive.value,
          ))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.localDateKey)]);
    if (confirmedOnly) {
      query.where((t) => t.isConfirmed.equals(true));
    }
    return query;
  }

  Future<List<Transaction>> inRange(
    DateRange range, {
    bool confirmedOnly = false,
  }) =>
      inRangeQuery(range, confirmedOnly: confirmedOnly).get();

  /// Sums in Dart rather than in SQL, which means the whole range crosses the
  /// boundary to be added up. Fine at Phase 0 sizes and it keeps the exact
  /// integer arithmetic in one place; when analytics arrives this should become
  /// a SUM() aggregate so a year of rows is one row on the wire.
  ///
  /// Note it counts income and expense alike, and includes unconfirmed rows.
  /// Deciding what a "total" means is analytics' job, not storage's.
  Future<Money> totalInRange(DateRange range) async {
    final rows = await inRange(range);
    return Money.sum(rows.map((t) => t.amount));
  }

  /// Replaces the whole tag set for a transaction. Duplicates in [tagIds] are
  /// collapsed, and the join table's composite key would reject them anyway.
  Future<void> setTags(String transactionId, List<String> tagIds) async {
    await _db.transaction(() async {
      await (_db.delete(_db.transactionTags)
            ..where((t) => t.transactionId.equals(transactionId)))
          .go();
      for (final tagId in tagIds.toSet()) {
        await _db.into(_db.transactionTags).insert(
              TransactionTagsCompanion.insert(
                transactionId: transactionId,
                tagId: tagId,
              ),
            );
      }
    });
  }

  Future<List<String>> tagsOf(String transactionId) async {
    final rows = await (_db.select(_db.transactionTags)
          ..where((t) => t.transactionId.equals(transactionId)))
        .get();
    return rows.map((r) => r.tagId).toList();
  }

  /// A hard delete. `transaction_tags.transaction_id` is ON DELETE CASCADE, so
  /// the links go with the row.
  Future<void> deleteTransaction(String id) =>
      (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
}
