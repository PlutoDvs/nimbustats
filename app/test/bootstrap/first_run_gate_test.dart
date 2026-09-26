import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/transactions/routes.dart';

import '../support/harness.dart';

const _everything = DateRange(DateKey(20000101), DateKey(20991231));

/// The first-run gate: nothing past onboarding works until the category tree
/// exists, because every transaction points into it.
///
/// Found on a real device, not by a test: a fresh install opened on the list,
/// onboarding never ran, and every save failed its foreign key against a
/// category table with no rows. Every test here runs the real gate against a
/// database the way a first launch finds it.
void main() {
  Finder onboarding() => find.byKey(const Key('onboarding-finish'));

  testWidgets('a fresh install opens on onboarding, not the list',
      (tester) async {
    await pumpApp(tester, realFirstRunGate: true);

    expect(onboarding(), findsOneWidget);
    expect(find.byKey(const Key('tx-add-fab')), findsNothing);
  });

  testWidgets('a deep link on a fresh install still goes through onboarding',
      (tester) async {
    // Phase 6's home-screen widget opens the add screen directly. On an
    // install that has never been set up, that screen can only fail.
    await pumpApp(tester,
        realFirstRunGate: true, initialLocation: addTransactionRoute);

    expect(onboarding(), findsOneWidget);
    expect(find.byKey(const Key('tx-save')), findsNothing);
  });

  testWidgets('after onboarding, the first expense saves', (tester) async {
    // The device failure end to end: no category is picked, so the draft
    // falls back to Uncategorized -- the row onboarding creates.
    final db = await pumpApp(tester, realFirstRunGate: true);

    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tx-add-fab')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tx-amount-field')), '45000');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tx-save')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final saved =
        await db.transactionsDao.pageAfter(range: _everything, limit: 10);
    expect(saved, hasLength(1));
    expect(saved.single.categoryId, SystemCategoryIds.uncategorized);
  });

  testWidgets('a first run whose seeding failed is offered again next launch',
      (tester) async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    // A write failure part-way through seeding, injected where SQLite itself
    // would raise one.
    await db.customStatement(
        'CREATE TEMP TRIGGER fail_seed BEFORE INSERT ON categories '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END");

    await pumpApp(tester, database: db, realFirstRunGate: true);
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();
    expect(find.byType(NimbusErrorState), findsOneWidget);

    // The settings were saved before the seed failed. The gate must not take
    // that as "done": the next launch has to land on onboarding again rather
    // than on a list whose every save would fail.
    await pumpApp(tester, database: db, realFirstRunGate: true);
    expect(onboarding(), findsOneWidget);
  });

  testWidgets('an install that has been through first run opens on the list',
      (tester) async {
    await pumpApp(tester, seedFirstRun: true);

    expect(find.byKey(const Key('tx-add-fab')), findsOneWidget);
    expect(onboarding(), findsNothing);
  });
}
