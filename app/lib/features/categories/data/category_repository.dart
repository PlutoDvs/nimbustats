import 'package:nimbus_data/nimbus_data.dart';

import 'category_tree.dart';

/// Thrown when something tries to mutate the reserved Uncategorized row.
///
/// An [Error], not an [Exception]: reaching it means the UI offered an action
/// it should have disabled, which is a programming mistake rather than a
/// condition a caller is expected to recover from.
final class SystemCategoryError extends Error {
  SystemCategoryError(this.id, this.action);

  final String id;
  final String action;

  @override
  String toString() =>
      'Cannot $action the system category "$id". It is required to exist '
      'because every transaction must resolve to a category.';
}

/// The write path for the category tree, and the only place the system-row
/// rules are enforced.
///
/// Guards throw *synchronously*, before the returned future is created, so an
/// unawaited call still surfaces the mistake at the call site rather than
/// several turns later on an error zone.
final class CategoryRepository {
  const CategoryRepository(this._dao);

  final CategoriesDao _dao;

  /// The manager's view: every live category, archived ones included, nested.
  ///
  /// Includes the Uncategorized row -- the user must be able to see and
  /// recolour it even though they cannot rename or remove it.
  Stream<List<CategoryNode>> watchTree() =>
      _dao.watchAll().map(CategoryTree.build);

  /// The picker's view: flat, archived excluded, system row excluded.
  ///
  /// Uncategorized is where an uncategorized expense lands, not something a
  /// user picks on purpose; offering it as a normal choice would make the
  /// "review these" queries in Phase 2 meaningless.
  Future<List<Category>> pickableCategories() async {
    final rows = await _dao.allLive(includeArchived: false);
    return rows.where((c) => !SystemCategoryIds.isSystem(c.id)).toList();
  }

  /// Creates a category and returns its generated id.
  Future<String> create({
    required String name,
    String? parentId,
    String iconKey = 'tag',
    int color = 0xFF9E9E9E,
    String kind = 'expense',
  }) {
    if (parentId != null) _guard(parentId, 'nest a category under');
    final id = Ids.newId();
    return _dao
        .insertNode(
          id: id,
          name: name,
          parentId: parentId,
          iconKey: iconKey,
          color: color,
          kind: kind,
        )
        .then((_) => id);
  }

  Future<void> rename(String id, String name) {
    _guard(id, 'rename');
    return _dao.rename(id, name);
  }

  Future<void> updateAppearance(String id, {String? iconKey, int? color}) =>
      _dao.updateAppearance(id, iconKey: iconKey, color: color);

  Future<void> move(String id, String? newParentId) {
    _guard(id, 'move');
    if (newParentId != null) _guard(newParentId, 'nest a category under');
    return _dao.move(id, newParentId);
  }

  /// Archives [id] and its subtree, returning the ids touched so an undo can
  /// restore exactly that set.
  Future<List<String>> archive(String id) {
    _guard(id, 'archive');
    return _dao.setArchivedSubtree(id, true);
  }

  Future<List<String>> unarchive(String id) {
    _guard(id, 'unarchive');
    return _dao.setArchivedSubtree(id, false);
  }

  /// Soft-deletes [id] and its subtree, returning the ids touched.
  Future<List<String>> delete(String id) {
    _guard(id, 'delete');
    return _dao.softDeleteSubtree(id);
  }

  /// Undoes a [delete], restoring exactly the ids it reported.
  Future<void> restore(List<String> ids) => _dao.restoreAll(ids);

  Future<void> reorder(String? parentId, List<String> orderedIds) {
    for (final id in orderedIds) {
      _guard(id, 'reorder');
    }
    return _dao.reorderSiblings(parentId, orderedIds);
  }

  void _guard(String id, String action) {
    if (SystemCategoryIds.isSystem(id)) throw SystemCategoryError(id, action);
  }
}
