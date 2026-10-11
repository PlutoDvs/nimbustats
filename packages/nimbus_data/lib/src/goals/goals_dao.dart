import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../database/app_database.dart';
import 'goal_amount_columns.dart';

/// One stored goal, readable or not.
///
/// Sealed so the Goals tab has to say what it draws for a row it cannot
/// read. Rows parse one at a time for exactly this: one corrupt row must
/// never blank the list (goals design §1, the treatment saved views give a
/// corrupt row).
sealed class GoalRead {
  const GoalRead();

  String get id;
}

final class GoalReadable extends GoalRead {
  const GoalReadable(this.goal);

  final Goal goal;

  @override
  String get id => goal.id;

  @override
  String toString() => 'GoalReadable(${goal.id})';
}

/// A row that does not parse into a [Goal].
///
/// Carries the error instead of a substitute goal. A default target or
/// period under the user's own name looks as if it worked, which is worse
/// than an honest "cannot read this". Its card offers Delete.
final class GoalUnreadable extends GoalRead {
  const GoalUnreadable(this.id, this.name, this.error);

  @override
  final String id;
  final String name;
  final FormatException error;

  @override
  String toString() => 'GoalUnreadable($id, $error)';
}

/// The `goals` table, as [Goal] values.
///
/// Ids come from the caller (`Ids.newId()`), so the editor can name a goal
/// before it is saved. Every write stamps `updated_at` with the wall clock,
/// as every other DAO here does.
final class GoalsDao {
  GoalsDao(this._db);

  final AppDatabase _db;

  /// Live goals, active and paused, oldest first. Ids are UUIDv7, so id
  /// order is creation order.
  Stream<List<GoalRead>> watchAll() => (_db.select(_db.goals)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .watch()
      .map((rows) => rows.map(_parse).toList());

  /// One live goal, or null when there is none.
  Future<GoalRead?> byId(String id) async {
    final row = await (_db.select(_db.goals)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .getSingleOrNull();
    return row == null ? null : _parse(row);
  }

  /// The live row's `updated_at`, or null when the row is missing or deleted.
  Future<int?> stampOf(String id) async {
    final row = await (_db.select(_db.goals)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .getSingleOrNull();
    return row?.updatedAt;
  }

  /// Inserts [goal], or rewrites every field of the row with its id.
  /// `created_at` is written once, on insert.
  Future<void> upsert(Goal goal) async {
    final now = _now();
    final target = amountToColumns(goal.target);
    final values = GoalsCompanion(
      name: Value(goal.name),
      metric: Value(goal.metric.name),
      scopeJson: Value(jsonEncode(goal.scope.toJson())),
      direction: Value(goal.direction.name),
      targetMinor: Value(target.minor),
      targetQuantity: Value(target.quantity),
      period: Value(goal.period.storedName),
      calendar: Value(goal.calendar.name),
      weekStart: Value(goal.weekStart),
      startDate: Value(goal.period.startDate.value),
      endDate: Value(goal.period.endDate?.value),
      alertPercents: Value(Goal.alertPercentsToJson(goal.alertPercents)),
      active: Value(goal.active),
      updatedAt: Value(now),
    );
    await _db.into(_db.goals).insert(
          values.copyWith(id: Value(goal.id), createdAt: Value(now)),
          onConflict: DoUpdate((_) => values),
        );
  }

  Future<void> setActive(String id, bool active) => _write(
      id, GoalsCompanion(active: Value(active), updatedAt: Value(_now())));

  Future<void> softDelete(String id) {
    final now = _now();
    return _write(
        id, GoalsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }

  Future<void> restore(String id) => _write(
      id,
      GoalsCompanion(
          deletedAt: const Value(null), updatedAt: Value(_now())));

  Future<void> _write(String id, GoalsCompanion values) async {
    final written =
        await (_db.update(_db.goals)..where((t) => t.id.equals(id)))
            .write(values);
    // A write that matched nothing is a caller holding a stale id. Saying so
    // beats reporting success for a pause that paused nothing.
    if (written != 1) throw StateError('no goal "$id"');
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  /// Parses one stored row. Nothing defaults (goals design §1).
  ///
  /// Only what malformed stored data can throw becomes a [GoalUnreadable]:
  /// - [FormatException] from the parsers;
  /// - [TypeError] from a JSON value of the wrong type meeting a cast;
  /// - [ArgumentError] from [Goal] rejecting a combination.
  ///
  /// The last two are wrapped in a [FormatException], which is what the
  /// card reports. Anything else is a bug here and surfaces as one -- the
  /// rule `SavedViewsDao` follows.
  static GoalRead _parse(GoalRow row) {
    try {
      final scope = jsonDecode(row.scopeJson);
      if (scope is! Map<String, Object?>) {
        throw FormatException('scope is not a JSON object', row.scopeJson);
      }
      return GoalReadable(Goal(
        id: row.id,
        name: row.name,
        metric: _named(GoalMetric.values, row.metric, 'metric'),
        scope: GoalScope.fromJson(scope),
        direction: _named(GoalDirection.values, row.direction, 'direction'),
        target: amountFromColumns(row.targetMinor, row.targetQuantity, 'target'),
        period: GoalPeriod.fromStored(row.period, row.startDate, row.endDate),
        calendar: _named(CalendarKind.values, row.calendar, 'calendar'),
        weekStart: row.weekStart,
        alertPercents: Goal.alertPercentsFromJson(row.alertPercents),
        active: row.active,
      ));
    } on FormatException catch (error) {
      return GoalUnreadable(row.id, row.name, error);
    } on TypeError catch (error) {
      return GoalUnreadable(row.id, row.name, FormatException('$error'));
    } on ArgumentError catch (error) {
      return GoalUnreadable(row.id, row.name, FormatException('$error'));
    }
  }

  /// Throws rather than guessing: a guessed metric or direction would show
  /// a goal the user never made.
  static T _named<T extends Enum>(List<T> values, String raw, String field) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw FormatException('unknown $field "$raw"');
  }
}
