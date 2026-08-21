import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  test('everything is unlocked under the current source', () {
    final e =
        Entitlements(source: const AlwaysUnlockedSource(), isFoundingUser: false);
    for (final f in Feature.values) {
      expect(e.has(f), isTrue, reason: '$f should be unlocked');
    }
  });

  test('a founding user keeps every feature even under a restrictive source', () {
    final e = Entitlements(
      source: const GrantedSetSource(<Feature>{}),
      isFoundingUser: true,
    );
    for (final f in Feature.values) {
      expect(e.has(f), isTrue, reason: 'founding users are grandfathered');
    }
  });

  test('a non-founding user only gets what the source grants', () {
    final e = Entitlements(
      source: const GrantedSetSource(<Feature>{Feature.cloudBackup}),
      isFoundingUser: false,
    );
    expect(e.has(Feature.cloudBackup), isTrue);
    expect(e.has(Feature.advancedAnalytics), isFalse);
    expect(e.has(Feature.unlimitedTemplates), isFalse);
  });

  test('the unlocked set is shared and cannot be mutated by a caller', () {
    const source = AlwaysUnlockedSource();
    expect(identical(source.granted, const AlwaysUnlockedSource().granted), isTrue,
        reason: 'granted is read on every gate check; do not rebuild it');
    expect(() => source.granted.add(Feature.cloudBackup), throwsUnsupportedError);
  });
}
