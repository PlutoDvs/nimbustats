import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimbustats/features/backup/data/backup_state_store.dart';

void main() {
  late Directory dir;
  late BackupStateStore store;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('nimbus_backup_state');
    store = BackupStateStore('${dir.path}/backup_state.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('nothing recorded reads as never exported', () {
    expect(store.lastExport(), isNull);
  });

  test('a recorded export reads back to the millisecond, in UTC', () {
    final at = DateTime.utc(2026, 10, 17, 9, 30, 15, 250);
    store.recordExport(at);
    expect(store.lastExport(), at);
    expect(store.lastExport()!.isUtc, isTrue);
  });

  test('a later export replaces the earlier one', () {
    store
      ..recordExport(DateTime.utc(2026, 1, 1))
      ..recordExport(DateTime.utc(2026, 2, 1));
    expect(store.lastExport(), DateTime.utc(2026, 2, 1));
  });

  test('a file that does not parse is an error, not "never"', () {
    File('${dir.path}/backup_state.json').writeAsStringSync('{"v":1');
    expect(store.lastExport, throwsFormatException);
  });

  test('an unknown version is an error', () {
    File('${dir.path}/backup_state.json')
        .writeAsStringSync('{"v":2,"lastExportUtcMs":1}');
    expect(store.lastExport, throwsFormatException);
  });
}
