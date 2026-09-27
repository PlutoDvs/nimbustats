import 'package:flutter/material.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/payment_method_repository.dart';
import '../payment_method_manager_screen.dart';

/// Opens the create/edit sheet for a payment method.
///
/// Resolves to the method just created, so a caller can put it straight to
/// use -- the add screen's "+" selects it on the expense being entered. Null
/// when the sheet was dismissed or an existing method was edited.
Future<PaymentMethod?> showPaymentMethodEditorSheet(
  BuildContext context, {
  required PaymentMethodRepository repository,
  PaymentMethod? method,
}) =>
    showModalBottomSheet<PaymentMethod>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PaymentMethodEditorSheet(
        repository: repository,
        method: method,
      ),
    );

class PaymentMethodEditorSheet extends StatefulWidget {
  const PaymentMethodEditorSheet({
    super.key,
    required this.repository,
    this.method,
  });

  final PaymentMethodRepository repository;
  final PaymentMethod? method;

  @override
  State<PaymentMethodEditorSheet> createState() =>
      _PaymentMethodEditorSheetState();
}

class _PaymentMethodEditorSheetState extends State<PaymentMethodEditorSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.method?.name ?? '');
  late final TextEditingController _last4 =
      TextEditingController(text: widget.method?.last4 ?? '');
  late PaymentMethodKind _kind = widget.method?.kind ?? PaymentMethodKind.cash;
  late int _color = widget.method?.color ?? NimbusColors.defaultSwatch.toARGB32();
  late String _iconKey = widget.method?.iconKey ?? 'card';
  String? _last4Error;

  @override
  void dispose() {
    _name.dispose();
    _last4.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) return;

    // Validated here as well as in the repository, because the repository
    // throws -- correct for a programming error, wrong as a way to tell a user
    // they mistyped. This turns it into a field error before it gets there.
    final typed = Digits.toLatin(_last4.text).trim();
    final last4 = typed.isEmpty ? null : typed;
    if (last4 != null && !RegExp(r'^\d{4}$').hasMatch(last4)) {
      setState(() => _last4Error = l10n.payLast4Invalid);
      return;
    }

    final existing = widget.method;
    if (existing == null) {
      final created = await widget.repository.create(
        name: name,
        kind: _kind,
        last4: last4,
        color: _color,
        iconKey: _iconKey,
      );
      navigator.pop(created);
      return;
    }
    await widget.repository.update(
      existing.id,
      name: name,
      kind: _kind,
      last4: last4,
      color: _color,
      iconKey: _iconKey,
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: NimbusTokens.space4,
        right: NimbusTokens.space4,
        top: NimbusTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NimbusTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.method == null ? l10n.payNewTitle : l10n.payEditTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: NimbusTokens.space4),
            TextField(
              key: const Key('pay-name-field'),
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.payNameLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: NimbusTokens.space4),
            Semantics(
              label: l10n.payKindLabel,
              container: true,
              child: SegmentedButton<PaymentMethodKind>(
                key: const Key('pay-kind-field'),
                segments: [
                  for (final kind in PaymentMethodKind.values)
                    ButtonSegment(
                      value: kind,
                      label: Text(paymentMethodKindLabel(l10n, kind)),
                    ),
                ],
                selected: {_kind},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _kind = selection.first),
              ),
            ),
            const SizedBox(height: NimbusTokens.space4),
            TextField(
              key: const Key('pay-last4-field'),
              controller: _last4,
              keyboardType: TextInputType.number,
              // Four, not sixteen: the field cannot physically hold a card
              // number, which is a stronger guarantee than validating one.
              maxLength: 4,
              decoration: InputDecoration(
                labelText: l10n.payLast4Label,
                errorText: _last4Error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_last4Error != null) setState(() => _last4Error = null);
              },
            ),
            const SizedBox(height: NimbusTokens.space4),
            IconPicker(
              selected: _iconKey,
              semanticsLabel: l10n.categoryIconLabel,
              onSelected: (key) => setState(() => _iconKey = key),
            ),
            const SizedBox(height: NimbusTokens.space4),
            ColorPicker(
              selected: _color,
              semanticsLabel: l10n.categoryColorLabel,
              onSelected: (value) => setState(() => _color = value),
            ),
            const SizedBox(height: NimbusTokens.space6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: NimbusTokens.space2),
                FilledButton(
                  key: const Key('pay-save'),
                  onPressed: _save,
                  child: Text(l10n.commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
