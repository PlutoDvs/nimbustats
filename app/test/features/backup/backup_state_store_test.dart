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

  group('which way the undo copy points', () {
    void write(String json) =>
        File('${dir.path}/backup_state.json').writeAsStringSync(json);

    test('no file, or no field, is an undo', () {
      expect(store.undoRedoes(), isFalse);
      write('{"v":1,"lastExportUtcMs":1}');
      expect(store.undoRedoes(), isFalse);
    });

    test('a recorded value reads back', () {
      store.setUndoRedoes(true);
      expect(store.undoRedoes(), isTrue);
      store.setUndoRedoes(false);
      expect(store.undoRedoes(), isFalse);
    });

    test('an export never recorded reads as never, beside the flag', () {
      write('{"v":1,"undoRedoes":true}');
      expect(store.lastExport(), isNull);
    });

    test('each write keeps the other field', () {
      final at = DateTime.utc(2026, 10, 17, 9, 30);
      store
        ..recordExport(at)
        ..setUndoRedoes(true);
      expect(store.lastExport(), at);
      store.recordExport(DateTime.utc(2026, 11, 1));
      expect(store.undoRedoes(), isTrue);
    });

    test('a field of the wrong type is an error, for either read', () {
      for (final json in const [
        '{"v":1,"undoRedoes":"yes"}',
        '{"v":1,"lastExportUtcMs":"1"}',
        '{"v":1,"lastExportUtcMs":null}',
        '{"v":1,"other":1}',
        '{"v":2,"undoRedoes":true}',
        '[]',
      ]) {
        write(json);
        expect(store.lastExport, throwsFormatException, reason: json);
        expect(store.undoRedoes, throwsFormatException, reason: json);
        expect(() => store.setUndoRedoes(true), throwsFormatException,
            reason: json);
      }
    });
  });
}
