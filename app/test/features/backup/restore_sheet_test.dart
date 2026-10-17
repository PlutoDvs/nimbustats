import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/backup/application/restart.dart';
import 'package:nimbustats/features/backup/presentation/backup_messages.dart';

import '../../support/harness.dart';
import 'support/fake_backup_channel.dart';
import 'support/fake_backup_service.dart';
import 'support/gregorian_english.dart';

void main() {
  late AppDatabase db;
  late FakeBackupService service;
  late FakeBackupChannel channel;
  late Directory dir;
  late List<RestartNotice> restarts;

  setUp(() {
    db = AppDatabase.openInMemory();
    service = FakeBackupService();
    channel = FakeBackupChannel();
    dir = Directory.systemTemp.createTempSync('nimbus_restore_sheet');
    channel.picked = '${dir.path}/picked-1.nimbus';
    File(channel.picked!).writeAsBytesSync(const [1]);
    restarts = [];
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> tapRestore(WidgetTester tester) async {
    await useGregorianEnglish(db);
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        initialLocation: '/settings',
        backup: service,
        backupChannel: channel,
        overrides: [appRestartProvider.overrideWithValue(restarts.add)]);
    await tester.scrollUntilVisible(find.byKey(const Key('backup-restore')), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-restore')));
    await tester.pumpAndSettle();
  }

  Future<void> restoreWith(WidgetTester tester, String passphrase,
      {bool settle = true}) async {
    await tester.enterText(
        find.byKey(const Key('backup-restore-passphrase')), passphrase);
    await tester.tap(find.byKey(const Key('backup-restore-go')));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  bool restoreEnabled(WidgetTester tester) => tester
      .widget<FilledButton>(find.byKey(const Key('backup-restore-go')))
      .enabled;

  testWidgets("the sheet names the backup's date and what restoring does",
      (tester) async {
    await tapRestore(tester);
    final when = whenLabel(service.header.createdAt, const GregorianCalendar(),
        persianDigits: false);
    expect(find.text('Backup from $when'), findsOneWidget);
    expect(find.text('Restoring replaces all data on this phone. You can undo '
        'it afterwards.'), findsOneWidget);
  });

  testWidgets('a newer schema is refused before any passphrase, saying update',
      (tester) async {
    service.headerError = const NewerSchema(backup: 41, app: 40);
    await tapRestore(tester);
    expect(find.text('This backup is from a newer version of NimbuStats. '
        'Update the app, then restore it.'), findsOneWidget);
    expect(find.byKey(const Key('backup-restore-passphrase')), findsNothing);
    expect(File(channel.picked!).existsSync(), isFalse);
    expect(service.calls, isNot(contains('prepare')));
  });

  testWidgets('a file that is not a backup says so and leaves no copy',
      (tester) async {
    service.headerError = const NotABackup();
    await tapRestore(tester);
    expect(find.text("This isn't a NimbuStats backup file."), findsOneWidget);
    expect(File(channel.picked!).existsSync(), isFalse);
  });

  testWidgets('a wrong passphrase keeps the sheet to try again; the right one '
      'restores and restarts', (tester) async {
    await tapRestore(tester);
    await restoreWith(tester, 'not it');
    expect(find.text('Wrong passphrase.'), findsOneWidget);
    expect(restoreEnabled(tester), isTrue);
    expect(restarts, isEmpty);

    // No restart happens in this harness, so the sheet stays with its
    // progress bar showing, and pumpAndSettle would never return.
    await restoreWith(tester, FakeBackupService.goodPassphrase, settle: false);
    await tester.pump();
    expect(service.calls, containsAllInOrder(['prepare', 'restore']));
    expect(
        restarts.single,
        isA<BackupRestored>().having(
            (n) => n.backupCreatedAt, 'createdAt', service.header.createdAt));
    expect(File(channel.picked!).existsSync(), isFalse);
  });

  testWidgets('a damaged file says so and leaves only closing', (tester) async {
    service.prepareError = const CorruptBackup('authentication failed');
    await tapRestore(tester);
    await restoreWith(tester, FakeBackupService.goodPassphrase);
    expect(find.text("This backup file is damaged and can't be restored."),
        findsOneWidget);
    expect(restoreEnabled(tester), isFalse);
    expect(restarts, isEmpty);
  });

  testWidgets('an unexpected failure is reported and said generically',
      (tester) async {
    service.prepareError = StateError('migration failed');
    await tapRestore(tester);
    await restoreWith(tester, FakeBackupService.goodPassphrase);
    expect(tester.takeException(), isA<StateError>());
    expect(find.text("The backup couldn't be restored. Your data is unchanged."),
        findsOneWidget);
  });

  testWidgets('closing the sheet deletes the picked copy', (tester) async {
    await tapRestore(tester);
    await tester.tapAt(const Offset(10, 10)); // the barrier
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup-restore-go')), findsNothing);
    expect(File(channel.picked!).existsSync(), isFalse);
    expect(service.calls, isNot(contains('prepare')));
  });

  testWidgets('a second tap before the rebuild does not restore twice',
      (tester) async {
    await tapRestore(tester);
    await tester.enterText(
        find.byKey(const Key('backup-restore-passphrase')),
        FakeBackupService.goodPassphrase);
    await tester.tap(find.byKey(const Key('backup-restore-go')));
    await tester.tap(find.byKey(const Key('backup-restore-go')));
    await tester.pump();
    expect(service.calls.where((c) => c == 'prepare'), hasLength(1));
  });
}
