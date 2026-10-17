import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/backup/application/backup_controller.dart';
import 'package:nimbustats/features/backup/application/backup_providers.dart';
import 'package:nimbustats/features/backup/application/restart.dart';
import 'package:nimbustats/features/backup/data/backup_channel.dart';
import 'package:nimbustats/features/backup/data/backup_state_store.dart';

import 'support/fake_backup_channel.dart';
import 'support/fake_backup_service.dart';

void main() {
  late FakeBackupService service;
  late FakeBackupChannel channel;
  late Directory dir;
  late BackupStateStore store;
  late List<RestartNotice> restarts;
  late ProviderContainer container;

  ProviderContainer containerFor(BackupStateStore store) =>
      ProviderContainer(overrides: [
        backupServiceProvider.overrideWith((ref) async => service),
        backupChannelProvider.overrideWithValue(channel),
        backupStateStoreProvider.overrideWithValue(store),
        appRestartProvider.overrideWithValue(restarts.add),
      ]);

  setUp(() {
    service = FakeBackupService();
    channel = FakeBackupChannel();
    dir = Directory.systemTemp.createTempSync('nimbus_backup_controller');
    store = BackupStateStore('${dir.path}/backup_state.json');
    restarts = [];
    container = containerFor(store);
  });
  tearDown(() {
    container.dispose();
    dir.deleteSync(recursive: true);
  });

  BackupController controller() => container.read(backupControllerProvider);

  /// A store that cannot write: its path is a folder.
  void useBrokenStore() {
    container.dispose();
    container = containerFor(BackupStateStore(
        (Directory('${dir.path}/state-dir')..createSync()).path));
  }

  /// What [FlutterError.reportError] receives during the test.
  List<FlutterErrorDetails> captureReports() {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);
    return reports;
  }

  String pickedFile() {
    final path = '${dir.path}/picked-1.nimbus';
    File(path).writeAsBytesSync(const [1]);
    return path;
  }

  test('export writes one file, named by local time, in the cache out/ folder',
      () async {
    final first = await controller().export('correct horse');
    final second = await controller().export('correct horse');

    expect(File(second).parent.path, '${service.cacheDir}${Platform.pathSeparator}out');
    expect(File(second).uri.pathSegments.last,
        matches(RegExp(r'^nimbustats-\d{8}-\d{4}\.nimbus$')));
    // Only the latest is kept for Share.
    expect(File(second).parent.listSync(), hasLength(1));
    expect(first == second || !File(first).existsSync(), isTrue);
  });

  test('a saved export is recorded; a cancelled one is not (R9)', () async {
    channel.saveAnswer = false;
    expect(await controller().save('/x.nimbus'), isFalse);
    expect(store.lastExport(), isNull);

    channel.saveAnswer = true;
    expect(await controller().save('/x.nimbus'), isTrue);
    expect(store.lastExport(), isNotNull);
  });

  test('opening the share sheet is recorded as an export', () async {
    await controller().share('/x.nimbus');
    expect(channel.calls, ['shareFile /x.nimbus']);
    expect(store.lastExport(), isNotNull);
  });

  group('pick', () {
    test('a cancelled picker is null', () async {
      expect(await controller().pick(), isNull);
    });

    test('reads the header of the copy', () async {
      channel.picked = pickedFile();
      final picked = await controller().pick();
      expect(picked!.path, channel.picked);
      expect(picked.header.createdAt, service.header.createdAt);
    });

    test('a header error deletes the copy and rethrows', () async {
      channel.picked = pickedFile();
      service.headerError = const NotABackup();
      await expectLater(controller().pick(), throwsA(isA<NotABackup>()));
      expect(File(channel.picked!).existsSync(), isFalse);
    });
  });

  group('restore', () {
    test('a wrong passphrase keeps the copy and does not restart', () async {
      channel.picked = pickedFile();
      final picked = (await controller().pick())!;
      await expectLater(controller().restore(picked, 'wrong'),
          throwsA(isA<WrongPassphrase>()));
      expect(File(picked.path).existsSync(), isTrue);
      expect(restarts, isEmpty);
    });

    test('swaps, deletes the copy and restarts with the backup date', () async {
      store.setUndoRedoes(true); // an earlier undo
      channel.picked = pickedFile();
      final picked = (await controller().pick())!;
      await controller().restore(picked, FakeBackupService.goodPassphrase);

      expect(service.calls, containsAllInOrder(['prepare', 'restore']));
      expect(File(picked.path).existsSync(), isFalse);
      expect(store.undoRedoes(), isFalse); // the copy now undoes this restore
      expect(
          restarts.single,
          isA<BackupRestored>().having(
              (n) => n.backupCreatedAt, 'createdAt', service.header.createdAt));
    });

    test('once swapped, a failure recording it is reported and the app still '
        'restarts onto the restored data', () async {
      final reports = captureReports();
      useBrokenStore();
      channel.picked = pickedFile();
      final picked = (await controller().pick())!;

      await controller().restore(picked, FakeBackupService.goodPassphrase);
      expect(reports.single.library, 'backup');
      expect(restarts.single, isA<BackupRestored>());
    });
  });

  group('undo', () {
    test('swaps, then the next one swaps back: Undone, then Redone', () async {
      await controller().undo();
      expect(service.calls, ['undo']);
      expect(store.undoRedoes(), isTrue);
      expect(restarts.single, isA<RestoreUndone>());

      await controller().undo();
      expect(service.calls, ['undo', 'undo']);
      expect(store.undoRedoes(), isFalse);
      expect(restarts.last, isA<RestoreRedone>());
    });

    test('a failed swap changes neither the flag nor the app', () async {
      service.undoError = StateError('swap failed');
      await expectLater(controller().undo(), throwsStateError);
      expect(store.undoRedoes(), isFalse);
      expect(restarts, isEmpty);
    });

    test('once swapped, a failure recording it is reported, not thrown',
        () async {
      final reports = captureReports();
      useBrokenStore();
      await controller().undo();
      expect(reports.single.library, 'backup');
      expect(restarts.single, isA<RestoreUndone>());
    });
  });

  test('the status combines the store and the service', () async {
    store
      ..recordExport(DateTime.utc(2026, 10, 17))
      ..setUndoRedoes(true);
    service
      ..undoable = true
      ..bytes = 123;
    final status = await container.read(backupStatusProvider.future);
    expect(status.lastExport, DateTime.utc(2026, 10, 17));
    expect(status.canUndo, isTrue);
    expect(status.undoRedoes, isTrue);
    expect(status.databaseBytes, 123);
  });
}
