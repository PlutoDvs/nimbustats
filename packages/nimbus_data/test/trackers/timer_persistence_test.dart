import 'dart:io';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/tracker_rows.dart';

void main() {
  test('a running timer survives the database closing and reopening',
      () async {
    // A killed process, as close as a test gets: the first connection is
    // closed with the timer running, and a fresh one opens the same file.
    // Nothing but the stored start may carry over. The first database is
    // closed before the second opens, so drift never sees two at once.
    final dir = Directory.systemTemp.createTempSync('nimbus_timer_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/nimbus.db';
    final start = DateTime.utc(2026, 10, 4, 20, 30);

    final first = AppDatabase.openAtPath(path);
    await first.trackersDao
        .insertAll([newTracker('sleep', TrackerType.duration)]);
    expect(
        await first.trackersDao
            .startTimer('sleep', start.millisecondsSinceEpoch),
        isTrue);
    await first.close();

    final second = AppDatabase.openAtPath(path);
    addTearDown(second.close);
    final timer = (await second.trackersDao.byId('sleep'))!.runningTimer;

    expect(timer, RunningTimer(start));
    expect(timer!.elapsed(start.add(const Duration(hours: 7, minutes: 30))),
        const Duration(hours: 7, minutes: 30));
  });
}
