import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import 'support/tracker_rows.dart';

void main() {
  late AppDatabase db;
  late TrackersDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = db.trackersDao;
  });
  tearDown(() => db.close());

  Future<List<String>> liveIds({bool archived = false}) async =>
      [for (final t in await dao.watchLive(archived: archived).first) t.id];

  test('insertAll round-trips every field as a domain Tracker', () async {
    await dao.insertAll(
        [newTracker('water', TrackerType.quantity, unit: 'L', perTapValue: 0.25)]);

    expect(
      await dao.byId('water'),
      const Tracker(
        id: 'water',
        name: 'water',
        iconKey: 'tag',
        color: 0xFF1565C0,
        type: TrackerType.quantity,
        unit: 'L',
        perTapValue: 0.25,
        archived: false,
        sortOrder: 0,
      ),
    );
  });

  test('insertAll appends after existing trackers, in the order given',
      () async {
    await dao.insertAll([newTracker('a', TrackerType.counter)]);
    await dao.insertAll([
      newTracker('b', TrackerType.boolean),
      newTracker('c', TrackerType.duration),
    ]);

    expect(await liveIds(), ['a', 'b', 'c']);
    expect((await dao.byId('c'))!.sortOrder, 2);
  });

  test('insertAll is one transaction: a bad row inserts none', () async {
    await expectLater(
      dao.insertAll([
        newTracker('ok', TrackerType.counter),
        newTracker('ok', TrackerType.counter), // duplicate primary key
      ]),
      throwsA(anything),
    );
    expect(await liveIds(), isEmpty);
  });

  test('the live lists split archived from unarchived', () async {
    await dao.insertAll([
      newTracker('a', TrackerType.counter),
      newTracker('b', TrackerType.counter),
    ]);
    await dao.setArchived('b', true);

    expect(await liveIds(), ['a']);
    expect(await liveIds(archived: true), ['b']);

    await dao.setArchived('b', false);
    expect(await liveIds(), ['a', 'b']);
  });

  test('reorder makes the given order the stored one', () async {
    await dao.insertAll([
      newTracker('a', TrackerType.counter),
      newTracker('b', TrackerType.counter),
      newTracker('c', TrackerType.counter),
    ]);
    await dao.reorder(['c', 'a', 'b']);
    expect(await liveIds(), ['c', 'a', 'b']);
  });

  test('a write to an unknown tracker says so instead of succeeding',
      () async {
    expect(() => dao.setArchived('nope', true), throwsStateError);
    expect(() => dao.reorder(['nope']), throwsStateError);
    expect(
        () => dao.updateTracker('nope', name: 'x', iconKey: 'tag', color: 0),
        throwsStateError);
  });

  test('updateTracker rewrites appearance and quantity fields in one write',
      () async {
    await dao.insertAll(
        [newTracker('w', TrackerType.quantity, unit: 'L', perTapValue: 0.25)]);
    await dao.updateTracker('w',
        name: 'Water', iconKey: 'water_drop', color: 1, unit: null,
        perTapValue: 0.5);

    final tracker = (await dao.byId('w'))!;
    expect(tracker.name, 'Water');
    expect(tracker.iconKey, 'water_drop');
    expect(tracker.color, 1);
    expect(tracker.unit, isNull);
    expect(tracker.perTapValue, 0.5);
    expect(tracker.type, TrackerType.quantity);
  });

  group('timers', () {
    setUp(() => dao.insertAll([
          newTracker('sleep', TrackerType.duration),
          newTracker('cig', TrackerType.counter),
        ]));

    test('a start is persisted; a second start is refused and changes nothing',
        () async {
      final first = morning.millisecondsSinceEpoch;
      expect(await dao.startTimer('sleep', first), isTrue);
      expect(await dao.startTimer('sleep', first + 5000), isFalse);

      expect((await dao.byId('sleep'))!.timerStartedAtUtc,
          DateTime.fromMillisecondsSinceEpoch(first, isUtc: true));
    });

    test('two racing starts leave exactly one', () async {
      final ms = morning.millisecondsSinceEpoch;
      final results = await Future.wait(
          [dao.startTimer('sleep', ms), dao.startTimer('sleep', ms + 1)]);
      expect(results.where((started) => started), hasLength(1));
    });

    test('a counter cannot start a timer', () async {
      expect(await dao.startTimer('cig', morning.millisecondsSinceEpoch),
          isFalse);
    });

    test('finish clears the start and logs the entry together', () async {
      final ms = morning.millisecondsSinceEpoch;
      await dao.startTimer('sleep', ms);

      expect(
          await dao.finishTimer('sleep',
              startedAtUtcMs: ms,
              entry: newEntry('e1', 'sleep', value: 27000)),
          isTrue);

      expect((await dao.byId('sleep'))!.runningTimer, isNull);
      expect(await liveEntries(db, 'sleep'), 1);
    });

    test('a second finish of the same start logs nothing', () async {
      final ms = morning.millisecondsSinceEpoch;
      await dao.startTimer('sleep', ms);
      await dao.finishTimer('sleep',
          startedAtUtcMs: ms, entry: newEntry('e1', 'sleep', value: 60));

      expect(
          await dao.finishTimer('sleep',
              startedAtUtcMs: ms, entry: newEntry('e2', 'sleep', value: 60)),
          isFalse);
      expect(await liveEntries(db, 'sleep'), 1);
    });

    test('finish without an entry only clears the start', () async {
      final ms = morning.millisecondsSinceEpoch;
      await dao.startTimer('sleep', ms);
      expect(await dao.finishTimer('sleep', startedAtUtcMs: ms, entry: null),
          isTrue);

      expect((await dao.byId('sleep'))!.runningTimer, isNull);
      expect(await liveEntries(db, 'sleep'), 0);
    });

    test('a failed entry insert leaves the timer running', () async {
      // The proof that stop is one transaction: an entry pointing at a
      // missing tracker fails its foreign key, and the clear must roll back
      // with it.
      final ms = morning.millisecondsSinceEpoch;
      await dao.startTimer('sleep', ms);

      await expectLater(
        dao.finishTimer('sleep',
            startedAtUtcMs: ms, entry: newEntry('e1', 'missing', value: 60)),
        throwsA(anything),
      );
      expect((await dao.byId('sleep'))!.runningTimer, isNotNull);
    });
  });

  test("the live list's plan uses idx_trackers_live", () async {
    final plan = await planOf(db, dao.liveQuery(archived: false));
    expect(plan, contains('idx_trackers_live'), reason: 'plan: $plan');
  });
}
