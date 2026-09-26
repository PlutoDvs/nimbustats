import '../database/app_database.dart';
import 'seed_category.dart';

/// Ids the app itself owns, as opposed to ids a user created.
abstract final class SystemCategoryIds {
  /// Every transaction requires a category, so expenses logged before the user
  /// picks one -- and, from Phase 2, captures awaiting review -- land here.
  ///
  /// A fixed string rather than a generated UUID, so it is greppable, stable
  /// across reinstalls, and enforceable without an `is_system` column. Adding
  /// that column would have cost a schema version and the schema lock for one
  /// boolean; a reserved id costs nothing and the repository guards it.
  static const uncategorized = 'system-uncategorized';

  static bool isSystem(String id) => id == uncategorized;
}

/// First-run seeding of the default category tree.
///
/// Zero-config first run is a stated requirement: nobody should have to build
/// a taxonomy before logging their first expense.
final class CategorySeeder {
  const CategorySeeder(this._db);

  final AppDatabase _db;

  /// Whether the tree has ever been seeded on this database.
  ///
  /// "Seeded" means the `categories` table holds any row at all, **including
  /// soft-deleted ones**: a user who deleted every default category has made a
  /// decision, and treating that as a first run would silently undo it. Rows
  /// are only ever soft-deleted, so once this is true it stays true.
  ///
  /// The app's first-run gate asks this on launch, and [seedIfEmpty] asks it
  /// before seeding, so the two can never disagree about what "empty" means.
  Future<bool> hasSeeded() async =>
      await (_db.select(_db.categories)..limit(1)).getSingleOrNull() != null;

  /// Seeds [roots] plus the system Uncategorized row, and returns whether it
  /// did any work -- which it does only when [hasSeeded] is false.
  ///
  /// The whole thing runs in one transaction. A half-seeded tree is worse than
  /// no tree, because the emptiness check would then consider seeding done and
  /// never retry.
  Future<bool> seedIfEmpty({
    required List<SeedCategoryNode> roots,
    required String uncategorizedName,
  }) =>
      _db.transaction(() async {
        if (await hasSeeded()) return false;

        await _db.categoriesDao.insertNode(
          id: SystemCategoryIds.uncategorized,
          name: uncategorizedName,
          parentId: null,
          iconKey: 'help_outline',
          // Negative so it sorts above everything the user can reorder, whose
          // orders are a dense 0..n-1 sequence.
          sortOrder: -1,
        );

        var order = 0;
        Future<void> insertAll(
          List<SeedCategoryNode> nodes,
          String? parentId,
        ) async {
          for (final node in nodes) {
            await _db.categoriesDao.insertNode(
              id: node.id,
              name: node.name,
              parentId: parentId,
              iconKey: node.iconKey,
              color: node.color,
              kind: node.kind,
              sortOrder: order++,
            );
            await insertAll(node.children, node.id);
          }
        }

        await insertAll(roots, null);
        return true;
      });
}
