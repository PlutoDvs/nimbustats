import 'package:flutter/material.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';

/// The two reflection axes, on the edit screen and nowhere else.
///
/// They are the input Phase 3's regret matrix runs on, and they are exactly
/// the sort of question that turns a three-second capture into a form. Asking
/// them later, when the user chose to open the transaction, costs nothing.
///
/// Both are clearable: tapping the selected option deselects it. The regret
/// matrix reports unlabelled totals separately rather than dropping them, so
/// "no answer" has to stay a state a user can actually get back to.
class NecessitySelector extends StatelessWidget {
  const NecessitySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Necessity? value;
  final ValueChanged<Necessity?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = NimbusSemanticColors.of(context);

    return _AxisRow(
      label: l10n.txNecessityLabel,
      children: [
        for (final option in Necessity.values)
          _AxisChip(
            keyName: 'tx-necessity-${option.name}',
            label: switch (option) {
              Necessity.needed => l10n.txNecessityNeeded,
              Necessity.optional => l10n.txNecessityOptional,
              Necessity.avoidable => l10n.txNecessityAvoidable,
            },
            tint: switch (option) {
              Necessity.needed => colors.necessityNeeded,
              Necessity.optional => colors.necessityOptional,
              Necessity.avoidable => colors.necessityAvoidable,
            },
            selected: value == option,
            onTap: () => onChanged(value == option ? null : option),
          ),
      ],
    );
  }
}

class SatisfactionSelector extends StatelessWidget {
  const SatisfactionSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Satisfaction? value;
  final ValueChanged<Satisfaction?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = NimbusSemanticColors.of(context);

    return _AxisRow(
      label: l10n.txSatisfactionLabel,
      children: [
        for (final option in Satisfaction.values)
          _AxisChip(
            keyName: 'tx-satisfaction-${option.name}',
            label: switch (option) {
              Satisfaction.glad => l10n.txSatisfactionGlad,
              Satisfaction.neutral => l10n.txSatisfactionNeutral,
              Satisfaction.regret => l10n.txSatisfactionRegret,
            },
            tint: switch (option) {
              Satisfaction.glad => colors.satisfactionGlad,
              Satisfaction.neutral => colors.satisfactionNeutral,
              Satisfaction.regret => colors.satisfactionRegret,
            },
            selected: value == option,
            onTap: () => onChanged(value == option ? null : option),
          ),
      ],
    );
  }
}

class _AxisRow extends StatelessWidget {
  const _AxisRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NimbusTokens.space4,
          vertical: NimbusTokens.space2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: NimbusTokens.space2),
            Wrap(spacing: NimbusTokens.space2, children: children),
          ],
        ),
      );
}

class _AxisChip extends StatelessWidget {
  const _AxisChip({
    required this.keyName,
    required this.label,
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  final String keyName;
  final String label;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: NimbusTokens.chipHeight),
        child: FilterChip(
          key: Key(keyName),
          selected: selected,
          // The label carries the meaning; the tint only reinforces it, which
          // is why the same palette is contrast-tested rather than trusted.
          selectedColor: tint.withValues(alpha: 0.18),
          checkmarkColor: tint,
          label: Text(label),
          onSelected: (_) => onTap(),
        ),
      );
}
