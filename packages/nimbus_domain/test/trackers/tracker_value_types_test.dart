import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

Tracker water({DateTime? timerStartedAtUtc}) => Tracker(
      id: 'water',
      name: 'Water',
      iconKey: 'water_drop',
      color: 0xFF1565C0,
      type: TrackerType.quantity,
      unit: 'L',
      perTapValue: 0.25,
      archived: false,
      sortOrder: 0,
      timerStartedAtUtc: timerStartedAtUtc,
    );

void main() {
  test('trackers with the same fields are equal', () {
    expect(water(), water());
    expect(water().hashCode, water().hashCode);
  });

  test('a tracker with no stored start has no running timer', () {
    expect(water().runningTimer, isNull);
  });

  test('a stored start is the running timer', () {
    final start = DateTime.utc(2026, 10, 5, 9);
    expect(water(timerStartedAtUtc: start).runningTimer, RunningTimer(start));
  });

  test('entries with the same fields are equal; a different note is not', () {
    TrackerEntry entry({String? note}) => TrackerEntry(
          id: 'e1',
          trackerId: 'water',
          value: 0.25,
          occurredAtUtc: DateTime.utc(2026, 10, 5, 9),
          localDateKey: const DateKey(20261005),
          note: note,
        );

    expect(entry(), entry());
    expect(entry().hashCode, entry().hashCode);
    expect(entry(note: 'after lunch'), isNot(entry()));
  });
}
