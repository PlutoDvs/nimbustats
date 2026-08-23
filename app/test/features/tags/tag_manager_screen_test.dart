import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/provider_retry.dart';
import 'package:nimbustats/features/tags/application/tag_providers.dart';
import 'package:nimbustats/features/tags/data/tag_repository.dart';
import 'package:nimbustats/features/tags/data/tag_tree.dart';
import 'package:nimbustats/features/tags/presentation/widgets/tag_chip_row.dart';
import 'package:nimbustats/features/tags/presentation/widgets/tag_picker_sheet.dart';
import 'package:nimbustats/features/tags/routes.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

import '../../support/harness.dart';

Future<AppDatabase> seededTags() async {
  final db = AppDatabase.openInMemory();
  final repo = TagRepository(db.tagsDao);
  final travel = await repo.findOrCreate('travel');
  await repo.findOrCreate('turkey-2026', parentId: travel.id);
  await repo.findOrCreate('work');
  await repo.recordUsage(travel.id);
  await repo.recordUsage(travel.id);
  return db;
}

Future<void> pumpManager(WidgetTester tester, AppDatabase db) =>
    pumpApp(tester, database: db, initialLocation: tagManagerRoute);

/// A minimal host for widgets that have no screen of their own yet.
///
/// The tag picker is opened from the add-expense screen, which arrives in Task
/// 12. Everything with a route goes through `pumpApp` and the real shell; this
/// exists only for the pieces that do not have one to be reached through.
Future<void> pumpHosted(
  WidgetTester tester,
  AppDatabase db,
  Widget Function(BuildContext context) build,
) async {
  final container = ProviderContainer(
    retry: nimbusNoRetry,
    overrides: [appDatabaseProvider.overrideWithValue(db)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: NimbusTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(body: Builder(builder: build)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the empty state explains what a tag is, not that data is absent',
      (tester) async {
    // Tags are the one Phase 1 concept a first-time user has never configured,
    // and they are not seeded, so this is what they actually see first.
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    await pumpManager(tester, db);

    expect(find.byType(NimbusEmptyState), findsOneWidget);
    expect(find.text('No tags yet'), findsOneWidget);
    expect(
      find.text('Tags group expenses across categories, like travel or gift.'),
      findsOneWidget,
    );

    await tester.tap(find.text('New tag'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tag-name-field')), findsOneWidget);
  });

  testWidgets('loading shows a skeleton list, never a blocking spinner',
      (tester) async {
    final controller = StreamController<List<TagNode>>();
    addTearDown(controller.close);

    await pumpApp(
      tester,
      initialLocation: tagManagerRoute,
      overrides: [tagTreeProvider.overrideWith((ref) => controller.stream)],
    );

    expect(find.byType(NimbusLoadingList), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('error state retries and never shows the raw exception',
      (tester) async {
    await pumpApp(
      tester,
      initialLocation: tagManagerRoute,
      overrides: [
        tagTreeProvider.overrideWith(
            (ref) => Stream<List<TagNode>>.error(Exception('boom'))),
      ],
    );

    expect(find.byType(NimbusErrorState), findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('populated renders a row per tag and shows the usage count',
      (tester) async {
    final db = await seededTags();
    final travel = (await db.tagsDao.allLive())
        .firstWhere((t) => t.name == 'travel');
    await pumpManager(tester, db);

    expect(find.text('travel'), findsOneWidget);
    expect(find.text('turkey-2026'), findsOneWidget);
    expect(find.text('work'), findsOneWidget);
    expect(find.byKey(Key('tag-row-${travel.id}')), findsOneWidget);
    expect(find.text('2 uses'), findsOneWidget);
  });

  testWidgets('rename writes through and the row re-renders', (tester) async {
    final db = await seededTags();
    final work =
        (await db.tagsDao.allLive()).firstWhere((t) => t.name == 'work');
    await pumpManager(tester, db);

    await tester.tap(find.byKey(Key('tag-menu-${work.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('tag-name-field')), 'office');
    await tester.tap(find.byKey(const Key('tag-save')));
    await tester.pumpAndSettle();

    expect((await db.tagsDao.byId(work.id))!.name, 'office');
    expect(find.text('office'), findsOneWidget);
  });

  testWidgets('delete offers undo and no confirmation dialog', (tester) async {
    final db = await seededTags();
    final work =
        (await db.tagsDao.allLive()).firstWhere((t) => t.name == 'work');
    await pumpManager(tester, db);

    await tester.tap(find.byKey(Key('tag-menu-${work.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('work'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('work'), findsOneWidget);
  });

  testWidgets('the picker creates a tag inline and selects it, without the '
      'manager ever being opened', (tester) async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);

    Set<String>? result;
    await pumpHosted(
      tester,
      db,
      (context) => TextButton(
        onPressed: () async {
          result = await showTagPickerSheet(context, selected: const {});
        },
        child: const Text('open'),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('tag-picker-search')), 'brand-new');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tag-create-inline')));
    await tester.pumpAndSettle();

    final created = await db.tagsDao.allLive();
    expect(created.map((t) => t.name), ['brand-new']);

    // Selected immediately: making the user create it and then find it again
    // in the list is the friction this path exists to remove.
    final option = tester.widget<CheckboxListTile>(
        find.byKey(Key('tag-option-${created.single.id}')));
    expect(option.value, isTrue);

    await tester.tap(find.byKey(const Key('tag-picker-done')));
    await tester.pumpAndSettle();
    expect(result, {created.single.id});
  });

  testWidgets('the picker will not create a duplicate of an existing tag',
      (tester) async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    await TagRepository(db.tagsDao).findOrCreate('travel');

    await pumpHosted(
      tester,
      db,
      (context) => TextButton(
        onPressed: () => showTagPickerSheet(context, selected: const {}),
        child: const Text('open'),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('tag-picker-search')), 'Travel');
    await tester.pumpAndSettle();

    // An exact match, differing only in case, is already this tag.
    expect(find.byKey(const Key('tag-create-inline')), findsNothing);
  });

  testWidgets('twenty tags render four chips and a remainder, without '
      'overflowing a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    final repo = TagRepository(db.tagsDao);
    for (var i = 0; i < 20; i++) {
      await repo.findOrCreate('tag-number-$i');
    }
    final tags = await db.tagsDao.allLive();

    await pumpHosted(tester, db, (context) => TagChipRow(tags: tags));

    expect(find.byType(TagChip), findsNWidgets(4));
    expect(find.text('+16'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
