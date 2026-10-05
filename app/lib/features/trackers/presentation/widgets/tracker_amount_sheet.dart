import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';

/// Asks for an amount other than the tracker's per-tap one.
///
/// Resolves to the amount, or null when dismissed. Accepts every digit set
/// and decimal point a Persian keyboard produces (`TrackerValues.parseAmount`),
/// and refuses zero or less in place rather than logging it.
Future<double?> showTrackerAmountSheet(
  BuildContext context, {
  required Tracker tracker,
}) {
  // The last tap's snackbar would float over the sheet's buttons, and a tap
  // meant for "Log" would land on it. Opening the sheet moves on from it.
  ScaffoldMessenger.of(context).removeCurrentSnackBar();
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AmountSheet(tracker: tracker),
  );
}

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({required this.tracker});

  final Tracker tracker;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final value = TrackerValues.parseAmount(_amount.text);
    if (value == null) {
      setState(() => _error = AppLocalizations.of(context).trackerAmountInvalid);
      return;
    }
    Navigator.of(context).pop(value);
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.trackerOtherAmount, style: theme.textTheme.titleMedium),
          const SizedBox(height: NimbusTokens.space4),
          TextField(
            key: const Key('tracker-amount-field'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.trackerAmountLabel,
              suffixText: widget.tracker.unit,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: NimbusTokens.space4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: NimbusTokens.space2),
              FilledButton(
                key: const Key('tracker-amount-log'),
                onPressed: _submit,
                child: Text(l10n.trackerLogAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
