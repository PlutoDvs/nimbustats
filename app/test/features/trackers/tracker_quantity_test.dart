import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_draft.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late TrackerRepository repo;
  late Tracker w;

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    repo = repositoryFor(db, fake);
  });
  tearDown(() => db.close());

  Future<void> openTab(WidgetTester tester, {Locale locale = const Locale('en')}) =>
      pumpApp(tester,
          database: db,
          initialLocation: trackersRoute,
          locale: locale,
          overrides: trackerOverrides(fake));

  Finder action() => find.byKey(Key('tracker-action-${w.id}'));
  String total(WidgetTester tester) =>
      textIn(tester, Key('tracker-total-${w.id}'));

  Future<void> logOther(WidgetTester tester, String typed) async {
    await tester.longPress(action());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tracker-amount-field')), typed);
    await tester.tap(find.byKey(const Key('tracker-amount-log')));
    await tester.pumpAndSettle();
  }

  group('in English', () {
    setUp(() async {
      await useEnglishDigits(db);
      w = await repo.create(water);
    });

    testWidgets('one tap logs the per-tap amount', (tester) async {
      await openTab(tester);
      expect(
          find.descendant(of: action(), matching: find.text('+0.25')),
          findsOneWidget);

      await tester.tap(action());
      await tester.pumpAndSettle();
      await tester.tap(action());
      await tester.pumpAndSettle();

      expect(total(tester), '0.5 L today');
      expect(find.text('Water · 0.5 L today'), findsOneWidget);
    });

    testWidgets('a quantity tap fires a light haptic', (tester) async {
      final haptics = captureHaptics(tester);
      await openTab(tester);
      await tester.tap(action());
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('a long-press logs another amount', (tester) async {
      await openTab(tester);
      await logOther(tester, '1.5');
      expect(total(tester), '1.5 L today');
    });

    testWidgets('the sheet reads Persian digits and the Persian decimal point',
        (tester) async {
      await openTab(tester);
      await logOther(tester, '۱٫۵');
      expect(total(tester), '1.5 L today');
    });

    testWidgets('an amount of zero is refused in the sheet; nothing is logged',
        (tester) async {
      await openTab(tester);
      await logOther(tester, '0');

      expect(find.text('Enter an amount above zero'), findsOneWidget);
      expect(find.byKey(const Key('tracker-amount-field')), findsOneWidget);
      expect((await repo.entriesPage(w.id)).items, isEmpty);
    });

    testWidgets("undo removes the custom amount it logged", (tester) async {
      await openTab(tester);
      await tester.tap(action());
      await tester.pumpAndSettle();
      await logOther(tester, '1.5');
      expect(find.text('Water · 1.75 L today'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(total(tester), '0.25 L today');
    });

    testWidgets('the long-press is announced, with what it does',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await openTab(tester);
      expect(
        tester.getSemantics(action()),
        isSemantics(
          label: 'Add 0.25 L to Water',
          isButton: true,
          hasTapAction: true,
          hasLongPressAction: true,
          onLongPressHint: 'Log another amount',
        ),
      );
      semantics.dispose();
    });
  });

  testWidgets('Persian digits and unit in Persian', (tester) async {
    w = await repo.create(const TrackerDraft(
        name: 'آب',
        iconKey: 'water_drop',
        color: 0xFF1565C0,
        type: TrackerType.quantity,
        unit: 'لیتر',
        perTapValue: 0.25));
    await openTab(tester, locale: const Locale('fa'));

    await tester.tap(action());
    await tester.pumpAndSettle();

    expect(total(tester), 'امروز ۰٫۲۵ لیتر');
    expect(find.descendant(of: action(), matching: find.text('+۰٫۲۵')),
        findsOneWidget);
  });
}
