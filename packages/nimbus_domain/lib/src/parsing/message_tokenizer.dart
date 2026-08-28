import 'token.dart';

/// Splits a normalized message into the runs a user can assign roles to.
///
/// The input must already have been through `MessageNormalizer.normalize`;
/// the patterns below assume Latin digits and single spaces.
abstract final class MessageTokenizer {
  /// Tried before [_number] at every position, so `1403/05/12` stays one
  /// token instead of collapsing into three numbers and two words.
  static final _dateLike = RegExp(r'\d{1,4}[/-]\d{1,2}[/-]\d{1,4}');

  /// A digit run that may carry grouping separators but must begin and end
  /// with a digit, so a trailing sentence period is left to the next word
  /// rather than handed to the amount parser as a dangling separator.
  static final _number = RegExp(r'\d[\d,.]*\d|\d');

  static final _whitespace = RegExp(r'\s+');

  /// Anything contiguous that is neither space nor digit. Punctuation stays
  /// attached to its word; the generator escapes it either way.
  static final _word = RegExp(r'[^\s\d]+');

  /// Order matters: the first pattern that matches at a position wins.
  static const _order = <TokenType>[
    TokenType.dateLike,
    TokenType.number,
    TokenType.whitespace,
    TokenType.word,
  ];

  static RegExp _patternFor(TokenType type) => switch (type) {
        TokenType.dateLike => _dateLike,
        TokenType.number => _number,
        TokenType.whitespace => _whitespace,
        TokenType.word => _word,
      };

  static List<Token> tokenize(String normalized) {
    final tokens = <Token>[];
    var i = 0;
    while (i < normalized.length) {
      var matched = false;
      for (final type in _order) {
        final match = _patternFor(type).matchAsPrefix(normalized, i);
        if (match == null) continue;
        tokens.add(Token(type: type, text: match[0]!, start: i, end: match.end));
        i = match.end;
        matched = true;
        break;
      }
      if (!matched) {
        // Unreachable: the four patterns cover every code point. Throwing
        // beats an infinite loop if that ever stops being true.
        throw StateError('tokenizer stalled at offset $i');
      }
    }
    return tokens;
  }
}
