import 'package:meta/meta.dart';

import '../calendar/calendar.dart';

/// The dimension a query buckets its rows along.
///
/// Sealed rather than an enum because two cases carry parameters. An enum
/// would push a depth and a period onto `QuerySpec` as parallel nullable
/// fields that can contradict the chosen dimension.
@immutable
sealed class GroupBy {
  const GroupBy();

  factory GroupBy.fromJson(Map<String, Object?> json) => switch (json['kind']) {
        'none' => const GroupByNone(),
        'category' => GroupByCategory(_depthOf(json['depth'])),
        'tag' => const GroupByTag(),
        'period' => GroupByPeriod(_periodOf(json['period'])),
        'paymentMethod' => const GroupByPaymentMethod(),
        'merchant' => const GroupByMerchant(),
        'reflection' => const GroupByReflection(),
        'hourOfDay' => const GroupByHourOfDay(),
        'dayOfWeek' => const GroupByDayOfWeek(),
        'tagCrossCategory' =>
          GroupByTagCrossCategory(_depthOf(json['depth'])),
        final other => throw FormatException('unknown group-by kind "$other"'),
      };

  /// Stable discriminator, also used as the JSON tag.
  String get kind;

  Map<String, Object?> toJson() => {'kind': kind};

  static int _depthOf(Object? raw) => raw is int
      ? raw
      : throw FormatException('category group-by needs an int depth, got '
          '"$raw"');

  static PeriodType _periodOf(Object? raw) {
    for (final period in PeriodType.values) {
      if (period.name == raw) return period;
    }
    throw FormatException('unknown period type "$raw"');
  }
}

/// One bucket holding everything the filters matched.
final class GroupByNone extends GroupBy {
  const GroupByNone();
  @override
  String get kind => 'none';
  @override
  bool operator ==(Object other) => other is GroupByNone;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByNone()';
}

/// Category, rolled up to [depth] in the materialized path.
///
/// Depth 0 is a root category; deeper values split further. A transaction
/// whose category is shallower than [depth] buckets at its own depth.
final class GroupByCategory extends GroupBy {
  GroupByCategory(this.depth) {
    if (depth < 0) {
      throw ArgumentError.value(depth, 'depth', 'must not be negative');
    }
  }

  final int depth;

  @override
  String get kind => 'category';
  @override
  Map<String, Object?> toJson() => {'kind': kind, 'depth': depth};
  @override
  bool operator ==(Object other) =>
      other is GroupByCategory && other.depth == depth;
  @override
  int get hashCode => Object.hash(kind, depth);
  @override
  String toString() => 'GroupByCategory($depth)';
}

/// Tag. **Buckets on this dimension do not sum to the total** -- a transaction
/// with two tags lands in two buckets. See `AnalyticsResult.trueTotal`.
final class GroupByTag extends GroupBy {
  const GroupByTag();
  @override
  String get kind => 'tag';
  @override
  bool operator ==(Object other) => other is GroupByTag;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByTag()';
}

/// Calendar period. Boundaries are computed in the active calendar by
/// [PeriodBoundaries], never by SQL date functions.
final class GroupByPeriod extends GroupBy {
  const GroupByPeriod(this.period);

  final PeriodType period;

  @override
  String get kind => 'period';
  @override
  Map<String, Object?> toJson() => {'kind': kind, 'period': period.name};
  @override
  bool operator ==(Object other) =>
      other is GroupByPeriod && other.period == period;
  @override
  int get hashCode => Object.hash(kind, period);
  @override
  String toString() => 'GroupByPeriod(${period.name})';
}

final class GroupByPaymentMethod extends GroupBy {
  const GroupByPaymentMethod();
  @override
  String get kind => 'paymentMethod';
  @override
  bool operator ==(Object other) => other is GroupByPaymentMethod;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByPaymentMethod()';
}

final class GroupByMerchant extends GroupBy {
  const GroupByMerchant();
  @override
  String get kind => 'merchant';
  @override
  bool operator ==(Object other) => other is GroupByMerchant;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByMerchant()';
}

/// Necessity x satisfaction, the reflection matrix.
final class GroupByReflection extends GroupBy {
  const GroupByReflection();
  @override
  String get kind => 'reflection';
  @override
  bool operator ==(Object other) => other is GroupByReflection;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByReflection()';
}

final class GroupByHourOfDay extends GroupBy {
  const GroupByHourOfDay();
  @override
  String get kind => 'hourOfDay';
  @override
  bool operator ==(Object other) => other is GroupByHourOfDay;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByHourOfDay()';
}

final class GroupByDayOfWeek extends GroupBy {
  const GroupByDayOfWeek();
  @override
  String get kind => 'dayOfWeek';
  @override
  bool operator ==(Object other) => other is GroupByDayOfWeek;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByDayOfWeek()';
}

/// Tag x category: one bucket per pair, with the category rolled up to
/// [depth].
///
/// A concrete pair rather than a generic cross-product of any two dimensions,
/// following [GroupByReflection], which is likewise two axes in one key rather
/// than a mechanism. Nothing in the app asks to cross arbitrary dimensions,
/// and a generic version would have to reject the combinations that make no
/// sense -- a period crossed with itself, a cross-tab of a cross-tab -- for a
/// generality no caller wants.
///
/// **Buckets on this dimension overlap**, because one axis is tags: a
/// transaction tagged twice appears in two rows of the matrix. `QuerySpec`
/// reports this through `isTagDimension`, and a transaction with no tags at
/// all appears in no cell -- which is why the cells cannot be reconciled with
/// the total by arithmetic and the UI has to say so.
final class GroupByTagCrossCategory extends GroupBy {
  GroupByTagCrossCategory(this.depth) {
    if (depth < 0) {
      throw ArgumentError.value(depth, 'depth', 'must not be negative');
    }
  }

  /// Depth of the category axis, with the same meaning as in
  /// [GroupByCategory].
  final int depth;

  @override
  String get kind => 'tagCrossCategory';
  @override
  Map<String, Object?> toJson() => {'kind': kind, 'depth': depth};
  @override
  bool operator ==(Object other) =>
      other is GroupByTagCrossCategory && other.depth == depth;
  @override
  int get hashCode => Object.hash(kind, depth);
  @override
  String toString() => 'GroupByTagCrossCategory($depth)';
}
