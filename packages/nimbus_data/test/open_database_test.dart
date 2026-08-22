import 'dart:io';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

void main() {
  test('openInMemory returns a usable database', () async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    // A read against a real table proves the schema was created, not merely
    // that a connection object exists.
    expect(await db.settingsDao.get('absent'), isNull);
  });

  test('two in-memory databases do not share rows', () async {
    // Every test gets its own connection, so tests never leak into each other
    // and can run in any order.
    final a = AppDatabase.openInMemory();
    final b = AppDatabase.openInMemory();
    addTearDown(a.close);
    addTearDown(b.close);

    await a.settingsDao.put('key', 'from-a');
    expect(await b.settingsDao.get('key'), isNull);
  });

  test('openAtPath creates the file and persists across a reopen', () async {
    // This is the factory the app uses. The point of it living here rather
    // than in the app layer is that `app` then needs no drift or sqlite3
    // dependency of its own -- asserted by test/architecture_test.dart.
    final dir = Directory.systemTemp.createTempSync('nimbus_open_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}nimbustats.sqlite';

    final first = AppDatabase.openAtPath(path);
    await first.settingsDao.put('currency_code', 'IRT');
    await first.close();

    expect(File(path).existsSync(), isTrue);

    final second = AppDatabase.openAtPath(path);
    addTearDown(second.close);
    expect(await second.settingsDao.get('currency_code'), 'IRT');
  });

  test('foreign keys are enforced on a file-backed database', () async {
    // beforeOpen turns on the pragma. If that ever regressed, the cascade that
    // cleans up transaction_tags would silently stop working -- and orphaned
    // join rows are the kind of corruption nobody notices for months.
    final dir = Directory.systemTemp.createTempSync('nimbus_fk_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db =
        AppDatabase.openAtPath('${dir.path}${Platform.pathSeparator}fk.sqlite');
    addTearDown(db.close);

    final rows = await db.customSelect('PRAGMA foreign_keys').get();
    expect(rows.single.data.values.first, 1);
  });
}
