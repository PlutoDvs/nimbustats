import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('GroupByTagCrossCategory', () {
    test('round-trips with its depth', () {
      final restored =
          GroupBy.fromJson(GroupByTagCrossCategory(2).toJson());
      expect(restored, GroupByTagCrossCategory(2));
      expect((restored as GroupByTagCrossCategory).depth, 2);
    });

    test('a negative depth is rejected', () {
      expect(() => GroupByTagCrossCategory(-1), throwsArgumentError);
    });

    test('a missing or non-integer depth throws FormatException', () {
      expect(() => GroupBy.fromJson({'kind': 'tagCrossCategory'}),
          throwsFormatException);
      expect(
          () => GroupBy.fromJson({'kind': 'tagCrossCategory', 'depth': 'two'}),
          throwsFormatException);
    });

    test('it is not equal to a plain category grouping at the same depth', () {
      expect(GroupByTagCrossCategory(1), isNot(GroupByCategory(1)));
    });
  });

  group('overlap disclosure', () {
    test('a cross-tab with a tag axis reports that buckets overlap', () {
      // This is the switch that makes the UI show its disclosure. A cross-tab
      // that failed to set it would render a matrix whose cells sum to more
      // than the total with nothing on screen saying so -- the exact failure
      // the phase brief names, and it would look perfectly plausible.
      final spec = QuerySpec(
        filters: const QueryFilters(),
        groupBy: GroupByTagCrossCategory(0),
        aggregate: Aggregate.sum,
      );
      expect(spec.isTagDimension, isTrue);
    });

    test('a category-only breakdown still reports no overlap', () {
      final spec = QuerySpec(
        filters: const QueryFilters(),
        groupBy: GroupByCategory(0),
        aggregate: Aggregate.sum,
      );
      expect(spec.isTagDimension, isFalse);
    });
  });

  group('TagCategoryKey', () {
    test('both axes take part in equality', () {
      const a = TagCategoryKey(
          tagId: 'travel',
          tagPath: '/travel/',
          categoryId: 'food',
          categoryPath: '/food/');
      const sameCategoryOtherTag = TagCategoryKey(
          tagId: 'work',
          tagPath: '/work/',
          categoryId: 'food',
          categoryPath: '/food/');
      const sameTagOtherCategory = TagCategoryKey(
          tagId: 'travel',
          tagPath: '/travel/',
          categoryId: 'transport',
          categoryPath: '/transport/');

      expect(a, isNot(sameCategoryOtherTag));
      expect(a, isNot(sameTagOtherCategory));
      expect(
        a,
        const TagCategoryKey(
            tagId: 'travel',
            tagPath: '/travel/',
            categoryId: 'food',
            categoryPath: '/food/'),
      );
    });

    test('a cell is usable as a map key', () {
      // The matrix screen indexes cells by this, so a broken hashCode would
      // silently drop cells rather than fail.
      const a = TagCategoryKey(
          tagId: 't', tagPath: '/t/', categoryId: 'c', categoryPath: '/c/');
      const b = TagCategoryKey(
          tagId: 't', tagPath: '/t/', categoryId: 'c', categoryPath: '/c/');
      expect({a: 1}[b], 1);
    });
  });
}
