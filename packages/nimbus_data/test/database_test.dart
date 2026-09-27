import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  test('opens at schema version 21', () async {
    // Phase 3 took v20 for saved_views and v21 for its period columns. Ranges
    // are reserved per phase, so this number jumps rather than increments;
    // see the registry in CONVENTIONS.md.
    expect(db.schemaVersion, 21);
    await db.customSelect('SELECT 1').get();
  });

  test('settings round-trip a value', () async {
    await db.settingsDao.put('currency', 'IRT');
    expect(await db.settingsDao.get('currency'), 'IRT');
  });

  test('settings return null for an unknown key rather than throwing', () async {
    expect(await db.settingsDao.get('nope'), isNull);
  });

  test('deleteKeys removes exactly the keys named', () async {
    await db.settingsDao.put('a', '1');
    await db.settingsDao.put('b', '2');
    await db.settingsDao.put('c', '3');

    await db.settingsDao.deleteKeys(const ['a', 'c', 'never-written']);

    expect(await db.settingsDao.getAll(), {'b': '2'});
  });

  test('putting a key twice overwrites rather than duplicating', () async {
    await db.settingsDao.put('calendar', 'jalali');
    await db.settingsDao.put('calendar', 'gregorian');
    expect(await db.settingsDao.get('calendar'), 'gregorian');
    final rows = await db.customSelect(
      "SELECT COUNT(*) AS c FROM settings WHERE key = 'calendar'",
    ).getSingle();
    expect(rows.data['c'], 1);
  });

  test('foreign key enforcement is on for every connection', () async {
    // SQLite defaults this OFF per connection. Task 9 onward relies on it to
    // reject orphan rows; without this assertion the migration strategy could
    // stop setting it and nothing would fail until data was already corrupt.
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.data.values.first, 1);
  });

  group('type converters', () {
    // No table stores these yet -- the first ones land in Task 9. They are
    // pinned here so the SQL representation is fixed before any row is written
    // in it: a converter change after the fact silently reinterprets stored
    // integers.
    test('DateKey survives a round-trip as its yyyymmdd integer', () {
      const converter = DateKeyConverter();
      final key = DateKey.fromParts(2026, 8, 21);
      expect(converter.toSql(key), 20260821);
      expect(converter.fromSql(20260821), key);
    });

    test('Money survives a round-trip as minor units, negatives included', () {
      const converter = MoneyConverter();
      expect(converter.toSql(const Money(12345)), 12345);
      expect(converter.fromSql(12345), const Money(12345));
      expect(converter.toSql(const Money(-500)), -500);
      expect(converter.fromSql(-500), const Money(-500));
    });
  });
}
