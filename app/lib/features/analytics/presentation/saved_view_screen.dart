import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/application/settings_providers.dart';
import '../application/dashboard_anchor.dart';
import '../application/saved_view_providers.dart';
import 'widgets/month_bar.dart';
import 'widgets/saved_view_actions.dart';
import 'widgets/saved_view_body.dart';

enum _ViewAction { rename, remove }

/// One saved view, full screen.
class SavedViewScreen extends ConsumerStatefulWidget {
  const SavedViewScreen({super.key, required this.id, this.initialAnchor});

  final String id;

  /// The dashboard's month when the card was tapped; today when absent.
  final DateKey? initialAnchor;

  @override
  ConsumerState<SavedViewScreen> createState() => _SavedViewScreenState();
}

class _SavedViewScreenState extends ConsumerState<SavedViewScreen> {
  // Its own anchor, seeded from the dashboard's: moving months here must not
  // move the dashboard behind it.
  late DateKey _anchor =
      widget.initialAnchor ?? DateKey.fromDateTime(DateTime.now());

  void _shift(int months) => setState(
      () => _anchor = shiftMonths(_anchor, months, ref.read(calendarProvider)));

  Future<void> _remove() async {
    final repository = ref.read(savedViewsRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final router = GoRouter.of(context);
    // Leave first: once the row is gone this screen would show "no longer
    // exists" for a frame before closing.
    if (router.canPop()) router.pop();
    await removeSavedView(
        repository: repository, messenger: messenger, l10n: l10n, id: widget.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(savedViewByIdProvider(widget.id));
    final entry = async.hasError ? null : async.value;

    final Widget body;
    if (async.hasError) {
      body = NimbusErrorState(
        title: l10n.analyticsErrorTitle,
        detail: async.error.toString(),
        retryLabel: l10n.commonRetry,
        onRetry: () => ref.invalidate(savedViewByIdProvider(widget.id)),
      );
    } else if (!async.hasValue) {
      body = const NimbusLoadingList();
    } else {
      body = switch (entry) {
        null => NimbusEmptyState(
            icon: Icons.visibility_off_outlined,
            title: l10n.savedViewMissing,
            message: l10n.savedViewMissingBody,
          ),
        final UnreadableSavedView view => NimbusEmptyState(
            icon: Icons.error_outline,
            title: l10n.savedViewUnreadable,
            message: '${view.error}',
          ),
        final SavedView view => Column(
            children: [
              MonthBar(
                anchor: _anchor,
                onShift: _shift,
                keyPrefix: 'saved-view-period',
              ),
              Expanded(child: SavedViewBody(view: view, anchor: _anchor)),
            ],
          ),
      };
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(entry?.name ?? '', key: const Key('saved-view-title')),
        actions: [
          if (entry != null)
            PopupMenuButton<_ViewAction>(
              key: const Key('saved-view-menu'),
              tooltip: l10n.cardOptions,
              onSelected: (action) => switch (action) {
                _ViewAction.rename => renameSavedView(
                    context,
                    repository: ref.read(savedViewsRepositoryProvider),
                    id: widget.id,
                    currentName: entry.name,
                    takenNames: dashboardNames(ref, exceptId: widget.id),
                  ),
                _ViewAction.remove => _remove(),
              },
              itemBuilder: (context) => [
                if (entry is SavedView)
                  PopupMenuItem(
                    key: const Key('saved-view-menu-rename'),
                    value: _ViewAction.rename,
                    child: Text(l10n.renameView),
                  ),
                PopupMenuItem(
                  key: const Key('saved-view-menu-remove'),
                  value: _ViewAction.remove,
                  child: Text(l10n.removeView),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}
