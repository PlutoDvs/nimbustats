import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_clock.dart';
import 'package:nimbustats/features/trackers/data/tracker_draft.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';

import 'support/tracker_fixture.dart';

void main() {
  late AppDatabase db;
  late FakeClock fake;
  late TrackerRepository repo;

  setUp(() {
    db = AppDatabase.openInMemory();
    fake = FakeClock();
    repo = repositoryFor(db, fake);
  });
  tearDown(() => db.close());

  Future<List<TrackerEntry>> entriesOf(String id) async =>
      (await repo.entriesPage(id, limit: 1000)).items;

  group('create', () {
    test('trims the name and drops a blank unit', () async {
      final created = await repo.create(const TrackerDraft(
          name: '  Water ',
          iconKey: 'water_drop',
          color: 1,
          type: TrackerType.quantity,
          unit: '  ',
          perTapValue: 0.25));
      expect(created.name, 'Water');
      expect(created.unit, isNull);
    });

    test('refuses a blank name and definitions that do not fit the type',
        () async {
      expect(
          () => repo.create(const TrackerDraft(
              name: ' ', iconKey: 'tag', color: 1, type: TrackerType.counter)),
          throwsArgumentError);
      expect(
          () => repo.create(const TrackerDraft(
              name: 'W',
              iconKey: 'tag',
              color: 1,
              type: TrackerType.quantity)),
          throwsArgumentError);
      expect(
          () => repo.create(const TrackerDraft(
              name: 'C',
              iconKey: 'tag',
              color: 1,
              type: TrackerType.counter,
              unit: 'L')),
          throwsArgumentError);
    });

    test('createAll keeps the order and appends after existing trackers',
        () async {
      await repo.create(cigarettes);
      await repo.createAll([gym, water]);
      expect([for (final t in await repo.watchTrackers().first) t.name],
          ['Cigarettes', 'Gym', 'Water']);
    });
  });

  group('logEntry', () {
    test('a counter logs one, as many times as it is tapped', () async {
      final cig = await repo.create(cigarettes);
      await repo.logEntry(cig.id);
      await repo.logEntry(cig.id);
      expect(await repo.totalOn(cig.id, repo.today()), 2);
    });

    test('a boolean logs done once a day; the second tap is a result',
        () async {
      final g = await repo.create(gym);
      expect(await repo.logEntry(g.id), isA<EntryLogged>());
      expect(await repo.logEntry(g.id), isA<AlreadyDoneToday>());
      expect(await entriesOf(g.id), hasLength(1));
    });

    test('a quantity logs its per-tap amount, or the amount given', () async {
      final w = await repo.create(water);
      await repo.logEntry(w.id);
      await repo.logEntry(w.id, value: 1.5);
      expect(await repo.totalOn(w.id, repo.today()), 1.75);
    });

    test('values that do not fit the type are refused', () async {
      final cig = await repo.create(cigarettes);
      final w = await repo.create(water);
      final s = await repo.create(sleep);
      expect(() => repo.logEntry(cig.id, value: 2), throwsArgumentError);
      expect(() => repo.logEntry(w.id, value: 0), throwsArgumentError);
      // A duration has no per-tap value: its taps go through the timer.
      expect(() => repo.logEntry(s.id), throwsArgumentError);
    });

    test('an unknown tracker is a stale id, not a silent no-op', () async {
      expect(() => repo.logEntry('nope'), throwsStateError);
    });

    test('the note is trimmed, and a blank one is none', () async {
      final cig = await repo.create(cigarettes);
      final logged =
          await repo.logEntry(cig.id, note: '  after lunch ') as EntryLogged;
      expect(logged.entry.note, 'after lunch');
      final blank = await repo.logEntry(cig.id, note: '   ') as EntryLogged;
      expect(blank.entry.note, isNull);
    });
  });

  group('the local date is taken at write time', () {
    // 2026-10-04 22:00 UTC is already the 5th in Tehran, still the 4th in
    // New York.
    final lateEvening = DateTime.utc(2026, 10, 4, 22);

    test('from the device timezone, not from UTC', () async {
      final cig = await repo.create(cigarettes);
      final tehran =
          await repo.logEntry(cig.id, at: lateEvening) as EntryLogged;
      fake.offset = FakeClock.newYork;
      final newYork =
          await repo.logEntry(cig.id, at: lateEvening) as EntryLogged;

      expect(tehran.entry.localDateKey, const DateKey(20261005));
      expect(newYork.entry.localDateKey, const DateKey(20261004));
    });

    test('a flight does not move entries already logged', () async {
      // Correct, and pinned so nobody "fixes" it later: an entry belongs to
      // the local day the user was in when they logged it.
      final cig = await repo.create(cigarettes);
      final before =
          await repo.logEntry(cig.id, at: lateEvening) as EntryLogged;
      fake.offset = FakeClock.newYork;
      await repo.logEntry(cig.id);

      final stored = (await entriesOf(cig.id))
          .singleWhere((e) => e.id == before.entry.id);
      expect(stored.localDateKey, const DateKey(20261005));
    });

    test('editing only the note after a flight keeps the day', () async {
      final cig = await repo.create(cigarettes);
      final logged =
          await repo.logEntry(cig.id, at: lateEvening) as EntryLogged;
      fake.offset = FakeClock.newYork;

      final e = logged.entry;
      await repo.updateEntry(TrackerEntry(
          id: e.id,
          trackerId: e.trackerId,
          value: e.value,
          occurredAtUtc: e.occurredAtUtc,
          localDateKey: e.localDateKey,
          note: 'remembered'));

      final stored = (await entriesOf(cig.id)).single;
      expect(stored.note, 'remembered');
      expect(stored.localDateKey, const DateKey(20261005));
    });

    test('changing the time re-derives the day, where the device is now',
        () async {
      final cig = await repo.create(cigarettes);
      final e = (await repo.logEntry(cig.id) as EntryLogged).entry;

      await repo.updateEntry(TrackerEntry(
          id: e.id,
          trackerId: e.trackerId,
          value: e.value,
          occurredAtUtc: lateEvening,
          localDateKey: e.localDateKey,
          note: null));

      expect((await entriesOf(cig.id)).single.localDateKey,
          const DateKey(20261005));
    });
  });

  group('timers', () {
    late Tracker s;
    setUp(() async => s = await repo.create(sleep));

    test('start persists the start; a second start is a result', () async {
      final started = await repo.startTimer(s.id) as TimerStarted;
      expect(started.timer.startedAtUtc, fake.nowUtc);
      expect(await repo.startTimer(s.id), isA<TimerAlreadyRunning>());
      expect((await repo.watchTracker(s.id).first)!.runningTimer,
          started.timer);
    });

    test('stop logs the session in whole seconds, stamped at its start',
        () async {
      final start = fake.nowUtc;
      await repo.startTimer(s.id);
      fake.advance(const Duration(hours: 7, minutes: 30, seconds: 12));

      final stopped = await repo.stopTimer(s.id) as TimerStopped;
      expect(stopped.entry.value, 27012);
      expect(stopped.entry.occurredAtUtc, start);
      expect((await repo.watchTracker(s.id).first)!.runningTimer, isNull);
    });

    test('a session across midnight counts for the day it started', () async {
      fake.nowUtc = DateTime.utc(2026, 10, 5, 20, 20); // 23:50 in Tehran
      await repo.startTimer(s.id);
      fake.advance(const Duration(hours: 7, minutes: 30));

      final stopped = await repo.stopTimer(s.id) as TimerStopped;
      expect(stopped.entry.localDateKey, const DateKey(20261005));
    });

    test('a second stop is a result and logs nothing more', () async {
      await repo.startTimer(s.id);
      fake.advance(const Duration(minutes: 5));
      await repo.stopTimer(s.id);
      expect(await repo.stopTimer(s.id), isA<TimerNotRunning>());
      expect(await entriesOf(s.id), hasLength(1));
    });

    test('a stop under a second is discarded: cleared, nothing logged',
        () async {
      await repo.startTimer(s.id);
      fake.advance(const Duration(milliseconds: 900));
      expect(await repo.stopTimer(s.id), isA<TimerDiscarded>());
      expect(await entriesOf(s.id), isEmpty);
      expect((await repo.watchTracker(s.id).first)!.runningTimer, isNull);
    });

    test('a clock set back past the start is discarded, never negative',
        () async {
      await repo.startTimer(s.id);
      fake.advance(const Duration(hours: -1));
      expect(await repo.stopTimer(s.id), isA<TimerDiscarded>());
      expect(await entriesOf(s.id), isEmpty);
    });

    test('only a duration tracker has a timer', () async {
      final cig = await repo.create(cigarettes);
      expect(() => repo.startTimer(cig.id), throwsArgumentError);
      expect(() => repo.stopTimer(cig.id), throwsArgumentError);
    });

    test('a forgotten session is added as a duration ending now', () async {
      final logged = await repo.addDuration(
          s.id, const Duration(minutes: 45)) as EntryLogged;
      expect(logged.entry.value, 2700);
      expect(logged.entry.occurredAtUtc,
          fake.nowUtc.subtract(const Duration(minutes: 45)));
      expect(() => repo.addDuration(s.id, const Duration(milliseconds: 500)),
          throwsArgumentError);
    });
  });

  group('entries', () {
    test('pages report a next page exactly when one exists', () async {
      final cig = await repo.create(cigarettes);
      for (var i = 0; i < 4; i++) {
        await repo.logEntry(cig.id,
            at: fake.nowUtc.subtract(Duration(minutes: i)));
      }
      final first = await repo.entriesPage(cig.id, limit: 2);
      expect(first.items, hasLength(2));
      expect(first.hasMore, isTrue);

      // Four entries in pages of two: the second page is the last, even
      // though it is full -- the case items.length == limit gets wrong.
      final second =
          await repo.entriesPage(cig.id, after: first.cursor, limit: 2);
      expect(second.items, hasLength(2));
      expect(second.hasMore, isFalse);
    });

    test('clearToday removes the done, and restore brings it back', () async {
      final g = await repo.create(gym);
      await repo.logEntry(g.id);
      final cleared = await repo.clearToday(g.id);
      expect(await repo.totalOn(g.id, repo.today()), 0);

      expect(await repo.restoreEntries(cleared), DayWrite.written);
      expect(await repo.totalOn(g.id, repo.today()), 1);
    });

    test('an undo after marking done again reports the day is done',
        () async {
      final g = await repo.create(gym);
      await repo.logEntry(g.id);
      final cleared = await repo.clearToday(g.id);
      await repo.logEntry(g.id);

      expect(await repo.restoreEntries(cleared), DayWrite.dayAlreadyDone);
    });

    test('an edit must fit the type', () async {
      final cig = await repo.create(cigarettes);
      final e = (await repo.logEntry(cig.id) as EntryLogged).entry;
      expect(
          () => repo.updateEntry(TrackerEntry(
              id: e.id,
              trackerId: e.trackerId,
              value: 3,
              occurredAtUtc: e.occurredAtUtc,
              localDateKey: e.localDateKey)),
          throwsArgumentError);
    });
  });

  test('update rewrites the appearance and a quantity\'s amount', () async {
    final w = await repo.create(water);
    await repo.update(w.id,
        name: ' Aab ', iconKey: 'local_cafe', color: 7, unit: 'cup',
        perTapValue: 1);
    final stored = (await repo.watchTracker(w.id).first)!;
    expect(stored.name, 'Aab');
    expect(stored.unit, 'cup');
    expect(stored.perTapValue, 1);

    final cig = await repo.create(cigarettes);
    expect(
        () => repo.update(cig.id,
            name: 'C', iconKey: 'tag', color: 1, unit: 'L'),
        throwsArgumentError);
  });

  group('the offset is taken at write time', () {
    // Read in SQL: no domain type carries the offset, and app tests may not
    // import drift, so the id goes into the statement. Ids are UUIDv7 hex.
    Future<int> offsetOf(String entryId) async => (await db
            .customSelect('SELECT tz_offset_minutes AS o FROM tracker_entries '
                "WHERE id = '$entryId'")
            .getSingle())
        .read<int>('o');

    test('a tap stores the offset of wherever the device is', () async {
      final cig = await repo.create(cigarettes);
      final tehran = (await repo.logEntry(cig.id) as EntryLogged).entry;
      fake.offset = FakeClock.newYork;
      final newYork = (await repo.logEntry(cig.id) as EntryLogged).entry;

      expect(await offsetOf(tehran.id), 210);
      expect(await offsetOf(newYork.id), -240);
    });

    test('a timed session takes the offset at its start', () async {
      final s = await repo.create(sleep);
      await repo.startTimer(s.id);
      fake.advance(const Duration(hours: 1));
      final stopped = await repo.stopTimer(s.id) as TimerStopped;

      expect(await offsetOf(stopped.entry.id), 210);
    });

    test('a session added by hand takes the offset at its start', () async {
      final s = await repo.create(sleep);
      final added = await repo.addDuration(s.id, const Duration(minutes: 30))
          as EntryLogged;

      expect(await offsetOf(added.entry.id), 210);
    });

    test('a note-only edit after a flight keeps the offset; moving the time '
        'takes the new one', () async {
      final cig = await repo.create(cigarettes);
      final e = (await repo.logEntry(cig.id) as EntryLogged).entry;
      fake.offset = FakeClock.newYork;

      await repo.updateEntry(TrackerEntry(
          id: e.id,
          trackerId: e.trackerId,
          value: e.value,
          occurredAtUtc: e.occurredAtUtc,
          localDateKey: e.localDateKey,
          note: 'remembered'));
      expect(await offsetOf(e.id), 210);

      await repo.updateEntry(TrackerEntry(
          id: e.id,
          trackerId: e.trackerId,
          value: e.value,
          occurredAtUtc: e.occurredAtUtc.subtract(const Duration(hours: 1)),
          localDateKey: e.localDateKey,
          note: 'remembered'));
      expect(await offsetOf(e.id), -240);
    });

    test('an instant off the whole second still reads a whole offset', () {
      // 210 minutes, not 209. Dropping the milliseconds would put every such
      // entry an hour early in the time-of-day chart.
      expect(
          fake.clock.offsetMinutesOf(DateTime.utc(2026, 10, 5, 9, 0, 0, 500)),
          210);
      fake.offset = FakeClock.newYork;
      expect(
          fake.clock
              .offsetMinutesOf(DateTime.utc(2026, 10, 5, 9, 0, 0, 999, 999)),
          -240);
    });

    test("the system clock answers the device's own offset", () {
      final now = DateTime.now();
      expect(const TrackerClock().offsetMinutesOf(now.toUtc()),
          now.timeZoneOffset.inMinutes);
    });
  });

  group('totals', () {
    test("totalOn sums one tracker's live entries on one day", () async {
      final cig = await repo.create(cigarettes);
      final w = await repo.create(water);
      await repo.logEntry(cig.id);
      final second = (await repo.logEntry(cig.id) as EntryLogged).entry;
      await repo.logEntry(cig.id,
          at: fake.nowUtc.subtract(const Duration(days: 1)));
      await repo.logEntry(w.id);
      await repo.deleteEntry(second.id);

      expect(await repo.totalOn(cig.id, const DateKey(20261005)), 1);
      expect(await repo.totalOn(w.id, const DateKey(20261005)), 0.25);
      expect(await repo.totalOn(cig.id, const DateKey(20261006)), 0);
    });
  });
}
