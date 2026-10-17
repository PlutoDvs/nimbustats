import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/app.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/first_run.dart';
import 'package:nimbustats/features/backup/application/backup_providers.dart';
import 'package:nimbustats/features/backup/data/backup_channel.dart';
import 'package:nimbustats/features/backup/data/backup_state_store.dart';
import 'package:nimbustats/features/backup/presentation/app_restart.dart';
import 'package:nimbustats/features/notifications/application/notification_providers.dart';
import 'package:nimbustats/features/notifications/data/outside_channel.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

import '../notifications/support/fake_outside_channel.dart';
import 'support/fake_backup_channel.dart';
import 'support/fake_backup_service.dart';
import 'support/gregorian_english.dart';

/// The shipped root, `AppRestart` as `main` builds it, with fakes for
/// Android and files.
void main() {
  testWidgets('a restore lands on Home and says so; Undo restarts again and '
      'says that', (tester) async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    await FirstRunController(db)
        .ensureSeeded(await AppLocalizations.delegate.load(const Locale('en')));
    await useGregorianEnglish(db);
    final dir = Directory.systemTemp.createTempSync('nimbus_restart_flow');
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = FakeBackupService();
    final channel = FakeBackupChannel()..picked = '${dir.path}/picked-1.nimbus';
    File(channel.picked!).writeAsBytesSync(const [1]);

    await tester.pumpWidget(AppRestart(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        outsideChannelProvider.overrideWithValue(FakeOutsideChannel()),
        isForegroundProvider.overrideWithValue(() => true),
        backupServiceProvider.overrideWith((ref) async => service),
        backupChannelProvider.overrideWithValue(channel),
        backupStateStoreProvider
            .overrideWithValue(BackupStateStore('${dir.path}/backup_state.json')),
      ],
      child: const NimbuStatsApp(overrideLocale: Locale('en')),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('backup-restore')), 200);
    await tester.ensureVisible(find.byKey(const Key('backup-restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-restore')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('backup-restore-passphrase')),
        FakeBackupService.goodPassphrase);
    await tester.tap(find.byKey(const Key('backup-restore-go')));
    await tester.pumpAndSettle();

    expect(service.calls, containsAllInOrder(['prepare', 'restore']));
    expect(find.byKey(const Key('tx-add-fab')), findsOneWidget); // Home
    expect(find.textContaining('Restored the backup from'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'undo');
    expect(find.text('Restore undone. Your earlier data is back.'), findsOneWidget);
    expect(find.byKey(const Key('tx-add-fab')), findsOneWidget);

    // Drift's stream teardown leaves zero-length timers.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
