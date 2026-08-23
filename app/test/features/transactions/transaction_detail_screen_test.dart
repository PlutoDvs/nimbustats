import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/tags/data/tag_repository.dart';
import 'package:nimbustats/features/tags/presentation/widgets/tag_chip_row.dart';
import 'package:nimbustats/features/transactions/data/transaction_draft.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';

import '../../support/harness.dart';

Future<AppDatabase> seededDb() async {
  final db = AppDatabase.openInMemory();
  await CategorySeeder(db).seedIfEmpty(
    roots: const [SeedCategoryNode(id: 'seed-food', name: 'Food')],
    uncategorizedName: 'Uncategorized',
  );
  return db;
}

TransactionRepository repoFor(AppDatabase db) =>
    TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman);

Future<Transaction> seedOne(
  AppDatabase db, {
  int amount = 45000,
  List<String> tagIds = const [],
}) =>
    repoFor(db).add(TransactionDraft(
      amount: Money(amount),
      direction: TxDirection.expense,
      categoryId: 'seed-food',
      occurredAtUtc: DateTime.now().toUtc(),
      merchant: 'Cafe Naderi',
      tagIds: tagIds,
    ));

void main() {
  testWidgets('editing an amount writes through the repository',
      (tester) async {
    final db = await seededDb();
    final tx = await seedOne(db);
    await pumpApp(tester, database: db, initialLocation: '/tx/${tx.id}');

    await tester.enterText(
        find.byKey(const Key('tx-amount-field')), '99000');
    await tester.tap(find.byKey(const Key('tx-detail-save')));
    await tester.pumpAndSettle();

    expect((await db.transactionsDao.byId(tx.id))!.amount, const Money(99000));
  });

  testWidgets('necessity and satisfaction are settable here', (tester) async {
    final db = await seededDb();
    final tx = await seedOne(db);
    await pumpApp(tester, database: db, initialLocation: '/tx/${tx.id}');

    await tester.tap(find.byKey(const Key('tx-necessity-avoidable')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tx-satisfaction-regret')));
    await tester.pumpAndSettle();

    final row = (await db.transactionsDao.byId(tx.id))!;
    expect(row.necessity, Necessity.avoidable);
    expect(row.satisfaction, Satisfaction.regret);
  });

  testWidgets('both axes are optional and can be cleared', (tester) async {
    // Phase 3's regret matrix shows unlabelled totals separately rather than
    // dropping them, so "no answer" has to remain expressible.
    final db = await seededDb();
    final tx = await seedOne(db);
    await pumpApp(tester, database: db, initialLocation: '/tx/${tx.id}');

    await tester.tap(find.byKey(const Key('tx-necessity-needed')));
    await tester.pumpAndSettle();
    expect((await db.transactionsDao.byId(tx.id))!.necessity,
        Necessity.needed);

    // Tapping the selected option again deselects it.
    await tester.tap(find.byKey(const Key('tx-necessity-needed')));
    await tester.pumpAndSettle();
    expect((await db.transactionsDao.byId(tx.id))!.necessity, isNull);
  });

  testWidgets('setting one axis does not wipe the other', (tester) async {
    // Both are written by the same statement, so an implementation that read
    // stale state would silently clear whichever one it was not told about.
    final db = await seededDb();
    final tx = await seedOne(db);
    await pumpApp(tester, database: db, initialLocation: '/tx/${tx.id}');

    await tester.tap(find.byKey(const Key('tx-necessity-needed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tx-satisfaction-glad')));
    await tester.pumpAndSettle();

    final row = (await db.transactionsDao.byId(tx.id))!;
    expect(row.necessity, Necessity.needed);
    expect(row.satisfaction, Satisfaction.glad);
  });

  testWidgets('delete is soft, offers undo, and never confirms',
      (tester) async {
    final db = await seededDb();
    final tx = await seedOne(db);
    await pumpApp(tester, database: db, initialLocation: '/tx/${tx.id}');

    await tester.tap(find.byKey(const Key('tx-delete')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect((await db.transactionsDao.byId(tx.id))!.deletedAt, isNotNull);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await db.transactionsDao.byId(tx.id))!.deletedAt, isNull);
  });

  testWidgets('twenty tags collapse to a bounded row', (tester) async {
    final db = await seededDb();
    final tagRepo = TagRepository(db.tagsDao);
    final ids = <String>[];
    for (var i = 0; i < 20; i++) {
      ids.add((await tagRepo.findOrCreate('tag-number-$i')).id);
    }
    final tx = await seedOne(db, tagIds: ids);

    await pumpApp(tester, database: db, initialLocation: '/tx/${tx.id}');

    expect(find.byType(TagChip), findsNWidgets(4));
    expect(find.byKey(const Key('tx-tags-more')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an expense renders in RTL without overflowing', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = await seededDb();
    final tx = await seedOne(db, amount: 999999999);
    await pumpApp(
      tester,
      database: db,
      initialLocation: '/tx/${tx.id}',
      locale: const Locale('fa'),
    );

    expect(tester.takeException(), isNull);
    final direction = Directionality.of(
        tester.element(find.byKey(const Key('tx-amount-field'))));
    expect(direction, TextDirection.rtl);
  });
}
