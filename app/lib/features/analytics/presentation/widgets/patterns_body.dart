import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/patterns_controller.dart';
import '../../application/trends_controller.dart';

/// When spending happens, and how it was felt about.
class PatternsBody extends StatelessWidget {
  const PatternsBody({
    super.key,
    required this.byHour,
    required this.byWeekday,
    required this.reflection,
    required this.firstDayOfWeek,
    required this.formatter,
    required this.hourPin,
    required this.weekdayPin,
    required this.reflectionPin,
  });

  final AnalyticsResult byHour;
  final AnalyticsResult byWeekday;
  final AnalyticsResult reflection;
  final int firstDayOfWeek;
  final MoneyFormatter formatter;

  /// Each chart's own pin, beside its title. Pins are per chart rather than
  /// per tab because the dashboard draws them one at a time.
  final Widget hourPin;
  final Widget weekdayPin;
  final Widget reflectionPin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (byHour.trueCount == 0) {
      return NimbusEmptyState(
        icon: Icons.schedule_outlined,
        title: l10n.analyticsEmptyTitle,
        message: l10n.analyticsEmptyBody,
      );
    }

    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(NimbusTokens.space4),
      // A plain Column, not ListView: three fixed sections gain nothing from
      // virtualization, and a virtualized list can leave the last section
      // unbuilt when its header grows taller than plain text once was.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.patternsHourOfDay,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              hourPin,
            ],
          ),
          const SizedBox(height: NimbusTokens.space2),
          HourOfDayChart(result: byHour, formatter: formatter),
          const SizedBox(height: NimbusTokens.space6),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.patternsDayOfWeek,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              weekdayPin,
            ],
          ),
          const SizedBox(height: NimbusTokens.space2),
          DayOfWeekChart(
            result: byWeekday,
            firstDayOfWeek: firstDayOfWeek,
            formatter: formatter,
          ),
          const SizedBox(height: NimbusTokens.space6),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.patternsReflection,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              reflectionPin,
            ],
          ),
          const SizedBox(height: NimbusTokens.space2),
          ReflectionMatrix(result: reflection, formatter: formatter),
        ],
      ),
    );
  }
}

/// Spending by hour of day, every hour present.
///
/// Public so the dashboard can pin and draw it on its own.
class HourOfDayChart extends StatelessWidget {
  const HourOfDayChart({
    super.key,
    required this.result,
    required this.formatter,
  });

  final AnalyticsResult result;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context) {
    // Every hour gets a bar, including the quiet ones. The engine only returns
    // buckets that matched rows, so plotting those directly would put three
    // bars side by side and imply spending happens at every hour of the day.
    final hours = <int, Money>{
      for (final bucket in result.buckets)
        if (bucket.key case HourOfDayKey(:final hour)) hour: bucket.money,
    };
    return SizedBox(
      height: 180,
      child: BarChart(
        key: const Key('patterns-hour-chart'),
        _barData(
          context,
          formatter,
          [
            for (var hour = 0; hour < 24; hour++)
              (hour, hours[hour] ?? Money.zero),
          ],
          // Twenty-four labels do not fit; the shape is the message here and
          // the exact hour is available by touch.
          labelEvery: 6,
          labelOf: (hour) => '$hour',
        ),
      ),
    );
  }
}

/// Spending by day of week, in the order the user's week runs.
class DayOfWeekChart extends StatelessWidget {
  const DayOfWeekChart({
    super.key,
    required this.result,
    required this.firstDayOfWeek,
    required this.formatter,
  });

  final AnalyticsResult result;
  final int firstDayOfWeek;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final weekdays = <int, Money>{
      for (final bucket in result.buckets)
        if (bucket.key case DayOfWeekKey(:final weekday)) weekday: bucket.money,
    };
    final order = weekdaysFrom(firstDayOfWeek);
    return SizedBox(
      height: 180,
      child: BarChart(
        key: const Key('patterns-weekday-chart'),
        _barData(
          context,
          formatter,
          [
            for (final (index, weekday) in order.indexed)
              (index, weekdays[weekday] ?? Money.zero),
          ],
          labelEvery: 1,
          labelOf: (index) => _weekdayName(l10n, order[index]),
          labelKeyPrefix: 'patterns-weekday-label',
        ),
      ),
    );
  }
}

BarChartData _barData(
  BuildContext context,
  MoneyFormatter formatter,
  List<(int, Money)> bars, {
  required int labelEvery,
  required String Function(int) labelOf,
  String? labelKeyPrefix,
}) {
  final theme = Theme.of(context);
  return BarChartData(
    barGroups: [
      for (final (x, amount) in bars)
        BarChartGroupData(
          x: x,
          barRods: [
            BarChartRodData(
              toY: amount.minorUnits.toDouble(),
              color: theme.colorScheme.primary,
              width: 6,
            ),
          ],
        ),
    ],
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          getTitlesWidget: (value, meta) {
            final index = value.round();
            if (index % labelEvery != 0) return const SizedBox.shrink();
            return Text(
              labelOf(index),
              key: labelKeyPrefix == null
                  ? null
                  : Key('$labelKeyPrefix-$index'),
              style: theme.textTheme.labelSmall,
            );
          },
        ),
      ),
    ),
  );
}

String _weekdayName(AppLocalizations l10n, int isoWeekday) =>
    switch (isoWeekday) {
      DateTime.monday => l10n.weekdayMonday,
      DateTime.tuesday => l10n.weekdayTuesday,
      DateTime.wednesday => l10n.weekdayWednesday,
      DateTime.thursday => l10n.weekdayThursday,
      DateTime.friday => l10n.weekdayFriday,
      DateTime.saturday => l10n.weekdaySaturday,
      _ => l10n.weekdaySunday,
    };

/// Necessity down, satisfaction across, with the unset row and column kept.
/// Public so the dashboard can draw it on its own.
class ReflectionMatrix extends StatelessWidget {
  const ReflectionMatrix({
    super.key,
    required this.result,
    required this.formatter,
  });

  final AnalyticsResult result;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final cells = <(NecessityLevel?, SatisfactionLevel?), Money>{
      for (final bucket in result.buckets)
        if (bucket.key case ReflectionKey(
          :final necessity,
          :final satisfaction,
        ))
          (necessity, satisfaction): bucket.money,
    };

    // Null is a real row and a real column, not a gap. Phase 1 keeps both axes
    // off the add-expense path on purpose, so unreflected spending is the
    // common case -- dropping it would hide most of the data behind a matrix
    // that looked complete.
    const necessities = <NecessityLevel?>[
      NecessityLevel.needed,
      NecessityLevel.optional,
      NecessityLevel.avoidable,
      null,
    ];
    const satisfactions = <SatisfactionLevel?>[
      SatisfactionLevel.glad,
      SatisfactionLevel.neutral,
      SatisfactionLevel.regret,
      null,
    ];

    String necessityName(NecessityLevel? level) => switch (level) {
      NecessityLevel.needed => l10n.txNecessityNeeded,
      NecessityLevel.optional => l10n.txNecessityOptional,
      NecessityLevel.avoidable => l10n.txNecessityAvoidable,
      null => l10n.reflectionUnset,
    };
    String satisfactionName(SatisfactionLevel? level) => switch (level) {
      SatisfactionLevel.glad => l10n.txSatisfactionGlad,
      SatisfactionLevel.neutral => l10n.txSatisfactionNeutral,
      SatisfactionLevel.regret => l10n.txSatisfactionRegret,
      null => l10n.reflectionUnset,
    };
    String slug(Enum? level) => level?.name ?? 'unset';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 110),
              for (final satisfaction in satisfactions)
                SizedBox(
                  width: 90,
                  child: Padding(
                    padding: const EdgeInsets.all(NimbusTokens.space2),
                    child: Text(
                      satisfactionName(satisfaction),
                      style: theme.textTheme.labelMedium,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ),
            ],
          ),
          for (final necessity in necessities)
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Padding(
                    padding: const EdgeInsets.all(NimbusTokens.space2),
                    child: Text(
                      necessityName(necessity),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                for (final satisfaction in satisfactions)
                  SizedBox(
                    width: 90,
                    child: Padding(
                      padding: const EdgeInsets.all(NimbusTokens.space2),
                      child: switch (cells[(necessity, satisfaction)]) {
                        // Blank rather than zero, for the same reason as the
                        // tag matrix: never happened and measured as nothing
                        // are different claims.
                        null => const SizedBox.shrink(),
                        final amount => Text(
                          formatter.format(amount),
                          key: Key(
                            'patterns-reflection-'
                            '${slug(necessity)}-${slug(satisfaction)}',
                          ),
                          textAlign: TextAlign.end,
                          style: theme.textTheme.bodyMedium,
                        ),
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
