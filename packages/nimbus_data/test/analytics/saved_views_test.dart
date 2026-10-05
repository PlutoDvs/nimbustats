import 'package:drift/drift.dart' show Variable;
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';

const _spec = QuerySpec(
  filters: QueryFilters(direction: MoneyDirection.expense),
  groupBy: GroupByNone(),
  aggregate: Aggregate.sum,
);

NewSavedView _view(
  String id, {
  QuerySpec spec = _spec,
  ViewPeriod? period,
  SavedViewChart chart = SavedViewChart.breakdown,
}) =>
    (
      id: id,
      name: id,
      spec: spec,
      period: period ?? ViewPeriod(PeriodType.month, 1),
      chart: chart,
    );

/// A row written past the DAO, as corrupt or future-version data would be.
Future<void> _insertRaw(
  AppDatabase db, {
  required String id,
  required int sortOrder,
  String specJson =
      '{"filters":{},"groupBy":{"kind":"none"},"aggregate":"sum"}',
  String chartType = 'breakdown',
  String periodType = 'month',
}) =>
    db.customStatement(
      'INSERT INTO saved_views (id, name, spec_json, chart_type, period_type, '
      'period_count, pinned, sort_order, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, 1, 1, ?, 0, 0)',
      [id, id, specJson, chartType, periodType, sortOrder],
    );

void main() {
  late AppDatabase db;
  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  Future<List<String>> pinnedIds() async =>
      [for (final e in await db.savedViewsDao.watchPinned().first) e.id];

  Future<({int created, int updated})> stamps(String id) async {
    final row = await db.customSelect(
      'SELECT created_at, updated_at FROM saved_views WHERE id = ?',
      variables: [Variable.withString(id)],
    ).getSingle();
    return (
      created: row.read<int>('created_at'),
      updated: row.read<int>('updated_at'),
    );
  }

  test('the schema version is 31', () async {
    expect(db.schemaVersion, 31);
  });

  test('a view round-trips its spec, period and chart', () async {
    final spec = QuerySpec(
      filters: QueryFilters(
        direction: MoneyDirection.expense,
        tags: TagsAny(const ['/travel/']),
      ),
      groupBy: GroupByCategory(1),
      aggregate: Aggregate.sum,
    );
    await db.savedViewsDao.create([
      _view('v1',
          spec: spec,
          period: ViewPeriod(PeriodType.month, 6),
          chart: SavedViewChart.trend),
    ]);

    final loaded =
        (await db.savedViewsDao.watchPinned().first).single as SavedView;
    expect(loaded.name, 'v1');
    expect(loaded.spec, spec);
    expect(loaded.period, ViewPeriod(PeriodType.month, 6));
    expect(loaded.chart, SavedViewChart.trend);
  });

  test('a spec that still has a date range is refused and nothing is written',
      () async {
    final dated = _spec.withDateRange(
        DateRange(const DateKey(20260101), const DateKey(20260131)));

    await expectLater(
      db.savedViewsDao.create([_view('fine'), _view('dated', spec: dated)]),
      throwsArgumentError,
    );
    expect(await pinnedIds(), isEmpty);
  });

  test('new views go to the end, in the order given', () async {
    await db.savedViewsDao.create([_view('a'), _view('b')]);
    await db.savedViewsDao.create([_view('c')]);

    expect(await pinnedIds(), ['a', 'b', 'c']);
  });

  test('the pinned list is live', () async {
    final seen = <List<String>>[];
    final subscription = db.savedViewsDao
        .watchPinned()
        .listen((entries) => seen.add([for (final e in entries) e.id]));
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(seen, [<String>[]]);

    await db.savedViewsDao.create([_view('a')]);
    await pumpEventQueue();

    expect(seen.last, ['a']);
  });

  test('one unreadable row does not hide the others', () async {
    await db.savedViewsDao.create([_view('good')]);
    await _insertRaw(db, id: 'bad-json', specJson: '{not json', sortOrder: 10);
    await _insertRaw(db, id: 'bad-chart', chartType: 'sparkline', sortOrder: 11);
    await _insertRaw(db, id: 'bad-period', periodType: 'fortnight', sortOrder: 12);
    // Valid JSON of the wrong shape: a string where a bool belongs meets a
    // cast and throws a TypeError, not a FormatException.
    await _insertRaw(
      db,
      id: 'bad-type',
      specJson: '{"filters":{"confirmedOnly":"yes"},'
          '"groupBy":{"kind":"none"},"aggregate":"sum"}',
      sortOrder: 13,
    );

    final entries = await db.savedViewsDao.watchPinned().first;

    expect(entries.map((e) => e.id),
        ['good', 'bad-json', 'bad-chart', 'bad-period', 'bad-type']);
    expect(entries.first, isA<SavedView>());
    expect(entries.skip(1), everyElement(isA<UnreadableSavedView>()));
  });

  test('watchById follows a view and ends at null once it is removed',
      () async {
    await db.savedViewsDao.create([_view('v')]);
    expect((await db.savedViewsDao.watchById('v').first)?.id, 'v');

    await db.savedViewsDao.softDelete('v');

    expect(await db.savedViewsDao.watchById('v').first, isNull);
    expect(await pinnedIds(), isEmpty);
  });

  test('rename changes the name and keeps the creation time', () async {
    await db.savedViewsDao.create([_view('v')]);
    final before = await stamps('v');
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await db.savedViewsDao.rename('v', 'Food watch');

    expect((await db.savedViewsDao.watchPinned().first).single.name,
        'Food watch');
    final after = await stamps('v');
    expect(after.created, before.created);
    expect(after.updated, greaterThan(before.updated));
  });

  test('reorder rewrites the order and keeps creation times', () async {
    await db.savedViewsDao.create([_view('a'), _view('b'), _view('c')]);
    final before = await stamps('a');

    await db.savedViewsDao.reorder(['c', 'a', 'b']);

    expect(await pinnedIds(), ['c', 'a', 'b']);
    expect((await stamps('a')).created, before.created);
  });

  test('reorder is all or nothing', () async {
    await db.savedViewsDao.create([_view('a'), _view('b')]);

    await expectLater(
        db.savedViewsDao.reorder(['b', 'missing', 'a']), throwsStateError);

    expect(await pinnedIds(), ['a', 'b']);
  });

  test('restore brings a removed view back in its old place', () async {
    await db.savedViewsDao.create([_view('a'), _view('b'), _view('c')]);
    await db.savedViewsDao.softDelete('b');
    expect(await pinnedIds(), ['a', 'c']);

    await db.savedViewsDao.restore('b');

    expect(await pinnedIds(), ['a', 'b', 'c']);
  });

  test(
      'restore after an intervening reorder does not collide with a live '
      "view's slot", () async {
    await db.savedViewsDao.create([_view('a'), _view('b'), _view('c')]);
    await db.savedViewsDao.softDelete('b');
    // 'b' keeps its old sort_order (1) as a soft-deleted row. Reordering the
    // two survivors re-stamps them densely from 0, so 'c' now also claims
    // sort_order 1 -- the very slot 'b' is still holding onto.
    await db.savedViewsDao.reorder(['c', 'a']);

    await db.savedViewsDao.restore('b');

    final pinned = await db.savedViewsDao.watchPinned().first;
    expect(pinned.map((e) => e.id).toSet(), {'a', 'b', 'c'});
    expect(pinned.length, 3);

    final rows = await db.customSelect(
      'SELECT sort_order FROM saved_views WHERE deleted_at IS NULL',
    ).get();
    final sortOrders = rows.map((r) => r.read<int>('sort_order')).toList();
    expect(sortOrders.toSet().length, sortOrders.length,
        reason: 'no two live views may share a sort_order');
  });

  test('a write that matches no view says so', () async {
    // A rename that renamed nothing is a caller holding a stale id;
    // reporting success for it would be a silent failure.
    await expectLater(db.savedViewsDao.rename('nope', 'x'), throwsStateError);
    await expectLater(db.savedViewsDao.softDelete('nope'), throwsStateError);
    await expectLater(db.savedViewsDao.restore('nope'), throwsStateError);
  });

  test('the live list follows rename, reorder, removal and restore',
      () async {
    await db.savedViewsDao.create([_view('a'), _view('b')]);
    final seen = <List<String>>[];
    final subscription = db.savedViewsDao.watchPinned().listen(
        (entries) => seen.add([for (final e in entries) '${e.id}:${e.name}']));
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await db.savedViewsDao.rename('a', 'A');
    await pumpEventQueue();
    expect(seen.last, ['a:A', 'b:b']);

    await db.savedViewsDao.reorder(['b', 'a']);
    await pumpEventQueue();
    expect(seen.last, ['b:b', 'a:A']);

    await db.savedViewsDao.softDelete('b');
    await pumpEventQueue();
    expect(seen.last, ['a:A']);

    await db.savedViewsDao.restore('b');
    await pumpEventQueue();
    expect(seen.last, ['b:b', 'a:A']);
  });
}
