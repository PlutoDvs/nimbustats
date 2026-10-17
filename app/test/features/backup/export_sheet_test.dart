import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/backup/data/backup_state_store.dart';

import '../../support/harness.dart';
import 'support/fake_backup_channel.dart';
import 'support/fake_backup_service.dart';
import 'support/gregorian_english.dart';
import 'support/small_phone.dart';

void main() {
  late AppDatabase db;
  late FakeBackupService service;
  late FakeBackupChannel channel;
  late Directory dir;
  late BackupStateStore store;

  setUp(() {
    db = AppDatabase.openInMemory();
    service = FakeBackupService();
    channel = FakeBackupChannel();
    dir = Directory.systemTemp.createTempSync('nimbus_export_sheet');
    store = BackupStateStore('${dir.path}/backup_state.json');
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> openSheet(WidgetTester tester) async {
    await useGregorianEnglish(db);
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        initialLocation: '/settings',
        backup: service,
        backupChannel: channel,
        backupState: store);
    await tester.scrollUntilVisible(find.byKey(const Key('backup-export')), 200);
    await tester.ensureVisible(find.byKey(const Key('backup-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-export')));
    await tester.pumpAndSettle();
  }

  Future<void> encrypt(WidgetTester tester, String first, String second,
      {bool settle = true}) async {
    await tester.enterText(find.byKey(const Key('backup-passphrase')), first);
    await tester.enterText(find.byKey(const Key('backup-passphrase-repeat')), second);
    await tester.tap(find.byKey(const Key('backup-encrypt')));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('under 8 characters is refused, and nothing is exported',
      (tester) async {
    await openSheet(tester);
    await encrypt(tester, 'short', 'short');
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(service.calls, isNot(contains('exportTo')));
  });

  testWidgets('two passphrases that differ are refused', (tester) async {
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct house');
    expect(find.text('The two passphrases differ.'), findsOneWidget);
    expect(service.calls, isNot(contains('exportTo')));
  });

  testWidgets('the same passphrase in Persian and Latin digits matches',
      (tester) async {
    await openSheet(tester);
    await encrypt(tester, '۱۲۳۴۵۶۷۸', '12345678');
    expect(service.calls, contains('exportTo'));
    // Passed as typed: normalising is the key derivation's job.
    expect(service.lastPassphrase, '۱۲۳۴۵۶۷۸');
  });

  testWidgets('Save hands the file over, closes, says so and records the time',
      (tester) async {
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse');
    await tester.tap(find.byKey(const Key('backup-save')));
    await tester.pumpAndSettle();

    expect(channel.calls.single,
        matches(RegExp(r'^saveDocument .*nimbustats-\d{8}-\d{4}\.nimbus$')));
    expect(find.byKey(const Key('backup-save')), findsNothing);
    expect(find.text('Backup saved.'), findsOneWidget);
    expect(store.lastExport(), isNotNull);
    expect(find.textContaining('Last export: '), findsOneWidget);
  });

  testWidgets('a double tap on Save hands over once and leaves Settings open',
      (tester) async {
    channel.saveGate = Completer<void>();
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse');
    final save = find.byKey(const Key('backup-save'));
    await tester.tap(save);
    await tester.tap(save);
    channel.saveGate!.complete();
    await tester.pumpAndSettle();

    expect(channel.calls.where((c) => c.startsWith('saveDocument')), hasLength(1));
    expect(find.text('Backup saved.'), findsOneWidget);
    expect(find.byKey(const Key('backup-section')), findsOneWidget);
  });

  testWidgets('a cancelled Save is not an error: the choice stays, nothing '
      'is recorded', (tester) async {
    channel.saveAnswer = false;
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse');
    await tester.tap(find.byKey(const Key('backup-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backup-save')), findsOneWidget);
    expect(find.byKey(const Key('backup-sheet-error')), findsNothing);
    expect(store.lastExport(), isNull);
  });

  testWidgets('Share hands the file over and closes', (tester) async {
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse');
    await tester.tap(find.byKey(const Key('backup-share')));
    await tester.pumpAndSettle();

    expect(channel.calls.single, startsWith('shareFile '));
    expect(find.byKey(const Key('backup-share')), findsNothing);
    expect(store.lastExport(), isNotNull);
  });

  testWidgets('a failed Save is reported and said; the choice stays',
      (tester) async {
    channel.error = StateError('copy failed');
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse');
    await tester.tap(find.byKey(const Key('backup-save')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isA<StateError>());
    expect(find.text("The backup couldn't be saved."), findsOneWidget);
    expect(find.byKey(const Key('backup-share')), findsOneWidget);
  });

  testWidgets('a failed Save is announced (M7)', (tester) async {
    final semantics = tester.ensureSemantics();
    channel.error = StateError('copy failed');
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse');
    await tester.tap(find.byKey(const Key('backup-save')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isA<StateError>());
    expect(
        tester
            .getSemantics(find.bySemanticsLabel("The backup couldn't be saved."))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue);
    semantics.dispose();
  });

  testWidgets('on a small phone at twice the text size the sheet fits and '
      'scrolls to Encrypt (I2)', (tester) async {
    useSmallPhoneLargeText(tester);
    await openSheet(tester);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byKey(const Key('backup-passphrase')), 'correct horse');
    await tester.enterText(
        find.byKey(const Key('backup-passphrase-repeat')), 'correct horse');
    await tester.ensureVisible(find.byKey(const Key('backup-encrypt')));
    await tester.tap(find.byKey(const Key('backup-encrypt')));
    await tester.pumpAndSettle();
    expect(service.calls, contains('exportTo'));
  });

  testWidgets('the navigation bar cannot take the app from under a working '
      'sheet (M3)', (tester) async {
    service.exportGate = Completer<void>();
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse', settle: false);

    // Where Home's destination is: the sheet's barrier must cover it.
    await tester.tapAt(tester.getCenter(find.byIcon(Icons.receipt_long_outlined)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Encrypting…'), findsOneWidget);
    expect(find.byKey(const Key('tx-add-fab')), findsNothing);

    service.exportGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup-save')), findsOneWidget);
  });

  testWidgets('a failed export is reported and the passphrase step returns',
      (tester) async {
    service.exportError = StateError('disk full');
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse');

    expect(tester.takeException(), isA<StateError>());
    expect(find.text("The backup couldn't be made."), findsOneWidget);
    expect(find.byKey(const Key('backup-encrypt')), findsOneWidget);
  });

  testWidgets('the sheet cannot be dismissed while encrypting', (tester) async {
    service.exportGate = Completer<void>();
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse', settle: false);
    expect(find.text('Encrypting…'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // the barrier
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Encrypting…'), findsOneWidget);

    service.exportGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup-save')), findsOneWidget);
  });
}
