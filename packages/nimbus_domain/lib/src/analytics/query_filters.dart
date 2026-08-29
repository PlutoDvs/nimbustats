import 'package:meta/meta.dart';

import '../calendar/date_key.dart';
import 'amount_range.dart';
import 'json_support.dart';
import 'reflection_levels.dart';
import 'tag_filter.dart';

/// Every way a query can be narrowed.
///
/// Pure and serializable: Phase 5 stores a `QuerySpec` as a goal's scope, so a
/// field that does not survive a JSON round trip is a data-loss bug in a later
/// phase rather than a cosmetic one.
@immutable
final class QueryFilters {
  const QueryFilters({
    this.dateRange,
    this.direction,
    this.categorySubtreePaths = const [],
    this.tags,
    this.paymentMethodIds = const [],
    this.necessity = const {},
    this.satisfaction = const {},
    this.amountRange,
    this.confirmedOnly = false,
    this.searchText,
  });

  factory QueryFilters.fromJson(Map<String, Object?> json) => QueryFilters(
        dateRange: _rangeOf(json['dateRange']),
        direction: json['direction'] == null
            ? null
            : _enumOf(MoneyDirection.values, json['direction'], 'direction'),
        categorySubtreePaths: _stringsOf(json['categorySubtreePaths']),
        tags: json['tags'] == null
            ? null
            : TagFilter.fromJson(jsonMapOf(json['tags'], 'tags')),
        paymentMethodIds: _stringsOf(json['paymentMethodIds']),
        necessity: _stringsOf(json['necessity'])
            .map((v) => _enumOf(NecessityLevel.values, v, 'necessity'))
            .toSet(),
        satisfaction: _stringsOf(json['satisfaction'])
            .map((v) => _enumOf(SatisfactionLevel.values, v, 'satisfaction'))
            .toSet(),
        amountRange: json['amountRange'] == null
            ? null
            : AmountRange.fromJson(
                jsonMapOf(json['amountRange'], 'amountRange')),
        confirmedOnly: json['confirmedOnly'] as bool? ?? false,
        searchText: json['searchText'] as String?,
      );

  final DateRange? dateRange;
  final MoneyDirection? direction;

  /// Materialized paths. Each names a subtree, not a single category.
  final List<String> categorySubtreePaths;
  final TagFilter? tags;
  final List<String> paymentMethodIds;
  final Set<NecessityLevel> necessity;
  final Set<SatisfactionLevel> satisfaction;
  final AmountRange? amountRange;

  /// Defaults to false: unconfirmed captures are included everywhere unless a
  /// caller opts out, so a dashboard and a goal cannot disagree by accident.
  final bool confirmedOnly;
  final String? searchText;

  Map<String, Object?> toJson() => {
        if (dateRange != null)
          'dateRange': {
            'start': dateRange!.startInclusive.value,
            'end': dateRange!.endInclusive.value,
          },
        if (direction != null) 'direction': direction!.name,
        if (categorySubtreePaths.isNotEmpty)
          'categorySubtreePaths': categorySubtreePaths,
        if (tags != null) 'tags': tags!.toJson(),
        if (paymentMethodIds.isNotEmpty) 'paymentMethodIds': paymentMethodIds,
        if (necessity.isNotEmpty)
          'necessity': necessity.map((n) => n.name).toList(),
        if (satisfaction.isNotEmpty)
          'satisfaction': satisfaction.map((s) => s.name).toList(),
        if (amountRange != null) 'amountRange': amountRange!.toJson(),
        if (confirmedOnly) 'confirmedOnly': true,
        if (searchText != null) 'searchText': searchText,
      };

  static DateRange? _rangeOf(Object? value) {
    if (value == null) return null;
    final map = jsonMapOf(value, 'dateRange');
    final start = map['start'];
    final end = map['end'];
    if (start is! int || end is! int) {
      // Both ends are required. Defaulting one would quietly widen or narrow
      // every result computed from the restored filter set.
      throw FormatException('dateRange needs int start and end, got '
          '"$start" and "$end"');
    }
    return DateRange(DateKey(start), DateKey(end));
  }

  static List<String> _stringsOf(Object? value) => switch (value) {
        null => const <String>[],
        final List<Object?> list => list.map((e) => e.toString()).toList(),
        _ => throw FormatException('expected a string list, got "$value"'),
      };

  /// Throws on an unknown value rather than dropping it. A dropped filter
  /// *widens* the query, which on a goal means reporting under budget while
  /// the user is over.
  static T _enumOf<T extends Enum>(List<T> values, Object? raw, String field) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw FormatException('unknown $field value "$raw"');
  }

  @override
  bool operator ==(Object other) =>
      other is QueryFilters &&
      other.dateRange == dateRange &&
      other.direction == direction &&
      _sameList(other.categorySubtreePaths, categorySubtreePaths) &&
      other.tags == tags &&
      _sameList(other.paymentMethodIds, paymentMethodIds) &&
      _sameSet(other.necessity, necessity) &&
      _sameSet(other.satisfaction, satisfaction) &&
      other.amountRange == amountRange &&
      other.confirmedOnly == confirmedOnly &&
      other.searchText == searchText;

  @override
  int get hashCode => Object.hash(
        dateRange,
        direction,
        Object.hashAll(categorySubtreePaths),
        tags,
        Object.hashAll(paymentMethodIds),
        Object.hashAllUnordered(necessity),
        Object.hashAllUnordered(satisfaction),
        amountRange,
        confirmedOnly,
        searchText,
      );

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameSet<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);
}
