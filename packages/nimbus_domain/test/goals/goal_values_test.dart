import 'dart:convert';

import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

MoneyAmount rials(int minor) => MoneyAmount(Money(minor));

void main() {
  final food = MoneyScope(const QueryFilters(
      direction: MoneyDirection.expense, categorySubtreePaths: ['/food/']));
  final cigarettes = TrackerScope('cig');
  final everything = MoneyScope(const QueryFilters());
  const october = RecurringPeriod(PeriodType.month, DateKey(20261001));

  /// A valid spending cap unless told otherwise, so each test changes only
  /// the field it is about.
  Goal goal({
    String id = 'g1',
    String name = 'Dining out',
    GoalMetric metric = GoalMetric.moneySum,
    GoalScope? scope,
    GoalDirection direction = GoalDirection.atMost,
    GoalAmount? target,
    GoalPeriod period = october,
    int weekStart = DateTime.saturday,
    List<int> alertPercents = Goal.defaultAlertPercents,
  }) =>
      Goal(
        id: id,
        name: name,
        metric: metric,
        scope: scope ?? food,
        direction: direction,
        target: target ?? rials(10000),
        period: period,
        calendar: CalendarKind.jalali,
        weekStart: weekStart,
        alertPercents: alertPercents,
      );

  group('GoalMetric', () {
    test('the money metrics are the two whose target is money', () {
      expect(GoalMetric.values.where((m) => m.isMoney).toList(),
          [GoalMetric.moneySum, GoalMetric.netSavings]);
      expect(GoalMetric.values.where((m) => m.isTrackerMetric).toList(),
          [GoalMetric.trackerSum, GoalMetric.trackerCount]);
    });
  });

  group('GoalScope', () {
    test('both scopes survive being stored as JSON text', () {
      final money = MoneyScope(QueryFilters(
        direction: MoneyDirection.expense,
        categorySubtreePaths: const ['/food/', '/food/dining/'],
        tags: TagsAny(const ['/work/']),
      ));
      for (final scope in <GoalScope>[money, cigarettes]) {
        final text = jsonEncode(scope.toJson());
        final restored =
            GoalScope.fromJson(jsonDecode(text) as Map<String, Object?>);
        expect(restored, scope);
        expect(restored.runtimeType, scope.runtimeType);
      }
    });

    test('an unknown type or a missing field is refused, not defaulted', () {
      for (final bad in <Map<String, Object?>>[
        {'type': 'merchant'},
        {'filters': <String, Object?>{}},
        {'type': 'money'},
        {'type': 'tracker'},
        {'type': 'tracker', 'trackerId': ''},
        {'type': 'tracker', 'trackerId': 7},
      ]) {
        expect(() => GoalScope.fromJson(bad), throwsFormatException,
            reason: 'accepted $bad');
      }
    });

    test('money filters that carry a date range are refused', () {
      // The goal's period decides the dates. A stored range would contradict
      // it, and whichever one won, the other would be silently wrong.
      final dated = const QueryFilters()
          .withDateRange(const DateRange(DateKey(20261001), DateKey(20261031)));
      expect(() => MoneyScope(dated), throwsArgumentError);
      expect(
          () => GoalScope.fromJson(
              {'type': 'money', 'filters': dated.toJson()}),
          throwsFormatException);
    });

    test('a tracker scope names a tracker', () {
      expect(() => TrackerScope(''), throwsArgumentError);
    });
  });

  group('GoalAmount', () {
    test('money adds, subtracts and compares in exact minor units', () {
      expect(rials(7999) + rials(1), rials(8000));
      expect(rials(100) - rials(250), rials(-150));
      expect(rials(8000).compareTo(rials(8000)), 0);
      expect(rials(7999).compareTo(rials(8000)), lessThan(0));
      expect(const QuantityAmount(2.5) + const QuantityAmount(0.5),
          const QuantityAmount(3));
    });

    test('money and a quantity never mix', () {
      // Rials plus cigarettes is a measurer bug. It must surface, not add up.
      const money = MoneyAmount(Money(1));
      const quantity = QuantityAmount(1);
      expect(() => money + quantity, throwsArgumentError);
      expect(() => quantity - money, throwsArgumentError);
      expect(() => money.compareTo(quantity), throwsArgumentError);
      expect(() => quantity.ratioTo(money), throwsArgumentError);
      expect(() => money.reaches(quantity, 80), throwsArgumentError);
    });

    test('zero keeps the subtype; isZero and isNegative read the sign', () {
      expect(rials(500).zero, rials(0));
      expect(const QuantityAmount(2).zero, const QuantityAmount(0));
      expect(rials(0).isZero, isTrue);
      expect(rials(-1).isNegative, isTrue);
      expect(const QuantityAmount(0.5).isNegative, isFalse);
    });

    test('ratioTo is a fraction, and a zero target never divides', () {
      expect(rials(2500).ratioTo(rials(10000)), 0.25);
      expect(rials(-2000).ratioTo(rials(10000)), -0.2);
      expect(const QuantityAmount(3).ratioTo(const QuantityAmount(4)), 0.75);
      // Zero cigarettes: none so far is 0% of the way; any at all is past it.
      expect(const QuantityAmount(0).ratioTo(const QuantityAmount(0)), 0);
      expect(const QuantityAmount(1).ratioTo(const QuantityAmount(0)),
          double.infinity);
      expect(rials(-5).ratioTo(rials(0)), 0);
    });

    test('reaches compares money exactly at a threshold', () {
      expect(rials(7999).reaches(rials(10000), 80), isFalse);
      expect(rials(8000).reaches(rials(10000), 80), isTrue);
      expect(rials(10000).reaches(rials(10000), 100), isTrue);
      expect(rials(-500).reaches(rials(10000), 80), isFalse);
      expect(const QuantityAmount(4).reaches(const QuantityAmount(5), 80),
          isTrue);
      expect(const QuantityAmount(3.9).reaches(const QuantityAmount(5), 80),
          isFalse);
    });

    test('a decimal exactly on a threshold reaches it', () {
      // 0.29 * 100 == 28.999999999999996 in binary floating point.
      expect(const QuantityAmount(0.29).reaches(const QuantityAmount(1), 29),
          isTrue);
      expect(const QuantityAmount(0.2899).reaches(const QuantityAmount(1), 29),
          isFalse);
    });

    test('a zero target is reached by anything above zero', () {
      for (final percent in [1, 80, 100]) {
        expect(
            const QuantityAmount(0).reaches(const QuantityAmount(0), percent),
            isFalse);
        expect(
            const QuantityAmount(1).reaches(const QuantityAmount(0), percent),
            isTrue);
        expect(rials(1).reaches(rials(0), percent), isTrue);
      }
    });

    test('exceeds is strictly over, with the tolerance reaches uses', () {
      expect(rials(10001).exceeds(rials(10000)), isTrue);
      expect(rials(10000).exceeds(rials(10000)), isFalse,
          reason: 'exactly at a cap is within it');
      expect(rials(1).exceeds(rials(0)), isTrue);
      expect(rials(0).exceeds(rials(0)), isFalse);
      // 0.1 + 0.2 is 0.30000000000000004: on the target, so it reaches 100%
      // and is not over it. A value that reaches 100% is never also over.
      final sum = const QuantityAmount(0.1) + const QuantityAmount(0.2);
      expect(sum.reaches(const QuantityAmount(0.3), 100), isTrue);
      expect(sum.exceeds(const QuantityAmount(0.3)), isFalse);
      expect(const QuantityAmount(0.300001).exceeds(const QuantityAmount(0.3)),
          isTrue,
          reason: 'past the tolerance is over');
      expect(const QuantityAmount(1).exceeds(const QuantityAmount(0)), isTrue);
      expect(const QuantityAmount(0).exceeds(const QuantityAmount(0)), isFalse);
      expect(() => rials(1).exceeds(const QuantityAmount(1)),
          throwsArgumentError);
    });

    test('scaledBy keeps money integer, rounding half away from zero', () {
      expect(rials(10).scaledBy(1, 4), rials(3)); // 2.5
      expect(rials(-10).scaledBy(1, 4), rials(-3)); // -2.5
      expect(rials(10).scaledBy(1, 3), rials(3)); // 3.33...
      expect(rials(20).scaledBy(1, 3), rials(7)); // 6.66...
      expect(rials(10000).scaledBy(31, 10), rials(31000));
      expect(const QuantityAmount(10).scaledBy(1, 4),
          const QuantityAmount(2.5));
    });

    test('dividedUp rounds money up: it is a minimum to set aside', () {
      expect(rials(10).dividedUp(3), rials(4));
      expect(rials(9).dividedUp(3), rials(3));
      expect(rials(-10).dividedUp(3), rials(-3)); // the ceiling of -3.33...
      expect(const QuantityAmount(10).dividedUp(4), const QuantityAmount(2.5));
    });

    test('scaling or dividing by nothing is refused', () {
      // A quantity would otherwise turn into infinity without a word.
      expect(() => rials(10).scaledBy(1, 0), throwsArgumentError);
      expect(
          () => const QuantityAmount(1).scaledBy(1, -2), throwsArgumentError);
      expect(() => rials(10).dividedUp(0), throwsArgumentError);
      expect(() => const QuantityAmount(1).dividedUp(0), throwsArgumentError);
    });
  });

  group('GoalPeriod', () {
    test('each period maps to its stored columns and back', () {
      for (final type in PeriodType.values) {
        final recurring = RecurringPeriod(type, const DateKey(20261015));
        expect(recurring.storedName, type.name);
        expect(recurring.startDate, const DateKey(20261015));
        expect(recurring.endDate, isNull);
        expect(GoalPeriod.fromStored(type.name, 20261015, null), recurring);
      }
      final range = FixedRangePeriod(
          const DateRange(DateKey(20261101), DateKey(20270320)));
      expect(range.storedName, 'fixedRange');
      expect(range.startDate, const DateKey(20261101));
      expect(range.endDate, const DateKey(20270320));
      expect(GoalPeriod.fromStored('fixedRange', 20261101, 20270320), range);
    });

    test('stored columns that mean nothing are refused', () {
      for (final (name, start, end) in [
        ('fortnight', 20261001, null), // not a period
        ('month', 20261001, 20261031), // a recurring period has no end
        ('fixedRange', 20261001, null), // a range needs one
        ('fixedRange', 20261031, 20261001), // and cannot end before it starts
      ]) {
        expect(() => GoalPeriod.fromStored(name, start, end),
            throwsFormatException,
            reason: 'accepted ($name, $start, $end)');
      }
    });

    test('a fixed range cannot end before it starts', () {
      expect(
          () => FixedRangePeriod(
              const DateRange(DateKey(20261031), DateKey(20261001))),
          throwsArgumentError);
      expect(
          FixedRangePeriod(
                  const DateRange(DateKey(20261001), DateKey(20261001)))
              .range
              .dayCount,
          1);
    });
  });

  group('Goal', () {
    test('each shape the editor offers builds', () {
      // A cap, a limit, a minimum and savings: metric and direction only.
      expect(goal, returnsNormally);
      expect(
          () => goal(
              metric: GoalMetric.trackerCount,
              scope: cigarettes,
              target: const QuantityAmount(0),
              period: const RecurringPeriod(PeriodType.day, DateKey(20261010))),
          returnsNormally);
      expect(
          () => goal(
              metric: GoalMetric.trackerCount,
              scope: TrackerScope('gym'),
              direction: GoalDirection.atLeast,
              target: const QuantityAmount(3),
              period:
                  const RecurringPeriod(PeriodType.week, DateKey(20261010))),
          returnsNormally);
      expect(
          () => goal(
              metric: GoalMetric.netSavings,
              scope: everything,
              direction: GoalDirection.atLeast,
              target: rials(5000000),
              period: FixedRangePeriod(
                  const DateRange(DateKey(20261101), DateKey(20270320)))),
          returnsNormally);
    });

    test('the scope must match the metric family', () {
      expect(() => goal(scope: cigarettes), throwsArgumentError);
      expect(
          () => goal(
              metric: GoalMetric.trackerSum,
              target: const QuantityAmount(2)),
          throwsArgumentError);
      expect(
          () => goal(
              metric: GoalMetric.txnCount,
              scope: cigarettes,
              target: const QuantityAmount(5)),
          throwsArgumentError);
    });

    test('the target type must match the metric', () {
      expect(() => goal(target: const QuantityAmount(10000)),
          throwsArgumentError);
      expect(() => goal(metric: GoalMetric.txnCount, target: rials(5)),
          throwsArgumentError);
      expect(
          () => goal(
              metric: GoalMetric.trackerSum,
              scope: cigarettes,
              target: rials(5)),
          throwsArgumentError);
      expect(
          () => goal(
              metric: GoalMetric.netSavings,
              scope: everything,
              direction: GoalDirection.atLeast,
              target: const QuantityAmount(5)),
          throwsArgumentError);
    });

    test('net savings reads both directions, so it cannot filter one', () {
      // Income minus expense: a direction filter would zero one side.
      expect(
          () => goal(
              metric: GoalMetric.netSavings,
              direction: GoalDirection.atLeast,
              scope: food),
          throwsArgumentError);
    });

    test('a negative target is refused; zero only for atMost', () {
      expect(() => goal(target: rials(-1)), throwsArgumentError);
      expect(
          () => goal(target: rials(0), direction: GoalDirection.atLeast),
          throwsArgumentError);
      // "Spend nothing on this" is a real cap, as zero cigarettes is a limit.
      expect(() => goal(target: rials(0)), returnsNormally);
    });

    test('alert percents are ascending, distinct and within 1 to 100', () {
      for (final bad in [
        <int>[],
        [100, 80],
        [80, 80],
        [0, 100],
        [80, 101],
      ]) {
        expect(() => goal(alertPercents: bad), throwsArgumentError,
            reason: 'accepted $bad');
      }
      expect(() => goal(alertPercents: [1, 100]), returnsNormally);
      expect(() => goal(alertPercents: [50]), returnsNormally);
    });

    test('the week starts on an ISO weekday', () {
      expect(() => goal(weekStart: 0), throwsArgumentError);
      expect(() => goal(weekStart: 8), throwsArgumentError);
      expect(() => goal(weekStart: DateTime.monday), returnsNormally);
      expect(() => goal(weekStart: DateTime.sunday), returnsNormally);
    });

    test('a blank name is refused', () {
      expect(() => goal(name: ''), throwsArgumentError);
      expect(() => goal(name: '   '), throwsArgumentError);
    });

    test('the alert percents cannot change after construction', () {
      // A goal keys provider families; a list mutated after hashing would
      // strand its cache entry.
      final percents = [80, 100];
      final g = goal(alertPercents: percents);
      percents.add(120);
      expect(g.alertPercents, [80, 100]);
      expect(() => g.alertPercents.add(90), throwsUnsupportedError);
    });

    test('copyWith replaces only what it names, and validates the result', () {
      final g = goal();
      expect(g.copyWith(), g);
      final paused = g.copyWith(name: 'Eating out', active: false);
      expect(paused.id, 'g1');
      expect(paused.name, 'Eating out');
      expect(paused.active, isFalse);
      expect(paused.copyWith(name: g.name, active: true), g);
      // A zero cap is fine; turned into a goal to reach, it is not.
      final zero = goal(target: rials(0));
      expect(() => zero.copyWith(direction: GoalDirection.atLeast),
          throwsArgumentError);
    });

    test('equal goals are equal and hash alike; every field counts', () {
      expect(goal(), goal());
      expect(goal().hashCode, goal().hashCode);
      expect(goal(), isNot(goal(alertPercents: [50, 100])));
      expect(goal(), isNot(goal(weekStart: DateTime.monday)));
      expect(goal(), isNot(goal().copyWith(active: false)));
    });

    test('two goals differing in any one of the eleven fields are unequal',
        () {
      // A goal keys provider families and the history cache's content
      // guard, so a field == ignored would serve one goal another's numbers.
      // The base has no direction filter, so the metric can switch alone.
      final base = goal(scope: everything);
      final variants = <String, Goal>{
        'id': goal(id: 'g2', scope: everything),
        'name': base.copyWith(name: 'Eating out'),
        'metric': base.copyWith(metric: GoalMetric.netSavings),
        'scope': base.copyWith(scope: food),
        'direction': base.copyWith(direction: GoalDirection.atLeast),
        'target': base.copyWith(target: rials(20000)),
        'period': base.copyWith(
            period: const RecurringPeriod(PeriodType.week, DateKey(20261001))),
        'calendar': base.copyWith(calendar: CalendarKind.gregorian),
        'weekStart': base.copyWith(weekStart: DateTime.monday),
        'alertPercents': base.copyWith(alertPercents: [50, 100]),
        'active': base.copyWith(active: false),
      };
      for (final MapEntry(key: field, value: variant) in variants.entries) {
        expect(variant, isNot(base), reason: field);
        expect(base, isNot(variant), reason: '$field, the other way round');
      }
    });

    test('alert percents survive being stored as JSON text', () {
      expect(Goal.alertPercentsToJson(const [80, 100]), '[80,100]');
      expect(Goal.alertPercentsFromJson('[80,100]'), [80, 100]);
      expect(
          Goal.alertPercentsFromJson(
              Goal.alertPercentsToJson(const [25, 50, 100])),
          [25, 50, 100]);
    });

    test('stored alert percents must be a JSON list of ints', () {
      for (final bad in [
        '',
        'eighty',
        '{"a":1}',
        'null',
        '80',
        '[80.5]',
        '["80"]',
        '[null]',
      ]) {
        expect(() => Goal.alertPercentsFromJson(bad), throwsFormatException,
            reason: 'accepted "$bad"');
      }
    });
  });
}
