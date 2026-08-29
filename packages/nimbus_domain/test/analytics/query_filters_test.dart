import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('TagFilter', () {
    test('each kind round-trips through JSON as its own kind', () {
      final filters = <TagFilter>[
        TagsAll(const ['/travel/', '/food/']),
        TagsAny(const ['/travel/']),
        TagsNone(const ['/work/']),
      ];
      for (final filter in filters) {
        final restored = TagFilter.fromJson(filter.toJson());
        expect(restored, filter);
        expect(restored.runtimeType, filter.runtimeType,
            reason: 'ALL, ANY and NONE mean different things; a round trip '
                'that changes the kind changes the answer');
      }
    });

    test('subtreePaths exposes the paths regardless of kind', () {
      expect(TagsAny(const ['/a/', '/b/']).subtreePaths, ['/a/', '/b/']);
    });

    test('an empty path list is rejected', () {
      // "all of nothing" and "none of nothing" are degenerate and almost
      // certainly a UI bug rather than an intent.
      expect(() => TagsAll(const []), throwsArgumentError);
    });

    test('an unknown kind throws rather than defaulting to ANY', () {
      // Defaulting would turn "none of #work" into "any of #work" -- the
      // exact inverse of what the user asked for.
      expect(() => TagFilter.fromJson({'kind': 'wat', 'paths': <String>['/a/']}),
          throwsFormatException);
    });
  });

  group('QueryFilters', () {
    test('the default filter set is unfiltered and includes unconfirmed', () {
      const filters = QueryFilters();
      expect(filters.dateRange, isNull);
      expect(filters.confirmedOnly, isFalse,
          reason: 'Decision 7: unconfirmed captures are included by default, '
              'the same way everywhere');
      expect(filters.categorySubtreePaths, isEmpty);
    });

    test('a fully populated filter set round-trips losslessly', () {
      // Phase 5 stores a QuerySpec as a goal's scope. A field that does not
      // survive this is a data-loss bug in a later phase.
      final filters = QueryFilters(
        dateRange: DateRange(const DateKey(20260101), const DateKey(20261231)),
        direction: MoneyDirection.expense,
        categorySubtreePaths: const ['/food/', '/transport/'],
        tags: TagsAll(const ['/travel/']),
        paymentMethodIds: const ['pm1', 'pm2'],
        necessity: const {NecessityLevel.avoidable},
        satisfaction: const {SatisfactionLevel.regret},
        amountRange: AmountRange(minInclusive: const Money(1000)),
        confirmedOnly: true,
        searchText: 'taxi',
      );
      expect(QueryFilters.fromJson(filters.toJson()), filters);
    });

    test('the empty filter set round-trips too', () {
      const filters = QueryFilters();
      expect(QueryFilters.fromJson(filters.toJson()), filters);
    });

    test('an unknown necessity value throws rather than being dropped', () {
      // A silently dropped filter widens the query. On a goal, that means
      // reporting under budget when the user is over.
      expect(
          () => QueryFilters.fromJson({
                'necessity': ['wat']
              }),
          throwsFormatException);
    });

    test('value equality covers every field', () {
      const a = QueryFilters(direction: MoneyDirection.expense);
      const b = QueryFilters(direction: MoneyDirection.income);
      expect(a, isNot(b));
      expect(a, const QueryFilters(direction: MoneyDirection.expense));
    });
  });
}
