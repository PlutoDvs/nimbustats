import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../tables/categories_table.dart';
import '../analytics/saved_view.dart';
import '../tables/payment_methods_table.dart';
import '../tables/saved_views_table.dart';
import '../tables/settings_table.dart';
import '../tables/tags_table.dart';
import '../tables/tracker_entries_table.dart';
import '../tables/trackers_table.dart';
import '../tables/transaction_tags_table.dart';
import '../tables/transactions_table.dart';
import '../trackers/tracker_entries_dao.dart';
import '../trackers/trackers_dao.dart';
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
    SavedViews,
    Trackers,
    TrackerEntries,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e, {int Function(DateTime utc)? trackerOffsetAt})
      : _trackerOffsetAt = trackerOffsetAt ?? _deviceOffsetAt;

  /// The UTC offset, in minutes, that the device's zone had at an instant.
  ///
  /// Read only by the v31 backfill. A parameter so the migration test can pin
  /// it; the default is the device's real zone.
  final int Function(DateTime utc) _trackerOffsetAt;

  static int _deviceOffsetAt(DateTime utc) =>
      utc.toLocal().timeZoneOffset.inMinutes;

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
  int get schemaVersion => 32;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // v1 -> v20: Phase 3 adds saved_views. Phases 1 and 2 consumed no
          // schema version, so there is no intermediate step to write. The
          // reserved per-phase ranges in CONVENTIONS.md are what make that
          // safe rather than lucky: two branches both bumping to v2 would
          // produce a merge in which one migration silently disappears, and
          // the failure lands on a user's device, not in CI.
          if (from < 20) {
            // createTable builds the table as it is declared *now*, so this
            // path already gets v21's period columns -- which is why the v21
            // step below is an else rather than a second if. Adding them again
            // here would fail on a duplicate column.
            await m.createTable(savedViews);
            // createTable does not bring the table's indexes with it, but a
            // fresh install's createAll does. Without this line an upgraded
            // device runs the pinned-views query without its index while a
            // new install has it -- two populations on different schemas,
            // which is exactly what the migration test exists to catch.
            await m.create(idxSavedViewsPinned);
          } else if (from < 21) {
            // v20 -> v21: a saved view's period moves out of its spec, whose
            // date range is absolute. Existing rows take the defaults -- one
            // month -- which is what every v20 pin source meant.
            await m.addColumn(savedViews, savedViews.periodType);
            await m.addColumn(savedViews, savedViews.periodCount);
          }
          // v21 -> v30: Phase 4 adds trackers and their entries. New tables
          // only, so every older version takes this same step, after the
          // saved-views chain above. createTable builds the tables as they are
          // declared *now*, so this path already has v31's offset column and
          // index, and never had the day index v32 drops -- and with no
          // entries yet there is nothing to backfill, which is why the v31
          // step below is an else.
          if (from < 30) {
            await m.createTable(trackers);
            await m.createTable(trackerEntries);
            // As with saved_views: createTable leaves the indexes behind, and
            // the once-per-day index is a correctness rule rather than a
            // speed-up -- an upgraded device without it could log "done"
            // twice where a fresh install cannot.
            await m.create(idxTrackersLive);
            await m.create(idxTrackerEntriesHistory);
            await m.create(idxTrackerEntriesOncePerDay);
            await m.create(idxTrackerEntriesTrackerDay);
          } else if (from < 31) {
            // v30 -> v31: entries learn the UTC offset they were logged at,
            // without which no hour-of-day pattern can be right.
            //
            // In a transaction because drift runs onUpgrade without one and
            // records the new version only after it returns. A process killed
            // half-way through the backfill would otherwise leave a v30
            // database with the column already added, and every later start
            // would fail on addColumn. The version is written inside too, so
            // nothing separates this step's commit from its record.
            await transaction(() async {
              await m.addColumn(
                  trackerEntries, trackerEntries.tzOffsetMinutes);
              await _backfillTrackerOffsets();
              await m.create(idxTrackerEntriesTrackerDay);
              await customStatement('PRAGMA user_version = 31');
            });
          }
          // v31 -> v32: 4a's (local_date_key, tracker_id) index lost its one
          // reader, the DAO's day total, which 4b moved into the engine. Only
          // a database that reached v30 has it -- a table created later never
          // did. IF EXISTS keeps a re-run after an interrupted upgrade
          // harmless.
          if (from >= 30 && from < 32) {
            await customStatement(
                'DROP INDEX IF EXISTS idx_tracker_entries_day');
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Gives every existing entry the offset the device's zone had at that
  /// entry's own instant -- not today's, which in a zone with daylight saving
  /// would put a winter entry an hour off. Exact under Iran's fixed +3:30.
  Future<void> _backfillTrackerOffsets() async {
    final rows = await customSelect(
            'SELECT id, occurred_at_utc FROM tracker_entries')
        .get();
    for (final row in rows) {
      final at = DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('occurred_at_utc'),
          isUtc: true);
      await customStatement(
        'UPDATE tracker_entries SET tz_offset_minutes = ? WHERE id = ?',
        [_trackerOffsetAt(at), row.read<String>('id')],
      );
    }
  }

  /// Built once per database. Cheap either way, but a DAO is a handle, not a
  /// value -- handing out a fresh one per property read invites callers to
  /// assume identity that would not hold.
  late final SettingsDao settingsDao = SettingsDao(this);
  late final CategoriesDao categoriesDao = CategoriesDao(this);
  late final TagsDao tagsDao = TagsDao(this);
  late final TransactionsDao transactionsDao = TransactionsDao(this);
  late final PaymentMethodsDao paymentMethodsDao = PaymentMethodsDao(this);
  late final SavedViewsDao savedViewsDao = SavedViewsDao(this);
  late final TrackersDao trackersDao = TrackersDao(this);
  late final TrackerEntriesDao trackerEntriesDao = TrackerEntriesDao(this);
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

  /// Drops exactly [keys], so each reads back as absent.
  ///
  /// Keyed rather than "drop everything" because the table holds two kinds of
  /// row: preferences, which a reset returns to their defaults, and facts
  /// about the install (when it happened, whether its user is a founding
  /// one), which no reset should erase.
  Future<void> deleteKeys(Iterable<String> keys) =>
      (_db.delete(_db.settings)..where((t) => t.key.isIn(keys))).go();
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
/// A keyset cursor: the last row a page returned.
///
/// Declared here so `nimbus_data` and `app` name the same shape rather than
/// each inventing its own pair.
typedef TransactionCursorRow = ({DateKey dateKey, String id});

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
    int tzOffsetMinutes = 0,
    Necessity? necessity,
    Satisfaction? satisfaction,
    String? captureId,
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
            tzOffsetMinutes: Value(tzOffsetMinutes),
            categoryId: categoryId,
            source: source,
            isConfirmed: Value(isConfirmed),
            paymentMethodId: Value(paymentMethodId),
            merchant: Value(merchant),
            note: Value(note),
            necessity: Value(necessity),
            satisfaction: Value(satisfaction),
            captureId: Value(captureId),
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

  /// Keyset pagination over `(local_date_key DESC, id DESC)`.
  ///
  /// Not LIMIT/OFFSET. Offset re-counts every skipped row on each page, so it
  /// degrades exactly when the user has enough history for the app to be worth
  /// using -- and it repeats or drops rows whenever a write lands between two
  /// page fetches, which for this app is the normal case rather than the edge.
  ///
  /// UUIDv7 ids are time-ordered, so `id` is a meaningful tiebreaker within a
  /// day rather than an arbitrary one.
  Future<List<Transaction>> pageAfter({
    required DateRange range,
    TransactionCursorRow? after,
    int limit = 40,
    TxDirection? direction,
    String? categoryId,
    String? searchText,
    bool confirmedOnly = false,
  }) {
    final query = _db.select(_db.transactions)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.localDateKey.isBetweenValues(
            range.startInclusive.value,
            range.endInclusive.value,
          ))
      ..orderBy([
        (t) => OrderingTerm.desc(t.localDateKey),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);

    if (after != null) {
      query.where((t) =>
          t.localDateKey.isSmallerThanValue(after.dateKey.value) |
          (t.localDateKey.equals(after.dateKey.value) &
              t.id.isSmallerThanValue(after.id)));
    }
    if (direction != null) {
      query.where((t) => t.direction.equalsValue(direction));
    }
    if (categoryId != null) query.where((t) => t.categoryId.equals(categoryId));
    if (confirmedOnly) query.where((t) => t.isConfirmed.equals(true));

    final needle = searchText?.trim();
    if (needle != null && needle.isNotEmpty) {
      // Wildcards in user input match literally. A backslash escapes `%`, `_`,
      // and itself, and SQLite needs the ESCAPE clause spelled out for that to
      // hold -- without it, someone typing `%` matches every row they own and
      // the search silently stops being a search.
      final escaped = needle
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      final pattern = '%$escaped%';
      query.where((t) =>
          t.merchant.like(pattern, escapeChar: r'\') |
          t.note.like(pattern, escapeChar: r'\'));
    }
    return query.get();
  }

  /// A period total as one SUM.
  ///
  /// [totalInRange] pulls every row across the boundary and adds them in Dart,
  /// which was fine at Phase 0 volumes and is not fine at five thousand.
  Future<Money> sumInRange(
    DateRange range, {
    TxDirection? direction,
    bool confirmedOnly = false,
  }) async {
    final total = _db.transactions.amount.sum();
    final query = _db.selectOnly(_db.transactions)..addColumns([total]);
    var predicate = _db.transactions.deletedAt.isNull() &
        _db.transactions.localDateKey.isBetweenValues(
          range.startInclusive.value,
          range.endInclusive.value,
        );
    if (direction != null) {
      predicate = predicate & _db.transactions.direction.equalsValue(direction);
    }
    if (confirmedOnly) {
      predicate = predicate & _db.transactions.isConfirmed.equals(true);
    }
    query.where(predicate);
    final row = await query.getSingle();
    // The sum comes back as raw minor units -- SQL adds integers, and the
    // column's converter applies per row, not to an aggregate. Wrapped here so
    // the value is Money before it leaves this method and never spends a
    // moment as a number that could be mistaken for a double.
    //
    // An empty range sums to NULL in SQL, which is zero money, not an error.
    return Money(row.read(total) ?? 0);
  }

  /// Writes every mutable field. An argument left null is left alone.
  Future<void> updateTransaction(
    String id, {
    Money? amount,
    TxDirection? direction,
    String? categoryId,
    int? occurredAtUtc,
    DateKey? localDateKey,
    int? tzOffsetMinutes,
    String? paymentMethodId,
    String? merchant,
    String? note,
    Necessity? necessity,
    Satisfaction? satisfaction,
    bool? isConfirmed,
  }) =>
      (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          amount: amount == null ? const Value.absent() : Value(amount),
          direction:
              direction == null ? const Value.absent() : Value(direction),
          categoryId:
              categoryId == null ? const Value.absent() : Value(categoryId),
          occurredAtUtc: occurredAtUtc == null
              ? const Value.absent()
              : Value(occurredAtUtc),
          localDateKey:
              localDateKey == null ? const Value.absent() : Value(localDateKey),
          tzOffsetMinutes: tzOffsetMinutes == null
              ? const Value.absent()
              : Value(tzOffsetMinutes),
          paymentMethodId: paymentMethodId == null
              ? const Value.absent()
              : Value(paymentMethodId),
          merchant: merchant == null ? const Value.absent() : Value(merchant),
          note: note == null ? const Value.absent() : Value(note),
          necessity:
              necessity == null ? const Value.absent() : Value(necessity),
          satisfaction: satisfaction == null
              ? const Value.absent()
              : Value(satisfaction),
          isConfirmed:
              isConfirmed == null ? const Value.absent() : Value(isConfirmed),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  /// Writes the two reflection axes, including clearing them.
  ///
  /// Separate from [updateTransaction], where a null argument means "leave
  /// alone". These two must be settable *to* null: Phase 3's regret matrix
  /// reports unlabelled spending separately rather than dropping it, so "no
  /// answer" is a real value a user has to be able to get back to.
  Future<void> setReflection(
    String id, {
    required Necessity? necessity,
    required Satisfaction? satisfaction,
  }) =>
      (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          necessity: Value(necessity),
          satisfaction: Value(satisfaction),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  /// Writes the note, including clearing it. Same reasoning as
  /// [setReflection]: an emptied note has to become null rather than staying
  /// whatever it was.
  Future<void> setNote(String id, String? note) =>
      (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          note: Value(note),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<void> softDelete(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (_db.update(_db.transactions)..where((t) => t.id.equals(id)))
        .write(TransactionsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
  }

  Future<void> restore(String id) =>
      (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  /// The most recent category choices, newest first -- the raw material the
  /// Phase 1 category predictor ranks.
  ///
  /// Returns only the three fields the predictor reads rather than whole rows,
  /// so a prediction never drags an amount or a note across the boundary.
  Future<List<({String categoryId, String? merchant, DateTime occurredAt})>>
      recentCategoryUsage({int limit = 200}) async {
    final query = _db.select(_db.transactions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.localDateKey),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);
    final rows = await query.get();
    return [
      for (final row in rows)
        (
          categoryId: row.categoryId,
          merchant: row.merchant,
          occurredAt: DateTime.fromMillisecondsSinceEpoch(
            row.occurredAtUtc,
            isUtc: true,
          ),
        ),
    ];
  }

  /// A hard delete. `transaction_tags.transaction_id` is ON DELETE CASCADE, so
  /// the links go with the row.
  Future<void> deleteTransaction(String id) =>
      (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
}


/// Named `QuerySpec`s pinned to the dashboard.
///
/// Reads parse each row on its own, here, so there is one place that decides
/// what a malformed row means -- an [UnreadableSavedView], never a guessed
/// default -- and no caller can forget to look.
class SavedViewsDao {
  SavedViewsDao(this._db);

  final AppDatabase _db;

  /// Pinned views in the order the user arranged them, live.
  Stream<List<SavedViewEntry>> watchPinned() => (_db.select(_db.savedViews)
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.pinned.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch()
      .map((rows) => rows.map(_parse).toList());

  /// One live view, or null once it is removed.
  Stream<SavedViewEntry?> watchById(String id) => (_db.select(_db.savedViews)
        ..where((t) => t.id.equals(id))
        ..where((t) => t.deletedAt.isNull()))
      .watchSingleOrNull()
      .map((row) => row == null ? null : _parse(row));

  /// Pins [views] at the end of the dashboard, in the order given, as one
  /// transaction: the starter cards arrive together or not at all.
  ///
  /// A spec that still carries a date range is refused before anything is
  /// written. The period lives in its own columns; stripping the dates here
  /// would hide the caller's bug instead of reporting it.
  Future<void> create(List<NewSavedView> views) async {
    for (final view in views) {
      if (view.spec.filters.dateRange != null) {
        throw ArgumentError.value(
          view.spec,
          'spec',
          'a saved view stores its period apart from its spec, so the spec '
              'must carry no date range -- strip it with withDateRange(null)',
        );
      }
    }
    await _db.transaction(() async {
      // Soft-deleted rows count toward the maximum, so a removal that is
      // later undone gets its old slot back instead of sharing one.
      final highest = _db.savedViews.sortOrder.max();
      final top = await (_db.selectOnly(_db.savedViews)..addColumns([highest]))
          .map((row) => row.read(highest))
          .getSingle();
      var next = (top ?? -1) + 1;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final view in views) {
        await _db.into(_db.savedViews).insert(SavedViewsCompanion.insert(
              id: view.id,
              name: view.name,
              specJson: jsonEncode(view.spec.toJson()),
              chartType: view.chart.name,
              periodType: Value(view.period.type.name),
              periodCount: Value(view.period.count),
              pinned: const Value(true),
              sortOrder: Value(next++),
              createdAt: now,
              updatedAt: now,
            ));
      }
    });
  }

  Future<void> rename(String id, String name) async {
    final written =
        await (_db.update(_db.savedViews)..where((t) => t.id.equals(id)))
            .write(SavedViewsCompanion(
      name: Value(name),
      updatedAt: Value(_now()),
    ));
    _expectOne(written, id);
  }

  /// Makes [ids] the dashboard's order: each view's position in the list
  /// becomes its sort order. One transaction -- a half-applied order would
  /// leave two cards claiming the same slot. Callers pass every pinned view.
  Future<void> reorder(List<String> ids) => _db.transaction(() async {
        final now = _now();
        for (final (index, id) in ids.indexed) {
          final written =
              await (_db.update(_db.savedViews)..where((t) => t.id.equals(id)))
                  .write(SavedViewsCompanion(
            sortOrder: Value(index),
            updatedAt: Value(now),
          ));
          _expectOne(written, id);
        }
      });

  Future<void> softDelete(String id) async {
    final now = _now();
    final written =
        await (_db.update(_db.savedViews)..where((t) => t.id.equals(id)))
            .write(SavedViewsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
    _expectOne(written, id);
  }

  /// The undo behind "Remove". The view's sort order was never reused (see
  /// [create]), so it normally returns to the place it left. But a
  /// [reorder] between the removal and the undo re-stamps the live rows
  /// densely from 0 without knowing about the soft-deleted row, so its old
  /// slot can now also be held by a live view. Restoring inside that
  /// collision is detected and re-stamped to the end instead of leaving two
  /// rows tied on `sort_order` for SQLite to break arbitrarily.
  Future<void> restore(String id) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.savedViews)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) _expectOne(0, id);
      final collision = await (_db.select(_db.savedViews)
            ..where((t) => t.deletedAt.isNull())
            ..where((t) => t.sortOrder.equals(row!.sortOrder)))
          .getSingleOrNull();
      var sortOrder = row!.sortOrder;
      if (collision != null) {
        final highest = _db.savedViews.sortOrder.max();
        final top =
            await (_db.selectOnly(_db.savedViews)..addColumns([highest]))
                .map((r) => r.read(highest))
                .getSingle();
        sortOrder = (top ?? -1) + 1;
      }
      final written =
          await (_db.update(_db.savedViews)..where((t) => t.id.equals(id)))
              .write(SavedViewsCompanion(
        deletedAt: const Value(null),
        sortOrder: Value(sortOrder),
        updatedAt: Value(_now()),
      ));
      _expectOne(written, id);
    });
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  /// A write that matched nothing is a caller holding a stale id. Saying so
  /// beats reporting success for a rename that renamed nothing.
  static void _expectOne(int written, String id) {
    if (written != 1) throw StateError('no saved view "$id"');
  }

  /// Parses one stored row.
  ///
  /// Only what malformed stored data can throw becomes an unreadable card:
  /// [FormatException] from the parsers, [TypeError] from a JSON value of the
  /// wrong type meeting a cast, [ArgumentError] from a value type rejecting
  /// its fields. Anything else is a bug in this code and surfaces as one.
  static SavedViewEntry _parse(SavedViewRow row) {
    try {
      final decoded = jsonDecode(row.specJson);
      if (decoded is! Map<String, Object?>) {
        throw FormatException('spec is not a JSON object', row.specJson);
      }
      return SavedView(
        id: row.id,
        name: row.name,
        sortOrder: row.sortOrder,
        spec: QuerySpec.fromJson(decoded),
        period: ViewPeriod.fromStored(row.periodType, row.periodCount),
        chart: SavedViewChart.parse(row.chartType),
      );
    } on Object catch (error) {
      if (error is! FormatException &&
          error is! TypeError &&
          error is! ArgumentError) {
        rethrow;
      }
      return UnreadableSavedView(
        id: row.id,
        name: row.name,
        sortOrder: row.sortOrder,
        error: error,
      );
    }
  }
}
