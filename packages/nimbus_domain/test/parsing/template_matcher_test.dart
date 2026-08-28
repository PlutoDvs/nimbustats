import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

const jalali = JalaliCalendar();
final receivedAt = DateTime(2026, 8, 28, 10, 30);

MessageTemplate purchase({
  String id = 'a',
  int priority = 0,
  bool enabled = true,
  int amountScale = 1,
  String regex = r'^kharid (?<amount>[\d,.]+) rial$',
  Iterable<FieldRole> roles = const [FieldRole.amount],
}) =>
    MessageTemplate(
      id: id,
      name: 'purchase',
      senderPattern: r'^BANK$',
      regex: regex,
      fieldMap: FieldMap.of(roles),
      amountScale: amountScale,
      directionRule: const FixedDirectionRule(ParsedDirection.debit),
      priority: priority,
      enabled: enabled,
    );

MatchOutcome run(
  String body,
  List<MessageTemplate> templates, {
  String sender = 'BANK',
}) =>
    TemplateMatcher.match(
      sender: sender,
      rawBody: body,
      receivedAt: receivedAt,
      templates: templates,
      currency: Currency.toman,
      calendar: jalali,
    );

void main() {
  group('TemplateMatcher', () {
    test('a matching template yields the parsed amount', () {
      final outcome = run('kharid 1,250 rial', [purchase()]);
      expect(outcome, isA<MatchedMessage>());
      final parsed = (outcome as MatchedMessage).message;
      expect(parsed.amount, const Money(1250));
      expect(parsed.direction, ParsedDirection.debit);
      expect(parsed.templateId, 'a');
    });

    test('it normalizes the body itself', () {
      // Persian digits and a bidi mark, exactly as a real SMS arrives.
      final outcome = run(
          'kharid \u{06F1},\u{06F2}\u{06F5}\u{06F0}\u{200F} rial',
          [purchase()]);
      expect((outcome as MatchedMessage).message.amount, const Money(1250));
    });

    test('the highest priority template wins', () {
      final outcome = run('kharid 1,250 rial', [
        purchase(id: 'low', priority: 1),
        purchase(id: 'high', priority: 9),
      ]);
      expect((outcome as MatchedMessage).message.templateId, 'high');
    });

    test('equal priorities break by ascending id, not list order', () {
      // Determinism matters: the same inbox must parse the same way twice.
      final forward =
          run('kharid 1,250 rial', [purchase(id: 'b'), purchase(id: 'a')]);
      final reverse =
          run('kharid 1,250 rial', [purchase(id: 'a'), purchase(id: 'b')]);
      expect((forward as MatchedMessage).message.templateId, 'a');
      expect((reverse as MatchedMessage).message.templateId, 'a');
    });

    test('disabled templates are skipped', () {
      expect(run('kharid 1,250 rial', [purchase(enabled: false)]),
          isA<NoMatchingTemplate>());
    });

    test('a template whose sender pattern does not match is skipped', () {
      expect(run('kharid 1,250 rial', [purchase()], sender: 'SOMEONE'),
          isA<NoMatchingTemplate>());
    });

    test('no template at all is a clean no-match', () {
      expect(run('ramz 12345', [purchase()]), isA<NoMatchingTemplate>());
    });

    test('amountScale is applied', () {
      final outcome = run('kharid 12,500 rial', [purchase(amountScale: 10)]);
      expect((outcome as MatchedMessage).message.amount, const Money(1250));
    });

    test('an unparseable amount is malformed, never a guessed number', () {
      final outcome =
          run('kharid 12,505 rial', [purchase(id: 'x', amountScale: 10)]);
      expect(outcome, isA<MalformedMatch>());
      expect((outcome as MalformedMatch).templateId, 'x');
    });

    test('a missing date falls back to the receipt date', () {
      // A message without every field is still worth keeping.
      final outcome = run('kharid 1,250 rial', [purchase()]);
      expect((outcome as MatchedMessage).message.date,
          DateKey.fromDateTime(receivedAt));
    });

    test('a captured date is used when present', () {
      final outcome = run('kharid 1,250 rial 1403/05/12', [
        purchase(
          regex: r'^kharid (?<amount>[\d,.]+) rial '
              r'(?<date>\d{1,4}[/-]\d{1,2}[/-]\d{1,4})$',
          roles: const [FieldRole.amount, FieldRole.date],
        )
      ]);
      expect(
          (outcome as MatchedMessage).message.date, jalali.keyOf(1403, 5, 12));
    });

    test('an unparseable date falls back rather than failing the match', () {
      // Losing the whole transaction over a malformed date would be worse
      // than booking it on the day it arrived.
      final outcome = run('kharid 1,250 rial 99/99/99', [
        purchase(
          regex: r'^kharid (?<amount>[\d,.]+) rial '
              r'(?<date>\d{1,4}[/-]\d{1,2}[/-]\d{1,4})$',
          roles: const [FieldRole.amount, FieldRole.date],
        )
      ]);
      expect((outcome as MatchedMessage).message.date,
          DateKey.fromDateTime(receivedAt));
    });

    test('a template with no merchant group still parses', () {
      // namedGroup throws for an undefined group, so the matcher must read
      // roles from the field map rather than probing.
      final outcome = run('kharid 1,250 rial', [purchase()]);
      expect((outcome as MatchedMessage).message.merchant, isNull);
      expect(outcome.message.amount, const Money(1250));
    });

    test('a merchant group is captured when the template defines one', () {
      final outcome = run('kharid az refah 1,250 rial', [
        purchase(
          regex: r'^kharid az (?<merchant>.{1,40}?) (?<amount>[\d,.]+) rial$',
          roles: const [FieldRole.merchant, FieldRole.amount],
        )
      ]);
      expect((outcome as MatchedMessage).message.merchant, 'refah');
    });
  });
}
