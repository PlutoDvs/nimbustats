import 'dart:async';

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
    repo = repositoryFor(db, fake);
  });
  tearDown(() => db.close());

  Future<void> openDetail(WidgetTester tester, String id,
          {Locale locale = const Locale('en')}) =>
      pumpApp(tester,
          database: db,
          initialLocation: trackerLocation(id),
          locale: locale,
          overrides: trackerOverrides(fake));

  Finder row(String entryId) => find.byKey(Key('tracker-entry-$entryId'));
  Finder quickLog() => find.descendant(
      of: find.byKey(const Key('tracker-quick-log')),
      matching: find.byType(InkWell));
  Future<String> logged(Tracker t, {DateTime? at, double? value}) async =>
      (await repo.logEntry(t.id, at: at, value: value) as EntryLogged).entry.id;
  double screenHeight(WidgetTester tester) =>
      tester.view.physicalSize.height / tester.view.devicePixelRatio;

  group('states', () {
    testWidgets('loading shows a skeleton', (tester) async {
      final never = StreamController<Tracker?>();
      addTearDown(never.close);
      await pumpApp(tester, initialLocation: trackerLocation('x'), overrides: [
        ...trackerOverrides(fake),
        trackerByIdProvider('x').overrideWith((ref) => never.stream),
      ]);
      expect(find.byType(NimbusLoadingList), findsOneWidget);
    });

    testWidgets('the error state retries and hides the raw exception',
        (tester) async {
      await pumpApp(tester, initialLocation: trackerLocation('x'), overrides: [
        ...trackerOverrides(fake),
        trackerByIdProvider('x')
            .overrideWith((ref) => Stream<Tracker?>.error(Exception('boom'))),
      ]);
      expect(find.byType(NimbusErrorState), findsOneWidget);
      expect(find.text('Exception: boom'), findsNothing);
    });

    testWidgets('an unknown tracker says it is gone, with a way back',
        (tester) async {
      await openDetail(tester, 'missing');
      expect(find.text('This tracker is gone'), findsOneWidget);
      expect(find.text('Trackers'), findsOneWidget);
    });

    testWidgets('an empty history says so, with the quick log below',
        (tester) async {
      await useEnglishDigits(db);
      final cig = await repo.create(cigarettes);
      await openDetail(tester, cig.id);

      expect(textIn(tester, const Key('tracker-detail-total')), '0 today');
      expect(find.text('Nothing logged yet'), findsOneWidget);
      expect(quickLog(), findsOneWidget);
    });
  });

  group('history', () {
    setUp(() => useEnglishDigits(db));

    testWidgets('newest first, each with its day and time', (tester) async {
      final cig = await repo.create(cigarettes);
      final early = await logged(cig, at: DateTime.utc(2026, 10, 5, 9));
      final late = await logged(cig, at: DateTime.utc(2026, 10, 5, 11));
      await openDetail(tester, cig.id);

      expect(tester.getCenter(row(late)).dy,
          lessThan(tester.getCenter(row(early)).dy));
      // Dates follow the active calendar, Jalali by default: 2026-10-05 is
      // 13 Mehr 1405.
      expect(
          find.descendant(
              of: row(late), matching: find.textContaining('1405/07/13 · 14:30')),
          findsOneWidget);
      expect(textIn(tester, const Key('tracker-detail-total')), '2 today');
    });

    testWidgets('scrolling down loads older pages', (tester) async {
      final cig = await repo.create(cigarettes);
      late String oldest;
      for (var i = 0; i < 45; i++) {
        oldest = await logged(cig,
            at: fake.nowUtc.subtract(Duration(minutes: i)));
      }
      await openDetail(tester, cig.id);
      expect(row(oldest), findsNothing);

      await tester.scrollUntilVisible(row(oldest), 300,
          scrollable: find.descendant(
              of: find.byKey(const Key('tracker-history')),
              matching: find.byType(Scrollable)));
      expect(row(oldest), findsOneWidget);
    });

    testWidgets('the quick log stays in the bottom third while history scrolls',
        (tester) async {
      final cig = await repo.create(cigarettes);
      for (var i = 0; i < 30; i++) {
        await logged(cig, at: fake.nowUtc.subtract(Duration(minutes: i)));
      }
      await openDetail(tester, cig.id);
      final before = tester.getCenter(quickLog()).dy;

      await tester.drag(
          find.byKey(const Key('tracker-history')), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(tester.getCenter(quickLog()).dy, before);
      expect(before, greaterThan(screenHeight(tester) * 2 / 3));
    });

    testWidgets('a quick log adds a row and moves the header', (tester) async {
      final cig = await repo.create(cigarettes);
      await openDetail(tester, cig.id);

      await tester.tap(quickLog());
      await tester.pumpAndSettle();

      expect(textIn(tester, const Key('tracker-detail-total')), '1 today');
      final entry = (await repo.entriesPage(cig.id)).items.single;
      expect(row(entry.id), findsOneWidget);
    });
  });

  group('editing an entry', () {
    setUp(() => useEnglishDigits(db));

    testWidgets("the sheet shows the entry's own day and time", (tester) async {
      final cig = await repo.create(cigarettes);
      final id = await logged(cig);
      await openDetail(tester, cig.id);

      await tester.tap(row(id));
      await tester.pumpAndSettle();
      expect(find.text('Edit entry'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('tracker-entry-date')),
              matching: find.text('1405/07/13')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('tracker-entry-time')),
              matching: find.text('12:30')),
          findsOneWidget);
    });

    testWidgets('a note is saved and the instant is left alone',
        (tester) async {
      // Logged in Tehran at an instant with seconds and milliseconds, then
      // edited after flying to New York. A note-only edit must change neither
      // the instant nor the day; rebuilding the instant from the picker's
      // wall time would drop the milliseconds and move the day.
      final cig = await repo.create(cigarettes);
      final id =
          await logged(cig, at: DateTime.utc(2026, 10, 4, 22, 0, 7, 500));
      final before = (await repo.entriesPage(cig.id)).items.single;
      expect(before.localDateKey, const DateKey(20261005));
      fake.offset = FakeClock.newYork;
      await openDetail(tester, cig.id);

      await tester.tap(row(id));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('tracker-entry-note')), 'after lunch');
      await tester.tap(find.byKey(const Key('tracker-entry-save')));
      await tester.pumpAndSettle();

      final after = (await repo.entriesPage(cig.id)).items.single;
      expect(after.note, 'after lunch');
      expect(after.occurredAtUtc, before.occurredAtUtc);
      expect(after.localDateKey, before.localDateKey);
      expect(find.descendant(of: row(id), matching: find.textContaining('after lunch')),
          findsOneWidget);
    });

    testWidgets("a quantity's amount can be changed", (tester) async {
      final w = await repo.create(water);
      final id = await logged(w);
      await openDetail(tester, w.id);

      await tester.tap(row(id));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('tracker-entry-amount')), '0.5');
      await tester.tap(find.byKey(const Key('tracker-entry-save')));
      await tester.pumpAndSettle();

      expect(find.descendant(of: row(id), matching: find.text('0.5 L')),
          findsOneWidget);
      expect(textIn(tester, const Key('tracker-detail-total')), '0.5 L today');
    });

    testWidgets('a counter entry has no value to edit', (tester) async {
      final cig = await repo.create(cigarettes);
      final id = await logged(cig);
      await openDetail(tester, cig.id);

      await tester.tap(row(id));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tracker-entry-amount')), findsNothing);
      expect(find.byKey(const Key('tracker-entry-hours')), findsNothing);
    });

    testWidgets("a timed session's seconds survive a note-only edit",
        (tester) async {
      final s = await repo.create(sleep);
      await repo.startTimer(s.id);
      fake.advance(const Duration(hours: 7, minutes: 30, seconds: 15));
      final stopped = await repo.stopTimer(s.id) as TimerStopped;
      await openDetail(tester, s.id);

      await tester.tap(row(stopped.entry.id));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tracker-entry-note')), 'ok');
      await tester.tap(find.byKey(const Key('tracker-entry-save')));
      await tester.pumpAndSettle();

      expect((await repo.entriesPage(s.id)).items.single.value, 27015);
    });
  });

  group('deleting an entry', () {
    setUp(() => useEnglishDigits(db));

    Future<void> deleteRow(WidgetTester tester, String id) async {
      await tester.tap(find.byKey(Key('tracker-entry-menu-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracker-entry-delete')));
      await tester.pumpAndSettle();
    }

    testWidgets('delete removes the row, and undo brings it back',
        (tester) async {
      final cig = await repo.create(cigarettes);
      final id = await logged(cig);
      await openDetail(tester, cig.id);

      await deleteRow(tester, id);
      expect(row(id), findsNothing);
      expect(find.text('Entry deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(row(id), findsOneWidget);
    });

    testWidgets('an undo onto a day marked done again says so', (tester) async {
      final g = await repo.create(gym);
      final id = await logged(g);
      await openDetail(tester, g.id);

      await deleteRow(tester, id);
      // Done again from somewhere else while the snackbar is still up.
      await repo.logEntry(g.id);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('That day is already marked done'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('time', () {
    setUp(() => useEnglishDigits(db));

    testWidgets('a forgotten session is added from the detail screen',
        (tester) async {
      final s = await repo.create(sleep);
      await openDetail(tester, s.id);

      await tester.tap(find.byKey(const Key('tracker-add-duration')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('tracker-duration-hours')), '1');
      await tester.enterText(
          find.byKey(const Key('tracker-duration-minutes')), '15');
      await tester.tap(find.byKey(const Key('tracker-duration-save')));
      await tester.pumpAndSettle();

      final entry = (await repo.entriesPage(s.id)).items.single;
      expect(entry.value, 4500);
      expect(find.descendant(of: row(entry.id), matching: find.text('1:15')),
          findsOneWidget);
      expect(textIn(tester, const Key('tracker-detail-total')), '1:15 today');
    });

    testWidgets('less than a minute is refused in the sheet', (tester) async {
      final s = await repo.create(sleep);
      await openDetail(tester, s.id);

      await tester.tap(find.byKey(const Key('tracker-add-duration')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracker-duration-save')));
      await tester.pumpAndSettle();

      expect(find.text('Enter at least one minute'), findsOneWidget);
      expect((await repo.entriesPage(s.id)).items, isEmpty);
    });
  });

  group('from the tab', () {
    setUp(() => useEnglishDigits(db));

    Future<void> openFromTab(WidgetTester tester, Tracker t) async {
      await pumpApp(tester,
          database: db,
          initialLocation: trackersRoute,
          overrides: trackerOverrides(fake));
      await tester.tap(find.descendant(
          of: find.byKey(Key('tracker-tile-${t.id}')),
          matching: find.text(t.name)));
      await tester.pumpAndSettle();
    }

    testWidgets('a tile opens its tracker', (tester) async {
      final cig = await repo.create(cigarettes);
      await openFromTab(tester, cig);
      expect(find.byKey(const Key('tracker-detail-total')), findsOneWidget);
    });

    testWidgets('the menu edits the tracker', (tester) async {
      final cig = await repo.create(cigarettes);
      await openFromTab(tester, cig);

      await tester.tap(find.byKey(const Key('tracker-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracker-menu-edit-tracker')));
      await tester.pumpAndSettle();
      expect(find.text('Edit tracker'), findsOneWidget);
    });

    testWidgets('archive goes back to the tab, with an undo', (tester) async {
      final [cig, g] = await repo.createAll([cigarettes, gym]);
      await openFromTab(tester, cig);

      await tester.tap(find.byKey(const Key('tracker-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracker-menu-archive-tracker')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tracker-detail-total')), findsNothing);
      expect(find.byKey(Key('tracker-tile-${cig.id}')), findsNothing);
      expect(find.byKey(Key('tracker-tile-${g.id}')), findsOneWidget);
      expect(find.text('Archived Cigarettes'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('tracker-tile-${cig.id}')), findsOneWidget);
    });
  });

  testWidgets('Persian digits in the header and the history', (tester) async {
    final cig = await repo.create(cigarettes);
    final id = await logged(cig);
    await openDetail(tester, cig.id, locale: const Locale('fa'));

    expect(textIn(tester, const Key('tracker-detail-total')), 'امروز ۱');
    expect(
        find.descendant(of: row(id), matching: find.textContaining('۱۲:۳۰')),
        findsOneWidget);
  });
}
