import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

Bucket bucket(BucketKey key, int minorUnits, {int count = 1}) =>
    Bucket(key: key, money: Money(minorUnits), count: count);

void main() {
  group('AnalyticsResult', () {
    test('bucketSum adds every bucket', () {
      final result = AnalyticsResult(
        buckets: [
          bucket(const CategoryKey('food', '/food/'), 1000),
          bucket(const CategoryKey('travel', '/travel/'), 2500),
        ],
        trueTotal: const Money(3500),
        trueCount: 2,
        bucketsMayOverlap: false,
      );
      expect(result.bucketSum, const Money(3500));
      expect(result.overlaps, isFalse);
    });

    test('a non-overlapping dimension has bucketSum == trueTotal', () {
      final result = AnalyticsResult(
        buckets: [bucket(const CategoryKey('food', '/food/'), 1000)],
        trueTotal: const Money(1000),
        trueCount: 1,
        bucketsMayOverlap: false,
      );
      expect(result.bucketSum, result.trueTotal);
    });

    test('a tag dimension can exceed the true total, and says so', () {
      // The headline trap: one transaction tagged #travel AND #food lands in
      // both buckets. Asserting equality here would be the bug.
      final result = AnalyticsResult(
        buckets: [
          bucket(const TagKey('travel', '/travel/'), 1000),
          bucket(const TagKey('food', '/food/'), 1000),
        ],
        trueTotal: const Money(1000),
        trueCount: 1,
        bucketsMayOverlap: true,
      );
      expect(result.bucketSum.minorUnits,
          greaterThan(result.trueTotal.minorUnits));
      expect(result.overlaps, isTrue);
    });

    test('an empty result is zero, not an error', () {
      const result = AnalyticsResult(
        buckets: [],
        trueTotal: Money.zero,
        trueCount: 0,
        bucketsMayOverlap: false,
      );
      expect(result.bucketSum, Money.zero);
      expect(result.buckets, isEmpty);
    });
  });

  group('BucketKey', () {
    test('null-valued keys are legitimate buckets', () {
      // "No payment method" and "no merchant" are real answers. The columns
      // are nullable and the rows still count.
      expect(const PaymentMethodKey(null).paymentMethodId, isNull);
      expect(const MerchantKey(null).merchant, isNull);
      expect(const ReflectionKey(necessity: null, satisfaction: null).necessity,
          isNull);
    });

    test('keys compare by value so buckets can be looked up', () {
      expect(const CategoryKey('a', '/a/'), const CategoryKey('a', '/a/'));
      expect(
          const CategoryKey('a', '/a/'), isNot(const CategoryKey('b', '/b/')));
      // Not const: HourOfDayKey validates its range, so it has a body.
      expect(HourOfDayKey(9), HourOfDayKey(9));
      expect(
          PeriodKey(DateRange(const DateKey(20260101), const DateKey(20260131))),
          PeriodKey(
              DateRange(const DateKey(20260101), const DateKey(20260131))));
    });

    test('an out-of-range hour is rejected', () {
      expect(() => HourOfDayKey(24), throwsArgumentError);
      expect(() => HourOfDayKey(-1), throwsArgumentError);
    });

    test('an out-of-range weekday is rejected', () {
      expect(() => DayOfWeekKey(0), throwsArgumentError);
      expect(() => DayOfWeekKey(8), throwsArgumentError);
    });
  });
}
