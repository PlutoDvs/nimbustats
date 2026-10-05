import 'package:meta/meta.dart';

import '../calendar/date_key.dart';
import '../money/money.dart';
import 'reflection_levels.dart';

/// What a bucket is keyed on. One case per group-by dimension.
@immutable
sealed class BucketKey {
  const BucketKey();
}

/// The single bucket produced when nothing is grouped.
final class TotalKey extends BucketKey {
  const TotalKey();
  @override
  bool operator ==(Object other) => other is TotalKey;
  @override
  int get hashCode => 'total'.hashCode;
  @override
  String toString() => 'TotalKey()';
}

final class CategoryKey extends BucketKey {
  const CategoryKey(this.categoryId, this.path);
  final String categoryId;
  final String path;
  @override
  bool operator ==(Object other) =>
      other is CategoryKey &&
      other.categoryId == categoryId &&
      other.path == path;
  @override
  int get hashCode => Object.hash(categoryId, path);
  @override
  String toString() => 'CategoryKey($categoryId)';
}

final class TagKey extends BucketKey {
  const TagKey(this.tagId, this.path);
  final String tagId;
  final String path;
  @override
  bool operator ==(Object other) =>
      other is TagKey && other.tagId == tagId && other.path == path;
  @override
  int get hashCode => Object.hash(tagId, path);
  @override
  String toString() => 'TagKey($tagId)';
}

final class PeriodKey extends BucketKey {
  const PeriodKey(this.range);
  final DateRange range;
  @override
  bool operator ==(Object other) => other is PeriodKey && other.range == range;
  @override
  int get hashCode => range.hashCode;
  @override
  String toString() => 'PeriodKey($range)';
}

/// `null` means the transaction carried no payment method -- a real bucket.
final class PaymentMethodKey extends BucketKey {
  const PaymentMethodKey(this.paymentMethodId);
  final String? paymentMethodId;
  @override
  bool operator ==(Object other) =>
      other is PaymentMethodKey && other.paymentMethodId == paymentMethodId;
  @override
  int get hashCode => paymentMethodId.hashCode;
  @override
  String toString() => 'PaymentMethodKey($paymentMethodId)';
}

/// `null` means the transaction named no merchant -- still worth counting.
final class MerchantKey extends BucketKey {
  const MerchantKey(this.merchant);
  final String? merchant;
  @override
  bool operator ==(Object other) =>
      other is MerchantKey && other.merchant == merchant;
  @override
  int get hashCode => merchant.hashCode;
  @override
  String toString() => 'MerchantKey($merchant)';
}

/// A cell of the necessity x satisfaction matrix. Either axis may be unset,
/// because Phase 1 deliberately keeps both off the add-expense path.
final class ReflectionKey extends BucketKey {
  const ReflectionKey({required this.necessity, required this.satisfaction});
  final NecessityLevel? necessity;
  final SatisfactionLevel? satisfaction;
  @override
  bool operator ==(Object other) =>
      other is ReflectionKey &&
      other.necessity == necessity &&
      other.satisfaction == satisfaction;
  @override
  int get hashCode => Object.hash(necessity, satisfaction);
  @override
  String toString() => 'ReflectionKey($necessity, $satisfaction)';
}

final class HourOfDayKey extends BucketKey {
  HourOfDayKey(this.hour) {
    if (hour < 0 || hour > 23) {
      throw ArgumentError.value(hour, 'hour', 'must be 0..23');
    }
  }
  final int hour;
  @override
  bool operator ==(Object other) => other is HourOfDayKey && other.hour == hour;
  @override
  int get hashCode => hour.hashCode;
  @override
  String toString() => 'HourOfDayKey($hour)';
}

/// ISO weekday: `DateTime.monday` (1) through `DateTime.sunday` (7).
final class DayOfWeekKey extends BucketKey {
  DayOfWeekKey(this.weekday) {
    if (weekday < DateTime.monday || weekday > DateTime.sunday) {
      throw ArgumentError.value(weekday, 'weekday', 'must be 1..7');
    }
  }
  final int weekday;
  @override
  bool operator ==(Object other) =>
      other is DayOfWeekKey && other.weekday == weekday;
  @override
  int get hashCode => weekday.hashCode;
  @override
  String toString() => 'DayOfWeekKey($weekday)';
}

/// One cell of a tag x category matrix.
final class TagCategoryKey extends BucketKey {
  const TagCategoryKey({
    required this.tagId,
    required this.tagPath,
    required this.categoryId,
    required this.categoryPath,
  });

  final String tagId;
  final String tagPath;
  final String categoryId;
  final String categoryPath;

  @override
  bool operator ==(Object other) =>
      other is TagCategoryKey &&
      other.tagId == tagId &&
      other.tagPath == tagPath &&
      other.categoryId == categoryId &&
      other.categoryPath == categoryPath;
  @override
  int get hashCode => Object.hash(tagId, tagPath, categoryId, categoryPath);
  @override
  String toString() => 'TagCategoryKey($tagId, $categoryId)';
}

/// One tracker's bucket, when a tracker query groups by tracker.
///
/// Here rather than beside the tracker types because a sealed class's
/// subclasses must share its library. Phase 3's screens match keys with
/// `case` patterns, not exhaustive switches, so a new key changes nothing
/// for them.
final class TrackerKey extends BucketKey {
  const TrackerKey(this.trackerId);
  final String trackerId;
  @override
  bool operator ==(Object other) =>
      other is TrackerKey && other.trackerId == trackerId;
  @override
  int get hashCode => trackerId.hashCode;
  @override
  String toString() => 'TrackerKey($trackerId)';
}

/// One row of an answer.
@immutable
final class Bucket {
  const Bucket({required this.key, required this.money, required this.count});

  final BucketKey key;

  /// The monetary result of the aggregate. `Money.zero` when the aggregate is
  /// `Aggregate.count`, where [count] is the answer.
  final Money money;

  /// How many transactions fell in this bucket. Always populated, because
  /// every chart wants "n = 12" beside a total and computing it separately
  /// would mean a second query over the same rows.
  final int count;

  @override
  String toString() => 'Bucket($key, $money, n=$count)';
}

/// The answer to one `QuerySpec`.
///
/// [trueTotal] is required rather than optional because for tag dimensions the
/// buckets overlap and their sum exceeds it. A caller that never receives the
/// true total cannot know it should have disclosed the difference, and the
/// resulting pie chart is a quiet lie.
@immutable
final class AnalyticsResult {
  const AnalyticsResult({
    required this.buckets,
    required this.trueTotal,
    required this.trueCount,
    required this.bucketsMayOverlap,
  });

  final List<Bucket> buckets;

  /// The total across the matched rows, counting each transaction once.
  final Money trueTotal;

  /// The number of matched transactions, counting each once.
  final int trueCount;

  /// True when one transaction can land in more than one bucket.
  final bool bucketsMayOverlap;

  Money get bucketSum => Money.sum(buckets.map((b) => b.money));

  /// Whether this result's buckets can be presented as parts of a whole.
  /// When true, the UI must say the slices do not sum to the total.
  bool get overlaps => bucketsMayOverlap;

  @override
  String toString() =>
      'AnalyticsResult(${buckets.length} buckets, total $trueTotal)';
}
