import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/tag_repository.dart';
import '../../data/tag_tree.dart';

/// Opens the "Move to…" sheet for [moving].
Future<void> showTagMoveTargetSheet(
  BuildContext context, {
  required TagRepository repository,
  required List<TagNode> tree,
  required TagNode moving,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => TagMoveTargetSheet(
        repository: repository,
        tree: tree,
        moving: moving,
      ),
    );

/// Drop targets for re-parenting a tag, invalid ones disabled up front.
///
/// Same rule as the category manager: an invalid drop is refused before it
/// happens rather than undone afterwards, and this sheet is also how the move
/// is reachable without a drag at all.
class TagMoveTargetSheet extends StatelessWidget {
  const TagMoveTargetSheet({
    super.key,
    required this.repository,
    required this.tree,
    required this.moving,
  });

  final TagRepository repository;
  final List<TagNode> tree;
  final TagNode moving;

  Future<void> _moveTo(BuildContext context, String? parentId) async {
    final navigator = Navigator.of(context);
    await repository.move(moving.value.id, parentId);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rootEnabled = TagTree.canMove(
      tree: tree,
      id: moving.value.id,
      newParentId: null,
    );

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: NimbusTokens.space2),
        children: [
          Padding(
            padding: const EdgeInsets.all(NimbusTokens.space4),
            child:
                Text(l10n.commonMoveTo, style: theme.textTheme.titleMedium),
          ),
          ListTile(
            key: const Key('tag-move-target-root'),
            enabled: rootEnabled,
            leading: const Icon(Icons.vertical_align_top),
            title: Text(l10n.categoryMoveToRoot),
            onTap: rootEnabled ? () => _moveTo(context, null) : null,
          ),
          for (final node in TagTree.flatten(tree))
            _target(context, l10n, node),
        ],
      ),
    );
  }

  Widget _target(
    BuildContext context,
    AppLocalizations l10n,
    TagNode node,
  ) {
    final enabled = TagTree.canMove(
      tree: tree,
      id: moving.value.id,
      newParentId: node.value.id,
    );
    final indent = math.min(node.depth, NimbusTokens.maxTreeIndentDepth) *
        NimbusTokens.indentPerLevel;

    return ListTile(
      key: Key('tag-move-target-${node.value.id}'),
      enabled: enabled,
      subtitle: enabled ? null : Text(l10n.categoryMoveInvalid),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: indent),
          ExcludeSemantics(
            child: Icon(
              nimbusIconFor(node.value.iconKey),
              color: Color(node.value.color),
            ),
          ),
        ],
      ),
      title:
          Text(node.value.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: enabled ? () => _moveTo(context, node.value.id) : null,
    );
  }
}
