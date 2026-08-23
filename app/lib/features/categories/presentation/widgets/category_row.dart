import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/category_tree.dart';
import 'icon_picker.dart';

/// What a row's overflow menu can do.
enum CategoryRowAction { rename, appearance, move, archive, unarchive, delete }

/// One category in the manager list.
///
/// Rendered flat with its own indent rather than nested, because
/// `ReorderableListView` needs a flat child list -- see the comment on the
/// manager screen for why reordering is confined to a sibling group.
class CategoryRow extends StatelessWidget {
  const CategoryRow({
    super.key,
    required this.node,
    required this.onTap,
    required this.onAction,
  });

  final CategoryNode node;
  final VoidCallback onTap;
  final ValueChanged<CategoryRowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final category = node.category;
    final isSystem = SystemCategoryIds.isSystem(category.id);

    // Indent stops growing after the cap so a six-deep tree still fits a
    // narrow screen. Placed at the row's start rather than as a left padding,
    // which is what makes it indent from the right in Persian for free.
    final indent = math.min(node.depth, NimbusTokens.maxTreeIndentDepth) *
        NimbusTokens.indentPerLevel;

    final badges = <Widget>[
      if (node.children.isNotEmpty)
        Text(
          l10n.categoryChildCount(node.children.length),
          style: theme.textTheme.bodySmall,
        ),
      if (category.archived)
        Text(
          l10n.categoryArchivedBadge,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
    ];

    return ListTile(
      onTap: onTap,
      minTileHeight: NimbusTokens.minTapTarget,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(key: Key('category-indent-${category.id}'), width: indent),
          // Decorative: the name carries the meaning, so announcing the icon
          // as well would only make a screen reader repeat itself.
          ExcludeSemantics(
            child: Icon(
              categoryIconFor(category.iconKey),
              color: Color(category.color),
            ),
          ),
        ],
      ),
      title: Text(
        category.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // A Wrap rather than a Row: at six levels of indent on a 320pt screen
      // there is not always room for both badges side by side, and a subtitle
      // must never be the thing that overflows a row.
      subtitle: badges.isEmpty
          ? null
          : Wrap(spacing: NimbusTokens.space2, children: badges),
      trailing: PopupMenuButton<CategoryRowAction>(
        key: Key('category-menu-${category.id}'),
        onSelected: onAction,
        itemBuilder: (context) => [
          // The repository guards the system row, but a menu that offers an
          // action which always throws is a bug in its own right, so the
          // offer is withheld here too.
          if (!isSystem)
            PopupMenuItem(
              value: CategoryRowAction.rename,
              child: Text(l10n.commonRename),
            ),
          PopupMenuItem(
            value: CategoryRowAction.appearance,
            child: Text(l10n.categoryIconLabel),
          ),
          if (!isSystem) ...[
            PopupMenuItem(
              value: CategoryRowAction.move,
              child: Text(l10n.commonMoveTo),
            ),
            PopupMenuItem(
              value: category.archived
                  ? CategoryRowAction.unarchive
                  : CategoryRowAction.archive,
              child: Text(category.archived
                  ? l10n.commonUnarchive
                  : l10n.commonArchive),
            ),
            PopupMenuItem(
              value: CategoryRowAction.delete,
              child: Text(l10n.commonDelete),
            ),
          ],
        ],
      ),
    );
  }
}
