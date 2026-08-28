import '../calendar/calendar.dart';
import '../calendar/date_key.dart';
import '../money/currency.dart';
import 'amount_parser.dart';
import 'date_parser.dart';
import 'field_role.dart';
import 'message_normalizer.dart';
import 'message_template.dart';
import 'parsed_message.dart';

/// Applies stored templates to an incoming message, in priority order.
///
/// Higher priority is tried first and ties break by ascending id, so the same
/// inbox parses identically on every run rather than depending on the order
/// the database happened to return rows in.
abstract final class TemplateMatcher {
  static MatchOutcome match({
    required String sender,
    required String rawBody,
    required DateTime receivedAt,
    required Iterable<MessageTemplate> templates,
    required Currency currency,
    required AppCalendar calendar,
  }) {
    // Normalized here rather than by the caller: one path, nothing to forget.
    final body = MessageNormalizer.normalize(rawBody);

    final candidates =
        templates.where((t) => t.enabled && t.matchesSender(sender)).toList()
          ..sort((a, b) {
            final byPriority = b.priority.compareTo(a.priority);
            return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
          });

    for (final template in candidates) {
      final match = template.compiled().firstMatch(body);
      if (match == null) continue;

      // Read roles from the field map rather than probing the regex:
      // namedGroup throws for a group the pattern does not define.
      String? group(FieldRole role) =>
          template.fieldMap.has(role) ? match.namedGroup(role.name) : null;

      final rawAmount = group(FieldRole.amount);
      if (rawAmount == null) {
        return MalformedMatch(
            templateId: template.id, reason: 'matched but captured no amount');
      }

      try {
        final amount = AmountParser.parse(rawAmount,
            currency: currency, amountScale: template.amountScale);

        final rawBalance = group(FieldRole.balance);
        final balance = rawBalance == null
            ? null
            : AmountParser.parse(rawBalance,
                currency: currency, amountScale: template.amountScale);

        return MatchedMessage(ParsedMessage(
          templateId: template.id,
          amount: amount,
          direction: template.directionRule.resolve(body),
          date: _dateOf(group(FieldRole.date), receivedAt, calendar),
          merchant: group(FieldRole.merchant)?.trim(),
          card: group(FieldRole.card),
          balance: balance,
        ));
      } on FormatException catch (error) {
        // The template claimed this message and then produced nonsense. That
        // is a template bug, not a missing template, and falling through to a
        // lower-priority template would let the wrong one claim the message.
        return MalformedMatch(templateId: template.id, reason: error.message);
      }
    }

    return const NoMatchingTemplate();
  }

  /// A malformed date costs the transaction its exact day, not its existence.
  static DateKey _dateOf(
      String? captured, DateTime receivedAt, AppCalendar calendar) {
    if (captured == null) return DateKey.fromDateTime(receivedAt);
    try {
      return DateParser.parse(captured, calendar: calendar);
    } on FormatException {
      return DateKey.fromDateTime(receivedAt);
    }
  }
}
