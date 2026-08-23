import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../categories/application/category_providers.dart';
import '../../../categories/data/category_tree.dart';
import '../../application/prediction_providers.dart';

/// The predicted category chips, plus a way to reach the rest.
///
/// This row is the second of the three taps. Everything about it is in service
/// of that: the predictions are ranked before they arrive, the chips are wide
/// enough to hit without looking, and the row's height is reserved so it never
/// moves once it fills in.
class CategoryChips extends ConsumerWidget {
  const CategoryChips({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.merchant,
  });

  final String? selectedId;
  final ValueChanged<String> onSelected;

  /// Feeds the merchant short-circuit. Phase 2's captures pass the parsed
  /// merchant here and get a near-certain prediction for free.
  final String? merchant;

  /// Reserved height, held whether or not predictions have arrived.
  ///
  /// Predictions come from a database read, so they land a frame or two after
  /// first paint. Without a reserved box the amount field would shift upward
  /// under a thumb already on its way down -- the sort of jump that turns a
  /// three-tap flow into a mistyped amount.
  static const reservedHeight = NimbusTokens.chipHeight + NimbusTokens.space4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final predictor = ref.watch(categoryPredictorProvider).value;
    final tree = ref.watch(categoryTreeProvider).value ?? const [];

    final byId = {
      for (final node in CategoryTree.flatten(tree)) node.category.id: node,
    };
    final predicted = predictor
            ?.predict(merchant: merchant, limit: 4)
            .where((id) => _isOfferable(byId[id]))
            .toList() ??
        const <String>[];

    // A selection made from the full picker is not necessarily predicted, so
    // it is pinned in front rather than silently missing from the row.
    final ids = <String>[
      if (selectedId != null &&
          !predicted.contains(selectedId) &&
          _isOfferable(byId[selectedId]))
        selectedId!,
      ...predicted,
    ].take(4).toList();

    return SizedBox(
      height: reservedHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: NimbusTokens.space4),
        children: [
          for (final id in ids) ...[
            _Chip(
              node: byId[id]!,
              selected: id == selectedId,
              onSelected: () {
                // Confirms the tap without the user looking up from the
                // keypad, which is the point of a chip row at all.
                unawaited(HapticFeedback.selectionClick());
                onSelected(id);
              },
            ),
            const SizedBox(width: NimbusTokens.space2),
          ],
          ActionChip(
            key: const Key('tx-chip-more'),
            label: Text(l10n.txCategoryMore),
            onPressed: () => _openPicker(context, ref, byId),
          ),
        ],
      ),
    );
  }

  /// Archived categories and the reserved system row are never offered.
  ///
  /// Archiving is how a user says "stop showing me this", and Uncategorized is
  /// a fallback rather than a choice -- offering it would make the Phase 2
  /// "needs review" queries meaningless.
  static bool _isOfferable(CategoryNode? node) =>
      node != null &&
      !node.category.archived &&
      !SystemCategoryIds.isSystem(node.category.id);

  Future<void> _openPicker(
    BuildContext context,
    WidgetRef ref,
    Map<String, CategoryNode> byId,
  ) async {
    final offerable = byId.values.where((n) => _isOfferable(n)).toList()
      ..sort((a, b) => a.category.name.compareTo(b.category.name));

    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final node in offerable)
              ListTile(
                key: Key('tx-picker-${node.category.id}'),
                leading: ExcludeSemantics(
                  child: Icon(
                    nimbusIconFor(node.category.iconKey),
                    color: Color(node.category.color),
                  ),
                ),
                title: Text(node.category.name),
                selected: node.category.id == selectedId,
                onTap: () => Navigator.of(context).pop(node.category.id),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) onSelected(chosen);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.node,
    required this.selected,
    required this.onSelected,
  });

  final CategoryNode node;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: NimbusTokens.chipHeight),
        child: FilterChip(
          key: Key('tx-chip-${node.category.id}'),
          selected: selected,
          avatar: ExcludeSemantics(
            child: Icon(
              nimbusIconFor(node.category.iconKey),
              color: Color(node.category.color),
              size: 18,
            ),
          ),
          label: Text(node.category.name),
          onSelected: (_) => onSelected(),
        ),
      );
}
