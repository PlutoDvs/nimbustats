import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import 'support/tracker_rows.dart';

void main() {
  late AppDatabase db;
  late TrackerEntriesDao dao;

  setUp(() async {
    db = openTestDatabase();
    dao = db.trackerEntriesDao;
    await db.trackersDao.insertAll([
      newTracker('cig', TrackerType.counter),
      newTracker('gym', TrackerType.boolean),
      newTracker('yoga', TrackerType.boolean),
      newTracker('water', TrackerType.quantity, perTapValue: 0.25),
    ]);
  });
  tearDown(() => db.close());

  test('insertEntry returns the stored entry', () async {
    final result = await dao.insertEntry(
        newEntry('e1', 'water', value: 2.5, note: 'after lunch'));

    expect(
      (result as EntryLogged).entry,
      TrackerEntry(
        id: 'e1',
        trackerId: 'water',
        value: 2.5,
        occurredAtUtc: morning,
        localDateKey: today,
        note: 'after lunch',
      ),
    );
  });

  group('one live "done" per day', () {
    test('a second done on the same day is refused and writes nothing',
        () async {
      expect(await dao.insertEntry(newEntry('a', 'gym', oncePerDay: true)),
          isA<EntryLogged>());
      expect(await dao.insertEntry(newEntry('b', 'gym', oncePerDay: true)),
          isA<AlreadyDoneToday>());
      expect(await liveEntries(db, 'gym'), 1);
    });

    test('a fast double-tap logs exactly one', () async {
      final results = await Future.wait([
        dao.insertEntry(newEntry('a', 'gym', oncePerDay: true)),
        dao.insertEntry(newEntry('b', 'gym', oncePerDay: true)),
      ]);
      expect(results.whereType<EntryLogged>(), hasLength(1));
      expect(results.whereType<AlreadyDoneToday>(), hasLength(1));
    });

    test('a soft-deleted done no longer holds the day', () async {
      await dao.insertEntry(newEntry('a', 'gym', oncePerDay: true));
      await dao.softDelete('a');
      expect(await dao.insertEntry(newEntry('b', 'gym', oncePerDay: true)),
          isA<EntryLogged>());
    });

    test('the rule is per tracker and per day, and only for flagged rows',
        () async {
      await dao.insertEntry(newEntry('a', 'gym', oncePerDay: true));
      expect(
          await dao.insertEntry(newEntry('b', 'gym',
              oncePerDay: true, day: today.addDays(1))),
          isA<EntryLogged>());
      expect(await dao.insertEntry(newEntry('c', 'yoga', oncePerDay: true)),
          isA<EntryLogged>());
      for (final id in ['d', 'e', 'f']) {
        expect(await dao.insertEntry(newEntry(id, 'cig')), isA<EntryLogged>());
      }
    });

    test('an edit that moves a done onto a done day is refused', () async {
      await dao.insertEntry(newEntry('mon', 'gym', oncePerDay: true));
      await dao.insertEntry(newEntry('tue', 'gym',
          oncePerDay: true, day: today.addDays(1)));

      final result = await dao.updateEntry('tue',
          value: 1,
          occurredAtUtc: morning,
          localDateKey: today,
          note: null,
          tzOffsetMinutes: null);

      expect(result, DayWrite.dayAlreadyDone);
      expect((await dao.byId('tue'))!.localDateKey, today.addDays(1));
    });

    test('an undo onto a day marked done again is refused, all or nothing',
        () async {
      await dao.insertEntry(newEntry('first', 'gym', oncePerDay: true));
      final cleared = await dao.softDeleteOn('gym', today);
      await dao.insertEntry(newEntry('again', 'gym', oncePerDay: true));

      expect(await dao.restore(cleared), DayWrite.dayAlreadyDone);
      expect(await liveEntries(db, 'gym'), 1);
      expect(await dao.byId('first'), isNull);
    });
  });

  test('updateEntry rewrites value, time, day and note', () async {
    await dao.insertEntry(newEntry('e1', 'water', value: 0.25));
    final later = morning.add(const Duration(hours: 2));

    expect(
        await dao.updateEntry('e1',
            value: 0.5,
            occurredAtUtc: later,
            localDateKey: today.addDays(-1),
            note: 'fixed',
            tzOffsetMinutes: null),
        DayWrite.written);
    expect(
      await dao.byId('e1'),
      TrackerEntry(
        id: 'e1',
        trackerId: 'water',
        value: 0.5,
        occurredAtUtc: later,
        localDateKey: today.addDays(-1),
        note: 'fixed',
      ),
    );
  });

  test('a write to an unknown or deleted entry says so', () async {
    expect(() => dao.softDelete('nope'), throwsStateError);
    expect(
        () => dao.updateEntry('nope',
            value: 1, occurredAtUtc: morning, localDateKey: today, note: null,
            tzOffsetMinutes: null),
        throwsStateError);
    expect(() => dao.restore(['nope']), throwsStateError);
  });

  test('softDeleteOn removes the day and restore brings exactly it back',
      () async {
    await dao.insertEntry(newEntry('a', 'cig'));
    await dao.insertEntry(newEntry('b', 'cig'));
    await dao.insertEntry(newEntry('old', 'cig', day: today.addDays(-1)));

    final cleared = await dao.softDeleteOn('cig', today);
    expect(cleared.toSet(), {'a', 'b'});
    expect(await liveEntries(db, 'cig'), 1);

    expect(await dao.restore(cleared), DayWrite.written);
    expect(await liveEntries(db, 'cig'), 3);
  });

  test("day totals sum each tracker's live entries for that day only",
      () async {
    await dao.insertEntry(newEntry('c1', 'cig'));
    await dao.insertEntry(newEntry('c2', 'cig'));
    await dao.insertEntry(newEntry('c3', 'cig'));
    await dao.softDelete('c3');
    await dao.insertEntry(newEntry('old', 'cig', day: today.addDays(-1)));
    await dao.insertEntry(newEntry('w1', 'water', value: 0.25));
    await dao.insertEntry(newEntry('w2', 'water', value: 0.5));

    expect(await dao.watchDayTotals(today).first, {'cig': 2.0, 'water': 0.75});
    expect(await dao.watchDayTotals(today.addDays(1)).first, isEmpty);
  });

  test('dayTotals reads the same totals once, without a subscription',
      () async {
    await dao.insertEntry(newEntry('c1', 'cig'));
    await dao.insertEntry(newEntry('w1', 'water', value: 0.25));

    expect(await dao.dayTotals(today), {'cig': 1.0, 'water': 0.25});
    expect(await dao.dayTotals(today.addDays(1)), isEmpty);
  });

  test('day totals follow writes', () async {
    final totals = dao.watchDayTotals(today);
    final seen = expectLater(
        totals,
        emitsInOrder([
          <String, double>{},
          {'cig': 1.0},
        ]));
    await pumpEventQueue();
    await dao.insertEntry(newEntry('c1', 'cig'));
    await seen;
  });

  group('history pages', () {
    setUp(() async {
      // Five entries; two share a timestamp, so id breaks the tie.
      await dao.insertEntry(newEntry('e1', 'cig', at: morning));
      await dao.insertEntry(newEntry('e2', 'cig', at: morning));
      for (final (i, id) in ['e3', 'e4', 'e5'].indexed) {
        await dao.insertEntry(
            newEntry(id, 'cig', at: morning.add(Duration(minutes: i + 1))));
      }
    });

    test('newest first, continued from a cursor without repeats or gaps',
        () async {
      final first = await dao.pageAfter('cig', limit: 3);
      expect(first.map((e) => e.id), ['e5', 'e4', 'e3']);

      final last = first.last;
      final rest = await dao.pageAfter('cig',
          after: (occurredAtUtc: last.occurredAtUtc, id: last.id), limit: 3);
      expect(rest.map((e) => e.id), ['e2', 'e1']);
    });

    test('a write between two pages neither repeats nor drops a row',
        () async {
      final first = await dao.pageAfter('cig', limit: 2);
      await dao.insertEntry(newEntry('new', 'cig',
          at: morning.add(const Duration(hours: 1))));

      final last = first.last;
      final rest = await dao.pageAfter('cig',
          after: (occurredAtUtc: last.occurredAtUtc, id: last.id), limit: 10);
      expect(rest.map((e) => e.id), ['e3', 'e2', 'e1']);
    });
  });

  test('changes fires on an entry write', () async {
    final fired = expectLater(dao.changes(), emits(anything));
    await dao.insertEntry(newEntry('c1', 'cig'));
    await fired;
  });

  group('query plans', () {
    // Asserted on the plan, not on a stopwatch, so the guarantee survives a
    // fast machine.
    test('day totals seek the day index and need no temp B-tree', () async {
      final plan = await planOf(db, dao.dayTotalsQuery(today));
      expect(plan, contains('idx_tracker_entries_day'), reason: plan);
      expect(plan, isNot(contains('SCAN tracker_entries')), reason: plan);
      expect(plan, isNot(contains('TEMP B-TREE')), reason: plan);
    });

    test('history pages walk the history index in order', () async {
      for (final after in [
        null,
        (occurredAtUtc: morning, id: 'e1'),
      ]) {
        final plan = await planOf(db, dao.historyQuery('cig', after: after));
        expect(plan, contains('idx_tracker_entries_history'), reason: plan);
        expect(plan, isNot(contains('TEMP B-TREE')), reason: plan);
      }
    });
  });

  group('timezone offset', () {
    test('insertEntry stores the offset it is given', () async {
      await dao.insertEntry(newEntry('ny', 'cig', tzOffsetMinutes: -240));
      expect(await offsetOf(db, 'ny'), -240);
    });

    test('updateEntry leaves the offset alone given null, else rewrites it',
        () async {
      await dao.insertEntry(newEntry('e', 'cig'));

      await dao.updateEntry('e',
          value: 1,
          occurredAtUtc: morning,
          localDateKey: today,
          note: 'kept',
          tzOffsetMinutes: null);
      expect(await offsetOf(db, 'e'), 210);

      await dao.updateEntry('e',
          value: 1,
          occurredAtUtc: morning,
          localDateKey: today,
          note: 'moved',
          tzOffsetMinutes: -240);
      expect(await offsetOf(db, 'e'), -240);
    });
  });
}
