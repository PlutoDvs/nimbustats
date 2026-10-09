import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/application/tracker_format.dart';
import 'package:nimbustats/features/trackers/application/tracker_insights_controller.dart';
import 'package:nimbustats/features/trackers/application/tracker_insights_data.dart';

void main() {
  const gregorian = GregorianCalendar();
  const today = DateKey(20261005);
  const october = DateRange(DateKey(20261001), DateKey(20261031));
  final english = TrackerFormat(
      localeTag: 'en', persianDigits: false, calendar: gregorian);

  TrackerResult answer(Map<DateRange, double> values) => TrackerResult(
        buckets: [
          for (final MapEntry(key: range, value: value) in values.entries)
            TrackerBucket(key: PeriodKey(range), value: value, count: 1),
        ],
        sum: values.values.fold<double>(0, (a, b) => a + b),
        count: values.length,
      );

  test('a month draws every day, quiet ones at zero', () {
    final bars = historyBars(
      const TrackerInsightsView(kind: TrackerRangeKind.month, range: october),
      answer({
        const DateRange(DateKey(20261003), DateKey(20261003)): 0.5,
        const DateRange(DateKey(20261005), DateKey(20261005)): 0.75,
      }),
      gregorian,
    );
    expect(bars, hasLength(31));
    expect(bars[2], const TrackerBar(DateRange(DateKey(20261003), DateKey(20261003)), 0.5));
    expect(bars[4].value, 0.75);
    expect(bars.where((bar) => bar.value == 0), hasLength(29));
  });

  test('a week draws seven days', () {
    const week = DateRange(DateKey(20261003), DateKey(20261009));
    final bars = historyBars(
        const TrackerInsightsView(kind: TrackerRangeKind.week, range: week),
        answer({}),
        gregorian);
    expect(bars, hasLength(7));
  });

  test("a year draws its calendar's twelve months", () {
    const year = DateRange(DateKey(20260101), DateKey(20261231));
    final bars = historyBars(
      const TrackerInsightsView(kind: TrackerRangeKind.year, range: year),
      answer({october: 12}),
      gregorian,
    );
    expect(bars, hasLength(12));
    expect(bars[9], const TrackerBar(october, 12));
  });

  test('a Jalali year draws Jalali months', () {
    const jalali = JalaliCalendar();
    final year = jalali.periodContaining(today, PeriodType.year);
    final bars = historyBars(
        TrackerInsightsView(kind: TrackerRangeKind.year, range: year),
        answer({}),
        jalali);
    expect(bars, hasLength(12));
    expect(bars.first.period,
        jalali.periodContaining(year.startInclusive, PeriodType.month));
  });

  test('a per-day average divides only by the days already begun', () {
    expect(elapsedDays(october, today), 5);
    expect(
        elapsedDays(
            const DateRange(DateKey(20260901), DateKey(20260930)), today),
        30);
    expect(
        elapsedDays(
            const DateRange(DateKey(20261101), DateKey(20261130)), today),
        0);
  });

  test('the peak is the highest bar, the earliest on a tie', () {
    expect(peakIndex([0, 3, 1, 3]), 1);
    expect(peakIndex([0, 0]), 0);
  });

  test('the range is named by its kind', () {
    expect(
        rangeLabel(
            const TrackerInsightsView(
                kind: TrackerRangeKind.week,
                range: DateRange(DateKey(20261003), DateKey(20261009))),
            english),
        '2026/10/03 – 2026/10/09');
    expect(
        rangeLabel(
            const TrackerInsightsView(
                kind: TrackerRangeKind.month, range: october),
            english),
        '2026/10');
    expect(
        rangeLabel(
            const TrackerInsightsView(
                kind: TrackerRangeKind.year,
                range: DateRange(DateKey(20260101), DateKey(20261231))),
            english),
        '2026');
  });

  test('the range name follows the digits setting', () {
    final persian = TrackerFormat(
        localeTag: 'fa', persianDigits: true, calendar: gregorian);
    expect(
        rangeLabel(
            const TrackerInsightsView(
                kind: TrackerRangeKind.month, range: october),
            persian),
        '۲۰۲۶/۱۰');
  });

  test('twenty-four hour bars, quiet hours at zero', () {
    final bars = hourBars(TrackerResult(buckets: [
      TrackerBucket(key: HourOfDayKey(7), value: 1, count: 1),
      TrackerBucket(key: HourOfDayKey(12), value: 2, count: 2),
    ], sum: 3, count: 3));
    expect(bars, hasLength(24));
    expect(bars[7], 1);
    expect(bars[12], 2);
    expect(bars.where((value) => value == 0), hasLength(22));
  });

  test("weekday bars follow the user's week, not ISO order", () {
    final result = TrackerResult(buckets: [
      TrackerBucket(key: DayOfWeekKey(DateTime.monday), value: 3, count: 3),
      TrackerBucket(key: DayOfWeekKey(DateTime.saturday), value: 1, count: 1),
    ], sum: 4, count: 4);
    const saturdayFirst = [6, 7, 1, 2, 3, 4, 5];
    expect(weekdayBars(result, saturdayFirst), [1, 0, 3, 0, 0, 0, 0]);
  });
}
