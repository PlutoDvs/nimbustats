import 'package:flutter_riverpod/flutter_riverpod.dart';
// ProviderException is not in the main barrel; Riverpod 3 keeps it in misc.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';

void main() {
  test('the database provider refuses to guess a database', () {
    // A provider that silently created an in-memory database when the real one
    // was missing would turn a bootstrap failure into silent data loss: the
    // app would run perfectly and write the user's expenses nowhere.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      () => container.read(appDatabaseProvider),
      throwsA(
        // Riverpod 3 wraps whatever a provider throws in a ProviderException.
        // The wrapper is incidental; what this test is about is the cause and
        // the fact that it explains how to fix itself.
        isA<ProviderException>().having(
          (e) => e.exception,
          'exception',
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('overridden'), contains('openInMemory')),
          ),
        ),
      ),
    );
  });

  test('an overridden provider hands back a queryable database', () async {
    // Also proves sqlite3 resolves under `flutter test` on this host, which is
    // the one part of the app-layer test setup that could fail for
    // environmental rather than logical reasons.
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final resolved = container.read(appDatabaseProvider);
    expect(resolved, same(db));
    await resolved.settingsDao.put('locale', 'fa');
    expect(await resolved.settingsDao.get('locale'), 'fa');
  });
}
