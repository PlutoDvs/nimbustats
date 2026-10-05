import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_providers.dart';
import '../../data/tracker_presets.dart';
import 'tracker_editor_sheet.dart';
import 'tracker_write.dart';

/// The tab's empty state: what a tracker is, and the four presets to start
/// with.
///
/// Several can be chosen at once and added together. The empty state
/// disappears with the first tracker, so a tap-to-create-one would only ever
/// let a user pick one preset.
class TrackerPresetsEmpty extends ConsumerStatefulWidget {
  const TrackerPresetsEmpty({super.key});

  @override
  ConsumerState<TrackerPresetsEmpty> createState() =>
      _TrackerPresetsEmptyState();
}

class _TrackerPresetsEmptyState extends ConsumerState<TrackerPresetsEmpty> {
  /// Stable test keys, in the presets' order.
  static const _slugs = ['water', 'cigarettes', 'gym', 'sleep'];

  final _chosen = <int>{};

  void _add() {
    final l10n = AppLocalizations.of(context);
    final presets = trackerPresets(l10n);
    final chosen = [
      for (final (index, preset) in presets.indexed)
        if (_chosen.contains(index)) preset,
    ];
    unawaited(reportingTrackerFailure(
      messenger: ScaffoldMessenger.of(context),
      l10n: l10n,
      write: () => ref.read(trackerRepositoryProvider).createAll(chosen),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final presets = trackerPresets(l10n);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NimbusTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.checklist_outlined,
                  size: NimbusTokens.space8 * 1.5,
                  color: theme.colorScheme.primary),
            ),
            const SizedBox(height: NimbusTokens.space4),
            Text(l10n.trackerEmptyTitle,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: NimbusTokens.space2),
            Text(l10n.trackerEmptyMessage,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: NimbusTokens.space6),
            Wrap(
              key: const Key('tracker-presets'),
              alignment: WrapAlignment.center,
              spacing: NimbusTokens.space2,
              runSpacing: NimbusTokens.space2,
              children: [
                for (final (index, preset) in presets.indexed)
                  FilterChip(
                    key: Key('tracker-preset-${_slugs[index]}'),
                    avatar: Icon(nimbusIconFor(preset.iconKey)),
                    label: Text(preset.name),
                    selected: _chosen.contains(index),
                    onSelected: (on) => setState(
                        () => on ? _chosen.add(index) : _chosen.remove(index)),
                  ),
              ],
            ),
            const SizedBox(height: NimbusTokens.space6),
            FilledButton(
              key: const Key('tracker-presets-add'),
              onPressed: _chosen.isEmpty ? null : _add,
              child: Text(l10n.trackerPresetsAdd),
            ),
            const SizedBox(height: NimbusTokens.space2),
            TextButton(
              key: const Key('tracker-create-own'),
              onPressed: () => showTrackerEditorSheet(context,
                  repository: ref.read(trackerRepositoryProvider)),
              child: Text(l10n.trackerCreateOwn),
            ),
          ],
        ),
      ),
    );
  }
}
