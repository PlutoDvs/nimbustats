import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';

const _tree = <SeedCategoryNode>[
  SeedCategoryNode(
    id: 'seed-food',
    name: 'Food',
    iconKey: 'restaurant',
    color: 0xFFEF6C00,
    children: [
      SeedCategoryNode(id: 'seed-food-groceries', name: 'Groceries'),
      SeedCategoryNode(id: 'seed-food-dining', name: 'Dining out'),
    ],
  ),
  SeedCategoryNode(id: 'seed-transport', name: 'Transport'),
  SeedCategoryNode(id: 'seed-salary', name: 'Salary', kind: 'income'),
];

void main() {
  late AppDatabase db;
  late CategorySeeder seeder;

  setUp(() {
    db = openTestDatabase();
    seeder = CategorySeeder(db);
  });

  tearDown(() => db.close());

  Future<bool> seed({String uncategorizedName = 'Uncategorized'}) =>
      seeder.seedIfEmpty(roots: _tree, uncategorizedName: uncategorizedName);

  test('seeds the tree and reports that it did', () async {
    expect(await seed(), isTrue);
    // three roots, two children, plus the system row
    expect(await db.categoriesDao.allLive(), hasLength(6));
  });

  test('creates the system Uncategorized row at the root', () async {
    await seed();

    final row = await db.categoriesDao.byId(SystemCategoryIds.uncategorized);
    expect(row, isNotNull);
    expect(row!.name, 'Uncategorized');
    expect(row.parentId, isNull);
    expect(row.path, '/${SystemCategoryIds.uncategorized}/');
    expect(row.depth, 0);
    expect(SystemCategoryIds.isSystem(row.id), isTrue);
    expect(SystemCategoryIds.isSystem('seed-food'), isFalse);
  });

  test('the system row sorts above everything the user can reorder', () async {
    await seed();
    final system = await db.categoriesDao.byId(SystemCategoryIds.uncategorized);
    final food = await db.categoriesDao.byId('seed-food');
    expect(system!.sortOrder, lessThan(food!.sortOrder));
  });

  test('builds correct materialized paths and depths for children', () async {
    await seed();

    final groceries = await db.categoriesDao.byId('seed-food-groceries');
    expect(groceries!.path, '/seed-food/seed-food-groceries/');
    expect(groceries.depth, 1);
    expect(groceries.parentId, 'seed-food');

    final food = await db.categoriesDao.byId('seed-food');
    expect(food!.path, '/seed-food/');
    expect(food.depth, 0);
    expect(food.parentId, isNull);
  });

  test('preserves the declared order as sortOrder', () async {
    await seed();
    final food = await db.categoriesDao.byId('seed-food');
    final transport = await db.categoriesDao.byId('seed-transport');
    expect(food!.sortOrder, lessThan(transport!.sortOrder));

    final groceries = await db.categoriesDao.byId('seed-food-groceries');
    final dining = await db.categoriesDao.byId('seed-food-dining');
    expect(groceries!.sortOrder, lessThan(dining!.sortOrder));
  });

  test('carries the declared kind and appearance', () async {
    await seed();
    expect((await db.categoriesDao.byId('seed-salary'))!.kind, 'income');
    final food = (await db.categoriesDao.byId('seed-food'))!;
    expect(food.kind, 'expense');
    expect(food.iconKey, 'restaurant');
    expect(food.color, 0xFFEF6C00);
  });

  test('is idempotent: a second run changes nothing', () async {
    await seed();
    final before = await db.categoriesDao.allLive();

    expect(await seed(uncategorizedName: 'Different'), isFalse);

    expect(await db.categoriesDao.allLive(), hasLength(before.length));
    // The name must not be rewritten either: a user who renamed a seeded
    // category would otherwise lose that on the next launch.
    expect((await db.categoriesDao.byId(SystemCategoryIds.uncategorized))!.name,
        'Uncategorized');
  });

  test('a renamed seeded category survives a second run', () async {
    await seed();
    await db.categoriesDao.rename('seed-food', 'Groceries & eating out');
    await seed();
    expect((await db.categoriesDao.byId('seed-food'))!.name,
        'Groceries & eating out');
  });

  test('a soft-deleted tree still counts as seeded', () async {
    await seed();
    await db.categoriesDao.softDeleteSubtree('seed-transport');

    expect(await seed(), isFalse,
        reason: 'a user who deleted a default category has made a decision, '
            'and re-seeding on the next launch would silently undo it');
    expect((await db.categoriesDao.byId('seed-transport'))!.deletedAt,
        isNotNull);
  });

  test('a failure part-way through leaves no rows behind', () async {
    // Two nodes sharing an id violates the primary key on the second insert.
    const broken = <SeedCategoryNode>[
      SeedCategoryNode(id: 'dup', name: 'First'),
      SeedCategoryNode(id: 'dup', name: 'Second'),
    ];
    await expectLater(
      seeder.seedIfEmpty(roots: broken, uncategorizedName: 'Uncategorized'),
      throwsA(anything),
    );
    expect(await db.categoriesDao.allLive(), isEmpty,
        reason: 'seeding is transactional; a half-seeded tree is worse than '
            'none, because the emptiness check would then consider seeding '
            'already done and never retry');
  });

  test('an empty root list still creates the system row', () async {
    // Nothing depends on this today, but a caller passing an empty tree must
    // not produce a database where a transaction has no category to point at.
    expect(
      await seeder.seedIfEmpty(roots: const [], uncategorizedName: 'None'),
      isTrue,
    );
    expect(await db.categoriesDao.byId(SystemCategoryIds.uncategorized),
        isNotNull);
  });

  group('Ids', () {
    test('generates unique identifiers', () {
      final ids = List.generate(200, (_) => Ids.newId());
      expect(ids.toSet(), hasLength(200));
    });

    test('identifiers sort chronologically across milliseconds', () async {
      // UUIDv7 leads with a millisecond timestamp, so lexical order is
      // chronological order -- which is what lets keyset pagination use `id`
      // as a meaningful tiebreaker for two transactions on the same day.
      //
      // The guarantee is across milliseconds, not within one: ids minted
      // inside a single millisecond differ only in random bits. That is fine
      // for pagination, which needs a *stable total order*, not a record of
      // which of two simultaneous inserts happened first.
      final ids = <String>[];
      for (var i = 0; i < 8; i++) {
        ids.add(Ids.newId());
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      expect([...ids]..sort(), ids);
    });

    test('produces canonical uuid text', () {
      final id = Ids.newId();
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });
  });
}
