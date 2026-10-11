import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/application/settings_providers.dart';
import '../../trackers/application/tracker_format.dart';

/// How goal numbers read.
///
/// Money goes through [MoneyFormatter], and tracker values through the
/// trackers' own [TrackerFormat] (read-only), so a habit goal writes its
/// litres and minutes exactly as the tracker does. Digits follow the
/// settings locale (screen contract §8). Every string that shows a goal
/// number gets it from here, so the ARB strings never format a number
/// themselves.
final class GoalFormat {
  const GoalFormat({required this._money, required this._trackers});

  final MoneyFormatter _money;
  final TrackerFormat _trackers;

  bool get persianDigits => _money.persianDigits;

  /// In full, for the detail screen, the editor and the preview.
  String amount(GoalAmount value, {Tracker? tracker}) => switch (value) {
        MoneyAmount(:final money) => _money.format(money),
        QuantityAmount(value: final quantity) => _quantity(quantity, tracker),
      };

  /// Short, for the Goals tab's cards and the run-rate line (screen
  /// contract D1). Tracker values have no short form.
  String compact(GoalAmount value, {Tracker? tracker}) => switch (value) {
        MoneyAmount(:final money) => _money.formatCompact(money),
        QuantityAmount(value: final quantity) => _quantity(quantity, tracker),
      };

  /// [fraction] as a whole percent, rounded down so 79.99% never reads as
  /// 80%. The epsilon absorbs float noise such as `0.29 * 100 =
  /// 28.999999999999996`. A reached zero target is infinite and reads as
  /// 100%.
  String percent(double fraction) => wholePercent(
      fraction.isFinite ? (fraction * 100 + 1e-9).floor() : 100);

  /// A whole percent in the settings' digits: `80%`, `۸۰٪`.
  String wholePercent(int value) =>
      persianDigits ? '${Digits.toPersian('$value')}٪' : '$value%';

  /// A whole number in the settings' digits, without grouping.
  String digits(int value) => _trackers.digits(value);

  /// [day] as a date in [calendar], as the transaction list writes one:
  /// `1405/07/13`.
  String date(CalendarKind calendar, DateKey day) =>
      _digits(_ymd(GoalPeriods.calendarFor(calendar), day));

  /// [range], one of [goal]'s periods, named in the goal's own calendar, not
  /// the app's (spec §5.2). Numeric, as Phase 3's period labels are:
  /// - a day is its date;
  /// - a month is `1405/07`;
  /// - a year is `1405`;
  /// - a week, a quarter and a fixed range are their first and last days.
  String period(Goal goal, DateRange range) {
    final calendar = GoalPeriods.calendarFor(goal.calendar);
    final first = calendar.partsOf(range.startInclusive);
    final type = switch (goal.period) {
      RecurringPeriod(:final type) => type,
      FixedRangePeriod() => null,
    };
    return _digits(switch (type) {
      PeriodType.day => _ymd(calendar, range.startInclusive),
      PeriodType.month => '${first.year}/${_two(first.month)}',
      PeriodType.year => '${first.year}',
      _ => '${_ymd(calendar, range.startInclusive)} – '
          '${_ymd(calendar, range.endInclusive)}',
    });
  }

  String _digits(String latin) =>
      persianDigits ? Digits.toPersian(latin) : latin;

  static String _ymd(AppCalendar calendar, DateKey day) {
    final parts = calendar.partsOf(day);
    return '${parts.year}/${_two(parts.month)}/${_two(parts.day)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// A savings target's "900K/month for 6 more months", or null when there
  /// is no run-rate to state. That is the case when the range is not open, or
  /// nothing more is needed.
  String? runRate(AppLocalizations l10n, GoalProgress progress) {
    final rate = progress.projection.requiredRate;
    if (rate == null || rate.perMonth.isZero) return null;
    return l10n.goalsSavingsRunRate(
        rate.monthsLeft, compact(rate.perMonth), digits(rate.monthsLeft));
  }

  /// What the shell's snackbar says about [alert] (spec §4.2).
  ///
  /// Below 100% it gives the percent reached, from the progress itself:
  /// "82%", not the 80 that fired. At 100% a goal is "met" and a limit is
  /// "over" only when it is exceeded; spending exactly the limit is within
  /// it (spec §2), so that reads "reached". [period] is the goal's
  /// `period.storedName`, which picks "today's", "this week's" and so on; a
  /// fixed range reads plainly. Every at-most goal says "limit", because an
  /// alert does not carry a goal's kind (Contract note 11).
  String alertMessage(AppLocalizations l10n, GoalAlert alert, String period) {
    final name = alert.goalName;
    final reached = alert.percent >= 100;
    final percent = this.percent(alert.progress.fractionOfTarget);
    return switch (alert.direction) {
      GoalDirection.atMost => !reached
          ? l10n.goalsAlertLimitPercent(name, percent, period)
          : alert.progress.status == GoalStatus.exceeded
              ? l10n.goalsAlertLimitOver(name, period)
              : l10n.goalsAlertLimitReached(name, period),
      GoalDirection.atLeast => reached
          ? l10n.goalsAlertGoalMet(name, period)
          : l10n.goalsAlertGoalPercent(name, percent, period),
    };
  }

  String _quantity(double value, Tracker? tracker) =>
      tracker == null ? _trackers.number(value) : _trackers.total(tracker, value);
}

final goalFormatProvider = Provider<GoalFormat>((ref) => GoalFormat(
      money: ref.watch(moneyFormatterProvider),
      trackers: ref.watch(trackerFormatProvider),
    ));

/// A status in words. Every status is shown with its icon too, never by
/// colour alone.
String goalStatusText(AppLocalizations l10n, GoalStatus status) =>
    switch (status) {
      GoalStatus.notStarted => l10n.goalsStatusNotStarted,
      GoalStatus.onTrack => l10n.goalsStatusOnTrack,
      GoalStatus.atRisk => l10n.goalsStatusAtRisk,
      GoalStatus.exceeded => l10n.goalsStatusExceeded,
      GoalStatus.met => l10n.goalsStatusMet,
      GoalStatus.missed => l10n.goalsStatusMissed,
    };
