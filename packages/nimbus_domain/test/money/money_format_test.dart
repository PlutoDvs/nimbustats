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

  group('formatInput', () {
    // What the amount field shows while the user is still typing. Found on a
    // device: format() padded "5" to "5.00" mid-keystroke, so the next "0"
    // landed after the cents and $50 could not be typed at all.
    test('never adds cents the user has not typed', () {
      expect(usd.formatInput('5'), '5');
      expect(usd.formatInput('50'), '50');
    });

    test('keeps a trailing dot and a partial fraction as typed', () {
      expect(usd.formatInput('50.'), '50.');
      expect(usd.formatInput('50.2'), '50.2');
      expect(usd.formatInput('50.25'), '50.25');
    });

    test('groups the whole part as it grows', () {
      expect(usd.formatInput('1234.5'), '1,234.5');
      expect(toman.formatInput('45000'), '45,000');
      expect(toman.formatInput('1234567'), '1,234,567');
    });

    test('drops leading zeros from the whole part', () {
      expect(toman.formatInput('007'), '7');
      expect(usd.formatInput('00.5'), '0.5');
    });

    test('uses Persian digits and separators when asked', () {
      expect(tomanFa.formatInput('45000'), '۴۵٬۰۰۰');
    });

    test('leaves input that does not parse exactly as typed', () {
      // Rejected once, on save -- rewriting it mid-keystroke would make the
      // field fight the user.
      expect(usd.formatInput('5.000'), '5.000');
      expect(toman.formatInput('5.5'), '5.5');
      expect(usd.formatInput('.'), '.');
      expect(usd.formatInput('-'), '-');
    });

    test('whatever it shows parses back to the same amount format() would',
        () {
      for (final typed in ['5', '50.', '1234.5', '0.05']) {
        final shown = usd.formatInput(typed);
        expect(usd.parse(shown), usd.parse(typed), reason: typed);
      }
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
