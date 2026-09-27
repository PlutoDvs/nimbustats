import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../settings/application/settings_providers.dart';
import '../../application/period_label.dart';

/// ◀ month ▶, for the dashboard and the full-screen view.
class MonthBar extends ConsumerWidget {
  const MonthBar({
    super.key,
    required this.anchor,
    required this.onShift,
    required this.keyPrefix,
  });

  final DateKey anchor;
  final ValueChanged<int> onShift;

  /// Keys are `<prefix>-previous`, `<prefix>-label`, `<prefix>-next`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final calendar = ref.watch(calendarProvider);
    return Row(
      children: [
        IconButton(
          key: Key('$keyPrefix-previous'),
          icon: const Icon(Icons.chevron_left),
          tooltip: l10n.periodPreviousMonth,
          onPressed: () => onShift(-1),
        ),
        Expanded(
          child: Center(
            child: Text(
              periodLabel(
                calendar.periodContaining(anchor, PeriodType.month),
                calendar,
                persianDigits: ref.watch(moneyFormatterProvider).persianDigits,
              ),
              key: Key('$keyPrefix-label'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        IconButton(
          key: Key('$keyPrefix-next'),
          icon: const Icon(Icons.chevron_right),
          tooltip: l10n.periodNextMonth,
          onPressed: () => onShift(1),
        ),
      ],
    );
  }
}
