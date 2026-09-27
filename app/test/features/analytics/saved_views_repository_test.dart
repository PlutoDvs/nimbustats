import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/analytics/data/pin_request.dart';
import 'package:nimbustats/features/analytics/data/saved_views_repository.dart';

import 'support/dashboard_fixture.dart';

void main() {
  late AppDatabase db;
  late SavedViewsRepository repository;
  setUp(() {
    db = AppDatabase.openInMemory();
    repository = SavedViewsRepository(db.savedViewsDao);
  });
  tearDown(() => db.close());

  final shown = QuerySpec(
    filters: QueryFilters(
      dateRange: DateRange(const DateKey(20260901), const DateKey(20260930)),
      direction: MoneyDirection.expense,
    ),
    groupBy: GroupByCategory(0),
    aggregate: Aggregate.sum,
  );

  PinRequest request(String name) => PinRequest.fromShown(
        name: name,
        shownSpec: shown,
        period: ViewPeriod(PeriodType.month, 1),
        chart: SavedViewChart.breakdown,
      );

  test("a pin request drops the tab's dates and keeps the question", () {
    final pinned = request('Food');
    expect(pinned.spec.filters.dateRange, isNull);
    expect(pinned.spec.withDateRange(shown.filters.dateRange), shown);
  });

  test('pinning trims the name and appends in order', () async {
    final ids = await repository.pin([request('  Food  '), request('Rent')]);

    final views = await storedViews(db);
    expect(views.map((v) => v.id), ids);
    expect(views.map((v) => v.name), ['Food', 'Rent']);
  });

  test('a blank name is refused and nothing is written', () async {
    await expectLater(
        repository.pin([request('Food'), request('   ')]), throwsArgumentError);
    expect(await storedViews(db), isEmpty);
  });
}
