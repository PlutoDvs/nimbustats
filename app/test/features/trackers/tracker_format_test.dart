import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/application/tracker_format.dart';

Tracker tracker(TrackerType type, {String? unit}) => Tracker(
      id: 't',
      name: 'T',
      iconKey: 'tag',
      color: 0,
      type: type,
      unit: unit,
      perTapValue: type == TrackerType.quantity ? 0.25 : null,
      archived: false,
      sortOrder: 0,
    );

void main() {
  final persian = TrackerFormat(
      localeTag: 'fa', persianDigits: true, calendar: const GregorianCalendar());
  final english = TrackerFormat(
      localeTag: 'en', persianDigits: false, calendar: const GregorianCalendar());

  test("numbers use the locale's digits and separators", () {
    expect(persian.number(2.5), '۲٫۵');
    expect(persian.number(1250), '۱٬۲۵۰');
    expect(english.number(2.5), '2.5');
    expect(english.number(1250), '1,250');
  });

  test('two decimals at most, so a float sum reads cleanly', () {
    expect(english.number(0.1 + 0.2), '0.3');
    expect(english.number(1 / 3), '0.33');
    expect(english.number(5), '5');
  });

  test("a total reads in its tracker's terms", () {
    expect(english.total(tracker(TrackerType.counter), 5), '5');
    expect(english.total(tracker(TrackerType.quantity, unit: 'L'), 0.75),
        '0.75 L');
    expect(english.total(tracker(TrackerType.quantity), 3), '3');
    expect(english.total(tracker(TrackerType.duration), 5400), '1:30');
    expect(persian.total(tracker(TrackerType.quantity, unit: 'لیتر'), 0.75),
        '۰٫۷۵ لیتر');
  });

  test('durations are h:mm; a running timer is h:mm:ss', () {
    const d = Duration(hours: 1, minutes: 2, seconds: 5);
    expect(english.duration(d), '1:02');
    expect(english.elapsed(d), '1:02:05');
    expect(persian.elapsed(d), '۱:۰۲:۰۵');
    expect(english.duration(const Duration(minutes: 12)), '0:12');
  });

  test('times and dates follow the digits and the active calendar', () {
    expect(english.time(DateTime.utc(2026, 10, 5, 7, 5)), '07:05');
    expect(persian.time(DateTime.utc(2026, 10, 5, 14, 30)), '۱۴:۳۰');
    expect(english.date(const DateKey(20261005)), '2026/10/05');
    expect(persian.date(const DateKey(20261005)), '۲۰۲۶/۱۰/۰۵');
  });
}
