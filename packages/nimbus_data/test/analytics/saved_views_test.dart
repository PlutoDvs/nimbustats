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

  test('the schema version is 21', () async {
    expect(db.schemaVersion, 21);
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
}
