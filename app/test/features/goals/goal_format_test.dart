import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/application/goal_format.dart';
import 'package:nimbustats/features/trackers/application/tracker_format.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

import 'support/goal_test_app.dart';

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

  test("a period is named in the goal's own calendar", () {
    const day5 = DateKey(20261005);
    final mehr =
        const JalaliCalendar().periodContaining(day5, PeriodType.month);
    expect(english.period(spendingCap(), mehr), '1405/07');
    expect(
        english.period(spendingCap(calendar: CalendarKind.gregorian),
            const DateRange(DateKey(20261001), DateKey(20261031))),
        '2026/10');
    expect(persian.period(spendingCap(), mehr), '۱۴۰۵/۰۷');
    expect(english.date(CalendarKind.jalali, day5), '1405/07/13');
  });

  test('a day reads as its date; a week and a range as their two ends', () {
    Goal gregorian(PeriodType type) =>
        spendingCap(period: type, calendar: CalendarKind.gregorian);
    expect(
        english.period(gregorian(PeriodType.day),
            const DateRange(DateKey(20261005), DateKey(20261005))),
        '2026/10/05');
    expect(
        english.period(gregorian(PeriodType.week),
            const DateRange(DateKey(20261003), DateKey(20261009))),
        '2026/10/03 – 2026/10/09');
    expect(
        english.period(gregorian(PeriodType.year),
            const DateRange(DateKey(20260101), DateKey(20261231))),
        '2026');
    expect(
        english.period(savingsTarget(),
            const DateRange(DateKey(20261001), DateKey(20270331))),
        '2026/10/01 – 2027/03/31');
  });

  GoalAlert alert(GoalDirection direction, int percent, double fraction,
      {String name = 'Dining out', GoalStatus status = GoalStatus.atRisk}) {
    const day = DateRange(DateKey(20261005), DateKey(20261005));
    return GoalAlert(
      goalId: 'g',
      goalName: name,
      period: day,
      percent: percent,
      direction: direction,
      progress: GoalProgress(
        period: day,
        current: QuantityAmount(fraction * 10),
        target: const QuantityAmount(10),
        status: status,
        fractionOfTarget: fraction,
        projection: const Projection(projectedEnd: QuantityAmount(0)),
      ),
    );
  }

  test('an alert is worded by its direction and by reaching 100% (spec §4.2)',
      () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
        english.alertMessage(en, alert(GoalDirection.atMost, 80, 0.82), 'month'),
        "Dining out: 82% of this month's limit");
    expect(
        english.alertMessage(
            en,
            alert(GoalDirection.atMost, 100, 1.05,
                status: GoalStatus.exceeded),
            'month'),
        "Dining out: over this month's limit");
    expect(
        english.alertMessage(
            en, alert(GoalDirection.atLeast, 100, 1.0, name: 'Gym'), 'week'),
        "Gym: this week's goal met");
    expect(
        english.alertMessage(
            en, alert(GoalDirection.atLeast, 80, 0.8, name: 'Gym'), 'week'),
        "Gym: 80% of this week's goal");
    expect(english.alertMessage(en, alert(GoalDirection.atMost, 80, 0.8), 'day'),
        "Dining out: 80% of today's limit");
    expect(
        english.alertMessage(en,
            alert(GoalDirection.atLeast, 100, 1.2, name: 'Car'), 'fixedRange'),
        'Car: goal met');
  });

  test('spending exactly the cap is within it: reached, not over (spec §2)',
      () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
        english.alertMessage(
            en, alert(GoalDirection.atMost, 100, 1.0), 'month'),
        "Dining out: reached this month's limit");
  });

  test('an alert in Persian', () async {
    final fa = await AppLocalizations.delegate.load(const Locale('fa'));
    expect(
        persian.alertMessage(fa, alert(GoalDirection.atMost, 80, 0.82), 'month'),
        'Dining out: ۸۲٪ از سقف این ماه');
    expect(
        persian.alertMessage(
            fa, alert(GoalDirection.atLeast, 100, 1.0, name: 'Gym'), 'week'),
        'Gym: هدف این هفته محقق شد');
  });
}
