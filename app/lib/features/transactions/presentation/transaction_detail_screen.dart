import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/application/settings_providers.dart';
import '../../tags/application/tag_providers.dart';
import '../../tags/presentation/widgets/tag_chip_row.dart';
import '../../tags/presentation/widgets/tag_picker_sheet.dart';
import '../application/transaction_list_controller.dart';
import '../application/transaction_providers.dart';
import 'widgets/amount_field.dart';
import 'widgets/reflection_selectors.dart';

/// One transaction, editable.
///
/// This is where necessity and satisfaction live. They are the input Phase 3's
/// regret matrix runs on, and they are precisely what the add flow cannot
/// afford -- someone who opened a transaction on purpose has time for them.
class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen> {
  final _amount = TextEditingController();
  final _amountFocus = FocusNode();
  final _note = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _amount.dispose();
    _amountFocus.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Refreshes everything a write invalidates.
  ///
  /// The list is refreshed too: it holds a page of rows, not a live query, so
  /// an edit made here would otherwise stay invisible behind the back button.
  void _afterWrite({bool tags = false}) {
    ref.invalidate(transactionByIdProvider(widget.id));
    if (tags) ref.invalidate(transactionTagsProvider(widget.id));
    unawaited(ref.read(transactionListControllerProvider.notifier).refresh());
  }

  Future<void> _setReflection({
    Necessity? necessity,
    Satisfaction? satisfaction,
    required Transaction current,
    bool clearNecessity = false,
    bool clearSatisfaction = false,
  }) async {
    await ref.read(transactionRepositoryProvider).setReflection(
          widget.id,
          necessity: clearNecessity ? null : necessity ?? current.necessity,
          satisfaction:
              clearSatisfaction ? null : satisfaction ?? current.satisfaction,
        );
    _afterWrite();
  }

  Future<void> _delete(Transaction transaction) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final repository = ref.read(transactionRepositoryProvider);
    final listController =
        ref.read(transactionListControllerProvider.notifier);

    await repository.softDelete(transaction.id);
    unawaited(listController.refresh());

    // Soft delete plus undo. No confirmation dialog exists anywhere in this
    // app, and `test/ux_rules_test.dart` fails the build if one appears.
    messenger.showSnackBar(nimbusUndoSnackBar(
      message: l10n.txDeleted,
      undoLabel: l10n.commonUndo,
      onUndo: () async {
        await repository.restore(transaction.id);
        unawaited(listController.refresh());
      },
    ));
    if (router.canPop()) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(transactionByIdProvider(widget.id));
    final formatter = ref.watch(moneyFormatterProvider);
    final repository = ref.watch(transactionRepositoryProvider);

    final Widget body;
    if (async.hasError) {
      body = NimbusErrorState(
        title: l10n.txListErrorTitle,
        retryLabel: l10n.commonRetry,
        detail: async.error.toString(),
        onRetry: () => ref.invalidate(transactionByIdProvider(widget.id)),
      );
    } else if (async.value == null) {
      body = const NimbusLoadingList(rows: 4);
    } else {
      final transaction = async.value!;
      if (!_seeded) {
        _seeded = true;
        _amount.text = formatter.format(transaction.amount);
        _note.text = transaction.note ?? '';
      }

      body = ListView(
        padding: const EdgeInsets.symmetric(vertical: NimbusTokens.space4),
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: NimbusTokens.space4),
            child: AmountField(
              controller: _amount,
              focusNode: _amountFocus,
              formatter: formatter,
              label: l10n.amount,
              onChanged: (_) {},
            ),
          ),
          const SizedBox(height: NimbusTokens.space2),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: NimbusTokens.space4),
            child: TextField(
              key: const Key('tx-detail-note'),
              controller: _note,
              decoration: InputDecoration(labelText: l10n.txNoteLabel),
            ),
          ),
          _TagsTile(
            transactionId: widget.id,
            onChanged: () => _afterWrite(tags: true),
          ),
          NecessitySelector(
            value: transaction.necessity,
            onChanged: (value) => _setReflection(
              current: transaction,
              necessity: value,
              clearNecessity: value == null,
            ),
          ),
          SatisfactionSelector(
            value: transaction.satisfaction,
            onChanged: (value) => _setReflection(
              current: transaction,
              satisfaction: value,
              clearSatisfaction: value == null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(NimbusTokens.space4),
            child: SizedBox(
              height: NimbusTokens.minTapTarget,
              child: FilledButton(
                key: const Key('tx-detail-save'),
                onPressed: () async {
                  final parsed = formatter.parse(_amount.text);
                  if (parsed != null && parsed.minorUnits != 0) {
                    await repository.setAmount(widget.id, parsed);
                  }
                  final note = _note.text.trim();
                  await repository.setNote(
                    widget.id,
                    note.isEmpty ? null : note,
                  );
                  _afterWrite();
                },
                child: Text(l10n.commonSave),
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.txDetailTitle),
        actions: [
          if (async.value != null)
            IconButton(
              key: const Key('tx-delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(async.value!),
            ),
        ],
      ),
      body: body,
    );
  }
}

class _TagsTile extends ConsumerWidget {
  const _TagsTile({required this.transactionId, required this.onChanged});

  final String transactionId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tagIds =
        ref.watch(transactionTagsProvider(transactionId)).value ?? const [];
    final allTags = ref.watch(tagPickerOptionsProvider).value ?? const [];
    final attached = allTags.where((t) => tagIds.contains(t.id)).toList();

    return ListTile(
      key: const Key('tx-detail-tags'),
      title: Text(l10n.txTagsLabel),
      subtitle: attached.isEmpty
          ? null
          : TagChipRow(tags: attached, moreKey: const Key('tx-tags-more')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final chosen =
            await showTagPickerSheet(context, selected: tagIds.toSet());
        if (chosen == null) return;
        final row = await ref
            .read(transactionByIdProvider(transactionId).future);
        if (row == null) return;
        await ref
            .read(transactionRepositoryProvider)
            .update(row, tagIds: chosen.toList());
        onChanged();
      },
    );
  }
}
