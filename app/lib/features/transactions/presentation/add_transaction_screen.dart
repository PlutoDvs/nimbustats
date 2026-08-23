import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../payment_methods/application/payment_method_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../tags/presentation/widgets/tag_picker_sheet.dart';
import '../application/add_transaction_controller.dart';
import '../application/transaction_providers.dart';
import 'widgets/amount_field.dart';
import 'widgets/category_chips.dart';

/// The screen the whole app is judged on.
///
/// Amount first, keypad already up, one predicted chip, save. Everything else
/// is behind "more details", because a field that is on screen is a field
/// someone feels obliged to fill in.
class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key, this.initialAmount});

  /// Prefills the amount. Exists for Phase 6's home-screen widget deep link,
  /// which passes `?amount=`; accepted now so the widget works the day it
  /// ships rather than requiring this screen to change then.
  final String? initialAmount;

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  late final TextEditingController _amount =
      TextEditingController(text: widget.initialAmount ?? '');
  final _amountFocus = FocusNode();
  final _merchant = TextEditingController();
  final _note = TextEditingController();
  bool _detailsOpen = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialAmount;
    if (initial != null && initial.isNotEmpty) {
      // After the first frame: the controller cannot be written to while the
      // widget tree that reads it is still building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(addTransactionControllerProvider.notifier)
            .setAmountText(initial);
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _amountFocus.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final controller = ref.read(addTransactionControllerProvider.notifier);
    final draft = controller.validate();
    if (draft == null) return;

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final repository = ref.read(transactionRepositoryProvider);

    // Confirms the capture without the user waiting to look at the screen.
    unawaited(HapticFeedback.mediumImpact());

    // Awaited before leaving, deliberately -- the plan called for popping
    // first. A local SQLite insert is sub-millisecond, so nothing is gained by
    // leaving early, and if the write does fail the user is still on the
    // screen holding the data instead of watching it disappear. No spinner
    // either way, which is what the interaction rule actually forbids.
    try {
      await repository.add(draft);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.txSaveFailed)));
      rethrow;
    }

    messenger.showSnackBar(SnackBar(content: Text(l10n.txSaved)));
    if (router.canPop()) router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(addTransactionControllerProvider);
    final controller = ref.read(addTransactionControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.addExpense)),
      body: ListView(
        padding: const EdgeInsets.all(NimbusTokens.space4),
        children: [
          SegmentedButton<TxDirection>(
            key: const Key('tx-direction'),
            segments: [
              ButtonSegment(
                value: TxDirection.expense,
                label: Text(l10n.txDirectionExpense),
              ),
              ButtonSegment(
                value: TxDirection.income,
                label: Text(l10n.txDirectionIncome),
              ),
            ],
            selected: {state.direction},
            showSelectedIcon: false,
            onSelectionChanged: (s) => controller.setDirection(s.first),
          ),
          const SizedBox(height: NimbusTokens.space4),
          AmountField(
            controller: _amount,
            focusNode: _amountFocus,
            formatter: ref.watch(moneyFormatterProvider),
            label: l10n.amount,
            errorText: state.amountError ? l10n.txAmountInvalid : null,
            onChanged: controller.setAmountText,
            onSubmitted: _save,
          ),
          const SizedBox(height: NimbusTokens.space2),
          CategoryChips(
            selectedId: state.categoryId,
            merchant: state.merchant,
            onSelected: controller.selectCategory,
          ),
          ExpansionTile(
            key: const Key('tx-more-details'),
            title: Text(l10n.txMoreDetails),
            initiallyExpanded: _detailsOpen,
            onExpansionChanged: (open) => _detailsOpen = open,
            childrenPadding:
                const EdgeInsets.only(bottom: NimbusTokens.space4),
            children: [
              _TagsTile(state: state, controller: controller),
              _PaymentMethodTile(state: state, controller: controller),
              _DateTile(state: state, controller: controller),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: NimbusTokens.space4),
                child: TextField(
                  key: const Key('tx-merchant-field'),
                  controller: _merchant,
                  decoration: InputDecoration(labelText: l10n.txMerchantLabel),
                  onChanged: controller.setMerchant,
                ),
              ),
              const SizedBox(height: NimbusTokens.space2),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: NimbusTokens.space4),
                child: TextField(
                  key: const Key('tx-note-field'),
                  controller: _note,
                  decoration: InputDecoration(labelText: l10n.txNoteLabel),
                  onChanged: controller.setNote,
                ),
              ),
            ],
          ),
        ],
      ),
      // Pinned to the bottom so it stays within one-handed reach whatever the
      // keyboard is doing.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(NimbusTokens.space4),
          child: SizedBox(
            height: NimbusTokens.minTapTarget,
            child: FilledButton(
              key: const Key('tx-save'),
              onPressed: _save,
              child: Text(
                l10n.commonSave,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TagsTile extends ConsumerWidget {
  const _TagsTile({required this.state, required this.controller});

  final AddTransactionState state;
  final AddTransactionController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const Key('tx-tags'),
      title: Text(l10n.txTagsLabel),
      subtitle: state.tagIds.isEmpty ? null : Text('${state.tagIds.length}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final chosen =
            await showTagPickerSheet(context, selected: state.tagIds);
        if (chosen != null) controller.setTags(chosen);
      },
    );
  }
}

class _PaymentMethodTile extends ConsumerWidget {
  const _PaymentMethodTile({required this.state, required this.controller});

  final AddTransactionState state;
  final AddTransactionController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final methods = ref.watch(pickablePaymentMethodsProvider).value ?? const [];
    final selected = methods.where((m) => m.id == state.paymentMethodId);

    return ListTile(
      key: const Key('tx-payment-method'),
      title: Text(l10n.txPaymentMethodLabel),
      subtitle: Text(selected.isEmpty ? l10n.payNone : selected.first.name),
      trailing: const Icon(Icons.chevron_right),
      onTap: methods.isEmpty
          ? null
          : () async {
              final chosen = await showModalBottomSheet<String?>(
                context: context,
                builder: (context) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        key: const Key('tx-payment-none'),
                        title: Text(l10n.payNone),
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      for (final method in methods)
                        ListTile(
                          key: Key('tx-payment-${method.id}'),
                          leading: ExcludeSemantics(
                            child: Icon(
                              nimbusIconFor(method.iconKey),
                              color: Color(method.color),
                            ),
                          ),
                          title: Text(method.name),
                          onTap: () => Navigator.of(context).pop(method.id),
                        ),
                    ],
                  ),
                ),
              );
              controller.setPaymentMethod(chosen);
            },
    );
  }
}

class _DateTile extends ConsumerWidget {
  const _DateTile({required this.state, required this.controller});

  final AddTransactionState state;
  final AddTransactionController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final calendar = ref.watch(calendarProvider);
    final persianDigits = ref.watch(moneyFormatterProvider).persianDigits;

    // Rendered through the active calendar, so a Jalali user sees a Jalali
    // date rather than a Gregorian one they have to convert in their head.
    final parts = calendar.partsOf(DateKey.fromDateTime(state.date));
    final label = '${parts.year}/'
        '${parts.month.toString().padLeft(2, '0')}/'
        '${parts.day.toString().padLeft(2, '0')}';

    return ListTile(
      key: const Key('tx-date'),
      title: Text(l10n.txDateLabel),
      subtitle: Text(persianDigits ? Digits.toPersian(label) : label),
      trailing: const Icon(Icons.calendar_today_outlined),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: state.date,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) controller.setDate(picked);
      },
    );
  }
}
