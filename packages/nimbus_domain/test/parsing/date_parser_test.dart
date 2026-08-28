import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('DateParser', () {
    const jalali = JalaliCalendar();
    const gregorian = GregorianCalendar();

    test('a Jalali year-first date resolves through the Jalali calendar', () {
      expect(DateParser.parse('1403/05/12', calendar: jalali),
          jalali.keyOf(1403, 5, 12));
    });

    test('a Gregorian year is detected even when the active calendar is Jalali',
        () {
      // The year is unambiguous: no Jalali year is 2026. Trusting the active
      // calendar here would place the transaction 621 years away.
      expect(DateParser.parse('2026-08-28', calendar: jalali),
          gregorian.keyOf(2026, 8, 28));
    });

    test('a Jalali year is detected even when the active calendar is Gregorian',
        () {
      expect(DateParser.parse('1403/05/12', calendar: gregorian),
          jalali.keyOf(1403, 5, 12));
    });

    test('a day-first date with a four-digit year is read day/month/year', () {
      expect(DateParser.parse('28-08-2026', calendar: gregorian),
          gregorian.keyOf(2026, 8, 28));
    });

    test('a two-part date is rejected rather than guessed', () {
      // The matcher falls back to the message receipt date, which is right
      // far more often than a guessed year.
      expect(() => DateParser.parse('05/12', calendar: jalali),
          throwsFormatException);
    });

    test('a two-digit year is rejected rather than guessed', () {
      expect(() => DateParser.parse('03/05/12', calendar: jalali),
          throwsFormatException);
    });

    test('an out-of-range month throws', () {
      expect(() => DateParser.parse('1403/13/12', calendar: jalali),
          throwsFormatException);
    });

    test('garbage throws', () {
      expect(() => DateParser.parse('x/y/z', calendar: jalali),
          throwsFormatException);
    });
  });
}
