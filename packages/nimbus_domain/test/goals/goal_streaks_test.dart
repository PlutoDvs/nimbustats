import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

/// Consecutive weeks, oldest first, with the given statuses. Only the order
/// matters to a streak.
List<PeriodOutcome> weeks(List<GoalStatus> statuses) => [
      for (final (i, status) in statuses.indexed) _week(i, status),
    ];

PeriodOutcome _week(int index, GoalStatus status) {
  final start = const DateKey(20260103).addDays(7 * index);
  return PeriodOutcome(
      DateRange(start, start.addDays(6)), const QuantityAmount(0), status);
}

void main() {
  test('no closed periods, no streak', () {
    expect(GoalStreaks.of(const []), GoalStreaks.none);
  });

  test('current is the trailing run of met; best the longest anywhere', () {
    expect(
        GoalStreaks.of(weeks([
          GoalStatus.met,
          GoalStatus.met,
          GoalStatus.met,
          GoalStatus.missed,
          GoalStatus.met,
          GoalStatus.met,
        ])),
        const GoalStreaks(current: 2, best: 3));
  });

  test('a closed period that was not met ends the current streak', () {
    expect(
        GoalStreaks.of(
            weeks([GoalStatus.met, GoalStatus.met, GoalStatus.exceeded])),
        const GoalStreaks(current: 0, best: 2));
    expect(GoalStreaks.of(weeks([GoalStatus.met, GoalStatus.missed])),
        const GoalStreaks(current: 0, best: 1));
  });

  test('best is never less than current', () {
    expect(
        GoalStreaks.of(weeks([
          GoalStatus.missed,
          GoalStatus.met,
          GoalStatus.met,
          GoalStatus.met,
        ])),
        const GoalStreaks(current: 3, best: 3));
  });
}
