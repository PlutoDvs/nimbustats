import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('mirror enums', () {
    test('names match the nimbus_data enums they mirror', () {
      // nimbus_domain cannot import nimbus_data, so these names are the
      // contract. Task 6's mapping test asserts the other side.
      expect(MoneyDirection.values.map((v) => v.name), ['expense', 'income']);
      expect(NecessityLevel.values.map((v) => v.name),
          ['needed', 'optional', 'avoidable']);
      expect(SatisfactionLevel.values.map((v) => v.name),
          ['glad', 'neutral', 'regret']);
    });
  });

  group('AmountRange', () {
    test('an unbounded range contains everything', () {
      final range = AmountRange();
      expect(range.isUnbounded, isTrue);
      expect(range.contains(const Money(-500)), isTrue);
      expect(range.contains(const Money(9999999)), isTrue);
    });

    test('bounds are inclusive on both ends', () {
      final range = AmountRange(
          minInclusive: const Money(1000), maxInclusive: const Money(2000));
      expect(range.contains(const Money(1000)), isTrue);
      expect(range.contains(const Money(2000)), isTrue);
      expect(range.contains(const Money(999)), isFalse);
      expect(range.contains(const Money(2001)), isFalse);
    });

    test('a half-open range bounds only the side it names', () {
      final atLeast = AmountRange(minInclusive: const Money(1000));
      expect(atLeast.contains(const Money(999)), isFalse);
      expect(atLeast.contains(const Money(10000000)), isTrue);
      expect(atLeast.isUnbounded, isFalse);
    });

    test('an inverted range is rejected at construction', () {
      // A range that can never match is a caller bug, and silently returning
      // nothing would look like "no data for this period".
      expect(
          () => AmountRange(
              minInclusive: const Money(2000), maxInclusive: const Money(1000)),
          throwsArgumentError);
    });

    test('JSON round-trips, including the unbounded sides', () {
      final bounded = AmountRange(
          minInclusive: const Money(1000), maxInclusive: const Money(2000));
      final halfOpen = AmountRange(maxInclusive: const Money(2000));
      final unbounded = AmountRange();
      for (final range in [bounded, halfOpen, unbounded]) {
        expect(AmountRange.fromJson(range.toJson()), range,
            reason: 'lost information round-tripping $range');
      }
    });

    test('value equality', () {
      expect(AmountRange(minInclusive: const Money(1)),
          AmountRange(minInclusive: const Money(1)));
      expect(AmountRange(minInclusive: const Money(1)),
          isNot(AmountRange(minInclusive: const Money(2))));
    });
  });
}
