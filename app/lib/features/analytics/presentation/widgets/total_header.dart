import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../settings/application/settings_providers.dart';
import '../../application/period_label.dart';

/// A body's total, captioned with the period it covers.
///
/// One widget for the breakdown's and the cross-tab's headers, which were
/// identical apart from their keys: two copies of a caption are two places for
/// it to go stale, and the first copy already outlived the assumption that a
/// body only ever shows the current month.
class TotalHeader extends ConsumerWidget {
  const TotalHeader({
    super.key,
    required this.range,
    required this.total,
    required this.formatter,
    required this.keyPrefix,
  });

  /// The period the total covers: what the caption names.
  final DateRange range;

  final Money total;
  final MoneyFormatter formatter;

  /// Keys are `<prefix>-total`, `<prefix>-total-label`, `<prefix>-total-amount`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      key: Key('$keyPrefix-total'),
      padding: const EdgeInsets.all(NimbusTokens.space4),
      child: Column(
        children: [
          Text(
            totalCaption(
              range,
              ref.watch(calendarProvider),
              today: DateKey.fromDateTime(DateTime.now()),
              thisMonth: AppLocalizations.of(context).txMonthTotal,
              // The passed formatter, not the provider: a body renders with
              // the digits its caller chose, and a caption in Latin digits
              // over an amount in Persian ones would be one header in two
              // scripts.
              persianDigits: formatter.persianDigits,
            ),
            key: Key('$keyPrefix-total-label'),
            style: theme.textTheme.labelMedium,
          ),
          Text(
            formatter.format(total),
            key: Key('$keyPrefix-total-amount'),
            style: theme.textTheme.headlineSmall,
          ),
        ],
      ),
    );
  }
}
