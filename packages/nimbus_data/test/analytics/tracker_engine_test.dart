import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import '../trackers/support/tracker_rows.dart';

void main() {
  late AppDatabase db;
  late AnalyticsEngine engine;

  /// [hourUtc] o'clock UTC on that day. At 05:00 UTC, Tehran reads 08:30.
  DateTime at(int month, int day, [int hourUtc = 5]) =>
      DateTime.utc(2026, month, day, hourUtc);

  TrackerQuerySpec spec(List<String> ids, TrackerGroupBy groupBy,
          {DateRange? range, Aggregate aggregate = Aggregate.sum}) =>
      TrackerQuerySpec(
          trackerIds: ids,
          dateRange: range,
          groupBy: groupBy,
          aggregate: aggregate);

  Map<BucketKey, double> valuesOf(TrackerResult result) =>
      {for (final bucket in result.buckets) bucket.key: bucket.value};

  DateRange oneDay(int key) => DateRange(DateKey(key), DateKey(key));

  // Hand-computed expectations depend on these rows; change one and recompute.
  // Every entry is logged in Tehran (+3:30) unless it says otherwise.
  // - cig: Mon 5 Jan at 08:30 and 19:30, Tue 6 Jan, Sun 25 Jan, Tue 10 Feb,
  //   plus one soft-deleted on 5 Jan.
  // - water: 0.5 and 0.25 on 5 Jan, at 08:30 and 09:30.
  // - gym: done on 6 Jan.
  // - empty: nothing.
  setUp(() async {
    db = openTestDatabase();
    engine = AnalyticsEngine(db, calendar: const GregorianCalendar());
    await db.trackersDao.insertAll([
      newTracker('cig', TrackerType.counter),
      newTracker('water', TrackerType.quantity, perTapValue: 0.25),
      newTracker('gym', TrackerType.boolean),
      newTracker('empty', TrackerType.counter),
    ]);
    final dao = db.trackerEntriesDao;
    await dao.insertEntry(
        newEntry('c1', 'cig', at: at(1, 5), day: const DateKey(20260105)));
    await dao.insertEntry(newEntry('c2', 'cig',
        at: at(1, 5, 16), day: const DateKey(20260105)));
    await dao.insertEntry(
        newEntry('c3', 'cig', at: at(1, 6), day: const DateKey(20260106)));
    await dao.insertEntry(
        newEntry('c4', 'cig', at: at(1, 25), day: const DateKey(20260125)));
    await dao.insertEntry(
        newEntry('c5', 'cig', at: at(2, 10), day: const DateKey(20260210)));
    await dao.insertEntry(
        newEntry('gone', 'cig', at: at(1, 5), day: const DateKey(20260105)));
    await dao.softDelete('gone');
    await dao.insertEntry(newEntry('w1', 'water',
        value: 0.5, at: at(1, 5), day: const DateKey(20260105)));
    await dao.insertEntry(newEntry('w2', 'water',
        value: 0.25, at: at(1, 5, 6), day: const DateKey(20260105)));
    await dao.insertEntry(newEntry('g1', 'gym',
        at: at(1, 6), day: const DateKey(20260106), oncePerDay: true));
  });
  tearDown(() => db.close());

  test('no grouping answers one bucket, and the totals beside it', () async {
    final result =
        await engine.runTracker(spec(['cig'], const TrackerGroupByNone()));
    expect(result.buckets,
        [const TrackerBucket(key: TotalKey(), value: 5, count: 5)]);
    expect(result.sum, 5);
    expect(result.count, 5);
  });

  test('soft-deleted entries and other trackers are left out', () async {
    final result = await engine.runTracker(spec(
        ['cig'], const TrackerGroupByNone(),
        range: oneDay(20260105)));
    // c1 and c2. Not "gone", not water's two.
    expect(result.sum, 2);
    expect(result.count, 2);
  });

  test('grouping by tracker keys each tracker that has entries', () async {
    final result = await engine.runTracker(spec(
        ['cig', 'water', 'empty'], const TrackerGroupByTracker(),
        range: oneDay(20260105)));
    expect(valuesOf(result),
        {const TrackerKey('cig'): 2.0, const TrackerKey('water'): 0.75});
    expect(result.sum, 2.75);
    expect(result.count, 4);
  });

  test('grouping by day needs no date range, and comes oldest first',
      () async {
    final result =
        await engine.runTracker(spec(['cig'], const TrackerGroupByDay()));
    expect(result.buckets.map((b) => (b.key, b.value)), [
      (PeriodKey(oneDay(20260105)), 2.0),
      (PeriodKey(oneDay(20260106)), 1.0),
      (PeriodKey(oneDay(20260125)), 1.0),
      (PeriodKey(oneDay(20260210)), 1.0),
    ]);
  });

  test("grouping by month uses the calendar's months", () async {
    final result = await engine.runTracker(spec(
        ['cig'], TrackerGroupByPeriod(PeriodType.month),
        range: const DateRange(DateKey(20260101), DateKey(20260228))));
    expect(valuesOf(result), {
      const PeriodKey(DateRange(DateKey(20260101), DateKey(20260131))): 4.0,
      const PeriodKey(DateRange(DateKey(20260201), DateKey(20260228))): 1.0,
    });
  });

  test('a Jalali month is not a Gregorian one', () async {
    // Dey 1404 is 22 Dec - 20 Jan and Bahman 21 Jan - 19 Feb, so 25 Jan moves
    // from January's bucket into Bahman's.
    final jalali = AnalyticsEngine(db, calendar: const JalaliCalendar());
    final result = await jalali.runTracker(spec(
        ['cig'], TrackerGroupByPeriod(PeriodType.month),
        range: const DateRange(DateKey(20251222), DateKey(20260219))));
    expect(valuesOf(result), {
      const PeriodKey(DateRange(DateKey(20251222), DateKey(20260120))): 3.0,
      const PeriodKey(DateRange(DateKey(20260121), DateKey(20260219))): 2.0,
    });
  });

  test('grouping by period without a date range is refused', () async {
    await expectLater(
        engine.runTracker(
            spec(['cig'], TrackerGroupByPeriod(PeriodType.month))),
        throwsArgumentError);
  });

  test("hour of day reads each entry's own offset", () async {
    // The same instant, logged in Tehran (+3:30) and in Kabul (+4:30): two
    // different local hours.
    await db.trackersDao.insertAll([newTracker('trip', TrackerType.counter)]);
    final dao = db.trackerEntriesDao;
    await dao.insertEntry(newEntry('home', 'trip',
        at: at(3, 1), day: const DateKey(20260301), tzOffsetMinutes: 210));
    await dao.insertEntry(newEntry('away', 'trip',
        at: at(3, 1), day: const DateKey(20260301), tzOffsetMinutes: 270));

    final result = await engine
        .runTracker(spec(['trip'], const TrackerGroupByHourOfDay()));
    expect(valuesOf(result), {HourOfDayKey(8): 1.0, HourOfDayKey(9): 1.0});
  });

  test('hour of day over the fixture', () async {
    final result = await engine
        .runTracker(spec(['cig'], const TrackerGroupByHourOfDay()));
    // c2 at 16:00 UTC reads 19:30; every other one 08:30.
    expect(valuesOf(result), {HourOfDayKey(8): 4.0, HourOfDayKey(19): 1.0});
  });

  test('day of week answers ISO weekdays, Sunday as 7', () async {
    final result = await engine
        .runTracker(spec(['cig'], const TrackerGroupByDayOfWeek()));
    expect(valuesOf(result), {
      DayOfWeekKey(DateTime.monday): 2.0,
      DayOfWeekKey(DateTime.tuesday): 2.0,
      DayOfWeekKey(DateTime.sunday): 1.0,
    });
  });

  test('each aggregate answers in value; count is always the entry count',
      () async {
    Future<TrackerBucket> one(Aggregate aggregate) async => (await engine
            .runTracker(spec(['water'], const TrackerGroupByNone(),
                range: oneDay(20260105), aggregate: aggregate)))
        .buckets
        .single;

    expect((await one(Aggregate.sum)).value, 0.75);
    expect((await one(Aggregate.count)).value, 2);
    expect((await one(Aggregate.average)).value, 0.375);
    expect((await one(Aggregate.min)).value, 0.25);
    expect((await one(Aggregate.max)).value, 0.5);
    expect((await one(Aggregate.max)).count, 2);
  });

  test('a tracker with no entries answers no buckets and zeros', () async {
    final result =
        await engine.runTracker(spec(['empty'], const TrackerGroupByNone()));
    expect(result.buckets, isEmpty);
    expect(result.sum, 0);
    expect(result.count, 0);
  });

  test('trackerChanges fires on an entry write', () async {
    final fired = expectLater(engine.trackerChanges(), emits(anything));
    await db.trackerEntriesDao.insertEntry(newEntry('new', 'cig'));
    await fired;
  });

  test('trackerChanges ignores a settings write', () async {
    var fired = false;
    final subscription = engine.trackerChanges().listen((_) => fired = true);
    addTearDown(subscription.cancel);
    await db.settingsDao.put('locale', 'en');
    await pumpEventQueue();
    expect(fired, isFalse);
  });
}
