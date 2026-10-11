import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/application/goal_kind.dart';

import 'support/goal_test_app.dart';

void main() {
  const gym = Tracker(
      id: 'gym',
      name: 'Gym',
      iconKey: 'fitness_center',
      color: 0,
      type: TrackerType.boolean,
      archived: false,
      sortOrder: 0);

  test("a goal's kind is read off its metric family and direction", () {
    expect(kindOf(spendingCap()), GoalKind.spendingCap);
    expect(kindOf(habitGoal(gym)), GoalKind.habitLimit);
    expect(kindOf(habitGoal(gym, direction: GoalDirection.atLeast)),
        GoalKind.habitGoal);
    expect(kindOf(savingsTarget()), GoalKind.savingsTarget);
  });

  test('each kind has its direction and default period (spec §5.3)', () {
    expect({
      for (final kind in GoalKind.values)
        kind: (kind.direction, kind.defaultPeriod)
    }, {
      GoalKind.spendingCap: (GoalDirection.atMost, PeriodType.month),
      GoalKind.habitLimit: (GoalDirection.atMost, PeriodType.day),
      GoalKind.habitGoal: (GoalDirection.atLeast, PeriodType.week),
      GoalKind.savingsTarget: (GoalDirection.atLeast, null),
    });
  });

  test("a habit's metric follows its tracker's type, with no picker", () {
    expect({for (final type in TrackerType.values) type: habitMetricFor(type)},
        {
          TrackerType.counter: GoalMetric.trackerCount,
          TrackerType.boolean: GoalMetric.trackerCount,
          TrackerType.quantity: GoalMetric.trackerSum,
          TrackerType.duration: GoalMetric.trackerSum,
        });
  });
}
