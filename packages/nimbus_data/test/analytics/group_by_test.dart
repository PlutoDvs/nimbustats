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

  Future<AnalyticsResult> run(GroupBy dimension,
          {QueryFilters filters = const QueryFilters(),
          Aggregate aggregate = Aggregate.sum}) =>
      engine.run(QuerySpec(
          filters: filters, groupBy: dimension, aggregate: aggregate));

  test('no grouping yields one bucket holding the true total', () async {
    final result = await run(const GroupByNone());
    expect(result.buckets, hasLength(1));
    expect(result.buckets.single.key, const TotalKey());
    expect(result.buckets.single.money, const Money(1750));
    expect(result.buckets.single.count, 3);
    expect(result.trueTotal, const Money(1750));
    expect(result.overlaps, isFalse);
  });

  test('every bucket carries its count', () async {
    final result = await run(const GroupByNone());
    expect(result.buckets.single.count, 3);
    expect(result.trueCount, 3);
  });

  test('grouping by merchant keeps the null bucket', () async {
    // All three rows have a null merchant in the fixture. "No merchant" is a
    // real answer, not a row to drop.
    final result = await run(const GroupByMerchant());
    expect(result.buckets, hasLength(1));
    expect((result.buckets.single.key as MerchantKey).merchant, isNull);
    expect(result.buckets.single.money, const Money(1750));
  });

  test('grouping by payment method keeps the null bucket', () async {
    final result = await run(const GroupByPaymentMethod());
    expect((result.buckets.single.key as PaymentMethodKey).paymentMethodId,
        isNull);
  });

  test('grouping by period uses Dart-computed boundaries', () async {
    final result = await run(
      const GroupByPeriod(PeriodType.month),
      filters: QueryFilters(
          dateRange:
              DateRange(const DateKey(20260101), const DateKey(20260331))),
    );
    expect(result.buckets, hasLength(3));
    expect(result.buckets[0].money, const Money(1000)); // January
    expect(result.buckets[1].money, const Money(500)); // February
    expect(result.buckets[2].money, const Money(250)); // March
    expect(result.trueTotal, const Money(1750));
  });

  test('period buckets are ordered oldest first', () async {
    final result = await run(
      const GroupByPeriod(PeriodType.month),
      filters: QueryFilters(
          dateRange:
              DateRange(const DateKey(20260101), const DateKey(20260331))),
    );
    final keys = result.buckets.map((b) => (b.key as PeriodKey).range).toList();
    for (var i = 1; i < keys.length; i++) {
      expect(keys[i].startInclusive.value,
          greaterThan(keys[i - 1].startInclusive.value));
    }
  });

  test('period grouping without a date range is refused', () async {
    // There is no finite set of periods to enumerate. Bucketing everything
    // into one would look like a working chart.
    expect(
        () => engine.compile(const QuerySpec(
            filters: QueryFilters(),
            groupBy: GroupByPeriod(PeriodType.month),
            aggregate: Aggregate.sum)),
        throwsArgumentError);
  });

  test('a Jalali month grouping is not a Gregorian one', () async {
    final jalaliEngine = AnalyticsEngine(db, calendar: const JalaliCalendar());
    final span = DateRange(const DateKey(20260101), const DateKey(20260331));
    final gregorian = await run(const GroupByPeriod(PeriodType.month),
        filters: QueryFilters(dateRange: span));
    final jalali = await jalaliEngine.run(QuerySpec(
        filters: QueryFilters(dateRange: span),
        groupBy: const GroupByPeriod(PeriodType.month),
        aggregate: Aggregate.sum));
    final gregorianStarts =
        gregorian.buckets.map((b) => (b.key as PeriodKey).range.startInclusive);
    final jalaliStarts =
        jalali.buckets.map((b) => (b.key as PeriodKey).range.startInclusive);
    expect(jalaliStarts, isNot(gregorianStarts),
        reason: 'if these agree, period math is happening in SQL');
    expect(jalali.trueTotal, const Money(1750),
        reason: 'the calendar changes the buckets, never the total');
  });

  test('grouping by hour of day', () async {
    final result = await run(const GroupByHourOfDay());
    expect(result.buckets, hasLength(1));
    expect((result.buckets.single.key as HourOfDayKey).hour, 0);
  });

  test('grouping by day of week yields an ISO weekday', () async {
    final result = await run(const GroupByDayOfWeek());
    final weekday = (result.buckets.single.key as DayOfWeekKey).weekday;
    expect(weekday, inInclusiveRange(DateTime.monday, DateTime.sunday));
  });

  test('grouping by reflection keeps unset axes as their own cell', () async {
    final result = await run(const GroupByReflection());
    final key = result.buckets.single.key as ReflectionKey;
    expect(key.necessity, isNull);
    expect(key.satisfaction, isNull);
    expect(result.buckets.single.count, 3);
  });

  test('grouping by category rolls up to the requested depth', () async {
    final result = await run(GroupByCategory(0));
    expect(result.buckets, hasLength(1));
    expect((result.buckets.single.key as CategoryKey).categoryId, 'cat');
    expect(result.buckets.single.money, const Money(1750));
  });

  group('category rollup actually rolls up', () {
    // The fixture has one root category, so the test above passes whether or
    // not `depth` does anything. These add a child and prove it does.
    setUp(() async {
      await db.customStatement(
        'INSERT INTO categories (id,name,icon_key,color,parent_id,path,depth,'
        'sort_order,kind,archived,created_at,updated_at,deleted_at) '
        "VALUES ('sub','sub','tag',0,'cat','/cat/sub/',1,0,'expense',0,1,1,"
        'NULL)',
      );
      await db.customStatement(
        'INSERT INTO transactions (id,direction,amount,currency_code,'
        'occurred_at_utc,local_date_key,tz_offset_minutes,category_id,'
        'payment_method_id,merchant,note,necessity,satisfaction,source,'
        'is_confirmed,capture_id,created_at,updated_at,deleted_at) '
        "VALUES ('t4','expense',400,'IRT',0,20260410,0,'sub',NULL,NULL,NULL,"
        "NULL,NULL,'manual',1,NULL,1,1,NULL)",
      );
    });

    test('depth 0 folds a child category into its root', () async {
      // 1750 from the root's own rows + 400 from the child, in ONE bucket.
      // If depth is ignored, this comes back as two buckets instead.
      final result = await run(GroupByCategory(0));
      expect(result.buckets, hasLength(1),
          reason: 'a depth-0 rollup must not leave the child in its own '
              'bucket; that is the nested-rollup trap');
      expect((result.buckets.single.key as CategoryKey).categoryId, 'cat');
      expect(result.buckets.single.money, const Money(2150));
      expect(result.buckets.single.count, 4);
    });

    test('depth 1 splits the child back out', () async {
      final result = await run(GroupByCategory(1));
      final byId = {
        for (final bucket in result.buckets)
          (bucket.key as CategoryKey).categoryId: bucket.money.minorUnits
      };
      expect(byId, {'cat': 1750, 'sub': 400});
    });

    test('a transaction shallower than the requested depth buckets at its own',
        () async {
      // The root's rows are at depth 0; asking for depth 5 must not drop them.
      final result = await run(GroupByCategory(5));
      final byId = {
        for (final bucket in result.buckets)
          (bucket.key as CategoryKey).categoryId: bucket.money.minorUnits
      };
      expect(byId, {'cat': 1750, 'sub': 400});
    });

    test('the true total is unchanged by the rollup depth', () async {
      for (final depth in [0, 1, 5]) {
        final result = await run(GroupByCategory(depth));
        expect(result.trueTotal, const Money(2150),
            reason: 'depth $depth changed the total');
        expect(result.bucketSum, result.trueTotal,
            reason: 'category buckets must not overlap at depth $depth');
      }
    });
  });

  group('aggregates', () {
    test('count answers in the count field', () async {
      final result = await run(const GroupByNone(), aggregate: Aggregate.count);
      expect(result.buckets.single.count, 3);
    });

    test('min and max stay integer money', () async {
      final min = await run(const GroupByNone(), aggregate: Aggregate.min);
      final max = await run(const GroupByNone(), aggregate: Aggregate.max);
      expect(min.buckets.single.money, const Money(250));
      expect(max.buckets.single.money, const Money(1000));
    });

    test('average rounds half away from zero and stays an int', () async {
      // (1000 + 500 + 250) / 3 = 583.33... -> 583
      final result =
          await run(const GroupByNone(), aggregate: Aggregate.average);
      expect(result.buckets.single.money, const Money(583));
    });

    test('an average of exactly .5 rounds away from zero', () async {
      await db.customStatement('DELETE FROM transaction_tags');
      await db.customStatement("DELETE FROM transactions WHERE id != 't1'");
      await db.customStatement(
          "UPDATE transactions SET amount = 1 WHERE id = 't1'");
      await db.customStatement(
        'INSERT INTO transactions (id,direction,amount,currency_code,'
        'occurred_at_utc,local_date_key,tz_offset_minutes,category_id,'
        'payment_method_id,merchant,note,necessity,satisfaction,source,'
        'is_confirmed,capture_id,created_at,updated_at,deleted_at) '
        "VALUES ('t9','expense',2,'IRT',0,20260115,0,'cat',NULL,NULL,NULL,"
        "NULL,NULL,'manual',1,NULL,1,1,NULL)",
      );
      // (1 + 2) / 2 = 1.5 -> 2
      final result =
          await run(const GroupByNone(), aggregate: Aggregate.average);
      expect(result.buckets.single.money, const Money(2));
    });

    test('an empty result is zero money, not an error', () async {
      final result = await run(
        const GroupByNone(),
        filters: QueryFilters(
            dateRange:
                DateRange(const DateKey(20200101), const DateKey(20200102))),
      );
      expect(result.trueTotal, Money.zero);
      expect(result.trueCount, 0);
    });
  });
}
