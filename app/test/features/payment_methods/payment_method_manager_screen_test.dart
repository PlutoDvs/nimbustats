import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbustats/features/payment_methods/application/payment_method_providers.dart';
import 'package:nimbustats/features/payment_methods/data/payment_method_repository.dart';
import 'package:nimbustats/features/payment_methods/routes.dart';

import '../../support/harness.dart';

Future<AppDatabase> seededMethods() async {
  final db = AppDatabase.openInMemory();
  final repo = PaymentMethodRepository(db.paymentMethodsDao);
  await repo.create(name: 'Cash', kind: PaymentMethodKind.cash);
  await repo.create(
      name: 'Blue card', kind: PaymentMethodKind.card, last4: '1234');
  return db;
}

Future<void> pumpManager(WidgetTester tester, AppDatabase db) =>
    pumpApp(tester, database: db, initialLocation: paymentMethodManagerRoute);

void main() {
  testWidgets('loading shows a skeleton list, never a blocking spinner',
      (tester) async {
    final controller = StreamController<List<PaymentMethod>>();
    addTearDown(controller.close);

    await pumpApp(
      tester,
      initialLocation: paymentMethodManagerRoute,
      overrides: [
        paymentMethodsProvider.overrideWith((ref) => controller.stream),
      ],
    );

    expect(find.byType(NimbusLoadingList), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the empty state says what a payment method is for',
      (tester) async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    await pumpManager(tester, db);

    expect(find.byType(NimbusEmptyState), findsOneWidget);
    expect(find.text('No payment methods'), findsOneWidget);
    expect(
      find.text('Add cash, a card, or a bank account to see where your money '
          'goes out from.'),
      findsOneWidget,
    );

    await tester.tap(find.text('New payment method'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pay-name-field')), findsOneWidget);
  });

  testWidgets('error state retries and never shows the raw exception',
      (tester) async {
    await pumpApp(
      tester,
      initialLocation: paymentMethodManagerRoute,
      overrides: [
        paymentMethodsProvider.overrideWith(
            (ref) => Stream<List<PaymentMethod>>.error(Exception('boom'))),
      ],
    );

    expect(find.byType(NimbusErrorState), findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('populated shows the kind and the masked last four',
      (tester) async {
    final db = await seededMethods();
    await pumpManager(tester, db);

    expect(find.text('Cash'), findsWidgets);
    expect(find.text('Blue card'), findsOneWidget);
    expect(find.text('•••• 1234'), findsOneWidget);
  });

  testWidgets('creating a method with Persian digits stores Latin ones',
      (tester) async {
    final db = await seededMethods();
    await pumpManager(tester, db);

    await tester.tap(find.byKey(const Key('pay-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('pay-name-field')), 'Melli card');
    await tester.enterText(find.byKey(const Key('pay-last4-field')), '۹۸۷۶');
    await tester.tap(find.byKey(const Key('pay-save')));
    await tester.pumpAndSettle();

    final created = (await db.paymentMethodsDao.allLive())
        .firstWhere((m) => m.name == 'Melli card');
    expect(created.last4, '9876');
  });

  testWidgets('a short last4 is a field error, not a thrown exception',
      (tester) async {
    // The repository throws, which is right for a programming error and wrong
    // as a way to tell someone they mistyped four digits.
    final db = await seededMethods();
    await pumpManager(tester, db);

    await tester.tap(find.byKey(const Key('pay-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pay-name-field')), 'Oops');
    await tester.enterText(find.byKey(const Key('pay-last4-field')), '12');
    await tester.tap(find.byKey(const Key('pay-save')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Enter exactly four digits'), findsOneWidget);
    expect(await db.paymentMethodsDao.allLive(), hasLength(2));
  });

  testWidgets('delete offers undo and no confirmation dialog', (tester) async {
    final db = await seededMethods();
    final card = (await db.paymentMethodsDao.allLive())
        .firstWhere((m) => m.name == 'Blue card');
    await pumpManager(tester, db);

    await tester.tap(find.byKey(Key('pay-menu-${card.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byKey(Key('pay-row-${card.id}')), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('pay-row-${card.id}')), findsOneWidget);
  });

  testWidgets('archiving keeps the row in the manager and out of the picker',
      (tester) async {
    final db = await seededMethods();
    final card = (await db.paymentMethodsDao.allLive())
        .firstWhere((m) => m.name == 'Blue card');
    await pumpManager(tester, db);

    await tester.tap(find.byKey(Key('pay-menu-${card.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('pay-row-${card.id}')), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);

    final pickable =
        await PaymentMethodRepository(db.paymentMethodsDao).pickable();
    expect(pickable.map((m) => m.id), isNot(contains(card.id)));
  });
}
