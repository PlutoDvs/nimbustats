import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('MessageTokenizer', () {
    test('each word is its own token so a merchant can be tapped', () {
      // If consecutive text collapsed into one token, the user could never
      // mark just the merchant inside a longer sentence.
      final tokens = MessageTokenizer.tokenize('kharid az forushgah refah');
      expect(tokens.where((t) => t.type == TokenType.word).map((t) => t.text),
          ['kharid', 'az', 'forushgah', 'refah']);
    });

    test('whitespace is its own token kind', () {
      final tokens = MessageTokenizer.tokenize('a b');
      expect(tokens.map((t) => t.type),
          [TokenType.word, TokenType.whitespace, TokenType.word]);
    });

    test('an amount keeps its separators inside one number token', () {
      final tokens = MessageTokenizer.tokenize('mablagh 1,250,000 rial');
      expect(tokens.where((t) => t.type == TokenType.number).map((t) => t.text),
          ['1,250,000']);
    });

    test('a Jalali date is one date-like token, not three numbers', () {
      final tokens = MessageTokenizer.tokenize('tarikh 1403/05/12');
      expect(
          tokens.where((t) => t.type == TokenType.dateLike).map((t) => t.text),
          ['1403/05/12']);
      expect(tokens.where((t) => t.type == TokenType.number), isEmpty);
    });

    test('an ISO date is date-like too', () {
      final tokens = MessageTokenizer.tokenize('on 2026-08-28 ok');
      expect(
          tokens.where((t) => t.type == TokenType.dateLike).map((t) => t.text),
          ['2026-08-28']);
    });

    test('a bare digit is a number token', () {
      final tokens = MessageTokenizer.tokenize('card 7');
      expect(tokens.last.type, TokenType.number);
      expect(tokens.last.text, '7');
    });

    test('a trailing sentence period is its own word token', () {
      // The amount parser must not inherit a dangling separator to guess at.
      final tokens = MessageTokenizer.tokenize('total 1,250.');
      expect(tokens.map((t) => '${t.type.name}:${t.text}'),
          ['word:total', 'whitespace: ', 'number:1,250', 'word:.']);
    });

    test('concatenating every token reproduces the input exactly', () {
      const input = 'kharid 1,250,000 R az forushgah 1403/05/12 karp 6037';
      expect(MessageTokenizer.tokenize(input).map((t) => t.text).join(), input);
    });

    test('offsets index back into the input', () {
      const input = 'kharid 1,250 az X';
      for (final token in MessageTokenizer.tokenize(input)) {
        expect(input.substring(token.start, token.end), token.text);
      }
    });

    test('an empty message produces no tokens', () {
      expect(MessageTokenizer.tokenize(''), isEmpty);
    });
  });
}
