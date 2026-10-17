import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android files no host test can run (spec §4.1), pinned as text. The
/// two rule files must never drift apart, and an `<include>` would silently
/// turn every other file off.
void main() {
  const res = 'android/app/src/main/res/xml';
  const excluded = {
    'app_flutter/nimbustats.sqlite-shm',
    'app_flutter/nimbustats.pre-restore.sqlite',
    'app_flutter/nimbustats.pre-restore.sqlite.part',
  };

  Set<String> excludes(String xml) =>
      RegExp(r'<exclude domain="root" path="([^"]+)"')
          .allMatches(xml)
          .map((match) => match[1]!)
          .toSet();

  String section(String xml, String tag) =>
      RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml)![1]!;

  test('both rule files exclude exactly the local-only files', () {
    final legacy = File('$res/backup_rules.xml').readAsStringSync();
    final modern = File('$res/data_extraction_rules.xml').readAsStringSync();

    expect(excludes(legacy), excluded);
    expect(excludes(section(modern, 'cloud-backup')), excluded);
    expect(excludes(section(modern, 'device-transfer')), excluded);
    expect('$legacy$modern', isNot(contains('<include')));
  });

  test('the manifest wires the agent and both rule files', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    for (final attribute in const [
      'android:allowBackup="true"',
      'android:fullBackupOnly="true"',
      'android:backupAgent=".backup.NimbusBackupAgent"',
      'android:fullBackupContent="@xml/backup_rules"',
      'android:dataExtractionRules="@xml/data_extraction_rules"',
    ]) {
      expect(manifest, contains(attribute));
    }
  });
}
