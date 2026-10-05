import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  test('elapsed is now minus the stored start', () {
    final timer = RunningTimer(DateTime.utc(2026, 10, 4, 23, 50));
    expect(timer.elapsed(DateTime.utc(2026, 10, 5, 7, 20)),
        const Duration(hours: 7, minutes: 30));
  });

  test('a timer rebuilt from its stored start reads the same', () {
    // What a process death does: the timer is rebuilt from the persisted
    // epoch milliseconds, and nothing about it may change.
    final start = DateTime.utc(2026, 10, 4, 23, 50);
    final before = RunningTimer(start);
    final after = RunningTimer(DateTime.fromMillisecondsSinceEpoch(
        start.millisecondsSinceEpoch,
        isUtc: true));
    final now = DateTime.utc(2026, 10, 5, 1);

    expect(after, before);
    expect(after.elapsed(now), before.elapsed(now));
  });

  test('a timezone change does not warp it: it is between two instants', () {
    final timer = RunningTimer(DateTime.utc(2026, 10, 5, 9));
    final nowUtc = DateTime.utc(2026, 10, 5, 10);
    expect(timer.elapsed(nowUtc.toLocal()), const Duration(hours: 1));
  });

  test('a clock set back past the start reads zero, never negative', () {
    final timer = RunningTimer(DateTime.utc(2026, 10, 5, 9));
    expect(timer.elapsed(DateTime.utc(2026, 10, 5, 8)), Duration.zero);
  });

  test('the start must be UTC', () {
    expect(() => RunningTimer(DateTime(2026, 10, 5, 9)), throwsArgumentError);
  });
}
