import 'package:drift/drift.dart';

import '../database/columns.dart';
import '../database/converters.dart';
import 'goals_table.dart';

/// One period of one goal: a cached value, and the period's alert state.
///
/// Two kinds of column share the row and are never written together.
/// [currentMinor] / [currentQuantity] with [sourceWatermark] are a cache:
/// rebuilt whenever the watermark moves, and dropping every row loses
/// nothing but time. [lastAlertedPercent] is not a cache: it is what stops a
/// crossing from alerting twice, so a cache rewrite never touches it.
///
/// `idx_goal_period_results_period` is UNIQUE: one row per goal per period.
/// It is also the conflict target of every write to this table.
@DataClassName('GoalPeriodResultRow')
@TableIndex(
    name: 'idx_goal_period_results_period',
    columns: {#goalId, #periodStart},
    unique: true)
class GoalPeriodResults extends Table with BaseColumns {
  TextColumn get goalId => text().references(Goals, #id)();

  /// The period's first day, in the goal's own calendar when it was written.
  IntColumn get periodStart => integer().map(const DateKeyConverter())();

  /// The period's last day.
  IntColumn get periodEnd => integer().map(const DateKeyConverter())();

  /// The cached value in minor units, for a money goal; null until computed.
  IntColumn get currentMinor => integer().nullable()();

  /// The cached value for a quantity goal; null until computed.
  RealColumn get currentQuantity => real().nullable()();

  /// The watermark the value was computed at. Null means stale.
  IntColumn get sourceWatermark => integer().nullable()();

  /// The highest alert percent already announced for this period; null
  /// below every threshold.
  IntColumn get lastAlertedPercent => integer().nullable()();
}
