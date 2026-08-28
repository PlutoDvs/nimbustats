import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

/// A synthetic Persian purchase SMS. Not a real bank's wording.
const purchaseSample = 'بانک نمونه\nخرید از فروشگاه رفاه\n'
    'مبلغ ۱,۲۵۰,۰۰۰ ریال\nمانده ۵,۰۰۰,۰۰۰\nتاریخ ۱۴۰۳/۰۵/۱۲';

/// Builds the purchase template the way the teach flow would. Indices are
/// looked up by content rather than hardcoded, so a reworded sample fails
/// loudly here instead of silently tagging the wrong tokens.
GeneratedTemplate buildPurchaseTemplate() {
  final tokens =
      MessageTokenizer.tokenize(MessageNormalizer.normalize(purchaseSample));

  final merchantStart = tokens.indexWhere(
      (t) => t.type == TokenType.word && t.text == 'فروشگاه');
  final amountIndex = tokens.indexWhere((t) => t.type == TokenType.number);
  final dateIndex = tokens.indexWhere((t) => t.type == TokenType.dateLike);
  expect([merchantStart, amountIndex, dateIndex], everyElement(isNonNegative));

  return RegexGenerator.generate(
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
}

void main() {
  group('RegexGenerator', () {
    test('the generated regex matches its own sample and captures each role',
        () {
      final template = buildPurchaseTemplate();
      final match = RegExp(template.regex)
          .firstMatch(MessageNormalizer.normalize(purchaseSample));
      expect(match, isNotNull);
      expect(match!.namedGroup('merchant'), 'فروشگاه رفاه');
      expect(match.namedGroup('amount'), '1,250,000');
      expect(match.namedGroup('date'), '1403/05/12');
    });

    test('an unassigned number is tolerant, not baked in', () {
      // The balance was 5,000,000 in the sample. A template that only
      // matches that balance is worthless after the next purchase.
      final template = buildPurchaseTemplate();
      final other = MessageNormalizer.normalize(
          'بانک نمونه خرید از قهوه ونک مبلغ ۹۸,۷۶۵ ریال '
          'مانده ۱,۱۱۱ تاریخ ۱۴۰۳/۰۶/۰۱');
      final match = RegExp(template.regex).firstMatch(other);
      expect(match, isNotNull);
      expect(match!.namedGroup('amount'), '98,765');
      expect(match.namedGroup('merchant'), 'قهوه ونک');
    });

    test('it does NOT match an OTP from the same sender', () {
      // The single most important assertion in this file. A regex that turns
      // an OTP into a 12,345-Toman expense is worse than one that matches
      // nothing at all.
      final template = buildPurchaseTemplate();
      final otp = MessageNormalizer.normalize('بانک نمونه رمز پویا ۱۲۳۴۵');
      expect(RegExp(template.regex).hasMatch(otp), isFalse);
    });

    test('it does NOT match a promotional message', () {
      final template = buildPurchaseTemplate();
      final promo = MessageNormalizer.normalize(
          'بانک نمونه وام ۵۰۰,۰۰۰,۰۰۰ ریالی ویژه مشتریان');
      expect(RegExp(template.regex).hasMatch(promo), isFalse);
    });

    test('trailing text breaks the anchor', () {
      final template = buildPurchaseTemplate();
      final withTail = '${MessageNormalizer.normalize(purchaseSample)} tabligh';
      expect(RegExp(template.regex).hasMatch(withTail), isFalse);
    });

    test('variable whitespace is tolerated', () {
      final tokens = MessageTokenizer.tokenize('total 1,250 ok');
      final template = RegexGenerator.generate(
          tokens: tokens,
          assignments: const [RoleAssignment.single(2, FieldRole.amount)]);
      expect(RegExp(template.regex).hasMatch('total   1,250    ok'), isTrue);
    });

    test('literal punctuation is escaped, not treated as a metacharacter', () {
      final tokens = MessageTokenizer.tokenize('a.b 5 c');
      final template = RegexGenerator.generate(
          tokens: tokens,
          assignments: const [RoleAssignment.single(2, FieldRole.amount)]);
      expect(RegExp(template.regex).hasMatch('a.b 5 c'), isTrue);
      expect(RegExp(template.regex).hasMatch('axb 5 c'), isFalse);
    });

    test('the field map reports exactly the assigned roles', () {
      final template = buildPurchaseTemplate();
      expect(template.fieldMap.roles,
          {FieldRole.merchant, FieldRole.amount, FieldRole.date});
      expect(template.fieldMap.has(FieldRole.balance), isFalse);
    });

    test('a template with no amount is rejected', () {
      final tokens = MessageTokenizer.tokenize('kharid 1,250 rial');
      expect(
          () => RegexGenerator.generate(
              tokens: tokens,
              assignments: const [
                RoleAssignment.single(0, FieldRole.merchant)
              ]),
          throwsArgumentError);
    });

    test('the same role twice is rejected', () {
      final tokens = MessageTokenizer.tokenize('kharid 1,250 rial');
      expect(
          () => RegexGenerator.generate(tokens: tokens, assignments: const [
                RoleAssignment.single(2, FieldRole.amount),
                RoleAssignment.single(0, FieldRole.amount),
              ]),
          throwsArgumentError);
    });

    test('an out-of-range token index is rejected', () {
      final tokens = MessageTokenizer.tokenize('kharid 1,250 rial');
      expect(
          () => RegexGenerator.generate(tokens: tokens, assignments: const [
                RoleAssignment.single(2, FieldRole.amount),
                RoleAssignment.single(99, FieldRole.merchant),
              ]),
          throwsArgumentError);
    });

    test('overlapping ranges are rejected', () {
      final tokens = MessageTokenizer.tokenize('kharid 1,250 rial');
      expect(
          () => RegexGenerator.generate(tokens: tokens, assignments: const [
                RoleAssignment.single(2, FieldRole.amount),
                RoleAssignment(
                    startIndex: 1, endIndex: 3, role: FieldRole.merchant),
              ]),
          throwsArgumentError);
    });

    test('a template with no literal anchor is rejected', () {
      // Every token assigned or tolerant means a regex that matches nearly
      // any message of that shape. Refuse to build it.
      final tokens = MessageTokenizer.tokenize('1,250');
      expect(
          () => RegexGenerator.generate(
              tokens: tokens,
              assignments: const [RoleAssignment.single(0, FieldRole.amount)]),
          throwsArgumentError);
    });
  });
}
