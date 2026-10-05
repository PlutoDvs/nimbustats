import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  const today = DateKey(20261005);
  DateKey ago(int days) => today.addDays(-days);
  TrackerStreaks of(List<DateKey> days) =>
      TrackerStreaks.of(days, today: today);

  test('never logged: no streak and no last entry', () {
    expect(of([]), const TrackerStreaks(current: 0, longest: 0));
  });

  test('a run that includes today ends today', () {
    expect(of([ago(2), ago(1), today]),
        const TrackerStreaks(current: 3, longest: 3, daysSinceLast: 0));
  });

  test("today with nothing yet keeps yesterday's run alive", () {
    expect(of([ago(2), ago(1)]),
        const TrackerStreaks(current: 2, longest: 2, daysSinceLast: 1));
  });

  test('a missed day ends the run', () {
    expect(of([ago(4), ago(3), ago(1)]),
        const TrackerStreaks(current: 1, longest: 2, daysSinceLast: 1));
  });

  test('two days without an entry leave no current streak', () {
    expect(of([ago(3), ago(2)]),
        const TrackerStreaks(current: 0, longest: 2, daysSinceLast: 2));
  });

  test('the longest run can lie in the past', () {
    expect(of([ago(10), ago(9), ago(8), ago(7), ago(1), today]),
        const TrackerStreaks(current: 2, longest: 4, daysSinceLast: 0));
  });

  test('a single day long ago', () {
    expect(of([ago(5)]),
        const TrackerStreaks(current: 0, longest: 1, daysSinceLast: 5));
  });

  test('order and repeats in the input do not matter', () {
    expect(of([today, ago(1), today, ago(1)]),
        const TrackerStreaks(current: 2, longest: 2, daysSinceLast: 0));
  });

  test('days after today are ignored', () {
    // The entry sheet should not produce them, and a clock set back must not
    // become a streak.
    expect(of([today.addDays(1), today.addDays(2)]),
        const TrackerStreaks(current: 0, longest: 0));
    expect(of([ago(1), today.addDays(1)]),
        const TrackerStreaks(current: 1, longest: 1, daysSinceLast: 1));
  });

  test('a run across a month boundary is one run', () {
    expect(
        TrackerStreaks.of(const [
          DateKey(20260929),
          DateKey(20260930),
          DateKey(20261001),
        ], today: const DateKey(20261001)),
        const TrackerStreaks(current: 3, longest: 3, daysSinceLast: 0));
  });
}
