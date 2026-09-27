import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/analytics/application/breakdown_controller.dart';
import 'package:nimbustats/features/analytics/application/cross_tab_controller.dart';
import 'package:nimbustats/features/analytics/application/patterns_controller.dart';
import 'package:nimbustats/features/analytics/application/trends_controller.dart';
import 'package:nimbustats/features/analytics/data/pin_request.dart';
import 'package:nimbustats/features/analytics/data/saved_views_repository.dart';
import 'package:nimbustats/features/tags/data/tag_repository.dart';

import 'support/dashboard_fixture.dart';

final _month = const JalaliCalendar()
    .periodContaining(DateKey.fromDateTime(DateTime.now()), PeriodType.month);

Future<String> _pin(AppDatabase db, QuerySpec shown, SavedViewChart chart,
        {int months = 1}) async =>
    (await SavedViewsRepository(db.savedViewsDao).pin([
      PinRequest.fromShown(
        name: chart.name,
        shownSpec: shown,
        period: ViewPeriod(PeriodType.month, months),
        chart: chart,
      ),
    ]))
        .single;

Finder _inCard(String id, Finder matching) => find.descendant(
    of: find.byKey(Key('saved-view-card-$id')), matching: matching);

void main() {
  testWidgets('a breakdown card lists its top categories beside a pie',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final id = await _pin(
        db, BreakdownView(period: _month).spec, SavedViewChart.breakdown);
    await openAnalytics(tester, db);

    expect(_inCard(id, find.byType(PieChart)), findsOneWidget);
    expect(_inCard(id, find.text('Food')), findsOneWidget);
    expect(_inCard(id, find.text('Transport')), findsOneWidget);
    expect(_inCard(id, find.byKey(const Key('card-row-seed-food'))),
        findsOneWidget);
  });

  testWidgets('a trend card plots one point per month of its window',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final id = await _pin(
        db, TrendsView(periods: [_month]).spec, SavedViewChart.trend,
        months: 6);
    await openAnalytics(tester, db);

    final chart = tester.widget<LineChart>(
        _inCard(id, find.byKey(const Key('card-trend-chart'))));
    expect(chart.data.lineBarsData.single.spots, hasLength(6));
  });

  testWidgets('a cross-tab card names its top cells and says tags overlap',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final tags = TagRepository(db.tagsDao);
    final travel = await tags.create(name: 'Travel');
    await seedSpending(db, diningTags: [travel], transportTags: [travel]);
    final id = await _pin(
        db, CrossTabView(period: _month).spec, SavedViewChart.crossTab);
    await openAnalytics(tester, db);

    expect(_inCard(id, find.byKey(const Key('card-overlap-note'))),
        findsOneWidget);
    expect(_inCard(id, find.text('Travel · Food')), findsOneWidget);
  });

  testWidgets('a cross-tab card with no tagged spending says so',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final id = await _pin(
        db, CrossTabView(period: _month).spec, SavedViewChart.crossTab);
    await openAnalytics(tester, db);

    expect(
      _inCard(id, find.text('No tagged spending in this period')),
      findsOneWidget,
    );
    expect(
      _inCard(id, find.text('Nothing in this period')),
      findsNothing,
    );
  });

  testWidgets('hour and weekday cards draw bars', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final patterns = PatternsView(period: _month);
    final hour = await _pin(db, patterns.hourSpec, SavedViewChart.hourOfDay);
    final day =
        await _pin(db, patterns.weekdaySpec, SavedViewChart.dayOfWeek);
    await openAnalytics(tester, db);

    expect(_inCard(hour, find.byType(BarChart)), findsOneWidget);
    await revealInTab(tester, find.byKey(Key('saved-view-card-$day')));
    expect(_inCard(day, find.byType(BarChart)), findsOneWidget);
  });

  testWidgets('a reflection card shows what was avoidable and regretted',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final ids = await seedSpending(db);
    // Groceries (1000) is avoidable and regretted; the other 750 is not
    // labelled at all.
    await db.transactionsDao.setReflection(ids[0],
        necessity: Necessity.avoidable, satisfaction: Satisfaction.regret);
    final id = await _pin(db, PatternsView(period: _month).reflectionSpec,
        SavedViewChart.reflection);
    await openAnalytics(tester, db);

    expect(
      tester.widget<Text>(_inCard(id, find.byKey(const Key('card-regretted')))).data,
      total1000,
    );
    expect(
      tester.widget<Text>(_inCard(id, find.byKey(const Key('card-unlabelled')))).data,
      total750,
    );
  });
}
