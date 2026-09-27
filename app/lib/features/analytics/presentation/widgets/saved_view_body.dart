import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../categories/application/category_providers.dart';
import '../../../settings/application/settings_providers.dart';
import '../../../tags/application/tag_providers.dart';
import '../../application/analytics_providers.dart';
import '../../application/dashboard_anchor.dart';
import '../../application/trends_controller.dart';
import 'breakdown_body.dart';
import 'cross_tab_body.dart';
import 'patterns_body.dart';
import 'trends_body.dart';

/// A saved view at full size, drawn by the same body its tab uses.
class SavedViewBody extends ConsumerWidget {
  const SavedViewBody({super.key, required this.view, required this.anchor});

  final SavedView view;
  final DateKey anchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final calendar = ref.watch(calendarProvider);
    final firstDayOfWeek = ref.watch(firstDayOfWeekProvider);
    final formatter = ref.watch(moneyFormatterProvider);
    final spec =
        resolvedSpec(view, anchor, calendar, firstDayOfWeek: firstDayOfWeek);
    final result = ref.watch(analyticsResultProvider(spec));
    final categories = ref.watch(categoryNodesByIdProvider);
    final tags = ref.watch(tagNodesByIdProvider);

    // Names gate the chart with the answer, as on the tabs: a chart labelled
    // with raw ids is an unreadable answer, not a partial one.
    final failure = result.error ?? categories.error ?? tags.error;
    if (failure != null) {
      return NimbusErrorState(
        title: l10n.analyticsErrorTitle,
        detail: failure.toString(),
        retryLabel: l10n.commonRetry,
        onRetry: () => ref.invalidate(analyticsResultProvider(spec)),
      );
    }
    final data = result.value;
    final byCategory = categories.value;
    final byTag = tags.value;
    if (data == null || byCategory == null || byTag == null) {
      return const NimbusLoadingList();
    }
    if (data.trueCount == 0) {
      return NimbusEmptyState(
        icon: Icons.insights_outlined,
        title: l10n.analyticsEmptyTitle,
        message: l10n.analyticsEmptyBody,
      );
    }

    Widget padded(Widget chart) => ListView(
          padding: const EdgeInsets.all(NimbusTokens.space4),
          children: [chart],
        );

    return switch (view.chart) {
      SavedViewChart.breakdown => BreakdownBody(
          result: data,
          nodesById: byCategory,
          formatter: formatter,
        ),
      SavedViewChart.trend => TrendsBody(
          view: TrendsView(
            periods:
                trendPeriods(spec, calendar, firstDayOfWeek: firstDayOfWeek),
            confirmedOnly: spec.filters.confirmedOnly,
          ),
          result: data,
          formatter: formatter,
        ),
      SavedViewChart.crossTab => CrossTabBody(
          result: data,
          categoriesById: byCategory,
          tagsById: byTag,
          formatter: formatter,
        ),
      SavedViewChart.hourOfDay =>
        padded(HourOfDayChart(result: data, formatter: formatter)),
      SavedViewChart.dayOfWeek => padded(DayOfWeekChart(
          result: data,
          firstDayOfWeek: firstDayOfWeek,
          formatter: formatter,
        )),
      SavedViewChart.reflection =>
        padded(ReflectionMatrix(result: data, formatter: formatter)),
    };
  }
}
