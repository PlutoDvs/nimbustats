import 'package:meta/meta.dart';

import 'aggregate.dart';
import 'group_by.dart';
import 'json_support.dart';
import 'query_filters.dart';

/// One analytical question: what to include, how to bucket it, what to compute.
///
/// Pure and serializable by requirement, not by preference -- Phase 5 persists
/// a `QuerySpec` as a goal's scope, so this type is a storage format as much as
/// an argument.
@immutable
final class QuerySpec {
  const QuerySpec({
    required this.filters,
    required this.groupBy,
    required this.aggregate,
  });

  factory QuerySpec.fromJson(Map<String, Object?> json) => QuerySpec(
        filters: QueryFilters.fromJson(jsonMapOf(json['filters'], 'filters')),
        groupBy: GroupBy.fromJson(jsonMapOf(json['groupBy'], 'groupBy')),
        aggregate: _aggregateOf(json['aggregate']),
      );

  final QueryFilters filters;
  final GroupBy groupBy;
  final Aggregate aggregate;

  /// True when buckets on this dimension can overlap, so their sum exceeds the
  /// true total. Exposed as one predicate rather than left to callers to
  /// rediscover with a type check -- a chart that forgets is a chart that lies.
  bool get isTagDimension =>
      groupBy is GroupByTag || groupBy is GroupByTagCrossCategory;

  Map<String, Object?> toJson() => {
        'filters': filters.toJson(),
        'groupBy': groupBy.toJson(),
        'aggregate': aggregate.name,
      };

  static Aggregate _aggregateOf(Object? raw) {
    for (final value in Aggregate.values) {
      if (value.name == raw) return value;
    }
    throw FormatException('unknown aggregate "$raw"');
  }

  @override
  bool operator ==(Object other) =>
      other is QuerySpec &&
      other.filters == filters &&
      other.groupBy == groupBy &&
      other.aggregate == aggregate;

  @override
  int get hashCode => Object.hash(filters, groupBy, aggregate);

  @override
  String toString() => 'QuerySpec($groupBy, ${aggregate.name})';
}
