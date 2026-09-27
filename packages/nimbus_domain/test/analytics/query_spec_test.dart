import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

// Not const: GroupByCategory validates its depth, so it has a body.
final everyDimension = <GroupBy>[
  GroupByNone(),
  GroupByCategory(2),
  GroupByTag(),
  GroupByPeriod(PeriodType.month),
  GroupByPaymentMethod(),
  GroupByMerchant(),
  GroupByReflection(),
  GroupByHourOfDay(),
  GroupByDayOfWeek(),
  GroupByTagCrossCategory(1),
];

/// Exhaustive over the sealed family on purpose.
///
/// Adding a GroupBy case makes this switch non-exhaustive, which is a compile
/// error rather than a test that quietly keeps passing with one dimension
/// untested.
String kindOf(GroupBy dimension) => switch (dimension) {
      GroupByNone() => 'none',
      GroupByCategory() => 'category',
      GroupByTag() => 'tag',
      GroupByPeriod() => 'period',
      GroupByPaymentMethod() => 'paymentMethod',
      GroupByMerchant() => 'merchant',
      GroupByReflection() => 'reflection',
      GroupByHourOfDay() => 'hourOfDay',
      GroupByDayOfWeek() => 'dayOfWeek',
      GroupByTagCrossCategory() => 'tagCrossCategory',
    };

void main() {
  group('GroupBy', () {
    test('every dimension round-trips as its own kind', () {
      for (final dimension in everyDimension) {
        final restored = GroupBy.fromJson(dimension.toJson());
        expect(restored, dimension, reason: 'round trip changed $dimension');
        expect(restored.runtimeType, dimension.runtimeType);
      }
    });

    test('category depth survives the round trip', () {
      // Losing the depth silently regroups a chart from sub-category to
      // top-level, which looks like a data change rather than a bug.
      final restored = GroupBy.fromJson(GroupByCategory(3).toJson());
      expect((restored as GroupByCategory).depth, 3);
    });

    test('period type survives the round trip', () {
      final restored =
          GroupBy.fromJson(const GroupByPeriod(PeriodType.quarter).toJson());
      expect((restored as GroupByPeriod).period, PeriodType.quarter);
    });

    test('a negative category depth is rejected', () {
      expect(() => GroupByCategory(-1), throwsArgumentError);
    });

    test('an unknown kind throws rather than falling back to none', () {
      // Falling back to "no grouping" turns a breakdown into a single total,
      // which renders as a plausible-looking chart with one bar.
      expect(() => GroupBy.fromJson({'kind': 'wat'}), throwsFormatException);
    });

    test('every case is covered by this test', () {
      // Two guards, because the first one alone is not enough. Distinct kinds
      // only prove the list has no duplicates -- a dimension added to the
      // library and forgotten here would still pass.
      expect(everyDimension.map((d) => d.kind).toSet(),
          hasLength(everyDimension.length));

      // The real guard is the switch in `kindOf` below: GroupBy is sealed, so
      // adding a case makes that switch non-exhaustive and this file stops
      // compiling. Comparing its output against the list catches the case
      // where somebody adds the branch but not the fixture.
      expect(everyDimension.map(kindOf).toSet(),
          everyDimension.map((d) => d.kind).toSet());
    });
  });

  group('QuerySpec', () {
    test('a fully populated spec round-trips losslessly', () {
      // Phase 5 stores this as a goal's scope.
      final spec = QuerySpec(
        filters: QueryFilters(
          dateRange:
              DateRange(const DateKey(20260101), const DateKey(20260131)),
          direction: MoneyDirection.expense,
          tags: TagsAny(const ['/travel/']),
          confirmedOnly: true,
        ),
        groupBy: GroupByCategory(1),
        aggregate: Aggregate.sum,
      );
      expect(QuerySpec.fromJson(spec.toJson()), spec);
    });

    test('the minimal spec round-trips', () {
      const spec = QuerySpec(
          filters: QueryFilters(),
          groupBy: GroupByNone(),
          aggregate: Aggregate.sum);
      expect(QuerySpec.fromJson(spec.toJson()), spec);
    });

    test('isTagDimension is true for exactly the dimensions with a tag axis',
        () {
      // Both of them: a tag breakdown, and the tag x category cross-tab, whose
      // rows overlap for the same reason. Written as an explicit type test
      // rather than reading the flag back off the spec, so this asserts the
      // intended set rather than restating the implementation.
      for (final dimension in everyDimension) {
        final spec = QuerySpec(
            filters: const QueryFilters(),
            groupBy: dimension,
            aggregate: Aggregate.sum);
        final hasTagAxis =
            dimension is GroupByTag || dimension is GroupByTagCrossCategory;
        expect(spec.isTagDimension, hasTagAxis,
            reason: '$dimension reported the wrong tag-dimension answer, and '
                'that flag is what makes a chart disclose double-counting');
      }
    });

    test('a malformed document throws FormatException, not a TypeError', () {
      // Decision 1 says fromJson throws on a missing required field. A bare
      // null-check throws a TypeError instead, which is an Error rather than
      // an Exception -- so a caller that reasonably catches Exception around
      // a stored spec would not catch it, and the app would die on a corrupt
      // row instead of reporting it.
      final malformed = <Map<String, Object?>>[
        {'nope': 1},
        {'groupBy': {'kind': 'none'}, 'aggregate': 'sum'}, // no filters
        {'filters': <String, Object?>{}, 'aggregate': 'sum'}, // no groupBy
        {'filters': 'not a map', 'groupBy': {'kind': 'none'}, 'aggregate': 'sum'},
      ];
      for (final json in malformed) {
        expect(() => QuerySpec.fromJson(json), throwsFormatException,
            reason: 'did not reject $json as a FormatException');
      }
    });

    test('a category group-by missing its depth throws FormatException', () {
      expect(() => GroupBy.fromJson({'kind': 'category'}),
          throwsFormatException);
      expect(() => GroupBy.fromJson({'kind': 'category', 'depth': 'two'}),
          throwsFormatException);
    });

    test('an unknown aggregate throws', () {
      expect(
          () => QuerySpec.fromJson({
                'filters': <String, Object?>{},
                'groupBy': {'kind': 'none'},
                'aggregate': 'median',
              }),
          throwsFormatException);
    });

    test('withDateRange replaces the range and keeps every other field', () {
      final full = QuerySpec(
        filters: QueryFilters(
          dateRange: DateRange(const DateKey(20260101), const DateKey(20260131)),
          direction: MoneyDirection.expense,
          categorySubtreePaths: const ['/food/'],
          tags: TagsAny(const ['/travel/']),
          paymentMethodIds: const ['card'],
          necessity: const {NecessityLevel.avoidable},
          satisfaction: const {SatisfactionLevel.regret},
          amountRange: AmountRange(minInclusive: const Money(100)),
          confirmedOnly: true,
          searchText: 'cafe',
        ),
        groupBy: GroupByCategory(1),
        aggregate: Aggregate.sum,
      );

      final undated = full.withDateRange(null);

      expect(undated.filters.dateRange, isNull);
      // Putting the range back must give the original: proof nothing else was
      // dropped on the way out.
      expect(undated.withDateRange(full.filters.dateRange), full);
    });
  });
}
