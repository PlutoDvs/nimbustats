import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/trends_controller.dart';

/// One amount per period in [periods], in order -- zero for a quiet period.
///
/// The engine returns buckets only for periods that matched rows, so this
/// re-indexes them against the periods actually asked for. Plotting the
/// buckets directly would draw a line straight from March to June and
/// present the quiet months as a trend rather than as zero. Public so a
/// trend card can plot the same series.
List<Money> trendAmounts(AnalyticsResult result, List<DateRange> periods) {
  final found = <int, Money>{
    for (final bucket in result.buckets)
      if (bucket.key case PeriodKey(:final range))
        range.startInclusive.value: bucket.money,
  };
  return [
    for (final period in periods) found[period.startInclusive.value] ?? Money.zero,
  ];
}

/// Spending per period, and this period against the one before it.
class TrendsBody extends StatelessWidget {
  const TrendsBody({
    super.key,
    required this.view,
    required this.result,
    required this.formatter,
  });

  final TrendsView view;
  final AnalyticsResult result;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (result.trueCount == 0) {
      return NimbusEmptyState(
        icon: Icons.show_chart,
        title: l10n.analyticsEmptyTitle,
        message: l10n.analyticsEmptyBody,
      );
    }

    final theme = Theme.of(context);
    final amounts = trendAmounts(result, view.periods);

    return ListView(
      padding: const EdgeInsets.all(NimbusTokens.space4),
      children: [
        SizedBox(
          height: 220,
          child: LineChart(
            key: const Key('trends-chart'),
            LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (final (index, amount) in amounts.indexed)
                      FlSpot(index.toDouble(), amount.minorUnits.toDouble()),
                  ],
                  isCurved: false,
                  color: theme.colorScheme.primary,
                  barWidth: 2,
                ),
              ],
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) => Text(
                      trendsAxisLabel(value, formatter),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: NimbusTokens.space6),
        _Comparison(
          current: amounts.last,
          previous: amounts.length >= 2 ? amounts[amounts.length - 2] : null,
          formatter: formatter,
        ),
      ],
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({
    required this.current,
    required this.previous,
    required this.formatter,
  });

  final Money current;
  final Money? previous;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final before = previous;

    return Card(
      key: const Key('trends-comparison'),
      child: Padding(
        padding: const EdgeInsets.all(NimbusTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Line(
              label: l10n.trendsCurrentPeriod,
              amount: current,
              valueKey: 'trends-comparison-current',
              formatter: formatter,
            ),
            const SizedBox(height: NimbusTokens.space2),
            _Line(
              label: l10n.trendsPreviousPeriod,
              amount: before ?? Money.zero,
              valueKey: 'trends-comparison-previous',
              formatter: formatter,
            ),
            const SizedBox(height: NimbusTokens.space3),
            Text(
              _delta(l10n),
              key: const Key('trends-comparison-delta'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }

  /// The change, or a sentence saying there is nothing to divide by.
  ///
  /// A zero baseline makes the percentage undefined. Computing it anyway puts
  /// `Infinity%` on a user's screen, which is the kind of thing that gets
  /// screenshotted.
  String _delta(AppLocalizations l10n) {
    final before = previous;
    if (before == null || before.minorUnits == 0) {
      return l10n.trendsDeltaNoBaseline;
    }
    final change = current.minorUnits - before.minorUnits;
    final percent = (change * 100 / before.minorUnits).round();
    // U+2212, the same minus the transaction list uses -- a hyphen reads as a
    // dash at this size and disappears next to a digit.
    final sign = change < 0 ? '−' : '+';
    // Through Digits rather than a raw toString, so the percentage matches the
    // amounts above it. A Persian total over a Latin percentage looks like two
    // different apps sharing a card.
    final digits = formatter.persianDigits
        ? Digits.toPersian(percent.abs().toString())
        : percent.abs().toString();
    return '$sign$digits%';
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.amount,
    required this.valueKey,
    required this.formatter,
  });

  final String label;
  final Money amount;
  final String valueKey;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        Text(
          formatter.format(amount),
          key: Key(valueKey),
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}
