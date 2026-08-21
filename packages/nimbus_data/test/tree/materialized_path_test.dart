import 'package:drift/drift.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  Future<void> seedTree() async {
    await db.categoriesDao.insertNode(id: 'food', name: 'Food', parentId: null);
    await db.categoriesDao
        .insertNode(id: 'dining', name: 'Dining out', parentId: 'food');
    await db.categoriesDao
        .insertNode(id: 'fast', name: 'Fast food', parentId: 'dining');
    await db.categoriesDao
        .insertNode(id: 'grocery', name: 'Groceries', parentId: 'food');
    await db.categoriesDao
        .insertNode(id: 'transport', name: 'Transport', parentId: null);
  }

  test('builds paths with leading and trailing slashes', () async {
    await seedTree();
    final fast = await db.categoriesDao.byId('fast');
    expect(fast!.path, '/food/dining/fast/');
    expect(fast.depth, 2);

    final root = await db.categoriesDao.byId('food');
    expect(root!.path, '/food/');
    expect(root.depth, 0);
  });

  test('subtree includes the node and all descendants', () async {
    await seedTree();
    final ids =
        (await db.categoriesDao.subtreeOf('food')).map((c) => c.id).toSet();
    expect(ids, {'food', 'dining', 'fast', 'grocery'});
  });

  test('subtree of a leaf is just the leaf', () async {
    await seedTree();
    final ids =
        (await db.categoriesDao.subtreeOf('fast')).map((c) => c.id).toSet();
    expect(ids, {'fast'});
  });

  test('materialized path agrees with a recursive CTE oracle', () async {
    await seedTree();
    for (final id in ['food', 'dining', 'fast', 'grocery', 'transport']) {
      final viaPath =
          (await db.categoriesDao.subtreeOf(id)).map((c) => c.id).toSet();
      final viaCte = (await db.categoriesDao.descendantIdsViaCte(id)).toSet();
      expect(viaPath, viaCte, reason: 'subtree mismatch for $id');
    }
  });

  test('moving a node rewrites the paths of its whole subtree', () async {
    await seedTree();
    await db.categoriesDao.move('dining', 'transport');

    final dining = await db.categoriesDao.byId('dining');
    expect(dining!.path, '/transport/dining/');
    expect(dining.depth, 1);

    final fast = await db.categoriesDao.byId('fast');
    expect(fast!.path, '/transport/dining/fast/');
    expect(fast.depth, 2);

    final foodSubtree =
        (await db.categoriesDao.subtreeOf('food')).map((c) => c.id).toSet();
    expect(foodSubtree, {'food', 'grocery'});
  });

  test('moving a node to the root works', () async {
    await seedTree();
    await db.categoriesDao.move('dining', null);
    final dining = await db.categoriesDao.byId('dining');
    expect(dining!.path, '/dining/');
    expect(dining.depth, 0);
  });

  test('a node cannot be moved beneath its own descendant', () async {
    await seedTree();
    expect(
      () => db.categoriesDao.move('food', 'fast'),
      throwsArgumentError,
    );
  });

  test('tags support the same nesting', () async {
    await db.tagsDao.insertNode(id: 'travel', name: 'travel', parentId: null);
    await db.tagsDao
        .insertNode(id: 'turkey', name: 'turkey-2026', parentId: 'travel');
    final ids = (await db.tagsDao.subtreeOf('travel')).map((t) => t.id).toSet();
    expect(ids, {'travel', 'turkey'});
  });

  test('subtree lookup is an indexed range scan, not a table scan', () async {
    // The entire reason for storing a materialized path is that rollup becomes
    // an index seek. If the query ever stops using the index, every analytics
    // aggregation silently degrades to a full scan of the category table and
    // nothing else in the suite would notice.
    await seedTree();
    final query = db.categoriesDao.subtreeQuery('/food/').constructQuery();
    final plan = await db.customSelect(
      'EXPLAIN QUERY PLAN ${query.sql}',
      variables: query.boundVariables
          .map((v) => Variable<String>(v as String))
          .toList(),
    ).get();
    final detail = plan.map((r) => r.read<String>('detail')).join(' | ');
    expect(detail, contains('idx_categories_path'), reason: 'plan: $detail');
    expect(detail, isNot(contains('SCAN categories')), reason: 'plan: $detail');
  });

  test('ids sharing a prefix or holding LIKE wildcards stay separate subtrees',
      () async {
    await seedTree();
    await db.categoriesDao
        .insertNode(id: 'foodstuff', name: 'Foodstuff', parentId: null);
    await db.categoriesDao
        .insertNode(id: 'fo_d', name: 'Wildcard id', parentId: null);
    await db.categoriesDao
        .insertNode(id: 'child', name: 'Child', parentId: 'fo_d');

    // A prefix match must respect the trailing slash: '/foodstuff/' is not
    // inside '/food/'.
    expect((await db.categoriesDao.subtreeOf('food')).map((c) => c.id).toSet(),
        {'food', 'dining', 'fast', 'grocery'});

    // As a LIKE pattern, '/fo_d/%' matches '/food/...' too, because _ is a
    // single-character wildcard. A range scan has no metacharacters.
    expect((await db.categoriesDao.subtreeOf('fo_d')).map((c) => c.id).toSet(),
        {'fo_d', 'child'});
  });
}
