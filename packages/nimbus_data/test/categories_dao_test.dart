import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase db;
  late CategoriesDao dao;

  setUp(() async {
    db = openTestDatabase();
    dao = db.categoriesDao;
    // /food/ -> /food/dining/ -> /food/dining/fast/ ; /transport/
    await dao.insertNode(id: 'food', name: 'Food', parentId: null, sortOrder: 0);
    await dao.insertNode(
        id: 'dining', name: 'Dining', parentId: 'food', sortOrder: 0);
    await dao.insertNode(
        id: 'fast', name: 'Fast food', parentId: 'dining', sortOrder: 0);
    await dao.insertNode(
        id: 'transport', name: 'Transport', parentId: null, sortOrder: 1);
  });

  tearDown(() => db.close());

  test('rename changes the name and bumps updatedAt', () async {
    final before = (await dao.byId('food'))!;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await dao.rename('food', 'Food & drink');
    final after = (await dao.byId('food'))!;
    expect(after.name, 'Food & drink');
    expect(after.updatedAt, greaterThan(before.updatedAt));
    // Renaming must not disturb the tree: paths are built from ids, not names.
    expect(after.path, before.path);
  });

  test('updateAppearance changes only what it is given', () async {
    await dao.updateAppearance('food', iconKey: 'restaurant');
    var row = (await dao.byId('food'))!;
    expect(row.iconKey, 'restaurant');
    final colorBefore = row.color;

    await dao.updateAppearance('food', color: 0xFFEF6C00);
    row = (await dao.byId('food'))!;
    expect(row.color, 0xFFEF6C00);
    expect(row.iconKey, 'restaurant');
    expect(colorBefore, isNot(0xFFEF6C00));
  });

  test('archiving a node archives its whole subtree', () async {
    // A picker that hides Food but still offers Dining is incoherent.
    final affected = await dao.setArchivedSubtree('food', true);
    expect(affected, containsAll(<String>['food', 'dining', 'fast']));
    expect(affected, isNot(contains('transport')));

    for (final id in ['food', 'dining', 'fast']) {
      expect((await dao.byId(id))!.archived, isTrue);
    }
    expect((await dao.byId('transport'))!.archived, isFalse);
  });

  test('archived categories still resolve for historical transactions',
      () async {
    await dao.setArchivedSubtree('food', true);
    // byId is the lookup a transaction row uses; archiving must not hide it,
    // or every old chart loses its labels.
    expect(await dao.byId('food'), isNotNull);
    expect(await dao.allLive(includeArchived: true), hasLength(4));
    expect(await dao.allLive(includeArchived: false), hasLength(1));
  });

  test('soft delete removes the subtree from live queries and undo restores it',
      () async {
    final deleted = await dao.softDeleteSubtree('food');
    expect(deleted, containsAll(<String>['food', 'dining', 'fast']));
    expect(await dao.allLive(), hasLength(1));

    await dao.restoreAll(deleted);
    expect(await dao.allLive(), hasLength(4));
    expect((await dao.byId('fast'))!.deletedAt, isNull);
  });

  test('undo restores exactly the set that was deleted', () async {
    // 'fast' was deleted separately and earlier; undoing the deletion of
    // 'food' must not resurrect it.
    await dao.softDeleteSubtree('fast');
    final deleted = await dao.softDeleteSubtree('food');
    expect(deleted, isNot(contains('fast')));

    await dao.restoreAll(deleted);
    expect((await dao.byId('fast'))!.deletedAt, isNotNull);
    expect((await dao.byId('dining'))!.deletedAt, isNull);
  });

  test('reorderSiblings writes a dense ascending order', () async {
    await dao.reorderSiblings(null, ['transport', 'food']);
    expect((await dao.byId('transport'))!.sortOrder, 0);
    expect((await dao.byId('food'))!.sortOrder, 1);
  });

  test('watchAll emits on every write', () async {
    final seen = <int>[];
    final sub = dao.watchAll().listen((rows) => seen.add(rows.length));
    addTearDown(sub.cancel);

    await pumpEventQueue();
    await dao.insertNode(id: 'health', name: 'Health', parentId: null);
    await pumpEventQueue();

    expect(seen.first, 4);
    expect(seen.last, 5);
  });

  test('moving a subtree rewrites descendant paths', () async {
    // Phase 0 built and tested this; re-asserted here because Task 6 drives it
    // through the UI and a regression would be attributed to the screen.
    await dao.move('dining', 'transport');
    expect((await dao.byId('dining'))!.path, '/transport/dining/');
    expect((await dao.byId('fast'))!.path, '/transport/dining/fast/');
    expect((await dao.byId('fast'))!.depth, 2);
  });
}
