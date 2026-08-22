import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Reads the runtime (non-dev) dependency names declared by a package.
///
/// Boundaries are asserted here rather than left to convention because folder
/// conventions erode under deadline pressure and pubspec rules do not.
Set<String> runtimeDeps(String packagePath) {
  final file = File('$packagePath/pubspec.yaml');
  if (!file.existsSync()) {
    fail('missing pubspec at $packagePath');
  }
  final doc = loadYaml(file.readAsStringSync()) as YamlMap;
  final deps = doc['dependencies'];
  if (deps is! YamlMap) return <String>{};
  return deps.keys.cast<String>().toSet();
}

void main() {
  test('nimbus_domain is pure Dart with no infrastructure dependencies', () {
    final deps = runtimeDeps('packages/nimbus_domain');
    for (final forbidden in [
      'flutter',
      'drift',
      'sqlite3',
      'flutter_riverpod',
      'nimbus_data',
      'nimbus_design',
    ]) {
      expect(deps, isNot(contains(forbidden)),
          reason: 'nimbus_domain must stay pure; remove $forbidden');
    }
  });

  test('nimbus_data is pure Dart and never reaches the UI', () {
    final deps = runtimeDeps('packages/nimbus_data');
    for (final forbidden in [
      'flutter',
      'flutter_riverpod',
      'path_provider',
      'nimbus_design',
    ]) {
      expect(deps, isNot(contains(forbidden)),
          reason: 'nimbus_data must stay pure; remove $forbidden');
    }
    expect(deps, contains('nimbus_domain'));
  });

  test('app reaches the database only through nimbus_data', () {
    // `app` may depend on all three packages -- that is the point of it. What
    // it must not do is depend on drift or sqlite3 directly: the moment a
    // screen can construct a NativeDatabase, the "UI cannot import the
    // database" boundary is decoration rather than a rule. Database
    // construction lives behind AppDatabase.openAtPath / .openInMemory.
    final deps = runtimeDeps('app');
    for (final forbidden in ['drift', 'sqlite3']) {
      expect(deps, isNot(contains(forbidden)),
          reason: 'app must open the database through AppDatabase.openAtPath; '
              'remove $forbidden');
    }
    expect(deps, contains('nimbus_domain'));
    expect(deps, contains('nimbus_data'));
    expect(deps, contains('nimbus_design'));
    // go_router is Phase 1's one new runtime dependency. Asserting it is
    // present keeps the routing decision visible to anyone reading the
    // boundary rules rather than buried in a pubspec.
    expect(deps, contains('go_router'));
  });

  test('nimbus_design never touches persistence', () {
    final deps = runtimeDeps('packages/nimbus_design');
    for (final forbidden in ['drift', 'sqlite3', 'nimbus_data']) {
      expect(deps, isNot(contains(forbidden)),
          reason: 'nimbus_design is presentation only; remove $forbidden');
    }
  });
}
