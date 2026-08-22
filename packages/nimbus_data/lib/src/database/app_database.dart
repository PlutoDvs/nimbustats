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
