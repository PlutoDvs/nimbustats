import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import 'support/goal_fixture.dart';

void main() {
  test('an empty database answers zero for both watermarks', () async {
    final db = openTestDatabase();
    addTearDown(db.close);

    expect(await db.goalPeriodResultsDao.moneyWatermark(), 0);
    expect(await db.goalPeriodResultsDao.trackerWatermark('cig'), 0);
  });

  group('the money watermark', () {
    late GoalFixture f;
    late String spent;

    setUp(() async {
      f = await GoalFixture.open();
      spent = await f.expense(1000, const DateKey(20260105), tags: ['trip']);
      await ageMoneyRows(f.db);
    });
    tearDown(() => f.db.close());

    Future<void> expectMovedBy(Future<void> Function() write) async {
      final before = await f.db.goalPeriodResultsDao.moneyWatermark();
      await write();
      expect(await f.db.goalPeriodResultsDao.moneyWatermark(),
          greaterThan(before));
    }

    test('moves on an insert',
        () => expectMovedBy(() => f.expense(5, const DateKey(20260106))));

    test(
        'moves on an edit that takes a row out of the scope',
        () => expectMovedBy(() =>
            f.db.transactionsDao.updateTransaction(spent, categoryId: 'rent')));

    test('moves on a soft delete',
        () => expectMovedBy(() => f.db.transactionsDao.softDelete(spent)));

    test('moves when a category moves under another parent',
        () => expectMovedBy(() => f.db.categoriesDao.move('dining', 'rent')));

    test('moves when a tag moves under another parent',
        () => expectMovedBy(() => f.db.tagsDao.move('trip', 'work')));

    test(
        'moves when a transaction is re-saved with new tags',
        () => expectMovedBy(() async {
              // TransactionRepository.update writes the row, then the links
              // (plan Decision 5). The stamp is the row's, which is why the
              // watermark needs no tag-link term.
              await f.db.transactionsDao.updateTransaction(spent);
              await f.db.transactionsDao.setTags(spent, ['work']);
            }));
  });

  group('the tracker watermark', () {
    late GoalFixture f;
    late String entry;

    setUp(() async {
      f = await GoalFixture.open();
      entry = await f.log('cig', const DateKey(20260105));
      await f.log('water', const DateKey(20260105), value: 0.5);
      await ageTrackerEntries(f.db);
    });
    tearDown(() => f.db.close());

    Future<int> mark() => f.db.goalPeriodResultsDao.trackerWatermark('cig');

    test('moves when an entry is edited', () async {
      final before = await mark();
      await f.db.trackerEntriesDao.updateEntry(
        entry,
        value: 2,
        occurredAtUtc: DateTime.utc(2026, 1, 5, 9),
        localDateKey: const DateKey(20260105),
        note: null,
        tzOffsetMinutes: null,
      );
      expect(await mark(), greaterThan(before));
    });

    test('moves when an entry is deleted', () async {
      final before = await mark();
      await f.db.trackerEntriesDao.softDelete(entry);
      expect(await mark(), greaterThan(before));
    });

    test("another tracker's entry leaves it alone", () async {
      final before = await mark();
      await f.log('water', const DateKey(20260106));
      expect(await mark(), before);
    });
  });
}
