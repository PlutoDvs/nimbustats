import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

/// Invisible characters are written as escapes so a reader can see what a
/// failing expectation is actually about.
const rlm = '\u{200F}';
const lrm = '\u{200E}';
const bom = '\u{FEFF}';

void main() {
  group('MessageNormalizer', () {
    test('Persian digits become Latin', () {
      expect(MessageNormalizer.normalize('\u{06F1}\u{06F2}\u{06F3}'), '123');
    });

    test('Arabic-Indic digits become Latin', () {
      expect(MessageNormalizer.normalize('\u{0665}\u{0660}\u{0660}'), '500');
    });

    test('Arabic kaf and yeh fold to their Persian forms', () {
      // The same bank name typed on an Arabic keyboard must normalize to the
      // same bytes as one typed on a Persian keyboard, or the user needs one
      // template per keyboard layout.
      const arabic = 'بانك ملي';
      const persian = 'بانک ملی';
      expect(MessageNormalizer.normalize(arabic), persian);
      expect(MessageNormalizer.normalize(persian), persian);
    });

    test('bidi controls are removed, not turned into spaces', () {
      // A stray space here would break an otherwise-correct template, and
      // these marks are invisible in every log you would debug it with.
      expect(MessageNormalizer.normalize('${rlm}123$lrm,456$bom'), '123,456');
    });

    test('ZWNJ and a real space normalize to the same text', () {
      // Banks spell the same compound word both ways across message
      // revisions. Folding both to a space makes one template cover both.
      expect(
        MessageNormalizer.normalize('خرید\u{200C}اینترنتی'),
        MessageNormalizer.normalize('خرید اینترنتی'),
      );
    });

    test('newlines, tabs and NBSP collapse into single spaces', () {
      expect(MessageNormalizer.normalize('a\n\nb\tc\u{00A0}d'), 'a b c d');
    });

    test('leading and trailing whitespace is trimmed', () {
      expect(MessageNormalizer.normalize('  card 1234  '), 'card 1234');
    });

    test('Arabic numeric separators become their Latin equivalents', () {
      expect(MessageNormalizer.normalize('12\u{066B}50'), '12.50');
      expect(MessageNormalizer.normalize('123\u{066C}456'), '123,456');
    });

    test('normalization is idempotent', () {
      // Templates are generated from normalized text and matched against
      // normalized text. If normalize were not a fixed point, a message could
      // match on capture and fail on re-parse after a bug fix.
      const raw = '  بانك\u{200C}ملي \u{06F1}\u{06F2}\u{06F3}$rlm\nریال ';
      final once = MessageNormalizer.normalize(raw);
      expect(MessageNormalizer.normalize(once), once);
    });

    test('a plain Latin message is returned unchanged', () {
      expect(MessageNormalizer.normalize('Purchase 1,250 card 4321'),
          'Purchase 1,250 card 4321');
    });

    test('a whitespace-only message normalizes to empty', () {
      expect(MessageNormalizer.normalize('   \n\t '), '');
    });
  });
}
