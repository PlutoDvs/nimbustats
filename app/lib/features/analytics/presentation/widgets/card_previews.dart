import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../categories/application/category_providers.dart';
import '../../../settings/application/settings_providers.dart';
import '../../../tags/application/tag_providers.dart';
import '../../application/dashboard_anchor.dart';
import 'patterns_body.dart';
import 'trends_body.dart';

/// The small chart under a card's total.
///
/// Deliberately partial -- a top three, a shape without axes. The whole
/// answer is one tap away, and a card that tried to be the full chart would
/// be one nobody could read at this size.
class CardPreview extends ConsumerWidget {
  const CardPreview({
    super.key,
    required this.view,
    required this.spec,
    required this.result,
  });

  final SavedView view;

  /// [view]'s question with its dates resolved.
  final QuerySpec spec;
  final AnalyticsResult result;

  static const height = 120.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatter = ref.watch(moneyFormatterProvider);
    final firstDayOfWeek = ref.watch(firstDayOfWeekProvider);
    return SizedBox(
      height: height,
      child: switch (view.chart) {
        SavedViewChart.breakdown =>
          _BreakdownPreview(result: result, formatter: formatter),
        SavedViewChart.trend => _TrendPreview(
            amounts: trendAmounts(
              result,
              trendPeriods(spec, ref.watch(calendarProvider),
                  firstDayOfWeek: firstDayOfWeek),
            ),
          ),
        SavedViewChart.crossTab =>
          _CrossTabPreview(result: result, formatter: formatter),
        SavedViewChart.hourOfDay => HourOfDayChart(
            result: result,
            formatter: formatter,
            height: height,
            showAxes: false,
          ),
        SavedViewChart.dayOfWeek => DayOfWeekChart(
            result: result,
            firstDayOfWeek: firstDayOfWeek,
            formatter: formatter,
            height: height,
            showAxes: false,
          ),
        SavedViewChart.reflection =>
          _ReflectionPreview(result: result, formatter: formatter),
      },
    );
  }
}

/// Shown when the names a preview needs failed to load.
class _PreviewUnavailable extends StatelessWidget {
  const _PreviewUnavailable({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Text(
        '${AppLocalizations.of(context).dashboardCardError}: $error',
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
}

class _BreakdownPreview extends ConsumerWidget {
  const _BreakdownPreview({required this.result, required this.formatter});

  final AnalyticsResult result;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodes = ref.watch(categoryNodesByIdProvider);
    if (nodes.hasError) return _PreviewUnavailable(error: nodes.error!);
    // Names gate the preview, as they gate the tab: a slice labelled with a
    // raw id is not a smaller answer, it is an unreadable one.
    final byId = nodes.value;
    if (byId == null) return const SizedBox.shrink();

    final rows = [
      for (final bucket in result.buckets)
        if (bucket.key case CategoryKey(:final categoryId))
          (id: categoryId, money: bucket.money),
    ]..sort((a, b) => b.money.minorUnits.compareTo(a.money.minorUnits));
    // Over every row, as the breakdown tab assigns them, so a category keeps
    // its colour between the card and the full chart.
    final colours = NimbusChartColors.of(context).assign(rows.map((r) => r.id));

    return Row(
      children: [
        SizedBox(
          width: CardPreview.height,
          child: PieChart(
            PieChartData(
              sectionsSpace: 1,
              centerSpaceRadius: 24,
              sections: [
                for (final row in rows)
                  PieChartSectionData(
                    value: row.money.minorUnits.toDouble(),
                    color: colours[row.id],
                    showTitle: false,
                    radius: 28,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: NimbusTokens.space4),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final row in rows.take(3))
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: NimbusTokens.space1),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colours[row.id],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: NimbusTokens.space2),
                      Expanded(
                        child: Text(
                          byId[row.id]?.category.name ?? row.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Compact: a dense row (screen contract §8).
                      Text(formatter.formatCompact(row.money),
                          key: Key('card-row-${row.id}')),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendPreview extends StatelessWidget {
  const _TrendPreview({required this.amounts});

  final List<Money> amounts;

  @override
  Widget build(BuildContext context) => LineChart(
        key: const Key('card-trend-chart'),
        LineChartData(
          titlesData: FlTitlesData(show: false),
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (final (index, amount) in amounts.indexed)
                  FlSpot(index.toDouble(), amount.minorUnits.toDouble()),
              ],
              color: Theme.of(context).colorScheme.primary,
              barWidth: 2,
              dotData: FlDotData(show: false),
            ),
          ],
        ),
      );
}

class _CrossTabPreview extends ConsumerWidget {
  const _CrossTabPreview({required this.result, required this.formatter});

  final AnalyticsResult result;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final categories = ref.watch(categoryNodesByIdProvider);
    final tags = ref.watch(tagNodesByIdProvider);
    final failure = categories.error ?? tags.error;
    if (failure != null) return _PreviewUnavailable(error: failure);
    final byCategory = categories.value;
    final byTag = tags.value;
    if (byCategory == null || byTag == null) return const SizedBox.shrink();

    final cells = [
      for (final bucket in result.buckets)
        if (bucket.key case TagCategoryKey(:final tagId, :final categoryId))
          (tagId: tagId, categoryId: categoryId, money: bucket.money),
    ]..sort((a, b) => b.money.minorUnits.compareTo(a.money.minorUnits));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cells.isEmpty)
          Text(l10n.dashboardCardEmpty)
        else
          for (final cell in cells.take(3))
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${byTag[cell.tagId]?.value.name ?? cell.tagId} · '
                    '${byCategory[cell.categoryId]?.category.name ?? cell.categoryId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(formatter.formatCompact(cell.money)),
              ],
            ),
        const Spacer(),
        // Unconditional, as on the full matrix: a tag axis always overlaps.
        Text(
          l10n.dashboardOverlapNote,
          key: const Key('card-overlap-note'),
          style: theme.textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _ReflectionPreview extends StatelessWidget {
  const _ReflectionPreview({required this.result, required this.formatter});

  final AnalyticsResult result;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // The two numbers the regret matrix exists for (screen contract §5.6):
    // what was avoidable and regretted, and what is not labelled yet -- the
    // honest prompt to label more. The full grid is on the full screen.
    final regretted = Money.sum([
      for (final bucket in result.buckets)
        if (bucket.key
            case ReflectionKey(
              necessity: NecessityLevel.avoidable,
              satisfaction: SatisfactionLevel.regret,
            ))
          bucket.money,
    ]);
    final unlabelled = Money.sum([
      for (final bucket in result.buckets)
        if (bucket.key case ReflectionKey(:final necessity, :final satisfaction)
            when necessity == null || satisfaction == null)
          bucket.money,
    ]);

    Widget line(String label, Money amount, String key) => Row(
          children: [
            Expanded(child: Text(label)),
            Text(formatter.format(amount),
                key: Key(key), style: theme.textTheme.titleMedium),
          ],
        );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        line(l10n.dashboardAvoidableRegretted, regretted, 'card-regretted'),
        const SizedBox(height: NimbusTokens.space2),
        line(l10n.reflectionUnset, unlabelled, 'card-unlabelled'),
      ],
    );
  }
}
