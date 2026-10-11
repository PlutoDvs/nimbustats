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

  /// A savings target's "900K/month for 6 more months", or null when there
  /// is no run-rate to state. That is the case when the range is not open, or
  /// nothing more is needed.
  String? runRate(AppLocalizations l10n, GoalProgress progress) {
    final rate = progress.projection.requiredRate;
    if (rate == null || rate.perMonth.isZero) return null;
    return l10n.goalsSavingsRunRate(
        rate.monthsLeft, compact(rate.perMonth), digits(rate.monthsLeft));
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
