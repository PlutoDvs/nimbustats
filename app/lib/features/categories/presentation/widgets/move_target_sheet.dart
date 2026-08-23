import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/category_repository.dart';
import '../../data/category_tree.dart';
import 'icon_picker.dart';

/// Opens the "Move to…" sheet for [moving].
Future<void> showMoveTargetSheet(
  BuildContext context, {
  required CategoryRepository repository,
  required List<CategoryNode> tree,
  required CategoryNode moving,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => MoveTargetSheet(
        repository: repository,
        tree: tree,
        moving: moving,
      ),
    );

/// Every category as a flat, indented list of drop targets, plus the root.
///
/// Targets that would produce an invalid tree are rendered disabled rather
/// than accepted and then undone: the screen contract calls surfacing an
/// invalid drop as an after-the-fact error toast unacceptable, and
/// [CategoryTree.canMove] answers the question without touching the database.
///
/// This is also what makes re-parenting reachable without a drag, which is the
/// only way it works for anyone using a screen reader or switch control.
class MoveTargetSheet extends StatelessWidget {
  const MoveTargetSheet({
    super.key,
    required this.repository,
    required this.tree,
    required this.moving,
  });

  final CategoryRepository repository;
  final List<CategoryNode> tree;
  final CategoryNode moving;

  Future<void> _moveTo(BuildContext context, String? parentId) async {
    final navigator = Navigator.of(context);
    await repository.move(moving.category.id, parentId);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rootEnabled = CategoryTree.canMove(
      tree: tree,
      id: moving.category.id,
      newParentId: null,
    );

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: NimbusTokens.space2),
        children: [
          Padding(
            padding: const EdgeInsets.all(NimbusTokens.space4),
            child: Text(
              l10n.commonMoveTo,
              style: theme.textTheme.titleMedium,
            ),
          ),
          ListTile(
            key: const Key('move-target-root'),
            enabled: rootEnabled,
            leading: const Icon(Icons.vertical_align_top),
            title: Text(l10n.categoryMoveToRoot),
            onTap: rootEnabled ? () => _moveTo(context, null) : null,
          ),
          for (final node in CategoryTree.flatten(tree))
            _target(context, l10n, node),
        ],
      ),
    );
  }

  Widget _target(
    BuildContext context,
    AppLocalizations l10n,
    CategoryNode node,
  ) {
    final enabled = CategoryTree.canMove(
      tree: tree,
      id: moving.category.id,
      newParentId: node.category.id,
    );
    final indent = math.min(node.depth, NimbusTokens.maxTreeIndentDepth) *
        NimbusTokens.indentPerLevel;

    return ListTile(
      key: Key('move-target-${node.category.id}'),
      enabled: enabled,
      // Why it is unavailable, rather than leaving the user to guess -- a
      // dimmed row with no explanation reads as a bug.
      subtitle: enabled ? null : Text(l10n.categoryMoveInvalid),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: indent),
          ExcludeSemantics(
            child: Icon(
              categoryIconFor(node.category.iconKey),
              color: Color(node.category.color),
            ),
          ),
        ],
      ),
      title: Text(
        node.category.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: enabled ? () => _moveTo(context, node.category.id) : null,
    );
  }
}
