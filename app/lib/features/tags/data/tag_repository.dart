import 'package:nimbus_data/nimbus_data.dart';

import 'tag_tree.dart';

/// The write path for the tag tree.
///
/// Structurally the same as `CategoryRepository` minus the system-row guards:
/// tags are not seeded, nothing depends on a reserved tag existing, and an
/// empty tag list is the honest first-run state rather than a bug.
final class TagRepository {
  const TagRepository(this._dao);

  final TagsDao _dao;

  /// The manager's view: every live tag, archived included, nested.
  Stream<List<TagNode>> watchTree() => _dao.watchAll().map(TagTree.build);

  /// Tags offered on the add screen, best first.
  ///
  /// Ranked by usage and then by recency, because the tag someone reaches for
  /// is overwhelmingly one they already use, and among equals the one they
  /// touched last. Archived tags are excluded -- archiving is how a user says
  /// "stop offering me this" without losing what it already labels.
  ///
  /// Bounded by [limit]: an unbounded suggestion list is a list nobody reads.
  Future<List<Tag>> suggestions({int limit = 8}) async =>
      _ranked(await _dao.allLive(includeArchived: false), limit);

  /// [suggestions] as a stream, so a tag created inline while adding an
  /// expense changes what the next expense is offered without anyone
  /// remembering to invalidate anything.
  Stream<List<Tag>> watchSuggestions({int limit = 8}) => _dao
      .watchAll(includeArchived: false)
      .map((live) => _ranked(live, limit));

  static List<Tag> _ranked(List<Tag> live, int limit) {
    final ranked = [...live]..sort((a, b) {
        final byUsage = b.usageCount.compareTo(a.usageCount);
        return byUsage != 0 ? byUsage : b.updatedAt.compareTo(a.updatedAt);
      });
    return ranked.take(limit).toList();
  }

  /// Returns the tag called [name] under [parentId], creating it if it is not
  /// there yet.
  ///
  /// This is what makes tagging possible without a trip to the tag manager,
  /// which is the friction this app exists to remove.
  ///
  /// The match is case-insensitive and trimmed: someone typing `Travel` today
  /// and `travel` tomorrow means one tag, and two rows would split that tag's
  /// history in half with nothing in the UI to explain why the numbers looked
  /// wrong. It is scoped to [parentId], so `#work > #travel` and
  /// `#personal > #travel` stay distinct.
  ///
  /// A name that is empty once trimmed throws rather than creating a blank
  /// tag -- a row nobody can find again, and nobody can delete on purpose.
  Future<Tag> findOrCreate(String name, {String? parentId}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A tag name cannot be blank');
    }

    final folded = trimmed.toLowerCase();
    final live = await _dao.allLive();
    for (final tag in live) {
      if (tag.parentId == parentId && tag.name.toLowerCase() == folded) {
        return tag;
      }
    }

    final id = await create(name: trimmed, parentId: parentId);
    // Read back rather than construct: the row carries defaults and timestamps
    // the database owns, and returning a hand-built copy would let the two
    // disagree.
    return (await _dao.byId(id))!;
  }

  /// Creates a tag and returns its generated id.
  Future<String> create({
    required String name,
    String? parentId,
    String iconKey = 'tag',
    int color = 0xFF9E9E9E,
  }) async {
    final id = Ids.newId();
    await _dao.insertNode(
      id: id,
      name: name,
      parentId: parentId,
      iconKey: iconKey,
      color: color,
    );
    return id;
  }

  Future<void> rename(String id, String name) => _dao.rename(id, name);

  Future<void> updateAppearance(String id, {String? iconKey, int? color}) =>
      _dao.updateAppearance(id, iconKey: iconKey, color: color);

  Future<void> move(String id, String? newParentId) =>
      _dao.move(id, newParentId);

  /// Archives [id] and its subtree, returning the ids touched so an undo can
  /// restore exactly that set.
  Future<List<String>> archive(String id) =>
      _dao.setArchivedSubtree(id, true);

  Future<List<String>> unarchive(String id) =>
      _dao.setArchivedSubtree(id, false);

  /// Soft-deletes [id] and its subtree, returning the ids touched.
  Future<List<String>> delete(String id) => _dao.softDeleteSubtree(id);

  /// Undoes a [delete], restoring exactly the ids it reported.
  Future<void> restore(List<String> ids) => _dao.restoreAll(ids);

  Future<void> reorder(String? parentId, List<String> orderedIds) =>
      _dao.reorderSiblings(parentId, orderedIds);

  /// Records that a tag was attached to a transaction.
  ///
  /// Called by the transaction write path rather than by the tag manager, and
  /// exposed here so `usage_count` has exactly one place that raises it.
  Future<void> recordUsage(String id) => _dao.incrementUsage(id);
}
