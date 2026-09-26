import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/settings/data/settings_keys.dart';
import 'package:nimbustats/features/transactions/application/prediction_providers.dart';
import 'package:nimbustats/features/transactions/data/transaction_draft.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';

import '../../support/harness.dart';

const everything = DateRange(DateKey(20000101), DateKey(20991231));

/// History so the predictor has something to offer.
Future<void> seedRepeatPurchases(
  AppDatabase db, {
  required String categoryId,
  int count = 5,
}) async {
  final repo = TransactionRepository(
    db.transactionsDao,
    db.tagsDao,
    Currency.toman,
  );
  for (var i = 0; i < count; i++) {
    await repo.add(TransactionDraft(
      amount: const Money(45000),
      direction: TxDirection.expense,
      categoryId: categoryId,
      occurredAtUtc: DateTime.now().toUtc().subtract(Duration(days: i)),
    ));
  }
}

void main() {
  group('the golden path', () {
    testWidgets('a repeat purchase takes three taps', (tester) async {
      // The tap count is written down here rather than left to interpretation.
      // Digit entry is data, not navigation, so it is not counted. A future
      // change that adds a required field fails this test, which is the point.
      final db = await pumpApp(tester, seedFirstRun: true);
      await seedRepeatPurchases(db, categoryId: 'seed-food-coffee');
      expect(await db.transactionsDao.pageAfter(range: everything, limit: 50),
          hasLength(5));

      var taps = 0;
      Future<void> tap(Finder finder) async {
        taps++;
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap(find.byKey(const Key('tx-add-fab'))); // 1
      await tester.enterText(
          find.byKey(const Key('tx-amount-field')), '45000');
      await tester.pumpAndSettle();
      await tap(find.byKey(const Key('tx-chip-seed-food-coffee'))); // 2
      await tap(find.byKey(const Key('tx-save'))); // 3

      expect(taps, 3);
      // Counted, not sampled: the seeded history is five rows of the same
      // amount and category, so asserting on the newest row alone would pass
      // even if the save had done nothing at all.
      final saved =
          await db.transactionsDao.pageAfter(range: everything, limit: 50);
      expect(saved, hasLength(6));
      expect(saved.first.amount, const Money(45000));
      expect(saved.first.categoryId, 'seed-food-coffee');
    });

    testWidgets('the keypad opens focused on the amount', (tester) async {
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      final field =
          tester.widget<TextField>(find.byKey(const Key('tx-amount-field')));
      expect(field.autofocus, isTrue);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.keyboardType, TextInputType.number);
    });

    testWidgets('amount is the only required field', (tester) async {
      final db =
          await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '1000');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();

      final saved =
          await db.transactionsDao.pageAfter(range: everything, limit: 5);
      expect(saved, hasLength(1));
      expect(saved.single.categoryId, SystemCategoryIds.uncategorized,
          reason: 'no category chosen must still produce a real row, because '
              'every chart depends on category_id being non-null');
      expect(saved.single.note, isNull);
      expect(saved.single.paymentMethodId, isNull);
    });

    testWidgets('save shows no spinner', (tester) async {
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '1000');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pump(); // one frame, mid-save
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('save fires a haptic', (tester) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments.toString());
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '1000');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();
      expect(haptics, isNotEmpty);
    });
  });

  group('the amount field', () {
    testWidgets('accepts Persian digits', (tester) async {
      // A user typing ۱۲۳۴۵ must not produce a parse error.
      final db = await pumpApp(
        tester,
        seedFirstRun: true,
        initialLocation: '/add',
        locale: const Locale('fa'),
      );
      await tester.enterText(
          find.byKey(const Key('tx-amount-field')), '۱۲۳۴۵');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();

      final saved =
          await db.transactionsDao.pageAfter(range: everything, limit: 5);
      expect(saved.single.amount, const Money(12345));
    });

    testWidgets('renders grouped digits in the active locale', (tester) async {
      await pumpApp(
        tester,
        seedFirstRun: true,
        initialLocation: '/add',
        locale: const Locale('fa'),
      );
      await tester.enterText(
          find.byKey(const Key('tx-amount-field')), '1234567');
      await tester.pump();
      expect(find.text('۱٬۲۳۴٬۵۶۷'), findsOneWidget);
    });

    testWidgets('a nine-digit Toman amount does not overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await pumpApp(
        tester,
        seedFirstRun: true,
        initialLocation: '/add',
        locale: const Locale('fa'),
      );
      await tester.enterText(
          find.byKey(const Key('tx-amount-field')), '999999999');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('refuses to save a malformed amount and says so',
        (tester) async {
      final db =
          await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      await tester.enterText(
          find.byKey(const Key('tx-amount-field')), '1.2.3');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tx-amount-error')), findsOneWidget);
      expect(await db.transactionsDao.pageAfter(range: everything, limit: 5),
          isEmpty);
    });

    testWidgets('an empty amount cannot be saved', (tester) async {
      final db =
          await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();
      expect(await db.transactionsDao.pageAfter(range: everything, limit: 5),
          isEmpty);
    });

    testWidgets('a dollar amount can be typed one key at a time',
        (tester) async {
      // Found on a device. "5" was redrawn as "5.00" mid-keystroke with the
      // caret at the end, so the next "0" landed after the cents and $50
      // could not be typed without moving the caret by hand. enterText sets
      // the whole string at once, so each key is sent as its own edit, the
      // way a keyboard delivers them.
      final db = AppDatabase.openInMemory();
      addTearDown(db.close);
      // The device's settings: dollars, in English (which is also what gives
      // Latin digits -- digit style follows the stored locale).
      await db.settingsDao.put(SettingsKeys.currencyCode, Currency.usd.code);
      await db.settingsDao.put(SettingsKeys.localeCode, 'en');
      await pumpApp(tester,
          database: db, seedFirstRun: true, initialLocation: '/add');

      final field = find.byKey(const Key('tx-amount-field'));
      String shown() => tester.widget<TextField>(field).controller!.text;
      for (final key in ['5', '0']) {
        await tester.enterText(field, shown() + key);
        await tester.pump();
      }
      expect(shown(), '50');

      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();
      final saved =
          await db.transactionsDao.pageAfter(range: everything, limit: 5);
      expect(saved.single.amount, const Money(5000));
    });

    testWidgets('a zero amount cannot be saved', (tester) async {
      // Parses fine, means nothing. Without this it would land as a real row
      // and quietly skew every average the app computes.
      final db =
          await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '0');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tx-amount-error')), findsOneWidget);
      expect(await db.transactionsDao.pageAfter(range: everything, limit: 5),
          isEmpty);
    });
  });

  group('layout and reachability', () {
    testWidgets('save sits in the bottom third of the screen', (tester) async {
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      final saveCentre = tester.getCenter(find.byKey(const Key('tx-save')));
      final height =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(saveCentre.dy, greaterThan(height * 2 / 3),
          reason: 'primary actions must stay within one-handed reach');
    });

    testWidgets('save stays above the keyboard', (tester) async {
      // Found on a device. The keypad opens with the screen, and it covered
      // Save: the three-tap path became four, with a tap spent closing the
      // keyboard. A test without a keyboard cannot see that, so this one
      // gives the view one, about the share of the screen the device's
      // numeric keypad takes.
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      final dpr = tester.view.devicePixelRatio;
      const keyboard = 250.0;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard * dpr);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      final height = tester.view.physicalSize.height / dpr;
      final save = tester.getRect(find.byKey(const Key('tx-save')));
      expect(save.bottom, lessThanOrEqualTo(height - keyboard),
          reason: 'Save must not sit under the keyboard');
      expect(save.top, greaterThanOrEqualTo(0));
    });

    testWidgets('category chips arriving late do not move the amount field',
        (tester) async {
      // The predictions are held open deliberately. Measuring across a route
      // transition instead would have moved the field for reasons that have
      // nothing to do with chips, and passed or failed for the wrong reason.
      final completer = Completer<CategoryPredictor>();
      await pumpApp(
        tester,
        seedFirstRun: true,
        initialLocation: '/add',
        overrides: [
          categoryPredictorProvider.overrideWith((ref) => completer.future),
        ],
      );

      final before = tester.getRect(find.byKey(const Key('tx-amount-field')));
      expect(find.byKey(const Key('tx-chip-seed-food-coffee')), findsNothing);

      completer.complete(MruFrequencyCategoryPredictor([
        for (var i = 0; i < 5; i++)
          CategoryObservation(
            categoryId: 'seed-food-coffee',
            occurredAt: DateTime.now().subtract(Duration(days: i)),
          ),
      ]));
      await tester.pumpAndSettle();

      // The chips really did arrive, so the comparison below means something.
      expect(find.byKey(const Key('tx-chip-seed-food-coffee')), findsOneWidget);
      final after = tester.getRect(find.byKey(const Key('tx-amount-field')));
      expect(after, before,
          reason: 'the chip row reserves its height so the keypad target does '
              'not jump under the user thumb');
    });

    testWidgets('necessity and satisfaction are absent from the add screen',
        (tester) async {
      // Deliberately absent: extra taps in the add path are what kill daily
      // tracking. They belong on the edit screen only.
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      expect(find.byKey(const Key('tx-necessity')), findsNothing);
      expect(find.byKey(const Key('tx-satisfaction')), findsNothing);
    });

    testWidgets('renders right-to-left with the amount reading correctly',
        (tester) async {
      await pumpApp(
        tester,
        seedFirstRun: true,
        initialLocation: '/add',
        locale: const Locale('fa'),
      );
      expect(tester.takeException(), isNull);
      final direction = Directionality.of(
          tester.element(find.byKey(const Key('tx-amount-field'))));
      expect(direction, TextDirection.rtl);
    });

    testWidgets('the Uncategorized row is never offered as a chip',
        (tester) async {
      // It is where uncategorised spending lands, not something anyone picks
      // on purpose -- offering it would make Phase 2's review queue meaningless.
      final db = await pumpApp(tester, seedFirstRun: true);
      await seedRepeatPurchases(
        db,
        categoryId: SystemCategoryIds.uncategorized,
        count: 8,
      );
      await tester.tap(find.byKey(const Key('tx-add-fab')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('tx-chip-${SystemCategoryIds.uncategorized}')),
        findsNothing,
      );
    });
  });
}
