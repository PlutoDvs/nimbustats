import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../categories/application/category_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../application/analytics_providers.dart';
import '../application/breakdown_controller.dart';
import 'widgets/breakdown_body.dart';

/// The analytics destination: a spending breakdown that drills down.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(breakdownControllerProvider);
    final controller = ref.read(breakdownControllerProvider.notifier);
    final result = ref.watch(analyticsResultProvider(view.spec));
    final nodes = ref.watch(categoryNodesByIdProvider);

    return Scaffold(
      key: const Key('analytics-screen'),
      appBar: AppBar(title: Text(l10n.navAnalytics)),
      body: SafeArea(
        child: Column(
          children: [
            _PeriodBar(view: view, controller: controller),
            _ConfirmedOnlySwitch(view: view, controller: controller),
            if (view.trail.isNotEmpty)
              _Breadcrumb(trail: view.trail, controller: controller),
            Expanded(
              // Both futures gate the same screen: a bucket without its
              // category's name is an id on a chart, so there is nothing
              // honest to render until each has arrived.
              child: switch ((result, nodes)) {
                (AsyncError(:final error), _) ||
                (_, AsyncError(:final error)) =>
                  NimbusErrorState(
                    title: l10n.analyticsErrorTitle,
                    detail: error.toString(),
                    retryLabel: l10n.commonRetry,
                    onRetry: () =>
                        ref.invalidate(analyticsResultProvider(view.spec)),
                  ),
                (AsyncData(value: final data), AsyncData(value: final byId)) =>
                  BreakdownBody(
                    result: data,
                    nodesById: byId,
                    formatter: ref.watch(moneyFormatterProvider),
                    onDrill: controller.drillInto,
                  ),
                _ => const NimbusLoadingList(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.view, required this.controller});

  final BreakdownView view;
  final BreakdownController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const Key('breakdown-period-previous'),
          icon: const Icon(Icons.chevron_left),
          onPressed: () => controller.shiftPeriod(-1),
        ),
        Expanded(
          child: Center(
            child: Text(
              // Keys rather than a formatted date: the label is refined in the
              // trends task, and an unlocalized month name here would be worse
              // than the range the user already chose.
              '${view.period.startInclusive.value}',
              key: const Key('breakdown-period-label'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        IconButton(
          key: const Key('breakdown-period-next'),
          icon: const Icon(Icons.chevron_right),
          onPressed: () => controller.shiftPeriod(1),
        ),
      ],
    );
  }
}

class _ConfirmedOnlySwitch extends StatelessWidget {
  const _ConfirmedOnlySwitch({required this.view, required this.controller});

  final BreakdownView view;
  final BreakdownController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SwitchListTile(
      key: const Key('breakdown-confirmed-only'),
      dense: true,
      title: Text(l10n.breakdownConfirmedOnly),
      value: view.confirmedOnly,
      onChanged: (value) => controller.setConfirmedOnly(value: value),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.trail, required this.controller});

  final List<CategoryCrumb> trail;
  final BreakdownController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: NimbusTokens.minTapTarget,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: NimbusTokens.space2),
        children: [
          TextButton(
            key: const Key('breakdown-crumb-root'),
            onPressed: () => controller.popTo(0),
            child: Text(l10n.breakdownAllCategories),
          ),
          for (final (index, crumb) in trail.indexed)
            TextButton(
              key: Key('breakdown-crumb-${crumb.id}'),
              // popTo(index + 1) keeps this crumb and drops everything after
              // it, so tapping the level you are already on is a no-op rather
              // than a jump back to the root.
              onPressed: () => controller.popTo(index + 1),
              child: Text(crumb.name),
            ),
        ],
      ),
    );
  }
}
