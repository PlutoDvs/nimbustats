import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'corpus/sample_messages.dart';

/// Builds the purchase template the way the teach flow would: normalize the
/// sample, tokenize it, tap the merchant, the amount and the date.
///
/// Indices are looked up by content rather than hardcoded, so a reworded
/// sample fails loudly here instead of silently tagging the wrong tokens.
MessageTemplate buildTemplate() {
  final tokens =
      MessageTokenizer.tokenize(MessageNormalizer.normalize(purchaseSample));

  final merchantStart = tokens
      .indexWhere((t) => t.type == TokenType.word && t.text == 'فروشگاه');
  final amountIndex = tokens.indexWhere((t) => t.type == TokenType.number);
  final dateIndex = tokens.indexWhere((t) => t.type == TokenType.dateLike);
  if (merchantStart < 0 || amountIndex < 0 || dateIndex < 0) {
    throw StateError('corpus drifted: the sample no longer tokenizes as '
        'merchant / amount / date');
  }

  final generated = RegexGenerator.generate(
    tokens: tokens,
    assignments: [
      RoleAssignment(
          startIndex: merchantStart,
          endIndex: merchantStart + 2,
          role: FieldRole.merchant),
      RoleAssignment.single(amountIndex, FieldRole.amount),
      RoleAssignment.single(dateIndex, FieldRole.date),
    ],
  );

  return MessageTemplate(
    id: 'purchase',
    name: 'purchase',
    senderPattern: r'^BANK$',
    regex: generated.regex,
    fieldMap: generated.fieldMap,
    // The sample quotes Rial; the app stores Toman.
    amountScale: 10,
    directionRule: const KeywordDirectionRule(
      debitKeywords: ['خرید'],
      creditKeywords: ['واریز'],
      fallback: ParsedDirection.debit,
    ),
    priority: 10,
    enabled: true,
    sampleBody: purchaseSample,
  );
}

MatchOutcome run(MessageTemplate template, String body) =>
    TemplateMatcher.match(
      sender: 'BANK',
      rawBody: body,
      receivedAt: DateTime.utc(2026, 8, 28, 10, 0),
      templates: [template],
      currency: Currency.toman,
      calendar: const JalaliCalendar(),
    );

void main() {
  final template = buildTemplate();

  group('corpus: messages that must parse', () {
    for (final sample in expectedMatches) {
      test(sample.label, () {
        final outcome = run(template, sample.body);
        expect(outcome, isA<MatchedMessage>(),
            reason: 'should have parsed: ${sample.body}');
        final parsed = (outcome as MatchedMessage).message;
        expect(parsed.amount, Money(sample.amountMinorUnits));
        expect(parsed.merchant, sample.merchant);
        expect(parsed.direction, ParsedDirection.debit);
      });
    }
  });

  group('corpus: near-misses that must NOT parse', () {
    for (final sample in nearMisses) {
      test(sample.label, () {
        // A regex that also matches an OTP is worse than one that matches
        // nothing: the first invents an expense, the second asks to be
        // taught. Never a MatchedMessage here.
        expect(run(template, sample.body), isNot(isA<MatchedMessage>()),
            reason: 'must not have parsed: ${sample.body}');
      });
    }
  });

  test('a redelivery dedups but a different message does not', () {
    final first = dedupHash(
        sender: 'BANK',
        body: purchaseSample,
        receivedAt: DateTime.utc(2026, 8, 28, 10, 0, 5));
    final retry = dedupHash(
        sender: 'BANK',
        body: purchaseSample,
        receivedAt: DateTime.utc(2026, 8, 28, 10, 0, 45));
    final different = dedupHash(
        sender: 'BANK',
        body: expectedMatches[1].body,
        receivedAt: DateTime.utc(2026, 8, 28, 10, 0, 5));

    expect(retry, first);
    expect(different, isNot(first));
  });
}
