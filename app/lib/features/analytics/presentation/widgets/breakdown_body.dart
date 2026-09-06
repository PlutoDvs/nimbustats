import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../categories/data/category_tree.dart';
import '../../application/breakdown_controller.dart';

/// The populated breakdown: a total, a pie, and the ranked rows behind it.
class BreakdownBody extends StatelessWidget {
  const BreakdownBody({
    super.key,
    required this.result,
    required this.nodesById,
    required this.formatter,
    required this.onDrill,
  });

  final AnalyticsResult result;
  final Map<String, CategoryNode> nodesById;
  final MoneyFormatter formatter;
  final void Function(CategoryCrumb) onDrill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (result.buckets.isEmpty) {
      return NimbusEmptyState(
        icon: Icons.insights_outlined,
        title: l10n.analyticsEmptyTitle,
        message: l10n.analyticsEmptyBody,
      );
    }

    final theme = Theme.of(context);
    final palette = NimbusChartColors.of(context);

    // Ranked before colours are assigned, because assignment must not depend
    // on order -- a category that changed colour when its rank moved would
    // make two months impossible to compare.
    final rows = [...result.buckets]
      ..sort((a, b) => b.money.minorUnits.compareTo(a.money.minorUnits));
    final ids = [
      for (final bucket in rows)
        if (bucket.key case CategoryKey(:final categoryId)) categoryId,
    ];
    final colours = palette.assign(ids);

    return ListView(
      children: [
        Padding(
          key: const Key('breakdown-total'),
          padding: const EdgeInsets.all(NimbusTokens.space4),
          child: Column(
            children: [
              Text(l10n.txMonthTotal, style: theme.textTheme.labelMedium),
              Text(
                // The engine's true total, which counts each transaction once.
                // Adding the slices up would be the same number here and the
                // wrong one the moment a tag dimension is grouped.
                formatter.format(result.trueTotal),
                key: const Key('breakdown-total-amount'),
                style: theme.textTheme.headlineSmall,
              ),
            ],
          ),
        ),
        if (result.overlaps)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NimbusTokens.space4,
            ),
            child: NimbusDisclosureBanner(
              message: l10n.analyticsOverlapDisclosure,
            ),
          ),
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 48,
              sections: [
                for (final bucket in rows)
                  if (bucket.key case CategoryKey(:final categoryId))
                    PieChartSectionData(
                      value: bucket.money.minorUnits.toDouble(),
                      color: colours[categoryId],
                      // The slice is the chart; the number is in the row
                      // beneath it, where it can be read at any size.
                      showTitle: false,
                      radius: 40,
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: NimbusTokens.space4),
        for (final bucket in rows)
          if (bucket.key case CategoryKey(:final categoryId))
            _BreakdownRow(
              node: nodesById[categoryId],
              categoryId: categoryId,
              bucket: bucket,
              colour: colours[categoryId] ?? palette.series.first,
              formatter: formatter,
              onDrill: onDrill,
            ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.node,
    required this.categoryId,
    required this.bucket,
    required this.colour,
    required this.formatter,
    required this.onDrill,
  });

  final CategoryNode? node;
  final String categoryId;
  final Bucket bucket;
  final Color colour;
  final MoneyFormatter formatter;
  final void Function(CategoryCrumb) onDrill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = node?.category;
    // A row whose category is missing from the tree is still real spending, so
    // it is listed under its id rather than dropped. Dropping it would make
    // the rows disagree with the total above them for no visible reason.
    final name = category?.name ?? categoryId;
    final canDrill = (node?.children.isNotEmpty ?? false);

    return ListTile(
      key: Key('breakdown-row-$categoryId'),
      leading: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      ),
      title: Text(name),
      subtitle: Text(
        AppLocalizations.of(context).breakdownTransactionCount(bucket.count),
      ),
      trailing: Text(
        formatter.format(bucket.money),
        key: Key('breakdown-amount-$categoryId'),
        style: theme.textTheme.titleMedium,
      ),
      // No callback at all when there is nothing below: an enabled row that
      // drops the user onto an empty level is worse than one that does not
      // respond, and Material greys a disabled tile for free.
      onTap: canDrill && category != null
          ? () => onDrill(CategoryCrumb(
                id: category.id,
                path: category.path,
                name: category.name,
              ))
          : null,
    );
  }
}
