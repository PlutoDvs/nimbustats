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

class _CardList extends ConsumerWidget {
  const _CardList({required this.entries});

  final List<SavedViewEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchor = ref.watch(dashboardAnchorProvider);
    return ListView.builder(
      padding: const EdgeInsets.all(NimbusTokens.space2),
      itemCount: entries.length,
      itemBuilder: (context, index) => SavedViewCard(
        key: ValueKey(entries[index].id),
        entry: entries[index],
        anchor: anchor,
      ),
    );
  }
}
