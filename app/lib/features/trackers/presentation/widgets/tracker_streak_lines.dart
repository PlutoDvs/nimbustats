import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../application/tracker_providers.dart';

/// The detail header's two quieter lines: the streak, and how long since the
/// last entry.
///
/// Nothing at all for a tracker never logged, because the History tab's empty
/// state already says what to do. Nothing while the first answer loads, so
/// the header does not jump on open. After that the lines stay: a write's
/// re-run, a calendar switch and a new day all keep the previous streaks
/// until the new ones land (`trackerStreaksProvider`).
class TrackerStreakLines extends ConsumerWidget {
  const TrackerStreakLines({super.key, required this.trackerId});

  final String trackerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final streaks = ref.watch(trackerStreaksProvider(trackerId));

    if (streaks.hasError) {
      return Row(
        children: [
          Expanded(
            child: Text(l10n.trackerStreakErrorTitle,
                key: const Key('tracker-streak-error'), style: style),
          ),
          TextButton(
            // The whole family: the streak's question is asked again.
            onPressed: () => ref.invalidate(trackerResultProvider),
            child: Text(l10n.commonRetry),
          ),
        ],
      );
    }
    if (!streaks.hasValue) return const SizedBox.shrink();
    final value = streaks.requireValue;
    final since = value.daysSinceLast;
    if (since == null) return const SizedBox.shrink();

    final format = ref.watch(trackerFormatProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value.current > 0
              ? l10n.trackerStreakLine(value.current,
                  format.digits(value.current), format.digits(value.longest))
              : l10n.trackerStreakBestOnly(
                  value.longest, format.digits(value.longest)),
          key: const Key('tracker-streak'),
          style: style,
        ),
        Text(
          switch (since) {
            0 => l10n.trackerLastEntryToday,
            1 => l10n.trackerLastEntryYesterday,
            _ => l10n.trackerLastEntryDaysAgo(format.digits(since)),
          },
          key: const Key('tracker-last-entry'),
          style: style,
        ),
      ],
    );
  }
}
