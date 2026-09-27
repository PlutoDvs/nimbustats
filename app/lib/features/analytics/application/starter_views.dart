import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../data/pin_request.dart';
import 'trends_controller.dart';

/// The two cards "Add starter cards" pins: this month by category, and the
/// last six months. Offered on a button rather than seeded, so they reach
/// installs that already exist and appear only when asked for.
///
/// Their specs are the Breakdown and Trends tabs' own questions, undated; a
/// test holds them to that.
List<PinRequest> starterViews(AppLocalizations l10n) => [
      PinRequest.fromShown(
        name: l10n.starterThisMonthByCategory,
        shownSpec: QuerySpec(
          filters: const QueryFilters(direction: MoneyDirection.expense),
          groupBy: GroupByCategory(0),
          aggregate: Aggregate.sum,
        ),
        period: ViewPeriod(PeriodType.month, 1),
        chart: SavedViewChart.breakdown,
      ),
      PinRequest.fromShown(
        name: l10n.pinNameLastMonths(TrendsView.defaultPeriodCount),
        shownSpec: const QuerySpec(
          filters: QueryFilters(direction: MoneyDirection.expense),
          groupBy: GroupByPeriod(PeriodType.month),
          aggregate: Aggregate.sum,
        ),
        period: ViewPeriod(PeriodType.month, TrendsView.defaultPeriodCount),
        chart: SavedViewChart.trend,
      ),
    ];
