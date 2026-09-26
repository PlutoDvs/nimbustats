import 'currency.dart';
import 'digits.dart';
import 'money.dart';

/// Formats and parses [Money] for one currency and one digit style.
final class MoneyFormatter {
  const MoneyFormatter({required this.currency, required this.persianDigits});

  final Currency currency;
  final bool persianDigits;

  static const _latinGroupSeparator = ',';
  // U+066C ARABIC THOUSANDS SEPARATOR.
  static const _persianGroupSeparator = '\u066C';

  /// Suffixes in ascending magnitude; the index into this list doubles as the
  /// number of times [formatCompact] has divided by a thousand.
  static const _compactSuffixes = ['K', 'M', 'B'];

  String format(Money money) {
    final negative = money.isNegative;
    final units = money.abs().minorUnits;
    final divisor = currency.minorUnitsPerMajor;
    final major = units ~/ divisor;
    final minor = units % divisor;

    var text = _group(major.toString());
    if (currency.decimalDigits > 0) {
      text = '$text.${minor.toString().padLeft(currency.decimalDigits, '0')}';
    }
    if (negative) text = '-$text';
    return persianDigits ? Digits.toPersian(text) : text;
  }

  /// Short form for chart axes and dense lists, where full grouping is noise.
  String formatCompact(Money money) {
    final negative = money.isNegative;
    final major = money.abs().minorUnits ~/ currency.minorUnitsPerMajor;

    String text;
    if (major >= 1000) {
      // Divide against the *rounded* value, so 999_999 reads as "1M" rather
      // than "1000K" — rounding at one unit can carry into the next.
      var value = major.toDouble();
      var suffix = -1;
      while (suffix < _compactSuffixes.length - 1 && _round1(value) >= 1000) {
        value /= 1000;
        suffix++;
      }
      text = '${_trim(value)}${_compactSuffixes[suffix]}';
    } else {
      text = major.toString();
    }
    if (negative) text = '-$text';
    return persianDigits ? Digits.toPersian(text) : text;
  }

  /// What an amount field shows while the user is still typing.
  ///
  /// Unlike [format], this never adds what was not typed: `5` stays `5` rather
  /// than becoming `5.00`, and `50.` keeps its dot. A field puts the caret at
  /// the end, so anything [format] appended there would sit in front of the
  /// next key -- `5.00` then `0` is `5.000`, and $50 cannot be typed. Only the
  /// whole part is regrouped. Input that does not [parse] comes back exactly
  /// as typed: it is rejected once, on save, not rewritten mid-keystroke.
  String formatInput(String input) {
    if (parse(input) == null) return input;

    var text = _stripSeparators(Digits.toLatin(input));
    final negative = text.startsWith('-');
    if (negative) text = text.substring(1);

    final dot = text.indexOf('.');
    final whole = dot < 0 ? text : text.substring(0, dot);
    final fraction = dot < 0 ? '' : text.substring(dot);

    text = '${whole.isEmpty ? '' : _group(int.parse(whole).toString())}'
        '$fraction';
    if (negative) text = '-$text';
    return persianDigits ? Digits.toPersian(text) : text;
  }

  /// Returns null for input that is not a number. Never guesses.
  Money? parse(String input) {
    var text = _stripSeparators(Digits.toLatin(input));
    if (text.isEmpty) return null;

    final negative = text.startsWith('-');
    if (negative) text = text.substring(1);

    final parts = text.split('.');
    if (parts.length > 2) return null;
    if (parts.any((p) => p.isNotEmpty && !_isDigits(p))) return null;
    if (parts[0].isEmpty && (parts.length == 1 || parts[1].isEmpty)) return null;

    final major = parts[0].isEmpty ? 0 : int.parse(parts[0]);
    var minor = 0;
    if (parts.length == 2 && currency.decimalDigits > 0) {
      final fraction = parts[1].padRight(currency.decimalDigits, '0');
      if (fraction.length > currency.decimalDigits) return null;
      minor = int.parse(fraction);
    } else if (parts.length == 2 && parts[1].isNotEmpty) {
      return null; // a fraction on a zero-decimal currency is an error
    }

    final total = major * currency.minorUnitsPerMajor + minor;
    return Money(negative ? -total : total);
  }

  static String _stripSeparators(String text) => text
      .trim()
      .replaceAll(_latinGroupSeparator, '')
      .replaceAll(_persianGroupSeparator, '')
      .replaceAll(' ', '') // non-breaking space
      .replaceAll(' ', '');

  static bool _isDigits(String s) {
    for (final unit in s.codeUnits) {
      if (unit < 0x30 || unit > 0x39) return false;
    }
    return true;
  }

  String _group(String digits) {
    final separator =
        persianDigits ? _persianGroupSeparator : _latinGroupSeparator;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(separator);
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  static double _round1(double value) => (value * 10).round() / 10;

  static String _trim(double value) {
    final rounded = _round1(value);
    return rounded == rounded.truncateToDouble()
        ? rounded.toInt().toString()
        : rounded.toString();
  }
}
