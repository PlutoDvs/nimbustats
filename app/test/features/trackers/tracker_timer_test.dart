import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late TrackerRepository repo;
  late Tracker s;

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    await useEnglishDigits(db);
    repo = repositoryFor(db, fake);
    s = await repo.create(sleep);
  });
  tearDown(() => db.close());

  Future<void> openTab(WidgetTester tester) => pumpApp(tester,
      database: db,
      initialLocation: trackersRoute,
      overrides: trackerOverrides(fake));

  Finder action() => find.byKey(Key('tracker-action-${s.id}'));
  String status(WidgetTester tester) =>
      textIn(tester, Key('tracker-total-${s.id}'));
  Future<Tracker> stored(WidgetTester tester) async =>
      (await firstOf<Tracker?>(tester, repo.watchTracker(s.id)))!;

  testWidgets('start persists the start at once and shows a running timer',
      (tester) async {
    await openTab(tester);
    await tester.tap(action());
    await tester.pumpAndSettle();

    expect((await stored(tester)).runningTimer, RunningTimer(fake.nowUtc));
    expect(status(tester), 'Running · 0:00:00');
  });

  testWidgets('the running time ticks once a second', (tester) async {
    await openTab(tester);
    await tester.tap(action());
    await tester.pumpAndSettle();

    fake.advance(const Duration(minutes: 1, seconds: 5));
    await tester.pump(const Duration(seconds: 1));

    expect(status(tester), 'Running · 0:01:05');
  });

  testWidgets('stop logs the session, stamped at its start, and says so',
      (tester) async {
    final start = fake.nowUtc;
    await openTab(tester);
    await tester.tap(action());
    await tester.pumpAndSettle();

    fake.advance(const Duration(hours: 7, minutes: 30));
    await tester.tap(action());
    await tester.pumpAndSettle();

    final entry = (await repo.entriesPage(s.id)).items.single;
    expect(entry.value, 27000);
    expect(entry.occurredAtUtc, start);
    expect(find.text('Sleep · 7:30 logged'), findsOneWidget);
    expect(status(tester), '7:30 today');
    expect((await stored(tester)).runningTimer, isNull);
  });

  testWidgets('undo after a stop removes the session it logged',
      (tester) async {
    await openTab(tester);
    await tester.tap(action());
    await tester.pumpAndSettle();
    fake.advance(const Duration(minutes: 20));
    await tester.tap(action());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await repo.entriesPage(s.id)).items, isEmpty);
  });

  testWidgets('a double-tap on start starts one timer', (tester) async {
    final start = fake.nowUtc;
    await openTab(tester);
    await tester.tap(action());
    fake.advance(const Duration(milliseconds: 300));
    await tester.tap(action());
    await tester.pumpAndSettle();

    expect((await stored(tester)).runningTimer, RunningTimer(start));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stopping within a second logs nothing and says so',
      (tester) async {
    await openTab(tester);
    await tester.tap(action());
    await tester.pumpAndSettle();
    await tester.tap(action());
    await tester.pumpAndSettle();

    expect(find.text('Under a second — nothing logged'), findsOneWidget);
    expect((await repo.entriesPage(s.id)).items, isEmpty);
    expect((await stored(tester)).runningTimer, isNull);
  });

  testWidgets('a timer started before the app was killed is still running',
      (tester) async {
    // The previous process started the timer two hours ago and died. This
    // run knows only what that one persisted.
    final earlier =
        FakeClock(nowUtc: fake.nowUtc.subtract(const Duration(hours: 2)));
    await repositoryFor(db, earlier).startTimer(s.id);

    await openTab(tester);

    expect(status(tester), 'Running · 2:00:00');
  });

  testWidgets('start and stop use a medium haptic', (tester) async {
    final haptics = captureHaptics(tester);
    await openTab(tester);
    await tester.tap(action());
    await tester.pumpAndSettle();
    fake.advance(const Duration(minutes: 1));
    await tester.tap(action());
    await tester.pumpAndSettle();

    expect(haptics,
        ['HapticFeedbackType.mediumImpact', 'HapticFeedbackType.mediumImpact']);
  });

  testWidgets('the timer button is named for a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await openTab(tester);
    expect(tester.getSemantics(action()),
        isSemantics(label: 'Start Sleep timer', isButton: true));

    await tester.tap(action());
    await tester.pumpAndSettle();
    expect(tester.getSemantics(action()),
        isSemantics(label: 'Stop Sleep timer', isButton: true));
    semantics.dispose();
  });
}
