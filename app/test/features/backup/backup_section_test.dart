import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/backup/application/backup_providers.dart';
import 'package:nimbustats/features/backup/application/restart.dart';
import 'package:nimbustats/features/backup/data/backup_state_store.dart';

import '../../support/harness.dart';
import 'support/fake_backup_service.dart';
import 'support/gregorian_english.dart';

void main() {
  late AppDatabase db;
  late FakeBackupService service;
  late Directory dir;
  late BackupStateStore store;
  late List<RestartNotice> restarts;

  setUp(() {
    db = AppDatabase.openInMemory();
    service = FakeBackupService();
    dir = Directory.systemTemp.createTempSync('nimbus_backup_section');
    store = BackupStateStore('${dir.path}/backup_state.json');
    restarts = [];
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  /// Opens Settings and scrolls the section's [row] into view. Loading and
  /// error states have no rows, so their tests scroll to the section itself.
  Future<void> open(WidgetTester tester,
      {Locale locale = const Locale('en'),
      String row = 'backup-restore',
      List<Override> overrides = const []}) async {
    if (locale.languageCode == 'en') await useGregorianEnglish(db);
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        initialLocation: '/settings',
        locale: locale,
        backup: service,
        backupState: store,
        overrides: [
          appRestartProvider.overrideWithValue(restarts.add),
          ...overrides,
        ]);
    await tester.scrollUntilVisible(find.byKey(Key(row)), 200);
    await tester.pumpAndSettle();
  }

  testWidgets('never exported: the empty state, and stale files are swept',
      (tester) async {
    await open(tester);
    expect(find.text('Never exported'), findsOneWidget);
    expect(service.calls, contains('sweep'));
    expect(find.byKey(const Key('backup-undo')), findsNothing);
    expect(find.byKey(const Key('backup-size-warning')), findsNothing);
  });

  testWidgets('the last export shows in the active calendar', (tester) async {
    store.recordExport(DateTime(2026, 10, 17, 9, 5).toUtc());
    await open(tester);
    expect(find.text('Last export: 2026/10/17 09:05'), findsOneWidget);
  });

  testWidgets('loading', (tester) async {
    await open(tester, row: 'backup-section', overrides: [
      backupStatusProvider.overrideWith((ref) => Completer<BackupStatus>().future),
    ]);
    expect(find.byKey(const Key('backup-loading')), findsOneWidget);
  });

  testWidgets('an unreadable state file is an error with a retry',
      (tester) async {
    await open(tester, row: 'backup-section', overrides: [
      backupStatusProvider.overrideWith(
          (ref) async => throw const FormatException('unreadable backup state')),
    ]);
    expect(find.byKey(const Key('backup-error')), findsOneWidget);
    expect(find.text("Couldn't read the backup status."), findsOneWidget);
  });

  testWidgets('past 20 MiB the section warns about the Auto Backup cap (R7)',
      (tester) async {
    service.bytes = autoBackupWarnBytes + 1;
    await open(tester);
    expect(find.byKey(const Key('backup-size-warning')), findsOneWidget);
  });

  testWidgets('Undo shows only while a copy exists, and restarts saying so',
      (tester) async {
    service.undoable = true;
    await open(tester, row: 'backup-undo');
    await tester.tap(find.byKey(const Key('backup-undo')));
    await tester.pumpAndSettle();
    expect(service.calls, contains('undo'));
    expect(restarts.single, isA<RestoreUndone>());
  });

  testWidgets('a failed undo is reported and said', (tester) async {
    service
      ..undoable = true
      ..undoError = StateError('backup step failed');
    await open(tester, row: 'backup-undo');
    await tester.tap(find.byKey(const Key('backup-undo')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    expect(find.text("The restore couldn't be undone."), findsOneWidget);
    expect(restarts, isEmpty);
  });

  testWidgets('Persian, right to left: the section renders without overflow',
      (tester) async {
    await open(tester, locale: const Locale('fa'));
    expect(find.text('هنوز پشتیبانی تهیه نشده'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
