import 'package:drift_dev/api/migrations_native.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:sqlite3/common.dart' show SqliteException;
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
  for (final from in [1, 20, 21]) {
    test('a v$from database upgrades to v30 and matches a fresh install',
        () async {
      final db = AppDatabase(await verifier.startAt(from));
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, 30);
    });
  }

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

    await verifier.migrateAndValidate(db, 30);

    final row = await db
        .customSelect(
            "SELECT period_type, period_count FROM saved_views WHERE id = 'old'")
        .getSingle();
    expect(row.read<String>('period_type'), 'month');
    expect(row.read<int>('period_count'), 1);
  });

  test('a database upgraded from v1 takes a view through the DAO', () async {
    // Validating the shape is not the same as proving the table works.
    final db = AppDatabase(await verifier.startAt(1));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 30);

    await db.savedViewsDao.create([
      (
        id: 'after-migration',
        name: 'Still works',
        spec: const QuerySpec(
            filters: QueryFilters(),
            groupBy: GroupByNone(),
            aggregate: Aggregate.sum),
        period: ViewPeriod(PeriodType.month, 1),
        chart: SavedViewChart.breakdown,
      ),
    ]);

    expect((await db.savedViewsDao.watchPinned().first).single,
        isA<SavedView>());
  });

  group('an upgraded v21 database enforces one live "done" per day', () {
    // The once-per-day index is a correctness rule, not a speed-up. A device
    // that upgraded without it could log "done" twice and every streak in 4b
    // would be wrong -- so it is proven on the upgraded path, not only on a
    // fresh install.
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(await verifier.startAt(21));
      await verifier.migrateAndValidate(db, 30);
      await db.customStatement(
        'INSERT INTO trackers (id, name, icon_key, color, type, created_at, '
        "updated_at) VALUES ('gym', 'Gym', 'fitness_center', 0, 'boolean', "
        '0, 0)',
      );
    });
    tearDown(() => db.close());

    Future<void> insert(String id, {int day = 20261005, bool once = true}) =>
        db.customStatement(
          'INSERT INTO tracker_entries (id, tracker_id, value, '
          'occurred_at_utc, local_date_key, once_per_day, created_at, '
          "updated_at) VALUES (?, 'gym', 1.0, 0, ?, ?, 0, 0)",
          [id, day, once ? 1 : 0],
        );

    test('a second live done on the same day is refused', () async {
      await insert('first');
      await expectLater(insert('second'), throwsA(isA<SqliteException>()));
    });

    test('a soft-deleted done does not block a new one', () async {
      await insert('first');
      await db.customStatement(
          "UPDATE tracker_entries SET deleted_at = 1 WHERE id = 'first'");
      await insert('second');
    });

    test('another day, and rows without the flag, are unaffected', () async {
      await insert('monday');
      await insert('tuesday', day: 20261006);
      await insert('plain-1', once: false);
      await insert('plain-2', once: false);
    });
  });
}
