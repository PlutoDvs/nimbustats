import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps Override out of the main barrel.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/app.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';

/// Pumps the real app against a fresh in-memory database.
///
/// Every widget test in this package goes through here, so what is under test
/// is the wiring that actually ships. A hand-rolled MaterialApp per test would
/// keep passing while the real shell was broken, which is the failure mode this
/// helper exists to prevent.
Future<AppDatabase> pumpApp(
  WidgetTester tester, {
  AppDatabase? database,
  List<Override> overrides = const [],
  String? initialLocation,
  Locale locale = const Locale('en'),
  void Function(ProviderContainer container)? onContainer,
}) async {
  final db = database ?? AppDatabase.openInMemory();
  if (database == null) addTearDown(db.close);

  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  onContainer?.call(container);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: NimbuStatsApp(
        initialLocation: initialLocation,
        overrideLocale: locale,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}
