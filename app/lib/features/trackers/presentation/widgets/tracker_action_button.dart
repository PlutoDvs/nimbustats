import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../application/tracker_providers.dart';
import 'tracker_amount_sheet.dart';
import 'tracker_logger.dart';

/// A tracker's one-tap action: +1, done, +amount, or start/stop.
///
/// The same widget on the tab and in the detail screen's quick-log bar, so a
/// tap means the same thing, and writes through the same path, wherever it
/// happens.
class TrackerActionButton extends ConsumerWidget {
  const TrackerActionButton({
    super.key,
    required this.tracker,
    required this.total,
  });

  final Tracker tracker;

  /// Today's total, which decides a boolean tracker's done state.
  final double total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    TrackerLogger logger() => TrackerLogger(
          messenger: ScaffoldMessenger.of(context),
          l10n: l10n,
          repository: ref.read(trackerRepositoryProvider),
          format: ref.read(trackerFormatProvider),
          tracker: tracker,
        );
    final key = Key('tracker-action-${tracker.id}');
    final format = ref.watch(trackerFormatProvider);
    final done = TrackerValues.isDone(total);

    return switch (tracker.type) {
      TrackerType.counter => _ActionButton(
          key: key,
          label: l10n.trackerAddOne(tracker.name),
          onTap: () => unawaited(logger().log()),
          child: const Icon(Icons.add),
        ),
      TrackerType.boolean => _ActionButton(
          key: key,
          label: done
              ? l10n.trackerMarkNotDone(tracker.name)
              : l10n.trackerMarkDone(tracker.name),
          selected: done,
          onTap: () => unawaited(logger().toggleDone(done: done)),
          child: Icon(done ? Icons.check : Icons.check_box_outline_blank),
        ),
      TrackerType.quantity =>
        _quantityButton(context, l10n, format, logger, key),
      // The timer arrives in the next task; until then a duration tile shows
      // its total only.
      TrackerType.duration => const SizedBox.shrink(),
    };
  }

  Widget _quantityButton(
    BuildContext context,
    AppLocalizations l10n,
    TrackerFormat format,
    TrackerLogger Function() logger,
    Key key,
  ) {
    final perTap =
        TrackerValues.perTap(tracker.type, perTapValue: tracker.perTapValue)!;
    return _ActionButton(
      key: key,
      label: l10n.trackerAddAmount(format.total(tracker, perTap), tracker.name),
      longPressHint: l10n.trackerOtherAmount,
      onTap: () => unawaited(logger().log()),
      onLongPress: () => unawaited(_logOther(context, logger())),
      child: Text('+${format.number(perTap)}'),
    );
  }

  /// The logger is built before the sheet opens: once it closes, this widget
  /// may no longer be mounted, and nothing here may read its context.
  Future<void> _logOther(BuildContext context, TrackerLogger logger) async {
    final amount = await showTrackerAmountSheet(context, tracker: tracker);
    if (amount != null) await logger.log(value: amount);
  }
}

/// The stadium-shaped button every action uses.
///
/// One semantics node says what the tap does, and the glyph inside is
/// decoration. `excludeSemantics` drops the InkWell's own actions, so they are
/// declared on the node instead.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.longPressHint,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? longPressHint;
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected ? scheme.primary : scheme.secondaryContainer;
    final foreground =
        selected ? scheme.onPrimary : scheme.onSecondaryContainer;

    return Semantics(
      // Its own node: without a container the label folds into the tile's,
      // and a screen reader hears the tracker's name, not what the tap does.
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressHint: longPressHint,
      excludeSemantics: true,
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: NimbusTokens.minTapTarget + NimbusTokens.space4,
              minHeight: NimbusTokens.minTapTarget,
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: NimbusTokens.space3),
              child: Center(
                widthFactor: 1,
                child: IconTheme.merge(
                  data: IconThemeData(color: foreground),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                        color: foreground, fontWeight: FontWeight.w600),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
