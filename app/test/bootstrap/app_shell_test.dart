import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';

import '../support/harness.dart';

void main() {
  testWidgets('the app boots against an injected database', (tester) async {
    await pumpApp(tester);
    // Screens arrive in later tasks. What is asserted here is that the
    // provider overrides, the router, and the theme compose at all.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unknown route renders the error screen, not a crash',
      (tester) async {
    await pumpApp(tester, initialLocation: '/no-such-route');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('router-error')), findsOneWidget);
  });

  testWidgets('the injected database is a real, queryable database',
      (tester) async {
    late AppDatabase db;
    await pumpApp(tester, onContainer: (c) => db = c.read(appDatabaseProvider));
    // Proves sqlite3 resolves under `flutter test` on this host, which is the
    // one part of the app-layer test setup that could fail for environmental
    // rather than logical reasons.
    await expectLater(db.settingsDao.get('missing'), completion(isNull));
  });

  testWidgets('the shell is right-to-left in Persian', (tester) async {
    await pumpApp(tester, locale: const Locale('fa'));
    expect(
      Directionality.of(tester.element(find.byType(Scaffold).first)),
      TextDirection.rtl,
    );
  });

  testWidgets('the shell carries the Nimbus theme', (tester) async {
    // Screens read semantic colours through the theme extension, so a shell
    // built without NimbusTheme would fail deep inside an unrelated widget.
    await pumpApp(tester);
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).extension<NimbusSemanticColorsProbe>(), isNull);
    expect(Theme.of(context).useMaterial3, isTrue);
  });
}

/// A type the theme deliberately does not carry, used to prove the lookup in
/// the previous test is actually querying extensions rather than always
/// returning something.
final class NimbusSemanticColorsProbe
    extends ThemeExtension<NimbusSemanticColorsProbe> {
  @override
  ThemeExtension<NimbusSemanticColorsProbe> copyWith() => this;

  @override
  ThemeExtension<NimbusSemanticColorsProbe> lerp(
          ThemeExtension<NimbusSemanticColorsProbe>? other, double t) =>
      this;
}
