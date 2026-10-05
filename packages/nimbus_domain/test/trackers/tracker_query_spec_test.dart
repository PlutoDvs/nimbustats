import 'dart:convert';

import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

// Not const: TrackerGroupByPeriod validates its period, so it has a body.
final everyDimension = <TrackerGroupBy>[
  const TrackerGroupByNone(),
  const TrackerGroupByTracker(),
  const TrackerGroupByDay(),
  TrackerGroupByPeriod(PeriodType.month),
  const TrackerGroupByHourOfDay(),
  const TrackerGroupByDayOfWeek(),
];

/// Exhaustive on purpose: a new case makes this a compile error rather than a
/// dimension that is never round-tripped.
String kindOf(TrackerGroupBy dimension) => switch (dimension) {
      TrackerGroupByNone() => 'none',
      TrackerGroupByTracker() => 'tracker',
      TrackerGroupByDay() => 'day',
      TrackerGroupByPeriod() => 'period',
      TrackerGroupByHourOfDay() => 'hourOfDay',
      TrackerGroupByDayOfWeek() => 'dayOfWeek',
    };

void main() {
  const october = DateRange(DateKey(20261001), DateKey(20261031));

  TrackerQuerySpec spec({
    List<String> ids = const ['cig'],
    DateRange? range = october,
    TrackerGroupBy groupBy = const TrackerGroupByDay(),
    Aggregate aggregate = Aggregate.sum,
  }) =>
      TrackerQuerySpec(
          trackerIds: ids,
          dateRange: range,
          groupBy: groupBy,
          aggregate: aggregate);

  group('TrackerGroupBy', () {
    test('every dimension round-trips as its own kind', () {
      for (final dimension in everyDimension) {
        final json = dimension.toJson();
        expect(json['kind'], kindOf(dimension));
        final restored = TrackerGroupBy.fromJson(json);
        expect(restored, dimension, reason: 'round trip changed $dimension');
        expect(restored.runtimeType, dimension.runtimeType);
      }
    });

    test('the period survives the round trip', () {
      final restored = TrackerGroupBy.fromJson(
          TrackerGroupByPeriod(PeriodType.quarter).toJson());
      expect((restored as TrackerGroupByPeriod).period, PeriodType.quarter);
    });

    test('days are asked for one way only', () {
      expect(() => TrackerGroupByPeriod(PeriodType.day), throwsArgumentError);
      expect(
          () => TrackerGroupBy.fromJson({'kind': 'period', 'period': 'day'}),
          throwsFormatException);
    });

    test('an unknown kind or period is refused, not guessed', () {
      expect(() => TrackerGroupBy.fromJson({'kind': 'merchant'}),
          throwsFormatException);
      expect(
          () => TrackerGroupBy.fromJson({'kind': 'period', 'period': 'decade'}),
          throwsFormatException);
    });
  });

  group('TrackerQuerySpec', () {
    test('round-trips every dimension and aggregate, dated or not', () {
      for (final dimension in everyDimension) {
        for (final aggregate in Aggregate.values) {
          for (final range in [october, null]) {
            final original =
                spec(groupBy: dimension, aggregate: aggregate, range: range);
            expect(TrackerQuerySpec.fromJson(original.toJson()), original,
                reason: 'round trip changed $original');
          }
        }
      }
    });

    test('survives being stored as JSON text', () {
      // Phase 5 stores the spec as text; ints must come back as ints.
      final original = spec(ids: ['cig', 'water']);
      final text = jsonEncode(original.toJson());
      expect(
          TrackerQuerySpec.fromJson(jsonDecode(text) as Map<String, Object?>),
          original);
    });

    test('an empty tracker list is refused', () {
      expect(() => spec(ids: const []), throwsArgumentError);
    });

    test('stored tracker ids must be a non-empty list of strings', () {
      final json = spec().toJson();
      for (final bad in [null, <String>[], 'cig', [1]]) {
        expect(
            () => TrackerQuerySpec.fromJson({...json, 'trackerIds': bad}),
            throwsFormatException,
            reason: 'accepted trackerIds "$bad"');
      }
    });

    test('a half-open date range is refused', () {
      final json = spec().toJson();
      expect(
          () => TrackerQuerySpec.fromJson({
                ...json,
                'dateRange': {'start': 20261001},
              }),
          throwsFormatException);
    });

    test('an unknown aggregate is refused', () {
      expect(
          () => TrackerQuerySpec.fromJson(
              {...spec().toJson(), 'aggregate': 'median'}),
          throwsFormatException);
    });

    test('withDateRange replaces only the range', () {
      final original = spec(groupBy: const TrackerGroupByHourOfDay());
      const november = DateRange(DateKey(20261101), DateKey(20261130));
      expect(original.withDateRange(november),
          spec(groupBy: const TrackerGroupByHourOfDay(), range: november));
      expect(original.withDateRange(null).dateRange, isNull);
    });

    test('equal specs are equal and hash alike; ids compare in order', () {
      expect(spec(ids: ['a', 'b']), spec(ids: ['a', 'b']));
      expect(spec(ids: ['a', 'b']).hashCode, spec(ids: ['a', 'b']).hashCode);
      expect(spec(ids: ['a', 'b']), isNot(spec(ids: ['b', 'a'])));
      expect(spec(), isNot(spec(aggregate: Aggregate.count)));
    });

    test('the ids cannot change after construction', () {
      // The spec keys a provider cache; a list mutated after hashing would
      // strand its entry.
      final ids = ['cig'];
      final s = spec(ids: ids);
      ids.add('water');
      expect(s.trackerIds, ['cig']);
      expect(() => s.trackerIds.add('x'), throwsUnsupportedError);
    });
  });
}
