import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../application/dashboard_anchor.dart';
import '../application/saved_view_providers.dart';
import '../application/starter_views.dart';
import 'widgets/month_bar.dart';
import 'widgets/saved_view_card.dart';
import 'widgets/saved_view_write.dart';

/// Analytics' first tab: the user's pinned views as cards.
class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pinned = ref.watch(pinnedViewsProvider);
    final entries = pinned.hasError ? null : pinned.value;

    final Widget body;
    if (pinned.hasError) {
      body = NimbusErrorState(
        title: l10n.dashboardErrorTitle,
        detail: pinned.error.toString(),
        retryLabel: l10n.commonRetry,
        onRetry: () => ref.invalidate(pinnedViewsProvider),
      );
    } else if (entries == null) {
      body = const NimbusLoadingList(rows: 3);
    } else if (entries.isEmpty) {
      body = const _EmptyDashboard();
    } else {
      body = _CardList(entries: entries);
    }

    return Column(
      key: const Key('dashboard-tab'),
      children: [
        MonthBar(
          anchor: ref.watch(dashboardAnchorProvider),
          onShift: ref.read(dashboardAnchorProvider.notifier).shift,
          keyPrefix: 'dashboard-period',
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _EmptyDashboard extends ConsumerWidget {
  const _EmptyDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    return Column(
      children: [
        Expanded(
          child: NimbusEmptyState(
            icon: Icons.dashboard_outlined,
            title: l10n.dashboardEmptyTitle,
            message: l10n.dashboardEmptyBody,
            actionLabel: l10n.dashboardAddStarters,
            onAction: () => reportingFailure(
              messenger: messenger,
              l10n: l10n,
              write: () =>
                  ref.read(savedViewsRepositoryProvider).pin(starterViews(l10n)),
            ),
          ),
        ),
        TextButton(
          key: const Key('dashboard-go-to-breakdown'),
          // Breakdown is the tab after this one in AnalyticsScreen's order.
          onPressed: () => DefaultTabController.of(context).animateTo(1),
          child: Text(l10n.dashboardGoToBreakdown),
        ),
        const SizedBox(height: NimbusTokens.space4),
      ],
    );
  }
}

class _CardList extends ConsumerStatefulWidget {
  const _CardList({required this.entries});

  final List<SavedViewEntry> entries;

  @override
  ConsumerState<_CardList> createState() => _CardListState();
}

class _CardListState extends ConsumerState<_CardList> {
  /// The order on screen. It follows the database, except between a drag and
  /// the write it causes: a reorderable list needs the new order in the same
  /// frame, or the card snaps back until the stream catches up.
  late List<SavedViewEntry> _shown = widget.entries;

  @override
  void didUpdateWidget(_CardList old) {
    super.didUpdateWidget(old);
    if (!identical(old.entries, widget.entries)) _shown = widget.entries;
  }

  Future<void> _move(int oldIndex, int newIndex) async {
    // Read before any await: by the time the write settles, this State may
    // no longer be mounted, and BuildContext lookups are only safe now.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    // onReorderItem reports the final index, already adjusted for the item
    // removed at oldIndex.
    final next = [..._shown];
    next.insert(newIndex, next.removeAt(oldIndex));
    setState(() => _shown = next);
    try {
      await reportingFailure(
        messenger: messenger,
        l10n: l10n,
        write: () => ref
            .read(savedViewsRepositoryProvider)
            .reorder([for (final entry in next) entry.id]),
      );
    } on Object {
      // The write never landed, so the list must not keep showing an order
      // that was never saved -- put the on-screen order back to what the
      // database still holds, then let the caller hear about the failure.
      if (mounted) setState(() => _shown = widget.entries);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final anchor = ref.watch(dashboardAnchorProvider);
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(NimbusTokens.space2),
      itemCount: _shown.length,
      onReorderItem: _move,
      itemBuilder: (context, index) => SavedViewCard(
        key: ValueKey(_shown[index].id),
        entry: _shown[index],
        anchor: anchor,
      ),
    );
  }
}
