import 'package:drift_dev/api/migrations_native.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  // The point of a migration test is not that the upgrade runs -- it is that
  // the schema it produces is identical to the one a new install creates.
  // A migration that half-works leaves two populations of users on subtly
  // different schemas, and the divergence surfaces phases later.
  test('a v1 database upgrades to v21 and matches a fresh install', () async {
    final db = AppDatabase(await verifier.startAt(1));
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 21);
  });

  test('a v20 database upgrades to v21 and matches a fresh install', () async {
    final db = AppDatabase(await verifier.startAt(20));
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 21);
  });

  test('a view saved under v20 covers one month after the upgrade', () async {
    // Written with raw SQL against the v20 schema, as an installed v20 app
    // would have left it.
    final schema = await verifier.schemaAt(20);
    schema.rawDatabase.execute(
      'INSERT INTO saved_views (id, name, spec_json, chart_type, pinned, '
      'sort_order, created_at, updated_at) '
      "VALUES ('old', 'Old view', '{}', 'breakdown', 1, 0, 0, 0)",
    );
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 21);

    final row = await db
        .customSelect(
            "SELECT period_type, period_count FROM saved_views WHERE id = 'old'")
        .getSingle();
    expect(row.read<String>('period_type'), 'month');
    expect(row.read<int>('period_count'), 1);
  });
}
