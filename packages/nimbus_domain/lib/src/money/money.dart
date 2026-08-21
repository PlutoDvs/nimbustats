import 'package:meta/meta.dart';

/// An exact monetary amount in a currency's smallest unit.
///
/// Money is never a `double`. Floating point cannot represent decimal
/// fractions exactly, and rounding drift in a ledger is not recoverable.
@immutable
final class Money implements Comparable<Money> {
  const Money(this.minorUnits);

  final int minorUnits;

  static const zero = Money(0);

  static Money sum(Iterable<Money> values) {
    var total = 0;
    for (final v in values) {
      total += v.minorUnits;
    }
    return Money(total);
  }

  Money operator +(Money other) => Money(minorUnits + other.minorUnits);
  Money operator -(Money other) => Money(minorUnits - other.minorUnits);
  Money operator *(int factor) => Money(minorUnits * factor);
  Money operator -() => Money(-minorUnits);

  bool get isZero => minorUnits == 0;
  bool get isNegative => minorUnits < 0;
  Money abs() => Money(minorUnits.abs());

  @override
  int compareTo(Money other) => minorUnits.compareTo(other.minorUnits);

  @override
  bool operator ==(Object other) =>
      other is Money && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;

  @override
  String toString() => 'Money($minorUnits)';
}
