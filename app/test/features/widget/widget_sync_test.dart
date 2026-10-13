import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import '../notifications/support/fake_outside_channel.dart';
import '../trackers/support/tracker_fixture.dart';

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
}
