import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/analytics/application/analytics_providers.dart';
import 'package:nimbustats/features/analytics/application/breakdown_controller.dart';
import 'package:nimbustats/features/analytics/application/starter_views.dart';
import 'package:nimbustats/features/analytics/application/trends_controller.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

import '../../support/harness.dart';
import 'support/dashboard_fixture.dart';

void main() {
  testWidgets('analytics opens on the dashboard', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await openAnalytics(tester, db);

    expect(find.byKey(const Key('dashboard-tab')), findsOneWidget);
    expect(find.text('Nothing pinned yet'), findsOneWidget);
  });

  testWidgets('an empty dashboard adds the two starter cards on request',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await openAnalytics(tester, db);

    await tester.tap(find.text('Add starter cards'));
    await tester.pumpAndSettle();

    expect(find.text('Spending by category'), findsOneWidget);
    expect(find.text('Last 6 months'), findsOneWidget);
    final views = await storedViews(db);
    expect(views.map((v) => v.chart), ['breakdown', 'trend']);
    expect(views.map((v) => v.periodCount), [1, 6]);
  });

  testWidgets('a failed starter write says so', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    // A write failure part-way through the starter insert, injected where
    // SQLite itself would raise one.
    await db.customStatement(
        'CREATE TEMP TRIGGER fail_saved_view BEFORE INSERT ON saved_views '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END");
    await openAnalytics(tester, db);

    // The failure still has to reach the framework's error handler rather
    // than vanish once the snackbar has shown it -- caught here directly
    // because it comes from a detached future the button never awaits.
    Object? caught;
    await runZonedGuarded(() async {
      await tester.tap(find.text('Add starter cards'));
      await tester.pumpAndSettle();
    }, (error, stack) => caught = error);

    expect(find.text('Could not save the change'), findsOneWidget);
    expect(await storedViews(db), isEmpty);
    expect(caught, isNotNull);
  });

  test('starter cards ask exactly what their tabs ask', () async {
    // Built by hand in starter_views.dart; this keeps them from drifting away
    // from the tabs they imitate.
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final month = const JalaliCalendar()
        .periodContaining(const DateKey(20260915), PeriodType.month);
    final starters = starterViews(l10n);

    expect(starters[0].spec,
        BreakdownView(period: month).spec.withDateRange(null));
    expect(starters[1].spec,
        TrendsView(periods: [month]).spec.withDateRange(null));
  });

  testWidgets('go to breakdown switches tab', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await openAnalytics(tester, db);

    await tester.tap(find.byKey(const Key('dashboard-go-to-breakdown')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('breakdown-period-label')), findsOneWidget);
  });

  testWidgets("a card shows its view's true total for the dashboard's month",
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, trend) = await pinStarters(db);
    await openAnalytics(tester, db);

    expect(textOf(tester, 'card-total-$breakdown'), total1750);
    // The six-month window ends with this month, so it holds the same 1750.
    expect(textOf(tester, 'card-total-$trend'), total1750);
  });

  testWidgets(
      "the trend starter's period spans months, the breakdown starter's "
      'is a single one', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, trend) = await pinStarters(db);
    await openAnalytics(tester, db);

    // viewPeriodLabel's multi-period form is 'first – last'; a range that
    // resolves to one period never contains that separator (dashboard_
    // anchor.dart's viewPeriodLabel).
    expect(textOf(tester, 'card-period-$breakdown'), isNot(contains(' – ')));
    expect(textOf(tester, 'card-period-$trend'), contains(' – '));
  });

  testWidgets('the month bar moves every card together', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, trend) = await pinStarters(db);
    await openAnalytics(tester, db);

    await tester.tap(find.byKey(const Key('dashboard-period-previous')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('card-empty-$breakdown')), findsOneWidget);
    expect(find.byKey(Key('card-empty-$trend')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dashboard-period-next')));
    await tester.pumpAndSettle();

    expect(textOf(tester, 'card-total-$breakdown'), total1750);
  });

  testWidgets("a starter card's name stays true on a past month",
      (tester) async {
    // D15: the month bar moves every card, so a starter named "This month by
    // category" sat above August's numbers the first time anyone pressed ◀.
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, _) = await pinStarters(db);
    await openAnalytics(tester, db);
    final thisMonth = textOf(tester, 'card-period-$breakdown');

    await tester.tap(find.byKey(const Key('dashboard-period-previous')));
    await tester.pumpAndSettle();

    expect(textOf(tester, 'card-period-$breakdown'), isNot(thisMonth));
    expect(textOf(tester, 'card-name-$breakdown'), 'Spending by category');
  });

  testWidgets('the month arrows mirror in Persian', (tester) async {
    Icon iconAt(String key) =>
        tester.widget<IconButton>(find.byKey(Key(key))).icon as Icon;

    final faDb = await categorisedDb();
    addTearDown(faDb.close);
    await seedSpending(faDb);
    final (breakdown, trend) =
        await pinStarters(faDb, locale: const Locale('fa'));
    await openAnalytics(tester, faDb, locale: const Locale('fa'));

    // fa is RTL: "previous" sits on the visual right, so its glyph must point
    // right to still read as backward-in-time, and "next" points left.
    expect(iconAt('dashboard-period-previous').icon, Icons.chevron_right);
    expect(iconAt('dashboard-period-next').icon, Icons.chevron_left);

    // The callback decides direction, not the glyph: previous still moves to
    // the earlier month even though its arrow now points right.
    await tester.tap(find.byKey(const Key('dashboard-period-previous')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('card-empty-$breakdown')), findsOneWidget);
    expect(find.byKey(Key('card-empty-$trend')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dashboard-period-next')));
    await tester.pumpAndSettle();

    expect(textOf(tester, 'card-total-$breakdown'), total1750);

    final enDb = await categorisedDb();
    addTearDown(enDb.close);
    await openAnalytics(tester, enDb);

    // en is LTR: the glyphs point the other way round.
    expect(iconAt('dashboard-period-previous').icon, Icons.chevron_left);
    expect(iconAt('dashboard-period-next').icon, Icons.chevron_right);
  });

  testWidgets('an unreadable view is its own card and the others still draw',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, _) = await pinStarters(db);
    await db.customStatement(
      'INSERT INTO saved_views (id, name, spec_json, chart_type, pinned, '
      'sort_order, created_at, updated_at) '
      "VALUES ('bad', 'Broken', '{not json', 'breakdown', 1, 99, 0, 0)",
    );
    await openAnalytics(tester, db);

    expect(find.byKey(const Key('card-unreadable-bad')), findsOneWidget);
    expect(textOf(tester, 'card-total-$breakdown'), total1750);
  });

  testWidgets('a failing query shows on its own card only', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, trend) = await pinStarters(db);
    usePhoneViewport(tester);
    await pumpApp(tester, database: db, overrides: [
      analyticsResultProvider.overrideWith((ref, spec) =>
          spec.groupBy is GroupByPeriod
              ? Future<AnalyticsResult>.error(StateError('trend query failed'))
              : ref.watch(analyticsEngineProvider).run(spec)),
    ]);
    await tester.tap(find.descendant(
      of: find.byKey(const Key('nav-bar')),
      matching: find.byIcon(Icons.insights_outlined),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('card-error-$trend')), findsOneWidget);
    expect(textOf(tester, 'card-total-$breakdown'), total1750);
  });

  testWidgets('a card reads as its name, period and total', (tester) async {
    final handle = tester.ensureSemantics();
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    await pinStarters(db);
    await openAnalytics(tester, db);

    expect(
      find.bySemanticsLabel(
          RegExp('Spending by category.*$total1750', dotAll: true)),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('in Persian the cards are right-to-left', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, _) = await pinStarters(db, locale: const Locale('fa'));
    await openAnalytics(tester, db, locale: const Locale('fa'));

    final name = find.byKey(Key('card-name-$breakdown'));
    // ‌ is the zero-width non-joiner Persian spells هزینه‌ها with.
    expect(tester.widget<Text>(name).data, 'هزینه‌ها به تفکیک دسته');
    expect(Directionality.of(tester.element(name)), TextDirection.rtl);
    expect(textOf(tester, 'card-total-$breakdown'), total1750);
  });
}
