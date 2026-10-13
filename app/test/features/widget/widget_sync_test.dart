import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/trackers/routes.dart';
import 'package:nimbustats/features/widget/presentation/widget_sync.dart';

import '../../support/harness.dart';
import '../notifications/support/fake_outside_channel.dart';
import '../trackers/support/tracker_fixture.dart';
import 'support/buffer_lines.dart';

void main() {
  late AppDatabase db;
  late FakeOutsideChannel outside;
  late FakeClock fake;

  setUp(() {
    db = AppDatabase.openInMemory();
    outside = FakeOutsideChannel();
    fake = FakeClock();
  });
  tearDown(() => db.close());

  Map<String, Object?> last() =>
      jsonDecode(outside.snapshots.last) as Map<String, Object?>;

  /// Longer than the 300 ms debounce, and lets the write finish.
  Future<void> settleSnapshot(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  testWidgets('a snapshot is written after start-up', (tester) async {
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);
    await settleSnapshot(tester);

    expect(outside.snapshots, isNotEmpty);
    expect(last()['v'], 1);
  });

  testWidgets("a tracker tap in the app rewrites it with today's new total",
      (tester) async {
    final cig = await repositoryFor(db, fake).create(cigarettes);
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        outside: outside,
        initialLocation: trackersRoute,
        overrides: trackerOverrides(fake));
    await settleSnapshot(tester);

    await tester.tap(find.byKey(Key('tracker-action-${cig.id}')));
    await tester.pumpAndSettle();
    await settleSnapshot(tester);

    final row = (last()['trackers']! as List<Object?>).single as Map;
    expect(row['todayTotal'], 1.0);
  });

  testWidgets('a language switch rewrites it in the new language',
      (tester) async {
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        outside: outside,
        initialLocation: '/settings',
        locale: null);
    await settleSnapshot(tester);
    expect(last()['localeTag'], 'fa');

    await tester.tap(find.byKey(const Key('settings-locale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('locale-en')));
    await tester.pumpAndSettle();
    await settleSnapshot(tester);

    expect(last()['localeTag'], 'en');
    expect(last()['rtl'], isFalse);
  });

  testWidgets('the app engine drains after the first frame', (tester) async {
    outside.buffer = [expense('w1')];
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);
    await tester.pumpAndSettle();

    expect(outside.buffer, isEmpty);
    expect(await db.transactionsDao.byId('w1'), isNotNull);
  });

  testWidgets("native's drainNow drains in the app engine and answers ok",
      (tester) async {
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);
    await tester.pumpAndSettle();
    outside.buffer = [expense('w2')];

    final answered = outside.onDrainNow!();
    await tester.pumpAndSettle();

    expect(await answered, isTrue);
    expect(outside.buffer, isEmpty);
  });

  testWidgets('a drainNow that fails is reported, and native hears the error',
      (tester) async {
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);
    await tester.pumpAndSettle();
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);
    outside.takeError = PlatformException(code: 'boom');

    // Listened to before it fails. The error reply is what sends native's
    // job to the headless engine.
    final answered =
        expectLater(outside.onDrainNow!(), throwsA(isA<PlatformException>()));
    await tester.pumpAndSettle();
    // Restored before any expect, or a failing one wedges the binding.
    FlutterError.onError = previous;

    await answered;
    expect(reports.single.library, 'widget drain');
  });

  testWidgets('a resume drains', (tester) async {
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);
    await tester.pumpAndSettle();
    outside.buffer = [expense('w3')];

    await backgroundAndResume(tester);
    await tester.pumpAndSettle();

    expect(outside.buffer, isEmpty);
  });

  testWidgets('leaving the shell unregisters the drain, so native drains '
      'headless', (tester) async {
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);
    expect(outside.onDrainNow, isNotNull);

    await tester.pumpWidget(const SizedBox());
    expect(outside.onDrainNow, isNull);
  });

  testWidgets('a shell leaving after a newer one mounted keeps the newer '
      "one's drain", (tester) async {
    late ProviderContainer container;
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        outside: outside,
        onContainer: (c) => container = c);
    Widget shells(List<String> keys) => UncontrolledProviderScope(
          container: container,
          child: Column(children: [
            for (final key in keys)
              WidgetSync(key: Key(key), child: const SizedBox()),
          ]),
        );

    // A router rebuild mounts the new shell before the old one disposes.
    await tester.pumpWidget(shells(['old', 'new']));
    await tester.pumpWidget(shells(['new']));

    expect(outside.onDrainNow, isNotNull);
  });
}
