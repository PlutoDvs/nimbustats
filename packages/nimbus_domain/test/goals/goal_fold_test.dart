import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

MoneyAmount rials(int minor) => MoneyAmount(Money(minor));
DateRange range(int start, int end) => DateRange(DateKey(start), DateKey(end));

void main() {
  // Three Saturday-start weeks.
  final weeks = [
    range(20261003, 20261009),
    range(20261010, 20261016),
    range(20261017, 20261023),
  ];

  test('each period sums its own days; a period with none is zero', () {
    final daily = <DateKey, GoalAmount>{
      const DateKey(20261003): rials(100),
      const DateKey(20261009): rials(50), // the first week's last day
      const DateKey(20261017): rials(-30), // net savings can go negative
      const DateKey(20261023): rials(10),
    };
    expect(foldDaily(daily, weeks, rials(0)),
        [rials(150), rials(0), rials(-20)]);
  });

  test('days outside every period are ignored', () {
    final daily = <DateKey, GoalAmount>{
      const DateKey(20261002): rials(999),
      const DateKey(20261010): rials(5),
      const DateKey(20261024): rials(999),
    };
    expect(foldDaily(daily, weeks, rials(0)), [rials(0), rials(5), rials(0)]);
  });

  test('quantities fold the same way, and never mix with money', () {
    final daily = <DateKey, GoalAmount>{
      const DateKey(20261011): const QuantityAmount(2),
      const DateKey(20261012): const QuantityAmount(1.5),
    };
    expect(foldDaily(daily, weeks, const QuantityAmount(0)), [
      const QuantityAmount(0),
      const QuantityAmount(3.5),
      const QuantityAmount(0),
    ]);
    // A measurer that answered in the wrong subtype is a bug to surface.
    expect(() => foldDaily(daily, weeks, rials(0)), throwsArgumentError);
  });
}
