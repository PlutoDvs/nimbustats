// Fakes throw whatever object a test sets, including non-Exceptions.
// ignore_for_file: only_throw_errors

import 'dart:async';

import 'package:nimbustats/features/backup/data/backup_channel.dart';

/// [BackupChannel] without Android: records each call and answers as a test
/// sets.
class FakeBackupChannel implements BackupChannel {
  final calls = <String>[];

  /// What Save's picker answers: true saved, false cancelled.
  bool saveAnswer = true;

  /// When set, Save's picker stays open until it completes.
  Completer<void>? saveGate;

  /// The cache copy Open answers with. Null is a cancelled picker.
  String? picked;

  /// Thrown by the next call, then cleared.
  Object? error;

  @override
  Future<bool> saveDocument(String path) async {
    calls.add('saveDocument $path');
    _fail();
    await saveGate?.future;
    return saveAnswer;
  }

  @override
  Future<void> shareFile(String path) async {
    calls.add('shareFile $path');
    _fail();
  }

  @override
  Future<String?> openDocument() async {
    calls.add('openDocument');
    _fail();
    return picked;
  }

  void _fail() {
    final failure = error;
    if (failure == null) return;
    error = null;
    throw failure;
  }
}
