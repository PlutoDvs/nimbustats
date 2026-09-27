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
    // chevron_left/chevron_right do not mirror on their own -- in RTL the
    // buttons swap sides but the glyphs would keep pointing the same way, so
    // "previous" would draw an arrow that points further into the future.
    // Pick the glyph from the ambient direction instead of hardcoding it, so
    // the arrow always points back in time regardless of script.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Row(
      children: [
        IconButton(
          key: Key('$keyPrefix-previous'),
          icon: Icon(rtl ? Icons.chevron_right : Icons.chevron_left),
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
          icon: Icon(rtl ? Icons.chevron_left : Icons.chevron_right),
          tooltip: l10n.periodNextMonth,
          onPressed: () => onShift(1),
        ),
      ],
    );
  }
}
