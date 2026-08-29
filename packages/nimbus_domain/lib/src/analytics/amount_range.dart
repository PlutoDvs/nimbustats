import 'package:meta/meta.dart';

import '../money/money.dart';

/// An inclusive amount filter. Either end may be absent.
@immutable
final class AmountRange {
  AmountRange({this.minInclusive, this.maxInclusive}) {
    final min = minInclusive;
    final max = maxInclusive;
    // Money defines compareTo but not the comparison operators, so this is
    // spelled out rather than written as `min > max`.
    if (min != null && max != null && min.compareTo(max) > 0) {
      // A range that can never match is a caller bug. Returning nothing
      // would be indistinguishable from "no data in this period".
      throw ArgumentError('AmountRange minInclusive ($min) exceeds '
          'maxInclusive ($max)');
    }
  }

  factory AmountRange.fromJson(Map<String, Object?> json) => AmountRange(
        minInclusive: _moneyOf(json['minInclusive']),
        maxInclusive: _moneyOf(json['maxInclusive']),
      );

  final Money? minInclusive;
  final Money? maxInclusive;

  bool get isUnbounded => minInclusive == null && maxInclusive == null;

  bool contains(Money value) {
    final min = minInclusive;
    final max = maxInclusive;
    if (min != null && value.compareTo(min) < 0) return false;
    if (max != null && value.compareTo(max) > 0) return false;
    return true;
  }

  Map<String, Object?> toJson() => {
        if (minInclusive != null) 'minInclusive': minInclusive!.minorUnits,
        if (maxInclusive != null) 'maxInclusive': maxInclusive!.minorUnits,
      };

  static Money? _moneyOf(Object? value) => switch (value) {
        null => null,
        final int minorUnits => Money(minorUnits),
        _ => throw FormatException('amount bound must be an int, got "$value"'),
      };

  @override
  bool operator ==(Object other) =>
      other is AmountRange &&
      other.minInclusive == minInclusive &&
      other.maxInclusive == maxInclusive;

  @override
  int get hashCode => Object.hash(minInclusive, maxInclusive);

  @override
  String toString() => 'AmountRange($minInclusive..$maxInclusive)';
}
