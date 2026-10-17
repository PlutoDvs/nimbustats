import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../bootstrap/database_provider.dart';
import '../data/backup_state_store.dart';

/// The live database file. `main` overrides it with the path it opened.
///
/// Reading it without the override is a bootstrap bug, so it throws, like
/// [appDatabaseProvider].
final databaseFileProvider = Provider<String>(
  (ref) => throw StateError(
      'databaseFileProvider was read without being overridden; main() '
      'overrides it with the path it opened.'),
);

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final live = ref.watch(databaseFileProvider);
  final cache = await getTemporaryDirectory();
  return BackupService(
    db: ref.watch(appDatabaseProvider),
    livePath: live,
    cacheDir: p.join(cache.path, 'backup'),
    preRestorePath: p.join(p.dirname(live), 'nimbustats.pre-restore.sqlite'),
  );
});

final backupStateStoreProvider = Provider<BackupStateStore>((ref) =>
    BackupStateStore(
        p.join(p.dirname(ref.watch(databaseFileProvider)), 'backup_state.json')));

/// What the backup section shows (spec §5.1).
typedef BackupStatus = ({
  DateTime? lastExport,
  bool canUndo,
  int databaseBytes,
});

final backupStatusProvider = FutureProvider<BackupStatus>((ref) async {
  final service = await ref.watch(backupServiceProvider.future);
  return (
    lastExport: ref.watch(backupStateStoreProvider).lastExport(),
    canUndo: service.canUndo,
    databaseBytes: await service.databaseBytes(),
  );
});

/// Above this, the section warns that Auto Backup's 25 MB cap is near
/// (spec §4.3, ruling R7; measured in docs/DEVELOPMENT.md).
const autoBackupWarnBytes = 20 * 1024 * 1024;
