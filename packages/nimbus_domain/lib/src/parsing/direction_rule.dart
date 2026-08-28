import 'package:meta/meta.dart';

import 'parsed_direction.dart';

/// How a template decides whether a message is money out or money in.
@immutable
sealed class DirectionRule {
  const DirectionRule();

  factory DirectionRule.fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    return switch (kind) {
      'fixed' => FixedDirectionRule(_directionOf(json['direction'])),
      'keyword' => KeywordDirectionRule(
          debitKeywords: _stringsOf(json['debitKeywords']),
          creditKeywords: _stringsOf(json['creditKeywords']),
          fallback: _directionOf(json['fallback']),
        ),
      _ => throw FormatException('unknown direction rule kind "$kind"'),
    };
  }

  ParsedDirection resolve(String normalizedBody);

  Map<String, Object?> toJson();

  static ParsedDirection _directionOf(Object? value) {
    for (final direction in ParsedDirection.values) {
      if (direction.name == value) return direction;
    }
    throw FormatException('unknown direction "$value"');
  }

  static List<String> _stringsOf(Object? value) => switch (value) {
        final List<Object?> list => list.map((e) => e.toString()).toList(),
        _ => throw FormatException('expected a keyword list, got "$value"'),
      };
}

/// Every message from this template moves money the same way.
@immutable
final class FixedDirectionRule extends DirectionRule {
  const FixedDirectionRule(this.direction);

  final ParsedDirection direction;

  @override
  ParsedDirection resolve(String normalizedBody) => direction;

  @override
  Map<String, Object?> toJson() =>
      {'kind': 'fixed', 'direction': direction.name};

  @override
  bool operator ==(Object other) =>
      other is FixedDirectionRule && other.direction == direction;

  @override
  int get hashCode => direction.hashCode;
}

/// The message's own wording decides.
///
/// A body carrying both a debit and a credit word — a transfer notice —
/// resolves to [fallback] rather than to whichever appeared first. Ordering
/// would be a coin flip dressed up as a decision.
@immutable
final class KeywordDirectionRule extends DirectionRule {
  const KeywordDirectionRule({
    required this.debitKeywords,
    required this.creditKeywords,
    required this.fallback,
  });

  final List<String> debitKeywords;
  final List<String> creditKeywords;
  final ParsedDirection fallback;

  @override
  ParsedDirection resolve(String normalizedBody) {
    final debit = debitKeywords.any(normalizedBody.contains);
    final credit = creditKeywords.any(normalizedBody.contains);
    if (debit && !credit) return ParsedDirection.debit;
    if (credit && !debit) return ParsedDirection.credit;
    return fallback;
  }

  @override
  Map<String, Object?> toJson() => {
        'kind': 'keyword',
        'debitKeywords': debitKeywords,
        'creditKeywords': creditKeywords,
        'fallback': fallback.name,
      };

  @override
  bool operator ==(Object other) =>
      other is KeywordDirectionRule &&
      other.fallback == fallback &&
      _sameList(other.debitKeywords, debitKeywords) &&
      _sameList(other.creditKeywords, creditKeywords);

  @override
  int get hashCode => Object.hash(
        fallback,
        Object.hashAll(debitKeywords),
        Object.hashAll(creditKeywords),
      );

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
