import 'package:meta/meta.dart';

import 'field_role.dart';
import 'token.dart';

/// A regex plus the roles its named groups carry.
@immutable
final class GeneratedTemplate {
  const GeneratedTemplate({required this.regex, required this.fieldMap});

  final String regex;
  final FieldMap fieldMap;

  @override
  bool operator ==(Object other) =>
      other is GeneratedTemplate &&
      other.regex == regex &&
      other.fieldMap == fieldMap;

  @override
  int get hashCode => Object.hash(regex, fieldMap);

  @override
  String toString() => 'GeneratedTemplate($regex)';
}

/// Turns a tokenized sample plus the user's role taps into a regex.
///
/// Four rules carry the weight here, and each exists because breaking it
/// costs the user money rather than convenience:
///
/// 1. Every word is escaped, so a literal `.` cannot become "any character".
/// 2. Unassigned numbers and dates become *tolerant non-capturing* groups. A
///    template built from a sample whose balance read 5,000,000 must still
///    match tomorrow's balance.
/// 3. The regex is anchored at both ends. This is what stops an OTP from
///    matching a purchase template. It costs recall — a bank that appends
///    variable trailing text needs a second template — and that is the
///    correct side of the trade when the output is a transaction.
/// 4. At least one unassigned word must survive as a literal anchor. A regex
///    made entirely of tolerant groups matches nearly anything.
abstract final class RegexGenerator {
  /// A merchant capture is bounded and lazy. An unbounded `.+` between two
  /// tolerant groups is how a template swallows half a message.
  static const merchantMaxLength = 40;

  static const _groupPatterns = <FieldRole, String>{
    FieldRole.amount: r'[\d,.]+',
    FieldRole.balance: r'[\d,.]+',
    FieldRole.date: r'\d{1,4}[/-]\d{1,2}[/-]\d{1,4}',
    FieldRole.card: r'[\dXx*\-]+',
    FieldRole.merchant: '.{1,$merchantMaxLength}?',
  };

  static String _escapeWord(String text) =>
      text.split(RegExp(r'\s+')).map(RegExp.escape).join(r'\s+');

  static GeneratedTemplate generate({
    required List<Token> tokens,
    required List<RoleAssignment> assignments,
  }) {
    final sorted = [...assignments]
      ..sort((a, b) => a.startIndex.compareTo(b.startIndex));

    final roles = <FieldRole>{};
    var previousEnd = -1;
    for (final assignment in sorted) {
      if (assignment.startIndex < 0 ||
          assignment.endIndex >= tokens.length ||
          assignment.endIndex < assignment.startIndex) {
        throw ArgumentError.value(
            '${assignment.startIndex}..${assignment.endIndex}',
            'assignment',
            'token range out of bounds');
      }
      if (!roles.add(assignment.role)) {
        throw ArgumentError.value(
            assignment.role.name, 'assignment', 'role assigned more than once');
      }
      if (assignment.startIndex <= previousEnd) {
        throw ArgumentError.value(
            assignment.role.name, 'assignment', 'token ranges overlap');
      }
      previousEnd = assignment.endIndex;
    }

    if (!roles.contains(FieldRole.amount)) {
      throw ArgumentError('a template with no amount can never build a '
          'transaction; assign FieldRole.amount');
    }

    final byStart = {for (final a in sorted) a.startIndex: a};
    final buffer = StringBuffer('^');
    var anchorChars = 0;
    var i = 0;

    while (i < tokens.length) {
      final assignment = byStart[i];
      if (assignment != null) {
        buffer.write('(?<${assignment.role.name}>'
            '${_groupPatterns[assignment.role]})');
        i = assignment.endIndex + 1;
        continue;
      }

      final token = tokens[i];
      switch (token.type) {
        case TokenType.word:
          buffer.write(_escapeWord(token.text));
          anchorChars += token.text.length;
        case TokenType.whitespace:
          buffer.write(r'\s+');
        case TokenType.number:
          buffer.write(r'(?:[\d,.]+)');
        case TokenType.dateLike:
          buffer.write(r'(?:\d{1,4}[/-]\d{1,2}[/-]\d{1,4})');
      }
      i++;
    }
    buffer.write(r'$');

    if (anchorChars == 0) {
      throw ArgumentError('every token is a tolerant group, so this regex '
          'would match unrelated messages; leave at least one word unassigned '
          'as an anchor');
    }

    return GeneratedTemplate(
        regex: buffer.toString(), fieldMap: FieldMap.of(roles));
  }
}
