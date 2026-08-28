import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('FixedDirectionRule', () {
    test('always resolves to its direction', () {
      const rule = FixedDirectionRule(ParsedDirection.debit);
      expect(rule.resolve('anything at all'), ParsedDirection.debit);
      expect(rule.resolve(''), ParsedDirection.debit);
    });

    test('JSON round-trips', () {
      const rule = FixedDirectionRule(ParsedDirection.credit);
      expect(DirectionRule.fromJson(rule.toJson()), rule);
    });
  });

  group('KeywordDirectionRule', () {
    const rule = KeywordDirectionRule(
      debitKeywords: ['برداشت', 'خرید'],
      creditKeywords: ['واریز'],
      fallback: ParsedDirection.debit,
    );

    test('a debit keyword resolves to debit', () {
      expect(rule.resolve('خرید از فروشگاه'), ParsedDirection.debit);
    });

    test('a credit keyword resolves to credit', () {
      expect(rule.resolve('واریز حقوق'), ParsedDirection.credit);
    });

    test('neither keyword falls back', () {
      expect(rule.resolve('تراکنش انجام شد'), ParsedDirection.debit);
    });

    test('both keywords fall back rather than picking the first', () {
      // A transfer notice can carry both words. Whichever-comes-first is a
      // coin flip dressed as a decision.
      expect(rule.resolve('برداشت و واریز'), ParsedDirection.debit);
    });

    test('JSON round-trips', () {
      expect(DirectionRule.fromJson(rule.toJson()), rule);
    });
  });

  group('DirectionRule.fromJson', () {
    test('an unknown kind throws rather than defaulting to debit', () {
      // Defaulting here would book incoming salary as an expense.
      expect(
          () => DirectionRule.fromJson({'kind': 'wat'}), throwsFormatException);
    });

    test('a missing kind throws', () {
      expect(() => DirectionRule.fromJson({}), throwsFormatException);
    });
  });
}
