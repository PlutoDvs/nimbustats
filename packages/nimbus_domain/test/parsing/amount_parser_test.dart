import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('AmountParser', () {
    test('a comma-grouped Toman amount parses exactly', () {
      expect(AmountParser.parse('1,250,000', currency: Currency.toman),
          const Money(1250000));
    });

    test('a dot-grouped amount parses the same way for Toman', () {
      // Iranian SMS use both separators for grouping. Toman has no decimal
      // digits, so a dot cannot mean anything else.
      expect(AmountParser.parse('1.250.000', currency: Currency.toman),
          const Money(1250000));
    });

    test('amountScale converts a Rial quote into Toman', () {
      expect(
          AmountParser.parse('12,500,000',
              currency: Currency.toman, amountScale: 10),
          const Money(1250000));
    });

    test('a scale that does not divide exactly throws', () {
      // Truncating here would understate every captured expense forever.
      expect(
          () => AmountParser.parse('12,500,005',
              currency: Currency.toman, amountScale: 10),
          throwsFormatException);
    });

    test('a decimal currency keeps its fraction', () {
      expect(AmountParser.parse('12.50', currency: Currency.usd),
          const Money(1250));
    });

    test('a decimal currency still groups with commas', () {
      expect(AmountParser.parse('1,234.50', currency: Currency.usd),
          const Money(123450));
    });

    test('European ordering is read by last-separator-wins', () {
      expect(AmountParser.parse('1.234,50', currency: Currency.usd),
          const Money(123450));
    });

    test('a lone separator with a three-digit group is read as grouping', () {
      // '12.505' cannot be a USD fraction -- USD has two decimal digits, so
      // twelve-point-five-oh-five is not expressible. Grouping is the only
      // valid reading, and pinning it here stops a later "fix" from turning
      // 12,505 into 12.50.
      expect(AmountParser.parse('12.505', currency: Currency.usd),
          const Money(1250500));
    });

    test('more fraction digits than the currency allows throws', () {
      // Four digits cannot be a thousands group, so this is unambiguously a
      // fraction -- and too long a one to represent without rounding.
      expect(() => AmountParser.parse('12.5055', currency: Currency.usd),
          throwsFormatException);
    });

    test('a non-numeric capture throws rather than yielding zero', () {
      // A silent Money.zero here is a captured expense that vanishes.
      expect(() => AmountParser.parse('abc', currency: Currency.toman),
          throwsFormatException);
      expect(() => AmountParser.parse('', currency: Currency.toman),
          throwsFormatException);
    });

    test('a non-positive scale is a programming error', () {
      expect(
          () => AmountParser.parse('100',
              currency: Currency.toman, amountScale: 0),
          throwsArgumentError);
    });
  });
}
