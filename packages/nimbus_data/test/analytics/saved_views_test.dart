import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  test('the schema version is 20', () async {
    expect(db.schemaVersion, 20);
  });

  test('a saved view round-trips its QuerySpec', () async {
    // The stored form is the JSON QuerySpec already tested in the domain
    // package. What this proves is that the column survives SQLite.
    final spec = QuerySpec(
      filters: QueryFilters(
        dateRange: DateRange(const DateKey(20260101), const DateKey(20260131)),
        tags: TagsAny(const ['/travel/']),
      ),
      groupBy: GroupByCategory(1),
      aggregate: Aggregate.sum,
    );

    await db.savedViewsDao.upsert(
      id: 'v1',
      name: 'Travel in January',
      spec: spec,
      chartType: 'bar',
      pinned: true,
      sortOrder: 0,
    );

    final loaded = await db.savedViewsDao.byId('v1');
    expect(loaded, isNotNull);
    expect(loaded!.spec, spec);
    expect(loaded.name, 'Travel in January');
    expect(loaded.pinned, isTrue);
  });

  test('upsert replaces an existing view rather than duplicating it', () async {
    const spec = QuerySpec(
        filters: QueryFilters(),
        groupBy: GroupByNone(),
        aggregate: Aggregate.sum);
    await db.savedViewsDao.upsert(
        id: 'v',
        name: 'First',
        spec: spec,
        chartType: 'bar',
        pinned: true,
        sortOrder: 0);
    await db.savedViewsDao.upsert(
        id: 'v',
        name: 'Renamed',
        spec: spec,
        chartType: 'line',
        pinned: true,
        sortOrder: 0);
    expect((await db.savedViewsDao.byId('v'))!.name, 'Renamed');
    expect(await db.savedViewsDao.pinned(), hasLength(1));
  });

  test('pinned views come back in sort order', () async {
    const spec = QuerySpec(
        filters: QueryFilters(),
        groupBy: GroupByNone(),
        aggregate: Aggregate.sum);
    await db.savedViewsDao.upsert(
        id: 'b',
        name: 'B',
        spec: spec,
        chartType: 'bar',
        pinned: true,
        sortOrder: 1);
    await db.savedViewsDao.upsert(
        id: 'a',
        name: 'A',
        spec: spec,
        chartType: 'bar',
        pinned: true,
        sortOrder: 0);
    await db.savedViewsDao.upsert(
        id: 'c',
        name: 'C',
        spec: spec,
        chartType: 'bar',
        pinned: false,
        sortOrder: 2);

    final pinned = await db.savedViewsDao.pinned();
    expect(pinned.map((v) => v.id), ['a', 'b']);
  });

  test('a soft-deleted view is not returned', () async {
    const spec = QuerySpec(
        filters: QueryFilters(),
        groupBy: GroupByNone(),
        aggregate: Aggregate.sum);
    await db.savedViewsDao.upsert(
        id: 'v',
        name: 'V',
        spec: spec,
        chartType: 'bar',
        pinned: true,
        sortOrder: 0);
    await db.savedViewsDao.softDelete('v');
    expect(await db.savedViewsDao.pinned(), isEmpty);
    expect(await db.savedViewsDao.byId('v'), isNull);
  });

  test('unparseable stored JSON throws rather than yielding a default view',
      () async {
    await db.customStatement(
      'INSERT INTO saved_views (id,name,spec_json,chart_type,pinned,'
      'sort_order,created_at,updated_at,deleted_at) '
      "VALUES ('bad','Bad','{\"nope\":1}','bar',1,0,1,1,NULL)",
    );
    // A default here would silently show the wrong chart under the user's
    // own saved name.
    expect(() => db.savedViewsDao.byId('bad'), throwsA(isA<Exception>()));
  });
}
