/// Converts between Latin, Persian (U+06F0–U+06F9) and Arabic-Indic
/// (U+0660–U+0669) digits.
///
/// Persian keyboards, SMS from Iranian banks, and copy-pasted amounts all
/// arrive in a mix of these three sets. Everything numeric is normalized to
/// Latin on the way in and rendered in the user's preferred set on the way out.
abstract final class Digits {
  static const _persianZero = 0x06F0;
  static const _arabicZero = 0x0660;
  static const _latinZero = 0x30;

  static String toLatin(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= _persianZero && rune <= _persianZero + 9) {
        buffer.writeCharCode(_latinZero + (rune - _persianZero));
      } else if (rune >= _arabicZero && rune <= _arabicZero + 9) {
        buffer.writeCharCode(_latinZero + (rune - _arabicZero));
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  static String toPersian(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= _latinZero && rune <= _latinZero + 9) {
        buffer.writeCharCode(_persianZero + (rune - _latinZero));
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }
}
