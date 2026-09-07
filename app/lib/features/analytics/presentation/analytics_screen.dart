import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../categories/application/category_providers.dart';
import '../../tags/application/tag_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../application/analytics_providers.dart';
import '../application/breakdown_controller.dart';
import '../application/cross_tab_controller.dart';
import '../application/patterns_controller.dart';
import '../application/period_label.dart';
import '../application/trends_controller.dart';
import 'widgets/breakdown_body.dart';
import 'widgets/cross_tab_body.dart';
import 'widgets/patterns_body.dart';
import 'widgets/trends_body.dart';

/// The analytics destination.
///
/// Two tabs answering two different questions: where the money went, and
/// whether that is changing. They are tabs rather than one scrolling screen
/// because they take different controls -- a breakdown needs one period and a
/// trend needs a window of them.
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        key: const Key('analytics-screen'),
        appBar: AppBar(
          title: Text(l10n.navAnalytics),
          bottom: TabBar(
            // Scrollable: four labels do not fit a phone's width, and Material
            // silently ellipsizes them into unreadable stubs otherwise.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                key: const Key('analytics-tab-breakdown'),
                text: l10n.analyticsTabBreakdown,
              ),
              Tab(
                key: const Key('analytics-tab-trends'),
                text: l10n.analyticsTabTrends,
              ),
              Tab(
                key: const Key('analytics-tab-crosstab'),
                text: l10n.analyticsTabCrossTab,
              ),
              Tab(
                key: const Key('analytics-tab-patterns'),
                text: l10n.analyticsTabPatterns,
              ),
            ],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            // Breakdown lands first: "where did it go" is the question
            // somebody opening analytics already has.
            children: [
              _BreakdownTab(),
              _TrendsTab(),
              _CrossTabTab(),
              _PatternsTab(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders [body] once both the answer and the category names have arrived.
///
/// Both gate the same screen because a bucket without its category's name is
/// an id on a chart, so there is nothing honest to draw until each is in.
class _AsyncChart<T> extends ConsumerWidget {
  const _AsyncChart({required this.value, required this.builder, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return switch (value) {
      AsyncError(:final error) => NimbusErrorState(
          title: l10n.analyticsErrorTitle,
          detail: error.toString(),
          retryLabel: l10n.commonRetry,
          onRetry: onRetry ?? () {},
        ),
      AsyncData(value: final data) => builder(data),
      _ => const NimbusLoadingList(),
    };
  }
}

class _BreakdownTab extends ConsumerWidget {
  const _BreakdownTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(breakdownControllerProvider);
    final controller = ref.read(breakdownControllerProvider.notifier);
    final result = ref.watch(analyticsResultProvider(view.spec));
    final nodes = ref.watch(categoryNodesByIdProvider);

    return Column(
      children: [
        _PeriodBar(view: view, controller: controller),
        _ConfirmedOnlySwitch(
          value: view.confirmedOnly,
          onChanged: (value) => controller.setConfirmedOnly(value: value),
          tileKey: const Key('breakdown-confirmed-only'),
        ),
        if (view.trail.isNotEmpty)
          _Breadcrumb(trail: view.trail, controller: controller),
        Expanded(
          // Both futures gate this tab: a bucket without its category's name
          // is an id on a chart, so there is nothing honest to draw until each
          // has arrived.
          child: switch ((result, nodes)) {
            (AsyncError(:final error), _) || (_, AsyncError(:final error)) =>
              NimbusErrorState(
                title: AppLocalizations.of(context).analyticsErrorTitle,
                detail: error.toString(),
                retryLabel: AppLocalizations.of(context).commonRetry,
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
    );
  }
}

class _TrendsTab extends ConsumerWidget {
  const _TrendsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(trendsControllerProvider);
    final controller = ref.read(trendsControllerProvider.notifier);
    final result = ref.watch(analyticsResultProvider(view.spec));

    return Column(
      children: [
        _ConfirmedOnlySwitch(
          value: view.confirmedOnly,
          onChanged: (value) => controller.setConfirmedOnly(value: value),
          tileKey: const Key('trends-confirmed-only'),
        ),
        Expanded(
          child: _AsyncChart(
            value: result,
            onRetry: () => ref.invalidate(analyticsResultProvider(view.spec)),
            builder: (data) => TrendsBody(
              view: view,
              result: data,
              formatter: ref.watch(moneyFormatterProvider),
            ),
          ),
        ),
      ],
    );
  }
}

class _CrossTabTab extends ConsumerWidget {
  const _CrossTabTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(crossTabControllerProvider);
    final controller = ref.read(crossTabControllerProvider.notifier);
    final result = ref.watch(analyticsResultProvider(view.spec));
    final categories = ref.watch(categoryNodesByIdProvider);
    final tags = ref.watch(tagNodesByIdProvider);

    return Column(
      children: [
        _ConfirmedOnlySwitch(
          value: view.confirmedOnly,
          onChanged: (value) => controller.setConfirmedOnly(value: value),
          tileKey: const Key('crosstab-confirmed-only'),
        ),
        Expanded(
          // Three futures, one screen: the cells, and the names for each axis.
          // A matrix labelled with raw ids is not a partial answer, it is an
          // unreadable one.
          child: switch ((result, categories, tags)) {
            (AsyncError(:final error), _, _) ||
            (_, AsyncError(:final error), _) ||
            (_, _, AsyncError(:final error)) =>
              NimbusErrorState(
                title: AppLocalizations.of(context).analyticsErrorTitle,
                detail: error.toString(),
                retryLabel: AppLocalizations.of(context).commonRetry,
                onRetry: () =>
                    ref.invalidate(analyticsResultProvider(view.spec)),
              ),
            (
              AsyncData(value: final data),
              AsyncData(value: final byCategory),
              AsyncData(value: final byTag)
            ) =>
              CrossTabBody(
                result: data,
                categoriesById: byCategory,
                tagsById: byTag,
                formatter: ref.watch(moneyFormatterProvider),
              ),
            _ => const NimbusLoadingList(),
          },
        ),
      ],
    );
  }
}

class _PatternsTab extends ConsumerWidget {
  const _PatternsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(patternsControllerProvider);
    final controller = ref.read(patternsControllerProvider.notifier);
    final hour = ref.watch(analyticsResultProvider(view.hourSpec));
    final weekday = ref.watch(analyticsResultProvider(view.weekdaySpec));
    final reflection = ref.watch(analyticsResultProvider(view.reflectionSpec));

    return Column(
      children: [
        _ConfirmedOnlySwitch(
          value: view.confirmedOnly,
          onChanged: (value) => controller.setConfirmedOnly(value: value),
          tileKey: const Key('patterns-confirmed-only'),
        ),
        Expanded(
          // All three gate the tab together. They are three views of one
          // period, and revealing them as they land would let a reader compare
          // a fresh chart against a stale one.
          child: switch ((hour, weekday, reflection)) {
            (AsyncError(:final error), _, _) ||
            (_, AsyncError(:final error), _) ||
            (_, _, AsyncError(:final error)) =>
              NimbusErrorState(
                title: AppLocalizations.of(context).analyticsErrorTitle,
                detail: error.toString(),
                retryLabel: AppLocalizations.of(context).commonRetry,
                onRetry: () =>
                    ref.invalidate(analyticsResultProvider(view.hourSpec)),
              ),
            (
              AsyncData(value: final byHour),
              AsyncData(value: final byWeekday),
              AsyncData(value: final byReflection)
            ) =>
              PatternsBody(
                byHour: byHour,
                byWeekday: byWeekday,
                reflection: byReflection,
                firstDayOfWeek: ref.watch(firstDayOfWeekProvider),
                formatter: ref.watch(moneyFormatterProvider),
              ),
            _ => const NimbusLoadingList(),
          },
        ),
      ],
    );
  }
}

class _PeriodBar extends ConsumerWidget {
  const _PeriodBar({required this.view, required this.controller});

  final BreakdownView view;
  final BreakdownController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              periodLabel(
                view.period,
                ref.watch(calendarProvider),
                persianDigits: ref.watch(moneyFormatterProvider).persianDigits,
              ),
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
  const _ConfirmedOnlySwitch({
    required this.value,
    required this.onChanged,
    required this.tileKey,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Key tileKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SwitchListTile(
      key: tileKey,
      dense: true,
      title: Text(l10n.breakdownConfirmedOnly),
      value: value,
      onChanged: onChanged,
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
        padding: const EdgeInsets.symmetric(horizontal: NimbusTokens.space2),
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
