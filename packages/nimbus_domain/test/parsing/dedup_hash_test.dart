import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  final at = DateTime.utc(2026, 8, 28, 10, 0, 15);

  group('dedupHash', () {
    test('is 64 lowercase hex characters', () {
      expect(dedupHash(sender: 'BANK', body: 'kharid 1,250', receivedAt: at),
          matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('is stable for the same inputs', () {
      expect(dedupHash(sender: 'BANK', body: 'x', receivedAt: at),
          dedupHash(sender: 'BANK', body: 'x', receivedAt: at));
    });

    test('a different sender gives a different hash', () {
      expect(dedupHash(sender: 'BANK', body: 'x', receivedAt: at),
          isNot(dedupHash(sender: 'OTHER', body: 'x', receivedAt: at)));
    });

    test('a different body gives a different hash', () {
      expect(dedupHash(sender: 'BANK', body: 'x', receivedAt: at),
          isNot(dedupHash(sender: 'BANK', body: 'y', receivedAt: at)));
    });

    test('normalization is inside the hash', () {
      // The same message re-delivered with Persian digits or a stray bidi
      // mark must dedup, or a carrier retry becomes a second expense.
      expect(
        dedupHash(sender: 'BANK', body: '1,250\u{200F}', receivedAt: at),
        dedupHash(
            sender: 'BANK',
            body: '\u{06F1},\u{06F2}\u{06F5}\u{06F0}',
            receivedAt: at),
      );
    });

    test('the same minute collapses to one hash', () {
      // Documented and deliberate: double-counting money is worse than
      // missing a genuine repeat purchase inside the same minute.
      expect(
        dedupHash(
            sender: 'BANK',
            body: 'x',
            receivedAt: DateTime.utc(2026, 8, 28, 10, 0, 1)),
        dedupHash(
            sender: 'BANK',
            body: 'x',
            receivedAt: DateTime.utc(2026, 8, 28, 10, 0, 59)),
      );
    });

    test('the next minute is a different hash', () {
      expect(
        dedupHash(
            sender: 'BANK',
            body: 'x',
            receivedAt: DateTime.utc(2026, 8, 28, 10, 0, 59)),
        isNot(dedupHash(
            sender: 'BANK',
            body: 'x',
            receivedAt: DateTime.utc(2026, 8, 28, 10, 1, 0))),
      );
    });

    test('the same instant hashes the same in any time zone', () {
      final utc = DateTime.utc(2026, 8, 28, 10, 0, 15);
      expect(dedupHash(sender: 'BANK', body: 'x', receivedAt: utc),
          dedupHash(sender: 'BANK', body: 'x', receivedAt: utc.toLocal()));
    });
  });
}
