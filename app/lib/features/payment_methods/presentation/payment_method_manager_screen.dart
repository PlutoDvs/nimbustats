import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../application/payment_method_providers.dart';
import '../data/payment_method_repository.dart';
import 'widgets/payment_method_editor_sheet.dart';

/// Localised name for a [PaymentMethodKind].
///
/// Lives here rather than on the enum: `nimbus_data` has no ARB bundle and
/// must not gain one, so the mapping belongs on the app side of that boundary.
String paymentMethodKindLabel(AppLocalizations l10n, PaymentMethodKind kind) =>
    switch (kind) {
      PaymentMethodKind.cash => l10n.payKindCash,
      PaymentMethodKind.card => l10n.payKindCard,
      PaymentMethodKind.bank => l10n.payKindBank,
      PaymentMethodKind.other => l10n.payKindOther,
    };

/// Create, edit, archive, and delete the places money goes out from.
///
/// Flat, so there is no tree, no drag-to-reorder, and no move: a payment
/// method is a label on a transaction, not a hierarchy.
class PaymentMethodManagerScreen extends ConsumerWidget {
  const PaymentMethodManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final methods = ref.watch(paymentMethodsProvider);
    final repository = ref.watch(paymentMethodRepositoryProvider);
    // hasError/hasValue rather than a switch over the AsyncValue subtypes --
    // see CategoryManagerScreen for why the subtypes lie here.
    final rows = methods.hasError ? null : methods.value;

    final Widget body;
    if (methods.hasError) {
      body = NimbusErrorState(
        title: l10n.payErrorTitle,
        retryLabel: l10n.commonRetry,
        detail: methods.error.toString(),
        onRetry: () => ref.invalidate(paymentMethodsProvider),
      );
    } else if (rows == null) {
      body = const NimbusLoadingList(rows: 4);
    } else if (rows.isEmpty) {
      body = NimbusEmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: l10n.payEmptyTitle,
        message: l10n.payEmptyMessage,
        actionLabel: l10n.payEmptyAction,
        onAction: () =>
            showPaymentMethodEditorSheet(context, repository: repository),
      );
    } else {
      body = _MethodList(methods: rows, repository: repository);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.payManagerTitle)),
      body: body,
      floatingActionButton: rows == null || rows.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const Key('pay-add'),
              onPressed: () =>
                  showPaymentMethodEditorSheet(context, repository: repository),
              icon: const Icon(Icons.add),
              label: Text(l10n.payEmptyAction),
            ),
    );
  }
}

class _MethodList extends StatelessWidget {
  const _MethodList({required this.methods, required this.repository});

  final List<PaymentMethod> methods;
  final PaymentMethodRepository repository;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: NimbusTokens.space8 * 3),
      itemCount: methods.length,
      itemBuilder: (context, index) {
        final method = methods[index];
        final badges = <Widget>[
          Text(paymentMethodKindLabel(l10n, method.kind),
              style: theme.textTheme.bodySmall),
          if (method.last4 != null)
            // Rendered as the app stores it: four Latin digits, never a
            // reconstructed card number.
            Text('•••• ${method.last4}', style: theme.textTheme.bodySmall),
          if (method.archived)
            Text(
              l10n.categoryArchivedBadge,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ];

        return ListTile(
          key: Key('pay-row-${method.id}'),
          minTileHeight: NimbusTokens.minTapTarget,
          onTap: () => showPaymentMethodEditorSheet(
            context,
            repository: repository,
            method: method,
          ),
          leading: ExcludeSemantics(
            child: Icon(nimbusIconFor(method.iconKey),
                color: Color(method.color)),
          ),
          title:
              Text(method.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Wrap(spacing: NimbusTokens.space2, children: badges),
          trailing: PopupMenuButton<_MethodAction>(
            key: Key('pay-menu-${method.id}'),
            onSelected: (action) => _onAction(context, method, action),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _MethodAction.edit,
                child: Text(l10n.commonRename),
              ),
              PopupMenuItem(
                value: method.archived
                    ? _MethodAction.unarchive
                    : _MethodAction.archive,
                child: Text(method.archived
                    ? l10n.commonUnarchive
                    : l10n.commonArchive),
              ),
              PopupMenuItem(
                value: _MethodAction.delete,
                child: Text(l10n.commonDelete),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onAction(
    BuildContext context,
    PaymentMethod method,
    _MethodAction action,
  ) async {
    switch (action) {
      case _MethodAction.edit:
        await showPaymentMethodEditorSheet(
          context,
          repository: repository,
          method: method,
        );
      case _MethodAction.archive:
        await repository.archive(method.id);
      case _MethodAction.unarchive:
        await repository.unarchive(method.id);
      case _MethodAction.delete:
        await _delete(context, method);
    }
  }

  Future<void> _delete(BuildContext context, PaymentMethod method) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final deleted = await repository.delete(method.id);
    messenger.showSnackBar(nimbusUndoSnackBar(
      message: l10n.payDeleted(method.name),
      undoLabel: l10n.commonUndo,
      onUndo: () => unawaited(repository.restore(deleted)),
    ));
  }
}

enum _MethodAction { edit, archive, unarchive, delete }
