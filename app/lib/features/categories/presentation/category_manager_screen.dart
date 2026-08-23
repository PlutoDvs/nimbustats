import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../application/category_providers.dart';
import '../data/category_repository.dart';
import '../data/category_tree.dart';
import 'widgets/category_editor_sheet.dart';
import 'widgets/category_row.dart';
import 'widgets/move_target_sheet.dart';

/// Create, rename, recolour, move, reorder, archive, and delete categories.
///
/// All four required states are here rather than only the happy path: a screen
/// that renders nothing while it waits, or a raw exception when it fails, is
/// the default this project exists to avoid.
class CategoryManagerScreen extends ConsumerWidget {
  const CategoryManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tree = ref.watch(categoryTreeProvider);
    final repository = ref.watch(categoryRepositoryProvider);
    // Matched on hasError/hasValue rather than on AsyncError/AsyncData.
    // Riverpod 3 reports a stream that errors before its first value as an
    // AsyncLoading *carrying* an error, so a `switch` over the subtypes misses
    // it and the screen shows a skeleton for ever. The widget test for the
    // error state is what caught that.
    final roots = tree.hasError ? null : tree.value;

    final Widget body;
    if (tree.hasError) {
      body = NimbusErrorState(
        title: l10n.categoryErrorTitle,
        retryLabel: l10n.commonRetry,
        // Handed over but deliberately not rendered -- see NimbusErrorState.
        detail: tree.error.toString(),
        onRetry: () => ref.invalidate(categoryTreeProvider),
      );
    } else if (roots == null) {
      body = const NimbusLoadingList(rows: 6);
    } else if (roots.isEmpty) {
      body = NimbusEmptyState(
        icon: Icons.category_outlined,
        title: l10n.categoryEmptyTitle,
        message: l10n.categoryEmptyMessage,
        actionLabel: l10n.categoryEmptyAction,
        onAction: () => showCategoryEditorSheet(context, repository: repository),
      );
    } else {
      body = _CategoryList(roots: roots, repository: repository);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.categoryManagerTitle)),
      body: body,
      // Withheld unless the list has rows: the empty state already offers the
      // same action, and two identical calls to action on one screen is noise
      // rather than emphasis.
      floatingActionButton: roots == null || roots.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const Key('category-add'),
              onPressed: () =>
                  showCategoryEditorSheet(context, repository: repository),
              icon: const Icon(Icons.add),
              label: Text(l10n.categoryEmptyAction),
            ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.roots, required this.repository});

  final List<CategoryNode> roots;
  final CategoryRepository repository;

  @override
  Widget build(BuildContext context) {
    final flat = CategoryTree.flatten(roots);

    return ReorderableListView.builder(
      // Clearance for the extended FAB, so the last row is never trapped
      // underneath it.
      padding: const EdgeInsets.only(bottom: NimbusTokens.space8 * 3),
      itemCount: flat.length,
      onReorderItem: (oldIndex, newIndex) => _reorder(flat, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final node = flat[index];
        return CategoryRow(
          key: Key('category-row-${node.category.id}'),
          node: node,
          onTap: () => showCategoryEditorSheet(
            context,
            repository: repository,
            category: node.category,
          ),
          onAction: (action) => _onAction(context, node, action),
        );
      },
    );
  }

  /// Reordering is confined to a sibling group.
  ///
  /// The list is flat because `ReorderableListView` requires it, which makes a
  /// drag that crosses levels ambiguous. The decision of what a given drag
  /// means lives in [CategoryTree.reorderedSiblings], where the index
  /// arithmetic can be tested without a gesture.
  void _reorder(List<CategoryNode> flat, int oldIndex, int newIndex) {
    final next = CategoryTree.reorderedSiblings(
      flat: flat,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
    if (next == null) return;
    // Not awaited because the list is already redrawing from the stream; an
    // error still reaches the zone rather than being swallowed.
    unawaited(repository.reorder(next.parentId, next.orderedIds));
  }

  Future<void> _onAction(
    BuildContext context,
    CategoryNode node,
    CategoryRowAction action,
  ) async {
    switch (action) {
      // Rename and appearance are the same sheet; the menu entries differ only
      // in which field the user came for.
      case CategoryRowAction.rename:
      case CategoryRowAction.appearance:
        await showCategoryEditorSheet(
          context,
          repository: repository,
          category: node.category,
        );
      case CategoryRowAction.move:
        await showMoveTargetSheet(
          context,
          repository: repository,
          tree: roots,
          moving: node,
        );
      case CategoryRowAction.archive:
        await repository.archive(node.category.id);
      case CategoryRowAction.unarchive:
        await repository.unarchive(node.category.id);
      case CategoryRowAction.delete:
        await _delete(context, node.category);
    }
  }

  /// Soft delete plus undo. There is deliberately no confirmation dialog: the
  /// delete happens immediately, the list redraws from the stream, and the
  /// snackbar carries the way back.
  Future<void> _delete(BuildContext context, Category category) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final deleted = await repository.delete(category.id);
    messenger.showSnackBar(nimbusUndoSnackBar(
      message: l10n.categoryDeleted(category.name),
      undoLabel: l10n.commonUndo,
      onUndo: () => unawaited(repository.restore(deleted)),
    ));
  }
}
