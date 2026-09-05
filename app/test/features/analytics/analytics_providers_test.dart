import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/features/analytics/application/analytics_providers.dart';
import 'package:nimbustats/features/settings/application/settings_providers.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/transactions/data/transaction_draft.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.openInMemory();
    await CategorySeeder(db).seedIfEmpty(
      roots: const [SeedCategoryNode(id: 'seed-food', name: 'Food')],
      uncategorizedName: 'Uncategorized',
    );
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  /// Three expenses on known days of January 2026, in minor units.
  Future<void> seedTransactions() async {
    final repo =
        TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman);
    for (final (day, amount) in [(5, 1000), (12, 500), (20, 250)]) {
      await repo.add(TransactionDraft(
        amount: Money(amount),
        direction: TxDirection.expense,
        categoryId: 'seed-food',
        // Built local, then converted: the stored date key is derived from
        // local time, so a UTC literal would land these on a different day
        // depending on which timezone the suite runs in.
        occurredAtUtc: DateTime(2026, 1, day, 10).toUtc(),
      ));
    }
  }

  const januaryTotal = QuerySpec(
    filters: QueryFilters(
      dateRange: DateRange(DateKey(20260101), DateKey(20260131)),
    ),
    groupBy: GroupByNone(),
    aggregate: Aggregate.sum,
  );

  test('the engine takes its calendar from settings', () async {
    // A Jalali month is not a Gregorian one, so an engine built with the wrong
    // calendar buckets every period query off by weeks -- and only visibly so
    // near a year boundary, where nobody looks.
    expect(container.read(analyticsEngineProvider).calendar,
        isA<JalaliCalendar>());

    await container.read(settingsRepositoryProvider).save(
        AppSettings.defaults.copyWith(calendarKind: CalendarKind.gregorian));
    final sub = container.listen(settingsProvider, (_, __) {});
    await container.read(settingsProvider.future);
    addTearDown(sub.close);

    expect(container.read(analyticsEngineProvider).calendar,
        isA<GregorianCalendar>());
  });

  test('a spec resolves to hand-computed totals', () async {
    await seedTransactions();

    final result = await container.read(analyticsResultProvider(
      januaryTotal,
    ).future);

    // 1000 + 500 + 250, computed here rather than by a second query.
    expect(result.trueTotal, const Money(1750));
    expect(result.trueCount, 3);
    expect(result.buckets, hasLength(1));
    expect(result.buckets.single.key, const TotalKey());
  });

  test('the true total survives the trip to the UI layer', () async {
    // The engine returns trueTotal so a tag chart can disclose that its slices
    // do not sum to it. A provider that dropped it would make that disclosure
    // impossible without anything failing.
    await seedTransactions();

    final result = await container.read(analyticsResultProvider(
      januaryTotal,
    ).future);

    expect(result.overlaps, isFalse);
    expect(result.bucketSum, result.trueTotal);
  });

  test('an empty range yields no buckets rather than an error', () async {
    await seedTransactions();

    final result = await container.read(analyticsResultProvider(
      const QuerySpec(
        filters: QueryFilters(
          dateRange: DateRange(DateKey(20250101), DateKey(20250131)),
        ),
        groupBy: GroupByNone(),
        aggregate: Aggregate.sum,
      ),
    ).future);

    expect(result.trueTotal, Money.zero);
    expect(result.trueCount, 0);
  });

  test('two identical specs share one provider', () async {
    // The family is keyed on QuerySpec's value equality. If that ever stopped
    // holding, every rebuild would issue a fresh query against the database
    // for a chart that had not changed.
    await seedTransactions();

    final a = analyticsResultProvider(januaryTotal);
    const copy = QuerySpec(
      filters: QueryFilters(
        dateRange: DateRange(DateKey(20260101), DateKey(20260131)),
      ),
      groupBy: GroupByNone(),
      aggregate: Aggregate.sum,
    );
    expect(a, analyticsResultProvider(copy));
  });
}
