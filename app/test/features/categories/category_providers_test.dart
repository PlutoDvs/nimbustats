import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/features/categories/application/category_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.openInMemory();
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    await CategorySeeder(db).seedIfEmpty(
      roots: const [
        SeedCategoryNode(id: 'food', name: 'Food', children: [
          SeedCategoryNode(id: 'dining', name: 'Dining'),
        ]),
      ],
      uncategorizedName: 'Uncategorized',
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  test('the tree provider serves the nested tree and re-emits after a write',
      () async {
    // Hold a listener so the stream stays subscribed while it resolves.
    final sub = container.listen(categoryTreeProvider, (_, __) {});
    addTearDown(sub.close);

    final first = await container.read(categoryTreeProvider.future);
    final food = first.firstWhere((n) => n.category.id == 'food');
    expect(food.children.single.category.id, 'dining');

    await container.read(categoryRepositoryProvider).create(name: 'Coffee');
    await pumpEventQueue();

    final after = container.read(categoryTreeProvider).value!;
    expect(after.map((n) => n.category.name), contains('Coffee'));
  });
}
