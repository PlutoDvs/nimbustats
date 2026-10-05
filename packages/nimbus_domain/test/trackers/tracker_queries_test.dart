import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  const day = DateKey(20261005);
  const oneDay = DateRange(day, day);

  test("the tab asks for each tracker's total that day", () {
    expect(
        TrackerQueries.dayTotals(['cig', 'water'], day),
        TrackerQuerySpec(
            trackerIds: ['cig', 'water'],
            dateRange: oneDay,
            groupBy: const TrackerGroupByTracker(),
            aggregate: Aggregate.sum));
  });

  test("the snackbar and the header ask for one tracker's total", () {
    expect(
        TrackerQueries.dayTotal('cig', day),
        TrackerQuerySpec(
            trackerIds: ['cig'],
            dateRange: oneDay,
            groupBy: const TrackerGroupByNone(),
            aggregate: Aggregate.sum));
  });

  test('the streaks ask for every day ever logged, undated', () {
    expect(
        TrackerQueries.loggedDays('cig'),
        TrackerQuerySpec(
            trackerIds: ['cig'],
            groupBy: const TrackerGroupByDay(),
            aggregate: Aggregate.count));
  });

  test('the week and month charts ask for one bucket per day', () {
    expect(
        TrackerQueries.byDay('cig', oneDay),
        TrackerQuerySpec(
            trackerIds: ['cig'],
            dateRange: oneDay,
            groupBy: const TrackerGroupByDay(),
            aggregate: Aggregate.sum));
  });

  test('the year chart asks for one bucket per calendar month', () {
    expect(
        TrackerQueries.byMonth('cig', oneDay),
        TrackerQuerySpec(
            trackerIds: ['cig'],
            dateRange: oneDay,
            groupBy: TrackerGroupByPeriod(PeriodType.month),
            aggregate: Aggregate.sum));
  });
}
