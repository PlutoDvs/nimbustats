import 'package:drift/drift.dart';

import '../database/columns.dart';

/// One goal: aggregate a metric over a period and compare it with a target
/// in a direction (goals design §1). The four goal kinds the editor offers
/// are not stored -- they are field values, so storage never branches on one.
///
/// The row class is named explicitly: drift would otherwise generate one
/// called `Goal`, which is the domain value type the DAO returns.
///
/// [metric], [direction], [period] and [calendar] are plain text, parsed by
/// the DAO, not `textEnum`. A `textEnum` converter throws while drift maps a
/// row -- inside the select -- so one row holding an unknown name would fail
/// the whole goal list, where the design shows that one row as unreadable
/// (§1, "Malformed rows"). The SQL is the same TEXT either way.
///
/// No index: a user has a handful of goals, and every read takes them all.
@DataClassName('GoalRow')
class Goals extends Table with BaseColumns {
  /// Non-blank. The editor suggests one from the scope.
  TextColumn get name => text()();

  /// A `GoalMetric` name: `moneySum`, `txnCount`, `trackerSum`,
  /// `trackerCount` or `netSavings`.
  TextColumn get metric => text()();

  /// A `GoalScope` as JSON: `{"type":"money","filters":{...}}` or
  /// `{"type":"tracker","trackerId":"..."}`. Filters rather than a whole
  /// query: the metric and the period decide grouping, aggregate and dates.
  TextColumn get scopeJson => text()();

  /// A `GoalDirection` name: `atMost` or `atLeast`.
  TextColumn get direction => text()();

  /// The target in minor units, for `moneySum` and `netSavings`; null
  /// otherwise. Exactly one of this and [targetQuantity] is set: two columns,
  /// so money is never stored as a double.
  IntColumn get targetMinor => integer().nullable()();

  /// The target for `txnCount`, `trackerSum` and `trackerCount`; null
  /// otherwise.
  RealColumn get targetQuantity => real().nullable()();

  /// A `PeriodType` name, or `fixedRange`.
  TextColumn get period => text()();

  /// A `CalendarKind` name: the goal's own calendar, copied from settings
  /// when it is created, so switching the app's calendar never moves it.
  TextColumn get calendar => text()();

  /// The first day of a week, 1 (Monday) to 7 (Sunday), copied from settings
  /// when the goal is created, for the same reason as [calendar].
  IntColumn get weekStart => integer()();

  /// A `DateKey`. Recurring: history starts with the period containing it.
  /// Fixed range: its first day.
  IntColumn get startDate => integer()();

  /// A `DateKey`: a fixed range's last day. Null for a recurring goal.
  IntColumn get endDate => integer().nullable()();

  /// A JSON list of whole percents, ascending: `[80,100]`.
  TextColumn get alertPercents =>
      text().withDefault(const Constant('[80,100]'))();

  /// False is paused: not evaluated, and no alerts.
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}
