import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/application/tracker_providers.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late TrackerRepository repo;

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    await useEnglishDigits(db);
    repo = repositoryFor(db, fake);
  });
  tearDown(() => db.close());

  Future<void> openManager(WidgetTester tester) => pumpApp(tester,
      database: db,
      initialLocation: trackerManagerRoute,
      overrides: trackerOverrides(fake));

  Future<List<String>> liveNames(WidgetTester tester) async =>
      [for (final t in await firstOf(tester, repo.watchTrackers())) t.name];

  testWidgets('loading shows a skeleton', (tester) async {
    final never = StreamController<List<Tracker>>();
    addTearDown(never.close);
    await pumpApp(tester, initialLocation: trackerManagerRoute, overrides: [
      ...trackerOverrides(fake),
      trackersProvider.overrideWith((ref) => never.stream),
    ]);
    expect(find.byType(NimbusLoadingList), findsOneWidget);
  });

  testWidgets('the error state retries and hides the raw exception',
      (tester) async {
    await pumpApp(tester, initialLocation: trackerManagerRoute, overrides: [
      ...trackerOverrides(fake),
      archivedTrackersProvider.overrideWith(
          (ref) => Stream<List<Tracker>>.error(Exception('boom'))),
    ]);
    expect(find.byType(NimbusErrorState), findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
  });

  testWidgets('the empty state offers to create a tracker', (tester) async {
    await openManager(tester);
    expect(find.text('No trackers yet'), findsOneWidget);
    await tester.tap(find.text('New tracker'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tracker-name-field')), findsOneWidget);
  });

  testWidgets('creating a counter: name, icon, colour, type', (tester) async {
    await openManager(tester);
    await tester.tap(find.text('New tracker'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('tracker-name-field')), 'Coffee');
    await tapVisible(tester, find.byKey(const Key('icon-option-local_cafe')));
    await tapVisible(tester, find.byKey(const Key('color-option-orange')));
    await tapVisible(tester, find.byKey(const Key('tracker-type-counter')));
    await tester.pump();
    await tapVisible(tester, find.byKey(const Key('tracker-save')));
    await tester.pumpAndSettle();

    final coffee = (await firstOf(tester, repo.watchTrackers())).single;
    expect(coffee.name, 'Coffee');
    expect(coffee.type, TrackerType.counter);
    expect(coffee.iconKey, 'local_cafe');
    expect(coffee.color, NimbusColors.categorySwatches['orange']!.toARGB32());
    expect(find.byKey(Key('tracker-row-${coffee.id}')), findsOneWidget);
  });

  testWidgets('a quantity cannot be saved without an amount per tap',
      (tester) async {
    await openManager(tester);
    await tester.tap(find.text('New tracker'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tracker-name-field')), 'Reading');
    await tapVisible(tester, find.byKey(const Key('tracker-type-quantity')));
    await tester.pump();

    FilledButton save() =>
        tester.widget<FilledButton>(find.byKey(const Key('tracker-save')));
    expect(save().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('tracker-per-tap-field')), '0');
    await tester.pump();
    expect(find.text('Enter an amount above zero'), findsOneWidget);
    expect(save().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('tracker-per-tap-field')), '۱۰');
    await tester.enterText(find.byKey(const Key('tracker-unit-field')), 'pages');
    await tester.pump();
    await tapVisible(tester, find.byKey(const Key('tracker-save')));
    await tester.pumpAndSettle();

    final reading = (await firstOf(tester, repo.watchTrackers())).single;
    expect(reading.perTapValue, 10);
    expect(reading.unit, 'pages');
  });

  testWidgets('editing keeps the type fixed and saves the rest',
      (tester) async {
    final cig = await repo.create(cigarettes);
    await openManager(tester);

    await tester.tap(find.byKey(Key('tracker-row-${cig.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Edit tracker'), findsOneWidget);
    expect(find.byKey(const Key('tracker-type-counter')), findsNothing);
    expect(find.byKey(const Key('tracker-type-fixed')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('tracker-name-field')), 'Smokes');
    await tapVisible(tester, find.byKey(const Key('tracker-save')));
    await tester.pumpAndSettle();

    expect(await liveNames(tester), ['Smokes']);
  });

  testWidgets('archive moves a tracker to the Archived section, undo returns it',
      (tester) async {
    final [cig, g] = await repo.createAll([cigarettes, gym]);
    await openManager(tester);

    await tester.tap(find.byKey(Key('tracker-menu-${cig.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tracker-menu-archive')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('tracker-archived-${cig.id}')), findsOneWidget);
    expect(find.text('Archived Cigarettes'), findsOneWidget);
    expect(await liveNames(tester), ['Gym']);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('tracker-row-${cig.id}')), findsOneWidget);
    expect(await liveNames(tester), ['Cigarettes', 'Gym']);
    expect(find.byKey(Key('tracker-row-${g.id}')), findsOneWidget);
  });

  testWidgets('unarchive returns a tracker to the tab', (tester) async {
    final cig = await repo.create(cigarettes);
    await repo.archive(cig.id);
    await openManager(tester);

    await tester.tap(find.byKey(Key('tracker-unarchive-${cig.id}')));
    await tester.pumpAndSettle();

    expect(await liveNames(tester), ['Cigarettes']);
  });

  Future<void> dragFirstAboveSecond(WidgetTester tester, Tracker first) async {
    // Reversed like the tab: the first tracker is the bottom row, so moving
    // it after the second is a drag *up*. Same gesture as the dashboard's
    // reorder test: a long press starts the drag on a phone, and 2.2 row
    // heights clears the neighbour's midpoint.
    final row = find.byKey(Key('tracker-row-${first.id}'));
    final height = tester.getSize(row).height;
    final gesture = await tester.startGesture(tester.getCenter(row),
        kind: PointerDeviceKind.touch);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.moveBy(Offset(0, -height * 2.2));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('dragging reorders, and the stored order follows',
      (tester) async {
    final [cig, _] = await repo.createAll([cigarettes, gym]);
    await openManager(tester);
    await dragFirstAboveSecond(tester, cig);
    expect(await liveNames(tester), ['Gym', 'Cigarettes']);
  });

  testWidgets('a failed reorder says so and puts the rows back',
      (tester) async {
    final [cig, g] = await repo.createAll([cigarettes, gym]);
    await db.customStatement(
        'CREATE TEMP TRIGGER fail_tracker BEFORE UPDATE ON trackers '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END");
    await openManager(tester);

    Object? caught;
    await runZonedGuarded(() => dragFirstAboveSecond(tester, cig),
        (error, stack) => caught = error);

    expect(find.text('Could not save. Try again.'), findsOneWidget);
    expect(caught, isNotNull);
    expect(await liveNames(tester), ['Cigarettes', 'Gym']);
    // On screen too: the first tracker is back at the bottom.
    expect(tester.getCenter(find.byKey(Key('tracker-row-${cig.id}'))).dy,
        greaterThan(tester.getCenter(find.byKey(Key('tracker-row-${g.id}'))).dy));
  });

  testWidgets('the tab opens the manager from its app bar', (tester) async {
    await repo.create(cigarettes);
    await pumpApp(tester,
        database: db,
        initialLocation: trackersRoute,
        overrides: trackerOverrides(fake));

    await tester.tap(find.byKey(const Key('trackers-manage')));
    await tester.pumpAndSettle();
    expect(find.text('Manage trackers'), findsOneWidget);
  });

  testWidgets('the empty tab offers "Create your own"', (tester) async {
    await pumpApp(tester,
        database: db,
        initialLocation: trackersRoute,
        overrides: trackerOverrides(fake));

    await tester.tap(find.byKey(const Key('tracker-create-own')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tracker-name-field')), 'Reading');
    await tapVisible(tester, find.byKey(const Key('tracker-save')));
    await tester.pumpAndSettle();

    final reading = (await firstOf(tester, repo.watchTrackers())).single;
    expect(find.byKey(Key('tracker-tile-${reading.id}')), findsOneWidget);
  });
}
