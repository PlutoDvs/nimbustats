import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/dashboard_fixture.dart';

Future<void> openMenu(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('card-menu-$id')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('remove offers undo, and undo puts the card back in its place',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final (first, second) = await pinStarters(db);
    await openAnalytics(tester, db);

    await openMenu(tester, first);
    await tester.tap(find.byKey(const Key('card-menu-remove')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('saved-view-card-$first')), findsNothing);
    expect(find.text('Removed from the dashboard'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect((await storedViews(db)).map((v) => v.id), [first, second]);
    expect(find.byKey(Key('saved-view-card-$first')), findsOneWidget);
  });

  testWidgets('rename shows the new name on the card', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final (first, _) = await pinStarters(db);
    await openAnalytics(tester, db);

    await openMenu(tester, first);
    await tester.tap(find.byKey(const Key('card-menu-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('view-name-field')), 'Where it went');
    await tester.tap(find.byKey(const Key('view-name-save')));
    await tester.pumpAndSettle();

    expect(textOf(tester, 'card-name-$first'), 'Where it went');
  });

  testWidgets('dragging a card below another saves the new order',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final (first, second) = await pinStarters(db);
    await openAnalytics(tester, db);

    final card = find.byKey(Key('saved-view-card-$first'));
    final height = tester.getSize(card).height;
    final gesture = await tester.startGesture(tester.getCenter(card),
        kind: PointerDeviceKind.touch);
    // A long press starts the drag on a phone.
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    // 2.2, not 1.5: the list picks the drop index from the dragged card's
    // top edge, so 1.5 * height puts that edge exactly on the next card's
    // midpoint, onReorderItem is never called, and the drag silently does
    // nothing -- which would also let the failure test below pass without
    // exercising anything.
    await gesture.moveBy(Offset(0, height * 2.2));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect((await storedViews(db)).map((v) => v.id), [second, first]);
  });

  testWidgets('an unreadable card can be removed but not renamed',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await db.customStatement(
      'INSERT INTO saved_views (id, name, spec_json, chart_type, pinned, '
      'sort_order, created_at, updated_at) '
      "VALUES ('bad', 'Broken', '{not json', 'breakdown', 1, 0, 0, 0)",
    );
    await openAnalytics(tester, db);

    await openMenu(tester, 'bad');
    expect(find.byKey(const Key('card-menu-rename')), findsNothing);
    await tester.tap(find.byKey(const Key('card-menu-remove')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('saved-view-card-bad')), findsNothing);
  });

  testWidgets('a failed removal says so and keeps the card', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final (first, _) = await pinStarters(db);
    // A write failure on the soft-delete, injected where SQLite itself would
    // raise one.
    await db.customStatement(
        'CREATE TEMP TRIGGER fail_saved_view BEFORE UPDATE ON saved_views '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END");
    await openAnalytics(tester, db);

    // The failure still has to reach the framework's error handler rather
    // than vanish once the snackbar has shown it -- caught here directly
    // because it comes from a detached future the menu action never awaits.
    Object? caught;
    await runZonedGuarded(() async {
      await openMenu(tester, first);
      await tester.tap(find.byKey(const Key('card-menu-remove')));
      await tester.pumpAndSettle();
    }, (error, stack) => caught = error);

    expect(find.text('Could not save the change'), findsOneWidget);
    expect(find.byKey(Key('saved-view-card-$first')), findsOneWidget);
    expect(caught, isNotNull);
  });

  testWidgets('a failed reorder says so and puts the cards back',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final (first, second) = await pinStarters(db);
    // A write failure on the reorder, injected where SQLite itself would
    // raise one.
    await db.customStatement(
        'CREATE TEMP TRIGGER fail_saved_view BEFORE UPDATE ON saved_views '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END");
    await openAnalytics(tester, db);

    final card = find.byKey(Key('saved-view-card-$first'));
    final height = tester.getSize(card).height;
    final gesture = await tester.startGesture(tester.getCenter(card),
        kind: PointerDeviceKind.touch);

    Object? caught;
    await runZonedGuarded(() async {
      // A long press starts the drag on a phone.
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      // ReorderableListView.builder decides the new slot from the dragged
      // proxy's leading edge, not the pointer: with a 2-card list and a grab
      // at the card's centre, only clearing a full card-and-a-half past the
      // target's far edge (~2.2x a card's height) registers as a full swap;
      // 1.5x only reaches the target's midpoint, which nets to no move.
      await gesture.moveBy(Offset(0, height * 2.2));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }, (error, stack) => caught = error);

    expect(find.text('Could not save the change'), findsOneWidget);
    expect((await storedViews(db)).map((v) => v.id), [first, second]);
    // The on-screen order must be put back too, not just the database: a
    // card that stayed where the drag left it would show an order that was
    // never saved.
    final firstTop =
        tester.getTopLeft(find.byKey(Key('saved-view-card-$first'))).dy;
    final secondTop =
        tester.getTopLeft(find.byKey(Key('saved-view-card-$second'))).dy;
    expect(firstTop, lessThan(secondTop));
    expect(caught, isNotNull);
  });
}
