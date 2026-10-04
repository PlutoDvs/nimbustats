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

  test('every number placeholder says how it is formatted', () {
    // Without a format, gen_l10n interpolates the raw int -- Latin digits in
    // every locale, so a Persian count sits in Latin beside Persian amounts.
    // With one, it goes through the locale's NumberFormat.
    final decoded = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final unformatted = <String>[];
    for (final MapEntry(:key, :value) in decoded.entries) {
      if (!key.startsWith('@') || value is! Map<String, dynamic>) continue;
      final placeholders =
          value['placeholders'] as Map<String, dynamic>? ?? const {};
      for (final MapEntry(key: name, value: meta) in placeholders.entries) {
        final fields = meta as Map<String, dynamic>;
        if (const {'int', 'double', 'num'}.contains(fields['type']) &&
            fields['format'] == null) {
          unformatted.add('${key.substring(1)}.$name');
        }
      }
    }
    expect(unformatted, isEmpty,
        reason: 'add "format": "decimalPattern" to each of these');
  });

  group("counts read in the locale's digits", () {
    List<String> countsIn(String languageCode) {
      final l10n = lookupAppLocalizations(Locale(languageCode));
      return [
        l10n.breakdownTransactionCount(1234),
        l10n.categoryChildCount(1234),
        l10n.pinNameLastMonths(1234),
        l10n.tagMoreCount(1234),
        l10n.tagUsageCount(1234),
        l10n.viewCoversLastMonths(1234),
      ];
    }

    test('Persian digits and separator in Persian', () {
      for (final text in countsIn('fa')) {
        expect(text, contains('۱٬۲۳۴'));
        expect(text, isNot(contains(RegExp('[0-9]'))), reason: text);
      }
    });

    test('Latin digits in English', () {
      for (final text in countsIn('en')) {
        expect(text, contains('1,234'));
      }
    });
  });

  test('no ARB value is left as its English text in the Persian bundle', () {
    // gen_l10n does not fail on an untranslated string, so a key copied across
    // and forgotten looks fine right up until a Farsi user sees English.
    Map<String, String> valuesOf(String path) {
      final decoded =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if (!entry.key.startsWith('@')) entry.key: entry.value as String,
      };
    }

    final en = valuesOf('lib/l10n/app_en.arb');
    final fa = valuesOf('lib/l10n/app_fa.arb');
    // Brand names and format-only strings legitimately match across bundles.
    const allowed = {'appTitle', 'tagMoreCount'};

    final untranslated = <String>[];
    for (final key in en.keys) {
      if (allowed.contains(key)) continue;
      if (en[key] == fa[key]) untranslated.add(key);
    }
    expect(untranslated, isEmpty,
        reason: 'these keys are still English in the fa bundle: $untranslated');
  });
}
