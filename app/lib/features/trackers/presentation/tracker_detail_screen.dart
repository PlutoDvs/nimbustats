import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../application/tracker_format.dart';
import '../application/tracker_history_controller.dart';
import '../application/tracker_providers.dart';
import '../routes.dart';
import 'widgets/tracker_action_button.dart';
import 'widgets/tracker_day_rollover.dart';
import 'widgets/tracker_duration_sheet.dart';
import 'widgets/tracker_editor_sheet.dart';
import 'widgets/tracker_entry_sheet.dart';
import 'widgets/tracker_logger.dart';
import 'widgets/tracker_streak_lines.dart';
import 'widgets/tracker_today_text.dart';

/// One tracker: today's total, its history newest first, and the quick log
/// pinned in the bottom third while the history scrolls (screen contract
/// §6.2).
class TrackerDetailScreen extends ConsumerWidget {
  const TrackerDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracker = ref.watch(trackerByIdProvider(id));
    final dayTotal = ref.watch(trackerDayTotalProvider(id));

    if (tracker.hasError || dayTotal.hasError) {
      return Scaffold(
        appBar: AppBar(),
        body: NimbusErrorState(
          title: l10n.trackerErrorTitle,
          retryLabel: l10n.commonRetry,
          detail: (tracker.error ?? dayTotal.error).toString(),
          onRetry: () {
            ref.invalidate(trackerByIdProvider(id));
            // The whole family: whichever question failed is asked again.
            ref.invalidate(trackerResultProvider);
          },
        ),
      );
    }
    if (!tracker.hasValue || !dayTotal.hasValue) {
      return Scaffold(appBar: AppBar(), body: const NimbusLoadingList(rows: 6));
    }
    final current = tracker.requireValue;
    if (current == null) {
      // A stale link -- Phase 6's widget can hold an old id. Say so, and
      // offer the way back rather than a blank screen.
      return Scaffold(
        appBar: AppBar(),
        body: NimbusEmptyState(
          icon: Icons.search_off,
          title: l10n.trackerNotFoundTitle,
          message: l10n.trackerNotFoundMessage,
          actionLabel: l10n.navTrackers,
          onAction: () => context.go(trackersRoute),
        ),
      );
    }

    final total = dayTotal.requireValue;
    return TrackerDayRollover(
      child: Scaffold(
        appBar: AppBar(
          title:
              Text(current.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [_TrackerMenu(tracker: current)],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(tracker: current, total: total),
            const Divider(height: 1),
            Expanded(child: _History(tracker: current)),
          ],
        ),
        // Outside the scrolling body, so it stays put while history scrolls.
        bottomNavigationBar: _QuickLogBar(tracker: current, total: total),
      ),
    );
  }
}

/// What a tap anywhere on this screen writes through. Built before any await,
/// because it holds the context's messenger and the widget may be gone after.
TrackerLogger _loggerFor(BuildContext context, WidgetRef ref, Tracker tracker) =>
    TrackerLogger(
      messenger: ScaffoldMessenger.of(context),
      l10n: AppLocalizations.of(context),
      repository: ref.read(trackerRepositoryProvider),
      format: ref.read(trackerFormatProvider),
      tracker: tracker,
    );

class _Header extends StatelessWidget {
  const _Header({required this.tracker, required this.total});

  final Tracker tracker;
  final double total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(NimbusTokens.space4),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(nimbusIconFor(tracker.iconKey),
                color: Color(tracker.color), size: NimbusTokens.space8 * 1.25),
          ),
          const SizedBox(width: NimbusTokens.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TrackerTodayText(
                  key: const Key('tracker-detail-total'),
                  tracker: tracker,
                  total: total,
                  style: theme.textTheme.headlineSmall,
                ),
                TrackerStreakLines(trackerId: tracker.id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickLogBar extends ConsumerWidget {
  const _QuickLogBar({required this.tracker, required this.total});

  final Tracker tracker;
  final double total;

  Future<void> _addDuration(BuildContext context, WidgetRef ref) async {
    final logger = _loggerFor(context, ref, tracker);
    final duration = await showAddDurationSheet(context);
    if (duration != null) await logger.addDuration(duration);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(NimbusTokens.space4),
        child: Row(
          key: const Key('tracker-quick-log'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TrackerActionButton(tracker: tracker, total: total),
            if (tracker.type == TrackerType.duration) ...[
              const SizedBox(width: NimbusTokens.space4),
              OutlinedButton.icon(
                key: const Key('tracker-add-duration'),
                onPressed: () => unawaited(_addDuration(context, ref)),
                icon: const Icon(Icons.more_time),
                label: Text(l10n.trackerAddDuration),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.tracker});

  final Tracker tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = trackerHistoryProvider(tracker.id);
    final history = ref.watch(provider);

    if (history.hasError) {
      return NimbusErrorState(
        title: l10n.trackerHistoryErrorTitle,
        retryLabel: l10n.commonRetry,
        detail: history.error.toString(),
        onRetry: () => ref.invalidate(provider),
      );
    }
    if (!history.hasValue) return const NimbusLoadingList(rows: 6);
    final entries = history.requireValue.entries;
    if (entries.isEmpty) {
      return NimbusEmptyState(
        icon: Icons.history,
        title: l10n.trackerHistoryEmptyTitle,
        message: l10n.trackerHistoryEmptyMessage,
      );
    }
    return NotificationListener<ScrollNotification>(
      // Near the end, ask for the next page. The controller ignores repeats
      // while one is loading.
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 400) {
          unawaited(ref.read(provider.notifier).loadMore());
        }
        return false;
      },
      child: ListView.builder(
        key: const Key('tracker-history'),
        itemCount: entries.length,
        itemBuilder: (context, index) =>
            _EntryRow(tracker: tracker, entry: entries[index]),
      ),
    );
  }
}

enum _EntryAction { edit, delete }

class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.tracker, required this.entry});

  final Tracker tracker;
  final TrackerEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final format = ref.watch(trackerFormatProvider);
    final clock = ref.watch(trackerClockProvider);
    // The day shown is the stored one, the day the entry belongs to, even if
    // the device has since crossed timezones.
    final when = '${format.date(entry.localDateKey)} · '
        '${format.time(clock.toLocal(entry.occurredAtUtc))}';
    final note = entry.note;

    return ListTile(
      key: Key('tracker-entry-${entry.id}'),
      title: Text(tracker.type == TrackerType.boolean
          ? l10n.trackerDone
          : format.total(tracker, entry.value)),
      subtitle: Text(note == null ? when : '$when\n$note'),
      isThreeLine: note != null,
      onTap: () => showTrackerEntrySheet(context, tracker: tracker, entry: entry),
      trailing: PopupMenuButton<_EntryAction>(
        key: Key('tracker-entry-menu-${entry.id}'),
        tooltip: l10n.trackerEntryOptions,
        onSelected: (action) {
          switch (action) {
            case _EntryAction.edit:
              unawaited(showTrackerEntrySheet(context,
                  tracker: tracker, entry: entry));
            case _EntryAction.delete:
              unawaited(_loggerFor(context, ref, tracker).deleteEntry(entry));
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            key: const Key('tracker-entry-edit'),
            value: _EntryAction.edit,
            child: Text(l10n.trackerEntryEditTitle),
          ),
          PopupMenuItem(
            key: const Key('tracker-entry-delete'),
            value: _EntryAction.delete,
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }
}

enum _TrackerAction { edit, archive }

class _TrackerMenu extends ConsumerWidget {
  const _TrackerMenu({required this.tracker});

  final Tracker tracker;

  /// Archives, then goes back to the tab, where the tracker has just left and
  /// the undo is showing.
  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final logger = _loggerFor(context, ref, tracker);
    final router = GoRouter.of(context);
    await logger.archive();
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(trackersRoute);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<_TrackerAction>(
      key: const Key('tracker-menu'),
      tooltip: l10n.trackerOptions,
      onSelected: (action) {
        switch (action) {
          case _TrackerAction.edit:
            unawaited(showTrackerEditorSheet(context,
                repository: ref.read(trackerRepositoryProvider),
                tracker: tracker));
          case _TrackerAction.archive:
            unawaited(_archive(context, ref));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          key: const Key('tracker-menu-edit-tracker'),
          value: _TrackerAction.edit,
          child: Text(l10n.trackerEditTitle),
        ),
        PopupMenuItem(
          key: const Key('tracker-menu-archive-tracker'),
          value: _TrackerAction.archive,
          child: Text(l10n.commonArchive),
        ),
      ],
    );
  }
}
