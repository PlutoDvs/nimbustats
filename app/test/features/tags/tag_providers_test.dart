import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/provider_retry.dart';
import 'package:nimbustats/features/tags/application/tag_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.openInMemory();
    container = ProviderContainer(
      retry: nimbusNoRetry,
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  test('the tree provider starts empty and re-emits after a write', () async {
    // Tags are not seeded, so empty is the real first-run state rather than a
    // condition that only shows up when something has gone wrong.
    final sub = container.listen(tagTreeProvider, (_, __) {});
    addTearDown(sub.close);

    expect(await container.read(tagTreeProvider.future), isEmpty);

    await container.read(tagRepositoryProvider).findOrCreate('travel');
    await pumpEventQueue();

    expect(
      container.read(tagTreeProvider).value!.map((n) => n.value.name),
      ['travel'],
    );
  });

  test('the suggestion provider ranks by usage and drops archived tags',
      () async {
    final sub = container.listen(tagSuggestionsProvider, (_, __) {});
    addTearDown(sub.close);

    final repo = container.read(tagRepositoryProvider);
    await repo.findOrCreate('quiet');
    final busy = await repo.findOrCreate('busy');
    final hidden = await repo.findOrCreate('hidden');
    await repo.recordUsage(busy.id);
    await repo.recordUsage(hidden.id);
    await repo.recordUsage(hidden.id);
    await repo.archive(hidden.id);
    await pumpEventQueue();

    final ranked = container.read(tagSuggestionsProvider).value!;
    expect(ranked.map((t) => t.name), ['busy', 'quiet']);
    expect(ranked.map((t) => t.id), isNot(contains(hidden.id)));
  });
}
