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
    // crypto is Phase 2A's one new runtime dependency. captured_messages
    // .dedup_hash is UNIQUE at the database level, so a hash collision does
    // not merely risk a duplicate -- it makes the second message unstorable
    // and loses the raw text. SHA-256 rather than a hand-rolled 64-bit hash
    // is the difference between that being impossible and being unlikely.
    // Asserting it here keeps the decision visible in the boundary rules
    // rather than buried in a pubspec.
    expect(deps, contains('crypto'));
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

  test('tracker code aggregates only through the analytics engine', () {
    // Phase 4b's definition of done, kept as a test rather than a one-off grep
    // so that no later change can quietly grow a second query engine beside
    // Phase 3's. Comment lines are skipped: they may name what they avoid.
    final aggregate = RegExp(r'\b(SUM|COUNT|AVG|MIN|MAX)\s*\(|GROUP BY'
        r'|\.(sum|count|avg|min|max)\(\)|\.groupBy\(');
    // Placing a new tracker at the end of the list as it is written. It reads
    // one column's maximum to choose a position and answers no analytical
    // question.
    const allowed = {'final highest = _db.trackers.sortOrder.max();'};

    final offenders = <String>[];
    for (final dir in [
      'packages/nimbus_data/lib/src/trackers',
      'app/lib/features/trackers',
    ]) {
      final files = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));
      for (final file in files) {
        for (final (index, line) in file.readAsLinesSync().indexed) {
          final code = line.trim();
          if (code.startsWith('//')) continue;
          if (aggregate.hasMatch(code) && !allowed.contains(code)) {
            offenders.add('${file.path}:${index + 1}: $code');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'aggregation belongs in AnalyticsEngine:\n'
            '${offenders.join('\n')}');
  });
}
