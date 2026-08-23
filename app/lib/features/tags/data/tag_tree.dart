import 'package:nimbus_data/nimbus_data.dart';

/// One tag plus the tags nested underneath it.
///
/// A near-copy of `CategoryNode`, for the same reason `TagsDao` is a near-copy
/// of `CategoriesDao`: the two rows are distinct drift-generated types with no
/// shared supertype, so the only way to write this once is a generic with four
/// accessor callbacks at every call site. Two concrete implementations of
/// ninety lines of pure math read better than one abstract one, and Phase 1
/// has exactly two trees -- payment methods are flat. If a third arrives, that
/// is the moment to generalise, not before.
final class TagNode {
  const TagNode({
    required this.value,
    required this.children,
    required this.depth,
  });

  final Tag value;
  final List<TagNode> children;

  /// Depth as actually built, counting from zero at the roots. The visual
  /// indent cap is applied by the widget, so the data stays truthful.
  final int depth;
}

/// Pure tree math over the flat rows [TagsDao] returns.
abstract final class TagTree {
  /// Builds the nested tree from a flat row list.
  ///
  /// A row whose parent is absent is promoted to a root rather than dropped --
  /// see `CategoryTree.build`; a tag that vanishes from the manager is
  /// unrecoverable while it still labels the user's transactions.
  static List<TagNode> build(List<Tag> rows) {
    final byParent = <String?, List<Tag>>{};
    final ids = {for (final row in rows) row.id};
    for (final row in rows) {
      final parent = row.parentId != null && ids.contains(row.parentId)
          ? row.parentId
          : null;
      (byParent[parent] ??= <Tag>[]).add(row);
    }
    for (final siblings in byParent.values) {
      siblings.sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
      });
    }

    List<TagNode> nodesUnder(String? parentId, int depth) => [
          for (final row in byParent[parentId] ?? const <Tag>[])
            TagNode(
              value: row,
              children: nodesUnder(row.id, depth + 1),
              depth: depth,
            ),
        ];

    return nodesUnder(null, 0);
  }

  /// Depth-first flattening, parents immediately before their children.
  static List<TagNode> flatten(List<TagNode> tree) {
    final out = <TagNode>[];
    void walk(List<TagNode> nodes) {
      for (final node in nodes) {
        out.add(node);
        walk(node.children);
      }
    }

    walk(tree);
    return out;
  }

  /// Whether [id] may be dropped under [newParentId], where null is the root.
  ///
  /// Unlike categories there is no reserved row to protect, so the only
  /// invalid moves are the ones that would break the tree itself.
  static bool canMove({
    required List<TagNode> tree,
    required String id,
    required String? newParentId,
  }) {
    if (newParentId == null) return true;
    if (newParentId == id) return false;

    final node = find(tree, id);
    if (node == null) return false;
    return find(node.children, newParentId) == null;
  }

  /// The sibling order produced by dragging the row at [oldIndex] of [flat] to
  /// [newIndex], or null when the drag must be refused.
  ///
  /// [newIndex] follows `ReorderableListView.onReorderItem`: already adjusted
  /// for the removal of the dragged row. A drag that crosses sibling groups is
  /// refused rather than interpreted -- see `CategoryTree.reorderedSiblings`.
  static ({String? parentId, List<String> orderedIds})? reorderedSiblings({
    required List<TagNode> flat,
    required int oldIndex,
    required int newIndex,
  }) {
    if (oldIndex == newIndex) return null;
    if (oldIndex < 0 || oldIndex >= flat.length) return null;
    if (newIndex < 0 || newIndex >= flat.length) return null;

    final moving = flat[oldIndex].value;
    final target = flat[newIndex].value;
    if (moving.parentId != target.parentId) return null;

    final orderedIds = flat
        .map((n) => n.value)
        .where((t) => t.parentId == moving.parentId)
        .map((t) => t.id)
        .toList();
    final from = orderedIds.indexOf(moving.id);
    final to = orderedIds.indexOf(target.id);
    if (from < 0 || to < 0) return null;

    orderedIds.removeAt(from);
    orderedIds.insert(to, moving.id);
    return (parentId: moving.parentId, orderedIds: orderedIds);
  }

  /// The node for [id], or null if it is not in [tree].
  static TagNode? find(List<TagNode> tree, String id) {
    for (final node in tree) {
      if (node.value.id == id) return node;
      final hit = find(node.children, id);
      if (hit != null) return hit;
    }
    return null;
  }
}
