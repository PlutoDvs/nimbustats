// Fakes throw whatever object a test sets, including non-Exceptions.
// ignore_for_file: only_throw_errors

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';

/// [BackupService] without files or crypto: it records each call and plays
/// the outcome a test sets.
class FakeBackupService implements BackupService {
  /// The passphrase [prepare] accepts; any other is [WrongPassphrase].
  static const goodPassphrase = 'correct horse';

  final calls = <String>[];
  String? lastPassphrase;

  Object? exportError;

  /// Holds [exportTo] open until completed, to test the working state.
  Completer<void>? exportGate;
  Object? headerError;
  Object? prepareError;
  Object? undoError;
  bool undoable = false;
  int bytes = 4 * 1024 * 1024;
  BackupHeader header = BackupHeader(
    schemaVersion: 40,
    createdAt: DateTime.utc(2026, 10, 1, 9, 30),
    kdf: KdfParams.standard,
    salt: Uint8List(16),
    nonce: Uint8List(12),
    keyCheck: Uint8List(16),
  );

  @override
  late final String cacheDir = _tempCacheDir();

  /// Created on first use, inside a test, and deleted when that test ends.
  static String _tempCacheDir() {
    final dir = Directory.systemTemp.createTempSync('nimbus_fake_backup');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return dir.path;
  }

  @override
  bool get canUndo => undoable;

  @override
  Future<int> databaseBytes() async => bytes;

  @override
  Future<void> sweep() async => calls.add('sweep');

  @override
  Future<void> exportTo(String outPath, String passphrase) async {
    calls.add('exportTo');
    lastPassphrase = passphrase;
    await exportGate?.future;
    if (exportError case final error?) throw error;
    File(outPath).writeAsBytesSync(const [1, 2, 3]);
  }

  @override
  Future<BackupHeader> readHeader(String path) async {
    calls.add('readHeader');
    if (headerError case final error?) throw error;
    return header;
  }

  @override
  Future<PreparedRestore> prepare(String path, String passphrase) async {
    calls.add('prepare');
    if (passphrase != goodPassphrase) throw const WrongPassphrase();
    if (prepareError case final error?) throw error;
    return PreparedRestore(path: path, createdAt: header.createdAt);
  }

  @override
  Future<void> restore(PreparedRestore prepared) async {
    calls.add('restore');
    undoable = true;
  }

  @override
  Future<void> undo() async {
    calls.add('undo');
    if (undoError case final error?) throw error;
    undoable = false;
  }

  @override
  Future<void> discard(PreparedRestore prepared) async => calls.add('discard');
}
