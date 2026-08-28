import 'package:meta/meta.dart';

import '../calendar/date_key.dart';
import '../money/money.dart';
import 'parsed_direction.dart';

/// Everything a template could extract from one message.
@immutable
final class ParsedMessage {
  const ParsedMessage({
    required this.templateId,
    required this.amount,
    required this.direction,
    required this.date,
    this.merchant,
    this.card,
    this.balance,
  });

  final String templateId;
  final Money amount;
  final ParsedDirection direction;

  /// Never null: a template without a date group falls back to the date the
  /// message arrived, which is right far more often than dropping the
  /// transaction would be.
  final DateKey date;
  final String? merchant;
  final String? card;
  final Money? balance;

  @override
  String toString() =>
      'ParsedMessage($templateId, $amount, ${direction.name}, $date)';
}

/// What matching a message produced.
///
/// A sealed result rather than a nullable [ParsedMessage] because "no
/// template recognised this" and "a template recognised it and then produced
/// nonsense" need different handling: the first is a prompt to teach a
/// template, the second is a bug to surface.
@immutable
sealed class MatchOutcome {
  const MatchOutcome();
}

final class MatchedMessage extends MatchOutcome {
  const MatchedMessage(this.message);

  final ParsedMessage message;
}

final class NoMatchingTemplate extends MatchOutcome {
  const NoMatchingTemplate();
}

final class MalformedMatch extends MatchOutcome {
  const MalformedMatch({required this.templateId, required this.reason});

  final String templateId;
  final String reason;
}
