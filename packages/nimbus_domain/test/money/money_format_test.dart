import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  final toman = MoneyFormatter(currency: Currency.toman, persianDigits: false);
  final tomanFa = MoneyFormatter(currency: Currency.toman, persianDigits: true);
  final usd = MoneyFormatter(currency: Currency.usd, persianDigits: false);

  group('Digits', () {
    test('converts Persian and Arabic-Indic digits to Latin', () {
      expect(Digits.toLatin('۴۵۰۰۰۰'), '450000');
      expect(Digits.toLatin('٤٥٠'), '450');
      expect(Digits.toLatin('12۳٤'), '1234');
    });

    test('converts Latin digits to Persian', () {
      expect(Digits.toPersian('450'), '۴۵۰');
    });
  });

  group('format', () {
    test('groups thousands', () {
      expect(toman.format(const Money(450000)), '450,000');
      expect(toman.format(const Money(1234567)), '1,234,567');
      expect(toman.format(const Money(999)), '999');
    });

    test('renders decimal currencies with their fraction', () {
      expect(usd.format(const Money(1234)), '12.34');
      expect(usd.format(const Money(5)), '0.05');
    });

    test('keeps the minus sign ahead of the digits', () {
      expect(toman.format(const Money(-450000)), '-450,000');
    });

    test('uses Persian digits when asked', () {
      expect(tomanFa.format(const Money(450000)), '۴۵۰٬۰۰۰');
    });
  });

  group('formatCompact', () {
    test('shortens large amounts', () {
      expect(toman.formatCompact(const Money(450000)), '450K');
      expect(toman.formatCompact(const Money(1200000)), '1.2M');
      expect(toman.formatCompact(const Money(3400000000)), '3.4B');
      expect(toman.formatCompact(const Money(999)), '999');
    });

    test('drops a trailing .0', () {
      expect(toman.formatCompact(const Money(2000000)), '2M');
    });

    test('promotes to the next unit when rounding reaches 1000', () {
      expect(toman.formatCompact(const Money(999999)), '1M');
      expect(toman.formatCompact(const Money(999499)), '999.5K');
    });

    test('keeps the minus sign ahead of the digits', () {
      expect(toman.formatCompact(const Money(-1200000)), '-1.2M');
    });
  });

  group('parse', () {
    test('accepts grouped, spaced, and Persian input', () {
      expect(toman.parse('450,000'), const Money(450000));
      expect(toman.parse('450 000'), const Money(450000));
      expect(toman.parse('۴۵۰٬۰۰۰'), const Money(450000));
    });

    test('accepts decimals for decimal currencies', () {
      expect(usd.parse('12.34'), const Money(1234));
      expect(usd.parse('12.3'), const Money(1230));
    });

    test('rejects junk rather than guessing', () {
      expect(toman.parse('abc'), isNull);
      expect(toman.parse(''), isNull);
    });
  });
}
