/// What a goal measures.
///
/// The `name` strings are stored in `goals.metric`. Do not rename a value.
enum GoalMetric {
  /// The sum of matching transactions' amounts.
  moneySum,

  /// How many transactions match.
  txnCount,

  /// The sum of one tracker's entry values.
  trackerSum,

  /// How many entries one tracker has.
  trackerCount,

  /// Income minus expense over matching transactions. May be negative.
  netSavings;

  /// The target and the measured value are `MoneyAmount`s.
  bool get isMoney => this == moneySum || this == netSavings;

  /// The scope is a `TrackerScope`. Every other metric reads transactions.
  bool get isTrackerMetric => this == trackerSum || this == trackerCount;
}
