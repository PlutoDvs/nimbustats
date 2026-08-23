import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/tag_tree.dart';

/// What a tag row's overflow menu can do.
enum TagRowAction { rename, appearance, move, archive, unarchive, delete }

/// One tag in the manager list.
///
/// The same shape as `CategoryRow`, minus the reserved-row rules -- no tag is
/// protected -- and plus the usage count, which is what makes the picker's
/// ordering legible rather than mysterious.
class TagRow extends StatelessWidget {
  const TagRow({
    super.key,
    required this.node,
    required this.onTap,
    required this.onAction,
  });

  final TagNode node;
  final VoidCallback onTap;
  final ValueChanged<TagRowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tag = node.value;

    final indent = math.min(node.depth, NimbusTokens.maxTreeIndentDepth) *
        NimbusTokens.indentPerLevel;

    final badges = <Widget>[
      if (tag.usageCount > 0)
        Text(l10n.tagUsageCount(tag.usageCount),
            style: theme.textTheme.bodySmall),
      if (tag.archived)
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
          SizedBox(key: Key('tag-indent-${tag.id}'), width: indent),
          ExcludeSemantics(
            child: Icon(nimbusIconFor(tag.iconKey), color: Color(tag.color)),
          ),
        ],
      ),
      title: Text(tag.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: badges.isEmpty
          ? null
          : Wrap(spacing: NimbusTokens.space2, children: badges),
      trailing: PopupMenuButton<TagRowAction>(
        key: Key('tag-menu-${tag.id}'),
        onSelected: onAction,
        itemBuilder: (context) => [
          PopupMenuItem(
            value: TagRowAction.rename,
            child: Text(l10n.commonRename),
          ),
          PopupMenuItem(
            value: TagRowAction.appearance,
            child: Text(l10n.categoryIconLabel),
          ),
          PopupMenuItem(
            value: TagRowAction.move,
            child: Text(l10n.commonMoveTo),
          ),
          PopupMenuItem(
            value: tag.archived ? TagRowAction.unarchive : TagRowAction.archive,
            child: Text(
                tag.archived ? l10n.commonUnarchive : l10n.commonArchive),
          ),
          PopupMenuItem(
            value: TagRowAction.delete,
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }
}
