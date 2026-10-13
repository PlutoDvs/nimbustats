import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';
import 'package:nimbustats/features/widget/application/widget_drain.dart';

import '../goals/support/goal_test_app.dart';
import '../trackers/support/tracker_fixture.dart';
import 'support/buffer_lines.dart';

void main() {
  late AppDatabase db;
  late FakeClock fake;
  late TrackerRepository trackers;
  late WidgetDrain drain;

  WidgetDrain drainOver(AppDatabase database) => _drainOver(database, fake);

  setUp(() async {
    db = AppDatabase.openInMemory();
    fake = FakeClock();
    trackers = repositoryFor(db, fake);
    drain = drainOver(db);
    await seedCategories(db);
  });
  tearDown(() => db.close());

  Future<Transaction?> row(String id) => db.transactionsDao.byId(id);

  test('each line is written once: a second drain writes nothing', () async {
    final cig = await trackers.create(cigarettes);
    final lines = [expense('e1', category: 'seed-dining'), tap('t1', cig.id)];

    final first = await drain.apply(lines);
    final second = await drain.apply(lines);

    expect(first.ackIds, ['e1', 't1']);
    expect(second.ackIds, ['e1', 't1'], reason: 'settled, so acked again');
    expect((await row('e1'))!.amount, const Money(120000));
    expect((await row('e1'))!.source, TxSource.widget);
    expect((await trackers.entriesPage(cig.id)).items, hasLength(1));
  });

  test('an expense deleted after it was drained is not resurrected',
      () async {
    await drain.apply([expense('e2')]);
    await db.transactionsDao.softDelete('e2');
    await drain.apply([expense('e2')]);

    expect((await row('e2'))!.deletedAt, isNotNull);
  });

  test('the tap time is kept, across midnight (Review Focus 1)', () async {
    final cig = await trackers.create(cigarettes);
    // 23:59 on the 4th in Tehran; drained at 12:30 on the 5th.
    final lateLastNight = DateTime.utc(2026, 10, 4, 20, 29);
    await drain.apply([
      expense('e3', at: lateLastNight),
      tap('t3', cig.id, at: lateLastNight),
    ]);

    expect((await row('e3'))!.occurredAtUtc,
        lateLastNight.millisecondsSinceEpoch);
    final entry = (await trackers.entriesPage(cig.id)).items.single;
    expect(entry.occurredAtUtc, lateLastNight);
    expect(entry.localDateKey, const DateKey(20261004));
  });

  test('no chip, or a category deleted since the snapshot, files it as '
      'Uncategorized', () async {
    await db.categoriesDao.softDeleteSubtree('seed-transport');
    await drain.apply([
      expense('e4'),
      expense('e5', category: 'seed-transport'),
    ]);

    expect((await row('e4'))!.categoryId, SystemCategoryIds.uncategorized);
    expect((await row('e5'))!.categoryId, SystemCategoryIds.uncategorized);
  });

  test('a tracker gone, archived or timed is rejected with a reason',
      () async {
    final gone = await trackers.create(cigarettes);
    // The app archives trackers and never deletes one, but a soft-deleted
    // row must still read as gone.
    await db.customStatement(
        'UPDATE trackers SET deleted_at = 1 WHERE id = ?', [gone.id]);
    final archived = await trackers.create(gym);
    await trackers.archive(archived.id);
    final timed = await trackers.create(sleep);

    final outcome = await drain.apply([
      tap('g', gone.id),
      tap('a', archived.id),
      tap('d', timed.id),
      tap('x', 'no-such-tracker'),
    ]);

    expect(outcome.ackIds, isEmpty);
    expect([for (final r in outcome.rejected) r.reason], [
      'tracker gone',
      'tracker archived',
      'duration tracker',
      'tracker gone',
    ]);
    expect(outcome.rejected.first.line, tap('g', gone.id));
  });

  test('a malformed line, an unknown version or an amount out of range is '
      'rejected', () async {
    final outcome = await drain.apply([
      'not json',
      '[1,2]',
      jsonEncode({'v': 2, 'id': 'v2', 'kind': 'expense', 'atUtc': 0}),
      expense('big', amount: maxAmountMinor + 1),
      expense('zero', amount: 0),
      jsonEncode({'v': 1, 'id': 'k', 'kind': 'transfer', 'atUtc': 0}),
      // Past DateTime's range: rejected, not thrown out of the whole drain.
      jsonEncode({
        'v': 1,
        'id': 't',
        'kind': 'expense',
        'atUtc': 8640000000000001,
        'amountMinor': 1,
      }),
    ]);

    expect(outcome.ackIds, isEmpty);
    expect(outcome.rejected, hasLength(7));
    expect(await db.transactionsDao.byId('big'), isNull);
  });

  test("a boolean already done that day is acked: it is the repository's "
      'rule', () async {
    final done = await trackers.create(gym);
    await trackers.logEntry(done.id);
    final outcome = await drain.apply([tap('t6', done.id)]);

    expect(outcome.ackIds, ['t6']);
    expect((await trackers.entriesPage(done.id)).items, hasLength(1));
  });

  test('an unexpected failure leaves the line for the next drain and is '
      'reported', () async {
    final bare = AppDatabase.openInMemory(); // no Uncategorized row: FK fails
    addTearDown(bare.close);
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);

    final outcome = await drainOver(bare).apply([expense('e7')]);

    expect(outcome.ackIds, isEmpty);
    expect(outcome.rejected, isEmpty);
    expect(outcome.failed, 1);
    expect(reported.single.library, 'widget drain');
  });

  test('two engines draining the same lines at once write each once '
      '(Review Focus 3)', () async {
    final dir = Directory.systemTemp.createTempSync('nimbus_drain_race');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}nimbustats.sqlite';
    final app = AppDatabase.openAtPath(path);
    addTearDown(app.close);
    await seedCategories(app);
    final lines = [for (var i = 0; i < 30; i++) expense('r$i')];

    // The headless engine is a real second isolate with its own connection,
    // as on the device. Two connections on one isolate would stall: SQLite's
    // busy handler sleeps on the only thread the other needs to commit. It
    // walks the lines from the other end, so the two meet mid-buffer rather
    // than the later one finding every row already written.
    final acked = await Future.wait([
      drainOver(app).apply(lines).then((outcome) => outcome.ackIds.length),
      _headlessDrain(path, lines),
    ]);

    expect(acked, [30, 30], reason: 'each engine settles every line');
    final rows = await app.transactionsDao.inRange(
        const DateRange(DateKey(20000101), DateKey(20991231)));
    expect(rows, hasLength(30));
    expect({for (final row in rows) row.currencyCode},
        {Currency.toman.code, Currency.usd.code},
        reason: 'each engine wrote some of the rows');
  });
}

WidgetDrain _drainOver(AppDatabase database, FakeClock fake,
        {Currency currency = Currency.toman}) =>
    WidgetDrain(
      db: database,
      transactions: TransactionRepository(
          database.transactionsDao, database.tagsDao, currency),
      trackers: repositoryFor(database, fake),
    );

/// In a second isolate, opens its own connection to [path] and drains
/// [lines] last to first: what the headless engine does to the same file.
/// Its rows are stamped in dollars, so the test can tell whose they are.
/// Returns how many lines it acked.
///
/// Spawned here, not in the test: a closure made in `main` carries `main`'s
/// context, whose open database cannot be sent to an isolate.
Future<int> _headlessDrain(String path, List<String> lines) =>
    Isolate.run(() async {
      final db = AppDatabase.openAtPath(path);
      try {
        final drain = _drainOver(db, FakeClock(), currency: Currency.usd);
        return (await drain.apply(lines.reversed.toList())).ackIds.length;
      } finally {
        await db.close();
      }
    });
