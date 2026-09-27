import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import 'support/analytics_fixture.dart';

void main() {
  late AppDatabase db;
  late AnalyticsEngine engine;

  setUp(() async {
    db = openTestDatabase();
    await seedAnalyticsFixture(db);
    engine = AnalyticsEngine(db, calendar: const GregorianCalendar());
  });
  tearDown(() => db.close());

  /// How many times [AnalyticsEngine.changes] fires across [write].
  Future<int> firingsDuring(Future<void> Function() write) async {
    var count = 0;
    final subscription = engine.changes().listen((_) => count++);
    await pumpEventQueue();
    await write();
    await pumpEventQueue();
    await subscription.cancel();
    return count;
  }

  test('a transaction write fires', () async {
    expect(
      await firingsDuring(() => db.transactionsDao.setNote('t1', 'lunch')),
      greaterThan(0),
    );
  });

  test('a transaction-tag write fires', () async {
    expect(
      await firingsDuring(() => db.transactionsDao.setTags('t3', ['food'])),
      greaterThan(0),
    );
  });

  test('a category or tag write fires', () async {
    // Their paths are what subtree filters and rollups resolve against, so a
    // moved category changes answers without touching a transaction.
    expect(
      await firingsDuring(() async => db.markTablesUpdated({db.categories})),
      greaterThan(0),
    );
    expect(
      await firingsDuring(() async => db.markTablesUpdated({db.tags})),
      greaterThan(0),
    );
  });

  test('a settings write does not fire', () async {
    // Re-running every open chart for a theme change would be wasted work.
    expect(await firingsDuring(() => db.settingsDao.put('theme', 'dark')), 0);
  });
}
