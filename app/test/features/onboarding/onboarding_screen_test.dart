import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

import '../../support/harness.dart';

void main() {
  testWidgets('onboarding is skippable in one tap and still leaves a usable '
      'app', (tester) async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    await pumpApp(tester, database: db, initialLocation: '/onboarding');

    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tx-add-fab')), findsOneWidget);

    // The defaults were already valid before the first question was answered,
    // which is what makes skipping safe rather than merely permitted.
    final settings = await SettingsRepository(db.settingsDao).load();
    expect(settings, AppSettings.defaults.copyWith(onboardingCompleted: true));
    expect(await db.categoriesDao.allLive(), isNotEmpty);
  });

  testWidgets('answering the questions stores those answers instead',
      (tester) async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    await pumpApp(tester, database: db, initialLocation: '/onboarding');

    await tester.tap(find.byKey(const Key('onboarding-currency-USD')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-calendar-gregorian')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-finish')));
    await tester.pumpAndSettle();

    final settings = await SettingsRepository(db.settingsDao).load();
    expect(settings.currency, Currency.usd);
    expect(settings.calendarKind, CalendarKind.gregorian);
    expect(settings.onboardingCompleted, isTrue);
  });

  testWidgets('the tree is seeded in the language just chosen', (tester) async {
    // No locale override: the app runs in the default, Persian, as a real
    // first launch does. Choosing English has to produce English categories,
    // not a Persian tree the user then has to rename one by one.
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    await pumpApp(tester,
        database: db, initialLocation: '/onboarding', locale: null);

    await tester.ensureVisible(find.byKey(const Key('onboarding-locale-en')));
    await tester.tap(find.byKey(const Key('onboarding-locale-en')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-finish')));
    await tester.pumpAndSettle();

    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect((await db.categoriesDao.allLive()).map((c) => c.name),
        contains('Food & drink'));
    expect((await db.categoriesDao.byId(SystemCategoryIds.uncategorized))!.name,
        en.uncategorized);
  });

  testWidgets('the seeded tree includes the reserved Uncategorized row',
      (tester) async {
    // Every transaction has to resolve to a category, so this row existing is
    // a precondition for the add screen working at all.
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    await pumpApp(tester, database: db, initialLocation: '/onboarding');

    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(await db.categoriesDao.byId(SystemCategoryIds.uncategorized),
        isNotNull);
  });

  testWidgets('finishing twice does not seed a second tree', (tester) async {
    // Reachable by navigating back to /onboarding. The emptiness check inside
    // CategorySeeder is what makes it idempotent, and this proves the screen
    // does not work around it.
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);

    await pumpApp(tester, database: db, initialLocation: '/onboarding');
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();
    final first = await db.categoriesDao.allLive();

    await pumpApp(tester, database: db, initialLocation: '/onboarding');
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(await db.categoriesDao.allLive(), hasLength(first.length));
  });
}
