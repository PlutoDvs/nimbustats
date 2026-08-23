import 'package:flutter/material.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../categories/data/category_tree.dart';

/// One transaction in the list.
///
/// Fixed to a single line of merchant text on purpose: a row that reflows when
/// a merchant name is long makes the list jump while it loads, and a jumping
/// list is unusable at the scroll speeds this screen is built for.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.transaction,
    required this.category,
    required this.formatter,
    required this.onTap,
  });

  final Transaction transaction;
  final CategoryNode? category;
  final MoneyFormatter formatter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantics = NimbusSemanticColors.of(context);
    final isIncome = transaction.direction == TxDirection.income;

    // The sign carries the meaning, not the hue. Red and green alone fail for
    // roughly one man in twelve, and the theme's own contrast tests exist
    // because colour is a second channel here rather than the only one.
    final sign = isIncome ? '+' : '−';
    final amount = '$sign${formatter.format(transaction.amount)}';

    final title = transaction.merchant ?? category?.category.name ?? '';

    return ListTile(
      key: Key('tx-row-${transaction.id}'),
      onTap: onTap,
      minTileHeight: NimbusTokens.minTapTarget,
      leading: ExcludeSemantics(
        child: Icon(
          nimbusIconFor(category?.category.iconKey ?? 'tag'),
          color: category == null ? null : Color(category!.category.color),
        ),
      ),
      title: Text(
        title,
        key: Key('tx-merchant-${transaction.id}'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: transaction.note == null
          ? null
          : Text(
              transaction.note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            key: Key(
              'tx-direction-icon-${isIncome ? 'income' : 'expense'}',
            ),
            isIncome ? Icons.south_west : Icons.north_east,
            size: 16,
            color: isIncome ? semantics.income : semantics.expense,
          ),
          const SizedBox(width: NimbusTokens.space1),
          Text(
            amount,
            style: theme.textTheme.titleSmall?.copyWith(
              color: isIncome ? semantics.income : semantics.expense,
            ),
          ),
        ],
      ),
    );
  }
}
