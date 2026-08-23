import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/categories/data/category_tree.dart';

Category cat(String id, {String? parentId, required int sortOrder}) => Category(
      id: id,
      name: id,
      iconKey: 'tag',
      color: 0xFF9E9E9E,
      parentId: parentId,
      path: parentId == null ? '/$id/' : '/$parentId/$id/',
      depth: parentId == null ? 0 : 1,
      sortOrder: sortOrder,
      kind: 'expense',
      archived: false,
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  // The order the manager renders: system row pinned on top, then Food with
  // one child, then Transport.
  final flat = CategoryTree.flatten(CategoryTree.build([
    cat(SystemCategoryIds.uncategorized, sortOrder: -1),
    cat('food', sortOrder: 0),
    cat('dining', parentId: 'food', sortOrder: 0),
    cat('transport', sortOrder: 1),
  ]));

  test('the fixture is the flat order the screen renders', () {
    expect(flat.map((n) => n.category.id), [
      SystemCategoryIds.uncategorized,
      'food',
      'dining',
      'transport',
    ]);
  });

  test('dragging a root above its sibling rewrites that sibling group', () {
    final result =
        CategoryTree.reorderedSiblings(flat: flat, oldIndex: 3, newIndex: 1);

    expect(result, isNotNull);
    expect(result!.parentId, isNull);
    // The system row keeps sortOrder -1, which is what pins it above a dense
    // 0..n-1 order, so it must not appear in the rewrite.
    expect(result.orderedIds, ['transport', 'food']);
  });

  test('a drag that crosses sibling groups is refused, not guessed', () {
    // Dropping Dining among the roots could mean re-parent or reorder. Rather
    // than pick one, the drag is refused and Move to... handles re-parenting.
    expect(
      CategoryTree.reorderedSiblings(flat: flat, oldIndex: 2, newIndex: 3),
      isNull,
    );
  });

  test('the system row cannot be dragged at all', () {
    expect(
      CategoryTree.reorderedSiblings(flat: flat, oldIndex: 0, newIndex: 2),
      isNull,
    );
  });

  test('a drag that lands where it started changes nothing', () {
    expect(
      CategoryTree.reorderedSiblings(flat: flat, oldIndex: 1, newIndex: 1),
      isNull,
    );
  });
}
