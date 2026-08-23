import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/transactions/application/transaction_list_controller.dart';
import 'package:nimbustats/features/transactions/data/transaction_draft.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';
import 'package:nimbustats/features/transactions/presentation/widgets/transaction_row.dart';

import '../../support/harness.dart';

/// A database with just enough of a category tree for rows to resolve, seeded
/// directly so the whole fixture is in place before the screen is pumped once.
Future<AppDatabase> seededDb() async {
  final db = AppDatabase.openInMemory();
  await CategorySeeder(db).seedIfEmpty(
    roots: const [
      SeedCategoryNode(id: 'seed-food', name: 'Food'),
      SeedCategoryNode(id: 'seed-salary', name: 'Salary', kind: 'income'),
    ],
    uncategorizedName: 'Uncategorized',
  );
  return db;
}

TransactionRepository repoFor(AppDatabase db) =>
    TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman);

/// A date [dayOffset] days into the *active* month.
///
/// Derived from the Jalali calendar because that is what the app defaults to,
/// and a Jalali month is not a Gregorian one. Anchoring the fixture to
/// `DateTime.now().month` instead put rows in Mordad while the screen was
/// showing Shahrivar, and every assertion failed for a reason that had nothing
/// to do with the code under test.
DateTime dayInThisMonth(int dayOffset) {
  const calendar = JalaliCalendar();
  final period = calendar.periodContaining(
    DateKey.fromDateTime(DateTime.now()),
    PeriodType.month,
  );
  final start = period.startInclusive.toDateTime();
  return DateTime(start.year, start.month, start.day)
      .add(Duration(days: dayOffset, hours: 12));
}

Future<Transaction> addExpense(
  AppDatabase db, {
  required int amount,
  required int day,
  String category = 'seed-food',
  String? merchant,
  TxDirection direction = TxDirection.expense,
}) =>
    repoFor(db).add(TransactionDraft(
      amount: Money(amount),
      direction: direction,
      categoryId: category,
      occurredAtUtc: dayInThisMonth(day).toUtc(),
      merchant: merchant,
    ));

void main() {
  testWidgets('the empty state points at the add action rather than reading '
      'as a failure', (tester) async {
    final db = await seededDb();
    await pumpApp(tester, database: db);

    expect(find.byType(NimbusEmptyState), findsOneWidget);
    expect(find.text('No transactions yet'), findsOneWidget);

    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tx-amount-field')), findsOneWidget);
  });

  testWidgets('rows are grouped by day with a subtotal per day',
      (tester) async {
    final db = await seededDb();
    for (final amount in [50000, 60000, 40000]) {
      await addExpense(db, amount: amount, day: 2);
    }
    await addExpense(db, amount: 7000, day: 1);

    await pumpApp(tester, database: db);

    final keyB = DateKey.fromDateTime(dayInThisMonth(2)).value;
    final keyA = DateKey.fromDateTime(dayInThisMonth(1)).value;
    expect(find.byKey(Key('day-header-$keyB')), findsOneWidget);
    expect(find.byKey(Key('day-header-$keyA')), findsOneWidget);

    // Persian digits, because the app's default locale is fa and the money
    // formatter follows the settings rather than the widget-tree locale.
    final subtotal =
        tester.widget<Text>(find.byKey(Key('day-subtotal-$keyB')));
    expect(subtotal.data, '۱۵۰٬۰۰۰');
  });

  testWidgets('the month total is a period sum, not a sum of loaded rows',
      (tester) async {
    // 45 rows against a page size of 40. If the header added up what is
    // loaded it would be short by five, and would look right until someone
    // scrolled -- which is exactly why it is a SQL aggregate.
    final db = await seededDb();
    for (var i = 0; i < 45; i++) {
      await addExpense(db, amount: 1000, day: i % 20);
    }

    ProviderContainer? container;
    await pumpApp(tester, database: db, onContainer: (c) => container = c);

    final total = tester.widget<Text>(find.byKey(const Key('tx-month-total')));
    expect(total.data, '۴۵٬۰۰۰');

    // Asserted on the controller, not on rendered widgets: SliverList builds
    // lazily, so counting TransactionRows counts what fits on screen rather
    // than what was loaded.
    final state = container!.read(transactionListControllerProvider).value!;
    expect(state.rowCount, 40);
    expect(state.hasMore, isTrue);
  });

  testWidgets('loading more appends without repeating a row', (tester) async {
    final db = await seededDb();
    for (var i = 0; i < 45; i++) {
      await addExpense(db, amount: 1000 + i, day: i % 20);
    }

    ProviderContainer? container;
    await pumpApp(tester, database: db, onContainer: (c) => container = c);
    // Scrolled rather than tapped: the list auto-loads past 80% of the
    // extent, so the explicit button is gone by the time a scroll reaches it.
    // This exercises the path a user actually takes.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    final state = container!.read(transactionListControllerProvider).value!;
    final ids = state.rows.map((t) => t.id).toList();
    expect(ids, hasLength(45));
    expect(ids.toSet(), hasLength(45), reason: 'no row may appear twice');
    expect(state.hasMore, isFalse);
  });

  testWidgets('income and expense are distinguishable without colour',
      (tester) async {
    // The sign and the icon carry the meaning. Red against green alone fails
    // for roughly one man in twelve.
    final db = await seededDb();
    await addExpense(
      db,
      amount: 5000,
      day: 1,
      category: 'seed-salary',
      direction: TxDirection.income,
    );
    await addExpense(db, amount: 2000, day: 1);

    await pumpApp(tester, database: db);
    expect(find.byKey(const Key('tx-direction-icon-income')), findsOneWidget);
    expect(find.byKey(const Key('tx-direction-icon-expense')), findsOneWidget);
    expect(find.textContaining('+'), findsWidgets);
    expect(find.textContaining('−'), findsWidgets);
  });

  testWidgets('a forty-character merchant ellipsises on one line',
      (tester) async {
    // Never reflow the row height: a list that changes row heights while it
    // loads is unusable at speed.
    final db = await seededDb();
    final tx = await addExpense(
      db,
      amount: 1000,
      day: 1,
      merchant: 'A' * 40,
    );

    await pumpApp(tester, database: db);
    final text = tester.widget<Text>(find.byKey(Key('tx-merchant-${tx.id}')));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search filters the list', (tester) async {
    final db = await seededDb();
    await addExpense(db, amount: 1000, day: 1, merchant: 'Cafe Naderi');
    await addExpense(db, amount: 2000, day: 1, merchant: 'Metro');

    await pumpApp(tester, database: db);
    expect(find.byType(TransactionRow), findsNWidgets(2));

    await tester.enterText(find.byKey(const Key('tx-search')), 'Naderi');
    await tester.pumpAndSettle();
    expect(find.byType(TransactionRow), findsOneWidget);
    expect(find.text('Cafe Naderi'), findsOneWidget);
  });

  testWidgets('a search that matches nothing shows the empty state, not an '
      'error', (tester) async {
    final db = await seededDb();
    await addExpense(db, amount: 1000, day: 1, merchant: 'Metro');

    await pumpApp(tester, database: db);
    await tester.enterText(find.byKey(const Key('tx-search')), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.byType(TransactionRow), findsNothing);
    expect(find.text('No transactions yet'), findsOneWidget);
  });

  testWidgets('the running total follows the period, not the whole database',
      (tester) async {
    // A row in the previous month must not count towards this month's total.
    final db = await seededDb();
    await addExpense(db, amount: 1000, day: 1);
    await repoFor(db).add(TransactionDraft(
      amount: const Money(999999),
      direction: TxDirection.expense,
      categoryId: 'seed-food',
      occurredAtUtc: dayInThisMonth(-40).toUtc(),
    ));

    await pumpApp(tester, database: db);
    final total = tester.widget<Text>(find.byKey(const Key('tx-month-total')));
    expect(total.data, '۱٬۰۰۰');
  });
}
