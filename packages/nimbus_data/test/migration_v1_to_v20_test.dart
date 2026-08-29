import 'package:drift_dev/api/migrations_native.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('a v1 database upgrades to v20 and matches a fresh install', () async {
    // The point of a migration test is not that the upgrade runs -- it is that
    // the schema it produces is identical to the one a new install creates.
    // A migration that half-works leaves two populations of users on subtly
    // different schemas, and the divergence surfaces phases later.
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 20);
  });

  test('saved_views is usable immediately after the upgrade', () async {
    // Validating the shape is not the same as proving the table works. This
    // writes and reads through the real DAO on a migrated database.
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 20);

    const spec = QuerySpec(
        filters: QueryFilters(),
        groupBy: GroupByNone(),
        aggregate: Aggregate.sum);
    await db.savedViewsDao.upsert(
      id: 'after-migration',
      name: 'Still works',
      spec: spec,
      chartType: 'bar',
      pinned: true,
      sortOrder: 0,
    );
    final loaded = await db.savedViewsDao.byId('after-migration');
    expect(loaded, isNotNull);
    expect(loaded!.spec, spec);
  });
}
