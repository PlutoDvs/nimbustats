import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/goal_fixture.dart';

void main() {
  late GoalFixture f;

  const january = DateRange(DateKey(20260101), DateKey(20260131));
  final food = MoneyScope(const QueryFilters(
      direction: MoneyDirection.expense, categorySubtreePaths: ['/food/']));
  final dining = MoneyScope(const QueryFilters(
      direction: MoneyDirection.expense,
      categorySubtreePaths: ['/food/dining/']));
  final trip = MoneyScope(QueryFilters(
      direction: MoneyDirection.expense, tags: TagsAny(const ['/trip/'])));
  final expenses =
      MoneyScope(const QueryFilters(direction: MoneyDirection.expense));
  final everything = MoneyScope(const QueryFilters());

  // Hand-computed expectations depend on these rows; change one and recompute.
  // Expenses, in dining unless named:
  // - 5 Jan: 1000 (tagged trip), and 500 in food itself;
  // - 6 Jan: 2000 in rent;
  // - 7 Jan: 300 unconfirmed, and 700 soft-deleted;
  // - 1 Feb: 400, outside January.
  // Income: 3000 salary on 10 Jan.
  // cig: two on 5 Jan, one on 6 Jan, and one soft-deleted on 5 Jan.
  // water: 0.5 and 0.25 on 5 Jan, 1.0 on 7 Jan.
  setUp(() async {
    f = await GoalFixture.open();
    await f.expense(1000, const DateKey(20260105), tags: ['trip']);
    await f.expense(500, const DateKey(20260105), category: 'food');
    await f.expense(2000, const DateKey(20260106), category: 'rent');
    await f.expense(300, const DateKey(20260107), confirmed: false);
    await f.db.transactionsDao
        .softDelete(await f.expense(700, const DateKey(20260107)));
    await f.expense(400, const DateKey(20260201));
    await f.income(3000, const DateKey(20260110));
    await f.log('cig', const DateKey(20260105));
    await f.log('cig', const DateKey(20260105));
    await f.log('cig', const DateKey(20260106));
    await f.db.trackerEntriesDao
        .softDelete(await f.log('cig', const DateKey(20260105)));
    await f.log('water', const DateKey(20260105), value: 0.5);
    await f.log('water', const DateKey(20260105), value: 0.25);
    await f.log('water', const DateKey(20260107), value: 1.0);
  });
  tearDown(() => f.db.close());

  group('measure', () {
    test('moneySum adds a subtree, unconfirmed in and deleted out', () async {
      expect(await f.measurer.measure(GoalMetric.moneySum, food, january),
          const MoneyAmount(Money(1800)));
    });

    test('txnCount counts the same rows', () async {
      expect(await f.measurer.measure(GoalMetric.txnCount, food, january),
          const QuantityAmount(3));
    });

    test('a tag filter narrows the sum', () async {
      expect(await f.measurer.measure(GoalMetric.moneySum, trip, january),
          const MoneyAmount(Money(1000)));
    });

    test("trackerSum adds one tracker's values", () async {
      expect(
          await f.measurer
              .measure(GoalMetric.trackerSum, TrackerScope('water'), january),
          const QuantityAmount(1.75));
    });

    test("trackerCount counts one tracker's live entries", () async {
      expect(
          await f.measurer
              .measure(GoalMetric.trackerCount, TrackerScope('cig'), january),
          const QuantityAmount(3));
    });

    test('netSavings is income minus expense, and can be negative', () async {
      // 3000 in; 1000 + 500 + 2000 + 300 out.
      expect(
          await f.measurer.measure(GoalMetric.netSavings, everything, january),
          const MoneyAmount(Money(-800)));
    });
  });

  group('measureDaily', () {
    test('moneySum by day', () async {
      expect(
          await f.measurer.measureDaily(GoalMetric.moneySum, food, january), {
        const DateKey(20260105): const MoneyAmount(Money(1500)),
        const DateKey(20260107): const MoneyAmount(Money(300)),
      });
    });

    test('txnCount by day', () async {
      expect(
          await f.measurer.measureDaily(GoalMetric.txnCount, food, january), {
        const DateKey(20260105): const QuantityAmount(2),
        const DateKey(20260107): const QuantityAmount(1),
      });
    });

    test('trackerSum by day', () async {
      expect(
          await f.measurer.measureDaily(
              GoalMetric.trackerSum, TrackerScope('water'), january),
          {
            const DateKey(20260105): const QuantityAmount(0.75),
            const DateKey(20260107): const QuantityAmount(1),
          });
    });

    test('trackerCount by day', () async {
      expect(
          await f.measurer.measureDaily(
              GoalMetric.trackerCount, TrackerScope('cig'), january),
          {
            const DateKey(20260105): const QuantityAmount(2),
            const DateKey(20260106): const QuantityAmount(1),
          });
    });

    test('netSavings by day, negative days and a positive one', () async {
      expect(
          await f.measurer
              .measureDaily(GoalMetric.netSavings, everything, january),
          {
            const DateKey(20260105): const MoneyAmount(Money(-1500)),
            const DateKey(20260106): const MoneyAmount(Money(-2000)),
            const DateKey(20260107): const MoneyAmount(Money(-300)),
            const DateKey(20260110): const MoneyAmount(Money(3000)),
          });
    });

    test('a span longer than one money query keeps the days at each seam',
        () async {
      // 31-day windows from 6 Dec: 6 Dec - 5 Jan, 6 Jan - 5 Feb, 6 - 28 Feb.
      // 5 and 6 January sit on either side of the first seam.
      expect(
          await f.measurer.measureDaily(GoalMetric.moneySum, expenses,
              const DateRange(DateKey(20251206), DateKey(20260228))),
          {
            const DateKey(20260105): const MoneyAmount(Money(1500)),
            const DateKey(20260106): const MoneyAmount(Money(2000)),
            const DateKey(20260107): const MoneyAmount(Money(300)),
            const DateKey(20260201): const MoneyAmount(Money(400)),
          });
    });

    test('net savings across the seams subtracts each expense once',
        () async {
      // The windows of the test above. 5 January ends the first and 6
      // January starts the second, both with expenses. A window overlap
      // would read a seam day twice: harmless to moneySum's by-day map, but
      // net savings subtracts every expense bucket it is given.
      expect(
          await f.measurer.measureDaily(GoalMetric.netSavings, everything,
              const DateRange(DateKey(20251206), DateKey(20260228))),
          {
            const DateKey(20260105): const MoneyAmount(Money(-1500)),
            const DateKey(20260106): const MoneyAmount(Money(-2000)),
            const DateKey(20260107): const MoneyAmount(Money(-300)),
            const DateKey(20260110): const MoneyAmount(Money(3000)),
            const DateKey(20260201): const MoneyAmount(Money(-400)),
          });
    });
  });

  group('stored paths follow their nodes (Review Focus 1)', () {
    test('a category moved under another parent is still measured',
        () async {
      await f.db.categoriesDao.move('dining', 'rent');

      final stored = await f.engine.run(QuerySpec(
          filters: dining.filters.withDateRange(january),
          groupBy: const GroupByNone(),
          aggregate: Aggregate.sum));
      expect(stored.trueTotal, Money.zero,
          reason: 'the stored path alone now matches nothing');
      expect(await f.measurer.measure(GoalMetric.moneySum, dining, january),
          const MoneyAmount(Money(1300)));
      expect(
          await f.measurer.measureDaily(GoalMetric.moneySum, dining, january),
          {
            const DateKey(20260105): const MoneyAmount(Money(1000)),
            const DateKey(20260107): const MoneyAmount(Money(300)),
          });
    });

    test('a tag moved under another parent still narrows', () async {
      await f.db.tagsDao.move('trip', 'work');

      expect(await f.measurer.measure(GoalMetric.moneySum, trip, january),
          const MoneyAmount(Money(1000)));
    });

    test('a category moved and then deleted still counts its live expenses, '
        'as Analytics does', () async {
      await f.db.categoriesDao.move('dining', 'rent');
      await f.db.categoriesDao.softDeleteSubtree('dining');

      expect(await f.measurer.measure(GoalMetric.moneySum, dining, january),
          const MoneyAmount(Money(1300)));
    });
  });

  group('nothing to measure', () {
    test('a stored path whose node has no row matches nothing', () async {
      // Not even a deleted row: the path stays as stored, which matches
      // nothing. Dropping it instead would widen the goal to every category.
      final gone = MoneyScope(const QueryFilters(
          direction: MoneyDirection.expense,
          categorySubtreePaths: ['/gone/']));
      final goneTag = MoneyScope(QueryFilters(
          direction: MoneyDirection.expense, tags: TagsAny(const ['/gone/'])));

      expect(await f.measurer.measure(GoalMetric.moneySum, gone, january),
          const MoneyAmount(Money.zero));
      expect(await f.measurer.measureDaily(GoalMetric.moneySum, gone, january),
          isEmpty);
      expect(await f.measurer.measure(GoalMetric.moneySum, goneTag, january),
          const MoneyAmount(Money.zero));
      expect(
          await f.measurer
              .measure(GoalMetric.trackerCount, TrackerScope('gone'), january),
          const QuantityAmount(0));
    });

    test('a range with no rows measures zero, and no days', () async {
      const march = DateRange(DateKey(20260301), DateKey(20260331));
      for (final (metric, scope, zero) in <(GoalMetric, GoalScope, GoalAmount)>[
        (GoalMetric.moneySum, food, const MoneyAmount(Money.zero)),
        (GoalMetric.txnCount, food, const QuantityAmount(0)),
        (GoalMetric.trackerSum, TrackerScope('water'), const QuantityAmount(0)),
        (GoalMetric.trackerCount, TrackerScope('cig'), const QuantityAmount(0)),
        (GoalMetric.netSavings, everything, const MoneyAmount(Money.zero)),
      ]) {
        expect(await f.measurer.measure(metric, scope, march), zero,
            reason: metric.name);
        expect(await f.measurer.measureDaily(metric, scope, march), isEmpty,
            reason: metric.name);
      }
    });
  });

  test('an archived tracker is still measured', () async {
    await f.db.trackersDao.setArchived('cig', true);

    expect(
        await f.measurer
            .measure(GoalMetric.trackerCount, TrackerScope('cig'), january),
        const QuantityAmount(3));
  });

  test("a metric given the other family's scope is refused", () async {
    await expectLater(
        f.measurer.measure(GoalMetric.moneySum, TrackerScope('cig'), january),
        throwsArgumentError);
    await expectLater(
        f.measurer.measureDaily(GoalMetric.trackerCount, food, january),
        throwsArgumentError);
  });
}
