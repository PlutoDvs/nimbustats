import 'package:nimbus_domain/nimbus_domain.dart';

/// A [GoalAmount] as the pair of nullable columns the goal tables store it
/// in: minor units for money, a double for a quantity. Two columns, so money
/// is never a double. Exactly one is set.
typedef AmountColumns = ({int? minor, double? quantity});

AmountColumns amountToColumns(GoalAmount amount) => switch (amount) {
      MoneyAmount(:final money) => (minor: money.minorUnits, quantity: null),
      QuantityAmount(:final value) => (minor: null, quantity: value),
    };

/// The inverse of [amountToColumns]. Both set, or neither, is malformed and
/// throws rather than picking one; [what] names the columns for the message.
GoalAmount amountFromColumns(int? minor, double? quantity, String what) =>
    switch ((minor, quantity)) {
      (final int m, null) => MoneyAmount(Money(m)),
      (null, final double q) => QuantityAmount(q),
      _ => throw FormatException(
          'exactly one of the $what columns must be set, got $minor and '
          '$quantity'),
    };
