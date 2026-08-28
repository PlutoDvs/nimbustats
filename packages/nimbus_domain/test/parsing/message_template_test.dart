import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

MessageTemplate template({
  String id = 't1',
  int amountScale = 1,
  int priority = 0,
  bool enabled = true,
  String senderPattern = r'^BANK$',
}) =>
    MessageTemplate(
      id: id,
      name: 'purchase',
      senderPattern: senderPattern,
      regex: r'^kharid (?<amount>[\d,.]+)$',
      fieldMap: FieldMap.of([FieldRole.amount]),
      amountScale: amountScale,
      directionRule: const FixedDirectionRule(ParsedDirection.debit),
      priority: priority,
      enabled: enabled,
    );

void main() {
  group('MessageTemplate', () {
    test('compiled() returns a usable RegExp', () {
      final match = template().compiled().firstMatch('kharid 1,250');
      expect(match?.namedGroup('amount'), '1,250');
    });

    test('matchesSender applies the sender pattern', () {
      expect(template().matchesSender('BANK'), isTrue);
      expect(template().matchesSender('OTHER'), isFalse);
    });

    test('a sender pattern that is not a valid regex throws on construction',
        () {
      // Better here than as a crash in the middle of ingesting a message.
      expect(() => template(senderPattern: '['), throwsFormatException);
    });

    test('a regex that does not compile throws on construction', () {
      expect(
          () => MessageTemplate(
                id: 't',
                name: 'bad',
                senderPattern: r'^X$',
                regex: '(?<amount>',
                fieldMap: FieldMap.of([FieldRole.amount]),
                amountScale: 1,
                directionRule: const FixedDirectionRule(ParsedDirection.debit),
                priority: 0,
                enabled: true,
              ),
          throwsFormatException);
    });

    test('a non-positive amountScale is rejected', () {
      expect(() => template(amountScale: 0), throwsArgumentError);
    });

    test('a field map claiming a group the regex lacks is rejected', () {
      // The matcher trusts the field map. A map that lies produces an
      // ArgumentError from deep inside the regex engine at capture time.
      expect(
          () => MessageTemplate(
                id: 't',
                name: 'lying',
                senderPattern: r'^X$',
                regex: r'^kharid (?<amount>[\d,.]+)$',
                fieldMap: FieldMap.of([FieldRole.amount, FieldRole.merchant]),
                amountScale: 1,
                directionRule: const FixedDirectionRule(ParsedDirection.debit),
                priority: 0,
                enabled: true,
              ),
          throwsArgumentError);
    });

    test('JSON round-trips', () {
      final original = template(amountScale: 10, priority: 5);
      expect(MessageTemplate.fromJson(original.toJson()), original);
    });
  });
}
