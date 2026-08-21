import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

void main() {
  Widget harness(Locale locale) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            return Column(
              key: const Key('body'),
              children: [Text(l10n.appTitle), Text(l10n.addExpense)],
            );
          },
        ),
      );

  TextDirection directionIn(WidgetTester tester) =>
      Directionality.of(tester.element(find.byKey(const Key('body'))));

  testWidgets('renders English left-to-right', (tester) async {
    await tester.pumpWidget(harness(const Locale('en')));
    expect(directionIn(tester), TextDirection.ltr);
    expect(find.text('NimbuStats'), findsOneWidget);
    expect(find.text('Add expense'), findsOneWidget);
  });

  testWidgets('renders Persian right-to-left', (tester) async {
    await tester.pumpWidget(harness(const Locale('fa')));
    expect(directionIn(tester), TextDirection.rtl);
    // Asserting a translated string, not just the direction: appTitle is the
    // same word in both locales, so direction alone would still pass if `fa`
    // silently fell back to the English bundle.
    expect(find.text('افزودن هزینه'), findsOneWidget);
  });

  test('supported locales are exactly en and fa', () {
    expect(AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
        {'en', 'fa'});
  });

  test('both ARB files define the same keys', () {
    // gen_l10n only warns about untranslated messages, so this is what actually
    // catches a string added to one ARB and forgotten in the other.
    Set<String> keysOf(String path) {
      final decoded =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      return decoded.keys.where((k) => !k.startsWith('@')).toSet();
    }

    final en = keysOf('lib/l10n/app_en.arb');
    final fa = keysOf('lib/l10n/app_fa.arb');
    expect(fa, en, reason: 'fa and en must define the same message keys');
  });
}
