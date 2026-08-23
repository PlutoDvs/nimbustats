import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/categories/data/category_repository.dart';
import 'package:nimbustats/features/categories/data/category_tree.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;

  setUp(() async {
    db = AppDatabase.openInMemory();
    repo = CategoryRepository(db.categoriesDao);
    await CategorySeeder(db).seedIfEmpty(
      roots: const [
        SeedCategoryNode(id: 'food', name: 'Food', children: [
          SeedCategoryNode(id: 'dining', name: 'Dining'),
        ]),
      ],
      uncategorizedName: 'Uncategorized',
    );
  });

  tearDown(() => db.close());

  group('the Uncategorized system row', () {
    // Every chart depends on category_id being non-null, so this row has to
    // survive anything the user does in the manager.
    test('cannot be renamed', () {
      expect(
        () => repo.rename(SystemCategoryIds.uncategorized, 'Misc'),
        throwsA(isA<SystemCategoryError>()),
      );
    });

    test('cannot be deleted', () {
      expect(() => repo.delete(SystemCategoryIds.uncategorized),
          throwsA(isA<SystemCategoryError>()));
    });

    test('cannot be archived', () {
      expect(() => repo.archive(SystemCategoryIds.uncategorized),
          throwsA(isA<SystemCategoryError>()));
    });

    test('cannot be moved under another category', () {
      expect(() => repo.move(SystemCategoryIds.uncategorized, 'food'),
          throwsA(isA<SystemCategoryError>()));
    });

    test('cannot become a parent, so it never grows a subtree', () {
      expect(() => repo.move('food', SystemCategoryIds.uncategorized),
          throwsA(isA<SystemCategoryError>()));
    });

    test('is excluded from the picker but present in the manager', () async {
      final pickable = await repo.pickableCategories();
      expect(pickable.map((c) => c.id),
          isNot(contains(SystemCategoryIds.uncategorized)));

      final tree = await repo.watchTree().first;
      expect(tree.map((n) => n.category.id),
          contains(SystemCategoryIds.uncategorized));
    });
  });

  test('create returns a usable id and places the node in the tree', () async {
    final id = await repo.create(name: 'Coffee', parentId: 'food');
    final row = await db.categoriesDao.byId(id);
    expect(row!.name, 'Coffee');
    expect(row.path, '/food/$id/');
    expect(row.depth, 1);
  });

  test('a move under its own descendant is rejected before it is attempted',
      () async {
    // Screen contract 3.4: rejecting the drop after the fact via an error toast
    // is explicitly not acceptable, so the check is a pure predicate the UI can
    // call while the drag is still in flight.
    final tree = await repo.watchTree().first;
    expect(CategoryTree.canMove(tree: tree, id: 'food', newParentId: 'dining'),
        isFalse);
    expect(CategoryTree.canMove(tree: tree, id: 'dining', newParentId: null),
        isTrue);
    expect(CategoryTree.canMove(tree: tree, id: 'food', newParentId: 'food'),
        isFalse);
    expect(
      CategoryTree.canMove(
          tree: tree,
          id: 'food',
          newParentId: SystemCategoryIds.uncategorized),
      isFalse,
    );
  });

  test('delete then restore round-trips the whole subtree', () async {
    final deleted = await repo.delete('food');
    expect(deleted, containsAll(<String>['food', 'dining']));
    expect((await repo.watchTree().first).map((n) => n.category.id),
        isNot(contains('food')));

    await repo.restore(deleted);
    expect((await repo.watchTree().first).map((n) => n.category.id),
        contains('food'));
  });

  test('watchTree nests children under parents and reports real depth',
      () async {
    final roots = await repo.watchTree().first;
    final food = roots.firstWhere((n) => n.category.id == 'food');
    expect(food.children.map((n) => n.category.id), ['dining']);
    expect(food.depth, 0);
    expect(food.children.single.depth, 1);
  });

  test('the system row cannot be dragged out of its pinned position', () {
    // It sorts at -1 so it stays above a dense 0..n-1 sibling order. A reorder
    // that included it would renumber it into the middle of the user's list.
    expect(
      () => repo.reorder(null, ['food', SystemCategoryIds.uncategorized]),
      throwsA(isA<SystemCategoryError>()),
    );
  });

  test('a live child of a deleted parent is promoted, not dropped', () async {
    // move() does not refuse a soft-deleted parent, so this is reachable. A
    // category that vanishes from the manager is unrecoverable by the user
    // while still labelling their old transactions.
    final orphan = Category(
      id: 'orphan',
      name: 'Orphan',
      iconKey: 'tag',
      color: 0xFF9E9E9E,
      parentId: 'ghost',
      path: '/ghost/orphan/',
      depth: 1,
      sortOrder: 0,
      kind: 'expense',
      archived: false,
      createdAt: 0,
      updatedAt: 0,
    );
    final tree = CategoryTree.build([orphan]);
    expect(tree.single.category.id, 'orphan');
    expect(tree.single.depth, 0);
  });
}
