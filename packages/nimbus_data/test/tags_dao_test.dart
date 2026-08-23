import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase db;
  late TagsDao dao;

  setUp(() async {
    db = openTestDatabase();
    dao = db.tagsDao;
    // /travel/ -> /travel/turkey/ ; /work/
    await dao.insertNode(
        id: 'travel', name: 'travel', parentId: null, sortOrder: 0);
    await dao.insertNode(
        id: 'turkey', name: 'turkey-2026', parentId: 'travel', sortOrder: 0);
    await dao.insertNode(
        id: 'work', name: 'work', parentId: null, sortOrder: 1);
  });

  tearDown(() => db.close());

  test('rename changes the name and bumps updatedAt', () async {
    final before = (await dao.byId('travel'))!;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await dao.rename('travel', 'holiday');
    final after = (await dao.byId('travel'))!;
    expect(after.name, 'holiday');
    expect(after.updatedAt, greaterThan(before.updatedAt));
    expect(after.path, before.path);
  });

  test('updateAppearance changes only what it is given', () async {
    await dao.updateAppearance('travel', iconKey: 'flight');
    var row = (await dao.byId('travel'))!;
    expect(row.iconKey, 'flight');

    await dao.updateAppearance('travel', color: 0xFF1565C0);
    row = (await dao.byId('travel'))!;
    expect(row.color, 0xFF1565C0);
    expect(row.iconKey, 'flight');
  });

  test('archiving a tag archives its whole subtree', () async {
    final affected = await dao.setArchivedSubtree('travel', true);
    expect(affected, containsAll(<String>['travel', 'turkey']));
    expect(affected, isNot(contains('work')));

    expect((await dao.byId('turkey'))!.archived, isTrue);
    expect((await dao.byId('work'))!.archived, isFalse);
    // Archived is not deleted: a transaction tagged #turkey-2026 last year must
    // still resolve its label.
    expect(await dao.byId('turkey'), isNotNull);
    expect(await dao.allLive(includeArchived: false), hasLength(1));
  });

  test('soft delete removes the subtree and undo restores exactly it',
      () async {
    // 'turkey' was deleted separately and earlier, so undoing 'travel' must
    // not resurrect it.
    await dao.softDeleteSubtree('turkey');
    final deleted = await dao.softDeleteSubtree('travel');
    expect(deleted, isNot(contains('turkey')));

    await dao.restoreAll(deleted);
    expect((await dao.byId('turkey'))!.deletedAt, isNotNull);
    expect((await dao.byId('travel'))!.deletedAt, isNull);
  });

  test('reorderSiblings writes a dense ascending order', () async {
    await dao.reorderSiblings(null, ['work', 'travel']);
    expect((await dao.byId('work'))!.sortOrder, 0);
    expect((await dao.byId('travel'))!.sortOrder, 1);
  });

  test('watchAll emits on every write', () async {
    final seen = <int>[];
    final sub = dao.watchAll().listen((rows) => seen.add(rows.length));
    addTearDown(sub.cancel);

    await pumpEventQueue();
    await dao.insertNode(id: 'health', name: 'health', parentId: null);
    await pumpEventQueue();

    expect(seen.first, 3);
    expect(seen.last, 4);
  });

  test('nested tags roll up through the materialized path', () async {
    final subtree = await dao.subtreeOf('travel');
    expect(subtree.map((t) => t.id), containsAll(<String>['travel', 'turkey']));
  });

  test('moving a subtree rewrites descendant paths', () async {
    await dao.move('turkey', 'work');
    expect((await dao.byId('turkey'))!.path, '/work/turkey/');
    expect((await dao.byId('turkey'))!.depth, 1);
  });

  test('usage count rises when a tag is attached', () async {
    expect((await dao.byId('travel'))!.usageCount, 0);
    await dao.incrementUsage('travel');
    await dao.incrementUsage('travel');
    expect((await dao.byId('travel'))!.usageCount, 2);
  });

  test('recomputeUsageCounts rebuilds from the join table', () async {
    // usage_count is a cache. Anything that can drift needs a way back to the
    // truth, or it becomes a number nobody trusts and everybody ignores.
    await dao.incrementUsage('travel');
    await dao.incrementUsage('travel');
    expect((await dao.byId('travel'))!.usageCount, 2);

    await dao.recomputeUsageCounts();
    expect((await dao.byId('travel'))!.usageCount, 0);
  });

  test('recomputeUsageCounts counts the links that actually exist', () async {
    await db.categoriesDao.insertNode(id: 'food', name: 'Food', parentId: null);
    const day = DateKey(20260823);
    await db.transactionsDao.insertTransaction(
      id: 'tx-1',
      direction: TxDirection.expense,
      amount: const Money(1000),
      currencyCode: 'IRT',
      occurredAtUtc: day.toDateTime().millisecondsSinceEpoch,
      localDateKey: day,
      categoryId: 'food',
      source: TxSource.manual,
    );
    await db.transactionsDao.setTags('tx-1', ['travel', 'turkey']);

    // Deliberately wrong beforehand, so a no-op implementation cannot pass.
    await dao.incrementUsage('travel');
    await dao.incrementUsage('travel');
    await dao.incrementUsage('travel');

    await dao.recomputeUsageCounts();
    expect((await dao.byId('travel'))!.usageCount, 1);
    expect((await dao.byId('turkey'))!.usageCount, 1);
    expect((await dao.byId('work'))!.usageCount, 0);
  });
}
