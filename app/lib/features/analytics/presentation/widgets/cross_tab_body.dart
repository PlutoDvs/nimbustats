import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../categories/data/category_tree.dart';
import '../../../tags/data/tag_tree.dart';
import 'total_header.dart';

/// Spending per tag against category, as a grid.
class CrossTabBody extends StatelessWidget {
  const CrossTabBody({
    super.key,
    required this.result,
    required this.period,
    required this.categoriesById,
    required this.tagsById,
    required this.formatter,
  });

  final AnalyticsResult result;

  /// The period [result] covers, for the caption over the total.
  final DateRange period;
  final Map<String, CategoryNode> categoriesById;
  final Map<String, TagNode> tagsById;
  final MoneyFormatter formatter;

  static const _cellWidth = 110.0;
  static const _labelWidth = 120.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (result.buckets.isEmpty) {
      return NimbusEmptyState(
        icon: Icons.grid_on_outlined,
        title: l10n.analyticsEmptyTitle,
        message: l10n.analyticsEmptyBody,
      );
    }

    final cells = <(String, String), Money>{
      for (final bucket in result.buckets)
        if (bucket.key case TagCategoryKey(:final tagId, :final categoryId))
          (tagId, categoryId): bucket.money,
    };

    // Axes are derived from the cells rather than from the whole tree, so the
    // grid only shows tags and categories that were actually spent on. A
    // column of blanks for a category nobody used is width this screen cannot
    // spare.
    final tagIds = cells.keys.map((c) => c.$1).toSet().toList()
      ..sort((a, b) => _nameOfTag(a).compareTo(_nameOfTag(b)));
    final categoryIds = cells.keys.map((c) => c.$2).toSet().toList()
      ..sort((a, b) => _nameOfCategory(a).compareTo(_nameOfCategory(b)));

    return ListView(
      children: [
        TotalHeader(
          range: period,
          // Each transaction once. The cells add up to more than this, which
          // is what the banner below exists to say.
          total: result.trueTotal,
          formatter: formatter,
          keyPrefix: 'crosstab',
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: NimbusTokens.space4),
          child: _Disclosure(),
        ),
        const SizedBox(height: NimbusTokens.space4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderRow(
                categoryIds: categoryIds,
                nameOf: _nameOfCategory,
                cellWidth: _cellWidth,
                labelWidth: _labelWidth,
                totalLabel: l10n.crossTabRowTotal,
              ),
              for (final tagId in tagIds)
                _TagRow(
                  tagId: tagId,
                  tagName: _nameOfTag(tagId),
                  categoryIds: categoryIds,
                  cells: cells,
                  formatter: formatter,
                  cellWidth: _cellWidth,
                  labelWidth: _labelWidth,
                ),
              // No column totals, deliberately. Down a category column the
              // same transaction appears once per tag it carries, so a total
              // there would be double counted -- and it would sit in a row of
              // otherwise trustworthy numbers, which is worse than absent.
            ],
          ),
        ),
      ],
    );
  }

  String _nameOfTag(String id) => tagsById[id]?.value.name ?? id;

  String _nameOfCategory(String id) =>
      categoriesById[id]?.category.name ?? id;
}

class _Disclosure extends StatelessWidget {
  const _Disclosure();

  @override
  Widget build(BuildContext context) {
    // Unconditional, unlike the breakdown's. A tag axis always overlaps, so
    // there is no data for which this matrix reconciles with its own total.
    return NimbusDisclosureBanner(
      message: AppLocalizations.of(context).crossTabDisclosure,
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.categoryIds,
    required this.nameOf,
    required this.cellWidth,
    required this.labelWidth,
    required this.totalLabel,
  });

  final List<String> categoryIds;
  final String Function(String) nameOf;
  final double cellWidth;
  final double labelWidth;
  final String totalLabel;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    return Row(
      children: [
        SizedBox(width: labelWidth),
        for (final id in categoryIds)
          SizedBox(
            width: cellWidth,
            child: Padding(
              padding: const EdgeInsets.all(NimbusTokens.space2),
              child: Text(nameOf(id), style: style, textAlign: TextAlign.end),
            ),
          ),
        SizedBox(
          width: cellWidth,
          child: Padding(
            padding: const EdgeInsets.all(NimbusTokens.space2),
            child: Text(totalLabel, style: style, textAlign: TextAlign.end),
          ),
        ),
      ],
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tagId,
    required this.tagName,
    required this.categoryIds,
    required this.cells,
    required this.formatter,
    required this.cellWidth,
    required this.labelWidth,
  });

  final String tagId;
  final String tagName;
  final List<String> categoryIds;
  final Map<(String, String), Money> cells;
  final MoneyFormatter formatter;
  final double cellWidth;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Honest, unlike a column total: within one tag's row the categories are
    // disjoint, so each transaction is counted exactly once across it.
    final rowTotal = Money.sum([
      for (final categoryId in categoryIds)
        cells[(tagId, categoryId)] ?? Money.zero,
    ]);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NimbusTokens.space1),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Padding(
              padding: const EdgeInsets.all(NimbusTokens.space2),
              child: Text(tagName, style: theme.textTheme.bodyMedium),
            ),
          ),
          for (final categoryId in categoryIds)
            SizedBox(
              width: cellWidth,
              child: Padding(
                padding: const EdgeInsets.all(NimbusTokens.space2),
                child: switch (cells[(tagId, categoryId)]) {
                  // Blank, not a zero. "Never spent" and "measured as nothing"
                  // are different claims, and a grid of zeroes reads as the
                  // second one.
                  null => const SizedBox.shrink(),
                  final amount => Text(
                      formatter.format(amount),
                      key: Key('crosstab-cell-$tagId-$categoryId'),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium,
                    ),
                },
              ),
            ),
          SizedBox(
            width: cellWidth,
            child: Padding(
              padding: const EdgeInsets.all(NimbusTokens.space2),
              child: Text(
                formatter.format(rowTotal),
                key: Key('crosstab-row-total-$tagId'),
                textAlign: TextAlign.end,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
