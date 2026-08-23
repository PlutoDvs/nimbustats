import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/tags/data/tag_repository.dart';
import 'package:nimbustats/features/tags/data/tag_tree.dart';

void main() {
  late AppDatabase db;
  late TagRepository repo;

  setUp(() {
    db = AppDatabase.openInMemory();
    repo = TagRepository(db.tagsDao);
  });

  tearDown(() => db.close());

  group('findOrCreate', () {
    test('returns the existing tag, case-insensitively', () async {
      final first = await repo.findOrCreate('Travel');
      final second = await repo.findOrCreate('travel');
      expect(second.id, first.id,
          reason: 'a user typing a different case means the same tag; two rows '
              'here would silently split their history in two');
      expect(await db.tagsDao.allLive(), hasLength(1));
    });

    test('trims, and rejects a name that is empty once trimmed', () async {
      final tag = await repo.findOrCreate('  travel  ');
      expect(tag.name, 'travel');
      expect(() => repo.findOrCreate('   '), throwsArgumentError);
      expect(await db.tagsDao.allLive(), hasLength(1));
    });

    test('nests under a parent when given one', () async {
      final parent = await repo.findOrCreate('travel');
      final child = await repo.findOrCreate('turkey-2026', parentId: parent.id);
      expect(child.path, '/${parent.id}/${child.id}/');
      expect(child.parentId, parent.id);
    });

    test('scopes the match to the parent, so the same leaf name can repeat',
        () async {
      // #work > #travel and #personal > #travel are different tags. Matching
      // globally would silently merge them.
      final work = await repo.findOrCreate('work');
      final personal = await repo.findOrCreate('personal');
      final a = await repo.findOrCreate('travel', parentId: work.id);
      final b = await repo.findOrCreate('travel', parentId: personal.id);
      expect(b.id, isNot(a.id));
    });

    test('does not resurrect a deleted tag, it creates a fresh one', () async {
      final first = await repo.findOrCreate('travel');
      await repo.delete(first.id);
      final second = await repo.findOrCreate('travel');
      expect(second.id, isNot(first.id));
    });
  });

  test('suggestions rank by usage, then by recency', () async {
    final work = await repo.findOrCreate('work');
    final travel = await repo.findOrCreate('travel');
    final food = await repo.findOrCreate('food');

    for (var i = 0; i < 3; i++) {
      await db.tagsDao.incrementUsage(work.id);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    for (var i = 0; i < 3; i++) {
      await db.tagsDao.incrementUsage(travel.id);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    for (var i = 0; i < 5; i++) {
      await db.tagsDao.incrementUsage(food.id);
    }

    final suggestions = await repo.suggestions();
    expect(suggestions.map((t) => t.name).take(3), ['food', 'travel', 'work']);
  });

  test('suggestions leave out archived tags and honour the limit', () async {
    final old = await repo.findOrCreate('old');
    await repo.archive(old.id);
    await repo.findOrCreate('a');
    await repo.findOrCreate('b');

    final suggestions = await repo.suggestions(limit: 1);
    expect(suggestions, hasLength(1));
    expect(suggestions.map((t) => t.name), isNot(contains('old')));
  });

  test('delete then restore round-trips the whole subtree', () async {
    final parent = await repo.findOrCreate('travel');
    await repo.findOrCreate('turkey-2026', parentId: parent.id);

    final deleted = await repo.delete(parent.id);
    expect(deleted, hasLength(2));
    expect(await repo.watchTree().first, isEmpty);

    await repo.restore(deleted);
    expect((await repo.watchTree().first).single.value.name, 'travel');
  });

  test('watchTree nests children under parents and reports real depth',
      () async {
    final parent = await repo.findOrCreate('travel');
    await repo.findOrCreate('turkey-2026', parentId: parent.id);

    final roots = await repo.watchTree().first;
    expect(roots.single.value.name, 'travel');
    expect(roots.single.depth, 0);
    expect(roots.single.children.single.value.name, 'turkey-2026');
    expect(roots.single.children.single.depth, 1);
  });

  test('a move under its own descendant is refused before it is attempted',
      () async {
    final parent = await repo.findOrCreate('travel');
    final child = await repo.findOrCreate('turkey-2026', parentId: parent.id);

    final tree = await repo.watchTree().first;
    expect(TagTree.canMove(tree: tree, id: parent.id, newParentId: child.id),
        isFalse);
    expect(TagTree.canMove(tree: tree, id: child.id, newParentId: null), isTrue);
  });
}
