import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dartSources(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.endsWith('.g.dart'));

void main() {
  test('no confirmation dialog exists anywhere in the app', () {
    // "Undo, never confirm" is an interaction rule, and rules that are only
    // enforced by review come back the first time someone is in a hurry.
    //
    // showDatePicker and showModalBottomSheet are deliberately not listed:
    // neither asks a user to confirm something they already chose to do.
    final offenders = <String>[];
    for (final file in _dartSources('lib')) {
      final source = file.readAsStringSync();
      for (final pattern in [
        'showDialog(',
        'AlertDialog(',
        'CupertinoAlertDialog(',
      ]) {
        if (source.contains(pattern)) offenders.add('${file.path}: $pattern');
      }
    }
    expect(offenders, isEmpty,
        reason: 'destructive actions use nimbusUndoSnackBar:\n'
            '${offenders.join('\n')}');
  });

  test('presentation code never calls a DAO directly', () {
    // The single-write-path guarantee. A screen that reached past the
    // repository would bypass tag usage counts, the stamped currency, and the
    // Uncategorized default -- and nothing would fail until a number looked
    // wrong months later.
    final offenders = <String>[];
    for (final file in _dartSources('lib')) {
      if (!file.path.contains('presentation')) continue;
      final source = file.readAsStringSync();
      for (final pattern in [
        'Dao.',
        'categoriesDao',
        'tagsDao',
        'transactionsDao',
        'paymentMethodsDao',
        'settingsDao',
        'trackersDao',
        'trackerEntriesDao',
      ]) {
        if (source.contains(pattern)) offenders.add('${file.path}: $pattern');
      }
    }
    expect(offenders, isEmpty,
        reason: 'presentation talks to repositories, not DAOs:\n'
            '${offenders.join('\n')}');
  });

  test('no raw Color literal outside nimbus_design', () {
    // Colours come from tokens, so swapping in a real design sheet stays an
    // edit to two files rather than a sweep through every screen.
    //
    // `Color(row.color)` is fine and deliberately not matched: that is a
    // stored value being rendered, not a colour being chosen here.
    final offenders = <String>[];
    final literal = RegExp(r'Color\(0x');
    for (final file in _dartSources('lib')) {
      if (literal.hasMatch(file.readAsStringSync())) offenders.add(file.path);
    }
    expect(offenders, isEmpty,
        reason: 'colours come from tokens so a token-sheet swap is one file:\n'
            '${offenders.join('\n')}');
  });

  test('the app package never imports drift', () {
    // The same boundary architecture_test.dart asserts, checked here from the
    // app side so a screen cannot quietly acquire a Value<T> or a Companion.
    final offenders = <String>[];
    for (final file in _dartSources('lib')) {
      final source = file.readAsStringSync();
      if (source.contains("package:drift/") ||
          source.contains("package:sqlite3/")) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'the database stays behind nimbus_data:\n'
            '${offenders.join('\n')}');
  });
}
