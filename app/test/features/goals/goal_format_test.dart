import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/application/goal_format.dart';
import 'package:nimbustats/features/trackers/application/tracker_format.dart';

void main() {
  final english = GoalFormat(
    money: const MoneyFormatter(currency: Currency.toman, persianDigits: false),
    trackers: TrackerFormat(
        localeTag: 'en', persianDigits: false, calendar: const GregorianCalendar()),
  );
  final persian = GoalFormat(
    money: const MoneyFormatter(currency: Currency.toman, persianDigits: true),
    trackers: TrackerFormat(
        localeTag: 'fa', persianDigits: true, calendar: const JalaliCalendar()),
  );

  Tracker tracker(TrackerType type, {String? unit}) => Tracker(
      id: type.name,
      name: type.name,
      iconKey: 'star',
      color: 0,
      type: type,
      unit: unit,
      perTapValue: type == TrackerType.quantity ? 0.25 : null,
      archived: false,
      sortOrder: 0);

  test('money reads in full on a detail and short on a card (D1)', () {
    expect(english.amount(const MoneyAmount(Money(850000))), '850,000');
    expect(english.compact(const MoneyAmount(Money(850000))), '850K');
    expect(persian.amount(const MoneyAmount(Money(850000))), '۸۵۰٬۰۰۰');
    expect(persian.compact(const MoneyAmount(Money(1000000))), '۱M');
  });

  test('a tracker number reads as its tracker shows it', () {
    expect(
        english.amount(const QuantityAmount(1.5),
            tracker: tracker(TrackerType.quantity, unit: 'L')),
        '1.5 L');
    expect(
        english.amount(const QuantityAmount(5400),
            tracker: tracker(TrackerType.duration)),
        '1:30');
    expect(
        english.compact(const QuantityAmount(3),
            tracker: tracker(TrackerType.counter)),
        '3');
    expect(english.amount(const QuantityAmount(3)), '3');
  });

  test('a percent is whole, rounded down, in the settings digits', () {
    expect(english.percent(0.825), '82%');
    expect(english.percent(0.7999), '79%', reason: 'never round up to 80');
    expect(english.percent(1.05), '105%');
    expect(english.percent(double.infinity), '100%');
    expect(persian.percent(0.825), '۸۲٪');
    expect(persian.wholePercent(80), '۸۰٪');
  });
}
