import '../money/currency.dart';
import '../money/money.dart';

/// Turns a captured digit run into exact [Money].
///
/// Iranian SMS group thousands with both `,` and `.`, so `1.250.000` and
/// `1,250,000` are the same number. The rules, in order:
///
/// 1. A currency with no decimal digits (Toman) treats every separator as a
///    grouping separator. That removes the ambiguity for the primary currency.
/// 2. When both separators appear, the one occurring last is the decimal.
/// 3. A lone separator kind groups when every group after the first is
///    exactly three digits, and is a decimal point when it is not.
/// 4. A fraction longer than the currency allows is an error, not a rounding.
abstract final class AmountParser {
  static final _shape = RegExp(r'^[\d.,]+$');
  static final _separators = RegExp(r'[.,]');
  static final _anyDigit = RegExp(r'\d');

  static Money parse(
    String captured, {
    required Currency currency,
    int amountScale = 1,
  }) {
    if (amountScale < 1) {
      throw ArgumentError.value(
          amountScale, 'amountScale', 'must be a positive divisor');
    }

    final text = captured.trim();
    if (text.isEmpty || !_shape.hasMatch(text) || !_anyDigit.hasMatch(text)) {
      throw FormatException('not a number', captured);
    }

    final decimalSeparator = _decimalSeparatorOf(text, currency);

    final String wholeText;
    final String fractionText;
    if (decimalSeparator == null) {
      wholeText = text.replaceAll(_separators, '');
      fractionText = '';
    } else {
      final cut = text.lastIndexOf(decimalSeparator);
      wholeText = text.substring(0, cut).replaceAll(_separators, '');
      fractionText = text.substring(cut + 1).replaceAll(_separators, '');
    }

    if (fractionText.length > currency.decimalDigits) {
      throw FormatException(
          'more fraction digits than ${currency.code} allows', captured);
    }

    final whole = int.tryParse(wholeText.isEmpty ? '0' : wholeText);
    final fraction = int.tryParse(fractionText.isEmpty ? '0' : fractionText);
    if (whole == null || fraction == null) {
      throw FormatException('not a number', captured);
    }

    var padded = fraction;
    for (var i = fractionText.length; i < currency.decimalDigits; i++) {
      padded *= 10;
    }

    final minorUnits = whole * currency.minorUnitsPerMajor + padded;
    if (minorUnits % amountScale != 0) {
      // A remainder means the template's scale is wrong. Truncating would
      // understate every capture from this template, forever and silently.
      throw FormatException(
          'amount does not divide evenly by amountScale $amountScale',
          captured);
    }
    return Money(minorUnits ~/ amountScale);
  }

  static String? _decimalSeparatorOf(String text, Currency currency) {
    if (currency.decimalDigits == 0) return null;

    final lastDot = text.lastIndexOf('.');
    final lastComma = text.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      return lastDot > lastComma ? '.' : ',';
    }

    final separator = lastDot >= 0 ? '.' : (lastComma >= 0 ? ',' : null);
    if (separator == null) return null;

    final groups = text.split(separator);
    final grouped = groups.skip(1).every((group) => group.length == 3);
    return grouped ? null : separator;
  }
}
