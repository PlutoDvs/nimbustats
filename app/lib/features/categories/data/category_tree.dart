import 'package:nimbus_data/nimbus_data.dart';

/// One category plus the children rendered underneath it.
final class CategoryNode {
  const CategoryNode({
    required this.category,
    required this.children,
    required this.depth,
  });

  final Category category;
  final List<CategoryNode> children;

  /// Depth in the tree as actually built, counting from zero at the roots.
  ///
  /// This is the real depth, not a display value: the visual indent cap from
  /// `NimbusTokens.maxTreeIndentDepth` is applied by the widget, so the data
  /// never lies about where a node sits.
  final int depth;
}

/// Pure tree math over the flat rows the DAO returns.
///
/// Deliberately free of database access so the manager screen can answer
/// questions -- above all "may this drop happen?" -- synchronously, while a
/// drag is still in flight.
abstract final class CategoryTree {
  /// Builds the nested tree from a flat row list.
  ///
  /// Siblings are ordered by `(sortOrder, name)` here as well as in SQL, so a
  /// caller that passes rows from anywhere else still gets the tree the app
  /// displays.
  ///
  /// A row whose parent is absent from [rows] is promoted to a root rather
  /// than dropped. That happens when a parent is soft-deleted while a child
  /// survives; dropping it would erase a category from the manager while it
  /// still labels the user's historical transactions, leaving them no way to
  /// reach it.
  static List<CategoryNode> build(List<Category> rows) {
    final byParent = <String?, List<Category>>{};
    final ids = {for (final row in rows) row.id};
    for (final row in rows) {
      final parent =
          row.parentId != null && ids.contains(row.parentId) ? row.parentId : null;
      (byParent[parent] ??= <Category>[]).add(row);
    }
    for (final siblings in byParent.values) {
      siblings.sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
      });
    }

    List<CategoryNode> nodesUnder(String? parentId, int depth) => [
          for (final row in byParent[parentId] ?? const <Category>[])
            CategoryNode(
              category: row,
              children: nodesUnder(row.id, depth + 1),
              depth: depth,
            ),
        ];

    return nodesUnder(null, 0);
  }

  /// Whether [id] may be dropped under [newParentId], where null means the
  /// root.
  ///
  /// A predicate rather than a failed write: the screen contract forbids
  /// accepting a drop and then undoing it with an error toast, so the answer
  /// has to be available before the finger lifts.
  static bool canMove({
    required List<CategoryNode> tree,
    required String id,
    required String? newParentId,
  }) {
    if (SystemCategoryIds.isSystem(id)) return false;
    if (newParentId == null) return true;
    if (SystemCategoryIds.isSystem(newParentId)) return false;
    if (newParentId == id) return false;

    final node = find(tree, id);
    if (node == null) return false;
    return !_contains(node.children, newParentId);
  }

  /// The node for [id], or null if it is not in [tree].
  static CategoryNode? find(List<CategoryNode> tree, String id) {
    for (final node in tree) {
      if (node.category.id == id) return node;
      final hit = find(node.children, id);
      if (hit != null) return hit;
    }
    return null;
  }

  static bool _contains(List<CategoryNode> nodes, String id) =>
      find(nodes, id) != null;
}
