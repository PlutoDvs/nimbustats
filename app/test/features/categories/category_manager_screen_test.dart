import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbustats/features/categories/application/category_providers.dart';
import 'package:nimbustats/features/categories/data/category_repository.dart';
import 'package:nimbustats/features/categories/data/category_tree.dart';
import 'package:nimbustats/features/categories/routes.dart';

import '../../support/harness.dart';

/// Two roots, one of which has a child, plus the seeded system row.
Future<AppDatabase> seededDatabase() async {
  final db = AppDatabase.openInMemory();
  await CategorySeeder(db).seedIfEmpty(
    roots: const [
      SeedCategoryNode(id: 'food', name: 'Food', children: [
        SeedCategoryNode(id: 'dining', name: 'Dining'),
      ]),
      SeedCategoryNode(id: 'transport', name: 'Transport'),
    ],
    uncategorizedName: 'Uncategorized',
  );
  return db;
}

Future<void> pumpManager(WidgetTester tester, AppDatabase db) =>
    pumpApp(tester, database: db, initialLocation: categoryManagerRoute);

void main() {
  testWidgets('loading shows a skeleton list, never a blocking spinner',
      (tester) async {
    // A stream that never emits: the provider stays in AsyncLoading.
    final controller = StreamController<List<CategoryNode>>();
    addTearDown(controller.close);

    await pumpApp(
      tester,
      initialLocation: categoryManagerRoute,
      overrides: [
        categoryTreeProvider.overrideWith((ref) => controller.stream),
      ],
    );

    expect(find.byType(NimbusLoadingList), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'empty state offers the create action rather than announcing that there '
      'is no data', (tester) async {
    await pumpApp(
      tester,
      initialLocation: categoryManagerRoute,
      overrides: [
        categoryTreeProvider
            .overrideWith((ref) => Stream.value(const <CategoryNode>[])),
      ],
    );

    expect(find.byType(NimbusEmptyState), findsOneWidget);
    expect(find.text('No categories'), findsOneWidget);

    await tester.tap(find.text('New category'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('category-name-field')), findsOneWidget);
  });

  testWidgets('error state retries and never shows the raw exception',
      (tester) async {
    await pumpApp(
      tester,
      initialLocation: categoryManagerRoute,
      overrides: [
        categoryTreeProvider.overrideWith(
            (ref) => Stream<List<CategoryNode>>.error(Exception('boom'))),
      ],
    );

    expect(find.byType(NimbusErrorState), findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('populated renders a row per node with its live child count',
      (tester) async {
    final db = await seededDatabase();
    await pumpManager(tester, db);

    expect(find.byKey(const Key('category-row-food')), findsOneWidget);
    expect(find.byKey(const Key('category-row-dining')), findsOneWidget);
    expect(find.byKey(const Key('category-row-transport')), findsOneWidget);
    expect(
      find.byKey(const Key('category-row-${SystemCategoryIds.uncategorized}')),
      findsOneWidget,
    );
    expect(find.text('1 subcategory'), findsOneWidget);
  });

  testWidgets(
      'indent stops growing after the cap and still fits a narrow RTL screen',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    String? parent;
    for (var level = 0; level < 6; level++) {
      await db.categoriesDao.insertNode(
        id: 'level$level',
        name: 'Level $level',
        parentId: parent,
      );
      parent = 'level$level';
    }

    await pumpApp(
      tester,
      database: db,
      initialLocation: categoryManagerRoute,
      locale: const Locale('fa'),
    );

    final deepest =
        tester.getSize(find.byKey(const Key('category-indent-level5')));
    expect(deepest.width,
        NimbusTokens.indentPerLevel * NimbusTokens.maxTreeIndentDepth);
    // A row that overflows paints an exception rather than failing an
    // assertion, so this is what catches it.
    expect(tester.takeException(), isNull);
  });

  testWidgets('rename writes through and the row re-renders', (tester) async {
    final db = await seededDatabase();
    await pumpManager(tester, db);

    await tester.tap(find.byKey(const Key('category-menu-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('category-name-field')), 'Groceries');
    await tester.tap(find.byKey(const Key('category-save')));
    await tester.pumpAndSettle();

    expect((await db.categoriesDao.byId('food'))!.name, 'Groceries');
    expect(find.text('Groceries'), findsOneWidget);
  });

  testWidgets(
      'an invalid move target is disabled before the drop, not rejected after '
      'it', (tester) async {
    final db = await seededDatabase();
    await pumpManager(tester, db);

    await tester.tap(find.byKey(const Key('category-menu-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to…'));
    await tester.pumpAndSettle();

    bool targetEnabled(String id) =>
        tester.widget<ListTile>(find.byKey(Key('move-target-$id'))).enabled;

    expect(targetEnabled('dining'), isFalse);
    expect(targetEnabled('transport'), isTrue);
    expect(targetEnabled(SystemCategoryIds.uncategorized), isFalse);

    await tester.tap(find.byKey(const Key('move-target-dining')));
    await tester.pumpAndSettle();
    expect((await db.categoriesDao.byId('food'))!.path, '/food/');
  });

  testWidgets(
      'archiving hides the subtree from the picker but keeps it in the manager',
      (tester) async {
    final db = await seededDatabase();
    await pumpManager(tester, db);

    await tester.tap(find.byKey(const Key('category-menu-food')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    final pickable =
        await CategoryRepository(db.categoriesDao).pickableCategories();
    expect(pickable.map((c) => c.id), isNot(contains('food')));
    expect(pickable.map((c) => c.id), isNot(contains('dining')));

    expect(find.byKey(const Key('category-row-food')), findsOneWidget);
    expect(find.text('Archived'), findsWidgets);
  });

  testWidgets('delete offers undo and no confirmation dialog', (tester) async {
    final db = await seededDatabase();
    await pumpManager(tester, db);

    await tester.tap(find.byKey(const Key('category-menu-transport')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byKey(const Key('category-row-transport')), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('category-row-transport')), findsOneWidget);
  });

  testWidgets('the system row offers no rename or delete', (tester) async {
    final db = await seededDatabase();
    await pumpManager(tester, db);

    await tester.tap(find
        .byKey(const Key('category-menu-${SystemCategoryIds.uncategorized}')));
    await tester.pumpAndSettle();

    expect(find.text('Rename'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Archive'), findsNothing);
    expect(find.text('Move to…'), findsNothing);
    // Appearance is the one thing that is safe, so the menu is not empty.
    expect(find.text('Icon'), findsOneWidget);
  });

  testWidgets('a row is an announced, tappable target', (tester) async {
    final db = await seededDatabase();
    await pumpManager(tester, db);

    final data = tester
        .getSemantics(find.byKey(const Key('category-row-food')))
        .getSemanticsData();
    expect(data.label, contains('Food'));
    expect(data.hasAction(SemanticsAction.tap), isTrue);
  });
}
