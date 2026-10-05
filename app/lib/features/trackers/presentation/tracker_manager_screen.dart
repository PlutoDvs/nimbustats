import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../application/tracker_format.dart';
import '../application/tracker_providers.dart';
import '../data/tracker_repository.dart';
import 'widgets/tracker_editor_sheet.dart';
import 'widgets/tracker_logger.dart';
import 'widgets/tracker_write.dart';

/// Create, edit, reorder and archive trackers.
///
/// Phase 1's manager shape: the live list, which can be dragged into order,
/// an "Archived" section, and an editor sheet. There is no delete: archiving
/// keeps every entry and is undone with one tap.
class TrackerManagerScreen extends ConsumerWidget {
  const TrackerManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final live = ref.watch(trackersProvider);
    final archived = ref.watch(archivedTrackersProvider);
    final repository = ref.watch(trackerRepositoryProvider);

    final Widget body;
    var hasRows = false;
    if (live.hasError || archived.hasError) {
      body = NimbusErrorState(
        title: l10n.trackerErrorTitle,
        retryLabel: l10n.commonRetry,
        detail: (live.error ?? archived.error).toString(),
        onRetry: () {
          ref.invalidate(trackersProvider);
          ref.invalidate(archivedTrackersProvider);
        },
      );
    } else if (!live.hasValue || !archived.hasValue) {
      body = const NimbusLoadingList(rows: 4);
    } else if (live.requireValue.isEmpty && archived.requireValue.isEmpty) {
      body = NimbusEmptyState(
        icon: Icons.checklist_outlined,
        title: l10n.trackerManagerEmptyTitle,
        message: l10n.trackerManagerEmptyMessage,
        actionLabel: l10n.trackerNew,
        onAction: () => showTrackerEditorSheet(context, repository: repository),
      );
    } else {
      hasRows = true;
      body = _ManagerList(
        live: live.requireValue,
        archived: archived.requireValue,
        repository: repository,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.trackerManagerTitle)),
      body: body,
      floatingActionButton: hasRows
          ? FloatingActionButton.extended(
              key: const Key('tracker-add'),
              onPressed: () =>
                  showTrackerEditorSheet(context, repository: repository),
              icon: const Icon(Icons.add),
              label: Text(l10n.trackerNew),
            )
          : null,
    );
  }
}

class _ManagerList extends ConsumerStatefulWidget {
  const _ManagerList({
    required this.live,
    required this.archived,
    required this.repository,
  });

  final List<Tracker> live;
  final List<Tracker> archived;
  final TrackerRepository repository;

  @override
  ConsumerState<_ManagerList> createState() => _ManagerListState();
}

class _ManagerListState extends ConsumerState<_ManagerList> {
  /// The order the user just dragged to, shown until the stream catches up.
  /// If the write fails it is put back.
  List<Tracker>? _dragged;

  @override
  void didUpdateWidget(covariant _ManagerList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new list from the stream is the stored order. Stop overriding it.
    if (!identical(oldWidget.live, widget.live)) _dragged = null;
  }

  Future<void> _move(int oldIndex, int newIndex) async {
    // onReorderItem reports the final index, already adjusted for the
    // removal, so this is a plain remove-then-insert.
    final order = [...(_dragged ?? widget.live)];
    order.insert(newIndex, order.removeAt(oldIndex));
    setState(() => _dragged = order);
    try {
      await reportingTrackerFailure(
        messenger: ScaffoldMessenger.of(context),
        l10n: AppLocalizations.of(context),
        write: () => widget.repository.reorder([for (final t in order) t.id]),
      );
    } on Object {
      // The stored order never changed, so the screen must not keep showing
      // the dragged one.
      if (mounted) setState(() => _dragged = null);
      rethrow;
    }
  }

  TrackerLogger _logger(Tracker tracker) => TrackerLogger(
        messenger: ScaffoldMessenger.of(context),
        l10n: AppLocalizations.of(context),
        repository: widget.repository,
        format: ref.read(trackerFormatProvider),
        tracker: tracker,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final live = _dragged ?? widget.live;

    return ReorderableListView.builder(
      key: const Key('tracker-manager-list'),
      // Reversed like the tab, so the row at the bottom here is the tracker
      // nearest the thumb there.
      reverse: true,
      padding: const EdgeInsets.only(bottom: NimbusTokens.space8 * 3),
      itemCount: live.length,
      onReorderItem: (oldIndex, newIndex) =>
          unawaited(_move(oldIndex, newIndex)),
      footer: widget.archived.isEmpty
          ? null
          : _ArchivedSection(
              archived: widget.archived,
              onUnarchive: (tracker) => unawaited(reportingTrackerFailure(
                messenger: ScaffoldMessenger.of(context),
                l10n: l10n,
                write: () => widget.repository.unarchive(tracker.id),
              )),
            ),
      itemBuilder: (context, index) {
        final tracker = live[index];
        return ListTile(
          key: Key('tracker-row-${tracker.id}'),
          minTileHeight: NimbusTokens.minTapTarget,
          leading: ExcludeSemantics(
            child: Icon(nimbusIconFor(tracker.iconKey),
                color: Color(tracker.color)),
          ),
          title: Text(tracker.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(trackerTypeLabel(l10n, tracker.type)),
          onTap: () => showTrackerEditorSheet(context,
              repository: widget.repository, tracker: tracker),
          trailing: PopupMenuButton<_RowAction>(
            key: Key('tracker-menu-${tracker.id}'),
            onSelected: (action) {
              switch (action) {
                case _RowAction.edit:
                  unawaited(showTrackerEditorSheet(context,
                      repository: widget.repository, tracker: tracker));
                case _RowAction.archive:
                  unawaited(_logger(tracker).archive());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                key: const Key('tracker-menu-edit'),
                value: _RowAction.edit,
                child: Text(l10n.trackerEditTitle),
              ),
              PopupMenuItem(
                key: const Key('tracker-menu-archive'),
                value: _RowAction.archive,
                child: Text(l10n.commonArchive),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _RowAction { edit, archive }

class _ArchivedSection extends StatelessWidget {
  const _ArchivedSection({required this.archived, required this.onUnarchive});

  final List<Tracker> archived;
  final ValueChanged<Tracker> onUnarchive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(NimbusTokens.space4,
              NimbusTokens.space6, NimbusTokens.space4, NimbusTokens.space2),
          child: Text(l10n.trackerArchivedSection,
              style: theme.textTheme.titleSmall),
        ),
        for (final tracker in archived)
          ListTile(
            key: Key('tracker-archived-${tracker.id}'),
            leading: ExcludeSemantics(
              child: Icon(nimbusIconFor(tracker.iconKey),
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            title: Text(tracker.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: TextButton(
              key: Key('tracker-unarchive-${tracker.id}'),
              onPressed: () => onUnarchive(tracker),
              child: Text(l10n.commonUnarchive),
            ),
          ),
      ],
    );
  }
}
