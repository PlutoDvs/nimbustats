import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../application/tag_providers.dart';
import '../data/tag_repository.dart';
import '../data/tag_tree.dart';
import 'widgets/tag_editor_sheet.dart';
import 'widgets/tag_move_target_sheet.dart';
import 'widgets/tag_row.dart';

/// Create, rename, recolour, nest, reorder, archive, and delete tags.
///
/// The same four states as the category manager, but `empty` is the state a
/// first-time user actually lands in: tags are not seeded, so this screen is
/// where the concept has to be explained rather than merely reported as
/// missing.
class TagManagerScreen extends ConsumerWidget {
  const TagManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tree = ref.watch(tagTreeProvider);
    final repository = ref.watch(tagRepositoryProvider);
    // hasError/hasValue rather than a switch over AsyncError/AsyncData: see
    // CategoryManagerScreen -- Riverpod 3 reports a stream that errors before
    // its first value as an AsyncLoading carrying an error.
    final roots = tree.hasError ? null : tree.value;

    final Widget body;
    if (tree.hasError) {
      body = NimbusErrorState(
        title: l10n.tagErrorTitle,
        retryLabel: l10n.commonRetry,
        detail: tree.error.toString(),
        onRetry: () => ref.invalidate(tagTreeProvider),
      );
    } else if (roots == null) {
      body = const NimbusLoadingList(rows: 6);
    } else if (roots.isEmpty) {
      body = NimbusEmptyState(
        icon: Icons.label_outline,
        title: l10n.tagEmptyTitle,
        // Says what a tag *is*, not that there is no data. Tags are the one
        // Phase 1 concept a first-time user has never configured, and an empty
        // list that does not teach is a dead end.
        message: l10n.tagEmptyMessage,
        actionLabel: l10n.tagEmptyAction,
        onAction: () => showTagEditorSheet(context, repository: repository),
      );
    } else {
      body = _TagList(roots: roots, repository: repository);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tagManagerTitle)),
      body: body,
      floatingActionButton: roots == null || roots.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const Key('tag-add'),
              onPressed: () =>
                  showTagEditorSheet(context, repository: repository),
              icon: const Icon(Icons.add),
              label: Text(l10n.tagEmptyAction),
            ),
    );
  }
}

class _TagList extends StatelessWidget {
  const _TagList({required this.roots, required this.repository});

  final List<TagNode> roots;
  final TagRepository repository;

  @override
  Widget build(BuildContext context) {
    final flat = TagTree.flatten(roots);

    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: NimbusTokens.space8 * 3),
      itemCount: flat.length,
      onReorderItem: (oldIndex, newIndex) =>
          _reorder(flat, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final node = flat[index];
        return TagRow(
          key: Key('tag-row-${node.value.id}'),
          node: node,
          onTap: () => showTagEditorSheet(
            context,
            repository: repository,
            tag: node.value,
          ),
          onAction: (action) => _onAction(context, node, action),
        );
      },
    );
  }

  void _reorder(List<TagNode> flat, int oldIndex, int newIndex) {
    final next = TagTree.reorderedSiblings(
      flat: flat,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
    if (next == null) return;
    unawaited(repository.reorder(next.parentId, next.orderedIds));
  }

  Future<void> _onAction(
    BuildContext context,
    TagNode node,
    TagRowAction action,
  ) async {
    switch (action) {
      case TagRowAction.rename:
      case TagRowAction.appearance:
        await showTagEditorSheet(
          context,
          repository: repository,
          tag: node.value,
        );
      case TagRowAction.move:
        await showTagMoveTargetSheet(
          context,
          repository: repository,
          tree: roots,
          moving: node,
        );
      case TagRowAction.archive:
        await repository.archive(node.value.id);
      case TagRowAction.unarchive:
        await repository.unarchive(node.value.id);
      case TagRowAction.delete:
        await _delete(context, node.value);
    }
  }

  Future<void> _delete(BuildContext context, Tag tag) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final deleted = await repository.delete(tag.id);
    messenger.showSnackBar(nimbusUndoSnackBar(
      message: l10n.tagDeleted(tag.name),
      undoLabel: l10n.commonUndo,
      onUndo: () => unawaited(repository.restore(deleted)),
    ));
  }
}
