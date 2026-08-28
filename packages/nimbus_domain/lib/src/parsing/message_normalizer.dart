import '../money/digits.dart';

/// The single normalization contract for captured messages.
///
/// Every template regex is generated from normalized text and matched against
/// normalized text. Two normalization paths that drift apart is how a stored
/// template silently stops matching a bank that changed nothing, so there is
/// exactly one: this function. The tokenizer, the matcher and the dedup hash
/// all route through it rather than asking their callers to remember.
///
/// The output alphabet is deliberately small: Latin digits, Persian letter
/// forms, no invisible formatting, single spaces, trimmed.
abstract final class MessageNormalizer {
  /// Zero-width non-joiner. Folded to a space rather than deleted, because
  /// banks spell the same compound word with a ZWNJ in one revision and a
  /// plain space in the next; folding both to a space makes one template
  /// cover both spellings.
  static const _zwnj = '\u{200C}';

  /// Invisible bidi, joiner and byte-order marks. Deleted outright — folding
  /// these to a space would insert a word boundary that is not in the
  /// message, and they are invisible in exactly the logs you would use to
  /// debug the resulting mismatch. ZWNJ (U+200C) is deliberately absent from
  /// this class; it is handled above.
  static final _invisible = RegExp(
    '[\u{200B}\u{200D}-\u{200F}\u{202A}-\u{202E}\u{2066}-\u{2069}\u{FEFF}]',
  );

  static final _whitespace = RegExp(r'\s+');

  /// Code points whose Persian counterpart is a different rune. They look
  /// alike and type alike; only the bytes differ, which is why an unfolded
  /// message fails to match a template built from a folded one.
  static const _folds = <String, String>{
    '\u{0643}': '\u{06A9}', // ARABIC KAF          -> PERSIAN KEHEH
    '\u{064A}': '\u{06CC}', // ARABIC YEH          -> FARSI YEH
    '\u{0649}': '\u{06CC}', // ARABIC ALEF MAKSURA -> FARSI YEH
    '\u{066B}': '.', // ARABIC DECIMAL SEPARATOR
    '\u{066C}': ',', // ARABIC THOUSANDS SEPARATOR
  };

  static String normalize(String input) {
    var text = Digits.toLatin(input);
    text = text.replaceAll(_invisible, '');
    text = text.replaceAll(_zwnj, ' ');

    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_folds[char] ?? char);
    }

    return buffer.toString().replaceAll(_whitespace, ' ').trim();
  }
}
