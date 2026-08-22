import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/features/settings/application/settings_providers.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_keys.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.openInMemory();
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  test('settings stream reaches the derived providers', () async {
    await container.read(settingsRepositoryProvider).save(
          AppSettings.defaults.copyWith(
            currency: Currency.usd,
            locale: const Locale('en'),
            calendarKind: CalendarKind.gregorian,
            themeMode: ThemeMode.dark,
            firstDayOfWeek: DateTime.monday,
          ),
        );

    // Hold a listener so the stream stays subscribed while it resolves.
    final sub = container.listen(settingsProvider, (_, __) {});
    addTearDown(sub.close);
    await container.read(settingsProvider.future);

    expect(container.read(currencyProvider), Currency.usd);
    expect(container.read(localeProvider), const Locale('en'));
    expect(container.read(calendarProvider), isA<GregorianCalendar>());
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(container.read(firstDayOfWeekProvider), DateTime.monday);
    expect(container.read(moneyFormatterProvider).currency, Currency.usd);
    expect(container.read(moneyFormatterProvider).persianDigits, isFalse);
  });

  test('derived providers yield defaults before the first emission', () {
    // The app has to render on the very first frame, before the stream has
    // produced anything. These are the same values a first run would write,
    // so nothing is being papered over.
    expect(container.read(currencyProvider), AppSettings.defaults.currency);
    expect(container.read(localeProvider), AppSettings.defaults.locale);
    expect(container.read(themeModeProvider), AppSettings.defaults.themeMode);
  });

  test('a corrupt row puts the settings provider in error without taking the '
      'app down', () async {
    await db.settingsDao.put(SettingsKeys.themeMode, 'chartreuse');

    final sub = container.listen(settingsProvider, (_, __) {},
        onError: (_, __) {}); // the error is the assertion below, not a crash
    addTearDown(sub.close);
    await pumpEventQueue();

    // Asserted on the provider's state rather than on `.future`, because a
    // stream whose *first* event is an error never completes that future --
    // and the state is what every screen actually reads.
    final state = container.read(settingsProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<SettingsFormatException>());
    // ...while every other screen keeps rendering rather than every one of
    // them crashing over a single bad row.
    expect(container.read(themeModeProvider), AppSettings.defaults.themeMode);
    expect(container.read(currencyProvider), AppSettings.defaults.currency);
  });
}
