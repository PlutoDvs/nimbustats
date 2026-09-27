import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/saved_view_providers.dart';
import '../../data/pin_request.dart';
import 'view_name_sheet.dart';

/// The pin on a tab or chart: names what is shown and puts it on the
/// dashboard.
class PinButton extends ConsumerWidget {
  const PinButton({super.key, required this.request});

  final PinRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
        key: Key('pin-${request.chart.name}'),
        icon: const Icon(Icons.push_pin_outlined),
        tooltip: AppLocalizations.of(context).pinToDashboard,
        onPressed: () => _pin(context, ref),
      );

  Future<void> _pin(BuildContext context, WidgetRef ref) async {
    // Everything the write and the snackbar need is read before the sheet
    // opens: after it closes, this button may no longer be mounted.
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(savedViewsRepositoryProvider);

    final name = await showViewNameSheet(
      context,
      title: l10n.pinToDashboard,
      initialName: request.name,
      note: coverageOf(l10n, request.period),
    );
    if (name == null) return;

    await repository.pin([request.named(name)]);
    messenger.showSnackBar(SnackBar(content: Text(l10n.pinnedToDashboard)));
  }
}

/// The pin sheet's line saying what the card will cover.
///
/// Every pin source today is monthly. A source with another period needs its
/// own wording rather than a month sentence that would misdescribe it.
String coverageOf(AppLocalizations l10n, ViewPeriod period) =>
    switch (period) {
      ViewPeriod(type: PeriodType.month, count: 1) =>
        l10n.viewCoversCurrentMonth,
      ViewPeriod(type: PeriodType.month, :final count) =>
        l10n.viewCoversLastMonths(count),
      _ => throw UnsupportedError(
          'no coverage wording for ${period.type.name} periods yet'),
    };
