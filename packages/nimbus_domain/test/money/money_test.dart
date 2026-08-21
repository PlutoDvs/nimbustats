import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Money', () {
    test('adds and subtracts without precision loss', () {
      expect(const Money(1500) + const Money(2500), const Money(4000));
      expect(const Money(1000) - const Money(2500), const Money(-1500));
    });

    test('sums an empty iterable to zero', () {
      expect(Money.sum(const []), Money.zero);
    });

    test('sums many values exactly', () {
      final values = List.generate(1000, (i) => Money(i));
      expect(Money.sum(values), const Money(499500));
    });

    test('compares and sorts by minor units', () {
      final list = [const Money(300), const Money(-100), const Money(50)]
        ..sort();
      expect(list, [const Money(-100), const Money(50), const Money(300)]);
    });

    test('equality is by value', () {
      expect(const Money(42), const Money(42));
      expect(const Money(42).hashCode, const Money(42).hashCode);
    });
  });

  group('Currency', () {
    test('toman has no decimal digits', () {
      expect(Currency.toman.code, 'IRT');
      expect(Currency.toman.decimalDigits, 0);
    });

    test('looks up by code and rejects unknown codes', () {
      expect(Currency.byCode('IRT'), Currency.toman);
      expect(() => Currency.byCode('XXX'), throwsArgumentError);
    });
  });
}
