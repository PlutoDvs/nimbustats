import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../support/test_database.dart';
import '../../trackers/support/tracker_rows.dart';

/// A database holding what every goals test starts from, written through the
/// DAOs the app uses, so a goal reads rows shaped like a user's.
///
/// - Categories: food > dining; rent; salary (income).
/// - Tags: trip, work.
/// - Trackers: cig (counter), water (quantity, 0.25 per tap).
final class GoalFixture {
  GoalFixture._(this.db, this.engine);

  static Future<GoalFixture> open() async {
    final db = openTestDatabase();
    final categories = db.categoriesDao;
    await categories.insertNode(id: 'food', name: 'Food', parentId: null);
    await categories.insertNode(id: 'dining', name: 'Dining', parentId: 'food');
    await categories.insertNode(id: 'rent', name: 'Rent', parentId: null);
    await categories.insertNode(
        id: 'salary', name: 'Salary', parentId: null, kind: 'income');
    await db.tagsDao.insertNode(id: 'trip', name: 'trip', parentId: null);
    await db.tagsDao.insertNode(id: 'work', name: 'work', parentId: null);
    await db.trackersDao.insertAll([
      newTracker('cig', TrackerType.counter),
      newTracker('water', TrackerType.quantity, unit: 'L', perTapValue: 0.25),
    ]);
    // The engine's calendar only shapes its own period grouping. Goals hand
    // it plain day ranges and group by day, so no answer here depends on it.
    return GoalFixture._(
        db, AnalyticsEngine(db, calendar: const GregorianCalendar()));
  }

  final AppDatabase db;
  final AnalyticsEngine engine;
  late final EngineGoalMeasurer measurer = EngineGoalMeasurer(db, engine);
  var _next = 0;

  /// An expense on [on]; dining unless told otherwise. Returns its id.
  Future<String> expense(
    int amount,
    DateKey on, {
    String category = 'dining',
    List<String> tags = const [],
    bool confirmed = true,
  }) =>
      _transaction(TxDirection.expense, amount, on, category, tags, confirmed);

  /// An income on [on]; salary unless told otherwise. Returns its id.
  Future<String> income(int amount, DateKey on, {String category = 'salary'}) =>
      _transaction(TxDirection.income, amount, on, category, const [], true);

  /// One tracker entry on [on]. Returns its id.
  Future<String> log(String trackerId, DateKey on, {double value = 1}) async {
    final id = 'entry-${_next++}';
    final logged = await db.trackerEntriesDao.insertEntry(newEntry(id, trackerId,
        value: value, day: on, at: _nineUtc(on)));
    if (logged is! EntryLogged) {
      throw StateError('the fixture entry $id was refused: $logged');
    }
    return id;
  }

  Future<String> _transaction(TxDirection direction, int amount, DateKey on,
      String category, List<String> tags, bool confirmed) async {
    final id = 'tx-${_next++}';
    await db.transactionsDao.insertTransaction(
      id: id,
      direction: direction,
      amount: Money(amount),
      currencyCode: 'IRT',
      occurredAtUtc: _nineUtc(on).millisecondsSinceEpoch,
      localDateKey: on,
      categoryId: category,
      source: TxSource.manual,
      isConfirmed: confirmed,
    );
    if (tags.isNotEmpty) await db.transactionsDao.setTags(id, tags);
    return id;
  }

  /// Goals read only the day key; the instant just has to be on that day.
  static DateTime _nineUtc(DateKey on) =>
      DateTime.utc(on.year, on.month, on.day, 9);
}

/// A money cap on the dining subtree's expenses: monthly from 1 January
/// 2026, 10 000 minor units, alerts at 80 and 100 percent.
Goal moneyGoal({
  String id = 'dining',
  int target = 10000,
  GoalDirection direction = GoalDirection.atMost,
  GoalPeriod period = const RecurringPeriod(PeriodType.month, DateKey(20260101)),
  CalendarKind calendar = CalendarKind.gregorian,
  int weekStart = DateTime.saturday,
  bool active = true,
}) =>
    Goal(
      id: id,
      name: 'Dining out',
      metric: GoalMetric.moneySum,
      scope: MoneyScope(const QueryFilters(
          direction: MoneyDirection.expense,
          categorySubtreePaths: ['/food/dining/'])),
      direction: direction,
      target: MoneyAmount(Money(target)),
      period: period,
      calendar: calendar,
      weekStart: weekStart,
      active: active,
    );

/// A goal over one tracker: by default at most 5 entries a day.
Goal trackerGoal(
  String trackerId, {
  String? id,
  GoalMetric metric = GoalMetric.trackerCount,
  GoalDirection direction = GoalDirection.atMost,
  double target = 5,
  GoalPeriod period = const RecurringPeriod(PeriodType.day, DateKey(20260101)),
  int weekStart = DateTime.saturday,
}) =>
    Goal(
      id: id ?? trackerId,
      name: trackerId,
      metric: metric,
      scope: TrackerScope(trackerId),
      direction: direction,
      target: QuantityAmount(target),
      period: period,
      calendar: CalendarKind.gregorian,
      weekStart: weekStart,
    );

/// Net savings over every transaction in [range], at least [target].
Goal netSavingsGoal(DateRange range,
        {String id = 'savings', int target = 100000}) =>
    Goal(
      id: id,
      name: 'Savings',
      metric: GoalMetric.netSavings,
      scope: MoneyScope(const QueryFilters()),
      direction: GoalDirection.atLeast,
      target: MoneyAmount(Money(target)),
      period: FixedRangePeriod(range),
      calendar: CalendarKind.jalali,
      weekStart: DateTime.saturday,
    );

/// Stamps every row the money watermark reads as written at epoch ms 1.
///
/// The next real write, stamped with the wall clock, is then certain to
/// move the watermark. Without this, a write in the same millisecond as the
/// fixture's own would not move it, and a test would flake.
Future<void> ageMoneyRows(AppDatabase db) async {
  for (final table in const ['transactions', 'categories', 'tags']) {
    await db.customStatement('UPDATE $table SET updated_at = 1');
  }
}

/// [ageMoneyRows] for tracker entries.
Future<void> ageTrackerEntries(AppDatabase db) =>
    db.customStatement('UPDATE tracker_entries SET updated_at = 1');
