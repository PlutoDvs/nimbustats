import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import 'support/analytics_fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    await seedAnalyticsFixture(db);
  });
  tearDown(() => db.close());

  /// Runs a filtered total so a predicate is checked against real rows rather
  /// than against its own SQL string.
  Future<({int total, int count})> totalWith(QueryFilters filters) async {
    final clause = AnalyticsPredicates.whereClause(filters);
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(t.amount),0) AS total, COUNT(*) AS n '
      'FROM transactions t WHERE ${clause.sql}',
      variables: clause.variables,
    ).getSingle();
    return (total: row.data['total']! as int, count: row.data['n']! as int);
  }

  group('the boundary mapping', () {
    test('every domain mirror maps to a nimbus_data value', () {
      // The two enum families live in different packages by necessity
      // (nimbus_domain cannot import nimbus_data). This test is the only
      // thing stopping them drifting apart.
      for (final value in MoneyDirection.values) {
        expect(AnalyticsPredicates.directionOf(value).name, value.name);
      }
      for (final value in NecessityLevel.values) {
        expect(AnalyticsPredicates.necessityOf(value).name, value.name);
      }
      for (final value in SatisfactionLevel.values) {
        expect(AnalyticsPredicates.satisfactionOf(value).name, value.name);
      }
    });

    test('the families are the same size in both directions', () {
      // Catches a value added to nimbus_data that the domain mirror lacks --
      // the direction the loop above cannot see.
      expect(TxDirection.values.length, MoneyDirection.values.length);
      expect(Necessity.values.length, NecessityLevel.values.length);
      expect(Satisfaction.values.length, SatisfactionLevel.values.length);
    });
  });

  group('whereClause', () {
    test('the empty filter set matches every live row', () {
      // 1000 + 500 + 250, hand-computed from the fixture.
      expect(
          totalWith(const QueryFilters()), completion((total: 1750, count: 3)));
    });

    test('deleted rows are excluded even with no filters', () async {
      await db.customStatement(
          "UPDATE transactions SET deleted_at = 1 WHERE id = 't3'");
      expect(await totalWith(const QueryFilters()), (total: 1500, count: 2));
    });

    test('a date range is an inclusive key range', () async {
      final filters = QueryFilters(
          dateRange:
              DateRange(const DateKey(20260101), const DateKey(20260228)));
      expect(await totalWith(filters), (total: 1500, count: 2));
    });

    test('the range boundaries are inclusive on both ends', () async {
      final filters = QueryFilters(
          dateRange:
              DateRange(const DateKey(20260115), const DateKey(20260115)));
      expect(await totalWith(filters), (total: 1000, count: 1));
    });

    test('an amount range filters on minor units', () async {
      final filters = QueryFilters(
          amountRange: AmountRange(minInclusive: const Money(500)));
      expect(await totalWith(filters), (total: 1500, count: 2));
    });

    test('ANY over a tag subtree includes descendants', () async {
      // t1 via /travel/ and t2 via /travel/flights/ -- both are inside the
      // /travel/ subtree.
      final filters = QueryFilters(tags: TagsAny(const ['/travel/']));
      expect(await totalWith(filters), (total: 1500, count: 2));
    });

    test('ANY counts a transaction once even when two of its tags match',
        () async {
      // t2 carries BOTH /travel/ and /travel/flights/. EXISTS, not JOIN.
      // A JOIN here returns 2000/n=3; this is the measured difference.
      final filters = QueryFilters(tags: TagsAny(const ['/travel/']));
      final result = await totalWith(filters);
      expect(result.count, 2);
      expect(result.total, 1500);
    });

    test('ALL requires every subtree', () async {
      // Only t1 carries both /travel/ and /food/.
      final filters = QueryFilters(tags: TagsAll(const ['/travel/', '/food/']));
      expect(await totalWith(filters), (total: 1000, count: 1));
    });

    test('NONE excludes anything in the subtree', () async {
      // Everything except t1 and t2.
      final filters = QueryFilters(tags: TagsNone(const ['/travel/']));
      expect(await totalWith(filters), (total: 250, count: 1));
    });

    test('a category subtree filter uses the path range', () async {
      const filters = QueryFilters(categorySubtreePaths: ['/cat/']);
      expect(await totalWith(filters), (total: 1750, count: 3));
    });

    test('confirmedOnly excludes unconfirmed captures', () async {
      await db.customStatement(
          "UPDATE transactions SET is_confirmed = 0 WHERE id = 't1'");
      expect(await totalWith(const QueryFilters(confirmedOnly: true)),
          (total: 750, count: 2));
      // and the default still includes them
      expect(await totalWith(const QueryFilters()), (total: 1750, count: 3));
    });

    test('search text escapes LIKE wildcards', () async {
      await db.customStatement(
          "UPDATE transactions SET merchant = '100% cotton' WHERE id = 't1'");
      // A literal % must not match every row.
      expect(await totalWith(const QueryFilters(searchText: '%')),
          (total: 1000, count: 1));
    });

    test('filters compose with AND', () async {
      final filters = QueryFilters(
        dateRange: DateRange(const DateKey(20260101), const DateKey(20260228)),
        tags: TagsAny(const ['/travel/']),
        amountRange: AmountRange(minInclusive: const Money(600)),
      );
      expect(await totalWith(filters), (total: 1000, count: 1));
    });

    test('every value reaches SQL as a bound variable', () {
      // No user value is interpolated into the statement text.
      final clause = AnalyticsPredicates.whereClause(
          const QueryFilters(searchText: "o'brien"));
      expect(clause.sql, isNot(contains("o'brien")));
      expect(clause.variables, isNotEmpty);
    });
  });
}
