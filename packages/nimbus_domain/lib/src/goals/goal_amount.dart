import 'package:meta/meta.dart';

import '../money/money.dart';

/// A goal's target or measured value: money, or a quantity.
///
/// Money stays `Money` -- exact minor units -- and is never converted to a
/// double. Every member taking another amount throws [ArgumentError] when the
/// two are different subtypes: rials plus cigarettes is a bug to surface, not
/// a number to report.
@immutable
sealed class GoalAmount implements Comparable<GoalAmount> {
  const GoalAmount();

  bool get isZero;
  bool get isNegative;

  /// The same subtype's zero.
  GoalAmount get zero;

  GoalAmount operator +(GoalAmount other);
  GoalAmount operator -(GoalAmount other);

  @override
  int compareTo(GoalAmount other);

  /// This amount as a fraction of [target]. A ratio, so a double even for
  /// money. A zero target never divides: 0 while this is zero or below,
  /// [double.infinity] once it is anything more.
  double ratioTo(GoalAmount target);

  /// Whether this amount is at least [percent]% of [target]. Money compares
  /// exactly, `minor * 100 >= target.minor * percent`, so 7 999 of 10 000 is
  /// not 80%. A zero target is reached by anything above zero.
  bool reaches(GoalAmount target, int percent);

  /// Whether this amount is over [target]. Uses the same tolerance as
  /// [reaches], so a value that reaches 100% is never also over it. A zero
  /// target is exceeded by anything above zero.
  bool exceeds(GoalAmount target);

  /// This amount x [numerator] / [denominator]. Money stays integer, rounded
  /// half away from zero. Throws [ArgumentError] unless [denominator] is
  /// positive.
  GoalAmount scaledBy(int numerator, int denominator);

  /// This amount split into [parts] equal shares. Money rounds up (the
  /// ceiling): it is a minimum to set aside, and rounding down would leave the
  /// target short. Throws [ArgumentError] unless [parts] is positive.
  GoalAmount dividedUp(int parts);
}

/// Tracker values are typed decimals summed in binary (0.29 * 100 is 28.999...,
/// 0.7 + 0.1 + 0.2 is 0.9999999999999999). A relative tolerance far below any
/// loggable difference keeps an exact threshold a crossing without admitting a
/// value that is really short of it. The one definition, shared by [reaches]
/// and [exceeds].
const _relativeTolerance = 1e-9;

/// A money target or value, in exact minor units.
final class MoneyAmount extends GoalAmount {
  const MoneyAmount(this.money);

  final Money money;

  @override
  bool get isZero => money.isZero;

  @override
  bool get isNegative => money.isNegative;

  @override
  MoneyAmount get zero => const MoneyAmount(Money.zero);

  @override
  MoneyAmount operator +(GoalAmount other) =>
      MoneyAmount(money + _moneyOf(other));

  @override
  MoneyAmount operator -(GoalAmount other) =>
      MoneyAmount(money - _moneyOf(other));

  @override
  int compareTo(GoalAmount other) => money.compareTo(_moneyOf(other));

  @override
  double ratioTo(GoalAmount target) {
    final of = _moneyOf(target).minorUnits;
    if (of == 0) return _ratioToZero(money.minorUnits > 0);
    return money.minorUnits / of;
  }

  @override
  bool reaches(GoalAmount target, int percent) {
    final of = _moneyOf(target).minorUnits;
    if (of == 0) return money.minorUnits > 0;
    return money.minorUnits * 100 >= of * percent;
  }

  @override
  bool exceeds(GoalAmount target) => compareTo(target) > 0;

  @override
  MoneyAmount scaledBy(int numerator, int denominator) {
    _checkPositive(denominator, 'denominator');
    // shortcut: a plain 64-bit product, which wraps past ~2.5e16 minor units over a year-long range (~2.5e15 over a decade); move to BigInt if a goal can hold amounts that large.
    final scaled = money.minorUnits * numerator;
    final quotient = scaled ~/ denominator; // truncates toward zero
    final remainder = scaled.remainder(denominator); // takes scaled's sign
    return MoneyAmount(Money(remainder.abs() * 2 >= denominator
        ? quotient + scaled.sign
        : quotient));
  }

  @override
  MoneyAmount dividedUp(int parts) {
    _checkPositive(parts, 'parts');
    final minor = money.minorUnits;
    // ~/ truncates toward zero, which is already the ceiling below zero.
    final quotient = minor ~/ parts;
    return MoneyAmount(Money(
        minor > 0 && minor.remainder(parts) != 0 ? quotient + 1 : quotient));
  }

  @override
  bool operator ==(Object other) =>
      other is MoneyAmount && other.money == money;

  @override
  int get hashCode => Object.hash('money', money);

  @override
  String toString() => 'MoneyAmount(${money.minorUnits})';
}

/// A count or a tracker quantity: cigarettes, litres, minutes.
final class QuantityAmount extends GoalAmount {
  const QuantityAmount(this.value);

  final double value;

  @override
  bool get isZero => value == 0;

  @override
  bool get isNegative => value < 0;

  @override
  QuantityAmount get zero => const QuantityAmount(0);

  @override
  QuantityAmount operator +(GoalAmount other) =>
      QuantityAmount(value + _valueOf(other));

  @override
  QuantityAmount operator -(GoalAmount other) =>
      QuantityAmount(value - _valueOf(other));

  @override
  int compareTo(GoalAmount other) => value.compareTo(_valueOf(other));

  @override
  double ratioTo(GoalAmount target) {
    final of = _valueOf(target);
    if (of == 0) return _ratioToZero(value > 0);
    return value / of;
  }

  @override
  bool reaches(GoalAmount target, int percent) {
    final of = _valueOf(target);
    if (of == 0) return value > 0;
    final needed = of * percent;
    return value * 100 >= needed - needed.abs() * _relativeTolerance;
  }

  @override
  bool exceeds(GoalAmount target) {
    final of = _valueOf(target);
    return value > of + of.abs() * _relativeTolerance;
  }

  @override
  QuantityAmount scaledBy(int numerator, int denominator) {
    _checkPositive(denominator, 'denominator');
    return QuantityAmount(value * numerator / denominator);
  }

  @override
  QuantityAmount dividedUp(int parts) {
    _checkPositive(parts, 'parts');
    return QuantityAmount(value / parts);
  }

  @override
  bool operator ==(Object other) =>
      other is QuantityAmount && other.value == value;

  @override
  int get hashCode => Object.hash('quantity', value);

  @override
  String toString() => 'QuantityAmount($value)';
}

Money _moneyOf(GoalAmount other) => switch (other) {
      MoneyAmount(:final money) => money,
      QuantityAmount() => throw ArgumentError.value(
          other, 'other', 'money cannot be combined with a quantity'),
    };

double _valueOf(GoalAmount other) => switch (other) {
      QuantityAmount(:final value) => value,
      MoneyAmount() => throw ArgumentError.value(
          other, 'other', 'a quantity cannot be combined with money'),
    };

double _ratioToZero(bool above) => above ? double.infinity : 0;

void _checkPositive(int value, String name) {
  if (value <= 0) throw ArgumentError.value(value, name, 'must be positive');
}
