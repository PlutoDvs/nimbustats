import 'package:meta/meta.dart';

/// What a run of text is, for the purpose of assigning it a role.
///
/// `word` is a single word rather than a whole run of text between numbers,
/// because the teach flow needs the user to be able to tap exactly the
/// merchant inside a longer sentence. `dateLike` is its own kind so
/// `1403/05/12` does not tokenize into three numbers.
enum TokenType { word, number, dateLike, whitespace }

/// A contiguous run of the normalized message, with its offsets.
///
/// Offsets are kept so the teach-template UI can highlight exactly what the
/// user tapped, and so the regex generator can rebuild the message.
@immutable
final class Token {
  const Token({
    required this.type,
    required this.text,
    required this.start,
    required this.end,
  });

  final TokenType type;
  final String text;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is Token &&
      other.type == type &&
      other.text == text &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(type, text, start, end);

  @override
  String toString() => 'Token(${type.name}, "$text", $start..$end)';
}
