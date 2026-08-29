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

  Future<AnalyticsResult> byTag([
    QueryFilters filters = const QueryFilters(),
  ]) =>
      engine.run(QuerySpec(
          filters: filters,
          groupBy: const GroupByTag(),
          aggregate: Aggregate.sum));

  test('tag buckets sum to MORE than the true total', () async {
    // The headline correctness trap. t1 carries /travel/ and /food/, so its
    // 1000 lands in two buckets. Measured: buckets 3000, true total 1750.
    //
    // If this ever asserts equality, the engine has started dropping a tag.
    final result = await byTag();
    expect(result.bucketSum.minorUnits, 3000);
    expect(result.trueTotal, const Money(1750));
    expect(result.bucketSum.minorUnits, greaterThan(result.trueTotal.minorUnits),
        reason: 'tag buckets overlap by construction; equality here means a '
            'transaction lost one of its tags');
  });

  test('the result declares that its buckets overlap', () async {
    // This flag is what a pie chart consults before claiming to show parts of
    // a whole. Without it the chart is a quiet lie.
    final result = await byTag();
    expect(result.overlaps, isTrue);
  });

  test('non-tag dimensions do not declare overlap and do sum to the total',
      () async {
    final result = await engine.run(const QuerySpec(
        filters: QueryFilters(),
        groupBy: GroupByMerchant(),
        aggregate: Aggregate.sum));
    expect(result.overlaps, isFalse);
    expect(result.bucketSum, result.trueTotal);
  });

  test('each tag bucket holds the right total', () async {
    final result = await byTag();
    final byId = {
      for (final bucket in result.buckets)
        (bucket.key as TagKey).tagId: bucket.money.minorUnits
    };
    expect(byId['travel'], 1500); // t1 1000 + t2 500
    expect(byId['food'], 1000); // t1
    expect(byId['flights'], 500); // t2
  });

  test('a nested rollup counts a transaction once', () async {
    // t2 carries BOTH /travel/ and its child /travel/flights/. Filtering to
    // the /travel/ subtree must yield 1500 over two transactions.
    //
    // The measured alternative -- a JOIN instead of EXISTS -- answers 2000
    // over three rows, confidently and with no error anywhere.
    final result = await engine.run(QuerySpec(
      filters: QueryFilters(tags: TagsAny(const ['/travel/'])),
      groupBy: const GroupByNone(),
      aggregate: Aggregate.sum,
    ));
    expect(result.trueTotal, const Money(1500));
    expect(result.trueCount, 2);
  });

  test('the true total ignores the grouping dimension entirely', () async {
    // Whatever the buckets do, the true total is the same number.
    final viaTag = await byTag();
    final viaMerchant = await engine.run(const QuerySpec(
        filters: QueryFilters(),
        groupBy: GroupByMerchant(),
        aggregate: Aggregate.sum));
    expect(viaTag.trueTotal, viaMerchant.trueTotal);
    expect(viaTag.trueCount, viaMerchant.trueCount);
  });
}
