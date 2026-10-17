import 'dart:io';

import 'package:nimbus_data/nimbus_data.dart';

/// Writes `test/fixtures/backup_v1.nimbus`, the golden file every later build
/// must keep restoring (Phase 7 spec §7).
///
/// Run it once per format version, from `packages/nimbus_data`:
/// `dart run tool/make_backup_fixture.dart`. Never regenerate v1. A new
/// format version gets a new fixture beside it, and v1 keeps its test.
Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('nimbus_fixture');
  try {
    final db = AppDatabase.openAtPath('${dir.path}/live.sqlite');
    try {
      await db.settingsDao.put('fixture', 'golden v1');
      await BackupService(
        db: db,
        cacheDir: '${dir.path}/cache',
        kdf: const KdfParams(memoryKiB: 1024, iterations: 1, parallelism: 1),
        clock: () => DateTime.utc(2026, 10, 17, 12),
      ).exportTo('test/fixtures/backup_v1.nimbus', 'رمز-پشتیبان-۱۴۰۵');
    } finally {
      await db.close();
    }
  } finally {
    dir.deleteSync(recursive: true);
  }
}
