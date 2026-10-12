# Phase 5 — Goals & limits — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One goal engine covering a spending cap, a habit limit, a habit goal and a savings target, with threshold alerts fired once per crossing, a self-healing per-period cache for streaks and history, and the Goals tab, editor and detail screens.

**Architecture:**
- **Pure domain core** in `nimbus_domain/lib/src/goals/`: value types, `GoalPeriods`, `assess`, `foldDaily`, `GoalStreaks`, `crossing`, the `GoalMeasurer` port and `GoalEngine`.
- **Data layer** in `nimbus_data/lib/src/goals/`: `EngineGoalMeasurer` over Phase 3's `AnalyticsEngine` (the only switch on the metric), `GoalsDao`, `GoalPeriodResultsDao` and `GoalService` (cache, re-baseline, alert recording).
- **App** in `app/lib/features/goals/`: providers, `GoalWatcher` (the `Stream<GoalAlert>` Phase 6 consumes), the Goals tab, editor, detail and the shell's alert snackbar.

**Tech Stack:** Flutter 3.47.1 / Dart 3.13.1, Riverpod 3.4.2, drift 2.34.3 (+ drift_dev 2.34.5), sqlite3 3.5.2, intl 0.20.3, uuid (as locked).

**Spec:** `docs/superpowers/specs/2026-10-10-goals-5-design.md`. Read it first; this plan argues from it. The brief is `docs/phases/phase-5-goals.md`; the conventions are `docs/phases/CONVENTIONS.md`.

## Global Constraints

**Toolchain and scope**
- Flutter 3.47.1 / Dart 3.13.1, `pubspec.lock` committed. No SDK or dependency changes.
- **Schema.** Phase 5 owns v40–v49. This plan takes **v40** (Task 1), landing alone on `main` (CONVENTIONS §2).
- **Owns:**
  - `packages/nimbus_domain/lib/src/goals/**`
  - `packages/nimbus_data/lib/src/tables/{goals,goal_period_results}_table.dart`
  - `packages/nimbus_data/lib/src/goals/**` (added to CONVENTIONS §3 in Task 1)
  - `app/lib/features/goals/**`
- **Must not touch** `analytics/`, `trackers/`, `capture/` in any package. Importing their public types read-only is allowed (`AnalyticsEngine`, `QuerySpec`, `TrackerQuerySpec`, `trackerClockProvider`, `AmountField`, the tag picker sheet).
- **Touches to other owners' files.** Each task names them and its commit message says so (CONVENTIONS §3):
  - Phase 0's `app_database.dart`, `database_test.dart`, `migration_test.dart` (Task 1, Task 8);
  - Phase 0's `test/architecture_test.dart` (Task 6);
  - the shell `app/lib/bootstrap/app_shell.dart` and router `app_router.dart` (Tasks 11, 14);
  - the shared ARBs and barrels;
  - `CONVENTIONS.md`, `DEFERRED.md`, the screen contract, the brief, `docs/phases/README.md`.

**Data rules**
- **Money is never `double`.** `MoneyAmount` wraps `Money` (`int minorUnits`); `QuantityAmount` wraps `double`. A ratio (`fractionOfTarget`) is a `double` — a ratio is not money.
- Every query filters `deleted_at IS NULL`, through `AnalyticsPredicates.notDeleted` (the engine) or the DAO's own `isNull` on `deletedAt` (goal tables).
- **Calendar math stays out of SQL.** Period ranges come only from `PeriodBoundaries` (through `GoalPeriods`). History groups by **day** and folds in Dart.
- **No defaults on stored data.** A malformed `goals` row raises `FormatException`; the list shows it as an unreadable card.

**Strings**
- Every user-facing string goes in **both** `app/lib/l10n/app_en.arb` and `app_fa.arb`, keys prefixed `goals`, in alphabetical position. The Persian value never equals the English one (`app/test/localization_test.dart`).
- ARB files are **CRLF** on disk, sorted case-insensitively, literal (unescaped) characters. Add keys only through the scratchpad `arb_add.py` defined in Task 11 Step 1, never by hand. Regenerate with `cd app && flutter gen-l10n`; generated files are committed.
- **No displayed `int` placeholders.** Numbers reach a string already formatted (`MoneyFormatter`, `Digits`) as a `String`. A plural takes an extra `int count` that only selects the branch.

**UI rules**
- **No confirmation dialogs** (`app/test/ux_rules_test.dart`). Deletes are undoable snackbars. No spinner on any save.
- **Package boundaries.** Presentation code never touches a DAO; `app` never imports `drift` or `sqlite3`.
- **No raw `Color(0x…)`** in `app/lib`.
- **Lints:** `unawaited_futures` is an error; `dart analyze --fatal-infos` clean.
- **Digits follow settings.** The default settings locale is `fa`, so numbers render in Persian digits even when a widget test pumps `locale: Locale('en')`. A test asserting Latin digits calls `useEnglishDigits(db)` first.
- **Accessibility.** Tap targets ≥ `NimbusTokens.minTapTarget` (48). Status is text + icon, never colour alone. Every progress bar has a semantics label. Dynamic type tested at `textScaleFactorTestValue = 2.0`.

**File editing**
- Edit files with the Write/Edit tools, or Python scripts written to the scratchpad. **Never** Bash heredocs or `printf` for content containing backslashes (Git Bash collapses `\\`).

### Commit routine (every task)

1. **Branch.** Task 1: `git switch main && git switch -c feat/schema-v40`. Every other task: `git switch phase/5-goals && git switch -c <branch named in the task>`.
2. **Write the task's tests and run them.** Confirm they fail **for the stated reason**. A compile error counts only when it names the missing symbol.
3. **Tag the parent:** `git tag pre-<slug>` (slug = branch name after the `/`), while nothing of the task is committed. Tags stay local.
4. **Implement.** Run the task's tests until green.
5. **Run the full gate from the repo root, all green.**
   - Baseline (Phase 4 gate, `7d3097e`): architecture 5, `nimbus_domain` 328, `nimbus_data` 246, `nimbus_design` 36, `app` 527. Each task's last step gives the expected new counts as "baseline + N".
   - Commands:
     ```bash
     dart analyze --fatal-infos
     dart test test/architecture_test.dart
     (cd packages/nimbus_domain && dart test)
     (cd packages/nimbus_data && dart test)
     (cd packages/nimbus_design && flutter test --no-pub)
     (cd app && flutter test --no-pub --concurrency=4)
     ```
   - `--no-pub`: pub.dev may 403 on the current VPN exit. `--concurrency=4`: the full app suite hangs at default concurrency (project memory).
   - When running one test file, give `flutter test` an **absolute** path.
   - A first run after edits occasionally fails while "loading" a file. Re-run once before treating it as real.
6. **Commit** with the message given. The body ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
7. **Merge.** Task 1: as the task says. Every other task: `git switch phase/5-goals && git merge --ff-only <branch>`. Nothing is pushed until the operator asks.

## Review Focus

The input classes the spec implies but no spec-listed test exercises, most likely first. Each has a pinning test in the task named.

1. **A category moved under another parent after a goal names it.** `QueryFilters.categorySubtreePaths` stores materialized paths (`/rootId/childId/`). After a move the stored path matches nothing, and a spending cap silently reads zero for ever. The measurer re-resolves each stored path by its last id segment (the category's own id) to the category's current path before querying; tag paths likewise. Pinned in Task 7.
2. **The calendar switched in Settings while the app is open.** `analyticsEngineProvider` rebuilds on a calendar change; goals must keep their own calendar, and the watcher's re-subscription must not re-fire an alert already recorded. Pinned in Task 10.
3. **Midnight with the app open.** A daily limit's period moves to the new day. Yesterday's `last_alerted_percent` belongs to yesterday's row, so the first crossing today alerts. Pinned in Task 5 (domain, a new period starts from null) and Task 10 (watcher re-evaluates on the day change).
4. **A crossing caused from a pushed screen** (the add-expense screen, a tracker detail). The alert must show exactly once, after the save's own snackbar, on whatever screen is visible. Pinned in Task 14.
5. **A goal over an archived tracker vs a deleted one.** Archived: measured and shown normally (archiving is not deletion). Deleted: an error card with Edit and Delete, never a crash or a silent zero. Pinned in Task 11.

## Decisions taken in this plan (beyond the design)

Each is a small, reasoned change to the spec, named so a reviewer can reject it explicitly.

1. **Names.** The spec's `Recurring` / `FixedRange` become `RecurringPeriod` / `FixedRangePeriod` (generic names in a shared barrel). The spec's data-layer `GoalHistory` becomes `GoalService`, which also owns save, re-baseline and alert recording — they share one transaction boundary.
2. **`crossing` takes the `Goal`** (`crossing(Goal goal, GoalProgress progress, int? lastAlerted)`): it needs the goal's id, name, direction and alert percents, and four loose parameters invite mixing two goals' values.
3. **Stored paths are re-resolved by leaf id** (Review Focus 1). This is the measurer's job, not the scope's: the stored JSON stays Phase 3's lossless `QueryFilters`.
4. **No `updated_at` index on `transactions`.** The money watermark is read once per history load (the tab and the detail), never per frame or per tap — the watcher evaluates the current period live and reads no watermark. Task 8 measures the `MAX` on 50 000 seeded rows and records the number in its commit message; the index is added only if it exceeds 5 ms on the host.
5. **Tag edits need no extra watermark term.** Verified 2026-10-10: `TransactionRepository` writes tags through `_attachTags` on the same save path that rewrites the transaction row (`updateTransaction` stamps `updated_at`). `TransactionsDao.deleteTransaction` (a hard delete) has no caller in `app/` or `packages/*/lib`; tracker entries are only soft-deleted. The watermark carries a `shortcut:` comment naming both limits (hard delete; clock set back).
6. **`GoalKind` lives in the app** (`app/lib/features/goals/application/goal_kind.dart`). Nothing in `nimbus_domain` or `nimbus_data` can name a kind, which is what makes the brief's grep criterion a structural fact. Task 6 adds the grep as a test.
7. **Today for goals** comes from `trackerClockProvider` (imported read-only): one clock for the whole app, already overridable in tests. Task 10 defines `goalTodayProvider` and its own midnight/resume refresh, because the trackers' rollover widget is mounted only on tracker screens.
8. **Restore after delete re-baselines** like create, edit and resume: progress may have moved while the goal was deleted.
9. **The pace line names a date** ("At this pace: 157,500 by 1405/07/30"), not "by the end of <month>": the date is unambiguous in both calendars and in a week or a fixed range, where "month" is wrong. Recorded at the Phase 5 gate.
10. **A card speaks amounts, not a percent** ("Goal test, 85K of 100K, At risk"), not "82% of cap": the amounts carry the percent's facts and read the same for a limit and a goal. The bar still speaks its percent. Recorded at the Phase 5 gate.

## File map

**nimbus_domain** (`packages/nimbus_domain/lib/src/goals/`)

| File | Contents | Task |
|---|---|---|
| `goal_metric.dart` | `GoalMetric` | 2 |
| `goal_direction.dart` | `GoalDirection` | 2 |
| `goal_scope.dart` | `GoalScope`, `MoneyScope`, `TrackerScope` | 2 |
| `goal_amount.dart` | `GoalAmount`, `MoneyAmount`, `QuantityAmount` | 2, extended in 4 |
| `goal_period.dart` | `GoalPeriod`, `RecurringPeriod`, `FixedRangePeriod` | 2 |
| `goal.dart` | `Goal` | 2 |
| `goal_status.dart` | `GoalStatus` | 3 |
| `goal_progress.dart` | `GoalProgress`, `Projection`, `RequiredRate` | 3, extended in 4 |
| `goal_periods.dart` | `GoalPeriods` | 3 |
| `goal_assess.dart` | `assess` | 3, extended in 4 |
| `goal_fold.dart` | `foldDaily` | 5 |
| `goal_streaks.dart` | `PeriodOutcome`, `GoalStreaks` | 5 |
| `goal_alert.dart` | `GoalAlert`, `CrossingResult`, `reachedPercent`, `crossing` | 5 |
| `goal_measurer.dart` | `GoalMeasurer` | 6 |
| `goal_engine.dart` | `GoalEngine` | 6 |
| `../../nimbus_domain.dart` | barrel, one export per file above | 2–6 |

**nimbus_data** (`packages/nimbus_data/`)

| File | Contents | Task |
|---|---|---|
| `lib/src/tables/goals_table.dart` | `Goals` (`GoalRow`) | 1 |
| `lib/src/tables/goal_period_results_table.dart` | `GoalPeriodResults` (`GoalPeriodResultRow`) | 1 |
| `lib/src/database/app_database.dart` (Phase 0) | tables registered, v40 step, two DAO getters | 1, 8 |
| `lib/src/goals/engine_goal_measurer.dart` | `EngineGoalMeasurer` | 7 |
| `lib/src/goals/goals_dao.dart` | `GoalsDao`, `GoalRead` | 8 |
| `lib/src/goals/goal_period_results_dao.dart` | `GoalPeriodResultsDao`, `CachedPeriod` | 8 |
| `lib/src/goals/goal_service.dart` | `GoalService`, `GoalHistoryResult`, `GoalPreview` | 9 |
| `drift_schemas/drift_schema_v40.json`, `test/generated/*` | generated | 1 |
| `lib/nimbus_data.dart` | barrel | 1, 7, 8, 9 |

**app** (`app/lib/features/goals/`)

| Path | Files | Task |
|---|---|---|
| `application/` | `goal_providers.dart`, `goal_watcher.dart` | 10 |
| `application/` | `goal_kind.dart`, `goal_format.dart` | 11 |
| `application/` | `goal_editor_controller.dart` | 12 |
| `presentation/` | `goals_screen.dart`, `widgets/goal_card.dart` | 11 |
| `presentation/` | `goal_editor_screen.dart`, `widgets/goal_kind_tiles.dart`, `widgets/goal_preview.dart` | 12 |
| `presentation/` | `goal_detail_screen.dart`, `widgets/goal_history_list.dart` | 13 |
| `presentation/` | `goal_alert_listener.dart` | 14 |
| `routes.dart` | `goalShellRoutes`, route constants | 11, extended in 12, 13 |

**Tests**

| Path | Files | Task |
|---|---|---|
| `packages/nimbus_domain/test/goals/` | `goal_values_test.dart` | 2 |
| `packages/nimbus_domain/test/goals/` | `goal_periods_test.dart`, `goal_assess_test.dart` | 3, 4 |
| `packages/nimbus_domain/test/goals/` | `goal_fold_test.dart`, `goal_streaks_test.dart`, `goal_alert_test.dart` | 5 |
| `packages/nimbus_domain/test/goals/` | `goal_engine_test.dart`, `support/fake_measurer.dart` | 6 |
| `test/` (root) | `architecture_test.dart` | 6 |
| `packages/nimbus_data/test/` | `migration_test.dart`, `database_test.dart` | 1 |
| `packages/nimbus_data/test/goals/` | `support/goal_fixture.dart`, `engine_goal_measurer_test.dart` | 7 |
| `packages/nimbus_data/test/goals/` | `goals_dao_test.dart`, `goal_period_results_dao_test.dart`, `watermark_test.dart` | 8 |
| `packages/nimbus_data/test/goals/` | `goal_service_test.dart`, `goal_cache_drop_test.dart` | 9 |
| `app/test/features/goals/` | `support/goal_test_app.dart`, `goal_watcher_test.dart` | 10 |
| `app/test/features/goals/` | `goals_screen_test.dart`, `goal_format_test.dart`, `goal_kind_test.dart` | 11 |
| `app/test/features/goals/` | `goal_editor_screen_test.dart` | 12 |
| `app/test/features/goals/` | `goal_detail_screen_test.dart` | 13 |
| `app/test/features/goals/` | `goal_alert_listener_test.dart` | 14 |

## Interface contract

Every task uses these names and signatures **exactly**. A task's implementer sees only their task; this section is how the tasks agree. All domain types are `@immutable` with value equality (`==`, `hashCode`) and a `toString`.

### Domain (`package:nimbus_domain/nimbus_domain.dart`)

```dart
enum GoalMetric {
  moneySum, txnCount, trackerSum, trackerCount, netSavings;
  bool get isMoney => this == moneySum || this == netSavings;     // target is MoneyAmount
  bool get isTrackerMetric => this == trackerSum || this == trackerCount; // scope is TrackerScope
}

enum GoalDirection { atMost, atLeast }

sealed class GoalScope {
  const GoalScope();
  /// {"type":"money","filters":{...}} | {"type":"tracker","trackerId":"..."}.
  /// Throws FormatException on an unknown type, a missing field, or filters with a dateRange.
  factory GoalScope.fromJson(Map<String, Object?> json);
  Map<String, Object?> toJson();
}
final class MoneyScope extends GoalScope {
  MoneyScope(this.filters); // ArgumentError if filters.dateRange != null
  final QueryFilters filters;
}
final class TrackerScope extends GoalScope {
  TrackerScope(this.trackerId); // ArgumentError if trackerId is empty
  final String trackerId;
}

sealed class GoalAmount implements Comparable<GoalAmount> {
  const GoalAmount();
  bool get isZero;
  bool get isNegative;
  GoalAmount get zero;                         // the same subtype's zero
  GoalAmount operator +(GoalAmount other);     // ArgumentError on mixed subtypes (every binary member)
  GoalAmount operator -(GoalAmount other);
  int compareTo(GoalAmount other);
  /// current / target as a ratio. Zero target: 0 when this <= 0, else double.infinity.
  double ratioTo(GoalAmount target);
  /// Exact: money `minor * 100 >= target.minor * percent`; quantity `value * 100 >= target * percent`.
  /// Zero target: true iff this > 0.
  bool reaches(GoalAmount target, int percent);
  /// this * numerator / denominator. Money: integer, rounded half away from zero. (Task 4)
  GoalAmount scaledBy(int numerator, int denominator);
  /// this / parts. Money: rounded up (ceiling). (Task 4)
  GoalAmount dividedUp(int parts);
}
final class MoneyAmount extends GoalAmount { const MoneyAmount(this.money); final Money money; }
final class QuantityAmount extends GoalAmount { const QuantityAmount(this.value); final double value; }

sealed class GoalPeriod {
  const GoalPeriod();
  /// FormatException on an unknown name, a missing or stray endDate, end < start.
  factory GoalPeriod.fromStored(String period, int startDate, int? endDate);
  String get storedName;   // a PeriodType name, or 'fixedRange'
  DateKey get startDate;
  DateKey? get endDate;
}
final class RecurringPeriod extends GoalPeriod {
  const RecurringPeriod(this.type, this.since);
  final PeriodType type;
  final DateKey since;     // history starts with the period containing it
}
final class FixedRangePeriod extends GoalPeriod {
  FixedRangePeriod(this.range); // ArgumentError if range.endInclusive < range.startInclusive
  final DateRange range;
}

final class Goal {
  /// ArgumentError (spec §2): scope type vs metric; target type vs metric;
  /// netSavings with a direction filter; negative target; zero target on atLeast;
  /// alertPercents empty/unsorted/duplicated/outside 1..100; weekStart outside 1..7; blank name.
  Goal({
    required this.id,
    required this.name,
    required this.metric,
    required this.scope,
    required this.direction,
    required this.target,
    required this.period,
    required this.calendar,      // CalendarKind
    required this.weekStart,     // 1..7, DateTime.monday..DateTime.sunday
    List<int> alertPercents = defaultAlertPercents,
    this.active = true,
  });
  static const defaultAlertPercents = <int>[80, 100];
  final String id, name;
  final GoalMetric metric;
  final GoalScope scope;
  final GoalDirection direction;
  final GoalAmount target;
  final GoalPeriod period;
  final CalendarKind calendar;
  final int weekStart;
  final List<int> alertPercents;   // unmodifiable
  final bool active;
  Goal copyWith({String? name, GoalMetric? metric, GoalScope? scope, GoalDirection? direction,
      GoalAmount? target, GoalPeriod? period, CalendarKind? calendar, int? weekStart,
      List<int>? alertPercents, bool? active});
  /// FormatException on anything that is not a JSON list of ints.
  static List<int> alertPercentsFromJson(String raw);
  static String alertPercentsToJson(List<int> percents);
}

enum GoalStatus { notStarted, onTrack, atRisk, exceeded, met, missed }

final class RequiredRate { const RequiredRate(this.perMonth, this.monthsLeft); final GoalAmount perMonth; final int monthsLeft; }
final class Projection { const Projection({required this.projectedEnd, this.requiredRate}); final GoalAmount projectedEnd; final RequiredRate? requiredRate; }
final class GoalProgress {
  const GoalProgress({required this.period, required this.current, required this.target,
      required this.status, required this.fractionOfTarget, required this.projection});
  final DateRange period;
  final GoalAmount current, target;
  final GoalStatus status;
  final double fractionOfTarget;
  final Projection projection;
}

abstract final class GoalPeriods {
  static AppCalendar calendarFor(CalendarKind kind);
  /// Recurring: PeriodBoundaries.forPeriod(type, today, calendar, firstDayOfWeek: goal.weekStart).
  /// Fixed range: its range.
  static DateRange current(Goal goal, DateKey today);
  /// Recurring: closed periods from the one containing `since` up to (excluding) the current one,
  /// oldest first; empty when since > today. Fixed range: always empty.
  static List<DateRange> closed(Goal goal, DateKey today);
}

/// Pure. Spec §2 "assess". (Task 3: status; Task 4: projection.)
GoalProgress assess(Goal goal, DateRange period, GoalAmount current, DateKey today);

/// One amount per period, in order; days with no entry contribute zero (`zero` gives the subtype).
List<GoalAmount> foldDaily(Map<DateKey, GoalAmount> daily, List<DateRange> periods, GoalAmount zero);

final class PeriodOutcome { const PeriodOutcome(this.period, this.value, this.status); final DateRange period; final GoalAmount value; final GoalStatus status; }
final class GoalStreaks {
  const GoalStreaks({required this.current, required this.best});
  /// outcomes oldest first, closed periods only. current = trailing run of `met`.
  factory GoalStreaks.of(List<PeriodOutcome> outcomes);
  final int current, best;
  static const none = GoalStreaks(current: 0, best: 0);
}

final class GoalAlert {
  const GoalAlert({required this.goalId, required this.goalName, required this.period,
      required this.percent, required this.direction, required this.progress});
  final String goalId, goalName;
  final DateRange period;
  final int percent;
  final GoalDirection direction;
  final GoalProgress progress;
}
final class CrossingResult { const CrossingResult(this.alert, this.lastAlerted); final GoalAlert? alert; final int? lastAlerted; }
/// The highest of goal.alertPercents that progress.current reaches against goal.target, or null.
int? reachedPercent(Goal goal, GoalAmount current);
/// Spec §2 "Crossing".
CrossingResult crossing(Goal goal, GoalProgress progress, int? lastAlerted);

abstract interface class GoalMeasurer {
  Future<GoalAmount> measure(GoalMetric metric, GoalScope scope, DateRange range);
  /// Days with no data are absent from the map.
  Future<Map<DateKey, GoalAmount>> measureDaily(GoalMetric metric, GoalScope scope, DateRange span);
}

final class GoalEngine {
  GoalEngine(this.measurer, {required DateKey Function() today});
  final GoalMeasurer measurer;
  DateKey today();
  Future<GoalProgress> evaluate(Goal goal, DateRange period);   // measure, then assess
  Future<GoalProgress> evaluateCurrent(Goal goal);              // evaluate(goal, GoalPeriods.current(goal, today()))
}
```

### Data (`package:nimbus_data/nimbus_data.dart`)

```dart
// Tables: Goals (@DataClassName('GoalRow')), GoalPeriodResults (@DataClassName('GoalPeriodResultRow')).
// AppDatabase gains: late final GoalsDao goalsDao; late final GoalPeriodResultsDao goalPeriodResultsDao;

final class EngineGoalMeasurer implements GoalMeasurer {
  EngineGoalMeasurer(AppDatabase db, AnalyticsEngine engine);   // db: to re-resolve stored paths by leaf id
}

sealed class GoalRead { const GoalRead(); String get id; }
final class GoalReadable extends GoalRead { const GoalReadable(this.goal); final Goal goal; }
final class GoalUnreadable extends GoalRead { const GoalUnreadable(this.id, this.name, this.error); final String id; final String name; final FormatException error; }

final class GoalsDao {
  GoalsDao(AppDatabase db);
  Stream<List<GoalRead>> watchAll();     // live rows (deleted_at IS NULL), oldest first (by id)
  Future<GoalRead?> byId(String id);
  Future<void> upsert(Goal goal);        // insert or update by id; stamps created_at/updated_at
  Future<void> setActive(String id, bool active);
  Future<void> softDelete(String id);
  Future<void> restore(String id);
}

final class CachedPeriod {
  const CachedPeriod({required this.period, required this.value, required this.watermark, this.lastAlerted});
  final DateRange period;
  final GoalAmount? value;    // null when never computed
  final int? watermark;       // null = stale
  final int? lastAlerted;
}

final class GoalPeriodResultsDao {
  GoalPeriodResultsDao(AppDatabase db);
  Future<List<CachedPeriod>> forGoal(String goalId);                 // ordered by period_start
  /// Upsert by (goalId, period.start); writes value + watermark only, never last_alerted_percent.
  Future<void> writeValues(String goalId, List<({DateRange period, GoalAmount value})> rows, int watermark);
  Future<void> deleteForGoal(String goalId);
  /// One transaction: read last_alerted_percent for progress.period, run `crossing`, write the new
  /// state (upserting the row), return the alert.
  Future<GoalAlert?> recordCrossing(Goal goal, GoalProgress progress);
  /// Writes last_alerted_percent = reachedPercent(goal, progress.current) for progress.period. No alert.
  Future<void> setBaseline(Goal goal, GoalProgress progress);
  /// shortcut: wall-clock stamps and hard deletes do not move it (spec §3).
  Future<int> moneyWatermark();
  Future<int> trackerWatermark(String trackerId);
}

final class GoalHistoryResult { const GoalHistoryResult(this.outcomes, this.streaks); final List<PeriodOutcome> outcomes; final GoalStreaks streaks; }
final class GoalPreview { const GoalPreview(this.recent, this.current); final List<PeriodOutcome> recent; final GoalProgress current; }

final class GoalService {
  GoalService(AppDatabase db, GoalEngine engine);
  GoalEngine get engine;
  /// Closed periods, oldest first, served from cache where the watermark matches (spec §3).
  Future<GoalHistoryResult> history(Goal goal);
  /// Evaluates the current period and records a crossing. Paused goals: returns null, writes nothing.
  Future<GoalAlert?> check(Goal goal);
  /// Upsert + deleteForGoal + evaluateCurrent + setBaseline, in one transaction (spec §4.3).
  Future<void> save(Goal goal);
  /// Resume re-baselines; pause writes only the flag.
  Future<void> setActive(Goal goal, bool active);
  Future<void> delete(String id);
  /// Restores and re-baselines.
  Future<void> restore(String id);
  /// The draft's last [periods] closed periods and its current progress. No cache, no writes.
  Future<GoalPreview> preview(Goal draft, {int periods = 3});
}
```

### App (`app/lib/features/goals/`)

```dart
// application/goal_providers.dart
final goalTodayProvider;          // NotifierProvider<GoalToday, DateKey>, from trackerClockProvider; refresh()
final goalServiceProvider;        // Provider<GoalService>, watches appDatabaseProvider + analyticsEngineProvider
final goalsProvider;              // StreamProvider<List<GoalRead>>
final goalProgressProvider;       // FutureProvider.autoDispose.family<GoalProgress, Goal>, re-run on engine changes + goalTodayProvider
final goalHistoryProvider;        // FutureProvider.autoDispose.family<GoalHistoryResult, Goal>
// application/goal_watcher.dart
final class GoalWatcher { Stream<GoalAlert> get alerts; void start(); Future<void> dispose(); }
final goalWatcherProvider;        // Provider<GoalWatcher>; started by GoalAlertListener
// application/goal_kind.dart
enum GoalKind { spendingCap, habitLimit, habitGoal, savingsTarget }
GoalKind kindOf(Goal goal);
// routes.dart
const goalsRoute = '/goals';
String goalDetailRoute(String id);   // '/goals/$id'
const newGoalRoute = '/goals/new';
String editGoalRoute(String id);     // '/goals/$id/edit'
final goalShellRoutes = <RouteBase>[...];
```

## Tasks

| # | Task | Branch | Writer |
|---|---|---|---|
| 1 | Schema v40 (the lock, on `main`) | `feat/schema-v40` | data |
| 2 | Goal value types and validation | `feat/goal-values` | domain |
| 3 | `GoalPeriods` and `assess` status, both directions | `feat/goal-assess` | domain |
| 4 | Projection and fixed-range run-rate | `feat/goal-projection` | domain |
| 5 | `foldDaily`, `GoalStreaks`, `crossing` | `feat/goal-crossing` | domain |
| 6 | `GoalMeasurer`, `GoalEngine`, the kind-free grep test | `feat/goal-engine` | domain |
| 7 | `EngineGoalMeasurer` | `feat/goal-measurer` | data |
| 8 | Goal DAOs and watermarks | `feat/goal-daos` | data |
| 9 | `GoalService`: cache, re-baseline, cache-drop test | `feat/goal-service` | data |
| 10 | Providers and `GoalWatcher` | `feat/goal-watcher` | app |
| 11 | Goals tab | `feat/goals-tab` | app |
| 12 | Goal editor | `feat/goal-editor` | app |
| 13 | Goal detail | `feat/goal-detail` | app |
| 14 | Alert snackbar | `feat/goal-alerts-ui` | app |
| 15 | Docs, device check, gate | `docs/phase-5-complete` | app |

After Task 1 merges to `main`: `git switch main && git switch -c phase/5-goals`.

---

## Contract notes from the task parts

The three groups of tasks were drafted in parallel against the interface contract above. Where a note below refines a signature, **the note wins**, and every task is written to it.

### Domain (Tasks 2–6)

Every domain code block was compiled, analyzed (`dart analyze --fatal-infos`) and run, task by task, in an isolated copy of `nimbus_domain` at `7c40f41`; the RED messages and counts are the ones observed. Note 9 was added at assembly and not run there.

Deviations from, or additions to, the Interface contract. Each is small; a reviewer can reject any one.

1. **`GoalEngine(this.measurer, {required this._today})`.** The contract's `{required DateKey Function() today}` + `: _today = today` fails `dart analyze --fatal-infos` (`prefer_initializing_formals`). A private named initializing formal (Dart 3.13; already used in `app/lib/features/settings/application/demo_data_seeder.dart`) keeps the call site exactly as the contract writes it: `GoalEngine(measurer, today: ...)`.
2. **`GoalEngine` and `GoalMeasurer` have no value equality.** They are a service and a port, not values. Every other domain type has `==`, `hashCode` and `toString`.
3. **Covariant returns.** `MoneyAmount`'s `+`, `-`, `zero`, `scaledBy`, `dividedUp` return `MoneyAmount` (`QuantityAmount` likewise), and `FixedRangePeriod.endDate` returns `DateKey`, not `DateKey?`. Narrower than the contract, so every contract call still compiles.
4. **`Goal.alertPercentsFromJson` checks shape only** (a JSON list of ints), as the contract says. Order and range are the constructor's `ArgumentError`. **Task 8's DAO must turn an `ArgumentError` thrown by `Goal(...)` into a `FormatException`** when it parses a row, or a stored `[120]` crashes the list instead of showing an unreadable card.
5. **Rounding of `projectedEnd`:** half **away from zero** (the contract), not the spec's "half up". They differ only for negative net savings (-17.5 → -18, not -17).
6. **`scaledBy`/`dividedUp` tests live in `goal_values_test.dart`** (Task 4), beside the other `GoalAmount` tests; the file map lists that file for Task 2 only.
7. **`GoalPeriods.closed` returns `const <DateRange>[]` when empty** and a fresh list otherwise. Callers must not mutate it.
8. **Behind pace compares ratios as doubles** (`fractionOfTarget < fullDays / daysInPeriod`). Equal rationals round to the same double, so exactly-on-pace is on track (pinned). Money threshold checks (`reaches`) stay integer.
9. **`QuantityAmount.reaches` uses a 1e-9 relative tolerance** (added at assembly, not run by the domain writer): `0.29 * 100` is `28.999…` in binary, so without it 0.29 of a 1-litre goal never reaches 29%. Pinned by `a decimal exactly on a threshold reaches it`; Task 2's count is therefore +28, not +27.

### Data (Tasks 1, 7, 8, 9)


Everything below uses the Interface contract's names and signatures. These are the additions and the places where the data tasks pin down something the contract or the spec left open. Each one is argued where it lands.

1. **No `textEnum` on `goals` (Task 1).** `metric`, `direction`, `calendar` and `period` are plain `text()` columns, parsed by `GoalsDao` into the domain enums. Spec §1 says `textEnum<…>`. Two reasons:
   - `GoalMetric` and `GoalDirection` do not exist on `main` when the schema lock lands; they arrive in Task 2 on the phase branch.
   - More important: drift's `EnumNameConverter.fromSql` is `values.byName(...)`, which throws `ArgumentError` **while drift maps the row, inside the select** (verified in drift 2.34.3, `lib/src/runtime/types/converters.dart`). One row with an unknown name would then fail `watchAll()` for every goal. That is the opposite of §1's "Malformed rows" rule, where that one row becomes an unreadable card.

   The SQL is `TEXT NOT NULL` either way. Only the snapshot's `type_converter` metadata differs, so no migration is lost by this choice.
2. **The v40 step can be re-run, and it runs without a transaction (Task 1).**
   - `m.createTable` already says `IF NOT EXISTS` (drift 2.34.3, `migration.dart:319`). `m.create(index)` does not, so the step drops the index by name before creating it.
   - The existing test "an upgrade killed after the v31 step reopens and finishes" therefore keeps its meaning (user_version stays 31 after the kill), and it now also proves v40's re-run.
   - Writing `PRAGMA user_version = 40` inside a transaction, as v31 does, would leave that test with nothing to re-run.
3. **`deleteForGoal` hard-deletes (Task 8).** The rows are a cache and the alert state beside it, and the re-baseline that follows rebuilds them (spec §4.3). A soft-deleted row would keep its `(goal_id, period_start)` UNIQUE key and collide with the row the re-baseline writes. Every read still filters `deleted_at IS NULL`.
4. **`GoalUnreadable.error` is always a `FormatException` (Task 8).**
   - The DAO catches the three things malformed stored data can throw, as `SavedViewsDao` does: `FormatException`, a `TypeError` from a JSON cast, and an `ArgumentError` from `Goal`'s constructor.
   - It wraps the last two in a `FormatException`, because the contract types the field that way.
   - Anything else rethrows.
5. **Stored paths are re-resolved whatever the node's `deleted_at` (Task 7).** The lookup answers "where is this node now", as `CategoriesDao.byId` does, not "is it live". This is the second deliberate exception to "every query filters `deleted_at IS NULL`", besides the watermark. Whether a deleted node's rows count stays the engine's rule:
   - A soft-deleted category's live expenses still count. `AnalyticsPredicates` matches categories by path alone, and Analytics shows them too.
   - A soft-deleted tag matches nothing, because the engine's tag predicate filters deleted tags.
   - An id with no row at all keeps its stored path, which matches nothing.

   A test pins the category case.
6. **Money `measureDaily` queries in 31-day windows (Task 7).** The engine's day grouping is a CASE ladder with one `BETWEEN` branch per day (`GroupExpressions._periodFragment`). So one query over a span costs rows × days, which is quadratic in history length. Windows cap it at rows × 31, for one extra statement per month. Tracker days use `local_date_key` directly and need no windows.
7. **`GoalService.check` also returns null when the current period is not open (Task 9).** That covers a fixed range not yet begun or already over. Spec §4.1 says "closed periods never alert", and a finished fixed range is closed. The contract's doc names only the paused case.
8. **A paused goal is not evaluated on save (Task 9).** `save`, `restore` and `setActive(…, true)` all re-baseline through one helper. That helper drops the cached rows but skips `evaluateCurrent` + `setBaseline` when `goal.active` is false; resuming re-baselines.
9. **`GoalService.preview`:**
   - The current period comes from `engine.evaluate`.
   - The recent periods come from one `measureDaily` + `foldDaily` over a copy of the draft whose `since` is moved back by `calendar.shiftPeriod(current, type, -periods)`. `GoalPeriods.closed` then yields exactly `periods` periods.
10. **Barrel.** Task 1 adds no export: the tables are not public, and the DAOs are, from Task 8.
11. **Test support** (`packages/nimbus_data/test/goals/support/goal_fixture.dart`):
    - Task 7 creates it, with `GoalFixture`: seeded categories, tags and trackers, plus `expense` / `income` / `log`.
    - Task 8 adds `moneyGoal`, `trackerGoal`, `netSavingsGoal`, `ageMoneyRows` and `ageTrackerEntries`.
    - None of them names a goal kind.

### App (Tasks 10–15)


Additions and changes to the Interface contract made by Tasks 10–15. Everything else is used exactly as the contract states.

1. **`GoalWatcher` gains a constructor and `stop()`:** `GoalWatcher(Ref ref, {Duration debounce = const Duration(milliseconds: 300)})` and `void stop()`.
   - **Why `stop()`:** the debounce `Timer` lives in a provider, which outlives the widget tree. In a widget test, flutter_riverpod's scope cancels the scheduled dispose of every provider when it unmounts (verified in `flutter_riverpod-3.4.2/lib/src/core/provider_scope.dart`, `scheduleDispose`/`dispose`). A provider-owned timer would therefore still be pending when flutter_test checks, and the test would fail with "A Timer is still pending even after the widget tree was disposed". `GoalAlertListener` calls `stop()` from its `dispose`. In the app, the shell never unmounts while the app runs.
   - `dispose()` = `stop()` + closing the stream. Only `goalWatcherProvider`'s `onDispose` calls it.
2. **`goalServiceProvider` also watches `goalTodayProvider`.** The engine's `today` is `() => today`, captured at build. The watcher, the cards and the detail screen then agree on one day, and a midnight refresh rebuilds the service. The closure never touches `ref`, so an old service held across a rebuild cannot throw `UnmountedRefException`.
3. **`goalPreviewProvider`** (Task 12): `FutureProvider.autoDispose.family<GoalPreview, Goal>` in `goal_providers.dart`.
4. **`goalRoutes`** (Task 11, filled in by Tasks 12 and 13): the full-screen editor and detail routes, pushed over the shell like `trackerRoutes`. The router adds `...goalShellRoutes` inside the `ShellRoute` and `...goalRoutes` with the full-screen routes. `'/goals/new'` is declared before `'/goals/:id'`.
5. **`GoalService.preview(draft)` ignores the draft's `since`.** A new goal's `since` is today, so honouring it would leave nothing to preview. Preview returns the `periods` closed periods before the current one, as if the goal had existed then. **Task 9's writer must implement this.** Task 12's preview test pins it.
6. **`GoalService.restore(id)` on a row that reads back as `GoalUnreadable`** restores the row and skips the re-baseline, because there is nothing to evaluate. It must not throw. **Task 9's writer must implement this.** Task 11's unreadable-goal undo test pins it.
7. **ARB key `navGoals`** follows the shell's `nav*` keys (`navHome`, `navTrackers`, …). It is the one key outside the `goals` prefix.
8. **App-only names** (none is visible to `nimbus_domain` or `nimbus_data`):
   - On `GoalKind`: `direction`, `defaultPeriod` and `isHabit`.
   - Top-level: `habitMetricFor(TrackerType)`, `goalStatusText`.
   - `GoalFormat`/`goalFormatProvider`.
   - The editor: `GoalEditorSeed`, `GoalEditorState`, `GoalEditorError`, `goalEditorErrors`, `goalDraft`, `GoalEditorController`/`goalEditorProvider`.
   - Widgets: `GoalCard`, `GoalStatusLine`, `GoalProgressBar`, `GoalKindTiles`, `GoalPreviewPanel`, `GoalOutcomeRow`, `GoalHistoryList`, `GoalAlertListener`.
   - `reportingGoalFailure` and `deleteGoalWithUndo`.
9. **Files beyond the file map:**
   - `app/lib/features/goals/presentation/widgets/goal_write.dart` (Task 11).
   - Phase 1's `app/test/bootstrap/app_shell_navigation_test.dart`, changed in Task 11 because the shell gains a destination.
10. **The goals' midnight/resume rollover is mounted in `GoalAlertListener`** (Task 14), which is always on the shell. Until Task 14 lands, the Goals screens do not roll over at midnight. Nothing ships between those tasks.
11. **Alert wording says "limit" for every `atMost` goal.** A `GoalAlert` does not carry the kind, so the spec's "Dining out: over this month's cap" reads "Dining out: over this month's limit". The period word comes from the goal's `period.storedName`, through an ICU `select`.
12. **Raw `goals` rows in tests.** Task 11's unreadable-row helper inserts a raw `goals` row using spec §1's column names. Check them against Task 1's table (`PRAGMA table_info(goals)` on a test database) before running.

---

### Task 1: Schema v40 — goals and their per-period results (the schema lock)

Branch `feat/schema-v40`, slug `schema-v40`. This task lands on **`main`** alone (CONVENTIONS §2), and `phase/5-goals` is then created from it.

**Files:**
- Create: `packages/nimbus_data/lib/src/tables/goals_table.dart`
- Create: `packages/nimbus_data/lib/src/tables/goal_period_results_table.dart`
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` (Phase 0)
- Generate:
  - `packages/nimbus_data/drift_schemas/drift_schema_v40.json`
  - `packages/nimbus_data/test/generated/schema_v40.dart`
  - `packages/nimbus_data/test/generated/schema.dart`
  - `packages/nimbus_data/lib/src/database/app_database.g.dart`
- Test: `packages/nimbus_data/test/migration_test.dart`, `packages/nimbus_data/test/database_test.dart` (Phase 0)
- Docs: `docs/phases/CONVENTIONS.md`, `docs/phases/DEFERRED.md`

**Interfaces:**
- Consumes: nothing new. `CalendarKind`, `DateKey` and `DateKeyConverter` already exist.
- Produces:
  - Table `goals` (`Goals`, row class `GoalRow`, companion `GoalsCompanion`, database getter `goals`). Columns:
    - `name`, `metric`, `scope_json`, `direction`, `period`, `calendar`: TEXT
    - `target_minor` INTEGER NULL, `target_quantity` REAL NULL
    - `week_start`, `start_date` INTEGER; `end_date` INTEGER NULL
    - `alert_percents` TEXT DEFAULT `'[80,100]'`; `active` BOOL DEFAULT true
    - the `BaseColumns`
  - Table `goal_period_results` (`GoalPeriodResults`, row class `GoalPeriodResultRow`, companion `GoalPeriodResultsCompanion`, getter `goalPeriodResults`). Columns:
    - `goal_id` TEXT REFERENCES `goals(id)`
    - `period_start`, `period_end` INTEGER, mapped by `DateKeyConverter`
    - `current_minor` INTEGER NULL, `current_quantity` REAL NULL, `source_watermark` INTEGER NULL, `last_alerted_percent` INTEGER NULL
    - the `BaseColumns`
  - Index `idx_goal_period_results_period` UNIQUE ON `goal_period_results (goal_id, period_start)`, with generated getter `idxGoalPeriodResultsPeriod`.
  - `AppDatabase.schemaVersion == 40`.

- [ ] **Step 1: Branch**

```bash
git switch main
git switch -c feat/schema-v40
```

- [ ] **Step 2: Write the failing tests**

In `packages/nimbus_data/test/database_test.dart`, replace the test `'opens at schema version 32'` with:

```dart
  test('opens at schema version 40', () async {
    // Phase 3 took v20 and v21, Phase 4 v30 to v32, Phase 5 v40. Ranges are
    // reserved per phase, so this number jumps rather than increments; see
    // the registry in CONVENTIONS.md.
    expect(db.schemaVersion, 40);
    await db.customSelect('SELECT 1').get();
  });

  test('a fresh install keeps one cache row per goal period', () async {
    final rows = await db
        .customSelect("SELECT sql FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_goal_period_results_period'")
        .get();
    final sql = rows.single.read<String>('sql');
    expect(sql, startsWith('CREATE UNIQUE INDEX'));
    expect(sql, contains('(goal_id, period_start)'));
  });
```

In `packages/nimbus_data/test/migration_test.dart`:

1. The upgrade loop becomes `for (final from in [1, 20, 21, 30, 31, 32])`, and its name becomes `'a v$from database upgrades to v40 and matches a fresh install'`.
2. Every `migrateAndValidate(db, 32` in the file becomes `migrateAndValidate(db, 40`. There are eight: the loop, the v20 view test, the v1 DAO test, the once-per-day group's `setUp`, the three tests in the v30 group, and the v31 drop test.
3. Leave `expect(schema.rawDatabase.userVersion, 30);` and `expect(schema.rawDatabase.userVersion, 31);` as they are.
4. In the test `'an upgrade killed after the v31 step reopens and finishes'`, replace its leading comment

```dart
      // Killed after every step of onUpgrade has run, before drift writes 32.
      // Two guards make the next start succeed: the v31 step records its own
      // version, or the reopen would add the offset column a second time; and
      // the v32 drop says IF EXISTS, because the index is already gone.
```

with

```dart
      // Killed after every step of onUpgrade has run, before drift writes 40.
      // Three guards make the next start succeed: the v31 step records its
      // own version, or the reopen would add the offset column a second time;
      // the v32 drop says IF EXISTS, because the index is already gone; and
      // the v40 step re-runs harmlessly over the goal tables it already made.
```

   and, directly after the `expect(... 'idx_tracker_entries_day' ..., isEmpty, reason: ...)` call in that test, add:

```dart
      expect(
        schema.rawDatabase.select("SELECT name FROM sqlite_master WHERE name "
            "IN ('goals', 'goal_period_results', "
            "'idx_goal_period_results_period')"),
        hasLength(3),
        reason: 'the re-run meets the goal tables and index already made',
      );
```

5. Append inside `main`, after the v31 drop test:

```dart
  group('an upgraded v32 database keeps goal periods sound', () {
    // The UNIQUE index is the conflict target of every cache write, and the
    // foreign key keeps a period row from outliving its goal. Both are
    // proven on the upgraded path, not only on a fresh install.
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(await verifier.startAt(32));
      await verifier.migrateAndValidate(db, 40);
      await db.customStatement(
        'INSERT INTO goals (id, name, metric, scope_json, direction, '
        'target_minor, period, calendar, week_start, start_date, created_at, '
        'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0)',
        [
          'g', 'Dining out', 'moneySum', '{"type":"money","filters":{}}',
          'atMost', 10000, 'month', 'gregorian', 6, 20260101,
        ],
      );
    });
    tearDown(() => db.close());

    Future<void> period(String id, {String goal = 'g', int start = 20260101}) =>
        db.customStatement(
          'INSERT INTO goal_period_results (id, goal_id, period_start, '
          'period_end, created_at, updated_at) VALUES (?, ?, ?, ?, 0, 0)',
          [id, goal, start, start + 30],
        );

    test('a second row for one goal period is refused', () async {
      await period('first');
      await expectLater(period('second'), throwsA(isA<SqliteException>()));
      await period('next-month', start: 20260201);
    });

    test('a row for no goal is refused', () async {
      await expectLater(
          period('orphan', goal: 'nope'), throwsA(isA<SqliteException>()));
    });
  });
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_data && dart test test/migration_test.dart test/database_test.dart`

Expected:
- FAIL: the version test reads 32.
- FAIL: `a fresh install keeps one cache row per goal period` finds no row (`Bad state: No element`).
- FAIL: every migration test cannot find schema v40 (`MissingSchemaException`).

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-schema-v40
```

- [ ] **Step 5: Write the two tables**

Create `packages/nimbus_data/lib/src/tables/goals_table.dart`:

```dart
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
```

Create `packages/nimbus_data/lib/src/tables/goal_period_results_table.dart`:

```dart
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
```

- [ ] **Step 6: Register the tables and add the v40 step**

In `packages/nimbus_data/lib/src/database/app_database.dart`:

1. After `import '../tables/categories_table.dart';`, add:

```dart
import '../tables/goal_period_results_table.dart';
import '../tables/goals_table.dart';
```

2. In `@DriftDatabase(tables: [...])`, after `TrackerEntries,`, add:

```dart
    Goals,
    GoalPeriodResults,
```

3. Change `int get schemaVersion => 32;` to `int get schemaVersion => 40;`.
4. After the closing brace of the v32 block, `if (from >= 30 && from < 32) { ... }`, still inside `onUpgrade`, add:

```dart
          // v32 -> v40: Phase 5 adds goals and their per-period results. New
          // tables only, so every older version takes this step.
          //
          // Nothing here records v40 before drift does, so every statement
          // must be safe to run twice: createTable says IF NOT EXISTS, and
          // the index -- which m.create does not guard -- is dropped by name
          // first. An upgrade killed after this step but before drift writes
          // the version then reopens cleanly, as the v32 step's IF EXISTS
          // already lets it.
          if (from < 40) {
            await m.createTable(goals);
            await m.createTable(goalPeriodResults);
            // As above, createTable leaves the indexes behind. This one is a
            // correctness rule: the cache's upsert names it as its conflict
            // target, so an upgraded device without it could not store a
            // goal's history at all.
            await customStatement(
                'DROP INDEX IF EXISTS idx_goal_period_results_period');
            await m.create(idxGoalPeriodResultsPeriod);
          }
```

- [ ] **Step 7: Generate code, the snapshot and the test schemas**

```bash
cd packages/nimbus_data
dart run build_runner build --delete-conflicting-outputs
grep -n "late final Index idxGoal" lib/src/database/app_database.g.dart
grep -n "CREATE UNIQUE INDEX idx_goal_period_results_period" lib/src/database/app_database.g.dart
dart run drift_dev schema dump lib/src/database/app_database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated/
```

Expected:
- The first `grep` prints one line, `late final Index idxGoalPeriodResultsPeriod = Index(`. If drift named the getter differently, use the generated name in Step 6 and record the difference in the commit body.
- The second `grep` prints one line. drift wrote the index as UNIQUE.
- `drift_schemas/drift_schema_v40.json` and `test/generated/schema_v40.dart` exist.
- `test/generated/schema.dart` lists `const [1, 20, 21, 30, 31, 32, 40]`.

- [ ] **Step 8: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_data && dart test test/migration_test.dart test/database_test.dart`

Expected: PASS.
- `migration_test.dart` has 17 tests:
  - six upgrade paths;
  - the v20 and v1 tests;
  - the three once-per-day tests;
  - the three v30-group tests;
  - the v31 drop test;
  - the two new v32 tests.
- `database_test.dart` has 11.

**Mutation check.**
1. In the v40 step, delete the `DROP INDEX IF EXISTS idx_goal_period_results_period` statement.
2. Re-run `migration_test.dart`. Expected: "an upgrade killed after the v31 step reopens and finishes" FAILS, on `index idx_goal_period_results_period already exists`.
3. Restore it.

- [ ] **Step 9: Update the registry, ownership and D21**

`docs/phases/CONVENTIONS.md`:
- The registry row:
  - old: `| 5 — Goals | v40–v49 | — | goals, goal_period_results |`
  - new: `| 5 — Goals | v40–v49 | **v40** | goals, goal_period_results |`
- In §3's ownership table, directly after the row ``| `packages/nimbus_data/lib/src/trackers/**` | Phase 4 |``, add:

```markdown
| `packages/nimbus_data/lib/src/goals/**` | Phase 5 |
```

`docs/phases/DEFERRED.md`. These edits follow goals design departure 7: Phase 5 stores a tracker id, never a `TrackerQuerySpec`.
- The summary table row:
  - old: ``| D21 | 4b's test and guard gaps, one of them a Phase 5 prerequisite | Phase 5 storing `TrackerQuerySpec` as JSON (the `fromJson` tests); nothing else | Phase 5 |``
  - new: ``| D21 | 4b's test and guard gaps | Storing a `TrackerQuerySpec` as JSON (the `fromJson` tests), which nothing does yet; nothing else | Next trackers work, or on demand |``
- In the section `## D21 — 4b's test and guard gaps`:
  1. Replace `**Status:** open. Found 2026-10-09 by the Phase 4b final review.` with:

```markdown
**Status:** open. Found 2026-10-09 by the Phase 4b final review. Re-scoped
2026-10-10: Phase 5 stores a tracker goal's tracker id, not a
`TrackerQuerySpec` (goals design, departure 7), so nothing here blocks it.
```

  2. Replace the two lines

```markdown
  `_rangeOf`); the tests are what pin a storage format. **They must land before
  Phase 5 stores specs as JSON.**
```

     with

```markdown
  `_rangeOf`); the tests are what pin a storage format. **They must land before
  anything stores a `TrackerQuerySpec` as JSON.**
```

  3. Replace

```markdown
**Blocks:** Phase 5 storing `TrackerQuerySpec` as JSON (the first item). The
rest block nothing.
```

     with

```markdown
**Blocks:** storing a `TrackerQuerySpec` as JSON (the first item), which
nothing does yet. The rest block nothing.
```

  4. Replace

```markdown
**Unblocked by:** Phase 5, whose prerequisite is the `fromJson` tests.
```

     with

```markdown
**Unblocked by:** the next trackers work, or on demand.
```

- [ ] **Step 10: Run the full gate**

Run the commands in the commit routine. Expected: all green.
- `nimbus_data` is 246 + 4 = **250**. Four tests are new: one database test, the v32 upgrade path, and the two v32 goal-period tests. The rest are re-pointed.
- The other suites are unchanged: architecture 5, `nimbus_domain` 328, `nimbus_design` 36, `app` 527.

- [ ] **Step 11: Commit, merge, and open the phase branch**

```bash
git add packages/nimbus_data docs/phases/CONVENTIONS.md docs/phases/DEFERRED.md
git commit -F - <<'EOF'
feat(schema): v40 -- goals and their per-period results

Phase 5's schema lock, alone on main (CONVENTIONS section 2). Two
tables: goals, one row per goal, and goal_period_results, one row per
goal per period holding a cached value and that period's alert state.

metric, direction, calendar and period are plain TEXT that the DAO
parses, not textEnum. A textEnum converter throws while drift maps a
row, so one unknown name would fail the whole goal list, where the
design shows that one row as unreadable. The SQL is TEXT either way,
and the domain enums do not exist on main yet.

(goal_id, period_start) is UNIQUE, because the cache's upsert names it
as its conflict target. It is created on the upgrade path too, since
createTable does not bring indexes. The step is safe to re-run:
createTable says IF NOT EXISTS, and the index is dropped by name
before it is made. An upgrade killed before drift records v40
therefore reopens cleanly. The existing killed-upgrade test now
proves this.

Touches Phase 0's app_database.dart, database_test.dart and
migration_test.dart. Updates the registry and gives Phase 5
nimbus_data/lib/src/goals/. Re-scopes D21: Phase 5 stores a tracker
id, not a TrackerQuerySpec, so D21 no longer blocks it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch main
git merge --ff-only feat/schema-v40
git switch -c phase/5-goals
```

---

### Task 2: Goal value types and validation

Branch `feat/goal-values`, slug `goal-values`.

**Files:**
- Create: `packages/nimbus_domain/lib/src/goals/goal_metric.dart`
- Create: `packages/nimbus_domain/lib/src/goals/goal_direction.dart`
- Create: `packages/nimbus_domain/lib/src/goals/goal_scope.dart`
- Create: `packages/nimbus_domain/lib/src/goals/goal_amount.dart`
- Create: `packages/nimbus_domain/lib/src/goals/goal_period.dart`
- Create: `packages/nimbus_domain/lib/src/goals/goal.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (shared barrel)
- Test: `packages/nimbus_domain/test/goals/goal_values_test.dart` (new)

**Interfaces:**
- Consumes: `Money` (`const Money(int)`, `Money.zero`, `+`, `-`, `compareTo`, `isZero`, `isNegative`); `QueryFilters` (`const` constructor, `fromJson`/`toJson`, `withDateRange`, `dateRange`, `direction`); `MoneyDirection`; `jsonMapOf` (`analytics/json_support.dart`); `DateKey`, `DateRange`, `PeriodType`, `CalendarKind`.
- Produces (contract names): `GoalMetric` (`isMoney`, `isTrackerMetric`); `GoalDirection`; `GoalScope` / `MoneyScope` / `TrackerScope` with `fromJson`/`toJson`; `GoalAmount` / `MoneyAmount` / `QuantityAmount` with `isZero`, `isNegative`, `zero`, `+`, `-`, `compareTo`, `ratioTo`, `reaches` (`scaledBy` and `dividedUp` arrive in Task 4); `GoalPeriod` / `RecurringPeriod` / `FixedRangePeriod` with `fromStored`, `storedName`, `startDate`, `endDate`; `Goal` with validation, `copyWith`, `defaultAlertPercents`, `alertPercentsFromJson`, `alertPercentsToJson`.

- [ ] **Step 1: Branch**

```bash
git switch phase/5-goals
git switch -c feat/goal-values
```

- [ ] **Step 2: Write the failing tests**

Create `packages/nimbus_domain/test/goals/goal_values_test.dart`:

```dart
import 'dart:convert';

import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

MoneyAmount rials(int minor) => MoneyAmount(Money(minor));

void main() {
  final food = MoneyScope(const QueryFilters(
      direction: MoneyDirection.expense, categorySubtreePaths: ['/food/']));
  final cigarettes = TrackerScope('cig');
  final everything = MoneyScope(const QueryFilters());
  const october = RecurringPeriod(PeriodType.month, DateKey(20261001));

  /// A valid spending cap unless told otherwise, so each test changes only
  /// the field it is about.
  Goal goal({
    String name = 'Dining out',
    GoalMetric metric = GoalMetric.moneySum,
    GoalScope? scope,
    GoalDirection direction = GoalDirection.atMost,
    GoalAmount? target,
    GoalPeriod period = october,
    int weekStart = DateTime.saturday,
    List<int> alertPercents = Goal.defaultAlertPercents,
  }) =>
      Goal(
        id: 'g1',
        name: name,
        metric: metric,
        scope: scope ?? food,
        direction: direction,
        target: target ?? rials(10000),
        period: period,
        calendar: CalendarKind.jalali,
        weekStart: weekStart,
        alertPercents: alertPercents,
      );

  group('GoalMetric', () {
    test('the money metrics are the two whose target is money', () {
      expect(GoalMetric.values.where((m) => m.isMoney).toList(),
          [GoalMetric.moneySum, GoalMetric.netSavings]);
      expect(GoalMetric.values.where((m) => m.isTrackerMetric).toList(),
          [GoalMetric.trackerSum, GoalMetric.trackerCount]);
    });
  });

  group('GoalScope', () {
    test('both scopes survive being stored as JSON text', () {
      final money = MoneyScope(QueryFilters(
        direction: MoneyDirection.expense,
        categorySubtreePaths: const ['/food/', '/food/dining/'],
        tags: TagsAny(const ['/work/']),
      ));
      for (final scope in <GoalScope>[money, cigarettes]) {
        final text = jsonEncode(scope.toJson());
        final restored =
            GoalScope.fromJson(jsonDecode(text) as Map<String, Object?>);
        expect(restored, scope);
        expect(restored.runtimeType, scope.runtimeType);
      }
    });

    test('an unknown type or a missing field is refused, not defaulted', () {
      for (final bad in <Map<String, Object?>>[
        {'type': 'merchant'},
        {'filters': <String, Object?>{}},
        {'type': 'money'},
        {'type': 'tracker'},
        {'type': 'tracker', 'trackerId': ''},
        {'type': 'tracker', 'trackerId': 7},
      ]) {
        expect(() => GoalScope.fromJson(bad), throwsFormatException,
            reason: 'accepted $bad');
      }
    });

    test('money filters that carry a date range are refused', () {
      // The goal's period decides the dates. A stored range would contradict
      // it, and whichever one won, the other would be silently wrong.
      final dated = const QueryFilters()
          .withDateRange(const DateRange(DateKey(20261001), DateKey(20261031)));
      expect(() => MoneyScope(dated), throwsArgumentError);
      expect(
          () => GoalScope.fromJson(
              {'type': 'money', 'filters': dated.toJson()}),
          throwsFormatException);
    });

    test('a tracker scope names a tracker', () {
      expect(() => TrackerScope(''), throwsArgumentError);
    });
  });

  group('GoalAmount', () {
    test('money adds, subtracts and compares in exact minor units', () {
      expect(rials(7999) + rials(1), rials(8000));
      expect(rials(100) - rials(250), rials(-150));
      expect(rials(8000).compareTo(rials(8000)), 0);
      expect(rials(7999).compareTo(rials(8000)), lessThan(0));
      expect(const QuantityAmount(2.5) + const QuantityAmount(0.5),
          const QuantityAmount(3));
    });

    test('money and a quantity never mix', () {
      // Rials plus cigarettes is a measurer bug. It must surface, not add up.
      const money = MoneyAmount(Money(1));
      const quantity = QuantityAmount(1);
      expect(() => money + quantity, throwsArgumentError);
      expect(() => quantity - money, throwsArgumentError);
      expect(() => money.compareTo(quantity), throwsArgumentError);
      expect(() => quantity.ratioTo(money), throwsArgumentError);
      expect(() => money.reaches(quantity, 80), throwsArgumentError);
    });

    test('zero keeps the subtype; isZero and isNegative read the sign', () {
      expect(rials(500).zero, rials(0));
      expect(const QuantityAmount(2).zero, const QuantityAmount(0));
      expect(rials(0).isZero, isTrue);
      expect(rials(-1).isNegative, isTrue);
      expect(const QuantityAmount(0.5).isNegative, isFalse);
    });

    test('ratioTo is a fraction, and a zero target never divides', () {
      expect(rials(2500).ratioTo(rials(10000)), 0.25);
      expect(rials(-2000).ratioTo(rials(10000)), -0.2);
      expect(const QuantityAmount(3).ratioTo(const QuantityAmount(4)), 0.75);
      // Zero cigarettes: none so far is 0% of the way; any at all is past it.
      expect(const QuantityAmount(0).ratioTo(const QuantityAmount(0)), 0);
      expect(const QuantityAmount(1).ratioTo(const QuantityAmount(0)),
          double.infinity);
      expect(rials(-5).ratioTo(rials(0)), 0);
    });

    test('reaches compares money exactly at a threshold', () {
      expect(rials(7999).reaches(rials(10000), 80), isFalse);
      expect(rials(8000).reaches(rials(10000), 80), isTrue);
      expect(rials(10000).reaches(rials(10000), 100), isTrue);
      expect(rials(-500).reaches(rials(10000), 80), isFalse);
      expect(const QuantityAmount(4).reaches(const QuantityAmount(5), 80),
          isTrue);
      expect(const QuantityAmount(3.9).reaches(const QuantityAmount(5), 80),
          isFalse);
    });

    test('a decimal exactly on a threshold reaches it', () {
      // 0.29 * 100 == 28.999999999999996 in binary floating point.
      expect(const QuantityAmount(0.29).reaches(const QuantityAmount(1), 29),
          isTrue);
      expect(const QuantityAmount(0.2899).reaches(const QuantityAmount(1), 29),
          isFalse);
    });

    test('a zero target is reached by anything above zero', () {
      for (final percent in [1, 80, 100]) {
        expect(
            const QuantityAmount(0).reaches(const QuantityAmount(0), percent),
            isFalse);
        expect(
            const QuantityAmount(1).reaches(const QuantityAmount(0), percent),
            isTrue);
        expect(rials(1).reaches(rials(0), percent), isTrue);
      }
    });
  });

  group('GoalPeriod', () {
    test('each period maps to its stored columns and back', () {
      for (final type in PeriodType.values) {
        final recurring = RecurringPeriod(type, const DateKey(20261015));
        expect(recurring.storedName, type.name);
        expect(recurring.startDate, const DateKey(20261015));
        expect(recurring.endDate, isNull);
        expect(GoalPeriod.fromStored(type.name, 20261015, null), recurring);
      }
      final range = FixedRangePeriod(
          const DateRange(DateKey(20261101), DateKey(20270320)));
      expect(range.storedName, 'fixedRange');
      expect(range.startDate, const DateKey(20261101));
      expect(range.endDate, const DateKey(20270320));
      expect(GoalPeriod.fromStored('fixedRange', 20261101, 20270320), range);
    });

    test('stored columns that mean nothing are refused', () {
      for (final (name, start, end) in [
        ('fortnight', 20261001, null), // not a period
        ('month', 20261001, 20261031), // a recurring period has no end
        ('fixedRange', 20261001, null), // a range needs one
        ('fixedRange', 20261031, 20261001), // and cannot end before it starts
      ]) {
        expect(() => GoalPeriod.fromStored(name, start, end),
            throwsFormatException,
            reason: 'accepted ($name, $start, $end)');
      }
    });

    test('a fixed range cannot end before it starts', () {
      expect(
          () => FixedRangePeriod(
              const DateRange(DateKey(20261031), DateKey(20261001))),
          throwsArgumentError);
      expect(
          FixedRangePeriod(
                  const DateRange(DateKey(20261001), DateKey(20261001)))
              .range
              .dayCount,
          1);
    });
  });

  group('Goal', () {
    test('each shape the editor offers builds', () {
      // A cap, a limit, a minimum and savings: metric and direction only.
      expect(goal, returnsNormally);
      expect(
          () => goal(
              metric: GoalMetric.trackerCount,
              scope: cigarettes,
              target: const QuantityAmount(0),
              period: const RecurringPeriod(PeriodType.day, DateKey(20261010))),
          returnsNormally);
      expect(
          () => goal(
              metric: GoalMetric.trackerCount,
              scope: TrackerScope('gym'),
              direction: GoalDirection.atLeast,
              target: const QuantityAmount(3),
              period:
                  const RecurringPeriod(PeriodType.week, DateKey(20261010))),
          returnsNormally);
      expect(
          () => goal(
              metric: GoalMetric.netSavings,
              scope: everything,
              direction: GoalDirection.atLeast,
              target: rials(5000000),
              period: FixedRangePeriod(
                  const DateRange(DateKey(20261101), DateKey(20270320)))),
          returnsNormally);
    });

    test('the scope must match the metric family', () {
      expect(() => goal(scope: cigarettes), throwsArgumentError);
      expect(
          () => goal(
              metric: GoalMetric.trackerSum,
              target: const QuantityAmount(2)),
          throwsArgumentError);
      expect(
          () => goal(
              metric: GoalMetric.txnCount,
              scope: cigarettes,
              target: const QuantityAmount(5)),
          throwsArgumentError);
    });

    test('the target type must match the metric', () {
      expect(() => goal(target: const QuantityAmount(10000)),
          throwsArgumentError);
      expect(() => goal(metric: GoalMetric.txnCount, target: rials(5)),
          throwsArgumentError);
      expect(
          () => goal(
              metric: GoalMetric.trackerSum,
              scope: cigarettes,
              target: rials(5)),
          throwsArgumentError);
      expect(
          () => goal(
              metric: GoalMetric.netSavings,
              scope: everything,
              direction: GoalDirection.atLeast,
              target: const QuantityAmount(5)),
          throwsArgumentError);
    });

    test('net savings reads both directions, so it cannot filter one', () {
      // Income minus expense: a direction filter would zero one side.
      expect(
          () => goal(
              metric: GoalMetric.netSavings,
              direction: GoalDirection.atLeast,
              scope: food),
          throwsArgumentError);
    });

    test('a negative target is refused; zero only for atMost', () {
      expect(() => goal(target: rials(-1)), throwsArgumentError);
      expect(
          () => goal(target: rials(0), direction: GoalDirection.atLeast),
          throwsArgumentError);
      // "Spend nothing on this" is a real cap, as zero cigarettes is a limit.
      expect(() => goal(target: rials(0)), returnsNormally);
    });

    test('alert percents are ascending, distinct and within 1 to 100', () {
      for (final bad in [
        <int>[],
        [100, 80],
        [80, 80],
        [0, 100],
        [80, 101],
      ]) {
        expect(() => goal(alertPercents: bad), throwsArgumentError,
            reason: 'accepted $bad');
      }
      expect(() => goal(alertPercents: [1, 100]), returnsNormally);
      expect(() => goal(alertPercents: [50]), returnsNormally);
    });

    test('the week starts on an ISO weekday', () {
      expect(() => goal(weekStart: 0), throwsArgumentError);
      expect(() => goal(weekStart: 8), throwsArgumentError);
      expect(() => goal(weekStart: DateTime.monday), returnsNormally);
      expect(() => goal(weekStart: DateTime.sunday), returnsNormally);
    });

    test('a blank name is refused', () {
      expect(() => goal(name: ''), throwsArgumentError);
      expect(() => goal(name: '   '), throwsArgumentError);
    });

    test('the alert percents cannot change after construction', () {
      // A goal keys provider families; a list mutated after hashing would
      // strand its cache entry.
      final percents = [80, 100];
      final g = goal(alertPercents: percents);
      percents.add(120);
      expect(g.alertPercents, [80, 100]);
      expect(() => g.alertPercents.add(90), throwsUnsupportedError);
    });

    test('copyWith replaces only what it names, and validates the result', () {
      final g = goal();
      expect(g.copyWith(), g);
      final paused = g.copyWith(name: 'Eating out', active: false);
      expect(paused.id, 'g1');
      expect(paused.name, 'Eating out');
      expect(paused.active, isFalse);
      expect(paused.copyWith(name: g.name, active: true), g);
      // A zero cap is fine; turned into a goal to reach, it is not.
      final zero = goal(target: rials(0));
      expect(() => zero.copyWith(direction: GoalDirection.atLeast),
          throwsArgumentError);
    });

    test('equal goals are equal and hash alike; every field counts', () {
      expect(goal(), goal());
      expect(goal().hashCode, goal().hashCode);
      expect(goal(), isNot(goal(alertPercents: [50, 100])));
      expect(goal(), isNot(goal(weekStart: DateTime.monday)));
      expect(goal(), isNot(goal().copyWith(active: false)));
    });

    test('alert percents survive being stored as JSON text', () {
      expect(Goal.alertPercentsToJson(const [80, 100]), '[80,100]');
      expect(Goal.alertPercentsFromJson('[80,100]'), [80, 100]);
      expect(
          Goal.alertPercentsFromJson(
              Goal.alertPercentsToJson(const [25, 50, 100])),
          [25, 50, 100]);
    });

    test('stored alert percents must be a JSON list of ints', () {
      for (final bad in [
        '',
        'eighty',
        '{"a":1}',
        'null',
        '80',
        '[80.5]',
        '["80"]',
        '[null]',
      ]) {
        expect(() => Goal.alertPercentsFromJson(bad), throwsFormatException,
            reason: 'accepted "$bad"');
      }
    });
  });
}
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_domain && dart test test/goals/goal_values_test.dart`
Expected: FAIL to load, naming the missing types; the first errors are:
```
Error: Type 'MoneyAmount' not found.
Error: Method not found: 'MoneyAmount'.
Error: Method not found: 'MoneyScope'.
Error: Method not found: 'TrackerScope'.
Error: Method not found: 'RecurringPeriod'.
```

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-goal-values
```

- [ ] **Step 5: Write `GoalMetric` and `GoalDirection`**

Create `packages/nimbus_domain/lib/src/goals/goal_metric.dart`:

```dart
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
```

Create `packages/nimbus_domain/lib/src/goals/goal_direction.dart`:

```dart
/// Which side of its target a goal wants to end on.
///
/// The `name` strings are stored in `goals.direction`. Do not rename a value.
enum GoalDirection {
  /// Stay at or below the target.
  atMost,

  /// Reach the target.
  atLeast,
}
```

- [ ] **Step 6: Write `GoalScope`**

Create `packages/nimbus_domain/lib/src/goals/goal_scope.dart`:

```dart
import 'package:meta/meta.dart';

import '../analytics/json_support.dart';
import '../analytics/query_filters.dart';

/// What a goal measures over: matching transactions, or one tracker.
///
/// Stored as `goals.scope_json`. A scope holds filters, never a whole query:
/// the goal's metric decides the aggregate and its period decides the dates.
@immutable
sealed class GoalScope {
  const GoalScope();

  /// Reads `{"type":"money","filters":{...}}` or
  /// `{"type":"tracker","trackerId":"..."}`.
  ///
  /// Throws [FormatException] on an unknown type, a missing field, or money
  /// filters with a date range. Never defaults: a dropped filter widens what a
  /// goal measures, and a cap would then read under budget while the user is
  /// over.
  factory GoalScope.fromJson(Map<String, Object?> json) {
    switch (json['type']) {
      case 'money':
        final filters =
            QueryFilters.fromJson(jsonMapOf(json['filters'], 'filters'));
        if (filters.dateRange != null) {
          throw const FormatException(
              'a goal scope stores no date range; the period sets it');
        }
        return MoneyScope(filters);
      case 'tracker':
        final id = json['trackerId'];
        if (id is! String || id.isEmpty) {
          throw FormatException(
              'trackerId needs a non-empty string, got "$id"');
        }
        return TrackerScope(id);
      case final other:
        throw FormatException('unknown goal scope type "$other"');
    }
  }

  Map<String, Object?> toJson();
}

/// Transactions matching [filters]: Phase 3's lossless `QueryFilters`.
final class MoneyScope extends GoalScope {
  /// Throws [ArgumentError] when [filters] has a date range: the goal's
  /// period decides the dates, and a stored range would contradict it.
  MoneyScope(this.filters) {
    if (filters.dateRange != null) {
      throw ArgumentError.value(
          filters, 'filters', 'a goal scope has no date range');
    }
  }

  final QueryFilters filters;

  @override
  Map<String, Object?> toJson() =>
      {'type': 'money', 'filters': filters.toJson()};

  @override
  bool operator ==(Object other) =>
      other is MoneyScope && other.filters == filters;

  @override
  int get hashCode => Object.hash('money', filters);

  @override
  String toString() => 'MoneyScope(${filters.toJson()})';
}

/// One tracker's entries.
final class TrackerScope extends GoalScope {
  /// Throws [ArgumentError] when [trackerId] is empty.
  TrackerScope(this.trackerId) {
    if (trackerId.isEmpty) {
      throw ArgumentError.value(trackerId, 'trackerId', 'must not be empty');
    }
  }

  final String trackerId;

  @override
  Map<String, Object?> toJson() => {'type': 'tracker', 'trackerId': trackerId};

  @override
  bool operator ==(Object other) =>
      other is TrackerScope && other.trackerId == trackerId;

  @override
  int get hashCode => Object.hash('tracker', trackerId);

  @override
  String toString() => 'TrackerScope($trackerId)';
}
```

- [ ] **Step 7: Write `GoalAmount`**

Create `packages/nimbus_domain/lib/src/goals/goal_amount.dart`. Every binary member goes through `_moneyOf` / `_valueOf`, so a mixed pair throws in one place:

```dart
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
}

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
    // Tracker values are typed decimals, and 0.29 * 100 is 28.999... in
    // binary: 0.29 of a 1-litre goal would never reach 29%. A relative
    // tolerance far below any loggable difference keeps an exact threshold
    // a crossing without admitting a value that is really short of it.
    final needed = of * percent;
    return value * 100 >= needed - needed.abs() * 1e-9;
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
```

- [ ] **Step 8: Write `GoalPeriod`**

Create `packages/nimbus_domain/lib/src/goals/goal_period.dart`:

```dart
import 'package:meta/meta.dart';

import '../calendar/calendar.dart';
import '../calendar/date_key.dart';

const _fixedRangeName = 'fixedRange';

/// When a goal applies: every calendar period of one type, or one fixed range.
///
/// Maps one-to-one onto `goals.period`, `start_date` and `end_date`. A
/// combination those columns could hold but that means nothing -- a month
/// with an end date, a range without one -- cannot be built.
@immutable
sealed class GoalPeriod {
  const GoalPeriod();

  /// Reads the stored columns back.
  ///
  /// Throws [FormatException] on an unknown name, an end date on a recurring
  /// period, a fixed range without one, or a range that ends before it starts.
  factory GoalPeriod.fromStored(String period, int startDate, int? endDate) {
    if (period == _fixedRangeName) {
      if (endDate == null) {
        throw const FormatException('a fixed range needs an end date');
      }
      if (endDate < startDate) {
        throw FormatException(
            'a fixed range ends ($endDate) before it starts ($startDate)');
      }
      return FixedRangePeriod(DateRange(DateKey(startDate), DateKey(endDate)));
    }
    for (final type in PeriodType.values) {
      if (type.name != period) continue;
      if (endDate != null) {
        throw FormatException(
            'a recurring "$period" goal has no end date, got $endDate');
      }
      return RecurringPeriod(type, DateKey(startDate));
    }
    throw FormatException('unknown goal period "$period"');
  }

  /// `goals.period`: a [PeriodType] name, or `fixedRange`.
  String get storedName;

  /// `goals.start_date`.
  DateKey get startDate;

  /// `goals.end_date`: null for a recurring period.
  DateKey? get endDate;
}

/// Every [type] period, from the one containing [since].
final class RecurringPeriod extends GoalPeriod {
  const RecurringPeriod(this.type, this.since);

  final PeriodType type;

  /// History starts with the period containing this day.
  final DateKey since;

  @override
  String get storedName => type.name;

  @override
  DateKey get startDate => since;

  @override
  DateKey? get endDate => null;

  @override
  bool operator ==(Object other) =>
      other is RecurringPeriod && other.type == type && other.since == since;

  @override
  int get hashCode => Object.hash(type, since);

  @override
  String toString() => 'RecurringPeriod(${type.name} since $since)';
}

/// One period: [range], for a target such as savings by a date.
final class FixedRangePeriod extends GoalPeriod {
  /// Throws [ArgumentError] when [range] ends before it starts.
  FixedRangePeriod(this.range) {
    if (range.endInclusive < range.startInclusive) {
      throw ArgumentError.value(range, 'range', 'ends before it starts');
    }
  }

  final DateRange range;

  @override
  String get storedName => _fixedRangeName;

  @override
  DateKey get startDate => range.startInclusive;

  @override
  DateKey get endDate => range.endInclusive;

  @override
  bool operator ==(Object other) =>
      other is FixedRangePeriod && other.range == range;

  @override
  int get hashCode => Object.hash(_fixedRangeName, range);

  @override
  String toString() => 'FixedRangePeriod($range)';
}
```

- [ ] **Step 9: Write `Goal`**

Create `packages/nimbus_domain/lib/src/goals/goal.dart`. `final scope = this.scope;` is deliberate: a public field does not promote, and the `netSavings` check needs `scope.filters`.

```dart
import 'dart:convert';

import 'package:meta/meta.dart';

import '../calendar/calendar.dart';
import 'goal_amount.dart';
import 'goal_direction.dart';
import 'goal_metric.dart';
import 'goal_period.dart';
import 'goal_scope.dart';

/// One goal: [metric] over [scope] each [period], compared to [target] in
/// [direction].
///
/// A combination that means nothing is refused at construction with an
/// [ArgumentError], so nothing downstream has to ask. The editor checks the
/// user-facing rules first and shows them inline; this is the backstop.
@immutable
final class Goal {
  /// Throws [ArgumentError] when:
  /// - [name] is blank;
  /// - [scope] is not a `TrackerScope` for a tracker metric, or not a
  ///   `MoneyScope` for any other;
  /// - [target] is not a `MoneyAmount` for a money metric, or not a
  ///   `QuantityAmount` for any other;
  /// - [metric] is `netSavings` and the filters name a direction (it reads
  ///   both);
  /// - [target] is negative, or zero on `atLeast` ("zero cigarettes" is a
  ///   real limit; "reach zero" is not a goal);
  /// - [alertPercents] is empty, not strictly ascending, or outside 1..100;
  /// - [weekStart] is not an ISO weekday, `DateTime.monday`..`sunday`.
  Goal({
    required this.id,
    required this.name,
    required this.metric,
    required this.scope,
    required this.direction,
    required this.target,
    required this.period,
    required this.calendar,
    required this.weekStart,
    List<int> alertPercents = defaultAlertPercents,
    this.active = true,
  }) : alertPercents = List.unmodifiable(alertPercents) {
    _validate();
  }

  static const defaultAlertPercents = <int>[80, 100];

  final String id;
  final String name;
  final GoalMetric metric;
  final GoalScope scope;
  final GoalDirection direction;
  final GoalAmount target;
  final GoalPeriod period;

  /// The goal's own calendar, copied from settings at creation. Switching the
  /// app's calendar later does not move this goal's periods.
  final CalendarKind calendar;

  /// ISO weekday a weekly period starts on, copied from settings at creation.
  final int weekStart;

  /// Whole percents, strictly ascending. Unmodifiable.
  final List<int> alertPercents;

  /// False when paused: not evaluated, no alerts.
  final bool active;

  void _validate() {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be blank');
    }
    final scope = this.scope;
    if (metric.isTrackerMetric != (scope is TrackerScope)) {
      throw ArgumentError.value(scope, 'scope',
          '${metric.name} does not measure over this kind of scope');
    }
    if (metric.isMoney != (target is MoneyAmount)) {
      throw ArgumentError.value(target, 'target',
          '${metric.name} does not measure this kind of amount');
    }
    if (metric == GoalMetric.netSavings &&
        scope is MoneyScope &&
        scope.filters.direction != null) {
      throw ArgumentError.value(scope, 'scope',
          'net savings reads income and expense, so it takes no direction');
    }
    if (target.isNegative) {
      throw ArgumentError.value(target, 'target', 'must not be negative');
    }
    if (target.isZero && direction == GoalDirection.atLeast) {
      throw ArgumentError.value(
          target, 'target', 'a target to reach must be above zero');
    }
    if (alertPercents.isEmpty) {
      throw ArgumentError.value(
          alertPercents, 'alertPercents', 'needs at least one percent');
    }
    for (var i = 0; i < alertPercents.length; i++) {
      final percent = alertPercents[i];
      if (percent < 1 || percent > 100) {
        throw ArgumentError.value(
            alertPercents, 'alertPercents', '$percent is outside 1..100');
      }
      if (i > 0 && percent <= alertPercents[i - 1]) {
        throw ArgumentError.value(alertPercents, 'alertPercents',
            'must be strictly ascending, without duplicates');
      }
    }
    if (weekStart < DateTime.monday || weekStart > DateTime.sunday) {
      throw ArgumentError.value(
          weekStart, 'weekStart', 'must be an ISO weekday, 1..7');
    }
  }

  /// This goal with the named fields replaced, validated like a new one.
  Goal copyWith({
    String? name,
    GoalMetric? metric,
    GoalScope? scope,
    GoalDirection? direction,
    GoalAmount? target,
    GoalPeriod? period,
    CalendarKind? calendar,
    int? weekStart,
    List<int>? alertPercents,
    bool? active,
  }) =>
      Goal(
        id: id,
        name: name ?? this.name,
        metric: metric ?? this.metric,
        scope: scope ?? this.scope,
        direction: direction ?? this.direction,
        target: target ?? this.target,
        period: period ?? this.period,
        calendar: calendar ?? this.calendar,
        weekStart: weekStart ?? this.weekStart,
        alertPercents: alertPercents ?? this.alertPercents,
        active: active ?? this.active,
      );

  /// Reads `goals.alert_percents`. Throws [FormatException] on anything that
  /// is not a JSON list of ints. Range and order are the constructor's to
  /// check.
  static List<int> alertPercentsFromJson(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! List || decoded.any((percent) => percent is! int)) {
      throw FormatException(
          'alert percents need a JSON list of ints, got "$raw"');
    }
    return List<int>.unmodifiable(decoded);
  }

  static String alertPercentsToJson(List<int> percents) =>
      jsonEncode(percents);

  @override
  bool operator ==(Object other) =>
      other is Goal &&
      other.id == id &&
      other.name == name &&
      other.metric == metric &&
      other.scope == scope &&
      other.direction == direction &&
      other.target == target &&
      other.period == period &&
      other.calendar == calendar &&
      other.weekStart == weekStart &&
      _samePercents(other.alertPercents, alertPercents) &&
      other.active == active;

  @override
  int get hashCode => Object.hash(id, name, metric, scope, direction, target,
      period, calendar, weekStart, Object.hashAll(alertPercents), active);

  static bool _samePercents(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'Goal($id, "$name", ${metric.name} ${direction.name} '
      '$target, $period, ${calendar.name}${active ? '' : ', paused'})';
}
```

- [ ] **Step 10: Export the new files**

In `packages/nimbus_domain/lib/nimbus_domain.dart`, add six lines between `export 'src/entitlements/feature.dart';` and `export 'src/money/currency.dart';`, with the Edit tool:

```dart
export 'src/goals/goal.dart';
export 'src/goals/goal_amount.dart';
export 'src/goals/goal_direction.dart';
export 'src/goals/goal_metric.dart';
export 'src/goals/goal_period.dart';
export 'src/goals/goal_scope.dart';
```

(`goal.dart` sorts before `goal_amount.dart`: `.` precedes `_`.)

- [ ] **Step 11: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_domain && dart test test/goals/goal_values_test.dart`
Expected: `+28: All tests passed!`

Then `dart analyze --fatal-infos` from the repo root. Expected: `No issues found!`

- [ ] **Step 12: Run the full gate**

Expected:
- `nimbus_domain` 328 + 28 = **356**.
- Architecture, `nimbus_data`, `nimbus_design` and `app` unchanged from Task 1.

- [ ] **Step 13: Commit and merge**

```bash
git add packages/nimbus_domain
git commit -F - <<'EOF'
feat(goals): goal value types and their validation

The four goal types differ only by field values: a metric over a
scope each period, compared to a target in a direction. This commit
names those values and refuses every combination that means nothing
(spec section 2), so the engine, the DAOs and the editor never have
to ask whether a goal is well formed.

Money stays Money. MoneyAmount wraps exact minor units and every
threshold check is integer arithmetic (minor x 100 >= target x
percent), so 7 999 of 10 000 is not 80%. Mixing money with a
quantity throws instead of adding up.

GoalScope and GoalPeriod map one-to-one onto the v40 columns and
read them back with FormatException on anything malformed, never a
default: a dropped filter widens what a cap measures and reports
the user under budget while they are over.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only feat/goal-values
```

---

### Task 3: `GoalPeriods` and `assess` status, both directions

Branch `feat/goal-assess`, slug `goal-assess`.

**Files:**
- Create: `packages/nimbus_domain/lib/src/goals/goal_status.dart`
- Create: `packages/nimbus_domain/lib/src/goals/goal_progress.dart`
- Create: `packages/nimbus_domain/lib/src/goals/goal_periods.dart`
- Create: `packages/nimbus_domain/lib/src/goals/goal_assess.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart`
- Test: `packages/nimbus_domain/test/goals/goal_periods_test.dart` (new), `packages/nimbus_domain/test/goals/goal_assess_test.dart` (new)

**Interfaces:**
- Consumes: Task 2's types; `PeriodBoundaries.forPeriod(PeriodType, DateKey, AppCalendar, {int firstDayOfWeek})` and `PeriodBoundaries.series(PeriodType, DateRange, AppCalendar, {int firstDayOfWeek})` (Phase 3); `const GregorianCalendar()`, `const JalaliCalendar()`; `DateKey.daysUntil`, `DateRange.dayCount`.
- Produces: `GoalStatus`; `RequiredRate`, `Projection`, `GoalProgress`; `GoalPeriods.calendarFor` / `current` / `closed`; `assess(Goal, DateRange, GoalAmount, DateKey)`.

**For the reviewer — the projection is a placeholder in this task.** `assess` sets `projection: Projection(projectedEnd: current)` with no `requiredRate`. Task 4 replaces exactly that argument (projection and required rate, with tests). No status rule reads the projection, so nothing in this task depends on it, and no test here asserts it.

**One status function.** `_status(direction, position, settled:, warned:)` holds spec §2's whole table once. Each direction only names three facts — what settles a period early (over a cap / reaching a goal), what a closed unsettled period is (`met` / `missed`) and its open warning (lowest alert percent / behind pace) — so there is no second copy of the rules with the comparisons flipped.

- [ ] **Step 1: Branch**

```bash
git switch phase/5-goals
git switch -c feat/goal-assess
```

- [ ] **Step 2: Write the failing tests**

The Jalali keys below were computed with `JalaliCalendar.keyOf` on this repo (the conversion `test/calendar/jalali_calendar_test.dart` pins), not guessed; the file's header comment lists them.

Create `packages/nimbus_domain/test/goals/goal_periods_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

// Jalali dates below were computed with JalaliCalendar.keyOf, whose
// conversion test/calendar/jalali_calendar_test.dart pins:
//   Bahman 1404      = 2026-01-21 .. 2026-02-19 (30 days)
//   Esfand 1404      = 2026-02-20 .. 2026-03-20 (29 days: 1404 is not leap)
//   Farvardin 1405   = 2026-03-21 .. 2026-04-20 (31 days)
//   Mehr 1405        = 2026-09-23 .. 2026-10-22 (30 days)
//   29 Esfand 1404 (2026-03-20) is a Friday.

DateRange range(int start, int end) => DateRange(DateKey(start), DateKey(end));

void main() {
  /// A cap whose period, calendar and week start are the only things that
  /// vary here.
  Goal goal(
    GoalPeriod period, {
    CalendarKind calendar = CalendarKind.gregorian,
    int weekStart = DateTime.saturday,
  }) =>
      Goal(
        id: 'g1',
        name: 'Groceries',
        metric: GoalMetric.moneySum,
        scope: MoneyScope(const QueryFilters()),
        direction: GoalDirection.atMost,
        target: const MoneyAmount(Money(10000)),
        period: period,
        calendar: calendar,
        weekStart: weekStart,
      );
  RecurringPeriod monthly(int since) =>
      RecurringPeriod(PeriodType.month, DateKey(since));
  RecurringPeriod weekly(int since) =>
      RecurringPeriod(PeriodType.week, DateKey(since));

  test('calendarFor gives the calendar each kind names', () {
    for (final kind in CalendarKind.values) {
      expect(GoalPeriods.calendarFor(kind).kind, kind);
    }
  });

  group('current', () {
    test('a Jalali month turns over at Nowruz', () {
      final g = goal(monthly(20260101), calendar: CalendarKind.jalali);
      expect(GoalPeriods.current(g, const DateKey(20260320)),
          range(20260220, 20260320));
      expect(GoalPeriods.current(g, const DateKey(20260321)),
          range(20260321, 20260420));
    });

    test('a Gregorian month turns over at New Year', () {
      final g = goal(monthly(20260101));
      expect(GoalPeriods.current(g, const DateKey(20261231)),
          range(20261201, 20261231));
      expect(GoalPeriods.current(g, const DateKey(20270101)),
          range(20270101, 20270131));
    });

    test("the goal's own calendar decides its month", () {
      // Switching the app's calendar must not move a goal's period: the
      // calendar is the goal's field, read here, and nothing else is.
      expect(
          GoalPeriods.current(
              goal(monthly(20260101)), const DateKey(20261010)),
          range(20261001, 20261031));
      expect(
          GoalPeriods.current(
              goal(monthly(20260101), calendar: CalendarKind.jalali),
              const DateKey(20261010)),
          range(20260923, 20261022));
    });

    test('a Monday and a Saturday week start give different weeks', () {
      // 2026-12-31 is a Thursday; both weeks straddle the Gregorian new year.
      expect(
          GoalPeriods.current(
              goal(weekly(20261201), weekStart: DateTime.monday),
              const DateKey(20261231)),
          range(20261228, 20270103));
      expect(
          GoalPeriods.current(
              goal(weekly(20261201), weekStart: DateTime.saturday),
              const DateKey(20261231)),
          range(20261226, 20270101));
      // On 29 Esfand a Saturday week ends with the Jalali year; a Monday week
      // runs on into Farvardin.
      expect(
          GoalPeriods.current(
              goal(weekly(20260301),
                  calendar: CalendarKind.jalali, weekStart: DateTime.saturday),
              const DateKey(20260320)),
          range(20260314, 20260320));
      expect(
          GoalPeriods.current(
              goal(weekly(20260301),
                  calendar: CalendarKind.jalali, weekStart: DateTime.monday),
              const DateKey(20260320)),
          range(20260316, 20260322));
    });

    test('a fixed range is its own current period, whatever the day', () {
      final g = goal(FixedRangePeriod(range(20261101, 20270320)));
      for (final today in [20261010, 20261215, 20270401]) {
        expect(GoalPeriods.current(g, DateKey(today)),
            range(20261101, 20270320));
      }
    });
  });

  group('closed', () {
    test('Jalali months close in order across Nowruz', () {
      // Since 10 Bahman 1404; today is 5 Farvardin 1405.
      final g = goal(monthly(20260130), calendar: CalendarKind.jalali);
      expect(GoalPeriods.closed(g, const DateKey(20260325)),
          [range(20260121, 20260219), range(20260220, 20260320)]);
    });

    test('Gregorian months close in order across New Year', () {
      final g = goal(monthly(20261115));
      expect(GoalPeriods.closed(g, const DateKey(20270110)),
          [range(20261101, 20261130), range(20261201, 20261231)]);
    });

    test('the week start moves every closed week', () {
      // Since Sunday 2026-12-20; today is Saturday 2027-01-02.
      expect(
          GoalPeriods.closed(
              goal(weekly(20261220), weekStart: DateTime.monday),
              const DateKey(20270102)),
          [range(20261214, 20261220), range(20261221, 20261227)]);
      expect(
          GoalPeriods.closed(
              goal(weekly(20261220), weekStart: DateTime.saturday),
              const DateKey(20270102)),
          [range(20261219, 20261225), range(20261226, 20270101)]);
    });

    test('nothing has closed in the first period, or before the goal starts',
        () {
      final g = goal(monthly(20261015));
      expect(GoalPeriods.closed(g, const DateKey(20261031)), isEmpty);
      expect(GoalPeriods.closed(g, const DateKey(20261001)), isEmpty);
      expect(GoalPeriods.closed(g, const DateKey(20260901)), isEmpty);
    });

    test('a fixed range never has closed periods', () {
      // It is one period. Once it ends it is still the current one, closed.
      final g = goal(FixedRangePeriod(range(20261101, 20270320)));
      expect(GoalPeriods.closed(g, const DateKey(20270401)), isEmpty);
    });
  });
}
```

Create `packages/nimbus_domain/test/goals/goal_assess_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

MoneyAmount rials(int minor) => MoneyAmount(Money(minor));
QuantityAmount count(double n) => QuantityAmount(n);
DateRange range(int start, int end) => DateRange(DateKey(start), DateKey(end));

/// A cap of 10 000 a month: atMost, money.
Goal cap({
  int since = 20260101,
  List<int> alertPercents = Goal.defaultAlertPercents,
  GoalAmount? target,
}) =>
    Goal(
      id: 'cap',
      name: 'Dining out',
      metric: GoalMetric.moneySum,
      scope: MoneyScope(const QueryFilters(direction: MoneyDirection.expense)),
      direction: GoalDirection.atMost,
      target: target ?? rials(10000),
      period: RecurringPeriod(PeriodType.month, DateKey(since)),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.saturday,
      alertPercents: alertPercents,
    );

/// Seven sessions a week, so the pace is one a day: atLeast, a quantity.
Goal reading({int since = 20260101}) => Goal(
      id: 'reading',
      name: 'Reading',
      metric: GoalMetric.trackerCount,
      scope: TrackerScope('reading'),
      direction: GoalDirection.atLeast,
      target: count(7),
      period: RecurringPeriod(PeriodType.week, DateKey(since)),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.saturday,
    );

/// Save 1 000 000 between two dates: atLeast, money, may go negative.
Goal savings(DateRange between) => Goal(
      id: 'savings',
      name: 'Laptop',
      metric: GoalMetric.netSavings,
      scope: MoneyScope(const QueryFilters()),
      direction: GoalDirection.atLeast,
      target: rials(1000000),
      period: FixedRangePeriod(between),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.saturday,
    );

GoalStatus statusOf(
        Goal goal, DateRange period, GoalAmount current, int today) =>
    assess(goal, period, current, DateKey(today)).status;

void main() {
  final october = range(20261001, 20261031);
  // Saturday 2026-10-10 to Friday 2026-10-16.
  final week = range(20261010, 20261016);

  group('atMost', () {
    test('below the lowest alert percent while open is on track', () {
      final progress =
          assess(cap(), october, rials(7999), const DateKey(20261010));
      expect(progress.status, GoalStatus.onTrack);
      expect(progress.period, october);
      expect(progress.current, rials(7999));
      expect(progress.target, rials(10000));
      expect(progress.fractionOfTarget, 0.7999);
    });

    test('at the lowest alert percent while open is at risk', () {
      expect(
          statusOf(cap(), october, rials(8000), 20261010), GoalStatus.atRisk);
    });

    test('exactly at the cap is within it: at risk while open, met once closed',
        () {
      expect(statusOf(cap(), october, rials(10000), 20261010),
          GoalStatus.atRisk);
      expect(statusOf(cap(), october, rials(10000), 20261101), GoalStatus.met);
    });

    test('over the cap is exceeded, open or closed', () {
      expect(statusOf(cap(), october, rials(10001), 20261010),
          GoalStatus.exceeded);
      expect(statusOf(cap(), october, rials(10001), 20261105),
          GoalStatus.exceeded);
    });

    test('a closed period within the cap is met', () {
      expect(statusOf(cap(), october, rials(9000), 20261101), GoalStatus.met);
    });

    test('the status reads the amount, never the pace', () {
      // Half the cap on day one projects far past it. Rent paid on the first
      // would otherwise hold the month at risk all month.
      expect(statusOf(cap(), october, rials(5000), 20261001),
          GoalStatus.onTrack);
    });

    test('the lowest alert percent sets the warning line', () {
      final early = cap(alertPercents: [50, 100]);
      expect(statusOf(early, october, rials(4999), 20261010),
          GoalStatus.onTrack);
      expect(
          statusOf(early, october, rials(5000), 20261010), GoalStatus.atRisk);
    });

    test('a zero target: nothing is fine, anything at all is exceeded', () {
      // "Zero cigarettes today" -- no division by zero anywhere.
      final none = Goal(
        id: 'cig',
        name: 'Cigarettes',
        metric: GoalMetric.trackerCount,
        scope: TrackerScope('cig'),
        direction: GoalDirection.atMost,
        target: count(0),
        period: const RecurringPeriod(PeriodType.day, DateKey(20260101)),
        calendar: CalendarKind.gregorian,
        weekStart: DateTime.saturday,
      );
      final today = range(20261010, 20261010);
      final clean = assess(none, today, count(0), const DateKey(20261010));
      expect(clean.status, GoalStatus.onTrack);
      expect(clean.fractionOfTarget, 0);
      expect(statusOf(none, today, count(0), 20261011), GoalStatus.met);
      final one = assess(none, today, count(1), const DateKey(20261010));
      expect(one.status, GoalStatus.exceeded);
      expect(one.fractionOfTarget, double.infinity);
    });
  });

  group('atLeast', () {
    test('day one with nothing yet is on track', () {
      // No full day has passed, so no pace has been missed.
      expect(statusOf(reading(), week, count(0), 20261010), GoalStatus.onTrack);
    });

    test('behind pace is at risk; exactly on pace is on track', () {
      // Tuesday: three full days (Sat, Sun, Mon) are behind us, so the pace
      // is 7 x 3 / 7 = 3 sessions.
      expect(statusOf(reading(), week, count(2), 20261013), GoalStatus.atRisk);
      expect(statusOf(reading(), week, count(3), 20261013), GoalStatus.onTrack);
    });

    test('reaching the target is met, before or after the period ends', () {
      expect(statusOf(reading(), week, count(7), 20261013), GoalStatus.met);
      expect(statusOf(reading(), week, count(8), 20261020), GoalStatus.met);
    });

    test('a closed period short of the target is missed, not exceeded', () {
      // "Exceeded" is a cap's failure. A minimum that fell short was missed.
      expect(statusOf(reading(), week, count(6), 20261017), GoalStatus.missed);
    });
  });

  group('both directions', () {
    test('nothing has started before the period or the goal begins', () {
      final laptop = savings(range(20261101, 20270331));
      expect(statusOf(laptop, range(20261101, 20270331), rials(0), 20261010),
          GoalStatus.notStarted);
      // A cap starting on the 20th has not started on the 15th, although its
      // month has.
      final late = cap(since: 20261020);
      expect(statusOf(late, october, rials(9000), 20261015),
          GoalStatus.notStarted);
      expect(statusOf(late, october, rials(9000), 20261020), GoalStatus.atRisk);
    });

    test('a goal made mid-period counts the whole period', () {
      // A cap made on the 15th covers the month, so what was spent on the
      // 3rd counts: the month is what the budget covers.
      final made15th = cap(since: 20261015);
      const today = DateKey(20261015);
      final period = GoalPeriods.current(made15th, today);
      expect(period, october);
      expect(assess(made15th, period, rials(9000), today).status,
          GoalStatus.atRisk);
      // The pace counts from the period's start too: a weekly goal made on a
      // Tuesday with nothing logged is already three sessions behind.
      expect(statusOf(reading(since: 20261013), week, count(0), 20261013),
          GoalStatus.atRisk);
    });

    test('an empty period is zero, and the table still applies', () {
      expect(statusOf(cap(), october, rials(0), 20261101), GoalStatus.met);
      expect(statusOf(reading(), week, count(0), 20261017), GoalStatus.missed);
    });

    test('negative net savings follows the same rules', () {
      final laptop = savings(october);
      final progress =
          assess(laptop, october, rials(-200000), const DateKey(20261010));
      expect(progress.status, GoalStatus.atRisk);
      expect(progress.fractionOfTarget, -0.2);
      expect(statusOf(laptop, october, rials(-200000), 20261101),
          GoalStatus.missed);
    });
  });
}
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_domain && dart test test/goals/goal_periods_test.dart test/goals/goal_assess_test.dart`
Expected: both files FAIL to load:
- `goal_periods_test.dart`: `Error: Undefined name 'GoalPeriods'.`
- `goal_assess_test.dart`: `Error: Method not found: 'assess'.`, `Error: Undefined name 'GoalStatus'.`, `Error: Undefined name 'GoalPeriods'.`

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-goal-assess
```

- [ ] **Step 5: Write `GoalStatus` and the progress types**

Create `packages/nimbus_domain/lib/src/goals/goal_status.dart`:

```dart
/// Where a goal stands for one period.
enum GoalStatus {
  /// Today is before the period, or before the goal's own start.
  notStarted,

  /// Open, and nothing to warn about.
  onTrack,

  /// Open: a cap past its lowest alert percent, or a goal behind pace.
  atRisk,

  /// A cap gone over, open or closed.
  exceeded,

  /// A goal reached, or a closed period that stayed within its cap.
  met,

  /// A closed period short of a goal. `exceeded` is a cap's failure, not a
  /// minimum's, so a minimum that fell short needs its own word.
  missed,
}
```

Create `packages/nimbus_domain/lib/src/goals/goal_progress.dart`:

```dart
import 'package:meta/meta.dart';

import '../calendar/date_key.dart';
import 'goal_amount.dart';
import 'goal_status.dart';

/// What a fixed-range goal still needs per month to reach its target.
@immutable
final class RequiredRate {
  const RequiredRate(this.perMonth, this.monthsLeft);

  /// Never below zero. Money is rounded up: it is a minimum to set aside.
  final GoalAmount perMonth;

  /// Calendar months from today's to the range's last, both counted, in the
  /// goal's calendar.
  final int monthsLeft;

  @override
  bool operator ==(Object other) =>
      other is RequiredRate &&
      other.perMonth == perMonth &&
      other.monthsLeft == monthsLeft;

  @override
  int get hashCode => Object.hash(perMonth, monthsLeft);

  @override
  String toString() => 'RequiredRate($perMonth x $monthsLeft months)';
}

/// Where the period is heading. Information only: no status reads it.
@immutable
final class Projection {
  const Projection({required this.projectedEnd, this.requiredRate});

  /// The period's value at its end if the pace so far holds.
  final GoalAmount projectedEnd;

  /// For a fixed range while it is open; null otherwise.
  final RequiredRate? requiredRate;

  @override
  bool operator ==(Object other) =>
      other is Projection &&
      other.projectedEnd == projectedEnd &&
      other.requiredRate == requiredRate;

  @override
  int get hashCode => Object.hash(projectedEnd, requiredRate);

  @override
  String toString() => 'Projection(end $projectedEnd, $requiredRate)';
}

/// How a goal stands for one period: the answer `assess` gives.
@immutable
final class GoalProgress {
  const GoalProgress({
    required this.period,
    required this.current,
    required this.target,
    required this.status,
    required this.fractionOfTarget,
    required this.projection,
  });

  final DateRange period;
  final GoalAmount current;
  final GoalAmount target;
  final GoalStatus status;

  /// [current] / [target]: a ratio, so a double even for money. Negative for
  /// negative net savings; [double.infinity] once a zero target is passed.
  final double fractionOfTarget;

  final Projection projection;

  @override
  bool operator ==(Object other) =>
      other is GoalProgress &&
      other.period == period &&
      other.current == current &&
      other.target == target &&
      other.status == status &&
      other.fractionOfTarget == fractionOfTarget &&
      other.projection == projection;

  @override
  int get hashCode => Object.hash(
      period, current, target, status, fractionOfTarget, projection);

  @override
  String toString() =>
      'GoalProgress(${status.name}, $current of $target over $period, '
      '$projection)';
}
```

- [ ] **Step 6: Write `GoalPeriods`**

Create `packages/nimbus_domain/lib/src/goals/goal_periods.dart`:

```dart
import '../analytics/period_boundaries.dart';
import '../calendar/calendar.dart';
import '../calendar/date_key.dart';
import '../calendar/gregorian_calendar.dart';
import '../calendar/jalali_calendar.dart';
import 'goal.dart';
import 'goal_period.dart';

/// A goal's periods, in the goal's own calendar and week start.
///
/// Every range comes from [PeriodBoundaries]; there is no period arithmetic
/// here. The calendar is the goal's, not the app's, so switching the app to
/// Gregorian does not move a Jalali budget's month.
abstract final class GoalPeriods {
  /// The two-case switch, kept here so Phase 0's `calendar/` is not modified.
  static AppCalendar calendarFor(CalendarKind kind) => switch (kind) {
        CalendarKind.gregorian => const GregorianCalendar(),
        CalendarKind.jalali => const JalaliCalendar(),
      };

  /// The period containing [today]. A fixed range is its own period, before,
  /// during and after it.
  static DateRange current(Goal goal, DateKey today) => switch (goal.period) {
        RecurringPeriod(:final type) => PeriodBoundaries.forPeriod(
            type, today, calendarFor(goal.calendar),
            firstDayOfWeek: goal.weekStart),
        FixedRangePeriod(:final range) => range,
      };

  /// The closed periods, oldest first: from the one containing `since` up to,
  /// not including, the current one.
  ///
  /// Empty for a recurring goal that starts after [today], and always empty
  /// for a fixed range, which is one period with no history behind it.
  static List<DateRange> closed(Goal goal, DateKey today) =>
      switch (goal.period) {
        RecurringPeriod(:final type, :final since) when since <= today =>
          PeriodBoundaries.series(
              type, DateRange(since, today), calendarFor(goal.calendar),
              firstDayOfWeek: goal.weekStart)
            // The last period in the series contains today: the current one.
            ..removeLast(),
        _ => const <DateRange>[],
      };
}
```

- [ ] **Step 7: Write `assess`**

Create `packages/nimbus_domain/lib/src/goals/goal_assess.dart`:

```dart
import '../calendar/date_key.dart';
import 'goal.dart';
import 'goal_amount.dart';
import 'goal_direction.dart';
import 'goal_progress.dart';
import 'goal_status.dart';

/// How [goal] stands for [period], given [current] measured over it, as of
/// [today]. Pure: the same inputs always give the same progress.
///
/// A goal made mid-period counts the whole period: a cap made on the 15th
/// shows what was already spent this month, because the month is what the
/// budget covers. [period] is used as given; nothing here trims it.
GoalProgress assess(
    Goal goal, DateRange period, GoalAmount current, DateKey today) {
  final position = _positionOf(goal, period, today);
  final fraction = current.ratioTo(goal.target);
  return GoalProgress(
    period: period,
    current: current,
    target: goal.target,
    status: _status(
      goal.direction,
      position,
      settled: _settled(goal.direction, current, goal.target),
      warned: _warned(goal, period, current, fraction, today),
    ),
    fractionOfTarget: fraction,
    // A placeholder until Task 4, which projects the pace to the period's end
    // and adds the fixed-range required rate. No status reads it.
    projection: Projection(projectedEnd: current),
  );
}

enum _Position { notStarted, open, closed }

_Position _positionOf(Goal goal, DateRange period, DateKey today) {
  final since = goal.period.startDate;
  final starts =
      since > period.startInclusive ? since : period.startInclusive;
  if (today < starts) return _Position.notStarted;
  if (today > period.endInclusive) return _Position.closed;
  return _Position.open;
}

/// The one status rule, for both directions (spec §2's table).
///
/// [settled] is the event that decides a period before it ends: going over a
/// cap, reaching a goal. [warned] is an open period's warning sign. Each
/// direction names its own words for those outcomes and nothing else.
GoalStatus _status(
  GoalDirection direction,
  _Position position, {
  required bool settled,
  required bool warned,
}) {
  if (position == _Position.notStarted) return GoalStatus.notStarted;
  if (settled) {
    return switch (direction) {
      GoalDirection.atMost => GoalStatus.exceeded,
      GoalDirection.atLeast => GoalStatus.met,
    };
  }
  if (position == _Position.closed) {
    return switch (direction) {
      GoalDirection.atMost => GoalStatus.met,
      GoalDirection.atLeast => GoalStatus.missed,
    };
  }
  return warned ? GoalStatus.atRisk : GoalStatus.onTrack;
}

/// A cap is settled by going over it; a goal by reaching it. Exactly at a
/// cap is still within it.
bool _settled(GoalDirection direction, GoalAmount current, GoalAmount target) {
  final order = current.compareTo(target);
  return switch (direction) {
    GoalDirection.atMost => order > 0,
    GoalDirection.atLeast => order >= 0,
  };
}

/// A cap warns once it reaches its lowest alert percent. It reads the
/// amount, never the pace: rent paid on day one would otherwise project past
/// the cap and hold the month at risk all month.
///
/// A goal warns when behind pace: `current < target x fullDaysElapsed /
/// daysInPeriod`, counting only days before today, so day one with nothing
/// yet is on track. Compared as fractions of the target: a ratio, not money.
bool _warned(Goal goal, DateRange period, GoalAmount current, double fraction,
        DateKey today) =>
    switch (goal.direction) {
      GoalDirection.atMost =>
        current.reaches(goal.target, goal.alertPercents.first),
      GoalDirection.atLeast =>
        fraction < period.startInclusive.daysUntil(today) / period.dayCount,
    };
```

- [ ] **Step 8: Export the new files**

In `packages/nimbus_domain/lib/nimbus_domain.dart`, the goal block becomes (four lines added, each in alphabetical position):

```dart
export 'src/goals/goal.dart';
export 'src/goals/goal_amount.dart';
export 'src/goals/goal_assess.dart';
export 'src/goals/goal_direction.dart';
export 'src/goals/goal_metric.dart';
export 'src/goals/goal_period.dart';
export 'src/goals/goal_periods.dart';
export 'src/goals/goal_progress.dart';
export 'src/goals/goal_scope.dart';
export 'src/goals/goal_status.dart';
```

- [ ] **Step 9: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_domain && dart test test/goals/`
Expected: `+55: All tests passed!` (28 from Task 2, 11 periods, 16 assess).

Then `dart analyze --fatal-infos` from the repo root. Expected: `No issues found!`

- [ ] **Step 10: Run the full gate**

Expected:
- `nimbus_domain` 356 + 27 = **383**: 11 in `goal_periods_test.dart`, 16 in `goal_assess_test.dart`.
- The rest unchanged.

- [ ] **Step 11: Commit and merge**

```bash
git add packages/nimbus_domain
git commit -F - <<'EOF'
feat(goals): GoalPeriods and the assess status rules

GoalPeriods computes a goal's periods through PeriodBoundaries in the
goal's own calendar and week start. Both are the goal's fields, so
switching the app's calendar or week start never moves a goal's
month, and a weekly goal keeps the week it was made with.

assess answers spec section 2's table through one status function
that takes the direction as input. Each direction names only what
settles a period early (over a cap, reaching a goal), what a closed
unsettled period is (met, missed) and its open warning (the lowest
alert percent, behind pace), so the rules exist once. A cap's status
reads the amount, never the pace: rent paid on day one must not hold
a month at risk. A goal made mid-period counts the whole period,
because the month is what a budget covers.

The projection is a placeholder (the current value) until the next
commit. No status reads it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only feat/goal-assess
```

---

### Task 4: Projection and fixed-range run-rate

Branch `feat/goal-projection`, slug `goal-projection`.

**Files:**
- Modify: `packages/nimbus_domain/lib/src/goals/goal_amount.dart` (adds `scaledBy`, `dividedUp`)
- Modify: `packages/nimbus_domain/lib/src/goals/goal_assess.dart` (replaces Task 3's placeholder projection)
- Test: `packages/nimbus_domain/test/goals/goal_values_test.dart`, `packages/nimbus_domain/test/goals/goal_assess_test.dart`

**Interfaces:**
- Consumes: Task 3's `assess`, `GoalPeriods.calendarFor`, `Projection`, `RequiredRate`; `PeriodBoundaries.series`.
- Produces: `GoalAmount.scaledBy(int numerator, int denominator)` (money: integer, half away from zero) and `GoalAmount.dividedUp(int parts)` (money: ceiling); `assess` now fills `projection.projectedEnd` and, for an open fixed range, `projection.requiredRate`.

- [ ] **Step 1: Branch**

```bash
git switch phase/5-goals
git switch -c feat/goal-projection
```

- [ ] **Step 2: Write the failing tests**

In `packages/nimbus_domain/test/goals/goal_values_test.dart`, inside `group('GoalAmount', ...)`, add three tests after `test('a zero target is reached by anything above zero', ...)`:

```dart
    test('scaledBy keeps money integer, rounding half away from zero', () {
      expect(rials(10).scaledBy(1, 4), rials(3)); // 2.5
      expect(rials(-10).scaledBy(1, 4), rials(-3)); // -2.5
      expect(rials(10).scaledBy(1, 3), rials(3)); // 3.33...
      expect(rials(20).scaledBy(1, 3), rials(7)); // 6.66...
      expect(rials(10000).scaledBy(31, 10), rials(31000));
      expect(const QuantityAmount(10).scaledBy(1, 4),
          const QuantityAmount(2.5));
    });

    test('dividedUp rounds money up: it is a minimum to set aside', () {
      expect(rials(10).dividedUp(3), rials(4));
      expect(rials(9).dividedUp(3), rials(3));
      expect(rials(-10).dividedUp(3), rials(-3)); // the ceiling of -3.33...
      expect(const QuantityAmount(10).dividedUp(4), const QuantityAmount(2.5));
    });

    test('scaling or dividing by nothing is refused', () {
      // A quantity would otherwise turn into infinity without a word.
      expect(() => rials(10).scaledBy(1, 0), throwsArgumentError);
      expect(
          () => const QuantityAmount(1).scaledBy(1, -2), throwsArgumentError);
      expect(() => rials(10).dividedUp(0), throwsArgumentError);
      expect(() => const QuantityAmount(1).dividedUp(0), throwsArgumentError);
    });
```

In `packages/nimbus_domain/test/goals/goal_assess_test.dart`, add this group at the end of `main`, after `group('both directions', ...)`. It reuses the file's `cap`, `reading`, `savings`, `october` and `week`; the Jalali dates in its comments were computed with `JalaliCalendar.keyOf`:

```dart
  group('projection', () {
    GoalAmount projectedEnd(
            Goal goal, DateRange period, GoalAmount current, int today) =>
        assess(goal, period, current, DateKey(today)).projection.projectedEnd;
    RequiredRate? requiredRate(
            Goal goal, DateRange period, GoalAmount current, int today) =>
        assess(goal, period, current, DateKey(today)).projection.requiredRate;

    test('an open period projects its pace to the end', () {
      // Ten days of October, today included, at 1 000 a day: 31 000.
      expect(
          assess(cap(), october, rials(10000), const DateKey(20261010))
              .projection,
          Projection(projectedEnd: rials(31000)));
    });

    test('a money projection rounds half away from zero', () {
      // Two days into a seven-day range: 5 x 7 / 2 = 17.5, and -17.5.
      final thisWeek = savings(week);
      expect(projectedEnd(thisWeek, week, rials(5), 20261011), rials(18));
      expect(projectedEnd(thisWeek, week, rials(-5), 20261011), rials(-18));
    });

    test('a quantity projection is not rounded', () {
      // 2.5 sessions in two days of a seven-day week.
      expect(projectedEnd(reading(), week, count(2.5), 20261011), count(8.75));
    });

    test('not started projects zero; closed projects what happened', () {
      // The cap starting on the 20th has 9 000 in its month already, but has
      // not started: nothing is projected from before it began.
      expect(projectedEnd(cap(since: 20261020), october, rials(9000), 20261015),
          rials(0));
      expect(projectedEnd(cap(), october, rials(9000), 20261101), rials(9000));
    });

    test('a projection past the cap does not change the status', () {
      // Information only: 5 000 on day one projects to 155 000.
      final progress =
          assess(cap(), october, rials(5000), const DateKey(20261001));
      expect(progress.projection.projectedEnd, rials(155000));
      expect(progress.status, GoalStatus.onTrack);
    });

    test('months left count the current one, across New Year', () {
      // 15 December 2026 to 28 February 2027 touches three Gregorian months.
      // 1 000 000 / 3 rounds up: a minimum to set aside.
      final between = range(20261101, 20270228);
      final laptop = savings(between);
      expect(requiredRate(laptop, between, rials(0), 20261215),
          RequiredRate(rials(333334), 3));
      // On the last day, what is left is due this month.
      expect(requiredRate(laptop, between, rials(400000), 20270228),
          RequiredRate(rials(600000), 1));
    });

    test("months left are counted in the goal's calendar", () {
      // 1 Dey 1404 (2025-12-22) to 10 Ordibehesht 1405 (2026-04-30), seen on
      // 25 Esfand 1404 (2026-03-16): Esfand, Farvardin and Ordibehesht are
      // three Jalali months, but the same days touch only March and April.
      final between = range(20251222, 20260430);
      final gregorian = savings(between);
      final jalali = gregorian.copyWith(calendar: CalendarKind.jalali);
      expect(requiredRate(jalali, between, rials(100000), 20260316),
          RequiredRate(rials(300000), 3));
      expect(requiredRate(gregorian, between, rials(100000), 20260316),
          RequiredRate(rials(450000), 2));
    });

    test('the required rate is zero once the target is passed', () {
      final between = range(20261101, 20270228);
      final progress = assess(
          savings(between), between, rials(1200000), const DateKey(20261215));
      expect(progress.status, GoalStatus.met);
      expect(progress.projection.requiredRate, RequiredRate(rials(0), 3));
    });

    test('only an open fixed range has a required rate', () {
      final between = range(20261101, 20270228);
      final laptop = savings(between);
      expect(requiredRate(laptop, between, rials(0), 20261010), isNull,
          reason: 'not started');
      expect(requiredRate(laptop, between, rials(0), 20270301), isNull,
          reason: 'closed');
      expect(requiredRate(cap(), october, rials(0), 20261010), isNull,
          reason: 'recurring');
    });
  });
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_domain && dart test test/goals/goal_values_test.dart`
Expected: FAIL to load: `Error: The method 'scaledBy' isn't defined for the type 'MoneyAmount'.` (and `dividedUp`).

Run: `cd packages/nimbus_domain && dart test test/goals/goal_assess_test.dart`
Expected: `+17 -8: Some tests failed.` The 8 failures are the projection tests (the placeholder projects `current`, and has no rate). `only an open fixed range has a required rate` already passes, because the placeholder never sets a rate; it stays to pin that the rate appears nowhere else.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-goal-projection
```

- [ ] **Step 5: Add `scaledBy` and `dividedUp` to `GoalAmount`**

In `packages/nimbus_domain/lib/src/goals/goal_amount.dart`:

1. In `sealed class GoalAmount`, after `bool reaches(GoalAmount target, int percent);`, add:

```dart

  /// This amount x [numerator] / [denominator]. Money stays integer, rounded
  /// half away from zero. Throws [ArgumentError] unless [denominator] is
  /// positive.
  GoalAmount scaledBy(int numerator, int denominator);

  /// This amount split into [parts] equal shares. Money rounds up (the
  /// ceiling): it is a minimum to set aside, and rounding down would leave the
  /// target short. Throws [ArgumentError] unless [parts] is positive.
  GoalAmount dividedUp(int parts);
```

2. In `MoneyAmount`, after its `reaches` method and before `operator ==`, add:

```dart
  @override
  MoneyAmount scaledBy(int numerator, int denominator) {
    _checkPositive(denominator, 'denominator');
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

```

3. In `QuantityAmount`, after its `reaches` method and before `operator ==`, add:

```dart
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

```

4. At the end of the file, after `_ratioToZero`, add:

```dart

void _checkPositive(int value, String name) {
  if (value <= 0) throw ArgumentError.value(value, name, 'must be positive');
}
```

`minorUnits * numerator` is plain 64-bit arithmetic. The numerator is the period's day count (366 at most for a recurring period), so it overflows only for a balance above 2.5 x 10^15 minor units on a decade-long fixed range.

- [ ] **Step 6: Project the pace in `assess`**

Replace `packages/nimbus_domain/lib/src/goals/goal_assess.dart` with the version below. Against Task 3 it adds four imports, replaces the placeholder `projection:` argument, and adds `_projectedEnd` and `_requiredRate`; the status code is unchanged.

```dart
import '../analytics/period_boundaries.dart';
import '../calendar/calendar.dart';
import '../calendar/date_key.dart';
import 'goal.dart';
import 'goal_amount.dart';
import 'goal_direction.dart';
import 'goal_period.dart';
import 'goal_periods.dart';
import 'goal_progress.dart';
import 'goal_status.dart';

/// How [goal] stands for [period], given [current] measured over it, as of
/// [today]. Pure: the same inputs always give the same progress.
///
/// A goal made mid-period counts the whole period: a cap made on the 15th
/// shows what was already spent this month, because the month is what the
/// budget covers. [period] is used as given; nothing here trims it.
GoalProgress assess(
    Goal goal, DateRange period, GoalAmount current, DateKey today) {
  final position = _positionOf(goal, period, today);
  final fraction = current.ratioTo(goal.target);
  return GoalProgress(
    period: period,
    current: current,
    target: goal.target,
    status: _status(
      goal.direction,
      position,
      settled: _settled(goal.direction, current, goal.target),
      warned: _warned(goal, period, current, fraction, today),
    ),
    fractionOfTarget: fraction,
    projection: Projection(
      projectedEnd: _projectedEnd(position, period, current, today),
      requiredRate: _requiredRate(goal, position, period, current, today),
    ),
  );
}

/// `current / daysElapsedIncludingToday x daysInPeriod` while open. Nothing is
/// projected before the goal starts, and a closed period ends where it ended.
GoalAmount _projectedEnd(_Position position, DateRange period,
        GoalAmount current, DateKey today) =>
    switch (position) {
      _Position.notStarted => current.zero,
      _Position.open => current.scaledBy(
          period.dayCount, period.startInclusive.daysUntil(today) + 1),
      _Position.closed => current,
    };

/// What an open fixed range still needs each month, counting today's month
/// and the range's last in the goal's own calendar: Esfand to Ordibehesht is
/// three Jalali months but two Gregorian ones.
RequiredRate? _requiredRate(Goal goal, _Position position, DateRange period,
    GoalAmount current, DateKey today) {
  if (goal.period is! FixedRangePeriod || position != _Position.open) {
    return null;
  }
  final monthsLeft = PeriodBoundaries.series(
          PeriodType.month,
          DateRange(today, period.endInclusive),
          GoalPeriods.calendarFor(goal.calendar))
      .length;
  final perMonth = (goal.target - current).dividedUp(monthsLeft);
  return RequiredRate(
      perMonth.isNegative ? perMonth.zero : perMonth, monthsLeft);
}

enum _Position { notStarted, open, closed }

_Position _positionOf(Goal goal, DateRange period, DateKey today) {
  final since = goal.period.startDate;
  final starts =
      since > period.startInclusive ? since : period.startInclusive;
  if (today < starts) return _Position.notStarted;
  if (today > period.endInclusive) return _Position.closed;
  return _Position.open;
}

/// The one status rule, for both directions (spec §2's table).
///
/// [settled] is the event that decides a period before it ends: going over a
/// cap, reaching a goal. [warned] is an open period's warning sign. Each
/// direction names its own words for those outcomes and nothing else.
GoalStatus _status(
  GoalDirection direction,
  _Position position, {
  required bool settled,
  required bool warned,
}) {
  if (position == _Position.notStarted) return GoalStatus.notStarted;
  if (settled) {
    return switch (direction) {
      GoalDirection.atMost => GoalStatus.exceeded,
      GoalDirection.atLeast => GoalStatus.met,
    };
  }
  if (position == _Position.closed) {
    return switch (direction) {
      GoalDirection.atMost => GoalStatus.met,
      GoalDirection.atLeast => GoalStatus.missed,
    };
  }
  return warned ? GoalStatus.atRisk : GoalStatus.onTrack;
}

/// A cap is settled by going over it; a goal by reaching it. Exactly at a
/// cap is still within it.
bool _settled(GoalDirection direction, GoalAmount current, GoalAmount target) {
  final order = current.compareTo(target);
  return switch (direction) {
    GoalDirection.atMost => order > 0,
    GoalDirection.atLeast => order >= 0,
  };
}

/// A cap warns once it reaches its lowest alert percent. It reads the
/// amount, never the pace: rent paid on day one would otherwise project past
/// the cap and hold the month at risk all month.
///
/// A goal warns when behind pace: `current < target x fullDaysElapsed /
/// daysInPeriod`, counting only days before today, so day one with nothing
/// yet is on track. Compared as fractions of the target: a ratio, not money.
bool _warned(Goal goal, DateRange period, GoalAmount current, double fraction,
        DateKey today) =>
    switch (goal.direction) {
      GoalDirection.atMost =>
        current.reaches(goal.target, goal.alertPercents.first),
      GoalDirection.atLeast =>
        fraction < period.startInclusive.daysUntil(today) / period.dayCount,
    };
```

- [ ] **Step 7: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_domain && dart test test/goals/`
Expected: `+67: All tests passed!`

Then `dart analyze --fatal-infos` from the repo root. Expected: `No issues found!`

- [ ] **Step 8: Run the full gate**

Expected:
- `nimbus_domain` 383 + 12 = **395**: 3 in `goal_values_test.dart`, 9 in `goal_assess_test.dart`.
- The rest unchanged.

- [ ] **Step 9: Commit and merge**

```bash
git add packages/nimbus_domain
git commit -F - <<'EOF'
feat(goals): projection and the fixed-range required rate

The detail screen's pace line and a savings card's "per month for N
more months" need where a period is heading. projectedEnd scales the
pace so far, today included, to the period's length; money stays
integer, rounded half away from zero. Before the goal starts nothing
is projected, and a closed period ends where it ended.

The required rate divides what is left by the months left, counted
with PeriodBoundaries in the goal's own calendar: Esfand to
Ordibehesht is three Jalali months but two Gregorian ones. It rounds
up, because it is a minimum to set aside, and floors at zero once
the target is passed.

Status still never reads the projection: half a cap spent on day one
projects far past it and is on track.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only feat/goal-projection
```

---

### Task 5: `foldDaily`, `GoalStreaks`, `crossing`

Branch `feat/goal-crossing`, slug `goal-crossing`.

**Files:**
- Create: `packages/nimbus_domain/lib/src/goals/goal_fold.dart`
- Create: `packages/nimbus_domain/lib/src/goals/goal_streaks.dart`
- Create: `packages/nimbus_domain/lib/src/goals/goal_alert.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart`
- Test: `packages/nimbus_domain/test/goals/goal_fold_test.dart`, `goal_streaks_test.dart`, `goal_alert_test.dart` (all new, same directory)

**Interfaces:**
- Consumes: `GoalAmount` (`+`, `reaches`), `GoalProgress`, `GoalStatus`, `Goal.alertPercents` / `target` / `direction`, `assess` (tests only).
- Produces: `foldDaily(Map<DateKey, GoalAmount>, List<DateRange>, GoalAmount zero)`; `PeriodOutcome`; `GoalStreaks` with `of`, `none`; `GoalAlert`; `CrossingResult`; `reachedPercent(Goal, GoalAmount)`; `crossing(Goal, GoalProgress, int?)`.

`crossing` reduces spec §2's three cases to one rule: **the new state is always the percent reached**; an alert fires only when that is above the stored state. Equal leaves the state as it was (recomputation never re-fires); lower lowers it (a genuine re-crossing warns again).

- [ ] **Step 1: Branch**

```bash
git switch phase/5-goals
git switch -c feat/goal-crossing
```

- [ ] **Step 2: Write the failing tests**

Create `packages/nimbus_domain/test/goals/goal_fold_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

MoneyAmount rials(int minor) => MoneyAmount(Money(minor));
DateRange range(int start, int end) => DateRange(DateKey(start), DateKey(end));

void main() {
  // Three Saturday-start weeks.
  final weeks = [
    range(20261003, 20261009),
    range(20261010, 20261016),
    range(20261017, 20261023),
  ];

  test('each period sums its own days; a period with none is zero', () {
    final daily = <DateKey, GoalAmount>{
      const DateKey(20261003): rials(100),
      const DateKey(20261009): rials(50), // the first week's last day
      const DateKey(20261017): rials(-30), // net savings can go negative
      const DateKey(20261023): rials(10),
    };
    expect(foldDaily(daily, weeks, rials(0)),
        [rials(150), rials(0), rials(-20)]);
  });

  test('days outside every period are ignored', () {
    final daily = <DateKey, GoalAmount>{
      const DateKey(20261002): rials(999),
      const DateKey(20261010): rials(5),
      const DateKey(20261024): rials(999),
    };
    expect(foldDaily(daily, weeks, rials(0)), [rials(0), rials(5), rials(0)]);
  });

  test('quantities fold the same way, and never mix with money', () {
    final daily = <DateKey, GoalAmount>{
      const DateKey(20261011): const QuantityAmount(2),
      const DateKey(20261012): const QuantityAmount(1.5),
    };
    expect(foldDaily(daily, weeks, const QuantityAmount(0)), [
      const QuantityAmount(0),
      const QuantityAmount(3.5),
      const QuantityAmount(0),
    ]);
    // A measurer that answered in the wrong subtype is a bug to surface.
    expect(() => foldDaily(daily, weeks, rials(0)), throwsArgumentError);
  });
}
```

Create `packages/nimbus_domain/test/goals/goal_streaks_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

/// Consecutive weeks, oldest first, with the given statuses. Only the order
/// matters to a streak.
List<PeriodOutcome> weeks(List<GoalStatus> statuses) => [
      for (final (i, status) in statuses.indexed) _week(i, status),
    ];

PeriodOutcome _week(int index, GoalStatus status) {
  final start = const DateKey(20260103).addDays(7 * index);
  return PeriodOutcome(
      DateRange(start, start.addDays(6)), const QuantityAmount(0), status);
}

void main() {
  test('no closed periods, no streak', () {
    expect(GoalStreaks.of(const []), GoalStreaks.none);
  });

  test('current is the trailing run of met; best the longest anywhere', () {
    expect(
        GoalStreaks.of(weeks([
          GoalStatus.met,
          GoalStatus.met,
          GoalStatus.met,
          GoalStatus.missed,
          GoalStatus.met,
          GoalStatus.met,
        ])),
        const GoalStreaks(current: 2, best: 3));
  });

  test('a closed period that was not met ends the current streak', () {
    expect(
        GoalStreaks.of(
            weeks([GoalStatus.met, GoalStatus.met, GoalStatus.exceeded])),
        const GoalStreaks(current: 0, best: 2));
    expect(GoalStreaks.of(weeks([GoalStatus.met, GoalStatus.missed])),
        const GoalStreaks(current: 0, best: 1));
  });

  test('best is never less than current', () {
    expect(
        GoalStreaks.of(weeks([
          GoalStatus.missed,
          GoalStatus.met,
          GoalStatus.met,
          GoalStatus.met,
        ])),
        const GoalStreaks(current: 3, best: 3));
  });
}
```

Create `packages/nimbus_domain/test/goals/goal_alert_test.dart`. The last-but-one test is Review Focus 3's domain pin:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

MoneyAmount rials(int minor) => MoneyAmount(Money(minor));
QuantityAmount count(double n) => QuantityAmount(n);
DateRange range(int start, int end) => DateRange(DateKey(start), DateKey(end));

/// A tracker goal; [target] and [direction] are what vary.
Goal trackerGoal(String id, GoalDirection direction, double target,
        PeriodType type) =>
    Goal(
      id: id,
      name: id,
      metric: GoalMetric.trackerCount,
      scope: TrackerScope(id),
      direction: direction,
      target: count(target),
      period: RecurringPeriod(type, const DateKey(20260101)),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.saturday,
    );

void main() {
  final october = range(20261001, 20261031);
  // 10 000 a month, alerts at 80 and 100.
  final cap = Goal(
    id: 'cap',
    name: 'Dining out',
    metric: GoalMetric.moneySum,
    scope: MoneyScope(const QueryFilters(direction: MoneyDirection.expense)),
    direction: GoalDirection.atMost,
    target: rials(10000),
    period: const RecurringPeriod(PeriodType.month, DateKey(20260101)),
    calendar: CalendarKind.gregorian,
    weekStart: DateTime.saturday,
  );

  GoalProgress progressOf(Goal goal, GoalAmount current,
          {DateRange? period, int today = 20261010}) =>
      assess(goal, period ?? october, current, DateKey(today));
  CrossingResult crossCap(GoalAmount current, int? lastAlerted) =>
      crossing(cap, progressOf(cap, current), lastAlerted);

  test('the first crossing alerts once, at the percent reached', () {
    final progress = progressOf(cap, rials(8000));
    final result = crossing(cap, progress, null);
    expect(result.lastAlerted, 80);
    expect(
        result.alert,
        GoalAlert(
          goalId: 'cap',
          goalName: 'Dining out',
          period: october,
          percent: 80,
          direction: GoalDirection.atMost,
          progress: progress,
        ));
  });

  test('recomputing at the same level never re-fires', () {
    // Every save re-evaluates the current period. A crossing already
    // recorded stays recorded, however often the value is recomputed.
    expect(crossCap(rials(8000), 80), const CrossingResult(null, 80));
    expect(crossCap(rials(9500), 80), const CrossingResult(null, 80));
    expect(crossCap(rials(12000), 100), const CrossingResult(null, 100));
  });

  test('a drop below a threshold, then a genuine re-crossing, warns again', () {
    // The expense that crossed 80% was deleted; a later one crosses again.
    final dropped = crossCap(rials(7000), 80);
    expect(dropped, const CrossingResult(null, null));
    final again = crossCap(rials(8200), dropped.lastAlerted);
    expect(again.alert?.percent, 80);
    expect(again.lastAlerted, 80);
    // The same one level up: back under 100 lowers the state to 80.
    final back = crossCap(rials(9000), 100);
    expect(back, const CrossingResult(null, 80));
    expect(crossCap(rials(10000), back.lastAlerted).alert?.percent, 100);
  });

  test('a jump over two thresholds alerts once, at the highest', () {
    // 70% to 105% in one save: one alert, at 100, not one per threshold.
    final result = crossCap(rials(10500), null);
    expect(result.alert?.percent, 100);
    expect(result.lastAlerted, 100);
  });

  test('falling below every threshold resets to null, without an alert', () {
    expect(crossCap(rials(100), 100), const CrossingResult(null, null));
  });

  test('money is compared exactly at the threshold', () {
    expect(reachedPercent(cap, rials(7999)), isNull);
    expect(reachedPercent(cap, rials(8000)), 80);
    expect(reachedPercent(cap, rials(9999)), 80);
    expect(reachedPercent(cap, rials(10000)), 100);
  });

  test('a zero atMost target: anything at all reaches every percent', () {
    final none = trackerGoal('cig', GoalDirection.atMost, 0, PeriodType.day);
    final today = range(20261010, 20261010);
    expect(reachedPercent(none, count(0)), isNull);
    expect(reachedPercent(none, count(1)), 100);
    expect(
        crossing(none, progressOf(none, count(1), period: today), null)
            .alert
            ?.percent,
        100);
  });

  test('a new period starts from no alert state', () {
    // Midnight with the app open (Review Focus 3). Yesterday's row holds 100;
    // today's period has a row of its own with nothing recorded yet, so the
    // first crossing today alerts, and names today.
    final limit = trackerGoal('cig', GoalDirection.atMost, 10, PeriodType.day);
    final yesterday = range(20261009, 20261009);
    final today = range(20261010, 20261010);
    final last = crossing(limit,
        progressOf(limit, count(12), period: yesterday, today: 20261009), null);
    expect(last.lastAlerted, 100);
    final first = crossing(limit,
        progressOf(limit, count(8), period: today, today: 20261010), null);
    expect(first.alert?.percent, 80);
    expect(first.alert?.period, today);
  });

  test('a goal to reach alerts as it climbs, with its own direction', () {
    final gym = trackerGoal('gym', GoalDirection.atLeast, 5, PeriodType.week);
    final week = range(20261010, 20261016);
    final four = crossing(
        gym, progressOf(gym, count(4), period: week, today: 20261014), null);
    expect(four.alert?.percent, 80);
    expect(four.alert?.direction, GoalDirection.atLeast);
    final five = crossing(gym,
        progressOf(gym, count(5), period: week, today: 20261015),
        four.lastAlerted);
    expect(five.alert?.percent, 100);
  });
}
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_domain && dart test test/goals/goal_fold_test.dart test/goals/goal_streaks_test.dart test/goals/goal_alert_test.dart`
Expected: all three FAIL to load:
- fold: `Error: Method not found: 'foldDaily'.`
- streaks: `Error: Type 'PeriodOutcome' not found.`, `Error: Undefined name 'GoalStreaks'.`
- alert: `Error: Method not found: 'crossing'.`, `Error: Method not found: 'reachedPercent'.`, `Error: Couldn't find constructor 'CrossingResult'.`

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-goal-crossing
```

- [ ] **Step 5: Write `foldDaily`**

Create `packages/nimbus_domain/lib/src/goals/goal_fold.dart`:

```dart
import '../calendar/date_key.dart';
import 'goal_amount.dart';

/// One amount per period in [periods], in the same order: the sum of
/// [daily]'s entries that fall in it.
///
/// History is measured by day and folded here, in Dart, because the engine's
/// week grouping cannot honour a goal's own week start. Days with no entry
/// contribute nothing, so a period without data is [zero], which also fixes
/// the subtype of an empty answer. Each period's days are walked once, so the
/// cost is the days covered, not days times periods.
List<GoalAmount> foldDaily(Map<DateKey, GoalAmount> daily,
        List<DateRange> periods, GoalAmount zero) =>
    [for (final period in periods) _sumOver(daily, period, zero)];

GoalAmount _sumOver(
    Map<DateKey, GoalAmount> daily, DateRange period, GoalAmount zero) {
  var total = zero;
  for (var day = period.startInclusive;
      day <= period.endInclusive;
      day = day.addDays(1)) {
    final amount = daily[day];
    if (amount != null) total += amount;
  }
  return total;
}
```

- [ ] **Step 6: Write `PeriodOutcome` and `GoalStreaks`**

Create `packages/nimbus_domain/lib/src/goals/goal_streaks.dart`:

```dart
import 'package:meta/meta.dart';

import '../calendar/date_key.dart';
import 'goal_amount.dart';
import 'goal_status.dart';

/// How one closed period ended: its value and the status `assess` gave it.
@immutable
final class PeriodOutcome {
  const PeriodOutcome(this.period, this.value, this.status);

  final DateRange period;
  final GoalAmount value;
  final GoalStatus status;

  @override
  bool operator ==(Object other) =>
      other is PeriodOutcome &&
      other.period == period &&
      other.value == value &&
      other.status == status;

  @override
  int get hashCode => Object.hash(period, value, status);

  @override
  String toString() => 'PeriodOutcome($period, $value, ${status.name})';
}

/// Runs of `met` periods in a recurring goal's history.
@immutable
final class GoalStreaks {
  const GoalStreaks({required this.current, required this.best});

  /// Reads [outcomes]: closed periods only, oldest first. [current] is the
  /// run of `met` ending at the most recent one; [best] the longest anywhere,
  /// so never less than [current].
  factory GoalStreaks.of(List<PeriodOutcome> outcomes) {
    var run = 0;
    var best = 0;
    for (final outcome in outcomes) {
      run = outcome.status == GoalStatus.met ? run + 1 : 0;
      if (run > best) best = run;
    }
    return GoalStreaks(current: run, best: best);
  }

  static const none = GoalStreaks(current: 0, best: 0);

  final int current;
  final int best;

  @override
  bool operator ==(Object other) =>
      other is GoalStreaks && other.current == current && other.best == best;

  @override
  int get hashCode => Object.hash(current, best);

  @override
  String toString() => 'GoalStreaks(current $current, best $best)';
}
```

- [ ] **Step 7: Write `GoalAlert`, `CrossingResult`, `reachedPercent` and `crossing`**

Create `packages/nimbus_domain/lib/src/goals/goal_alert.dart`. The early return is what lets `reached` promote to `int` for the alert:

```dart
import 'package:meta/meta.dart';

import '../calendar/date_key.dart';
import 'goal.dart';
import 'goal_amount.dart';
import 'goal_direction.dart';
import 'goal_progress.dart';

/// A goal crossed one of its alert percents. Data only: the app words it.
@immutable
final class GoalAlert {
  const GoalAlert({
    required this.goalId,
    required this.goalName,
    required this.period,
    required this.percent,
    required this.direction,
    required this.progress,
  });

  final String goalId;
  final String goalName;
  final DateRange period;
  final int percent;
  final GoalDirection direction;
  final GoalProgress progress;

  @override
  bool operator ==(Object other) =>
      other is GoalAlert &&
      other.goalId == goalId &&
      other.goalName == goalName &&
      other.period == period &&
      other.percent == percent &&
      other.direction == direction &&
      other.progress == progress;

  @override
  int get hashCode =>
      Object.hash(goalId, goalName, period, percent, direction, progress);

  @override
  String toString() =>
      'GoalAlert($goalId, $percent% ${direction.name}, $period)';
}

/// What `crossing` decided: the alert to show, if any, and the period's new
/// alert state to store.
@immutable
final class CrossingResult {
  const CrossingResult(this.alert, this.lastAlerted);

  final GoalAlert? alert;
  final int? lastAlerted;

  @override
  bool operator ==(Object other) =>
      other is CrossingResult &&
      other.alert == alert &&
      other.lastAlerted == lastAlerted;

  @override
  int get hashCode => Object.hash(alert, lastAlerted);

  @override
  String toString() => 'CrossingResult($alert, last $lastAlerted)';
}

/// The highest of [goal]'s alert percents that [current] reaches against its
/// target, or null below them all. Money compares exactly; a zero target is
/// reached, at every percent, by anything above zero.
int? reachedPercent(Goal goal, GoalAmount current) {
  for (final percent in goal.alertPercents.reversed) {
    if (current.reaches(goal.target, percent)) return percent;
  }
  return null;
}

/// Whether [progress] crosses a new alert percent, given the period's
/// [lastAlerted] state (null: nothing recorded).
///
/// - Reached above the state: one alert, for the highest percent reached. A
///   jump from 70% to 105% alerts once, at 100.
/// - Otherwise no alert, and the state follows what is reached: the same
///   level leaves it as it was, so recomputation never re-fires, and a drop
///   lowers it, so a genuine re-crossing warns again.
CrossingResult crossing(Goal goal, GoalProgress progress, int? lastAlerted) {
  final reached = reachedPercent(goal, progress.current);
  if (reached == null || (lastAlerted != null && reached <= lastAlerted)) {
    return CrossingResult(null, reached);
  }
  return CrossingResult(
    GoalAlert(
      goalId: goal.id,
      goalName: goal.name,
      period: progress.period,
      percent: reached,
      direction: goal.direction,
      progress: progress,
    ),
    reached,
  );
}
```

- [ ] **Step 8: Export the new files**

The barrel's goal block becomes:

```dart
export 'src/goals/goal.dart';
export 'src/goals/goal_alert.dart';
export 'src/goals/goal_amount.dart';
export 'src/goals/goal_assess.dart';
export 'src/goals/goal_direction.dart';
export 'src/goals/goal_fold.dart';
export 'src/goals/goal_metric.dart';
export 'src/goals/goal_period.dart';
export 'src/goals/goal_periods.dart';
export 'src/goals/goal_progress.dart';
export 'src/goals/goal_scope.dart';
export 'src/goals/goal_status.dart';
export 'src/goals/goal_streaks.dart';
```

- [ ] **Step 9: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_domain && dart test test/goals/`
Expected: `+83: All tests passed!`

Then `dart analyze --fatal-infos` from the repo root. Expected: `No issues found!`

- [ ] **Step 10: Run the full gate**

Expected:
- `nimbus_domain` 395 + 16 = **411**: 3 fold, 4 streaks, 9 alert.
- The rest unchanged.

- [ ] **Step 11: Commit and merge**

```bash
git add packages/nimbus_domain
git commit -F - <<'EOF'
feat(goals): foldDaily, streaks and alert crossings

History is measured by day and folded into the goal's periods in
Dart, because the engine's week grouping ignores the week start. A
day with no entry contributes zero, and a measurer answering in the
wrong subtype throws rather than adding rials to cigarettes. Streaks
read the folded outcomes: the trailing run of met periods, and the
best.

crossing decides whether one evaluation crosses a new alert percent,
given the state stored for that period. The new state is always the
percent reached; an alert fires only when that rises above the
state. So a jump past two thresholds alerts once, recomputation never
re-fires, and a drop lowers the state so a genuine re-crossing warns
again. State belongs to one period, so a new day's or month's first
crossing alerts even when the last period ended at 100.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only feat/goal-crossing
```

---

### Task 6: `GoalMeasurer`, `GoalEngine`, the kind-free grep test

Branch `feat/goal-engine`, slug `goal-engine`.

**Files:**
- Create: `packages/nimbus_domain/lib/src/goals/goal_measurer.dart`
- Create: `packages/nimbus_domain/lib/src/goals/goal_engine.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart`
- Modify: `test/architecture_test.dart` (**Phase 0's file**; the commit message says so, CONVENTIONS §3)
- Test: `packages/nimbus_domain/test/goals/goal_engine_test.dart` (new), `packages/nimbus_domain/test/goals/support/fake_measurer.dart` (new)

**Interfaces:**
- Consumes: `assess`, `GoalPeriods.current`, `foldDaily` (the fake), the value types.
- Produces: `abstract interface class GoalMeasurer` (`measure`, `measureDaily`); `GoalEngine(GoalMeasurer, {required DateKey Function() today})` with `measurer`, `today()`, `evaluate(Goal, DateRange)`, `evaluateCurrent(Goal)` (contract note 1 on how the constructor is written); test support `FakeMeasurer(Map<DateKey, GoalAmount> daily, {Exception? failure})` with `measured`. Task 7 implements `GoalMeasurer` in `nimbus_data`.

- [ ] **Step 1: Branch**

```bash
git switch phase/5-goals
git switch -c feat/goal-engine
```

- [ ] **Step 2: Write the failing tests**

Create `packages/nimbus_domain/test/goals/support/fake_measurer.dart`. `failure` is an `Exception?`, not an `Object?`: the `only_throw_errors` lint rejects throwing a value whose static type is neither.

```dart
import 'package:nimbus_domain/nimbus_domain.dart';

/// A [GoalMeasurer] over a fixed day-by-day table, recording what it is
/// asked.
///
/// [measure] folds the same table [measureDaily] serves, so the two cannot
/// disagree the way two hand-written answers could.
final class FakeMeasurer implements GoalMeasurer {
  FakeMeasurer(this.daily, {this.failure});

  final Map<DateKey, GoalAmount> daily;

  /// Thrown by every call when set.
  final Exception? failure;

  /// Every [measure] call, in order.
  final measured = <({GoalMetric metric, GoalScope scope, DateRange range})>[];

  @override
  Future<GoalAmount> measure(
      GoalMetric metric, GoalScope scope, DateRange range) async {
    measured.add((metric: metric, scope: scope, range: range));
    final failure = this.failure;
    if (failure != null) throw failure;
    final zero = metric.isMoney
        ? const MoneyAmount(Money.zero)
        : const QuantityAmount(0);
    return foldDaily(daily, [range], zero).single;
  }

  @override
  Future<Map<DateKey, GoalAmount>> measureDaily(
      GoalMetric metric, GoalScope scope, DateRange span) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    return {
      for (final MapEntry(:key, :value) in daily.entries)
        if (span.contains(key)) key: value,
    };
  }
}
```

Create `packages/nimbus_domain/test/goals/goal_engine_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/fake_measurer.dart';

MoneyAmount rials(int minor) => MoneyAmount(Money(minor));
DateRange range(int start, int end) => DateRange(DateKey(start), DateKey(end));

// Computed with JalaliCalendar.keyOf:
//   Shahrivar 1405 = 2026-08-23 .. 2026-09-22
//   Mehr 1405      = 2026-09-23 .. 2026-10-22 (30 Mehr = 2026-10-22)
final shahrivar = range(20260823, 20260922);
final mehr = range(20260923, 20261022);

void main() {
  // A Jalali cap of 10 000 a month.
  final cap = Goal(
    id: 'cap',
    name: 'Dining out',
    metric: GoalMetric.moneySum,
    scope: MoneyScope(const QueryFilters(direction: MoneyDirection.expense)),
    direction: GoalDirection.atMost,
    target: rials(10000),
    period: const RecurringPeriod(PeriodType.month, DateKey(20260101)),
    calendar: CalendarKind.jalali,
    weekStart: DateTime.saturday,
  );
  final daily = <DateKey, GoalAmount>{
    const DateKey(20260920): rials(4000), // 29 Shahrivar
    const DateKey(20260923): rials(3000), // 1 Mehr
    const DateKey(20261010): rials(6000), // 18 Mehr
  };

  test('evaluate measures the period it is given, then assesses it', () async {
    final measurer = FakeMeasurer(daily);
    final engine = GoalEngine(measurer, today: () => const DateKey(20261010));
    final progress = await engine.evaluate(cap, shahrivar);
    expect(measurer.measured, [
      (metric: GoalMetric.moneySum, scope: cap.scope, range: shahrivar),
    ]);
    expect(progress,
        assess(cap, shahrivar, rials(4000), const DateKey(20261010)));
    expect(progress.status, GoalStatus.met);
  });

  test("evaluateCurrent measures the goal's current period, in its calendar",
      () async {
    final engine =
        GoalEngine(FakeMeasurer(daily), today: () => const DateKey(20261010));
    final progress = await engine.evaluateCurrent(cap);
    // Mehr, not October: the goal is Jalali whatever the app shows.
    expect(progress.period, mehr);
    expect(progress.current, rials(9000));
    expect(progress.status, GoalStatus.atRisk);
  });

  test('today is read once, so an evaluation cannot straddle midnight',
      () async {
    // The clock turns from 30 Mehr to 1 Aban between two reads. Read twice,
    // Mehr would be measured and then assessed as if it had closed: met,
    // instead of at risk.
    final days = [const DateKey(20261022), const DateKey(20261023)];
    var reads = 0;
    final engine =
        GoalEngine(FakeMeasurer(daily), today: () => days[reads++]);
    final progress = await engine.evaluateCurrent(cap);
    expect(reads, 1);
    expect(progress.period, mehr);
    expect(progress.status, GoalStatus.atRisk);
  });

  test('a measurer failure reaches the caller', () async {
    // Never a silent zero: a cap reading zero after a database error would
    // tell the user they are under budget.
    final failure = Exception('database is locked');
    final engine = GoalEngine(FakeMeasurer(daily, failure: failure),
        today: () => const DateKey(20261010));
    await expectLater(engine.evaluateCurrent(cap), throwsA(same(failure)));
  });
}
```

Append to `test/architecture_test.dart`, inside `main`, after `test('tracker code aggregates only through the analytics engine', ...)`. It follows that test's style. `packages/nimbus_data/lib/src/goals/` does not exist until Task 7, so the test checks it only when present; the domain directory must exist, or the test would pass by checking nothing:

```dart
  test('goal code below the app never names a goal kind', () {
    // Phase 5's grep criterion, kept as a test. A kind is the editor's word
    // for a metric and direction pair and lives only in the app
    // (goal_kind.dart). The engine and storage branch on metric and
    // direction, so a kind named here would be a second, kind-shaped code
    // path. Comment lines are skipped: they may name what they avoid.
    final kind =
        RegExp(r'GoalKind|spendingCap|habitLimit|habitGoal|savingsTarget');
    final domain = Directory('packages/nimbus_domain/lib/src/goals');
    // nimbus_data's goals directory arrives with Phase 5's data tasks; until
    // then it has nothing to check. The domain's must exist, or this test
    // would pass by checking nothing.
    final data = Directory('packages/nimbus_data/lib/src/goals');
    expect(domain.existsSync(), isTrue,
        reason: '${domain.path} moved; point this test at it');

    final offenders = <String>[];
    for (final dir in [domain, data].where((d) => d.existsSync())) {
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));
      for (final file in files) {
        for (final (index, line) in file.readAsLinesSync().indexed) {
          final code = line.trim();
          if (code.startsWith('//')) continue;
          if (kind.hasMatch(code)) {
            offenders.add('${file.path}:${index + 1}: $code');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'a goal kind is the app editor\'s idea:\n'
            '${offenders.join('\n')}');
  });
```

- [ ] **Step 3: Run the tests to confirm RED, and prove the grep test bites**

Run: `cd packages/nimbus_domain && dart test test/goals/goal_engine_test.dart`
Expected: FAIL to load: `Error: Method not found: 'GoalEngine'.`, `Error: Type 'GoalMeasurer' not found.`

Run from the repo root: `dart test test/architecture_test.dart`
Expected: `+6: All tests passed!` — the grep test passes at once, because no kind is named yet. Prove it can fail:

1. Write `packages/nimbus_domain/lib/src/goals/kind_probe.dart` with the Write tool, containing exactly these two lines:
   ```dart
   // GoalKind named in a comment is allowed.
   const kindProbe = 'habitGoal';
   ```
2. Run `dart test test/architecture_test.dart`. Expected: `+5 -1: Some tests failed.`, with exactly one offender — the code line, not the comment:
   ```
   a goal kind is the app editor's idea:
   packages/nimbus_domain/lib/src/goals\kind_probe.dart:2: const kindProbe = 'habitGoal';
   ```
   (On Windows the last separator is `\`: `listSync` joins with the platform separator.)
3. Delete the probe: `rm packages/nimbus_domain/lib/src/goals/kind_probe.dart`. Run the test again: `+6: All tests passed!`. `git status --short` must not list `kind_probe.dart`.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-goal-engine
```

- [ ] **Step 5: Write the port**

Create `packages/nimbus_domain/lib/src/goals/goal_measurer.dart`:

```dart
import '../calendar/date_key.dart';
import 'goal_amount.dart';
import 'goal_metric.dart';
import 'goal_scope.dart';

/// The port a goal is measured through.
///
/// `nimbus_data` implements it over Phase 3's `AnalyticsEngine`, and that
/// implementation is the one place that switches on [GoalMetric]. Answers are
/// `MoneyAmount`s when `metric.isMoney`, `QuantityAmount`s otherwise.
abstract interface class GoalMeasurer {
  /// [metric] over [scope] across [range], as one amount.
  Future<GoalAmount> measure(
      GoalMetric metric, GoalScope scope, DateRange range);

  /// The same, one amount per day across [span]. Days with no data are
  /// absent from the map; `foldDaily` counts them as zero.
  Future<Map<DateKey, GoalAmount>> measureDaily(
      GoalMetric metric, GoalScope scope, DateRange span);
}
```

- [ ] **Step 6: Write `GoalEngine`**

Create `packages/nimbus_domain/lib/src/goals/goal_engine.dart`:

```dart
import '../calendar/date_key.dart';
import 'goal.dart';
import 'goal_assess.dart';
import 'goal_measurer.dart';
import 'goal_periods.dart';
import 'goal_progress.dart';

/// Measures a goal over a period and assesses the result: the brief's
/// `evaluate`, which the app calls now and Phase 6's background evaluation
/// calls later.
///
/// A service, not a value: it has no equality.
final class GoalEngine {
  /// [_today] is passed as `today:`.
  GoalEngine(this.measurer, {required this._today});

  final GoalMeasurer measurer;
  final DateKey Function() _today;

  /// The day goals are evaluated as of: the app's one clock.
  DateKey today() => _today();

  /// [goal]'s progress over [period], as of today.
  Future<GoalProgress> evaluate(Goal goal, DateRange period) =>
      _evaluate(goal, period, today());

  /// [goal]'s progress over its current period.
  ///
  /// Reads today once, before measuring, so a call that straddles midnight
  /// measures and assesses the same day's period.
  Future<GoalProgress> evaluateCurrent(Goal goal) {
    final day = today();
    return _evaluate(goal, GoalPeriods.current(goal, day), day);
  }

  Future<GoalProgress> _evaluate(
      Goal goal, DateRange period, DateKey day) async {
    final current = await measurer.measure(goal.metric, goal.scope, period);
    return assess(goal, period, current, day);
  }
}
```

- [ ] **Step 7: Export the new files**

The barrel's goal block becomes (final for Phase 5's domain):

```dart
export 'src/goals/goal.dart';
export 'src/goals/goal_alert.dart';
export 'src/goals/goal_amount.dart';
export 'src/goals/goal_assess.dart';
export 'src/goals/goal_direction.dart';
export 'src/goals/goal_engine.dart';
export 'src/goals/goal_fold.dart';
export 'src/goals/goal_measurer.dart';
export 'src/goals/goal_metric.dart';
export 'src/goals/goal_period.dart';
export 'src/goals/goal_periods.dart';
export 'src/goals/goal_progress.dart';
export 'src/goals/goal_scope.dart';
export 'src/goals/goal_status.dart';
export 'src/goals/goal_streaks.dart';
```

- [ ] **Step 8: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_domain && dart test test/goals/`
Expected: `+87: All tests passed!`

Run from the repo root: `dart test test/architecture_test.dart`. Expected: `+6: All tests passed!`

Then `dart analyze --fatal-infos` from the repo root. Expected: `No issues found!`

- [ ] **Step 9: Run the full gate**

Expected:
- Architecture 5 + 1 = **6**.
- `nimbus_domain` 411 + 4 = **415**.
- The rest unchanged.

- [ ] **Step 10: Commit and merge**

```bash
git add packages/nimbus_domain test/architecture_test.dart
git commit -F - <<'EOF'
feat(goals): GoalMeasurer port, GoalEngine and the kind-free test

GoalEngine is the brief's evaluate: measure through the GoalMeasurer
port, then assess. nimbus_data implements the port over Phase 3's
engine in the next commit, so the domain never sees SQL.
evaluateCurrent reads today once, before measuring, so an evaluation
that straddles midnight measures and assesses the same period
instead of calling a still-open month met.

Touches Phase 0's test/architecture_test.dart (CONVENTIONS section
3): the brief's grep criterion becomes a test. Nothing under goals/
in nimbus_domain or nimbus_data may name a goal kind. Kinds are the
app editor's idea, so the engine and storage cannot grow a
kind-shaped branch. The data directory is checked once it exists.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only feat/goal-engine
```

---

### Task 7: `EngineGoalMeasurer`

Branch `feat/goal-measurer`, slug `goal-measurer`.

**Files:**
- Create: `packages/nimbus_data/lib/src/goals/engine_goal_measurer.dart`
- Modify: `packages/nimbus_data/lib/nimbus_data.dart` (barrel, one line)
- Test: `packages/nimbus_data/test/goals/support/goal_fixture.dart`, `packages/nimbus_data/test/goals/engine_goal_measurer_test.dart`

**Interfaces:**
- Consumes:
  - Task 2: `GoalMetric`, `GoalScope` / `MoneyScope` / `TrackerScope`, `GoalAmount` / `MoneyAmount` / `QuantityAmount`.
  - Task 6: `GoalMeasurer`.
  - Phase 3 / 4b, read-only: `AnalyticsEngine.run` / `runTracker`, `QuerySpec`, `QueryFilters` (`toJson` / `fromJson` / `withDateRange`), `TagFilter`, `GroupByNone`, `GroupByPeriod`, `TrackerQuerySpec`, `TrackerGroupByNone`, `TrackerGroupByDay`, `PeriodKey`.
- Produces:
  - `final class EngineGoalMeasurer implements GoalMeasurer { EngineGoalMeasurer(AppDatabase db, AnalyticsEngine engine); }`, exported from `package:nimbus_data/nimbus_data.dart`.
  - Test support: `GoalFixture` with `open()`, `db`, `engine`, `measurer`, `expense(...)`, `income(...)`, `log(...)`.

- [ ] **Step 1: Branch**

```bash
git switch phase/5-goals
git switch -c feat/goal-measurer
```

- [ ] **Step 2: Write the test fixture**

Create `packages/nimbus_data/test/goals/support/goal_fixture.dart`:

```dart
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
```

- [ ] **Step 3: Write the failing tests**

Create `packages/nimbus_data/test/goals/engine_goal_measurer_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/goal_fixture.dart';

void main() {
  late GoalFixture f;

  const january = DateRange(DateKey(20260101), DateKey(20260131));
  final food = MoneyScope(const QueryFilters(
      direction: MoneyDirection.expense, categorySubtreePaths: ['/food/']));
  final dining = MoneyScope(const QueryFilters(
      direction: MoneyDirection.expense,
      categorySubtreePaths: ['/food/dining/']));
  final trip = MoneyScope(QueryFilters(
      direction: MoneyDirection.expense, tags: TagsAny(const ['/trip/'])));
  final expenses =
      MoneyScope(const QueryFilters(direction: MoneyDirection.expense));
  final everything = MoneyScope(const QueryFilters());

  // Hand-computed expectations depend on these rows; change one and recompute.
  // Expenses, in dining unless named:
  // - 5 Jan: 1000 (tagged trip), and 500 in food itself;
  // - 6 Jan: 2000 in rent;
  // - 7 Jan: 300 unconfirmed, and 700 soft-deleted;
  // - 1 Feb: 400, outside January.
  // Income: 3000 salary on 10 Jan.
  // cig: two on 5 Jan, one on 6 Jan, and one soft-deleted on 5 Jan.
  // water: 0.5 and 0.25 on 5 Jan, 1.0 on 7 Jan.
  setUp(() async {
    f = await GoalFixture.open();
    await f.expense(1000, const DateKey(20260105), tags: ['trip']);
    await f.expense(500, const DateKey(20260105), category: 'food');
    await f.expense(2000, const DateKey(20260106), category: 'rent');
    await f.expense(300, const DateKey(20260107), confirmed: false);
    await f.db.transactionsDao
        .softDelete(await f.expense(700, const DateKey(20260107)));
    await f.expense(400, const DateKey(20260201));
    await f.income(3000, const DateKey(20260110));
    await f.log('cig', const DateKey(20260105));
    await f.log('cig', const DateKey(20260105));
    await f.log('cig', const DateKey(20260106));
    await f.db.trackerEntriesDao
        .softDelete(await f.log('cig', const DateKey(20260105)));
    await f.log('water', const DateKey(20260105), value: 0.5);
    await f.log('water', const DateKey(20260105), value: 0.25);
    await f.log('water', const DateKey(20260107), value: 1.0);
  });
  tearDown(() => f.db.close());

  group('measure', () {
    test('moneySum adds a subtree, unconfirmed in and deleted out', () async {
      expect(await f.measurer.measure(GoalMetric.moneySum, food, january),
          const MoneyAmount(Money(1800)));
    });

    test('txnCount counts the same rows', () async {
      expect(await f.measurer.measure(GoalMetric.txnCount, food, january),
          const QuantityAmount(3));
    });

    test('a tag filter narrows the sum', () async {
      expect(await f.measurer.measure(GoalMetric.moneySum, trip, january),
          const MoneyAmount(Money(1000)));
    });

    test("trackerSum adds one tracker's values", () async {
      expect(
          await f.measurer
              .measure(GoalMetric.trackerSum, TrackerScope('water'), january),
          const QuantityAmount(1.75));
    });

    test("trackerCount counts one tracker's live entries", () async {
      expect(
          await f.measurer
              .measure(GoalMetric.trackerCount, TrackerScope('cig'), january),
          const QuantityAmount(3));
    });

    test('netSavings is income minus expense, and can be negative', () async {
      // 3000 in; 1000 + 500 + 2000 + 300 out.
      expect(
          await f.measurer.measure(GoalMetric.netSavings, everything, january),
          const MoneyAmount(Money(-800)));
    });
  });

  group('measureDaily', () {
    test('moneySum by day', () async {
      expect(
          await f.measurer.measureDaily(GoalMetric.moneySum, food, january), {
        const DateKey(20260105): const MoneyAmount(Money(1500)),
        const DateKey(20260107): const MoneyAmount(Money(300)),
      });
    });

    test('txnCount by day', () async {
      expect(
          await f.measurer.measureDaily(GoalMetric.txnCount, food, january), {
        const DateKey(20260105): const QuantityAmount(2),
        const DateKey(20260107): const QuantityAmount(1),
      });
    });

    test('trackerSum by day', () async {
      expect(
          await f.measurer.measureDaily(
              GoalMetric.trackerSum, TrackerScope('water'), january),
          {
            const DateKey(20260105): const QuantityAmount(0.75),
            const DateKey(20260107): const QuantityAmount(1),
          });
    });

    test('trackerCount by day', () async {
      expect(
          await f.measurer.measureDaily(
              GoalMetric.trackerCount, TrackerScope('cig'), january),
          {
            const DateKey(20260105): const QuantityAmount(2),
            const DateKey(20260106): const QuantityAmount(1),
          });
    });

    test('netSavings by day, negative days and a positive one', () async {
      expect(
          await f.measurer
              .measureDaily(GoalMetric.netSavings, everything, january),
          {
            const DateKey(20260105): const MoneyAmount(Money(-1500)),
            const DateKey(20260106): const MoneyAmount(Money(-2000)),
            const DateKey(20260107): const MoneyAmount(Money(-300)),
            const DateKey(20260110): const MoneyAmount(Money(3000)),
          });
    });

    test('a span longer than one money query keeps the days at each seam',
        () async {
      // 31-day windows from 6 Dec: 6 Dec - 5 Jan, 6 Jan - 5 Feb, 6 - 28 Feb.
      // 5 and 6 January sit on either side of the first seam.
      expect(
          await f.measurer.measureDaily(GoalMetric.moneySum, expenses,
              const DateRange(DateKey(20251206), DateKey(20260228))),
          {
            const DateKey(20260105): const MoneyAmount(Money(1500)),
            const DateKey(20260106): const MoneyAmount(Money(2000)),
            const DateKey(20260107): const MoneyAmount(Money(300)),
            const DateKey(20260201): const MoneyAmount(Money(400)),
          });
    });
  });

  group('stored paths follow their nodes (Review Focus 1)', () {
    test('a category moved under another parent is still measured',
        () async {
      await f.db.categoriesDao.move('dining', 'rent');

      final stored = await f.engine.run(QuerySpec(
          filters: dining.filters.withDateRange(january),
          groupBy: const GroupByNone(),
          aggregate: Aggregate.sum));
      expect(stored.trueTotal, Money.zero,
          reason: 'the stored path alone now matches nothing');
      expect(await f.measurer.measure(GoalMetric.moneySum, dining, january),
          const MoneyAmount(Money(1300)));
      expect(
          await f.measurer.measureDaily(GoalMetric.moneySum, dining, january),
          {
            const DateKey(20260105): const MoneyAmount(Money(1000)),
            const DateKey(20260107): const MoneyAmount(Money(300)),
          });
    });

    test('a tag moved under another parent still narrows', () async {
      await f.db.tagsDao.move('trip', 'work');

      expect(await f.measurer.measure(GoalMetric.moneySum, trip, january),
          const MoneyAmount(Money(1000)));
    });

    test('a category moved and then deleted still counts its live expenses, '
        'as Analytics does', () async {
      await f.db.categoriesDao.move('dining', 'rent');
      await f.db.categoriesDao.softDeleteSubtree('dining');

      expect(await f.measurer.measure(GoalMetric.moneySum, dining, january),
          const MoneyAmount(Money(1300)));
    });
  });

  test('an archived tracker is still measured', () async {
    await f.db.trackersDao.setArchived('cig', true);

    expect(
        await f.measurer
            .measure(GoalMetric.trackerCount, TrackerScope('cig'), january),
        const QuantityAmount(3));
  });

  test("a metric given the other family's scope is refused", () async {
    await expectLater(
        f.measurer.measure(GoalMetric.moneySum, TrackerScope('cig'), january),
        throwsArgumentError);
    await expectLater(
        f.measurer.measureDaily(GoalMetric.trackerCount, food, january),
        throwsArgumentError);
  });
}
```

- [ ] **Step 4: Run the tests to confirm RED**

Run: `cd packages/nimbus_data && dart test test/goals/engine_goal_measurer_test.dart`

Expected: FAIL to compile, naming `EngineGoalMeasurer` (`Type 'EngineGoalMeasurer' not found` in `goal_fixture.dart`).

- [ ] **Step 5: Tag the parent**

```bash
git tag pre-goal-measurer
```

- [ ] **Step 6: Implement the measurer**

Create `packages/nimbus_data/lib/src/goals/engine_goal_measurer.dart`:

```dart
// drift exports a GroupBy of its own; this file means the domain's.
import 'package:drift/drift.dart' hide GroupBy;
import 'package:nimbus_domain/nimbus_domain.dart';

import '../analytics/analytics_engine.dart';
import '../database/app_database.dart';

/// [GoalMeasurer] over Phase 3's [AnalyticsEngine] (goals design §3).
///
/// This file holds the codebase's only switches on [GoalMetric]: what a
/// metric reads is decided here, once, and nothing upstream branches on it.
/// Every number comes from the engine, so a goal and a chart over the same
/// rows cannot disagree: deleted rows out, unconfirmed captures in.
///
/// Statements run one after another. drift serializes every statement on
/// its one connection, so issuing them together would only queue them.
final class EngineGoalMeasurer implements GoalMeasurer {
  EngineGoalMeasurer(this._db, this._engine);

  /// Read only to re-resolve stored paths ([_filtersNow]).
  final AppDatabase _db;
  final AnalyticsEngine _engine;

  /// Days per money query in [measureDaily].
  ///
  /// The engine buckets money by day with a CASE ladder, one branch per day,
  /// so one query over a span costs rows x days: a three-year history would
  /// test every row against a thousand ranges. A window of about a month
  /// keeps it at rows x 31, for a few more statements. Tracker entries group
  /// by their stored day key directly and need no windows.
  static const _window = 31;

  @override
  Future<GoalAmount> measure(
          GoalMetric metric, GoalScope scope, DateRange range) async =>
      switch (metric) {
        GoalMetric.moneySum =>
          MoneyAmount((await _money(scope, range)).trueTotal),
        GoalMetric.txnCount =>
          QuantityAmount((await _money(scope, range)).trueCount.toDouble()),
        GoalMetric.trackerSum => QuantityAmount(
            (await _tracker(scope, range, const TrackerGroupByNone())).sum),
        GoalMetric.trackerCount => QuantityAmount(
            (await _tracker(scope, range, const TrackerGroupByNone()))
                .count
                .toDouble()),
        GoalMetric.netSavings => MoneyAmount(
            (await _money(scope, range, MoneyDirection.income)).trueTotal -
                (await _money(scope, range, MoneyDirection.expense))
                    .trueTotal),
      };

  @override
  Future<Map<DateKey, GoalAmount>> measureDaily(
          GoalMetric metric, GoalScope scope, DateRange span) async =>
      switch (metric) {
        GoalMetric.moneySum => <DateKey, GoalAmount>{
            for (final bucket in await _moneyDays(scope, span))
              _dayOf(bucket.key): MoneyAmount(bucket.money),
          },
        GoalMetric.txnCount => <DateKey, GoalAmount>{
            for (final bucket in await _moneyDays(scope, span))
              _dayOf(bucket.key): QuantityAmount(bucket.count.toDouble()),
          },
        GoalMetric.trackerSum => <DateKey, GoalAmount>{
            for (final bucket
                in (await _tracker(scope, span, const TrackerGroupByDay()))
                    .buckets)
              _dayOf(bucket.key): QuantityAmount(bucket.value),
          },
        GoalMetric.trackerCount => <DateKey, GoalAmount>{
            for (final bucket
                in (await _tracker(scope, span, const TrackerGroupByDay()))
                    .buckets)
              _dayOf(bucket.key): QuantityAmount(bucket.count.toDouble()),
          },
        GoalMetric.netSavings => _net(
            await _moneyDays(scope, span, MoneyDirection.income),
            await _moneyDays(scope, span, MoneyDirection.expense)),
      };

  /// One ungrouped money query. Its true total and count count each
  /// transaction once.
  Future<AnalyticsResult> _money(GoalScope scope, DateRange range,
          [MoneyDirection? direction]) async =>
      _engine.run(QuerySpec(
        filters: (await _filtersNow(scope, direction)).withDateRange(range),
        groupBy: const GroupByNone(),
        aggregate: Aggregate.sum,
      ));

  /// Money by day over [span], in windows of [_window] days. Each bucket's
  /// money is the day's sum, and its count the day's rows.
  Future<List<Bucket>> _moneyDays(GoalScope scope, DateRange span,
      [MoneyDirection? direction]) async {
    final filters = await _filtersNow(scope, direction);
    final buckets = <Bucket>[];
    for (var start = span.startInclusive;
        start <= span.endInclusive;
        start = start.addDays(_window)) {
      final last = start.addDays(_window - 1);
      final window =
          DateRange(start, last < span.endInclusive ? last : span.endInclusive);
      final result = await _engine.run(QuerySpec(
        filters: filters.withDateRange(window),
        groupBy: const GroupByPeriod(PeriodType.day),
        aggregate: Aggregate.sum,
      ));
      buckets.addAll(result.buckets);
    }
    return buckets;
  }

  Future<TrackerResult> _tracker(
          GoalScope scope, DateRange range, TrackerGroupBy groupBy) =>
      _engine.runTracker(TrackerQuerySpec(
        trackerIds: [_trackerIdOf(scope)],
        dateRange: range,
        groupBy: groupBy,
        aggregate: Aggregate.sum,
      ));

  /// Income minus expense, day by day. A day with only one of the two still
  /// has data.
  static Map<DateKey, GoalAmount> _net(
      List<Bucket> income, List<Bucket> expense) {
    final net = <DateKey, Money>{
      for (final bucket in income) _dayOf(bucket.key): bucket.money,
    };
    for (final bucket in expense) {
      final day = _dayOf(bucket.key);
      net[day] = (net[day] ?? Money.zero) - bucket.money;
    }
    return {
      for (final MapEntry(:key, :value) in net.entries) key: MoneyAmount(value),
    };
  }

  /// A day bucket's day. Both engine paths key a day as a one-day
  /// [PeriodKey].
  static DateKey _dayOf(BucketKey key) =>
      (key as PeriodKey).range.startInclusive;

  /// The scope's filters, with every stored category and tag path
  /// re-resolved to where its node is now, and with [direction] if given.
  ///
  /// A goal stores materialized paths, and moving a node rewrites its path,
  /// so the stored one would match nothing and a cap would read zero for
  /// ever (Review Focus 1). A path's last segment is its node's own id, so
  /// the node is looked up by that id.
  ///
  /// The lookup ignores deleted_at, as `CategoriesDao.byId` does: it asks
  /// where the node is, not whether it is live. Whether a deleted node's rows
  /// count stays the engine's rule. A soft-deleted category's live expenses
  /// still count, as they do in Analytics; a soft-deleted tag matches
  /// nothing. An id with no row at all keeps its stored path, which matches
  /// nothing.
  ///
  /// The filters are rebuilt through JSON, which Phase 3 keeps lossless. A
  /// filter field added to QueryFilters later is therefore carried over
  /// rather than silently dropped -- and a dropped filter widens the goal.
  Future<QueryFilters> _filtersNow(
      GoalScope scope, MoneyDirection? direction) async {
    final stored = _filtersOf(scope);
    final json = stored.toJson();
    final categories = stored.categorySubtreePaths;
    if (categories.isNotEmpty) {
      json['categorySubtreePaths'] = _relocated(categories,
          await _categoryPaths(categories.map(_leafId).toList()));
    }
    final tags = stored.tags;
    if (tags != null) {
      json['tags'] = {
        ...tags.toJson(),
        'paths': _relocated(tags.subtreePaths,
            await _tagPaths(tags.subtreePaths.map(_leafId).toList())),
      };
    }
    if (direction != null) {
      json['direction'] = direction.name;
    }
    return QueryFilters.fromJson(json);
  }

  Future<Map<String, String>> _categoryPaths(List<String> ids) async => {
        for (final row in await (_db.select(_db.categories)
              ..where((t) => t.id.isIn(ids)))
            .get())
          row.id: row.path,
      };

  Future<Map<String, String>> _tagPaths(List<String> ids) async => {
        for (final row
            in await (_db.select(_db.tags)..where((t) => t.id.isIn(ids))).get())
          row.id: row.path,
      };

  static List<String> _relocated(List<String> stored, Map<String, String> now) =>
      [for (final path in stored) now[_leafId(path)] ?? path];

  static String _leafId(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty);
    return segments.isEmpty ? path : segments.last;
  }

  static QueryFilters _filtersOf(GoalScope scope) => switch (scope) {
        MoneyScope(:final filters) => filters,
        TrackerScope() => throw ArgumentError.value(
            scope, 'scope', 'a money metric needs a money scope'),
      };

  static String _trackerIdOf(GoalScope scope) => switch (scope) {
        TrackerScope(:final trackerId) => trackerId,
        MoneyScope() => throw ArgumentError.value(
            scope, 'scope', 'a tracker metric needs a tracker scope'),
      };
}
```

In `packages/nimbus_data/lib/nimbus_data.dart`, after `export 'src/database/converters.dart';`, add:

```dart
export 'src/goals/engine_goal_measurer.dart';
```

- [ ] **Step 7: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_data && dart test test/goals/engine_goal_measurer_test.dart`

Expected: PASS, 17 tests.

**Mutation checks.**
1. In `_relocated`, return `stored` unchanged. Expected: the three "stored paths follow their nodes" tests FAIL. Restore it.
2. In `_moneyDays`, step by `start.addDays(_window + 1)`. Expected: "a span longer than one money query keeps the days at each seam" FAILS, missing 6 January. Restore it.

- [ ] **Step 8: Run the full gate**

Expected: all green. `nimbus_data` is 250 + 17 = **267**. The other suites are unchanged from Task 6's gate.

- [ ] **Step 9: Commit and merge**

```bash
git add packages/nimbus_data/lib/src/goals/engine_goal_measurer.dart packages/nimbus_data/lib/nimbus_data.dart packages/nimbus_data/test/goals
git commit -F - <<'EOF'
feat(goals): measure goals with the analytics engine

EngineGoalMeasurer is the GoalMeasurer port over Phase 3's engine, and
the one place that switches on GoalMetric:
- money metrics run an ungrouped QuerySpec;
- tracker metrics run a TrackerQuerySpec;
- net savings is income minus expense.
A goal therefore reads exactly what a chart over the same rows reads:
deleted rows out, unconfirmed captures in.

A goal stores materialized paths, and moving a category rewrites its
path. Before every query, each stored category and tag path is
re-resolved by its last segment, the node's own id. Without that, a
spending cap whose category moved would read zero for ever (Review
Focus 1). The lookup ignores deleted_at, so a moved-then-deleted
category's live expenses still count, as they do in Analytics.

Money days are measured in 31-day windows. The engine buckets days
with one CASE branch per day, so a single query over a long history
would test every row against every day.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only feat/goal-measurer
```

---

### Task 8: Goal DAOs and watermarks

Branch `feat/goal-daos`, slug `goal-daos`.

**Files:**
- Create: `packages/nimbus_data/lib/src/goals/goals_dao.dart`
- Create: `packages/nimbus_data/lib/src/goals/goal_period_results_dao.dart`
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` (Phase 0: two imports, two DAO getters)
- Modify: `packages/nimbus_data/lib/nimbus_data.dart` (barrel, two lines)
- Modify: `packages/nimbus_data/test/goals/support/goal_fixture.dart` (goal builders, row ageing)
- Test: `packages/nimbus_data/test/goals/goals_dao_test.dart`, `goal_period_results_dao_test.dart`, `watermark_test.dart`
- Scratch, never committed: `packages/nimbus_data/test/goals/watermark_probe_test.dart` (Step 11)

**Interfaces:**
- Consumes:
  - Task 1: the `goals` and `goal_period_results` tables.
  - Task 2: `Goal` with its `alertPercentsFromJson` / `alertPercentsToJson`, `GoalScope.fromJson`, `GoalPeriod.fromStored` / `storedName` / `startDate` / `endDate`, `GoalAmount`.
  - Tests only, Task 3: `assess`.
  - Task 5: `crossing`, `reachedPercent`, `GoalAlert`.
- Produces, exactly as the contract states:
  - `GoalRead`, `GoalReadable`, `GoalUnreadable`, `GoalsDao`, `CachedPeriod`, `GoalPeriodResultsDao`.
  - `AppDatabase.goalsDao` and `AppDatabase.goalPeriodResultsDao`.
  - Test support: `moneyGoal`, `trackerGoal`, `netSavingsGoal`, `ageMoneyRows`, `ageTrackerEntries`.

- [ ] **Step 1: Branch**

```bash
git switch phase/5-goals
git switch -c feat/goal-daos
```

- [ ] **Step 2: Re-check plan Decision 5 before relying on it**

```bash
grep -rn "deleteTransaction(\|delete(_db.transactions)\|DELETE FROM transactions" app/lib packages/*/lib
grep -rn "delete(_db.trackerEntries)\|DELETE FROM tracker_entries" app/lib packages/*/lib
grep -n "_dao.updateTransaction(\|await _attachTags(" app/lib/features/transactions/data/transaction_repository.dart
```

Expected (as of 2026-10-10):
- The first command prints only the definition, `packages/nimbus_data/lib/src/database/app_database.dart:1223` and `:1224` (`deleteTransaction` and its `_db.delete(_db.transactions)`). Nothing calls it.
- The second prints nothing.
- The third shows `update` calling `await _dao.updateTransaction(` (line 76) before `await _attachTags(tx.id, ...)` (line 94).

If any of these differs, **stop and report to the operator**. A caller of the hard delete, or a tag write without a row write, means the watermark needs a row-count term (spec §3). That is a design change, not this task's to make.

- [ ] **Step 3: Extend the fixture**

Append to `packages/nimbus_data/test/goals/support/goal_fixture.dart`:

```dart
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
```

- [ ] **Step 4: Write the failing tests**

Create `packages/nimbus_data/test/goals/goals_dao_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';

void main() {
  late AppDatabase db;
  late GoalsDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = db.goalsDao;
  });
  tearDown(() => db.close());

  // One of each shape the editor makes. Between them they set every
  // column: both target columns, all three period shapes, both calendars,
  // both week starts, custom alert percents, and a paused goal.
  final goals = [
    Goal(
      id: 'g1',
      name: 'Dining out',
      metric: GoalMetric.moneySum,
      scope: MoneyScope(QueryFilters(
        direction: MoneyDirection.expense,
        categorySubtreePaths: const ['/food/dining/'],
        tags: TagsAny(const ['/trip/']),
      )),
      direction: GoalDirection.atMost,
      target: const MoneyAmount(Money(5000000)),
      period: const RecurringPeriod(PeriodType.month, DateKey(20260321)),
      calendar: CalendarKind.jalali,
      weekStart: DateTime.saturday,
      alertPercents: const [50, 80, 100],
    ),
    Goal(
      id: 'g2',
      name: 'Cigarettes',
      metric: GoalMetric.trackerCount,
      scope: TrackerScope('cig'),
      direction: GoalDirection.atMost,
      target: const QuantityAmount(0),
      period: const RecurringPeriod(PeriodType.day, DateKey(20260105)),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.monday,
    ),
    Goal(
      id: 'g3',
      name: 'Water',
      metric: GoalMetric.trackerSum,
      scope: TrackerScope('water'),
      direction: GoalDirection.atLeast,
      target: const QuantityAmount(14.5),
      period: const RecurringPeriod(PeriodType.week, DateKey(20260105)),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.monday,
    ),
    Goal(
      id: 'g4',
      name: 'Car',
      metric: GoalMetric.netSavings,
      scope: MoneyScope(const QueryFilters()),
      direction: GoalDirection.atLeast,
      target: const MoneyAmount(Money(250000000)),
      period: FixedRangePeriod(
          const DateRange(DateKey(20260321), DateKey(20270320))),
      calendar: CalendarKind.jalali,
      weekStart: DateTime.saturday,
      active: false,
    ),
  ];

  for (final goal in goals) {
    test('${goal.name} survives a round trip', () async {
      await dao.upsert(goal);

      expect(await dao.byId(goal.id),
          isA<GoalReadable>().having((r) => r.goal, 'goal', goal));
    });
  }

  Future<int> createdAt(String id) async => (await db
          .customSelect("SELECT created_at AS c FROM goals WHERE id = '$id'")
          .getSingle())
      .read<int>('c');

  test('upserting an existing id rewrites it in place', () async {
    await dao.upsert(goals.first);
    final created = await createdAt('g1');

    await dao.upsert(goals.first.copyWith(name: 'Eating out'));

    expect(((await dao.byId('g1'))! as GoalReadable).goal.name, 'Eating out');
    expect(await createdAt('g1'), created);
    expect(await dao.watchAll().first, hasLength(1));
  });

  test('watchAll lists live goals by id; delete and restore move one out '
      'and back', () async {
    await dao.upsert(goals[1]);
    await dao.upsert(goals[0]);
    expect([for (final r in await dao.watchAll().first) r.id], ['g1', 'g2']);

    await dao.softDelete('g1');
    expect([for (final r in await dao.watchAll().first) r.id], ['g2']);
    expect(await dao.byId('g1'), isNull);

    await dao.restore('g1');
    expect([for (final r in await dao.watchAll().first) r.id], ['g1', 'g2']);
  });

  test('setActive writes the flag', () async {
    await dao.upsert(goals.first);

    await dao.setActive('g1', false);

    expect(((await dao.byId('g1'))! as GoalReadable).goal.active, isFalse);
  });

  test('a write to an id that does not exist throws', () async {
    await expectLater(dao.setActive('nope', true), throwsStateError);
    await expectLater(dao.softDelete('nope'), throwsStateError);
    await expectLater(dao.restore('nope'), throwsStateError);
  });

  // Each corrupts g1 in one way. None may default; each becomes an
  // unreadable row that still carries the goal's name for its card.
  final malformed = <String, Map<String, Object?>>{
    'an unknown metric': {'metric': 'moneyMax'},
    'an unknown direction': {'direction': 'sideways'},
    'an unknown calendar': {'calendar': 'lunar'},
    'a scope that is not JSON': {'scope_json': '{'},
    'a scope of an unknown type': {'scope_json': '{"type":"stocks"}'},
    'both targets set': {'target_quantity': 1.5},
    'no target': {'target_minor': null},
    'a quantity target on a money metric': {
      'target_minor': null,
      'target_quantity': 5000.0,
    },
    'alert percents that are not a list': {'alert_percents': '80'},
    'an unknown period': {'period': 'fortnight'},
  };
  for (final MapEntry(key: what, value: columns) in malformed.entries) {
    test('$what makes the row unreadable, not a guess', () async {
      await dao.upsert(goals.first);
      for (final MapEntry(key: column, value: value) in columns.entries) {
        await db.customStatement(
            'UPDATE goals SET $column = ? WHERE id = ?', [value, 'g1']);
      }

      expect(
        await dao.byId('g1'),
        isA<GoalUnreadable>()
            .having((r) => r.id, 'id', 'g1')
            .having((r) => r.name, 'name', 'Dining out')
            .having((r) => r.error, 'error', isA<FormatException>()),
      );
    });
  }

  test('an unreadable row leaves the others readable', () async {
    await dao.upsert(goals[0]);
    await dao.upsert(goals[1]);
    await db.customStatement(
        "UPDATE goals SET metric = 'moneyMax' WHERE id = 'g1'");

    final all = await dao.watchAll().first;

    expect(all[0], isA<GoalUnreadable>());
    expect(all[1], isA<GoalReadable>().having((r) => r.goal, 'goal', goals[1]));
  });
}
```

Create `packages/nimbus_data/test/goals/goal_period_results_dao_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/goal_fixture.dart';

void main() {
  late GoalFixture f;
  late GoalPeriodResultsDao dao;
  final goal = moneyGoal();
  final water = trackerGoal('water', metric: GoalMetric.trackerSum);
  const january = DateRange(DateKey(20260101), DateKey(20260131));
  const february = DateRange(DateKey(20260201), DateKey(20260228));
  const midJanuary = DateKey(20260115);

  GoalProgress spent(int minor) =>
      assess(goal, january, MoneyAmount(Money(minor)), midJanuary);

  setUp(() async {
    f = await GoalFixture.open();
    dao = f.db.goalPeriodResultsDao;
    // A period row references its goal.
    await f.db.goalsDao.upsert(goal);
    await f.db.goalsDao.upsert(water);
  });
  tearDown(() => f.db.close());

  Future<CachedPeriod?> rowFor(Goal g, DateRange period) async {
    for (final row in await dao.forGoal(g.id)) {
      if (row.period == period) return row;
    }
    return null;
  }

  test('values written are read back per period, oldest first', () async {
    await dao.writeValues(
        goal.id,
        [
          (period: february, value: const MoneyAmount(Money(700))),
          (period: january, value: const MoneyAmount(Money(1200))),
        ],
        42);
    await dao.writeValues(
        water.id, [(period: january, value: const QuantityAmount(2.5))], 7);

    final rows = await dao.forGoal(goal.id);

    expect([for (final r in rows) r.period], [january, february]);
    expect([for (final r in rows) r.value],
        [const MoneyAmount(Money(1200)), const MoneyAmount(Money(700))]);
    expect({for (final r in rows) r.watermark}, {42});
    expect((await dao.forGoal(water.id)).single.value,
        const QuantityAmount(2.5));
  });

  test('a value rewrite leaves the alert state alone', () async {
    expect(await dao.recordCrossing(goal, spent(8500)), isNotNull);

    await dao.writeValues(
        goal.id, [(period: january, value: const MoneyAmount(Money(9100)))], 99);

    final row = await rowFor(goal, january);
    expect(row!.value, const MoneyAmount(Money(9100)));
    expect(row.watermark, 99);
    expect(row.lastAlerted, 80);
  });

  test('a crossing alerts once; the same progress again does not', () async {
    expect((await dao.recordCrossing(goal, spent(8500)))?.percent, 80);
    expect(await dao.recordCrossing(goal, spent(8500)), isNull);
    expect((await dao.recordCrossing(goal, spent(10500)))?.percent, 100);
    expect((await rowFor(goal, january))!.lastAlerted, 100);
  });

  test('two evaluations of one crossing at once alert once', () async {
    // The app and, from Phase 6, a background isolate may evaluate the same
    // goal together. recordCrossing's transaction makes the second read the
    // first one's state.
    final alerts = await Future.wait([
      dao.recordCrossing(goal, spent(8500)),
      dao.recordCrossing(goal, spent(8500)),
    ]);

    expect(alerts.whereType<GoalAlert>(), hasLength(1));
    expect(alerts.whereType<GoalAlert>().single.percent, 80);
    expect((await rowFor(goal, january))!.lastAlerted, 80);
  });

  test('a baseline records the reached percent without an alert', () async {
    await dao.setBaseline(goal, spent(8500));

    expect((await rowFor(goal, january))!.lastAlerted, 80);
    expect(await dao.recordCrossing(goal, spent(8500)), isNull);
    expect((await dao.recordCrossing(goal, spent(10000)))?.percent, 100);
  });

  test("deleting one goal's rows leaves another's", () async {
    await dao.writeValues(
        goal.id, [(period: january, value: const MoneyAmount(Money(1)))], 1);
    await dao.writeValues(
        water.id, [(period: january, value: const QuantityAmount(1))], 1);

    await dao.deleteForGoal(goal.id);

    expect(await dao.forGoal(goal.id), isEmpty);
    expect(await dao.forGoal(water.id), hasLength(1));
  });
}
```

Create `packages/nimbus_data/test/goals/watermark_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import 'support/goal_fixture.dart';

void main() {
  test('an empty database answers zero for both watermarks', () async {
    final db = openTestDatabase();
    addTearDown(db.close);

    expect(await db.goalPeriodResultsDao.moneyWatermark(), 0);
    expect(await db.goalPeriodResultsDao.trackerWatermark('cig'), 0);
  });

  group('the money watermark', () {
    late GoalFixture f;
    late String spent;

    setUp(() async {
      f = await GoalFixture.open();
      spent = await f.expense(1000, const DateKey(20260105), tags: ['trip']);
      await ageMoneyRows(f.db);
    });
    tearDown(() => f.db.close());

    Future<void> expectMovedBy(Future<void> Function() write) async {
      final before = await f.db.goalPeriodResultsDao.moneyWatermark();
      await write();
      expect(await f.db.goalPeriodResultsDao.moneyWatermark(),
          greaterThan(before));
    }

    test('moves on an insert',
        () => expectMovedBy(() => f.expense(5, const DateKey(20260106))));

    test(
        'moves on an edit that takes a row out of the scope',
        () => expectMovedBy(() =>
            f.db.transactionsDao.updateTransaction(spent, categoryId: 'rent')));

    test('moves on a soft delete',
        () => expectMovedBy(() => f.db.transactionsDao.softDelete(spent)));

    test('moves when a category moves under another parent',
        () => expectMovedBy(() => f.db.categoriesDao.move('dining', 'rent')));

    test('moves on a tag change, through the row the save path rewrites',
        () => expectMovedBy(() async {
              // TransactionRepository.update writes the row, then the links
              // (plan Decision 5). The stamp is the row's, which is why the
              // watermark needs no tag-link term.
              await f.db.transactionsDao.updateTransaction(spent);
              await f.db.transactionsDao.setTags(spent, ['work']);
            }));
  });

  group('the tracker watermark', () {
    late GoalFixture f;
    late String entry;

    setUp(() async {
      f = await GoalFixture.open();
      entry = await f.log('cig', const DateKey(20260105));
      await f.log('water', const DateKey(20260105), value: 0.5);
      await ageTrackerEntries(f.db);
    });
    tearDown(() => f.db.close());

    Future<int> mark() => f.db.goalPeriodResultsDao.trackerWatermark('cig');

    test('moves when an entry is edited', () async {
      final before = await mark();
      await f.db.trackerEntriesDao.updateEntry(
        entry,
        value: 2,
        occurredAtUtc: DateTime.utc(2026, 1, 5, 9),
        localDateKey: const DateKey(20260105),
        note: null,
        tzOffsetMinutes: null,
      );
      expect(await mark(), greaterThan(before));
    });

    test('moves when an entry is deleted', () async {
      final before = await mark();
      await f.db.trackerEntriesDao.softDelete(entry);
      expect(await mark(), greaterThan(before));
    });

    test("another tracker's entry leaves it alone", () async {
      final before = await mark();
      await f.log('water', const DateKey(20260106));
      expect(await mark(), before);
    });
  });
}
```

- [ ] **Step 5: Run the tests to confirm RED**

Run: `cd packages/nimbus_data && dart test test/goals/goals_dao_test.dart test/goals/goal_period_results_dao_test.dart test/goals/watermark_test.dart`

Expected: FAIL to compile, naming the missing DAO: `The getter 'goalsDao' isn't defined for the type 'AppDatabase'` (and the same for `goalPeriodResultsDao`).

- [ ] **Step 6: Tag the parent**

```bash
git tag pre-goal-daos
```

- [ ] **Step 7: Implement `GoalsDao`**

Create `packages/nimbus_data/lib/src/goals/goals_dao.dart`:

```dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../database/app_database.dart';

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

  /// Inserts [goal], or rewrites every field of the row with its id.
  /// `created_at` is written once, on insert.
  Future<void> upsert(Goal goal) async {
    final now = _now();
    final (int? minor, double? quantity) = switch (goal.target) {
      MoneyAmount(:final money) => (money.minorUnits, null),
      QuantityAmount(:final value) => (null, value),
    };
    final values = GoalsCompanion(
      name: Value(goal.name),
      metric: Value(goal.metric.name),
      scopeJson: Value(jsonEncode(goal.scope.toJson())),
      direction: Value(goal.direction.name),
      targetMinor: Value(minor),
      targetQuantity: Value(quantity),
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
        target: _target(row.targetMinor, row.targetQuantity),
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

  /// Exactly one target column is set (§1). Anything else is unreadable.
  static GoalAmount _target(int? minor, double? quantity) =>
      switch ((minor, quantity)) {
        (final int m, null) => MoneyAmount(Money(m)),
        (null, final double q) => QuantityAmount(q),
        _ => throw FormatException('exactly one of target_minor and '
            'target_quantity must be set, got $minor and $quantity'),
      };
}
```

- [ ] **Step 8: Implement `GoalPeriodResultsDao`**

Create `packages/nimbus_data/lib/src/goals/goal_period_results_dao.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../database/app_database.dart';
import '../seed/ids.dart';

/// One period of one goal as cached: its value, the watermark it was
/// computed at, and the alert state beside them.
final class CachedPeriod {
  const CachedPeriod({
    required this.period,
    required this.value,
    required this.watermark,
    this.lastAlerted,
  });

  final DateRange period;

  /// Null when never computed. That is the current period's row, which
  /// exists only to hold [lastAlerted].
  final GoalAmount? value;

  /// The watermark [value] was computed at. Null means stale.
  final int? watermark;

  /// The highest alert percent already announced for [period].
  final int? lastAlerted;

  @override
  String toString() =>
      'CachedPeriod($period, $value, at $watermark, alerted $lastAlerted)';
}

/// `goal_period_results`: the per-period cache behind history and streaks,
/// and the alert state that stops a crossing from alerting twice.
///
/// The two kinds of column are never written together. [writeValues]
/// touches only the value and the watermark; [recordCrossing] and
/// [setBaseline] touch only the alert state. A cache rewrite therefore never
/// forgets an alert already shown (goals design, departure 2).
final class GoalPeriodResultsDao {
  GoalPeriodResultsDao(this._db);

  final AppDatabase _db;

  /// The goal's rows, oldest period first.
  Future<List<CachedPeriod>> forGoal(String goalId) async {
    final rows = await (_db.select(_db.goalPeriodResults)
          ..where((t) => t.goalId.equals(goalId))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.periodStart)]))
        .get();
    return [
      for (final row in rows)
        CachedPeriod(
          period: DateRange(row.periodStart, row.periodEnd),
          value: switch ((row.currentMinor, row.currentQuantity)) {
            (final int minor, _) => MoneyAmount(Money(minor)),
            (null, final double quantity) => QuantityAmount(quantity),
            (null, null) => null,
          },
          watermark: row.sourceWatermark,
          lastAlerted: row.lastAlertedPercent,
        ),
    ];
  }

  /// Upserts each row's value and [watermark] by (goal, period start), in
  /// one transaction. `last_alerted_percent` is never written here.
  Future<void> writeValues(
    String goalId,
    List<({DateRange period, GoalAmount value})> rows,
    int watermark,
  ) =>
      _db.transaction(() async {
        final now = _now();
        for (final row in rows) {
          final (int? minor, double? quantity) = switch (row.value) {
            MoneyAmount(:final money) => (money.minorUnits, null),
            QuantityAmount(:final value) => (null, value),
          };
          await _db.into(_db.goalPeriodResults).insert(
                GoalPeriodResultsCompanion.insert(
                  id: Ids.newId(),
                  goalId: goalId,
                  periodStart: row.period.startInclusive,
                  periodEnd: row.period.endInclusive,
                  currentMinor: Value(minor),
                  currentQuantity: Value(quantity),
                  sourceWatermark: Value(watermark),
                  createdAt: now,
                  updatedAt: now,
                ),
                onConflict: DoUpdate(
                  (_) => GoalPeriodResultsCompanion(
                    periodEnd: Value(row.period.endInclusive),
                    currentMinor: Value(minor),
                    currentQuantity: Value(quantity),
                    sourceWatermark: Value(watermark),
                    updatedAt: Value(now),
                  ),
                  target: _periodKey,
                ),
              );
        }
      });

  /// A hard delete, unlike every user-facing delete. These rows are a cache
  /// and the alert state beside it, and the re-baseline that follows
  /// rebuilds them (spec §4.3). A soft-deleted row would keep its
  /// (goal, period) key and collide with the row the re-baseline writes.
  Future<void> deleteForGoal(String goalId) => (_db.delete(_db.goalPeriodResults)
        ..where((t) => t.goalId.equals(goalId)))
      .go();

  /// Reads the period's alert state, runs [crossing] and writes the new
  /// state, in one transaction, and returns the alert, if any.
  ///
  /// The transaction is what lets two evaluations of one crossing -- the
  /// app's and, from Phase 6, a background isolate's -- alert once. drift
  /// runs a transaction alone on its connection, so the second call reads
  /// what the first wrote. There is no parallelism to cap. A second
  /// connection, Phase 6's isolate, is Phase 6's to verify.
  Future<GoalAlert?> recordCrossing(Goal goal, GoalProgress progress) =>
      _db.transaction(() async {
        final row = await (_db.select(_db.goalPeriodResults)
              ..where((t) => t.goalId.equals(goal.id))
              ..where((t) => t.periodStart.equalsValue(progress.period.startInclusive))
              ..where((t) => t.deletedAt.isNull()))
            .getSingleOrNull();
        final last = row?.lastAlertedPercent;
        final result = crossing(goal, progress, last);
        if (result.lastAlerted != last) {
          await _writeAlerted(goal.id, progress.period, result.lastAlerted);
        }
        return result.alert;
      });

  /// Records whatever [progress] already reaches as alerted, with no alert:
  /// the re-baseline after a create, an edit, a resume or a restore
  /// (spec §4.3).
  Future<void> setBaseline(Goal goal, GoalProgress progress) => _writeAlerted(
      goal.id, progress.period, reachedPercent(goal, progress.current));

  /// The latest write to anything a money goal reads (spec §3):
  /// transactions, categories and tags.
  ///
  /// Deleted rows are included on purpose, unlike every other query in this
  /// package. A soft delete is a write, and the row it stamps is exactly the
  /// one a live-only maximum would not see.
  ///
  /// It is table-wide, not limited to the goal's scope. An edit that takes a
  /// transaction *out* of a goal's category moves no in-scope maximum, and a
  /// category move changes what a subtree matches without touching a
  /// transaction. Tag links need no term of their own: the repository's
  /// save path rewrites the transaction row with them (plan Decision 5).
  ///
  /// shortcut: wall-clock stamps, so a write stamped at or before the
  /// stored maximum (a clock set back, or the same millisecond) does not
  /// move it; and a hard delete leaves no stamp, though
  /// `TransactionsDao.deleteTransaction` has no caller. The next ordinary
  /// write or any goal edit heals it. Upgrade to a write counter if a user
  /// report traces back to either.
  Future<int> moneyWatermark() async {
    final row = await _db
        .customSelect('SELECT MAX(m) AS m FROM ('
            'SELECT MAX(updated_at) AS m FROM transactions '
            'UNION ALL SELECT MAX(updated_at) FROM categories '
            'UNION ALL SELECT MAX(updated_at) FROM tags)')
        .getSingle();
    return row.read<int?>('m') ?? 0;
  }

  /// The latest write to [trackerId]'s entries, deleted ones included, for
  /// the reason [moneyWatermark] gives. A write to `trackers` itself changes
  /// no measurement, since a goal names its tracker by id. Same shortcut as
  /// [moneyWatermark]; entries are only ever soft-deleted.
  Future<int> trackerWatermark(String trackerId) async {
    final row = await _db.customSelect(
      'SELECT MAX(updated_at) AS m FROM tracker_entries WHERE tracker_id = ?',
      variables: [Variable.withString(trackerId)],
    ).getSingle();
    return row.read<int?>('m') ?? 0;
  }

  /// Upserts only the alert state of (goal, period).
  Future<void> _writeAlerted(String goalId, DateRange period, int? percent) {
    final now = _now();
    return _db.into(_db.goalPeriodResults).insert(
          GoalPeriodResultsCompanion.insert(
            id: Ids.newId(),
            goalId: goalId,
            periodStart: period.startInclusive,
            periodEnd: period.endInclusive,
            lastAlertedPercent: Value(percent),
            createdAt: now,
            updatedAt: now,
          ),
          onConflict: DoUpdate(
            (_) => GoalPeriodResultsCompanion(
              lastAlertedPercent: Value(percent),
              updatedAt: Value(now),
            ),
            target: _periodKey,
          ),
        );
  }

  /// The UNIQUE (goal_id, period_start) index every write upserts against.
  List<Column<Object>> get _periodKey =>
      [_db.goalPeriodResults.goalId, _db.goalPeriodResults.periodStart];

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}
```

- [ ] **Step 9: Wire the DAOs into the database and the barrel**

In `packages/nimbus_data/lib/src/database/app_database.dart` (Phase 0):

1. After `import '../analytics/saved_view.dart';`, add:

```dart
import '../goals/goal_period_results_dao.dart';
import '../goals/goals_dao.dart';
```

2. After `late final TrackerEntriesDao trackerEntriesDao = TrackerEntriesDao(this);`, add:

```dart
  late final GoalsDao goalsDao = GoalsDao(this);
  late final GoalPeriodResultsDao goalPeriodResultsDao =
      GoalPeriodResultsDao(this);
```

No code generation is needed: the DAO getters live in the class body, not in drift's generated part.

In `packages/nimbus_data/lib/nimbus_data.dart`, after `export 'src/goals/engine_goal_measurer.dart';`, add:

```dart
export 'src/goals/goal_period_results_dao.dart';
export 'src/goals/goals_dao.dart';
```

- [ ] **Step 10: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_data && dart test test/goals/goals_dao_test.dart test/goals/goal_period_results_dao_test.dart test/goals/watermark_test.dart`

Expected: PASS. That is 19 + 6 + 9 = 34 tests.

**Mutation checks.**
1. In `recordCrossing`, replace `_db.transaction(() async { ... })` with its body run directly. Expected: "two evaluations of one crossing at once alert once" FAILS, with two alerts. Restore it.
2. In `writeValues`'s `DoUpdate`, add `lastAlertedPercent: const Value(null),`. Expected: "a value rewrite leaves the alert state alone" FAILS. Restore it.
3. In `moneyWatermark`, add `WHERE deleted_at IS NULL` to the transactions term. Expected: "moves on a soft delete" FAILS. Restore it.

- [ ] **Step 11: Measure the money watermark (plan Decision 4)**

Create the probe `packages/nimbus_data/test/goals/watermark_probe_test.dart`. **It is a measurement, never committed.**

```dart
import 'dart:io';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

/// Plan Decision 4: time MAX(updated_at) on 50 000 transactions in a file
/// database. Run once, copy the numbers into the commit message, delete
/// this file.
void main() {
  test('probe: the money watermark on 50 000 transactions', () async {
    final dir = Directory.systemTemp.createTempSync('nimbus-watermark-');
    final db = AppDatabase.openAtPath('${dir.path}/probe.sqlite');
    addTearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    await db.categoriesDao.insertNode(id: 'food', name: 'Food', parentId: null);
    // One statement, so the rows are one write rather than 50 000 fsyncs.
    await db.customStatement(
      'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n '
      'WHERE i < 50000) '
      'INSERT INTO transactions (id, direction, amount, currency_code, '
      'occurred_at_utc, local_date_key, tz_offset_minutes, category_id, '
      'source, is_confirmed, created_at, updated_at) '
      "SELECT printf('tx%06d', i), 'expense', 1000 + i % 977, 'IRT', i, "
      "20200101 + i % 28, 210, 'food', 'manual', 1, i, i FROM n",
    );

    Future<int> medianMicros(Future<void> Function() run) async {
      final times = <int>[];
      for (var i = 0; i < 11; i++) {
        final watch = Stopwatch()..start();
        await run();
        times.add((watch..stop()).elapsedMicroseconds);
      }
      times.sort();
      return times[5];
    }

    final plan = await db
        .customSelect(
            'EXPLAIN QUERY PLAN SELECT MAX(updated_at) FROM transactions')
        .get();
    final single = await medianMicros(() => db
        .customSelect('SELECT MAX(updated_at) AS m FROM transactions')
        .getSingle());
    final full = await medianMicros(db.goalPeriodResultsDao.moneyWatermark);

    stdout
      ..writeln('plan: ${plan.map((r) => r.read<String>('detail')).join(' | ')}')
      ..writeln('MAX(updated_at) FROM transactions: median $single us of 11')
      ..writeln('moneyWatermark(): median $full us of 11');
  });
}
```

Run, then delete:

```bash
cd packages/nimbus_data
dart test test/goals/watermark_probe_test.dart
rm test/goals/watermark_probe_test.dart
cd ../..
git status --short packages/nimbus_data/test/goals
```

Expected:
- The test passes and prints three lines. The plan line should be `plan: SCAN transactions`, since no index covers `updated_at`. Record the plan line, both medians and the host (this Windows machine) for the commit message.
- `git status` lists the three new test files and `support/`, and **not** `watermark_probe_test.dart`.

Decision:
- **Median ≤ 5 000 µs for `MAX(updated_at) FROM transactions`:** no index, as plan Decision 4 says. Continue.
- **Median above 5 000 µs:** still commit this task as written. The watermark is correct either way; an index only makes it faster. **Stop and raise it with the operator** before Task 9. An index is a schema change: a v41 lock on `main` within Phase 5's v40–v49. It is the operator's decision, never one made silently inside this task.

- [ ] **Step 12: Run the full gate**

Expected: all green. `nimbus_data` is 267 + 34 = **301**. The other suites are unchanged from Task 7's gate.

- [ ] **Step 13: Commit and merge**

Replace the four `<…>` placeholders with the numbers Step 11 printed before committing.

```bash
git add packages/nimbus_data/lib/src/goals/goals_dao.dart packages/nimbus_data/lib/src/goals/goal_period_results_dao.dart packages/nimbus_data/lib/src/database/app_database.dart packages/nimbus_data/lib/nimbus_data.dart packages/nimbus_data/test/goals
git commit -F - <<'EOF'
feat(goals): goal DAOs, and the watermarks that invalidate the cache

GoalsDao parses each row into a Goal. A row that does not parse
becomes a GoalUnreadable carrying its FormatException, never a
default, and it does not take the other goals down with it.

GoalPeriodResultsDao holds the per-period cache and the alert state
beside it. writeValues rewrites only the value and watermark columns,
so recomputing a stale period never forgets an alert already shown.
recordCrossing reads, decides and writes in one transaction. drift
runs that transaction alone on its connection, so two evaluations of
one crossing alert once.

The watermarks are table-wide maxima of updated_at, deleted rows
included. An edit out of scope and a category move both change what a
goal reads without touching an in-scope row. Tag edits ride on the
transaction row the repository rewrites with them; nothing
hard-deletes. Both were re-checked before this commit (Decision 5).

Measured on 50 000 transactions in a file database on the dev host,
median of 11 runs:
- MAX(updated_at) FROM transactions: <single> us, plan "<plan>";
- the three-table watermark: <full> us.
That is under the 5 ms bar, so there is no updated_at index (plan
Decision 4). <If over the bar: replace this paragraph's last sentence
with "Over the 5 ms bar: raised with the operator as a v41 decision.">

Touches Phase 0's app_database.dart for the two DAO getters.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only feat/goal-daos
```

---

### Task 9: `GoalService` — cache, re-baseline, cache-drop test

Branch `feat/goal-service`, slug `goal-service`.

**Files:**
- Create: `packages/nimbus_data/lib/src/goals/goal_service.dart`
- Modify: `packages/nimbus_data/lib/nimbus_data.dart` (barrel, one line)
- Test: `packages/nimbus_data/test/goals/goal_service_test.dart`, `packages/nimbus_data/test/goals/goal_cache_drop_test.dart`

**Interfaces:**
- Consumes:
  - Task 3: `GoalPeriods.current` / `closed` / `calendarFor`, `assess`.
  - Task 5: `foldDaily`, `PeriodOutcome`, `GoalStreaks`.
  - Task 6: `GoalEngine`, which exposes `measurer`, `today()`, `evaluate` and `evaluateCurrent`.
  - Task 7: `EngineGoalMeasurer` (tests).
  - Task 8: `GoalsDao`, `GoalPeriodResultsDao`, `CachedPeriod`, and the fixture builders.
- Produces, exactly as the contract states: `GoalHistoryResult`, `GoalPreview`, `GoalService`. The behaviours added in contract notes 7–9:
  - `check` returns null for a period that is not open;
  - a paused goal is not evaluated on save;
  - `preview` is built as note 9 describes.

- [ ] **Step 1: Branch**

```bash
git switch phase/5-goals
git switch -c feat/goal-service
```

- [ ] **Step 2: Write the failing tests**

Create `packages/nimbus_data/test/goals/goal_service_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/goal_fixture.dart';

void main() {
  late GoalFixture f;
  late _CountingMeasurer measurer;
  late GoalService service;
  late DateKey today;

  setUp(() async {
    f = await GoalFixture.open();
    measurer = _CountingMeasurer(f.measurer);
    today = const DateKey(20260210);
    service = GoalService(f.db, GoalEngine(measurer, today: () => today));
  });
  tearDown(() => f.db.close());

  DateRange range(int start, int end) =>
      DateRange(DateKey(start), DateKey(end));

  PeriodOutcome spent(int start, int end, int minor, GoalStatus status) =>
      PeriodOutcome(range(start, end), MoneyAmount(Money(minor)), status);

  Future<CachedPeriod?> rowFor(Goal goal, DateRange period) async {
    for (final row in await f.db.goalPeriodResultsDao.forGoal(goal.id)) {
      if (row.period == period) return row;
    }
    return null;
  }

  group('history', () {
    final goal = moneyGoal(
        period: const RecurringPeriod(PeriodType.month, DateKey(20251001)));

    // Against the 10 000 cap: October and November met, December over,
    // January met. Today is 10 February.
    Future<void> seed() async {
      await f.expense(1000, const DateKey(20251010));
      await f.expense(4000, const DateKey(20251110));
      await f.expense(12000, const DateKey(20251205));
      await f.expense(3000, const DateKey(20260115));
    }

    final expected = [
      spent(20251001, 20251031, 1000, GoalStatus.met),
      spent(20251101, 20251130, 4000, GoalStatus.met),
      spent(20251201, 20251231, 12000, GoalStatus.exceeded),
      spent(20260101, 20260131, 3000, GoalStatus.met),
    ];

    test('a first load measures every closed period with one daily query '
        'and caches it', () async {
      await seed();
      await service.save(goal);

      final result = await service.history(goal);

      expect(result.outcomes, expected);
      expect(result.streaks, const GoalStreaks(current: 1, best: 2));
      expect(measurer.dailySpans, [range(20251001, 20260131)]);
      final watermark = await f.db.goalPeriodResultsDao.moneyWatermark();
      for (final outcome in expected) {
        final row = await rowFor(goal, outcome.period);
        expect(row?.value, outcome.value);
        expect(row?.watermark, watermark);
      }
    });

    test('a second load with nothing written is served from the cache',
        () async {
      await seed();
      await service.save(goal);
      final first = await service.history(goal);

      final second = await service.history(goal);

      expect(measurer.dailySpans, hasLength(1));
      expect(second.outcomes, first.outcomes);
      expect(second.streaks, first.streaks);
    });

    test('any money write, even out of scope, makes the cache stale',
        () async {
      await seed();
      await service.save(goal);
      await ageMoneyRows(f.db);
      await service.history(goal);

      await f.expense(500, const DateKey(20260205), category: 'rent');
      final again = await service.history(goal);

      expect(measurer.dailySpans,
          [range(20251001, 20260131), range(20251001, 20260131)]);
      expect(again.outcomes, expected);
    });

    test('a period that closes after the last load is measured alone',
        () async {
      await seed();
      await service.save(goal);
      await ageMoneyRows(f.db);
      await service.history(goal);

      today = const DateKey(20260310);
      final later = await service.history(goal);

      expect(measurer.dailySpans.last, range(20260201, 20260228));
      expect(later.outcomes,
          [...expected, spent(20260201, 20260228, 0, GoalStatus.met)]);
    });
  });

  group('alert state', () {
    // Monthly from 1 January 2026, cap 10 000, alerts at 80 and 100.
    final goal = moneyGoal();
    const january = DateRange(DateKey(20260101), DateKey(20260131));

    test('a stale recompute keeps the alert its period already gave',
        () async {
      today = const DateKey(20260115);
      await service.save(goal);
      await f.expense(8500, const DateKey(20260110));
      expect((await service.check(goal))?.percent, 80);

      today = const DateKey(20260210);
      await ageMoneyRows(f.db);
      await service.history(goal);
      await f.expense(100, const DateKey(20260205), category: 'rent');
      await service.history(goal);

      final row = await rowFor(goal, january);
      expect(measurer.dailySpans, hasLength(2),
          reason: 'January was measured, then recomputed');
      expect(row!.value, const MoneyAmount(Money(8500)));
      expect(row.watermark, greaterThan(1));
      expect(row.lastAlerted, 80);
    });

    test('history never alerts: a closed period over its cap leaves no '
        'alert state', () async {
      await service.save(goal);
      await f.expense(50000, const DateKey(20260110));

      final result = await service.history(goal);

      expect(result.outcomes.single.status, GoalStatus.exceeded);
      expect((await rowFor(goal, january))!.lastAlerted, isNull);
      expect(await service.check(goal), isNull, reason: 'February is empty');
    });

    test('a fixed range that is over does not alert', () async {
      final savings = netSavingsGoal(january, target: 1000);
      await service.save(savings);
      await f.income(5000, const DateKey(20260110));

      expect(await service.check(savings), isNull);
      expect((await rowFor(savings, january))!.lastAlerted, isNull);
    });

    test('saving records what the goal already reaches, without an alert',
        () async {
      today = const DateKey(20260115);
      await f.expense(8500, const DateKey(20260110));
      await service.save(goal);

      expect(await service.check(goal), isNull);
      await f.expense(1500, const DateKey(20260112));
      expect((await service.check(goal))?.percent, 100);
    });

    test('an edit drops the cache and re-baselines without an alert',
        () async {
      today = const DateKey(20260115);
      final older = goal.copyWith(
          period: const RecurringPeriod(PeriodType.month, DateKey(20251201)));
      await f.expense(3000, const DateKey(20251205));
      await f.expense(8500, const DateKey(20260110));
      await service.save(older);
      await service.history(older);

      final tighter = older.copyWith(target: const MoneyAmount(Money(5000)));
      await service.save(tighter);

      expect(await service.check(tighter), isNull);
      final rows = await f.db.goalPeriodResultsDao.forGoal(goal.id);
      expect(rows.single.period, january,
          reason: "December's cached row went with the edit");
      expect(rows.single.lastAlerted, 100);
    });

    test('a paused goal is not checked and writes nothing', () async {
      today = const DateKey(20260115);
      final paused = goal.copyWith(active: false);
      await service.save(paused);
      await f.expense(9000, const DateKey(20260110));

      expect(await service.check(paused), isNull);
      expect(await f.db.goalPeriodResultsDao.forGoal(goal.id), isEmpty);
    });

    test('resuming re-baselines', () async {
      today = const DateKey(20260115);
      await service.save(goal);
      await service.setActive(goal, false);
      await f.expense(9000, const DateKey(20260110));

      await service.setActive(goal, true);

      expect(await service.check(goal), isNull);
      expect((await rowFor(goal, january))!.lastAlerted, 80);
    });

    test('restoring a deleted goal re-baselines', () async {
      today = const DateKey(20260115);
      await service.save(goal);
      await service.delete(goal.id);
      expect(await f.db.goalsDao.byId(goal.id), isNull);
      await f.expense(9000, const DateKey(20260110));

      await service.restore(goal.id);

      expect(await f.db.goalsDao.byId(goal.id), isA<GoalReadable>());
      expect(await service.check(goal), isNull);
    });
  });

  group("periods are the goal's, not the engine's", () {
    test('across the Gregorian new year', () async {
      final goal = moneyGoal(
          period: const RecurringPeriod(PeriodType.month, DateKey(20251115)));
      await f.expense(1000, const DateKey(20251231));
      await f.expense(2000, const DateKey(20260101));
      await service.save(goal);

      expect((await service.history(goal)).outcomes, [
        spent(20251101, 20251130, 0, GoalStatus.met),
        spent(20251201, 20251231, 1000, GoalStatus.met),
        spent(20260101, 20260131, 2000, GoalStatus.met),
      ]);
    });

    test('across Nowruz in a Jalali goal', () async {
      // Bahman 1404 is 21 Jan - 19 Feb 2026. Esfand 1404 has 29 days, 20 Feb
      // - 20 Mar. Farvardin 1405 is 21 Mar - 20 Apr. The engine's calendar
      // is Gregorian: goals hand it plain days.
      today = const DateKey(20260425);
      final goal = moneyGoal(
          calendar: CalendarKind.jalali,
          period: const RecurringPeriod(PeriodType.month, DateKey(20260215)));
      await f.expense(1000, const DateKey(20260320));
      await f.expense(2000, const DateKey(20260321));
      await service.save(goal);

      expect((await service.history(goal)).outcomes, [
        spent(20260121, 20260219, 0, GoalStatus.met),
        spent(20260220, 20260320, 1000, GoalStatus.met),
        spent(20260321, 20260420, 2000, GoalStatus.met),
      ]);
    });

    test("a weekly history starts its weeks on the goal's week start",
        () async {
      today = const DateKey(20260121);
      const since = RecurringPeriod(PeriodType.week, DateKey(20260105));
      final monday =
          moneyGoal(id: 'monday', period: since, weekStart: DateTime.monday);
      final saturday = moneyGoal(
          id: 'saturday', period: since, weekStart: DateTime.saturday);
      // Saturday 10 and Sunday 11 January 2026.
      await f.expense(1000, const DateKey(20260110));
      await f.expense(500, const DateKey(20260111));
      await service.save(monday);
      await service.save(saturday);

      expect((await service.history(monday)).outcomes, [
        spent(20260105, 20260111, 1500, GoalStatus.met),
        spent(20260112, 20260118, 0, GoalStatus.met),
      ]);
      expect((await service.history(saturday)).outcomes, [
        spent(20260103, 20260109, 0, GoalStatus.met),
        spent(20260110, 20260116, 1500, GoalStatus.met),
      ]);
    });
  });

  group('preview', () {
    test("shows a new draft's last three closed periods and writes nothing",
        () async {
      await f.expense(4000, const DateKey(20251110));
      await f.expense(12000, const DateKey(20251205));
      await f.expense(3000, const DateKey(20260115));
      await f.expense(2000, const DateKey(20260205));
      final draft = moneyGoal(period: RecurringPeriod(PeriodType.month, today));

      final preview = await service.preview(draft);

      expect(preview.recent, [
        spent(20251101, 20251130, 4000, GoalStatus.met),
        spent(20251201, 20251231, 12000, GoalStatus.exceeded),
        spent(20260101, 20260131, 3000, GoalStatus.met),
      ]);
      expect(preview.current.period, range(20260201, 20260228));
      expect(preview.current.current, const MoneyAmount(Money(2000)));
      expect(measurer.dailySpans, [range(20251101, 20260131)]);
      expect(await f.db.goalsDao.watchAll().first, isEmpty);
      expect(await f.db.goalPeriodResultsDao.forGoal(draft.id), isEmpty);
    });

    test('a fixed range has no recent periods', () async {
      await f.income(5000, const DateKey(20260110));

      final preview =
          await service.preview(netSavingsGoal(range(20260101, 20261231)));

      expect(preview.recent, isEmpty);
      expect(preview.current.current, const MoneyAmount(Money(5000)));
    });
  });
}

/// Delegates, and records each measureDaily span. This is how a test tells
/// a history served from the cache from a computed one.
final class _CountingMeasurer implements GoalMeasurer {
  _CountingMeasurer(this._inner);

  final GoalMeasurer _inner;
  final dailySpans = <DateRange>[];

  @override
  Future<GoalAmount> measure(
          GoalMetric metric, GoalScope scope, DateRange range) =>
      _inner.measure(metric, scope, range);

  @override
  Future<Map<DateKey, GoalAmount>> measureDaily(
      GoalMetric metric, GoalScope scope, DateRange span) {
    dailySpans.add(span);
    return _inner.measureDaily(metric, scope, span);
  }
}
```

Create `packages/nimbus_data/test/goals/goal_cache_drop_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/goal_fixture.dart';

/// The brief's definition of done: goal_period_results is a cache. Drop
/// every row, and history, streaks and progress come back identical.
void main() {
  late GoalFixture f;
  late GoalService service;
  const today = DateKey(20260210);

  setUp(() async {
    f = await GoalFixture.open();
    service = GoalService(f.db, GoalEngine(f.measurer, today: () => today));
  });
  tearDown(() => f.db.close());

  Future<void> expectSurvivesTheDrop(Goal goal) async {
    await service.save(goal);
    final computed = await service.history(goal);
    final cached = await service.history(goal);
    final progress = await service.engine.evaluateCurrent(goal);
    expect(computed.outcomes, isNotEmpty);

    await f.db.customStatement('DELETE FROM goal_period_results');

    final rebuilt = await service.history(goal);
    expect(cached.outcomes, computed.outcomes);
    expect(cached.streaks, computed.streaks);
    expect(rebuilt.outcomes, computed.outcomes);
    expect(rebuilt.streaks, computed.streaks);
    expect(await service.engine.evaluateCurrent(goal), progress);
    expect(await f.db.goalPeriodResultsDao.forGoal(goal.id),
        hasLength(computed.outcomes.length),
        reason: 'the history rebuilt a row per closed period');
  }

  test('a money goal', () async {
    await f.expense(1000, const DateKey(20251010));
    await f.expense(12000, const DateKey(20251105));
    await f.expense(4000, const DateKey(20251220));
    await f.expense(9000, const DateKey(20260131));
    await f.expense(2500, const DateKey(20260203));

    await expectSurvivesTheDrop(moneyGoal(
        period: const RecurringPeriod(PeriodType.month, DateKey(20251001))));
  });

  test('a tracker goal', () async {
    // Saturday weeks from 3 Jan; the current week is 7 - 13 Feb.
    for (final (day, litres) in const [
      (20260105, 0.5), (20260106, 0.75), (20260108, 1.0),
      (20260111, 0.25),
      (20260118, 1.5), (20260120, 0.5),
      (20260126, 0.25),
      (20260201, 2.25),
      (20260208, 0.5),
    ]) {
      await f.log('water', DateKey(day), value: litres);
    }

    await expectSurvivesTheDrop(trackerGoal('water',
        metric: GoalMetric.trackerSum,
        direction: GoalDirection.atLeast,
        target: 2,
        period: const RecurringPeriod(PeriodType.week, DateKey(20260103))));
  });
}
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_data && dart test test/goals/goal_service_test.dart test/goals/goal_cache_drop_test.dart`

Expected: FAIL to compile, naming `GoalService` (`Type 'GoalService' not found`).

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-goal-service
```

- [ ] **Step 5: Implement the service**

Create `packages/nimbus_data/lib/src/goals/goal_service.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';

import '../database/app_database.dart';
import 'goal_period_results_dao.dart';
import 'goals_dao.dart';

/// A goal's closed periods with their outcomes, oldest first, and the
/// streaks they make.
final class GoalHistoryResult {
  const GoalHistoryResult(this.outcomes, this.streaks);

  final List<PeriodOutcome> outcomes;
  final GoalStreaks streaks;

  @override
  String toString() => 'GoalHistoryResult(${outcomes.length} periods, '
      'streak ${streaks.current}/${streaks.best})';
}

/// What the editor shows beside a draft (goals design §5.3).
final class GoalPreview {
  const GoalPreview(this.recent, this.current);

  final List<PeriodOutcome> recent;
  final GoalProgress current;
}

/// Goals' data-layer service. It owns the per-period cache, re-baselining
/// and alert recording, which share one transaction boundary (plan
/// Decision 1).
///
/// The Goals tab asks for several histories at once (`Future.wait`). drift
/// runs them on its one connection, so there is no parallelism to cap.
final class GoalService {
  GoalService(this._db, this.engine);

  final AppDatabase _db;

  /// Must measure through the same [AppDatabase] as this service. [save]
  /// measures inside a drift transaction, and a transaction routes only its
  /// own database's statements.
  final GoalEngine engine;

  GoalsDao get _goals => _db.goalsDao;
  GoalPeriodResultsDao get _results => _db.goalPeriodResultsDao;

  /// Closed periods, oldest first, served from the cache where the
  /// watermark matches (spec §3). The current period is never served from
  /// the cache: it is measured live, and its row only holds alert state.
  Future<GoalHistoryResult> history(Goal goal) async {
    final today = engine.today();
    final periods = GoalPeriods.closed(goal, today);
    if (periods.isEmpty) {
      return const GoalHistoryResult(<PeriodOutcome>[], GoalStreaks.none);
    }
    // Read before measuring. A write that lands mid-measure then leaves the
    // rows stamped with the older watermark, so the next load recomputes
    // them. Read after, it would stamp old values as current for ever.
    final watermark = await _watermark(goal);
    final values = <DateRange, GoalAmount>{
      for (final row in await _results.forGoal(goal.id))
        if (row.watermark == watermark && row.value != null)
          row.period: row.value!,
    };
    final stale = [
      for (final period in periods)
        if (!values.containsKey(period)) period,
    ];
    if (stale.isNotEmpty) {
      final measured = await _measured(goal, stale);
      await _results.writeValues(
        goal.id,
        [
          for (final (i, period) in stale.indexed)
            (period: period, value: measured[i]),
        ],
        watermark,
      );
      for (final (i, period) in stale.indexed) {
        values[period] = measured[i];
      }
    }
    final outcomes = [
      for (final period in periods)
        _outcome(goal, period, values[period]!, today),
    ];
    return GoalHistoryResult(outcomes, GoalStreaks.of(outcomes));
  }

  /// Evaluates the current period and records a crossing. Returns null,
  /// writing nothing, for a paused goal or a period that is not open.
  Future<GoalAlert?> check(Goal goal) async {
    if (!goal.active) return null;
    final today = engine.today();
    final period = GoalPeriods.current(goal, today);
    // Only an open period alerts. A fixed range not yet begun, or already
    // over, is as closed as last month is (spec §4.1).
    if (!period.contains(today)) return null;
    return _results.recordCrossing(goal, await engine.evaluate(goal, period));
  }

  /// Upsert, drop the cache, evaluate, baseline: one transaction (§4.3).
  Future<void> save(Goal goal) => _db.transaction(() async {
        await _goals.upsert(goal);
        await _rebaseline(goal);
      });

  /// Resuming re-baselines; pausing writes only the flag.
  Future<void> setActive(Goal goal, bool active) async {
    if (!active) return _goals.setActive(goal.id, false);
    await _db.transaction(() async {
      await _goals.setActive(goal.id, true);
      await _rebaseline(goal.copyWith(active: true));
    });
  }

  Future<void> delete(String id) => _goals.softDelete(id);

  /// Restores and re-baselines, because progress may have moved while the
  /// goal was deleted (plan Decision 8). An unreadable row is only
  /// restored: there is no goal to evaluate, and its card offers only
  /// Delete.
  Future<void> restore(String id) => _db.transaction(() async {
        await _goals.restore(id);
        final read = await _goals.byId(id);
        if (read is GoalReadable) await _rebaseline(read.goal);
      });

  /// The draft's last [periods] closed periods and its current progress.
  /// No cache, and no writes: a draft has no row to cache under.
  Future<GoalPreview> preview(Goal draft, {int periods = 3}) async {
    final today = engine.today();
    final current =
        await engine.evaluate(draft, GoalPeriods.current(draft, today));
    final recent = switch (draft.period) {
      FixedRangePeriod() => const <PeriodOutcome>[],
      RecurringPeriod(:final type) =>
        await _recent(draft, type, current.period, periods, today),
    };
    return GoalPreview(recent, current);
  }

  /// The [count] periods before [current], as if the draft had started
  /// early enough to have them. A new draft's `since` is today, so it has
  /// no closed periods of its own.
  Future<List<PeriodOutcome>> _recent(Goal draft, PeriodType type,
      DateRange current, int count, DateKey today) async {
    final calendar = GoalPeriods.calendarFor(draft.calendar);
    final since = calendar.shiftPeriod(current, type, -count).startInclusive;
    final early = draft.copyWith(period: RecurringPeriod(type, since));
    final closed = GoalPeriods.closed(early, today);
    final values = await _measured(early, closed);
    return [
      for (final (i, period) in closed.indexed)
        _outcome(early, period, values[i], today),
    ];
  }

  /// Spec §4.3. Drop the goal's cached rows -- after an edit their period
  /// keys may not be this goal's any more -- then record whatever the
  /// current period already reaches as alerted, without an alert. A paused
  /// goal is not evaluated; resuming re-baselines it.
  Future<void> _rebaseline(Goal goal) async {
    await _results.deleteForGoal(goal.id);
    if (!goal.active) return;
    await _results.setBaseline(goal, await engine.evaluateCurrent(goal));
  }

  Future<int> _watermark(Goal goal) => switch (goal.scope) {
        MoneyScope() => _results.moneyWatermark(),
        TrackerScope(:final trackerId) => _results.trackerWatermark(trackerId),
      };

  /// One daily measurement over the span [periods] cover, folded into one
  /// value per period.
  Future<List<GoalAmount>> _measured(
      Goal goal, List<DateRange> periods) async {
    if (periods.isEmpty) return const <GoalAmount>[];
    final daily = await engine.measurer.measureDaily(goal.metric, goal.scope,
        DateRange(periods.first.startInclusive, periods.last.endInclusive));
    return foldDaily(daily, periods, goal.target.zero);
  }

  static PeriodOutcome _outcome(
          Goal goal, DateRange period, GoalAmount value, DateKey today) =>
      PeriodOutcome(period, value, assess(goal, period, value, today).status);
}
```

In `packages/nimbus_data/lib/nimbus_data.dart`, after `export 'src/goals/goal_period_results_dao.dart';`, add:

```dart
export 'src/goals/goal_service.dart';
```

- [ ] **Step 6: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_data && dart test test/goals/goal_service_test.dart test/goals/goal_cache_drop_test.dart`

Expected: PASS. That is 17 + 2 = 19 tests.

**Mutation checks.**
1. In `history`, match a cached row on `row.value != null` alone, dropping the watermark comparison. Expected: "any money write, even out of scope, makes the cache stale" and "a stale recompute keeps the alert its period already gave" FAIL. Restore it.
2. In `check`, delete the `if (!period.contains(today)) return null;` guard. Expected: "a fixed range that is over does not alert" FAILS. Restore it.
3. In `_rebaseline`, delete `await _results.deleteForGoal(goal.id);`. Expected: "an edit drops the cache and re-baselines without an alert" FAILS. Restore it.

- [ ] **Step 7: Run the full gate**

Expected: all green. `nimbus_data` is 301 + 19 = **320**. The other suites are unchanged from Task 8's gate.

- [ ] **Step 8: Commit and merge**

```bash
git add packages/nimbus_data/lib/src/goals/goal_service.dart packages/nimbus_data/lib/nimbus_data.dart packages/nimbus_data/test/goals/goal_service_test.dart packages/nimbus_data/test/goals/goal_cache_drop_test.dart
git commit -F - <<'EOF'
feat(goals): GoalService -- history from a self-healing cache

history serves each closed period from goal_period_results when its
watermark is current. It recomputes the rest with one daily
measurement, folded into periods. The watermark is read before
measuring, so a write that lands mid-measure leaves those rows stale
rather than stamping old values as current. Dropping every cached row
costs nothing but time, as goal_cache_drop_test proves.

save, resume and restore re-baseline in one transaction. The cached
rows go, and whatever the current period already reaches is recorded
as alerted, without an alert: the user is looking at the goal they
have just changed. check alerts only for an open period of an active
goal, so neither last month nor a finished fixed range ever warns.

preview measures a draft's last closed periods the same way, without
the cache and without writing.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only feat/goal-service
```

---

### Task 10: Providers and `GoalWatcher`

Branch `feat/goal-watcher`, slug `goal-watcher`.

**Files:**
- Create: `app/lib/features/goals/application/goal_providers.dart`
- Create: `app/lib/features/goals/application/goal_watcher.dart`
- Test: `app/test/features/goals/support/goal_test_app.dart` (new), `app/test/features/goals/goal_watcher_test.dart` (new)

**Interfaces:**
- Consumes:
  - From Tasks 2–6: `Goal`, `GoalAmount`, `GoalProgress`, `GoalAlert`, `GoalEngine`, `RecurringPeriod`, `FixedRangePeriod`, `MoneyScope` and `TrackerScope`.
  - From Tasks 7–9: `EngineGoalMeasurer`, `GoalService`, `GoalRead`/`GoalReadable`/`GoalUnreadable`, and `AppDatabase.goalsDao.watchAll()`.
  - Read-only imports: `analyticsEngineProvider` (Phase 3), `trackerClockProvider` (Phase 4).
- Produces:
  - `goalTodayProvider` (`NotifierProvider<GoalToday, DateKey>`, with `refresh()`).
  - `goalServiceProvider`, `goalsProvider`, `goalProgressProvider` and `goalHistoryProvider`, as the contract types them.
  - `GoalWatcher(Ref, {Duration debounce})`, with `alerts`, `start()`, `stop()` and `dispose()` (Contract note 1).
  - `goalWatcherProvider`.
  - Test support:
    - `seedCategories(db)`; `foodPath`, `diningPath`, `transportPath`.
    - `spend(db, amount, day, {category})` and `earn(db, amount, day)`.
    - `goalServiceFor(db, today)`.
    - The builders `spendingCap(...)`, `habitGoal(tracker, ...)` and `savingsTarget(...)`.

- [ ] **Step 1: Branch**

```bash
git switch phase/5-goals
git switch -c feat/goal-watcher
```

- [ ] **Step 2: Write the failing tests**

Create `app/test/features/goals/support/goal_test_app.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/transactions/data/transaction_draft.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';

/// What every goals test stands on:
/// - categories to scope by;
/// - money moved on a chosen day;
/// - a service that writes goals the way the app does;
/// - one goal of each kind.

/// Food (with Dining) and Transport, plus the Uncategorized row every
/// transaction may fall back to.
Future<void> seedCategories(AppDatabase db) async {
  await CategorySeeder(db).seedIfEmpty(
    roots: const [
      SeedCategoryNode(id: 'seed-food', name: 'Food', children: [
        SeedCategoryNode(id: 'seed-dining', name: 'Dining'),
      ]),
      SeedCategoryNode(id: 'seed-transport', name: 'Transport'),
    ],
    uncategorizedName: 'Uncategorized',
  );
}

/// The seeded categories' materialized paths (`/rootId/childId/`).
const foodPath = '/seed-food/';
const diningPath = '/seed-food/seed-dining/';
const transportPath = '/seed-transport/';

/// One expense of [amount] on [day].
Future<void> spend(AppDatabase db, int amount, DateKey day,
        {String category = 'seed-dining'}) =>
    _record(db, amount, day, TxDirection.expense, category);

/// One income of [amount] on [day]: what a savings target counts up.
Future<void> earn(AppDatabase db, int amount, DateKey day) => _record(
    db, amount, day, TxDirection.income, SystemCategoryIds.uncategorized);

Future<void> _record(AppDatabase db, int amount, DateKey day,
    TxDirection direction, String category) async {
  await TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman)
      .add(TransactionDraft(
    amount: Money(amount),
    direction: direction,
    categoryId: category,
    // Noon UTC is the same date in every zone from UTC-11 to UTC+11, so the
    // repository's local date key cannot move it to the day next door.
    occurredAtUtc: DateTime.utc(day.year, day.month, day.day, 12),
  ));
}

/// A service over [db] whose today is [today], built as the app builds
/// `goalServiceProvider`. The engine's calendar is irrelevant here: a goal
/// hands it plain date keys.
GoalService goalServiceFor(AppDatabase db, DateKey Function() today) =>
    GoalService(
      db,
      GoalEngine(
        EngineGoalMeasurer(
            db, AnalyticsEngine(db, calendar: const JalaliCalendar())),
        today: today,
      ),
    );

/// A monthly cap on Dining, in the app's default calendar.
Goal spendingCap({
  String id = 'cap',
  String name = 'Dining out',
  int target = 1000000,
  List<String> paths = const [diningPath],
  PeriodType period = PeriodType.month,
  DateKey since = const DateKey(20260101),
  CalendarKind calendar = CalendarKind.jalali,
  List<int> alerts = Goal.defaultAlertPercents,
}) =>
    Goal(
      id: id,
      name: name,
      metric: GoalMetric.moneySum,
      scope: MoneyScope(QueryFilters(
          direction: MoneyDirection.expense, categorySubtreePaths: paths)),
      direction: GoalDirection.atMost,
      target: MoneyAmount(Money(target)),
      period: RecurringPeriod(period, since),
      calendar: calendar,
      weekStart: DateTime.saturday,
      alertPercents: alerts,
    );

/// A habit limit (the default) or a habit goal over [tracker].
Goal habitGoal(
  Tracker tracker, {
  String id = 'habit',
  GoalMetric metric = GoalMetric.trackerCount,
  GoalDirection direction = GoalDirection.atMost,
  double target = 5,
  PeriodType period = PeriodType.day,
  DateKey since = const DateKey(20260101),
  List<int> alerts = Goal.defaultAlertPercents,
}) =>
    Goal(
      id: id,
      name: tracker.name,
      metric: metric,
      scope: TrackerScope(tracker.id),
      direction: direction,
      target: QuantityAmount(target),
      period: RecurringPeriod(period, since),
      calendar: CalendarKind.jalali,
      weekStart: DateTime.saturday,
      alertPercents: alerts,
    );

/// Six million by the end of March 2027, Gregorian: six months from
/// 2026-10-05, October included.
Goal savingsTarget({
  String id = 'savings',
  String name = 'Car',
  int target = 6000000,
  DateRange range = const DateRange(DateKey(20261001), DateKey(20270331)),
}) =>
    Goal(
      id: id,
      name: name,
      metric: GoalMetric.netSavings,
      scope: MoneyScope(const QueryFilters()),
      direction: GoalDirection.atLeast,
      target: MoneyAmount(Money(target)),
      period: FixedRangePeriod(range),
      calendar: CalendarKind.gregorian,
      weekStart: DateTime.saturday,
    );
```

Create `app/test/features/goals/goal_watcher_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/provider_retry.dart';
import 'package:nimbustats/features/analytics/application/analytics_providers.dart';
import 'package:nimbustats/features/goals/application/goal_providers.dart';
import 'package:nimbustats/features/goals/application/goal_watcher.dart';
import 'package:nimbustats/features/settings/application/settings_providers.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';

import '../trackers/support/tracker_fixture.dart';
import 'support/goal_test_app.dart';

/// The watcher as the app runs it: real providers over a test database, on
/// the real clock for timing (the debounce is a real 300 ms), standing on
/// the fake's date.
void main() {
  late FakeClock fake;
  late AppDatabase db;
  late GoalService service;
  late List<GoalAlert> alerts;
  ProviderContainer? started;

  const day5 = DateKey(20261005);
  const day6 = DateKey(20261006);

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    service = goalServiceFor(db, fake.clock.today);
    alerts = [];
    started = null;
    await seedCategories(db);
  });
  tearDown(() async {
    started?.dispose();
    await db.close();
  });

  ProviderContainer container() => started!;

  /// The app's providers over the test database, wired as main() wires
  /// them, with the watcher started and its alerts collected.
  Future<GoalWatcher> start() async {
    final c = ProviderContainer(retry: nimbusNoRetry, overrides: [
      appDatabaseProvider.overrideWithValue(db),
      ...trackerOverrides(fake),
    ]);
    started = c;
    // Settings first, so their first emission is not mistaken for a
    // calendar switch.
    final settings = c.listen(settingsProvider, (_, __) {});
    addTearDown(settings.close);
    await c.read(settingsProvider.future);
    final watcher = c.read(goalWatcherProvider);
    final subscription = watcher.alerts.listen(alerts.add);
    addTearDown(subscription.cancel);
    watcher.start();
    return watcher;
  }

  /// Waits on the real clock until [done]: drift and the debounce settle in
  /// their own time.
  Future<void> until(bool Function() done, String what) async {
    for (var i = 0; i < 300; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('timed out waiting for $what');
  }

  /// Long enough for a debounce and an evaluation to have happened, for
  /// asserting that something did *not*.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 700));

  List<int> percents() => [for (final alert in alerts) alert.percent];

  test('a crossing made while the app was closed alerts once, at start',
      () async {
    await service.save(spendingCap()); // the baseline: nothing spent
    await spend(db, 850000, day5); // a background SMS capture, say
    final watcher = await start();
    await until(() => alerts.length == 1, 'the start-up alert');
    expect(alerts.single.goalId, 'cap');
    expect(alerts.single.percent, 80);

    // The app starts again: nothing new crossed, so nothing alerts.
    watcher
      ..stop()
      ..start();
    await settle();
    expect(alerts, hasLength(1));
  });

  test('a burst of writes inside the debounce is evaluated once', () async {
    await service.save(spendingCap());
    await start();
    await settle();

    await spend(db, 850000, day5);
    // Shorter than the debounce, longer than an evaluation: without the
    // debounce the first write alone would alert at 80.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await spend(db, 200000, day5);
    await until(() => alerts.isNotEmpty, 'the alert');
    await settle();

    expect(percents(), [100], reason: 'one evaluation, one alert at the top');
  });

  test("a calendar switch keeps each goal's own calendar and re-fires nothing",
      () async {
    // Review Focus 2. 2026-09-25 is inside the Jalali month that holds
    // today (1405/07 starts on 09-23) but outside Gregorian October, so a
    // goal that took the app's new calendar would lose this spending.
    final mehr =
        const JalaliCalendar().periodContaining(day5, PeriodType.month);
    await service.save(spendingCap());
    await spend(db, 850000, const DateKey(20260925));
    await start();
    await until(() => alerts.length == 1, 'the start-up alert');

    await SettingsRepository(db.settingsDao).save(
        AppSettings.defaults.copyWith(calendarKind: CalendarKind.gregorian));
    await until(
        () =>
            container().read(analyticsEngineProvider).calendar
                is GregorianCalendar,
        'the engine to take the new calendar');
    await spend(db, 10000, day5);
    await settle();
    expect(percents(), [80], reason: 'the rebuilt engine must not re-fire');

    final progress =
        container().listen(goalProgressProvider(spendingCap()), (_, __) {});
    addTearDown(progress.close);
    await until(
        () =>
            progress.read().value?.current == const MoneyAmount(Money(860000)),
        "the progress in the goal's own month");
    expect(progress.read().requireValue.period, mehr);

    await spend(db, 200000, day5);
    await until(() => alerts.length == 2, 'the 100% crossing');
    expect(percents(), [80, 100]);
  });

  test('the first crossing on a new day alerts again', () async {
    // Review Focus 3: yesterday's alert state belongs to yesterday's row.
    final daily = spendingCap(
        id: 'daily',
        name: 'Coffee',
        target: 100000,
        period: PeriodType.day,
        alerts: const [100]);
    await service.save(daily);
    await start();
    await settle();
    await spend(db, 120000, day5);
    await until(() => alerts.length == 1, "today's crossing");

    fake.advance(const Duration(days: 1));
    container().read(goalTodayProvider.notifier).refresh();
    await settle();
    expect(alerts, hasLength(1), reason: 'a new day starts from nothing');

    await spend(db, 120000, day6);
    await until(() => alerts.length == 2, "the new day's crossing");
    expect(alerts.last.period, const DateRange(day6, day6));
  });

  test('a new day is evaluated without waiting for a write', () async {
    // Spending dated tomorrow, entered today. Nothing writes at midnight, so
    // only the day change itself can find the crossing.
    await service.save(spendingCap(
        id: 'daily',
        name: 'Coffee',
        target: 100000,
        period: PeriodType.day,
        alerts: const [100]));
    await spend(db, 120000, day6);
    await start();
    await settle();
    expect(alerts, isEmpty);

    fake.advance(const Duration(days: 1));
    container().read(goalTodayProvider.notifier).refresh();
    await until(() => alerts.length == 1, "the new day's evaluation");
    expect(alerts.single.period, const DateRange(day6, day6));
  });

  test('a paused goal never alerts', () async {
    await service.save(spendingCap());
    await service.setActive(spendingCap(), false);
    await spend(db, 950000, day5);
    await start();
    await settle();
    expect(alerts, isEmpty);
  });

  test('a tracker entry evaluates tracker goals', () async {
    final trackers = repositoryFor(db, fake);
    final cig = await trackers.create(cigarettes);
    await service.save(habitGoal(cig, id: 'smoke', target: 2, alerts: const [100]));
    await start();
    await settle();

    await trackers.logEntry(cig.id);
    await trackers.logEntry(cig.id);
    await until(() => alerts.length == 1, 'the limit reached');
    expect(alerts.single.goalId, 'smoke');
    expect(alerts.single.direction, GoalDirection.atMost);
  });

  test('stop drops a pending evaluation; start picks the crossing up',
      () async {
    await service.save(spendingCap());
    final watcher = await start();
    await settle();

    await spend(db, 850000, day5);
    watcher.stop();
    await settle();
    expect(alerts, isEmpty, reason: 'a stopped watcher evaluates nothing');

    watcher.start();
    await until(() => alerts.length == 1, 'the start-up evaluation');
    expect(percents(), [80]);
  });

  test("a goal's progress re-runs on a write and keeps its value meanwhile",
      () async {
    await service.save(spendingCap());
    await start();
    final states = <AsyncValue<GoalProgress>>[];
    final subscription = container().listen(
        goalProgressProvider(spendingCap()), (_, next) => states.add(next),
        fireImmediately: true);
    addTearDown(subscription.close);
    await until(() => states.last.hasValue, 'the first answer');
    expect(states.last.requireValue.current, const MoneyAmount(Money(0)));

    await spend(db, 300000, day5);
    await until(
        () =>
            states.last.value?.current == const MoneyAmount(Money(300000)),
        'the re-run');
    final first = states.indexWhere((state) => state.hasValue);
    expect([for (final state in states.skip(first)) if (!state.hasValue) state],
        isEmpty,
        reason: 'the card would flash its skeleton: $states');
  });
}
```

- [ ] **Step 3: Run the tests to confirm RED**

Run from the repo root:

```bash
(cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/goal_watcher_test.dart)
```

Expected: FAIL to compile, naming `package:nimbustats/features/goals/application/goal_providers.dart` and `goal_watcher.dart` (files not found), so `goalWatcherProvider`, `goalTodayProvider` and `goalProgressProvider` are undefined.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-goal-watcher
```

- [ ] **Step 5: Write the providers**

Create `app/lib/features/goals/application/goal_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../bootstrap/database_provider.dart';
import '../../analytics/application/analytics_providers.dart';
import '../../trackers/application/tracker_providers.dart';

/// Today's local date, as the goals see it.
///
/// Read off the trackers' clock (imported read-only), so the app has one
/// clock and a test moves both features with one fake.
///
/// It is not re-read on every build: a goal left open overnight has to be
/// told the day changed. The shell's `GoalAlertListener` does that at local
/// midnight and on every resume. The trackers' own rollover is mounted only
/// on tracker screens, so it cannot serve the goals.
class GoalToday extends Notifier<DateKey> {
  @override
  DateKey build() => ref.watch(trackerClockProvider).today();

  /// Re-reads the clock. Changes nothing until the date has moved, so a
  /// resume at noon rebuilds nothing.
  void refresh() {
    final today = ref.read(trackerClockProvider).today();
    if (today != state) state = today;
  }
}

final goalTodayProvider = NotifierProvider<GoalToday, DateKey>(GoalToday.new);

/// The goals' one way into and out of the database.
///
/// It is rebuilt when the engine is (a calendar switch rebuilds it) and when
/// the day moves. The engine's `today` is therefore always
/// [goalTodayProvider]'s, and the watcher, the cards and the detail screen
/// agree on one day.
///
/// A calendar switch changes nothing a goal measures. Each goal computes its
/// periods in its own calendar and hands the engine plain date keys (spec,
/// finding 2).
final goalServiceProvider = Provider<GoalService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final today = ref.watch(goalTodayProvider);
  return GoalService(
    db,
    GoalEngine(
      EngineGoalMeasurer(db, ref.watch(analyticsEngineProvider)),
      // A value, not a provider read: a service still held across a rebuild
      // must not reach for a ref that has gone.
      today: () => today,
    ),
  );
});

/// Every live goal, active and paused, oldest first.
///
/// A row that does not parse arrives as [GoalUnreadable] rather than as an
/// error, so one bad row costs one card, not the tab. Kept alive: the
/// shell's watcher reads it for as long as the app runs.
final goalsProvider = StreamProvider<List<GoalRead>>(
    (ref) => ref.watch(appDatabaseProvider).goalsDao.watchAll());

/// Re-runs the provider behind [ref] whenever a write could move [goal]'s
/// numbers. For a money goal that is a transaction, category or tag write;
/// for a tracker goal, a tracker entry write. Mirrors
/// `analyticsResultProvider` and `trackerResultProvider`.
void _rerunOnWrites(Ref ref, Goal goal) {
  final engine = ref.watch(analyticsEngineProvider);
  final writes =
      goal.scope is TrackerScope ? engine.trackerChanges() : engine.changes();
  final subscription = writes.listen((_) => ref.invalidateSelf());
  ref.onDispose(subscription.cancel);
}

/// One goal's current period, measured live. The current period is never
/// served from the cache (spec §3).
///
/// Keyed on the goal itself, which has value equality, so an edited goal is
/// a new question.
///
/// Screens read `hasError`, `hasValue` and `requireValue` directly. Each of
/// these keeps the previous value through both a write's re-run and a reload
/// (a calendar switch, a new day). 4b's `deriveKeepingValue` exists for
/// *derived* views, and nothing here derives.
final goalProgressProvider =
    FutureProvider.autoDispose.family<GoalProgress, Goal>((ref, goal) {
  final service = ref.watch(goalServiceProvider);
  _rerunOnWrites(ref, goal);
  return service.engine.evaluateCurrent(goal);
});

/// One goal's closed periods and streaks, served from the self-healing
/// cache (spec §3).
final goalHistoryProvider =
    FutureProvider.autoDispose.family<GoalHistoryResult, Goal>((ref, goal) {
  final service = ref.watch(goalServiceProvider);
  _rerunOnWrites(ref, goal);
  return service.history(goal);
});
```

- [ ] **Step 6: Write the watcher**

Create `app/lib/features/goals/application/goal_watcher.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../analytics/application/analytics_providers.dart';
import 'goal_providers.dart';

/// Decides, while the app runs, that a goal has crossed one of its alert
/// percents (spec §4.1).
///
/// [alerts] is the stream Phase 6 subscribes to. Until then, the shell shows
/// each alert as a snackbar.
///
/// It evaluates every active goal's current period:
/// - once when [start]ed, for crossings made while the app was closed (a
///   background SMS capture, say);
/// - after a transaction, category or tag write, for money goals;
/// - after a tracker entry write, for tracker goals;
/// - when the day changes, because a new period may have begun.
///
/// How it evaluates:
/// - Every trigger waits [debounce] for the next, so a burst of taps is
///   evaluated once.
/// - Every evaluation goes through `GoalService.check`, which records the
///   crossing in one transaction. A recomputation therefore never re-fires,
///   and two evaluators cannot fire one crossing twice.
/// - Closed periods never alert.
///
/// It is a plain class held by [goalWatcherProvider], which never rebuilds.
/// The watcher follows its inputs with `ref.listen`, never `ref.watch`, so
/// one [alerts] stream lasts the life of the app. A calendar switch rebuilds
/// the engine, and the watcher moves its write subscriptions to the new one.
final class GoalWatcher {
  GoalWatcher(this._ref, {this.debounce = const Duration(milliseconds: 300)});

  final Ref _ref;
  final Duration debounce;

  final _alerts = StreamController<GoalAlert>.broadcast();
  final _following = <ProviderSubscription<Object?>>[];
  StreamSubscription<void>? _moneyWrites;
  StreamSubscription<void>? _trackerWrites;
  Timer? _pending;
  var _moneyDue = false;
  var _trackersDue = false;

  /// Every crossing, once.
  Stream<GoalAlert> get alerts => _alerts.stream;

  /// Starts watching, and evaluates every goal as soon as the goals have
  /// loaded. Starting a running watcher does nothing.
  void start() {
    if (_following.isNotEmpty) return;
    _following.addAll([
      _ref.listen<AnalyticsEngine>(
          analyticsEngineProvider, (_, engine) => _follow(engine),
          fireImmediately: true),
      _ref.listen<AsyncValue<List<GoalRead>>>(goalsProvider, (previous, next) {
        // The first list is the start-up evaluation. Later lists come from
        // edits, which re-baseline silently (spec §4.3), so they have
        // nothing to say.
        if (next.hasValue && !(previous?.hasValue ?? false)) {
          _due(money: true, trackers: true);
        }
      }, fireImmediately: true),
      _ref.listen<DateKey>(
          goalTodayProvider, (_, __) => _due(money: true, trackers: true)),
    ]);
  }

  /// Stops watching and drops an evaluation that has not begun. [start]
  /// resumes.
  ///
  /// The shell calls this when it unmounts. The debounce timer lives here,
  /// in a provider that outlives the widget tree, and would otherwise run on
  /// after the screen that shows the alerts has gone.
  void stop() {
    for (final subscription in _following) {
      subscription.close();
    }
    _following.clear();
    _pending?.cancel();
    _pending = null;
    _moneyDue = false;
    _trackersDue = false;
    unawaited(_moneyWrites?.cancel());
    unawaited(_trackerWrites?.cancel());
    _moneyWrites = null;
    _trackerWrites = null;
  }

  Future<void> dispose() async {
    stop();
    await _alerts.close();
  }

  void _follow(AnalyticsEngine engine) {
    unawaited(_moneyWrites?.cancel());
    unawaited(_trackerWrites?.cancel());
    _moneyWrites = engine.changes().listen((_) => _due(money: true));
    _trackerWrites =
        engine.trackerChanges().listen((_) => _due(trackers: true));
  }

  void _due({bool money = false, bool trackers = false}) {
    _moneyDue |= money;
    _trackersDue |= trackers;
    _pending?.cancel();
    _pending = Timer(debounce, () => unawaited(_evaluate()));
  }

  Future<void> _evaluate() async {
    _pending = null;
    final money = _moneyDue;
    final trackers = _trackersDue;
    _moneyDue = false;
    _trackersDue = false;
    final goals = [
      for (final read in _ref.read(goalsProvider).value ?? const <GoalRead>[])
        if (read case GoalReadable(:final goal)
            when goal.active &&
                (goal.scope is TrackerScope ? trackers : money))
          goal,
    ];
    if (goals.isEmpty) return;
    final service = _ref.read(goalServiceProvider);
    // Issued together. drift runs them on its one connection, so there is
    // no parallelism to cap (spec §3, Concurrency).
    final results =
        await Future.wait([for (final goal in goals) _check(service, goal)]);
    for (final alert in results) {
      // An alert recorded after the shell let go has no one to show it. Its
      // state is already written, and Phase 6 will listen for the life of
      // the app.
      if (alert != null && !_alerts.isClosed) _alerts.add(alert);
    }
  }

  /// One goal's check. A failure is reported and costs that goal only.
  Future<GoalAlert?> _check(GoalService service, Goal goal) async {
    try {
      return await service.check(goal);
    } on Object catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'goal watcher',
        context: ErrorDescription('while checking goal ${goal.id}'),
      ));
      return null;
    }
  }
}

/// The app's one [GoalWatcher]. The shell's `GoalAlertListener` starts it
/// and shows its alerts, and Phase 6 subscribes to the same stream.
///
/// It watches nothing, so it never rebuilds and its [GoalWatcher.alerts]
/// stream is never replaced under a subscriber.
final goalWatcherProvider = Provider<GoalWatcher>((ref) {
  final watcher = GoalWatcher(ref);
  ref.onDispose(() => unawaited(watcher.dispose()));
  return watcher;
});
```

- [ ] **Step 7: Run the tests to confirm GREEN**

```bash
(cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/goal_watcher_test.dart)
```

Expected: PASS, 9 tests.

**Mutation check.**
1. In `GoalWatcher.start`, delete the `goalTodayProvider` listener.
2. Re-run. Expected: "a new day is evaluated without waiting for a write" FAILS, timing out on "the new day's evaluation".
3. Restore it.
4. Then set `debounce` to `Duration.zero` in `goalWatcherProvider`.
5. Re-run. Expected: "a burst of writes inside the debounce is evaluated once" FAILS with `[80, 100]`.
6. Restore it.

- [ ] **Step 8: Run the full gate**

The six commands of the commit routine. Expected:
- `app` is 527 + 9 = **536**;
- the others are unchanged from Task 9's gate.

- [ ] **Step 9: Commit and merge**

```bash
git add app/lib/features/goals/application app/test/features/goals
git commit -F - <<'EOF'
feat(goals): providers and the GoalWatcher that decides an alert is due

The goals get their providers: today, the service, the goal list, and
each goal's live progress and cached history. Progress and history
re-run on the engine's change streams, as analyticsResultProvider and
trackerResultProvider do, and keep their value through a re-run and a
reload, so a card never flashes back to a skeleton.

GoalWatcher evaluates every active goal once at start, which catches
crossings from background capture. After that it evaluates on
transaction and tracker writes, debounced 300 ms, and on a day change.
Each evaluation records through GoalService.check, so a recomputation
cannot re-fire. Its alerts stream is the interface Phase 6 subscribes
to.

The service watches today as well as the engine. A day change then
re-keys every evaluation, so the first crossing on a new day alerts
(Review Focus 3). A calendar switch re-subscribes the watcher without
re-firing anything, because goals keep their own calendar (Review
Focus 2).

stop() exists because the debounce timer lives in a provider. The
shell stops the watcher when it unmounts, so no timer outlives the
widget tree.

Imports Phase 3's analyticsEngineProvider and Phase 4's
trackerClockProvider read-only.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only feat/goal-watcher
```

---

### Task 11: The Goals tab and the shell's fifth destination

Branch `feat/goals-tab`, slug `goals-tab`.

**Files:**
- Create:
  - `app/lib/features/goals/application/goal_kind.dart`
  - `app/lib/features/goals/application/goal_format.dart`
  - `app/lib/features/goals/routes.dart`
  - `app/lib/features/goals/presentation/goals_screen.dart`
  - `app/lib/features/goals/presentation/widgets/goal_card.dart`
  - `app/lib/features/goals/presentation/widgets/goal_write.dart`
- Modify (another owner's files, named in the commit):
  - Phase 1's shell `app/lib/bootstrap/app_shell.dart`;
  - Phase 0's router `app/lib/bootstrap/app_router.dart`;
  - Phase 1's `app/test/bootstrap/app_shell_navigation_test.dart`.
- Modify: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_fa.arb` and the generated `app/lib/l10n/app_localizations*.dart`
- Test: `app/test/features/goals/support/goal_test_app.dart` (extended), `app/test/features/goals/goal_kind_test.dart` (new), `app/test/features/goals/goal_format_test.dart` (new), `app/test/features/goals/goals_screen_test.dart` (new)
- Scratchpad (not the repo): `arb_add.py`, `keys_empty.json`, `keys_goals_tab.json`

**Interfaces:**
- Consumes:
  - `goalsProvider`, `goalProgressProvider` and `goalServiceProvider` (Task 10).
  - Read-only imports:
    - `trackerByIdProvider` and `TrackerFormat`/`trackerFormatProvider` (Phase 4);
    - `moneyFormatterProvider` (settings);
    - `nimbusUndoSnackBar`, `NimbusEmptyState`, `NimbusErrorState` and `NimbusLoadingList` (design).
- Produces:
  - `GoalKind`, with `direction`, `defaultPeriod` and `isHabit`.
  - `kindOf(Goal)` and `habitMetricFor(TrackerType)`.
  - `GoalFormat` with `amount`, `compact`, `percent`, `wholePercent`, `digits` and `runRate`; `goalFormatProvider`; `goalStatusText(l10n, status)`.
  - `goalsRoute`, `newGoalRoute`, `goalDetailRoute(id)`, `editGoalRoute(id)`, `goalShellRoutes` and `goalRoutes` (empty here, filled in by Tasks 12 and 13).
  - `GoalsScreen`.
  - `GoalCard(read:)`, `GoalStatusLine(status:)` (null status means paused) and `GoalProgressBar(goal:, progress:)`.
  - `reportingGoalFailure(...)` and `deleteGoalWithUndo(...)`.
  - Keys:
    - the screen: `goals-loading`, `goals-empty`, `goals-error`, `goals-list`, `goals-new`, `goals-paused-header`;
    - each card: `goal-card-<id>`, `goal-amounts-<id>`, `goal-run-rate-<id>`, `goal-skeleton-<id>`;
    - a problem card: `goal-problem-<id>`, `goal-edit-<id>`, `goal-delete-<id>`.
  - Test support: `pumpGoals(...)` and `insertUnreadableGoal(...)`.
  - The scratchpad helper `arb_add.py`, reused by Tasks 12–15.

- [ ] **Step 1: Write the ARB helper and prove it leaves the files alone**

Write the scratchpad file `arb_add.py` with the Write tool:

```python
"""Adds keys to app_en.arb and app_fa.arb -- or, with --update, changes
existing ones -- without disturbing anything else.

Usage: python arb_add.py <keys.json> [--update]
keys.json: {"en": {"key": "value", "@key": {...}}, "fa": {"key": "value"}}

The ARBs are CRLF, store characters literally, and keep keys sorted
case-insensitively with each "@key" right after its key. This re-sorts with
that rule and writes the same format back, so a run that adds nothing changes
nothing.
"""
import json
import os
import sys

ROOT = r'C:\Users\nimae\Desktop\nimbustats\app\lib\l10n'


def order(key):
    return (key.lstrip('@').lower(), key.startswith('@'))


def plain(keys):
    return {k for k in keys if not k.startswith('@')}


update = '--update' in sys.argv[2:]
new = json.load(open(sys.argv[1], encoding='utf-8'))
assert set(new) == {'en', 'fa'}, 'need exactly "en" and "fa"'
if not update:
    assert plain(new['en']) == plain(new['fa']), 'en and fa must add the same keys'

for lang in ('en', 'fa'):
    path = os.path.join(ROOT, 'app_' + lang + '.arb')
    data = json.loads(open(path, 'rb').read().decode('utf-8'))
    if update:
        missing = set(new[lang]) - set(data)
        assert not missing, 'not present, so not an update: %s' % sorted(missing)
    else:
        clash = set(new[lang]) & set(data)
        assert not clash, 'already present: %s' % sorted(clash)
    data.update(new[lang])
    out = {'@@locale': data.pop('@@locale')}
    for key in sorted(data, key=order):
        out[key] = data[key]
    text = json.dumps(out, ensure_ascii=False, indent=2) + '\n'
    open(path, 'wb').write(text.replace('\n', '\r\n').encode('utf-8'))
    print('wrote %s (%s%d entries)' % (path, '~' if update else '+', len(new[lang])))
```

Prove it is a no-op on today's files:
1. Write the scratchpad file `keys_empty.json` containing `{"en": {}, "fa": {}}`.
2. Run `python <scratchpad>/arb_add.py <scratchpad>/keys_empty.json`, then `git diff --stat app/lib/l10n/`.
3. Expected: **no diff**.
4. A diff means the files are not in the order `order()` assumes. Then stop: fix the helper to match the files' order, never reorder the files.

- [ ] **Step 2: Branch**

```bash
git switch phase/5-goals
git switch -c feat/goals-tab
```

- [ ] **Step 3: Write the failing tests**

Append to `app/test/features/goals/support/goal_test_app.dart`. These are the extra imports, merged into its import block:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbustats/features/goals/routes.dart';

import '../../../support/harness.dart';
import '../../trackers/support/tracker_fixture.dart';
```

and at the end of the file:

```dart
/// Pumps the real app at [location], standing on [fake]'s today.
Future<AppDatabase> pumpGoals(
  WidgetTester tester,
  AppDatabase db,
  FakeClock fake, {
  String location = goalsRoute,
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
  void Function(ProviderContainer container)? onContainer,
}) =>
    pumpApp(tester,
        database: db,
        initialLocation: location,
        locale: locale,
        overrides: [...trackerOverrides(fake), ...overrides],
        onContainer: onContainer);

/// A goals row whose scope is not JSON, which the list must show as
/// unreadable, with a delete, rather than crash on it or default it (spec
/// §1). The column names are spec §1's, created in Task 1: check them with
/// `PRAGMA table_info(goals)` if this insert fails.
Future<void> insertUnreadableGoal(AppDatabase db,
        {String id = 'bad', String name = 'Broken'}) =>
    db.customStatement(
      'INSERT INTO goals (id, created_at, updated_at, name, metric, '
      'scope_json, direction, target_minor, target_quantity, period, '
      'calendar, week_start, start_date, end_date, alert_percents, active) '
      "VALUES (?, 0, 0, ?, 'moneySum', '{not json', 'atMost', 1000, NULL, "
      "'month', 'jalali', 6, 20260101, NULL, '[80,100]', 1)",
      [id, name],
    );
```

Create `app/test/features/goals/goal_kind_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/application/goal_kind.dart';

import 'support/goal_test_app.dart';

void main() {
  const gym = Tracker(
      id: 'gym',
      name: 'Gym',
      iconKey: 'fitness_center',
      color: 0,
      type: TrackerType.boolean,
      archived: false,
      sortOrder: 0);

  test("a goal's kind is read off its metric family and direction", () {
    expect(kindOf(spendingCap()), GoalKind.spendingCap);
    expect(kindOf(habitGoal(gym)), GoalKind.habitLimit);
    expect(kindOf(habitGoal(gym, direction: GoalDirection.atLeast)),
        GoalKind.habitGoal);
    expect(kindOf(savingsTarget()), GoalKind.savingsTarget);
  });

  test('each kind has its direction and default period (spec §5.3)', () {
    expect({
      for (final kind in GoalKind.values)
        kind: (kind.direction, kind.defaultPeriod)
    }, {
      GoalKind.spendingCap: (GoalDirection.atMost, PeriodType.month),
      GoalKind.habitLimit: (GoalDirection.atMost, PeriodType.day),
      GoalKind.habitGoal: (GoalDirection.atLeast, PeriodType.week),
      GoalKind.savingsTarget: (GoalDirection.atLeast, null),
    });
  });

  test("a habit's metric follows its tracker's type, with no picker", () {
    expect({for (final type in TrackerType.values) type: habitMetricFor(type)},
        {
          TrackerType.counter: GoalMetric.trackerCount,
          TrackerType.boolean: GoalMetric.trackerCount,
          TrackerType.quantity: GoalMetric.trackerSum,
          TrackerType.duration: GoalMetric.trackerSum,
        });
  });
}
```

Create `app/test/features/goals/goal_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/application/goal_format.dart';
import 'package:nimbustats/features/trackers/application/tracker_format.dart';

void main() {
  final english = GoalFormat(
    money: const MoneyFormatter(currency: Currency.toman, persianDigits: false),
    trackers: TrackerFormat(
        localeTag: 'en', persianDigits: false, calendar: const GregorianCalendar()),
  );
  final persian = GoalFormat(
    money: const MoneyFormatter(currency: Currency.toman, persianDigits: true),
    trackers: TrackerFormat(
        localeTag: 'fa', persianDigits: true, calendar: const JalaliCalendar()),
  );

  Tracker tracker(TrackerType type, {String? unit}) => Tracker(
      id: type.name,
      name: type.name,
      iconKey: 'star',
      color: 0,
      type: type,
      unit: unit,
      perTapValue: type == TrackerType.quantity ? 0.25 : null,
      archived: false,
      sortOrder: 0);

  test('money reads in full on a detail and short on a card (D1)', () {
    expect(english.amount(const MoneyAmount(Money(850000))), '850,000');
    expect(english.compact(const MoneyAmount(Money(850000))), '850K');
    expect(persian.amount(const MoneyAmount(Money(850000))), '۸۵۰٬۰۰۰');
    expect(persian.compact(const MoneyAmount(Money(1000000))), '۱M');
  });

  test('a tracker number reads as its tracker shows it', () {
    expect(
        english.amount(const QuantityAmount(1.5),
            tracker: tracker(TrackerType.quantity, unit: 'L')),
        '1.5 L');
    expect(
        english.amount(const QuantityAmount(5400),
            tracker: tracker(TrackerType.duration)),
        '1:30');
    expect(
        english.compact(const QuantityAmount(3),
            tracker: tracker(TrackerType.counter)),
        '3');
    expect(english.amount(const QuantityAmount(3)), '3');
  });

  test('a percent is whole, rounded down, in the settings digits', () {
    expect(english.percent(0.825), '82%');
    expect(english.percent(0.7999), '79%', reason: 'never round up to 80');
    expect(english.percent(1.05), '105%');
    expect(english.percent(double.infinity), '100%');
    expect(persian.percent(0.825), '۸۲٪');
    expect(persian.wholePercent(80), '۸۰٪');
  });
}
```

Create `app/test/features/goals/goals_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/application/goal_providers.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';

import '../trackers/support/tracker_fixture.dart';
import 'support/goal_test_app.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late GoalService service;
  late TrackerRepository trackers;

  const day5 = DateKey(20261005);

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    service = goalServiceFor(db, fake.clock.today);
    trackers = repositoryFor(db, fake);
    await seedCategories(db);
  });
  tearDown(() => db.close());

  Finder inCard(String id, Finder matching) =>
      find.descendant(of: find.byKey(Key('goal-card-$id')), matching: matching);

  double barOf(WidgetTester tester, String id) => tester
      .widget<LinearProgressIndicator>(
          inCard(id, find.byType(LinearProgressIndicator)))
      .value!;

  testWidgets('goals show a skeleton while they load', (tester) async {
    final never = StreamController<List<GoalRead>>();
    addTearDown(never.close);

    await pumpGoals(tester, db, fake,
        overrides: [goalsProvider.overrideWith((ref) => never.stream)]);

    expect(find.byKey(const Key('goals-loading')), findsOneWidget);
  });

  testWidgets('with no goals the tab says what a goal is and offers one',
      (tester) async {
    await pumpGoals(tester, db, fake);

    expect(find.byKey(const Key('goals-empty')), findsOneWidget);
    expect(find.text('No goals yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'New goal'), findsOneWidget);
    expect(find.byKey(const Key('goals-new')), findsOneWidget,
        reason: 'and in the app bar, for when goals exist');
  });

  testWidgets('a failed read says so, retries, and hides the raw error',
      (tester) async {
    await pumpGoals(tester, db, fake, overrides: [
      goalsProvider.overrideWith(
          (ref) => Stream<List<GoalRead>>.error(Exception('boom'))),
    ]);

    expect(find.byKey(const Key('goals-error')), findsOneWidget);
    expect(find.text('Could not load your goals'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
  });

  testWidgets("a goal whose numbers fail says so on its own card",
      (tester) async {
    await service.save(spendingCap());

    await pumpGoals(tester, db, fake, overrides: [
      goalProgressProvider(spendingCap()).overrideWith(
          (ref) => Future<GoalProgress>.error(Exception('boom'))),
    ]);

    expect(inCard('cap', find.text('Could not work out this goal')),
        findsOneWidget);
    expect(inCard('cap', find.widgetWithText(TextButton, 'Retry')),
        findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
  });

  testWidgets('a spending cap shows its status in words and an icon, and a bar',
      (tester) async {
    await useEnglishDigits(db);
    await service.save(spendingCap());
    await spend(db, 850000, day5);

    await pumpGoals(tester, db, fake);

    expect(inCard('cap', find.text('Dining out')), findsOneWidget);
    expect(inCard('cap', find.text('At risk')), findsOneWidget);
    expect(inCard('cap', find.byIcon(Icons.warning_amber_rounded)),
        findsOneWidget);
    expect(inCard('cap', find.text('850K of 1M')), findsOneWidget);
    expect(barOf(tester, 'cap'), closeTo(0.85, 1e-9));
  });

  testWidgets('a habit limit fills toward its limit, a habit goal toward its goal',
      (tester) async {
    await useEnglishDigits(db);
    final cig = await trackers.create(cigarettes);
    final g = await trackers.create(gym);
    await service.save(habitGoal(cig, id: 'smoke', target: 10));
    await service.save(habitGoal(g,
        id: 'gym',
        direction: GoalDirection.atLeast,
        target: 4,
        period: PeriodType.week));
    for (var i = 0; i < 3; i++) {
      await trackers.logEntry(cig.id);
    }
    await trackers.logEntry(g.id);

    await pumpGoals(tester, db, fake);

    expect(inCard('smoke', find.text('3 of 10')), findsOneWidget);
    expect(barOf(tester, 'smoke'), closeTo(0.3, 1e-9));
    expect(barOf(tester, 'gym'), closeTo(0.25, 1e-9));
  });

  testWidgets('a savings target says what it needs a month, with no bar',
      (tester) async {
    // 6M by 2027-03-31 with 600K saved: 5.4M over the six months October to
    // March, 900K a month (spec §2, requiredRate).
    await useEnglishDigits(db);
    await service.save(savingsTarget());
    await earn(db, 600000, const DateKey(20261002));

    await pumpGoals(tester, db, fake);

    expect(inCard('savings', find.text('900K/month for 6 more months')),
        findsOneWidget);
    expect(inCard('savings', find.byType(LinearProgressIndicator)),
        findsNothing);
  });

  testWidgets('paused goals sit apart, under Paused', (tester) async {
    final fuel = spendingCap(id: 'fuel', name: 'Fuel', paths: const [transportPath]);
    await service.save(spendingCap());
    await service.save(fuel);
    await service.setActive(fuel, false);

    await pumpGoals(tester, db, fake);

    final header =
        tester.getTopLeft(find.byKey(const Key('goals-paused-header'))).dy;
    expect(tester.getTopLeft(find.byKey(const Key('goal-card-cap'))).dy,
        lessThan(header));
    expect(tester.getTopLeft(find.byKey(const Key('goal-card-fuel'))).dy,
        greaterThan(header));
    expect(inCard('fuel', find.text('Paused')), findsOneWidget);
    expect(inCard('fuel', find.byType(LinearProgressIndicator)), findsNothing);
  });

  testWidgets(
      "an archived tracker's goal reads normally; a deleted one's offers "
      'Edit and Delete', (tester) async {
    // Review Focus 5: archiving is not deletion.
    await useEnglishDigits(db);
    final cig = await trackers.create(cigarettes);
    final w = await trackers.create(water);
    await service.save(habitGoal(cig, id: 'smoke', target: 10));
    await service.save(habitGoal(w,
        id: 'water',
        metric: GoalMetric.trackerSum,
        direction: GoalDirection.atLeast,
        target: 2));
    await trackers.logEntry(cig.id);
    await trackers.archive(cig.id);
    // The app has no tracker delete yet; sync or a restore can produce one.
    await db.customStatement(
        'UPDATE trackers SET deleted_at = 1 WHERE id = ?', [w.id]);

    await pumpGoals(tester, db, fake);

    expect(inCard('smoke', find.text('1 of 10')), findsOneWidget);
    expect(inCard('smoke', find.byType(LinearProgressIndicator)),
        findsOneWidget);
    expect(find.byKey(const Key('goal-problem-water')), findsOneWidget);
    expect(find.text("This goal's tracker was deleted"), findsOneWidget);
    expect(find.byKey(const Key('goal-edit-water')), findsOneWidget);
    expect(find.byKey(const Key('goal-delete-water')), findsOneWidget);
  });

  testWidgets('an unreadable goal can be deleted, and the delete undone',
      (tester) async {
    await insertUnreadableGoal(db);

    await pumpGoals(tester, db, fake);
    expect(find.byKey(const Key('goal-problem-bad')), findsOneWidget);
    expect(find.text('This goal could not be read'), findsOneWidget);
    expect(find.byKey(const Key('goal-edit-bad')), findsNothing,
        reason: 'there is nothing readable to edit');

    await tester.tap(find.byKey(const Key('goal-delete-bad')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-card-bad')), findsNothing);
    expect(find.byKey(const Key('goals-empty')), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-card-bad')), findsOneWidget);
  });

  testWidgets('a card reads as one sentence: name, progress, status',
      (tester) async {
    final handle = tester.ensureSemantics();
    await useEnglishDigits(db);
    await service.save(spendingCap());
    await spend(db, 850000, day5);

    await pumpGoals(tester, db, fake);

    expect(find.bySemanticsLabel('Dining out, 850K of 1M, At risk'),
        findsOneWidget);
    handle.dispose();
  });

  testWidgets('Persian: right to left, Persian digits and words',
      (tester) async {
    // No useEnglishDigits: the default settings write Persian digits.
    await service.save(spendingCap());
    await spend(db, 850000, day5);

    await pumpGoals(tester, db, fake, locale: const Locale('fa'));

    expect(Directionality.of(tester.element(find.byKey(const Key('goal-card-cap')))),
        TextDirection.rtl);
    expect(inCard('cap', find.text('۸۵۰K از ۱M')), findsOneWidget);
    expect(inCard('cap', find.text('در خطر')), findsOneWidget);
  });

  testWidgets('at twice the font size the tab overflows nothing',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await service.save(
        spendingCap(name: 'A forty character name, for case D2 ok'));
    await service.save(savingsTarget());
    await spend(db, 850000, day5);

    await pumpGoals(tester, db, fake, locale: const Locale('fa'));

    expect(tester.takeException(), isNull);
  });
}
```

In Phase 1's `app/test/bootstrap/app_shell_navigation_test.dart`:
1. Rename the first test to `'the shell offers home, trackers, goals, analytics and settings'`, and add `expect(navItem('Goals'), findsOneWidget);` after the Trackers expectation.
2. In `'the destination the user is on is the selected one'`, insert after the Trackers step:

```dart
    await tester.tap(navItem('Goals'));
    await tester.pumpAndSettle();
    expect(bar().selectedIndex, 2);
```

   and change the Analytics expectation to `3` and the Settings one to `4`.
3. Append inside `main`:

```dart
  testWidgets('tapping goals shows the goals tab', (tester) async {
    await pumpApp(tester);

    await tester.tap(navItem('Goals'));
    await tester.pumpAndSettle();

    // An empty database: the tab says what a goal is.
    expect(find.byKey(const Key('goals-empty')), findsOneWidget);
  });
```

- [ ] **Step 4: Run the tests to confirm RED**

```bash
(cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/goal_kind_test.dart C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/goal_format_test.dart C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/goals_screen_test.dart C:/Users/nimae/Desktop/nimbustats/app/test/bootstrap/app_shell_navigation_test.dart)
```

Expected:
- FAIL to compile, naming `goal_kind.dart`, `goal_format.dart` and `routes.dart` under `features/goals` (files not found), and so `GoalKind`, `GoalFormat` and `goalsRoute`.
- The navigation test compiles, because it imports nothing from goals, and FAILS: `navItem('Goals')` finds nothing.

- [ ] **Step 5: Tag the parent**

```bash
git tag pre-goals-tab
```

- [ ] **Step 6: Add the strings**

Write the scratchpad file `keys_goals_tab.json`:

```json
{
  "en": {
    "navGoals": "Goals",
    "goalsCardErrorTitle": "Could not work out this goal",
    "goalsCardPausedSemantics": "{name}, paused",
    "@goalsCardPausedSemantics": {"placeholders": {"name": {"type": "String"}}},
    "goalsCardSemantics": "{name}, {progress}, {status}",
    "@goalsCardSemantics": {"placeholders": {"name": {"type": "String"}, "progress": {"type": "String"}, "status": {"type": "String"}}},
    "goalsDeleted": "Goal deleted",
    "goalsEdit": "Edit",
    "goalsEmptyBody": "A goal watches one number for you: a monthly spending cap, a daily habit limit, a weekly habit goal or a savings target. It warns you while there is still time to act.",
    "goalsEmptyTitle": "No goals yet",
    "goalsErrorTitle": "Could not load your goals",
    "goalsNew": "New goal",
    "goalsPausedSection": "Paused",
    "goalsProgressOf": "{current} of {target}",
    "@goalsProgressOf": {"placeholders": {"current": {"type": "String"}, "target": {"type": "String"}}},
    "goalsSavingsRunRate": "{count, plural, =1{{perMonth}/month for {months} more month} other{{perMonth}/month for {months} more months}}",
    "@goalsSavingsRunRate": {"placeholders": {"count": {"type": "int"}, "perMonth": {"type": "String"}, "months": {"type": "String"}}},
    "goalsScreenTitle": "Goals",
    "goalsStatusAtRisk": "At risk",
    "goalsStatusExceeded": "Over the limit",
    "goalsStatusMet": "Met",
    "goalsStatusMissed": "Missed",
    "goalsStatusNotStarted": "Not started",
    "goalsStatusOnTrack": "On track",
    "goalsStatusPaused": "Paused",
    "goalsTrackerMissingTitle": "This goal's tracker was deleted",
    "goalsUnreadableTitle": "This goal could not be read",
    "goalsWriteFailed": "Could not save the goal"
  },
  "fa": {
    "navGoals": "اهداف",
    "goalsCardErrorTitle": "وضعیت این هدف محاسبه نشد",
    "goalsCardPausedSemantics": "{name}، متوقف",
    "goalsCardSemantics": "{name}، {progress}، {status}",
    "goalsDeleted": "هدف حذف شد",
    "goalsEdit": "ویرایش",
    "goalsEmptyBody": "هدف یک عدد را برایتان زیر نظر می‌گیرد: سقف خرج ماهانه، حد روزانهٔ یک عادت، هدف هفتگی یک عادت یا هدف پس‌انداز. و تا وقتی هنوز فرصت هست، خبرتان می‌کند.",
    "goalsEmptyTitle": "هنوز هدفی ندارید",
    "goalsErrorTitle": "اهداف بارگیری نشد",
    "goalsNew": "هدف تازه",
    "goalsPausedSection": "متوقف‌شده‌ها",
    "goalsProgressOf": "{current} از {target}",
    "goalsSavingsRunRate": "{count, plural, other{ماهی {perMonth} برای {months} ماه دیگر}}",
    "goalsScreenTitle": "اهداف",
    "goalsStatusAtRisk": "در خطر",
    "goalsStatusExceeded": "از حد گذشته",
    "goalsStatusMet": "محقق شد",
    "goalsStatusMissed": "نرسید",
    "goalsStatusNotStarted": "شروع نشده",
    "goalsStatusOnTrack": "در مسیر",
    "goalsStatusPaused": "متوقف",
    "goalsTrackerMissingTitle": "عادتِ این هدف حذف شده است",
    "goalsUnreadableTitle": "این هدف خوانده نشد",
    "goalsWriteFailed": "هدف ذخیره نشد"
  }
}
```

`count` only selects the plural branch and is never printed. The month count arrives formatted as `months`.

Run:

```bash
python <scratchpad>/arb_add.py <scratchpad>/keys_goals_tab.json
(cd app && flutter gen-l10n)
```

Expected:
- `wrote … (+28 entries)` for en (24 keys and 4 `@` entries) and `(+24 entries)` for fa;
- `gen-l10n` reports no errors;
- `AppLocalizations` gains `goalsSavingsRunRate(int count, String perMonth, String months)` and `goalsCardSemantics(String name, String progress, String status)`.

- [ ] **Step 7: Write the kind and the format**

Create `app/lib/features/goals/application/goal_kind.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';

/// The four goals the editor offers.
///
/// They are never stored. Storage and evaluation know only a metric, a
/// direction and a period, so neither `nimbus_domain` nor `nimbus_data` can
/// branch on a kind (the brief's grep criterion, Task 6's test). The kind
/// lives here, where the editor chooses defaults by it and the card chooses
/// a bar or a run-rate.
enum GoalKind {
  spendingCap,
  habitLimit,
  habitGoal,
  savingsTarget;

  /// A cap and a limit are at most; a habit goal and savings, at least.
  GoalDirection get direction => switch (this) {
        GoalKind.spendingCap || GoalKind.habitLimit => GoalDirection.atMost,
        GoalKind.habitGoal || GoalKind.savingsTarget => GoalDirection.atLeast,
      };

  /// The period a new goal of this kind starts with, or null for a fixed
  /// date range (spec §5.3).
  PeriodType? get defaultPeriod => switch (this) {
        GoalKind.spendingCap => PeriodType.month,
        GoalKind.habitLimit => PeriodType.day,
        GoalKind.habitGoal => PeriodType.week,
        GoalKind.savingsTarget => null,
      };

  bool get isHabit => this == GoalKind.habitLimit || this == GoalKind.habitGoal;
}

/// [goal]'s kind, read off its metric family and direction. A `txnCount`
/// goal, which the editor does not offer (spec, Out of scope), reads as a
/// spending cap.
GoalKind kindOf(Goal goal) => switch (goal.metric) {
      GoalMetric.netSavings => GoalKind.savingsTarget,
      GoalMetric.trackerSum || GoalMetric.trackerCount =>
        goal.direction == GoalDirection.atMost
            ? GoalKind.habitLimit
            : GoalKind.habitGoal,
      GoalMetric.moneySum || GoalMetric.txnCount => GoalKind.spendingCap,
    };

/// A habit's metric, which its tracker's type decides, so the editor has no
/// metric picker (spec §5.3).
///
/// - Counters and booleans count entries: one tap, one cigarette; one
///   "done", one day.
/// - Quantities and durations sum them: litres, seconds.
GoalMetric habitMetricFor(TrackerType type) => switch (type) {
      TrackerType.counter || TrackerType.boolean => GoalMetric.trackerCount,
      TrackerType.quantity || TrackerType.duration => GoalMetric.trackerSum,
    };
```

Create `app/lib/features/goals/application/goal_format.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/application/settings_providers.dart';
import '../../trackers/application/tracker_format.dart';

/// How goal numbers read.
///
/// Money goes through [MoneyFormatter], and tracker values through the
/// trackers' own [TrackerFormat] (read-only), so a habit goal writes its
/// litres and minutes exactly as the tracker does. Digits follow the
/// settings locale (screen contract §8). Every string that shows a goal
/// number gets it from here, so the ARB strings never format a number
/// themselves.
final class GoalFormat {
  const GoalFormat({
    required MoneyFormatter money,
    required TrackerFormat trackers,
  })  : _money = money,
        _trackers = trackers;

  final MoneyFormatter _money;
  final TrackerFormat _trackers;

  bool get persianDigits => _money.persianDigits;

  /// In full, for the detail screen, the editor and the preview.
  String amount(GoalAmount value, {Tracker? tracker}) => switch (value) {
        MoneyAmount(:final money) => _money.format(money),
        QuantityAmount(value: final quantity) => _quantity(quantity, tracker),
      };

  /// Short, for the Goals tab's cards and the run-rate line (screen
  /// contract D1). Tracker values have no short form.
  String compact(GoalAmount value, {Tracker? tracker}) => switch (value) {
        MoneyAmount(:final money) => _money.formatCompact(money),
        QuantityAmount(value: final quantity) => _quantity(quantity, tracker),
      };

  /// [fraction] as a whole percent, rounded down so 79.99% never reads as
  /// 80%. The epsilon absorbs float noise such as `0.29 * 100 =
  /// 28.999999999999996`. A reached zero target is infinite and reads as
  /// 100%.
  String percent(double fraction) => wholePercent(
      fraction.isFinite ? (fraction * 100 + 1e-9).floor() : 100);

  /// A whole percent in the settings' digits: `80%`, `۸۰٪`.
  String wholePercent(int value) =>
      persianDigits ? '${Digits.toPersian('$value')}٪' : '$value%';

  /// A whole number in the settings' digits, without grouping.
  String digits(int value) => _trackers.digits(value);

  /// A savings target's "900K/month for 6 more months", or null when there
  /// is no run-rate to state. That is the case when the range is not open, or
  /// nothing more is needed.
  String? runRate(AppLocalizations l10n, GoalProgress progress) {
    final rate = progress.projection.requiredRate;
    if (rate == null || rate.perMonth.isZero) return null;
    return l10n.goalsSavingsRunRate(
        rate.monthsLeft, compact(rate.perMonth), digits(rate.monthsLeft));
  }

  String _quantity(double value, Tracker? tracker) =>
      tracker == null ? _trackers.number(value) : _trackers.total(tracker, value);
}

final goalFormatProvider = Provider<GoalFormat>((ref) => GoalFormat(
      money: ref.watch(moneyFormatterProvider),
      trackers: ref.watch(trackerFormatProvider),
    ));

/// A status in words. Every status is shown with its icon too, never by
/// colour alone.
String goalStatusText(AppLocalizations l10n, GoalStatus status) =>
    switch (status) {
      GoalStatus.notStarted => l10n.goalsStatusNotStarted,
      GoalStatus.onTrack => l10n.goalsStatusOnTrack,
      GoalStatus.atRisk => l10n.goalsStatusAtRisk,
      GoalStatus.exceeded => l10n.goalsStatusExceeded,
      GoalStatus.met => l10n.goalsStatusMet,
      GoalStatus.missed => l10n.goalsStatusMissed,
    };
```

- [ ] **Step 8: Write the routes, the screen and the card**

Create `app/lib/features/goals/routes.dart`:

```dart
import 'package:go_router/go_router.dart';

import 'presentation/goals_screen.dart';

const goalsRoute = '/goals';

/// Declared before the detail's `:id` route, which would otherwise match it.
const newGoalRoute = '/goals/new';

/// Where a card opens: [id]'s detail screen, pushed over the shell.
String goalDetailRoute(String id) => '$goalsRoute/$id';

String editGoalRoute(String id) => '$goalsRoute/$id/edit';

/// A nav-shell destination, so it keeps the bottom bar.
final goalShellRoutes = <RouteBase>[
  GoRoute(
    path: goalsRoute,
    name: 'goals',
    builder: (context, state) => const GoalsScreen(),
  ),
];

/// This feature's full-screen routes, composed by `app_router.dart`. The
/// editor and the detail screen own the whole screen. A nav bar under a
/// half-written goal would be an exit that silently discards it. Tasks 12
/// and 13 add them.
final goalRoutes = <RouteBase>[];
```

Create `app/lib/features/goals/presentation/widgets/goal_write.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';

/// Runs a goal write. If it fails, it says so and rethrows.
///
/// This is the rule the saved-view and tracker writes follow. A failed local
/// write is rare, but when it happens the user hears about it instead of
/// watching a tap do nothing, and the error still reaches the framework's
/// error handler. It takes its dependencies rather than a context, so it can
/// finish after the widget that started it is gone.
Future<void> reportingGoalFailure({
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required Future<void> Function() write,
}) async {
  try {
    await write();
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(l10n.goalsWriteFailed)));
    rethrow;
  }
}

/// Deletes the goal [id], then offers to undo it (screen contract §1.3:
/// undo, never confirm). The undo restores and re-baselines, so the goal
/// does not alert about a crossing made while it was gone.
Future<void> deleteGoalWithUndo({
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required GoalService service,
  required String id,
}) async {
  await reportingGoalFailure(
      messenger: messenger, l10n: l10n, write: () => service.delete(id));
  messenger.showSnackBar(nimbusUndoSnackBar(
    message: l10n.goalsDeleted,
    undoLabel: l10n.commonUndo,
    onUndo: () => unawaited(reportingGoalFailure(
        messenger: messenger, l10n: l10n, write: () => service.restore(id))),
  ));
}
```

Create `app/lib/features/goals/presentation/widgets/goal_card.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../trackers/application/tracker_providers.dart';
import '../../application/goal_format.dart';
import '../../application/goal_kind.dart';
import '../../application/goal_providers.dart';
import '../../routes.dart';
import 'goal_write.dart';

/// One goal on the Goals tab (spec §5.1).
///
/// It shows the name, the status as a word and an icon, and `current of
/// target` in the settings' digits. Caps and habits fill a bar toward their
/// target; a savings target states its run-rate instead. Two cards offer
/// actions in place of numbers:
/// - a goal whose tracker was deleted: Edit and Delete;
/// - a row that does not parse: Delete.
class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.read});

  final GoalRead read;

  @override
  Widget build(BuildContext context) => switch (read) {
        GoalUnreadable(:final id, :final name) => _ProblemCard(
            id: id,
            name: name,
            message: AppLocalizations.of(context).goalsUnreadableTitle,
            canEdit: false,
          ),
        GoalReadable(:final goal) => switch (goal.scope) {
            TrackerScope(:final trackerId) =>
              _TrackerGoalCard(goal: goal, trackerId: trackerId),
            MoneyScope() => _GoalBody(goal: goal),
          },
      };
}

/// A tracker goal's card. An archived tracker is still measured and shown
/// (archiving is not deletion). A deleted one turns the card into an error
/// with Edit and Delete, never a crash or a silent zero (Review Focus 5).
class _TrackerGoalCard extends ConsumerWidget {
  const _TrackerGoalCard({required this.goal, required this.trackerId});

  final Goal goal;
  final String trackerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracker = ref.watch(trackerByIdProvider(trackerId));
    if (tracker.hasError) {
      return _CardError(
          goal: goal,
          onRetry: () => ref.invalidate(trackerByIdProvider(trackerId)));
    }
    if (!tracker.hasValue) return _CardSkeleton(goal: goal);
    final found = tracker.requireValue;
    if (found == null) {
      return _ProblemCard(
        id: goal.id,
        name: goal.name,
        message: AppLocalizations.of(context).goalsTrackerMissingTitle,
        canEdit: true,
      );
    }
    return _GoalBody(goal: goal, tracker: found);
  }
}

class _GoalBody extends ConsumerWidget {
  const _GoalBody({required this.goal, this.tracker});

  final Goal goal;

  /// A habit's tracker, which decides how its numbers read.
  final Tracker? tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (!goal.active) {
      // Paused goals are not evaluated (spec §1).
      return _CardFrame(
        goal: goal,
        label: l10n.goalsCardPausedSemantics(goal.name),
        children: const [GoalStatusLine(status: null)],
      );
    }
    final progress = ref.watch(goalProgressProvider(goal));
    if (progress.hasError) {
      return _CardError(
          goal: goal, onRetry: () => ref.invalidate(goalProgressProvider(goal)));
    }
    if (!progress.hasValue) return _CardSkeleton(goal: goal);

    final value = progress.requireValue;
    final format = ref.watch(goalFormatProvider);
    final amounts = l10n.goalsProgressOf(
      format.compact(value.current, tracker: tracker),
      format.compact(value.target, tracker: tracker),
    );
    // Savings report a required run-rate, which a bar cannot show (screen
    // contract §7.1).
    final savings = kindOf(goal) == GoalKind.savingsTarget;
    final runRate = savings ? format.runRate(l10n, value) : null;
    return _CardFrame(
      goal: goal,
      label: l10n.goalsCardSemantics(
          goal.name, amounts, goalStatusText(l10n, value.status)),
      children: [
        GoalStatusLine(status: value.status),
        const SizedBox(height: NimbusTokens.space1),
        Text(amounts, key: Key('goal-amounts-${goal.id}')),
        if (!savings) ...[
          const SizedBox(height: NimbusTokens.space2),
          GoalProgressBar(goal: goal, progress: value),
        ],
        if (runRate != null)
          Text(runRate, key: Key('goal-run-rate-${goal.id}')),
      ],
    );
  }
}

/// The tappable card. A screen reader hears it as one sentence ([label]),
/// with one tap action, rather than as five loose fragments.
class _CardFrame extends StatelessWidget {
  const _CardFrame(
      {required this.goal, required this.label, required this.children});

  final Goal goal;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void open() => context.push(goalDetailRoute(goal.id));
    return Card(
      key: Key('goal-card-${goal.id}'),
      margin: const EdgeInsets.only(bottom: NimbusTokens.space2),
      child: Semantics(
        container: true,
        button: true,
        label: label,
        onTap: open,
        excludeSemantics: true,
        child: InkWell(
          onTap: open,
          borderRadius: NimbusTokens.borderRadiusMd,
          child: Padding(
            padding: const EdgeInsets.all(NimbusTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // D2: one line, ellipsised; the detail screen has it whole.
                Text(goal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: NimbusTokens.space2),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// While a card's numbers load: its name, and a static bar where the
/// numbers will be. Never a spinner (screen contract §1.1).
class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) => _CardFrame(
        goal: goal,
        label: goal.name,
        children: [
          Container(
            key: Key('goal-skeleton-${goal.id}'),
            height: NimbusTokens.space4,
            decoration: BoxDecoration(
              color: NimbusSemanticColors.of(context).skeleton,
              borderRadius: NimbusTokens.borderRadiusSm,
            ),
          ),
        ],
      );
}

/// One goal's numbers failed. It says so, with a retry, on that card only,
/// so one failure does not cost the tab.
class _CardError extends StatelessWidget {
  const _CardError({required this.goal, required this.onRetry});

  final Goal goal;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Plain(
      id: goal.id,
      name: goal.name,
      icon: Icons.error_outline,
      message: l10n.goalsCardErrorTitle,
      actions: [TextButton(onPressed: onRetry, child: Text(l10n.commonRetry))],
    );
  }
}

/// A goal that cannot be shown: its tracker was deleted, or its row does not
/// parse. Edit only when there is a goal to edit.
class _ProblemCard extends ConsumerWidget {
  const _ProblemCard({
    required this.id,
    required this.name,
    required this.message,
    required this.canEdit,
  });

  final String id;
  final String name;
  final String message;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return _Plain(
      id: id,
      name: name,
      icon: Icons.error_outline,
      message: message,
      messageKey: Key('goal-problem-$id'),
      actions: [
        if (canEdit)
          TextButton(
            key: Key('goal-edit-$id'),
            onPressed: () => context.push(editGoalRoute(id)),
            child: Text(l10n.goalsEdit),
          ),
        TextButton(
          key: Key('goal-delete-$id'),
          onPressed: () => unawaited(deleteGoalWithUndo(
            messenger: ScaffoldMessenger.of(context),
            l10n: l10n,
            service: ref.read(goalServiceProvider),
            id: id,
          )),
          child: Text(l10n.commonDelete),
        ),
      ],
    );
  }
}

/// A card that is not a tap target: a message and its own buttons, each
/// reachable by a screen reader.
class _Plain extends StatelessWidget {
  const _Plain({
    required this.id,
    required this.name,
    required this.icon,
    required this.message,
    required this.actions,
    this.messageKey,
  });

  final String id;
  final String name;
  final IconData icon;
  final String message;
  final List<Widget> actions;
  final Key? messageKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('goal-card-$id'),
      margin: const EdgeInsets.only(bottom: NimbusTokens.space2),
      child: Padding(
        padding: const EdgeInsets.all(NimbusTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: NimbusTokens.space2),
            Row(
              children: [
                ExcludeSemantics(
                    child: Icon(icon, color: theme.colorScheme.error)),
                const SizedBox(width: NimbusTokens.space2),
                Expanded(child: Text(message, key: messageKey)),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(spacing: NimbusTokens.space2, children: actions),
            ),
          ],
        ),
      ),
    );
  }
}

/// A status as an icon and a word, never colour alone. A null [status] is
/// a paused goal.
class GoalStatusLine extends StatelessWidget {
  const GoalStatusLine({super.key, required this.status});

  final GoalStatus? status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = this.status;
    final color = _statusColor(theme.colorScheme, status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(
            switch (status) {
              null => Icons.pause_circle_outline,
              GoalStatus.notStarted => Icons.schedule,
              GoalStatus.onTrack => Icons.check_circle_outline,
              GoalStatus.atRisk => Icons.warning_amber_rounded,
              GoalStatus.exceeded => Icons.error_outline,
              GoalStatus.met => Icons.emoji_events_outlined,
              GoalStatus.missed => Icons.highlight_off,
            },
            size: 18,
            color: color,
          ),
        ),
        const SizedBox(width: NimbusTokens.space1),
        // Flexible: a status wraps, at twice the font size, rather than
        // pushing past the card's edge.
        Flexible(
          child: Text(
            status == null
                ? l10n.goalsStatusPaused
                : goalStatusText(l10n, status),
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Fills toward the target from the reading side: from the right in
/// Persian. The bar names its goal and speaks its percent in the settings'
/// digits; the default would speak Latin digits in Persian.
class GoalProgressBar extends ConsumerWidget {
  const GoalProgressBar({super.key, required this.goal, required this.progress});

  final Goal goal;
  final GoalProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fraction = progress.fractionOfTarget;
    return LinearProgressIndicator(
      // Infinite for anything on a zero limit, which is simply full.
      value: fraction.isFinite ? fraction.clamp(0.0, 1.0).toDouble() : 1.0,
      minHeight: NimbusTokens.space2,
      borderRadius: NimbusTokens.borderRadiusSm,
      color: _statusColor(Theme.of(context).colorScheme, progress.status),
      semanticsLabel: goal.name,
      semanticsValue: ref.watch(goalFormatProvider).percent(fraction),
    );
  }
}

/// From the theme, never a raw colour. The word and the icon carry the
/// meaning; the colour only echoes it.
Color _statusColor(ColorScheme scheme, GoalStatus? status) => switch (status) {
      null || GoalStatus.notStarted => scheme.outline,
      GoalStatus.onTrack || GoalStatus.met => scheme.primary,
      GoalStatus.atRisk => scheme.tertiary,
      GoalStatus.exceeded || GoalStatus.missed => scheme.error,
    };
```

Create `app/lib/features/goals/presentation/goals_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../application/goal_providers.dart';
import '../routes.dart';
import 'widgets/goal_card.dart';

/// The Goals tab: every goal and where it stands this period (screen
/// contract §7.1). Paused goals sit apart, under their own header.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final goals = ref.watch(goalsProvider);

    // hasError and hasValue rather than a switch on the subtype: a refresh
    // carries the previous list, and blanking to a skeleton between two
    // emissions reads as a flicker.
    final Widget body;
    if (goals.hasError) {
      body = NimbusErrorState(
        key: const Key('goals-error'),
        title: l10n.goalsErrorTitle,
        retryLabel: l10n.commonRetry,
        detail: goals.error.toString(),
        onRetry: () => ref.invalidate(goalsProvider),
      );
    } else if (!goals.hasValue) {
      body = const NimbusLoadingList(key: Key('goals-loading'), rows: 4);
    } else if (goals.requireValue.isEmpty) {
      body = NimbusEmptyState(
        key: const Key('goals-empty'),
        icon: Icons.flag_outlined,
        title: l10n.goalsEmptyTitle,
        message: l10n.goalsEmptyBody,
        actionLabel: l10n.goalsNew,
        onAction: () => context.push(newGoalRoute),
      );
    } else {
      bool paused(GoalRead read) => read is GoalReadable && !read.goal.active;
      final all = goals.requireValue;
      final resting = [for (final read in all) if (paused(read)) read];
      body = ListView(
        key: const Key('goals-list'),
        padding: const EdgeInsets.all(NimbusTokens.space4),
        children: [
          for (final read in all)
            if (!paused(read)) GoalCard(key: ValueKey(read.id), read: read),
          if (resting.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: NimbusTokens.space2),
              child: Text(
                l10n.goalsPausedSection,
                key: const Key('goals-paused-header'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final read in resting)
              GoalCard(key: ValueKey(read.id), read: read),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.goalsScreenTitle),
        actions: [
          IconButton(
            key: const Key('goals-new'),
            tooltip: l10n.goalsNew,
            icon: const Icon(Icons.add),
            onPressed: () => context.push(newGoalRoute),
          ),
        ],
      ),
      body: body,
    );
  }
}
```

- [ ] **Step 9: Add the destination**

In Phase 1's `app/lib/bootstrap/app_shell.dart`:
1. Add `import '../features/goals/routes.dart';` between the analytics and settings imports.
2. In the class doc, change "Only these four live inside the shell." to "Only these five live inside the shell."
3. Make `destinations`:

```dart
  static const destinations = <String>[
    transactionListRoute,
    trackersRoute,
    goalsRoute,
    analyticsRoute,
    settingsRoute,
  ];
```

   `indexOf` is unchanged. It matches by prefix from the end, and `/goals` neither prefixes another destination nor is prefixed by one. The goals' pushed routes (`/goals/new`, `/goals/<id>`) are outside the shell.
4. Insert the destination between Trackers and Analytics:

```dart
          NavigationDestination(
            icon: const Icon(Icons.flag_outlined),
            selectedIcon: const Icon(Icons.flag),
            label: l10n.navGoals,
          ),
```

In Phase 0's `app/lib/bootstrap/app_router.dart`:
1. Add `import '../features/goals/routes.dart';` between the categories and onboarding imports.
2. In the `ShellRoute`'s routes, add `...goalShellRoutes,` after `...trackerShellRoutes,`.
3. In the full-screen list, add `...goalRoutes,` after `...trackerRoutes,`.

- [ ] **Step 10: Run the tests to confirm GREEN**

```bash
(cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/ C:/Users/nimae/Desktop/nimbustats/app/test/bootstrap/ C:/Users/nimae/Desktop/nimbustats/app/test/localization_test.dart C:/Users/nimae/Desktop/nimbustats/app/test/ux_rules_test.dart)
```

Expected: PASS.

If an existing dynamic-type test elsewhere now overflows in the nav bar (five labels at twice the font size, at 160 points each on the 800-point test screen), stop and report it. Do not shrink the labels to make it pass.

**Mutation check.**
1. In `_TrackerGoalCard`, treat an archived tracker as missing: `if (found == null || found.archived)`.
2. Re-run. Expected: the Review Focus 5 test FAILS, with no `1 of 10` on the `smoke` card.
3. Restore it.

- [ ] **Step 11: Run the full gate**

Expected:
- `app` is 536 + 20 = **556**:
  - goals_screen 13;
  - goal_kind 3;
  - goal_format 3;
  - navigation +1.
- The others are unchanged.

- [ ] **Step 12: Commit and merge**

```bash
git add app/lib/features/goals app/lib/bootstrap app/lib/l10n app/test/features/goals app/test/bootstrap/app_shell_navigation_test.dart
git commit -F - <<'EOF'
feat(goals): the Goals tab, a fifth destination between Trackers and Analytics

Every goal is a card: its name, its status as a word and an icon,
never colour alone, and current of target in the settings' digits.
Caps and habits fill a bar toward their target. A savings target
states its run-rate instead ("900K/month for 6 more months"), because
a range has no period progress to draw. Paused goals sit under their
own header. The tab has all four states.

A goal over an archived tracker reads normally, since archiving is
not deletion. A goal whose tracker was deleted shows an error card
with Edit and Delete, never a crash or a silent zero (Review Focus 5).
An unreadable row shows a card with Delete and an undo.

Kinds live in the app (goal_kind.dart). The defaults and the bar/run-
rate choice key on them; storage and evaluation never see one.

Touches Phase 1's app_shell.dart and its navigation test (the fifth
destination moves Analytics to 3 and Settings to 4), Phase 0's
app_router.dart (two lines), and the shared ARBs. Imports the
trackers' trackerByIdProvider and TrackerFormat read-only.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only feat/goals-tab
```

---

### Task 12: The goal editor

Branch `feat/goal-editor`, slug `goal-editor`.

**Files:**
- Create:
  - `app/lib/features/goals/application/goal_editor_controller.dart`
  - `app/lib/features/goals/presentation/goal_editor_screen.dart`
  - `app/lib/features/goals/presentation/widgets/goal_kind_tiles.dart`
  - `app/lib/features/goals/presentation/widgets/goal_preview.dart`
- Modify: `app/lib/features/goals/application/goal_providers.dart` (`goalPreviewProvider`), `app/lib/features/goals/application/goal_format.dart` (`date`, `period`), `app/lib/features/goals/routes.dart`
- Modify: the ARBs and the generated localizations
- Test: `app/test/features/goals/goal_editor_screen_test.dart` (new), `app/test/features/goals/goal_format_test.dart`
- Scratchpad: `keys_goal_editor.json`

**Interfaces:**
- Consumes:
  - `goalServiceProvider`, `goalsProvider` and `goalTodayProvider` (Task 10).
  - `GoalKind`, `kindOf`, `habitMetricFor`, `GoalFormat`, `GoalStatusLine` and `reportingGoalFailure` (Task 11).
  - Read-only imports:
    - `AmountField` (transactions);
    - `showTagPickerSheet` and `TagChipRow` (tags);
    - `categoryNodesByIdProvider`, `categoryTreeProvider` and `CategoryTree` (categories);
    - `tagNodesByIdProvider` (tags);
    - `trackersProvider` and `trackerByIdProvider` (trackers);
    - `calendarProvider`, `firstDayOfWeekProvider` and `moneyFormatterProvider` (settings);
    - `Ids.newId()` (`nimbus_data`).
- Produces:
  - `goalPreviewProvider`.
  - `GoalFormat.date(CalendarKind, DateKey)` and `GoalFormat.period(Goal, DateRange)`.
  - `GoalEditorSeed`, `GoalEditorState`, `GoalEditorError`, `goalEditorErrors(state, money)`, `goalDraft(state, money)`, `GoalEditorController` and `goalEditorProvider`.
  - `GoalEditorScreen({id})`, `GoalKindTiles`, `GoalPreviewPanel` and `GoalOutcomeRow`.
  - The routes `goal-new` and `goal-edit`.
  - Keys:
    - the kind tiles: `goal-kind-<kind>`;
    - the form: `goal-editor`, `goal-name`, `goal-category`, `goal-category-all`, `goal-category-<id>`, `goal-tags`, `goal-tracker`, `goal-tracker-option-<id>`, `goal-target`, `goal-period-<type>`, `goal-calendar`, `goal-start`, `goal-end`, `goal-alert-<percent>`, `goal-save`. `AmountField` keeps its own `tx-amount-field`.
    - the preview: `goal-preview-loading`, `goal-preview-error`, `goal-preview-<periodStart>`, `goal-preview-current`.

Decision, the tracker picker:
- It offers **unarchived** trackers only (`trackersProvider`). An archived tracker is one the user has stopped logging, so a new goal over it would never move.
- An existing goal over an archived tracker keeps it, shown by name, until the user picks another. Archiving is not deletion (Review Focus 5).

- [ ] **Step 1: Branch**

```bash
git switch phase/5-goals
git switch -c feat/goal-editor
```

- [ ] **Step 2: Write the failing tests**

Append to `app/test/features/goals/goal_format_test.dart`. Add `import 'support/goal_test_app.dart';` to its imports, and inside `main`:

```dart
  test("a period is named in the goal's own calendar", () {
    const day5 = DateKey(20261005);
    final mehr =
        const JalaliCalendar().periodContaining(day5, PeriodType.month);
    expect(english.period(spendingCap(), mehr), '1405/07');
    expect(
        english.period(spendingCap(calendar: CalendarKind.gregorian),
            const DateRange(DateKey(20261001), DateKey(20261031))),
        '2026/10');
    expect(persian.period(spendingCap(), mehr), '۱۴۰۵/۰۷');
    expect(english.date(CalendarKind.jalali, day5), '1405/07/13');
  });

  test('a day reads as its date; a week and a range as their two ends', () {
    Goal gregorian(PeriodType type) =>
        spendingCap(period: type, calendar: CalendarKind.gregorian);
    expect(
        english.period(gregorian(PeriodType.day),
            const DateRange(DateKey(20261005), DateKey(20261005))),
        '2026/10/05');
    expect(
        english.period(gregorian(PeriodType.week),
            const DateRange(DateKey(20261003), DateKey(20261009))),
        '2026/10/03 – 2026/10/09');
    expect(
        english.period(gregorian(PeriodType.year),
            const DateRange(DateKey(20260101), DateKey(20261231))),
        '2026');
    expect(
        english.period(savingsTarget(),
            const DateRange(DateKey(20261001), DateKey(20270331))),
        '2026/10/01 – 2027/03/31');
  });
```

Create `app/test/features/goals/goal_editor_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/application/goal_editor_controller.dart';
import 'package:nimbustats/features/goals/application/goal_kind.dart';
import 'package:nimbustats/features/goals/routes.dart';
import 'package:nimbustats/features/tags/data/tag_repository.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';

import '../trackers/support/tracker_fixture.dart';
import 'support/goal_test_app.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late GoalService service;
  late TrackerRepository trackers;

  const day5 = DateKey(20261005);

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    service = goalServiceFor(db, fake.clock.today);
    trackers = repositoryFor(db, fake);
    await seedCategories(db);
  });
  tearDown(() => db.close());

  Future<void> openNew(WidgetTester tester,
          {Locale locale = const Locale('en')}) =>
      pumpGoals(tester, db, fake, location: newGoalRoute, locale: locale);

  Future<void> choose(WidgetTester tester, GoalKind kind) async {
    await tester.tap(find.byKey(Key('goal-kind-${kind.name}')));
    await tester.pumpAndSettle();
  }

  Future<void> pickTracker(WidgetTester tester, Tracker tracker) async {
    await tapVisible(tester, find.byKey(const Key('goal-tracker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('goal-tracker-option-${tracker.id}')));
    await tester.pumpAndSettle();
  }

  String nameText(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('goal-name')))
      .controller!
      .text;

  VoidCallback? save(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('goal-save'))).onPressed;

  bool chip(WidgetTester tester, String key) =>
      switch (tester.widget(find.byKey(Key(key)))) {
        ChoiceChip(:final selected) => selected,
        FilterChip(:final selected) => selected,
        final other => throw StateError('$key is a ${other.runtimeType}'),
      };

  Future<Goal> savedGoal(WidgetTester tester) async =>
      ((await firstOf(tester, db.goalsDao.watchAll())).single as GoalReadable)
          .goal;

  test('each rule refuses the draft, and a clear draft builds the goal', () {
    const money = MoneyFormatter(currency: Currency.toman, persianDigits: false);
    final cap = GoalEditorState(
      id: 'g',
      kind: GoalKind.spendingCap,
      name: 'Dining',
      nameEdited: true,
      targetText: '500,000',
      categoryPaths: const [diningPath],
      tags: null,
      baseFilters: const QueryFilters(direction: MoneyDirection.expense),
      tracker: null,
      period: PeriodType.month,
      since: day5,
      start: day5,
      end: day5,
      calendar: CalendarKind.jalali,
      weekStart: DateTime.saturday,
      alertPercents: Goal.defaultAlertPercents,
      active: true,
    );
    expect(goalEditorErrors(cap, money), isEmpty);
    expect(goalDraft(cap, money),
        spendingCap(id: 'g', name: 'Dining', target: 500000, since: day5));

    expect(goalEditorErrors(cap.copyWith(name: '  '), money),
        {GoalEditorError.nameBlank});
    expect(goalEditorErrors(cap.copyWith(targetText: ''), money),
        {GoalEditorError.targetMissing});
    expect(goalEditorErrors(cap.copyWith(targetText: 'abc'), money),
        {GoalEditorError.targetInvalid});
    expect(goalEditorErrors(cap.copyWith(targetText: '0'), money), isEmpty,
        reason: 'zero is a legitimate cap');

    final savings = cap.copyWith(
        kind: GoalKind.savingsTarget,
        baseFilters: const QueryFilters(),
        end: day5.addDays(-1));
    expect(goalEditorErrors(savings, money), {GoalEditorError.endBeforeStart});
    expect(goalEditorErrors(savings.copyWith(end: day5, targetText: '0'), money),
        {GoalEditorError.targetZero});

    final habit = cap.copyWith(kind: GoalKind.habitLimit, targetText: '3');
    expect(goalEditorErrors(habit, money), {GoalEditorError.trackerMissing});
    expect(goalDraft(habit, money), isNull);
  });

  testWidgets(
      'a new goal starts with its kind; a cap starts monthly, on all '
      'expenses, alerting at 80 and 100', (tester) async {
    await openNew(tester);
    for (final kind in GoalKind.values) {
      expect(find.byKey(Key('goal-kind-${kind.name}')), findsOneWidget);
    }

    await choose(tester, GoalKind.spendingCap);

    expect(nameText(tester), 'All expenses');
    expect(chip(tester, 'goal-period-month'), isTrue);
    expect(chip(tester, 'goal-alert-80'), isTrue);
    expect(chip(tester, 'goal-alert-100'), isTrue);
    expect(chip(tester, 'goal-alert-50'), isFalse);
    expect(
        tester
            .widget<SegmentedButton<CalendarKind>>(
                find.byKey(const Key('goal-calendar')))
            .selected,
        {CalendarKind.jalali},
        reason: 'from the settings');
    expect(save(tester), isNull, reason: 'no amount yet');
  });

  testWidgets('the other kinds start daily, weekly, or on a dated range',
      (tester) async {
    await useEnglishDigits(db);
    for (final (kind, period) in const [
      (GoalKind.habitLimit, 'day'),
      (GoalKind.habitGoal, 'week'),
    ]) {
      await openNew(tester);
      await choose(tester, kind);
      expect(chip(tester, 'goal-period-$period'), isTrue, reason: kind.name);
    }

    await openNew(tester);
    await choose(tester, GoalKind.savingsTarget);
    expect(nameText(tester), 'Savings target');
    expect(find.byKey(const Key('goal-period-month')), findsNothing,
        reason: 'a range, not a period');
    expect(
        find.descendant(
            of: find.byKey(const Key('goal-start')),
            matching: find.text('1405/07/13')),
        findsOneWidget);
    expect(find.text('The end must not be before the start'), findsNothing);
  });

  testWidgets('a blank name says so and keeps Save disabled', (tester) async {
    await openNew(tester);
    await choose(tester, GoalKind.spendingCap);
    await tester.enterText(find.byKey(const Key('tx-amount-field')), '500000');
    await tester.pump();
    expect(save(tester), isNotNull);

    await tester.enterText(find.byKey(const Key('goal-name')), '   ');
    await tester.pump();

    expect(find.text('Give the goal a name'), findsOneWidget);
    expect(save(tester), isNull);
  });

  testWidgets('a habit goal refuses zero; a habit limit saves it',
      (tester) async {
    // Zero is a legitimate limit, "zero cigarettes" (screen contract §7.2).
    final cig = await trackers.create(cigarettes);
    await openNew(tester);
    await choose(tester, GoalKind.habitGoal);
    await pickTracker(tester, cig);
    await tester.enterText(find.byKey(const Key('goal-target')), '0');
    await tester.pump();
    expect(find.text('The goal must be more than zero'), findsOneWidget);
    expect(save(tester), isNull);

    await openNew(tester);
    await choose(tester, GoalKind.habitLimit);
    await pickTracker(tester, cig);
    await tester.enterText(find.byKey(const Key('goal-target')), '0');
    await tester.pump();
    expect(find.text('The goal must be more than zero'), findsNothing);
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();

    final goal = await savedGoal(tester);
    expect(goal.name, 'Cigarettes');
    expect(goal.metric, GoalMetric.trackerCount);
    expect(goal.direction, GoalDirection.atMost);
    expect(goal.target, const QuantityAmount(0));
    expect(goal.period, const RecurringPeriod(PeriodType.day, day5));
    expect(find.byKey(Key('goal-card-${goal.id}')), findsOneWidget,
        reason: 'back on the list');
  });

  testWidgets('a habit without a tracker says so; choosing one names it',
      (tester) async {
    final cig = await trackers.create(cigarettes);
    await openNew(tester);
    await choose(tester, GoalKind.habitLimit);
    expect(
        find.descendant(
            of: find.byKey(const Key('goal-tracker')),
            matching: find.text('Choose a tracker')),
        findsOneWidget);
    await tester.enterText(find.byKey(const Key('goal-target')), '5');
    await tester.pump();
    expect(save(tester), isNull);

    await pickTracker(tester, cig);

    expect(find.text('Choose a tracker'), findsNothing);
    expect(nameText(tester), 'Cigarettes');
    expect(find.text('Times'), findsOneWidget,
        reason: "a counter's target is a number of times");
    expect(save(tester), isNotNull);
  });

  testWidgets(
      "the preview shows the last three periods' outcomes and this "
      "period's progress", (tester) async {
    await useEnglishDigits(db);
    await spend(db, 500000, const DateKey(20260715));
    await spend(db, 1500000, const DateKey(20260815));
    await spend(db, 900000, const DateKey(20260915));
    await spend(db, 200000, const DateKey(20261002));
    await openNew(tester);
    await choose(tester, GoalKind.spendingCap);
    await tester.enterText(find.byKey(const Key('tx-amount-field')), '1000000');
    await tapVisible(tester, find.text('Gregorian'));
    // The preview runs once the last change has settled, ~300 ms on.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    // The form's fields hold Scrollables of their own, so drag the form
    // itself rather than "the" Scrollable.
    await tester.dragUntilVisible(find.byKey(const Key('goal-preview-current')),
        find.byKey(const Key('goal-editor')), const Offset(0, -200));
    await tester.pumpAndSettle();

    Finder row(int start, String text) => find.descendant(
        of: find.byKey(Key('goal-preview-$start')), matching: find.text(text));
    expect(row(20260701, '2026/07'), findsOneWidget);
    expect(row(20260701, 'Met'), findsOneWidget);
    expect(row(20260801, 'Over the limit'), findsOneWidget);
    expect(row(20260901, 'Met'), findsOneWidget);
    expect(find.text('This period: 200,000 of 1,000,000'), findsOneWidget);
  });

  testWidgets('a saved cap keeps its category and tags; the list shows it',
      (tester) async {
    final work = await TagRepository(db.tagsDao).findOrCreate('Work');
    await pumpGoals(tester, db, fake);
    await tester.tap(find.byKey(const Key('goals-new')));
    await tester.pumpAndSettle();
    await choose(tester, GoalKind.spendingCap);

    await tester.tap(find.byKey(const Key('goal-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-category-seed-dining')));
    await tester.pumpAndSettle();
    expect(nameText(tester), 'Dining',
        reason: 'the name follows the scope until the user types one');

    await tester.tap(find.byKey(const Key('goal-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('tag-option-${work.id}')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tag-picker-done')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('tx-amount-field')), '2000000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goals-list')), findsOneWidget,
        reason: 'back on the list');
    final goal = await savedGoal(tester);
    expect(goal.name, 'Dining');
    expect(
        goal.scope,
        MoneyScope(QueryFilters(
          direction: MoneyDirection.expense,
          categorySubtreePaths: const [diningPath],
          tags: TagsAny([work.path]),
        )));
    expect(goal.target, const MoneyAmount(Money(2000000)));
    expect(goal.period, const RecurringPeriod(PeriodType.month, day5));
    expect(goal.calendar, CalendarKind.jalali, reason: 'from the settings');
    expect(goal.weekStart, DateTime.saturday, reason: 'from the settings');
    expect(goal.alertPercents, const [80, 100]);
    expect(find.byKey(Key('goal-card-${goal.id}')), findsOneWidget);
  });

  testWidgets('editing a goal opens its own form, and saving keeps the goal',
      (tester) async {
    await useEnglishDigits(db);
    await service.save(spendingCap());

    await pumpGoals(tester, db, fake, location: editGoalRoute('cap'));

    expect(find.byKey(const Key('goal-kind-spendingCap')), findsNothing,
        reason: "an existing goal's kind is derived, not asked");
    expect(nameText(tester), 'Dining out');
    expect(
        find.descendant(
            of: find.byKey(const Key('goal-category')),
            matching: find.text('Dining')),
        findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('tx-amount-field')))
            .controller!
            .text,
        '1,000,000');

    await tester.enterText(find.byKey(const Key('tx-amount-field')), '1200000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();

    expect(await savedGoal(tester), spendingCap(target: 1200000));
  });

  testWidgets('Persian: right to left, Persian digits on the chips',
      (tester) async {
    await openNew(tester, locale: const Locale('fa'));
    await choose(tester, GoalKind.spendingCap);

    expect(Directionality.of(tester.element(find.byKey(const Key('goal-editor')))),
        TextDirection.rtl);
    expect(nameText(tester), 'همهٔ هزینه‌ها');
    expect(
        find.descendant(
            of: find.byKey(const Key('goal-alert-80')),
            matching: find.text('۸۰٪')),
        findsOneWidget);
  });

  testWidgets('at twice the font size no form overflows', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await openNew(tester, locale: const Locale('fa'));
    expect(tester.takeException(), isNull, reason: 'the kind tiles');
    for (final kind in GoalKind.values) {
      await openNew(tester, locale: const Locale('fa'));
      await choose(tester, kind);
      expect(tester.takeException(), isNull, reason: kind.name);
    }
  });
}
```

- [ ] **Step 3: Run the tests to confirm RED**

```bash
(cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/goal_editor_screen_test.dart C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/goal_format_test.dart)
```

Expected: FAIL to compile.
- The editor test names `goal_editor_controller.dart` (file not found), and so `GoalEditorState`, `goalEditorErrors` and `goalDraft`.
- The format test names `period` and `date`, which are not defined on `GoalFormat`.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-goal-editor
```

- [ ] **Step 5: Add the strings**

Write the scratchpad file `keys_goal_editor.json`:

```json
{
  "en": {
    "goalsAllExpenses": "All expenses",
    "goalsChooseTracker": "Choose a tracker",
    "goalsEditTitle": "Edit goal",
    "goalsErrorEndBeforeStart": "The end must not be before the start",
    "goalsErrorName": "Give the goal a name",
    "goalsErrorTargetInvalid": "Enter a number",
    "goalsErrorTargetZero": "The goal must be more than zero",
    "goalsFieldAlerts": "Alerts",
    "goalsFieldCategory": "Category",
    "goalsFieldEnd": "End",
    "goalsFieldName": "Name",
    "goalsFieldPeriod": "Period",
    "goalsFieldStart": "Start",
    "goalsFieldTags": "Tags",
    "goalsFieldTarget": "Target",
    "goalsFieldTracker": "Tracker",
    "goalsKindHabitGoal": "Habit goal",
    "goalsKindHabitGoalHint": "Do something at least so often, such as the gym three times a week",
    "goalsKindHabitLimit": "Habit limit",
    "goalsKindHabitLimitHint": "Keep something under a limit, such as five cigarettes a day",
    "goalsKindSavingsTarget": "Savings target",
    "goalsKindSavingsTargetHint": "Put an amount aside by a date",
    "goalsKindSpendingCap": "Spending cap",
    "goalsKindSpendingCapHint": "Spend at most an amount in a month, on everything or on one category",
    "goalsNoTrackers": "No trackers yet. Add one on the Trackers tab.",
    "goalsNotFoundBody": "It may have been deleted. Your other goals are on the Goals tab.",
    "goalsNotFoundTitle": "This goal is gone",
    "goalsPeriodDay": "Day",
    "goalsPeriodMonth": "Month",
    "goalsPeriodQuarter": "Quarter",
    "goalsPeriodWeek": "Week",
    "goalsPeriodYear": "Year",
    "goalsPreviewCurrent": "This period: {progress}",
    "@goalsPreviewCurrent": {"placeholders": {"progress": {"type": "String"}}},
    "goalsPreviewError": "Could not preview this goal",
    "goalsPreviewTitle": "What this goal would have said",
    "goalsScopeGone": "Deleted",
    "goalsTagsNone": "No tag filter",
    "goalsTargetDays": "Days",
    "goalsTargetMinutes": "Minutes",
    "goalsTargetTimes": "Times"
  },
  "fa": {
    "goalsAllExpenses": "همهٔ هزینه‌ها",
    "goalsChooseTracker": "یک عادت انتخاب کنید",
    "goalsEditTitle": "ویرایش هدف",
    "goalsErrorEndBeforeStart": "پایان نباید پیش از شروع باشد",
    "goalsErrorName": "برای هدف نامی بنویسید",
    "goalsErrorTargetInvalid": "یک عدد وارد کنید",
    "goalsErrorTargetZero": "هدف باید بیشتر از صفر باشد",
    "goalsFieldAlerts": "هشدارها",
    "goalsFieldCategory": "دسته",
    "goalsFieldEnd": "پایان",
    "goalsFieldName": "نام",
    "goalsFieldPeriod": "دوره",
    "goalsFieldStart": "شروع",
    "goalsFieldTags": "برچسب‌ها",
    "goalsFieldTarget": "مقدار هدف",
    "goalsFieldTracker": "عادت",
    "goalsKindHabitGoal": "هدف عادت",
    "goalsKindHabitGoalHint": "کاری را دست‌کم چند بار انجام دهید، مثلاً هفته‌ای سه بار باشگاه",
    "goalsKindHabitLimit": "حد عادت",
    "goalsKindHabitLimitHint": "چیزی را زیر یک حد نگه دارید، مثلاً روزی پنج نخ سیگار",
    "goalsKindSavingsTarget": "هدف پس‌انداز",
    "goalsKindSavingsTargetHint": "تا تاریخی مبلغی کنار بگذارید",
    "goalsKindSpendingCap": "سقف خرج",
    "goalsKindSpendingCapHint": "در یک ماه بیش از یک مبلغ خرج نکنید، برای همه یا برای یک دسته",
    "goalsNoTrackers": "هنوز عادتی ندارید. از زبانهٔ عادت‌ها یکی بسازید.",
    "goalsNotFoundBody": "شاید حذف شده باشد. اهداف دیگرتان در زبانهٔ اهداف است.",
    "goalsNotFoundTitle": "این هدف دیگر وجود ندارد",
    "goalsPeriodDay": "روز",
    "goalsPeriodMonth": "ماه",
    "goalsPeriodQuarter": "فصل",
    "goalsPeriodWeek": "هفته",
    "goalsPeriodYear": "سال",
    "goalsPreviewCurrent": "دورهٔ جاری: {progress}",
    "goalsPreviewError": "پیش‌نمایش این هدف ممکن نشد",
    "goalsPreviewTitle": "این هدف تا امروز چه می‌گفت",
    "goalsScopeGone": "حذف‌شده",
    "goalsTagsNone": "بدون فیلتر برچسب",
    "goalsTargetDays": "روز",
    "goalsTargetMinutes": "دقیقه",
    "goalsTargetTimes": "بار"
  }
}
```

Run:

```bash
python <scratchpad>/arb_add.py <scratchpad>/keys_goal_editor.json
(cd app && flutter gen-l10n)
```

Expected: `wrote … (+41 entries)` for en (40 keys and 1 `@` entry) and `(+40 entries)` for fa, and `gen-l10n` reports no errors.

- [ ] **Step 6: The preview provider and the period names**

In `app/lib/features/goals/application/goal_providers.dart`, append:

```dart
/// What a draft would have said over its last closed periods, and its
/// current progress (spec §5.3). The editor asks once its form has settled
/// for ~300 ms. The debounce lives in the editor's widget state, so no
/// provider timer outlives the screen.
final goalPreviewProvider = FutureProvider.autoDispose
    .family<GoalPreview, Goal>(
        (ref, draft) => ref.watch(goalServiceProvider).preview(draft));
```

In `app/lib/features/goals/application/goal_format.dart`, inside `GoalFormat`, after `digits`:

```dart
  /// [day] as a date in [calendar], as the transaction list writes one:
  /// `1405/07/13`.
  String date(CalendarKind calendar, DateKey day) =>
      _digits(_ymd(GoalPeriods.calendarFor(calendar), day));

  /// [range], one of [goal]'s periods, named in the goal's own calendar, not
  /// the app's (spec §5.2). Numeric, as Phase 3's period labels are:
  /// - a day is its date;
  /// - a month is `1405/07`;
  /// - a year is `1405`;
  /// - a week, a quarter and a fixed range are their first and last days.
  String period(Goal goal, DateRange range) {
    final calendar = GoalPeriods.calendarFor(goal.calendar);
    final first = calendar.partsOf(range.startInclusive);
    final type = switch (goal.period) {
      RecurringPeriod(:final type) => type,
      FixedRangePeriod() => null,
    };
    return _digits(switch (type) {
      PeriodType.day => _ymd(calendar, range.startInclusive),
      PeriodType.month => '${first.year}/${_two(first.month)}',
      PeriodType.year => '${first.year}',
      _ => '${_ymd(calendar, range.startInclusive)} – '
          '${_ymd(calendar, range.endInclusive)}',
    });
  }

  String _digits(String latin) =>
      persianDigits ? Digits.toPersian(latin) : latin;

  static String _ymd(AppCalendar calendar, DateKey day) {
    final parts = calendar.partsOf(day);
    return '${parts.year}/${_two(parts.month)}/${_two(parts.day)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
```

- [ ] **Step 7: Write the controller**

Create `app/lib/features/goals/application/goal_editor_controller.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';
import 'goal_kind.dart';
import 'goal_providers.dart';

/// What the editor starts from: the goal being edited and its tracker, or
/// nothing for a new goal. A deleted tracker arrives as null, and the form
/// then asks for another.
typedef GoalEditorSeed = ({Goal? goal, Tracker? tracker});

/// Why the draft cannot be saved yet (spec §5.3). [targetMissing] blocks the
/// save without an inline message: an empty field says enough.
enum GoalEditorError {
  nameBlank,
  targetMissing,
  targetInvalid,
  targetZero,
  endBeforeStart,
  trackerMissing,
}

const _keep = Object();

/// Everything the editor has collected.
///
/// The target is held as text, as the add-expense screen holds its amount.
/// Parsing happens when the draft is read, so `1.` is something the user is
/// typing rather than a value to represent.
///
/// Filters the editor does not show ([baseFilters]: payment methods,
/// necessity, …) and a tag filter it did not touch ([tags]) are carried over
/// unchanged. An edit then cannot quietly widen a goal.
@immutable
final class GoalEditorState {
  const GoalEditorState({
    required this.id,
    required this.kind,
    required this.name,
    required this.nameEdited,
    required this.targetText,
    required this.categoryPaths,
    required this.tags,
    required this.baseFilters,
    required this.tracker,
    required this.period,
    required this.since,
    required this.start,
    required this.end,
    required this.calendar,
    required this.weekStart,
    required this.alertPercents,
    required this.active,
  });

  final String id;

  /// Null until a new goal's kind is chosen.
  final GoalKind? kind;
  final String name;

  /// False while [name] is the editor's suggestion, which then follows the
  /// scope: the category's name, the tracker's.
  final bool nameEdited;
  final String targetText;

  /// Empty for all expenses. Written as the picked category's current path.
  final List<String> categoryPaths;
  final TagFilter? tags;
  final QueryFilters baseFilters;
  final Tracker? tracker;
  final PeriodType period;

  /// A recurring goal's history starts with the period containing it: today
  /// for a new goal, kept for an edited one.
  final DateKey since;
  final DateKey start;
  final DateKey end;
  final CalendarKind calendar;
  final int weekStart;
  final List<int> alertPercents;
  final bool active;

  GoalEditorState copyWith({
    GoalKind? kind,
    String? name,
    bool? nameEdited,
    String? targetText,
    List<String>? categoryPaths,
    Object? tags = _keep,
    QueryFilters? baseFilters,
    Tracker? tracker,
    PeriodType? period,
    DateKey? start,
    DateKey? end,
    CalendarKind? calendar,
    List<int>? alertPercents,
  }) =>
      GoalEditorState(
        id: id,
        kind: kind ?? this.kind,
        name: name ?? this.name,
        nameEdited: nameEdited ?? this.nameEdited,
        targetText: targetText ?? this.targetText,
        categoryPaths: categoryPaths ?? this.categoryPaths,
        // A sentinel, because null means "no tag filter" here.
        tags: identical(tags, _keep) ? this.tags : tags as TagFilter?,
        baseFilters: baseFilters ?? this.baseFilters,
        tracker: tracker ?? this.tracker,
        period: period ?? this.period,
        since: since,
        start: start ?? this.start,
        end: end ?? this.end,
        calendar: calendar ?? this.calendar,
        weekStart: weekStart,
        alertPercents: alertPercents ?? this.alertPercents,
        active: active,
      );
}

/// Every reason [state] cannot be saved. Empty means [goalDraft] builds.
///
/// These are the checks `Goal`'s constructor makes that a user can trip
/// (spec §5.3), so a draft that passes here never throws there. Zero is
/// refused only for an at-least goal: a limit of zero is legitimate.
Set<GoalEditorError> goalEditorErrors(
    GoalEditorState state, MoneyFormatter money) {
  final kind = state.kind;
  if (kind == null) return const {};
  final target = _targetOf(state, money);
  return {
    if (state.name.trim().isEmpty) GoalEditorError.nameBlank,
    if (state.targetText.trim().isEmpty)
      GoalEditorError.targetMissing
    else if (target == null)
      GoalEditorError.targetInvalid
    else if (kind.direction == GoalDirection.atLeast && target.isZero)
      GoalEditorError.targetZero,
    if (kind.isHabit && state.tracker == null) GoalEditorError.trackerMissing,
    if (kind == GoalKind.savingsTarget && state.end < state.start)
      GoalEditorError.endBeforeStart,
  };
}

/// The goal [state] describes, or null while anything blocks the save.
Goal? goalDraft(GoalEditorState state, MoneyFormatter money) {
  final kind = state.kind;
  if (kind == null || goalEditorErrors(state, money).isNotEmpty) return null;
  final base = state.baseFilters;
  return Goal(
    id: state.id,
    name: state.name.trim(),
    metric: switch (kind) {
      GoalKind.spendingCap => GoalMetric.moneySum,
      GoalKind.savingsTarget => GoalMetric.netSavings,
      GoalKind.habitLimit ||
      GoalKind.habitGoal =>
        habitMetricFor(state.tracker!.type),
    },
    scope: switch (kind) {
      GoalKind.spendingCap => MoneyScope(QueryFilters(
          direction: base.direction,
          categorySubtreePaths: state.categoryPaths,
          tags: state.tags,
          paymentMethodIds: base.paymentMethodIds,
          necessity: base.necessity,
          satisfaction: base.satisfaction,
          amountRange: base.amountRange,
          confirmedOnly: base.confirmedOnly,
          searchText: base.searchText,
        )),
      // All transactions, both directions (spec §5.3).
      GoalKind.savingsTarget => MoneyScope(base),
      GoalKind.habitLimit ||
      GoalKind.habitGoal =>
        TrackerScope(state.tracker!.id),
    },
    direction: kind.direction,
    target: _targetOf(state, money)!,
    period: kind == GoalKind.savingsTarget
        ? FixedRangePeriod(DateRange(state.start, state.end))
        : RecurringPeriod(state.period, state.since),
    calendar: state.calendar,
    weekStart: state.weekStart,
    alertPercents: state.alertPercents,
    active: state.active,
  );
}

GoalAmount? _targetOf(GoalEditorState state, MoneyFormatter money) {
  final kind = state.kind;
  if (kind == null) return null;
  if (!kind.isHabit) {
    final amount = money.parse(state.targetText);
    return amount == null || amount.isNegative ? null : MoneyAmount(amount);
  }
  // TrackerValues.parseAmount is written for entries and refuses zero. For a
  // limit, zero is a goal: "zero cigarettes".
  final value = double.tryParse(Digits.toLatin(state.targetText.trim())) == 0
      ? 0.0
      : TrackerValues.parseAmount(state.targetText);
  if (value == null) return null;
  // A duration is typed in minutes and measured in seconds.
  return QuantityAmount(
      state.tracker?.type == TrackerType.duration ? value * 60 : value);
}

/// Holds the editor's form. Auto-disposed, so a draft lives exactly as long
/// as its screen, as the add-expense form does.
class GoalEditorController extends Notifier<GoalEditorState> {
  GoalEditorController(this.seed);

  final GoalEditorSeed seed;

  /// The alert percents the chips offer.
  static const alertChoices = <int>[50, 80, 90, 100];

  @override
  GoalEditorState build() {
    // Read, not watched: a day or settings change must not reset a form
    // half written.
    final today = ref.read(goalTodayProvider);
    final money = ref.read(moneyFormatterProvider);
    final goal = seed.goal;
    if (goal == null) {
      return GoalEditorState(
        id: Ids.newId(),
        kind: null,
        name: '',
        nameEdited: false,
        targetText: '',
        categoryPaths: const [],
        tags: null,
        baseFilters: const QueryFilters(),
        tracker: null,
        period: PeriodType.month,
        since: today,
        start: today,
        end: today,
        // A new goal copies the settings at creation (spec §1).
        calendar: ref.read(calendarProvider).kind,
        weekStart: ref.read(firstDayOfWeekProvider),
        alertPercents: Goal.defaultAlertPercents,
        active: true,
      );
    }
    final filters = switch (goal.scope) {
      MoneyScope(:final filters) => filters,
      TrackerScope() => const QueryFilters(),
    };
    return GoalEditorState(
      id: goal.id,
      kind: kindOf(goal),
      name: goal.name,
      nameEdited: true,
      targetText: _textOf(goal.target, seed.tracker, money),
      categoryPaths: filters.categorySubtreePaths,
      tags: filters.tags,
      baseFilters: filters,
      tracker: seed.tracker,
      period: switch (goal.period) {
        RecurringPeriod(:final type) => type,
        FixedRangePeriod() => PeriodType.month,
      },
      since: goal.period.startDate,
      start: goal.period.startDate,
      end: goal.period.endDate ?? goal.period.startDate,
      calendar: goal.calendar,
      weekStart: goal.weekStart,
      alertPercents: goal.alertPercents,
      active: goal.active,
    );
  }

  /// Starts a new goal of [kind]: its direction and default period, and
  /// [suggestedName] until the user types one (spec §5.3).
  void chooseKind(GoalKind kind, {required String suggestedName}) {
    final today = ref.read(goalTodayProvider);
    final calendar = GoalPeriods.calendarFor(state.calendar);
    final month = calendar.periodContaining(today, PeriodType.month);
    state = state.copyWith(
      kind: kind,
      name: suggestedName,
      nameEdited: false,
      targetText: '',
      period: kind.defaultPeriod ?? state.period,
      start: today,
      // Six months, this one included: a horizon to change, not a rule.
      end: calendar.shiftPeriod(month, PeriodType.month, 5).endInclusive,
      baseFilters: kind == GoalKind.spendingCap
          ? const QueryFilters(direction: MoneyDirection.expense)
          : const QueryFilters(),
    );
  }

  void setName(String value) =>
      state = state.copyWith(name: value, nameEdited: true);

  void setTarget(String text) => state = state.copyWith(targetText: text);

  /// [path] null is all expenses. The name follows until the user types one.
  void setCategory(String? path, {required String suggestedName}) =>
      state = state.copyWith(
        categoryPaths: [if (path != null) path],
        name: state.nameEdited ? state.name : suggestedName,
      );

  void setTags(TagFilter? tags) => state = state.copyWith(tags: tags);

  void setTracker(Tracker tracker) => state = state.copyWith(
        tracker: tracker,
        name: state.nameEdited ? state.name : tracker.name,
      );

  void setPeriod(PeriodType period) => state = state.copyWith(period: period);

  void setStart(DateKey day) => state = state.copyWith(start: day);

  void setEnd(DateKey day) => state = state.copyWith(end: day);

  void setCalendar(CalendarKind calendar) =>
      state = state.copyWith(calendar: calendar);

  /// Adds or removes one alert percent. The last one stays on, because a goal
  /// alerts at least once (`Goal` refuses an empty list).
  void toggleAlert(int percent) {
    final current = state.alertPercents;
    if (current.contains(percent)) {
      if (current.length == 1) return;
      state = state.copyWith(
          alertPercents: [for (final p in current) if (p != percent) p]);
    } else {
      state = state.copyWith(alertPercents: [...current, percent]..sort());
    }
  }

  static String _textOf(
      GoalAmount target, Tracker? tracker, MoneyFormatter formatter) {
    final text = switch (target) {
      MoneyAmount(:final money) => formatter.format(money),
      QuantityAmount(:final value) =>
        _plain(tracker?.type == TrackerType.duration ? value / 60 : value),
    };
    return formatter.persianDigits ? Digits.toPersian(text) : text;
  }

  static String _plain(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';
}

final goalEditorProvider = NotifierProvider.autoDispose
    .family<GoalEditorController, GoalEditorState, GoalEditorSeed>(
        GoalEditorController.new);
```

`formatter.format(money)` already writes the settings' digits. `Digits.toPersian` on a string that is already Persian changes nothing, so the money branch is not converted twice.

- [ ] **Step 8: Write the kind tiles and the preview**

Create `app/lib/features/goals/presentation/widgets/goal_kind_tiles.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/goal_kind.dart';

/// A new goal starts here: four kinds, each a sentence the user recognises.
/// The four kinds are one formula, and the user never needs to know it
/// (screen contract §7.2).
class GoalKindTiles extends StatelessWidget {
  const GoalKindTiles({super.key, required this.onChosen});

  final ValueChanged<GoalKind> onChosen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      key: const Key('goal-kind-tiles'),
      padding: const EdgeInsets.all(NimbusTokens.space4),
      children: [
        for (final kind in GoalKind.values)
          Card(
            child: ListTile(
              key: Key('goal-kind-${kind.name}'),
              minTileHeight: NimbusTokens.minTapTarget + NimbusTokens.space6,
              leading: ExcludeSemantics(
                child: Icon(switch (kind) {
                  GoalKind.spendingCap => Icons.shopping_bag_outlined,
                  GoalKind.habitLimit => Icons.do_not_disturb_on_outlined,
                  GoalKind.habitGoal => Icons.trending_up,
                  GoalKind.savingsTarget => Icons.savings_outlined,
                }),
              ),
              title: Text(switch (kind) {
                GoalKind.spendingCap => l10n.goalsKindSpendingCap,
                GoalKind.habitLimit => l10n.goalsKindHabitLimit,
                GoalKind.habitGoal => l10n.goalsKindHabitGoal,
                GoalKind.savingsTarget => l10n.goalsKindSavingsTarget,
              }),
              subtitle: Text(switch (kind) {
                GoalKind.spendingCap => l10n.goalsKindSpendingCapHint,
                GoalKind.habitLimit => l10n.goalsKindHabitLimitHint,
                GoalKind.habitGoal => l10n.goalsKindHabitGoalHint,
                GoalKind.savingsTarget => l10n.goalsKindSavingsTargetHint,
              }),
              onTap: () => onChosen(kind),
            ),
          ),
      ],
    );
  }
}
```

Create `app/lib/features/goals/presentation/widgets/goal_preview.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/goal_format.dart';
import '../../application/goal_providers.dart';
import 'goal_card.dart';

/// What the draft would have said over its last closed periods, and where
/// this period stands, so a target is chosen against reality rather than
/// guessed (screen contract §7.2). Nothing while the draft cannot be saved.
class GoalPreviewPanel extends ConsumerWidget {
  const GoalPreviewPanel({super.key, required this.goal, this.tracker});

  /// The draft as it stood once the form settled; null while it is invalid.
  final Goal? goal;
  final Tracker? tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = goal;
    if (draft == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preview = ref.watch(goalPreviewProvider(draft));

    final Widget body;
    if (preview.hasError) {
      body = Row(
        key: const Key('goal-preview-error'),
        children: [
          Expanded(child: Text(l10n.goalsPreviewError)),
          TextButton(
            onPressed: () => ref.invalidate(goalPreviewProvider(draft)),
            child: Text(l10n.commonRetry),
          ),
        ],
      );
    } else if (!preview.hasValue) {
      body = Container(
        key: const Key('goal-preview-loading'),
        height: NimbusTokens.minTapTarget,
        decoration: BoxDecoration(
          color: NimbusSemanticColors.of(context).skeleton,
          borderRadius: NimbusTokens.borderRadiusSm,
        ),
      );
    } else {
      final value = preview.requireValue;
      final format = ref.watch(goalFormatProvider);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final outcome in value.recent)
            GoalOutcomeRow(
              key: Key('goal-preview-${outcome.period.startInclusive.value}'),
              goal: draft,
              outcome: outcome,
              tracker: tracker,
            ),
          Text(
            l10n.goalsPreviewCurrent(l10n.goalsProgressOf(
              format.amount(value.current.current, tracker: tracker),
              format.amount(value.current.target, tracker: tracker),
            )),
            key: const Key('goal-preview-current'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.goalsPreviewTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: NimbusTokens.space2),
        body,
      ],
    );
  }
}

/// One closed period: its name in the goal's calendar, its value, and how it
/// ended. Shared by the preview and the detail screen's history.
class GoalOutcomeRow extends ConsumerWidget {
  const GoalOutcomeRow(
      {super.key, required this.goal, required this.outcome, this.tracker});

  final Goal goal;
  final PeriodOutcome outcome;
  final Tracker? tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = ref.watch(goalFormatProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NimbusTokens.space2),
      child: Row(
        children: [
          Expanded(child: Text(format.period(goal, outcome.period))),
          Expanded(child: Text(format.amount(outcome.value, tracker: tracker))),
          Expanded(child: GoalStatusLine(status: outcome.status)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 9: Write the editor screen**

Create `app/lib/features/goals/presentation/goal_editor_screen.dart`:

```dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../categories/application/category_providers.dart';
import '../../categories/data/category_tree.dart';
import '../../settings/application/settings_providers.dart';
import '../../tags/application/tag_providers.dart';
import '../../tags/presentation/widgets/tag_chip_row.dart';
import '../../tags/presentation/widgets/tag_picker_sheet.dart';
import '../../trackers/application/tracker_providers.dart';
import '../../transactions/presentation/widgets/amount_field.dart';
import '../application/goal_editor_controller.dart';
import '../application/goal_format.dart';
import '../application/goal_kind.dart';
import '../application/goal_providers.dart';
import '../routes.dart';
import 'widgets/goal_kind_tiles.dart';
import 'widgets/goal_preview.dart';
import 'widgets/goal_write.dart';

/// Writes a goal (screen contract §7.2): for a new goal the kind first,
/// then one form for that kind, with a live preview against recent history.
class GoalEditorScreen extends ConsumerStatefulWidget {
  const GoalEditorScreen({super.key, this.id});

  /// The goal being edited, or null for a new one.
  final String? id;

  @override
  ConsumerState<GoalEditorScreen> createState() => _GoalEditorScreenState();
}

class _GoalEditorScreenState extends ConsumerState<GoalEditorScreen> {
  /// Frozen the first time the goal, and its tracker, are known. A later
  /// emission, such as the tracker's timer starting, must not reset a form
  /// half written.
  GoalEditorSeed? _seed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final id = widget.id;
    var seed = _seed;
    if (seed == null && id == null) seed = _seed = (goal: null, tracker: null);
    if (seed == null) {
      final goals = ref.watch(goalsProvider);
      if (goals.hasError) {
        return _ErrorScaffold(onRetry: () => ref.invalidate(goalsProvider));
      }
      if (!goals.hasValue) return const _LoadingScaffold();
      final goal = [
        for (final read in goals.requireValue)
          if (read case GoalReadable(:final goal) when goal.id == id) goal,
      ].firstOrNull;
      if (goal == null) {
        return Scaffold(
          appBar: AppBar(),
          body: NimbusEmptyState(
            icon: Icons.search_off,
            title: l10n.goalsNotFoundTitle,
            message: l10n.goalsNotFoundBody,
            actionLabel: l10n.navGoals,
            onAction: () => context.go(goalsRoute),
          ),
        );
      }
      Tracker? tracker;
      if (goal.scope case TrackerScope(:final trackerId)) {
        final found = ref.watch(trackerByIdProvider(trackerId));
        if (found.hasError) {
          return _ErrorScaffold(
              onRetry: () => ref.invalidate(trackerByIdProvider(trackerId)));
        }
        if (!found.hasValue) return const _LoadingScaffold();
        tracker = found.requireValue;
      }
      seed = _seed = (goal: goal, tracker: tracker);
    }
    return _GoalForm(seed: seed);
  }
}

class _GoalForm extends ConsumerStatefulWidget {
  const _GoalForm({required this.seed});

  final GoalEditorSeed seed;

  @override
  ConsumerState<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<_GoalForm> {
  late final _provider = goalEditorProvider(widget.seed);
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _targetFocus = FocusNode();

  /// The preview's debounce. It lives in widget state, so it ends with the
  /// screen.
  Timer? _debounce;

  /// The draft as it stood ~300 ms after the last change (spec §5.3).
  Goal? _previewed;

  @override
  void initState() {
    super.initState();
    ref.listenManual(_provider, (_, next) {
      // The editor changes these itself: a suggested name, or a target
      // cleared for a new kind. Typing leaves them equal, so the caret stays
      // where it is.
      if (_name.text != next.name) _name.text = next.name;
      if (_target.text != next.targetText) _target.text = next.targetText;
      _schedulePreview();
    }, fireImmediately: true);
  }

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _previewed =
          goalDraft(ref.read(_provider), ref.read(moneyFormatterProvider)));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _target.dispose();
    _targetFocus.dispose();
    super.dispose();
  }

  GoalEditorController get _controller => ref.read(_provider.notifier);

  Future<void> _save() async {
    final goal =
        goalDraft(ref.read(_provider), ref.read(moneyFormatterProvider));
    if (goal == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final service = ref.read(goalServiceProvider);
    // Awaited before leaving, as the add-expense screen does. If the write
    // fails, the user is still holding the form. No spinner: a local write
    // is sub-millisecond (screen contract §1.3).
    await reportingGoalFailure(
        messenger: messenger, l10n: l10n, write: () => service.save(goal));
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(goalsRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(_provider);
    final money = ref.watch(moneyFormatterProvider);
    final title =
        Text(widget.seed.goal == null ? l10n.goalsNew : l10n.goalsEditTitle);

    final kind = state.kind;
    if (kind == null) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: GoalKindTiles(
          onChosen: (kind) => _controller.chooseKind(kind,
              suggestedName: switch (kind) {
                GoalKind.spendingCap => l10n.goalsAllExpenses,
                GoalKind.savingsTarget => l10n.goalsKindSavingsTarget,
                // A habit is named after its tracker, once one is chosen.
                GoalKind.habitLimit || GoalKind.habitGoal => '',
              }),
        ),
      );
    }

    final errors = goalEditorErrors(state, money);
    final canSave = goalDraft(state, money) != null;
    return Scaffold(
      appBar: AppBar(title: title),
      body: ListView(
        key: const Key('goal-editor'),
        padding: const EdgeInsets.all(NimbusTokens.space4),
        children: [
          TextField(
            key: const Key('goal-name'),
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.goalsFieldName,
              border: const OutlineInputBorder(),
              errorText: errors.contains(GoalEditorError.nameBlank)
                  ? l10n.goalsErrorName
                  : null,
            ),
            onChanged: _controller.setName,
          ),
          const SizedBox(height: NimbusTokens.space2),
          ...switch (kind) {
            GoalKind.spendingCap => _capFields(l10n, state, errors, money),
            GoalKind.habitLimit ||
            GoalKind.habitGoal =>
              _habitFields(l10n, theme, state, errors),
            GoalKind.savingsTarget => _savingsFields(l10n, state, errors, money),
          },
          const SizedBox(height: NimbusTokens.space4),
          _AlertChips(
              selected: state.alertPercents, onToggled: _controller.toggleAlert),
          const SizedBox(height: NimbusTokens.space4),
          GoalPreviewPanel(goal: _previewed, tracker: state.tracker),
        ],
      ),
      // As on the add-expense screen: Save rides above the keyboard, in the
      // bottom third (screen contract §1.3).
      bottomNavigationBar: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(NimbusTokens.space4),
            child: SizedBox(
              height: NimbusTokens.minTapTarget,
              child: FilledButton(
                key: const Key('goal-save'),
                // Disabled until every inline error clears (spec §5.3).
                onPressed: canSave ? () => unawaited(_save()) : null,
                child: Text(l10n.commonSave,
                    style: theme.textTheme.titleMedium),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _capFields(AppLocalizations l10n, GoalEditorState state,
      Set<GoalEditorError> errors, MoneyFormatter money) {
    final categories = ref.watch(categoryNodesByIdProvider).value ??
        const <String, CategoryNode>{};
    final tagNodes = ref.watch(tagNodesByIdProvider).value ?? const {};
    final path = state.categoryPaths.firstOrNull;
    final tags = [
      for (final tagPath in state.tags?.subtreePaths ?? const <String>[])
        if (tagNodes[_leafOf(tagPath)] case final node?) node.value,
    ];
    return [
      ListTile(
        key: const Key('goal-category'),
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.goalsFieldCategory),
        // Named by the category's own id, the path's last segment, which
        // survives a move to another parent (Review Focus 1).
        subtitle: Text(path == null
            ? l10n.goalsAllExpenses
            : categories[_leafOf(path)]?.category.name ?? l10n.goalsScopeGone),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(_pickCategory()),
      ),
      ListTile(
        key: const Key('goal-tags'),
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.goalsFieldTags),
        // D3: a bounded row with a +N, however many tags the filter names.
        subtitle:
            tags.isEmpty ? Text(l10n.goalsTagsNone) : TagChipRow(tags: tags),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(_pickTags()),
      ),
      const SizedBox(height: NimbusTokens.space2),
      AmountField(
        controller: _target,
        focusNode: _targetFocus,
        formatter: money,
        label: l10n.amount,
        errorText: _targetError(l10n, errors),
        onChanged: _controller.setTarget,
      ),
      const SizedBox(height: NimbusTokens.space4),
      _PeriodChips(selected: state.period, onSelected: _controller.setPeriod),
      const SizedBox(height: NimbusTokens.space4),
      _CalendarChoice(
          selected: state.calendar, onChanged: _controller.setCalendar),
    ];
  }

  List<Widget> _habitFields(AppLocalizations l10n, ThemeData theme,
      GoalEditorState state, Set<GoalEditorError> errors) {
    // Loaded now, so the picker opens on a list rather than on nothing.
    ref.watch(trackersProvider);
    final tracker = state.tracker;
    return [
      ListTile(
        key: const Key('goal-tracker'),
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.goalsFieldTracker),
        subtitle: Text(
          tracker?.name ?? l10n.goalsChooseTracker,
          style: tracker == null
              ? TextStyle(color: theme.colorScheme.error)
              : null,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(_pickTracker()),
      ),
      const SizedBox(height: NimbusTokens.space2),
      TextField(
        key: const Key('goal-target'),
        controller: _target,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: switch (tracker) {
            null => l10n.goalsFieldTarget,
            Tracker(type: TrackerType.counter) => l10n.goalsTargetTimes,
            Tracker(type: TrackerType.boolean) => l10n.goalsTargetDays,
            Tracker(type: TrackerType.quantity, :final unit) =>
              unit ?? l10n.trackerAmountLabel,
            Tracker(type: TrackerType.duration) => l10n.goalsTargetMinutes,
          },
          border: const OutlineInputBorder(),
          errorText: _targetError(l10n, errors),
        ),
        onChanged: _controller.setTarget,
      ),
      const SizedBox(height: NimbusTokens.space4),
      _PeriodChips(selected: state.period, onSelected: _controller.setPeriod),
    ];
  }

  List<Widget> _savingsFields(AppLocalizations l10n, GoalEditorState state,
          Set<GoalEditorError> errors, MoneyFormatter money) =>
      [
        AmountField(
          controller: _target,
          focusNode: _targetFocus,
          formatter: money,
          label: l10n.amount,
          errorText: _targetError(l10n, errors),
          onChanged: _controller.setTarget,
        ),
        const SizedBox(height: NimbusTokens.space2),
        _DateTile(
          key: const Key('goal-start'),
          label: l10n.goalsFieldStart,
          day: state.start,
          calendar: state.calendar,
          onPicked: _controller.setStart,
        ),
        _DateTile(
          key: const Key('goal-end'),
          label: l10n.goalsFieldEnd,
          day: state.end,
          calendar: state.calendar,
          error: errors.contains(GoalEditorError.endBeforeStart)
              ? l10n.goalsErrorEndBeforeStart
              : null,
          onPicked: _controller.setEnd,
        ),
        const SizedBox(height: NimbusTokens.space4),
        _CalendarChoice(
            selected: state.calendar, onChanged: _controller.setCalendar),
      ];

  static String? _targetError(
          AppLocalizations l10n, Set<GoalEditorError> errors) =>
      errors.contains(GoalEditorError.targetInvalid)
          ? l10n.goalsErrorTargetInvalid
          : errors.contains(GoalEditorError.targetZero)
              ? l10n.goalsErrorTargetZero
              : null;

  /// A path's last segment: the category's or tag's own id.
  static String _leafOf(String path) =>
      path.split('/').where((segment) => segment.isNotEmpty).last;

  Future<void> _pickCategory() async {
    final l10n = AppLocalizations.of(context);
    final tree = ref.read(categoryTreeProvider).value ?? const <CategoryNode>[];
    // Expense categories a user can still choose: not archived, and not the
    // Uncategorized fallback, as the add screen's picker offers.
    final nodes = [
      for (final node in CategoryTree.flatten(tree))
        if (!node.category.archived &&
            node.category.kind == 'expense' &&
            !SystemCategoryIds.isSystem(node.category.id))
          node,
    ];
    final picked = await showModalBottomSheet<({String? path, String name})>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              key: const Key('goal-category-all'),
              leading: const ExcludeSemantics(child: Icon(Icons.all_inclusive)),
              title: Text(l10n.goalsAllExpenses),
              onTap: () => Navigator.of(context)
                  .pop((path: null, name: l10n.goalsAllExpenses)),
            ),
            for (final node in nodes)
              ListTile(
                key: Key('goal-category-${node.category.id}'),
                // D4: the indent stops growing at the token's depth.
                contentPadding: EdgeInsetsDirectional.only(
                  start: NimbusTokens.space4 +
                      math.min(node.depth, NimbusTokens.maxTreeIndentDepth) *
                          NimbusTokens.indentPerLevel,
                  end: NimbusTokens.space4,
                ),
                leading: ExcludeSemantics(
                  child: Icon(nimbusIconFor(node.category.iconKey),
                      color: Color(node.category.color)),
                ),
                title: Text(node.category.name),
                onTap: () => Navigator.of(context)
                    .pop((path: node.category.path, name: node.category.name)),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _controller.setCategory(picked.path, suggestedName: picked.name);
  }

  Future<void> _pickTags() async {
    final current = {
      for (final path
          in ref.read(_provider).tags?.subtreePaths ?? const <String>[])
        _leafOf(path),
    };
    final picked = await showTagPickerSheet(context, selected: current);
    if (picked == null || !mounted) return;
    // Read after the sheet, which can create a tag inline.
    // shortcut: a tag created in the sheet this instant may not be in the
    // tree yet, and is then left out; upgrade to a by-id read if a user
    // report shows one going missing.
    final nodes = ref.read(tagNodesByIdProvider).value ?? const {};
    final paths = [
      for (final id in picked)
        if (nodes[id] case final node?) node.value.path,
    ];
    _controller.setTags(paths.isEmpty ? null : TagsAny(paths));
  }

  Future<void> _pickTracker() async {
    final l10n = AppLocalizations.of(context);
    final trackers = ref.read(trackersProvider).value ?? const <Tracker>[];
    final picked = await showModalBottomSheet<Tracker>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (trackers.isEmpty) ListTile(title: Text(l10n.goalsNoTrackers)),
            for (final tracker in trackers)
              ListTile(
                key: Key('goal-tracker-option-${tracker.id}'),
                leading: ExcludeSemantics(
                  child: Icon(nimbusIconFor(tracker.iconKey),
                      color: Color(tracker.color)),
                ),
                title: Text(tracker.name),
                onTap: () => Navigator.of(context).pop(tracker),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _controller.setTracker(picked);
  }
}

class _PeriodChips extends StatelessWidget {
  const _PeriodChips({required this.selected, required this.onSelected});

  final PeriodType selected;
  final ValueChanged<PeriodType> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.goalsFieldPeriod,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: NimbusTokens.space2),
        // A Wrap, so five chips at twice the font size take two lines.
        Wrap(
          spacing: NimbusTokens.space2,
          runSpacing: NimbusTokens.space2,
          children: [
            for (final period in PeriodType.values)
              ChoiceChip(
                key: Key('goal-period-${period.name}'),
                label: Text(switch (period) {
                  PeriodType.day => l10n.goalsPeriodDay,
                  PeriodType.week => l10n.goalsPeriodWeek,
                  PeriodType.month => l10n.goalsPeriodMonth,
                  PeriodType.quarter => l10n.goalsPeriodQuarter,
                  PeriodType.year => l10n.goalsPeriodYear,
                }),
                selected: period == selected,
                onSelected: (_) => onSelected(period),
              ),
          ],
        ),
      ],
    );
  }
}

/// The goal's own calendar, copied from the settings at creation. A goal
/// keeps it when the app's calendar changes (the brief's first trap).
class _CalendarChoice extends StatelessWidget {
  const _CalendarChoice({required this.selected, required this.onChanged});

  final CalendarKind selected;
  final ValueChanged<CalendarKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsCalendar,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: NimbusTokens.space2),
        SegmentedButton<CalendarKind>(
          key: const Key('goal-calendar'),
          segments: [
            ButtonSegment(
                value: CalendarKind.jalali,
                label: Text(l10n.settingsCalendarJalali)),
            ButtonSegment(
                value: CalendarKind.gregorian,
                label: Text(l10n.settingsCalendarGregorian)),
          ],
          selected: {selected},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}

class _AlertChips extends ConsumerWidget {
  const _AlertChips({required this.selected, required this.onToggled});

  final List<int> selected;
  final ValueChanged<int> onToggled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = ref.watch(goalFormatProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context).goalsFieldAlerts,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: NimbusTokens.space2),
        Wrap(
          spacing: NimbusTokens.space2,
          runSpacing: NimbusTokens.space2,
          children: [
            for (final percent in GoalEditorController.alertChoices)
              FilterChip(
                key: Key('goal-alert-$percent'),
                label: Text(format.wholePercent(percent)),
                selected: selected.contains(percent),
                onSelected: (_) => onToggled(percent),
              ),
          ],
        ),
      ],
    );
  }
}

/// A date in the goal's calendar, picked with the platform's picker, as the
/// add-expense screen's date is.
class _DateTile extends ConsumerWidget {
  const _DateTile({
    super.key,
    required this.label,
    required this.day,
    required this.calendar,
    required this.onPicked,
    this.error,
  });

  final String label;
  final DateKey day;
  final CalendarKind calendar;
  final ValueChanged<DateKey> onPicked;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = this.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ref.watch(goalFormatProvider).date(calendar, day)),
          if (error != null)
            Text(error,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
      trailing: const Icon(Icons.calendar_today_outlined),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: day.toDateTime(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPicked(DateKey.fromDateTime(picked));
      },
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(), body: const NimbusLoadingList());
}

class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: NimbusErrorState(
        title: l10n.goalsErrorTitle,
        retryLabel: l10n.commonRetry,
        onRetry: onRetry,
      ),
    );
  }
}
```

In `app/lib/features/goals/routes.dart`:
1. Add `import 'presentation/goal_editor_screen.dart';`.
2. Replace `final goalRoutes = <RouteBase>[];` with:

```dart
final goalRoutes = <RouteBase>[
  GoRoute(
    path: newGoalRoute,
    name: 'goal-new',
    builder: (context, state) => const GoalEditorScreen(),
  ),
  GoRoute(
    path: '$goalsRoute/:id/edit',
    name: 'goal-edit',
    builder: (context, state) =>
        GoalEditorScreen(id: state.pathParameters['id']!),
  ),
];
```

- [ ] **Step 10: Run the tests to confirm GREEN**

```bash
(cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/ C:/Users/nimae/Desktop/nimbustats/app/test/localization_test.dart C:/Users/nimae/Desktop/nimbustats/app/test/ux_rules_test.dart)
```

Expected: PASS.

The preview test also proves Contract note 5: it shows three periods for a goal whose `since` is today. If it shows none, the data layer is honouring `since` in `preview`. That is a Task 9 bug. Fix it there in a separate `fix(goals): …` commit, not here.

**Mutation check.**
1. In `_targetOf`, drop the zero special case, so the habit branch is `final value = TrackerValues.parseAmount(state.targetText);`.
2. Re-run. Expected: "a habit goal refuses zero; a habit limit saves it" FAILS. Zero now reads as invalid, and Save stays disabled.
3. Restore it.

- [ ] **Step 11: Run the full gate**

Expected:
- `app` is 556 + 13 = **569**: the editor 11, format 2.
- The others are unchanged.

- [ ] **Step 12: Commit and merge**

```bash
git add app/lib/features/goals app/lib/l10n app/test/features/goals
git commit -F - <<'EOF'
feat(goals): the editor, kind first, with a live preview

A new goal starts from four tiles: spending cap, habit limit, habit
goal and savings target. Each sets the metric family, the direction
and the default period (month, day, week, a dated range), so nobody
has to know the four are one formula. An edited goal derives its kind.
A habit's metric follows its tracker's type, so there is no metric
picker. The calendar and week start come from the settings.

Validation is the spec's list. A blank name, zero on an at-least goal,
an end before the start and a missing tracker each show inline, and
Save stays disabled until they clear. Zero is accepted for a limit:
"zero cigarettes".

The preview shows what the draft would have said over the last three
closed periods, and where this one stands. It waits 300 ms after the
last change, and its timer lives in widget state, so it ends with the
screen.

The picker offers unarchived trackers. An existing goal over an
archived one keeps it. Filters the editor does not show are carried
over, so an edit cannot widen a goal.

Reuses AmountField, the tag picker sheet and the category tree
read-only.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only feat/goal-editor
```

---

### Task 13: Goal detail, history and streaks

Branch `feat/goal-detail`, slug `goal-detail`.

**Files:**
- Create: `app/lib/features/goals/presentation/goal_detail_screen.dart`, `app/lib/features/goals/presentation/widgets/goal_history_list.dart`
- Modify: `app/lib/features/goals/routes.dart`, the ARBs and the generated localizations
- Test: `app/test/features/goals/goal_detail_screen_test.dart` (new)
- Scratchpad: `keys_goal_detail.json`

**Interfaces:**
- Consumes:
  - `goalsProvider`, `goalProgressProvider`, `goalHistoryProvider`, `goalTodayProvider` and `goalServiceProvider` (Task 10).
  - From Task 11: `GoalCard`, `GoalStatusLine`, `GoalProgressBar`, `deleteGoalWithUndo` and `reportingGoalFailure`.
  - From Task 12: `GoalOutcomeRow`, `GoalFormat.date` and `GoalFormat.period`.
  - `GoalService.setActive`, `delete` and `restore` (Task 9).
- Produces:
  - `GoalDetailScreen(id:)` and the route `goal`.
  - `GoalHistoryList(goal:, tracker:)`, a sliver.
  - Keys:
    - the screen and its states: `goal-detail`, `goal-detail-loading`, `goal-detail-error`, `goal-detail-gone`;
    - this period: `goal-detail-amounts`, `goal-detail-status`, `goal-detail-bar`, `goal-detail-run-rate`, `goal-detail-pace`, `goal-detail-streak`, `goal-detail-progress-loading`, `goal-detail-progress-error`;
    - the actions: `goal-detail-edit`, `goal-detail-pause`, `goal-detail-delete`;
    - the history: `goal-history-loading`, `goal-history-error`, `goal-history-empty`, `goal-history-<periodStart>`.

- [ ] **Step 1: Branch**

```bash
git switch phase/5-goals
git switch -c feat/goal-detail
```

- [ ] **Step 2: Write the failing tests**

Create `app/test/features/goals/goal_detail_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/application/goal_providers.dart';
import 'package:nimbustats/features/goals/routes.dart';

import '../trackers/support/tracker_fixture.dart';
import 'support/goal_test_app.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late GoalService service;

  /// A Gregorian monthly cap on Dining since July, while the app keeps its
  /// default Jalali calendar, so every period name on screen must be
  /// Gregorian (spec §5.2).
  final cap = spendingCap(
      calendar: CalendarKind.gregorian, since: const DateKey(20260701));

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    service = goalServiceFor(db, fake.clock.today);
    await seedCategories(db);
  });
  tearDown(() => db.close());

  /// July over the cap; August and September under it; 300K so far in
  /// October.
  Future<void> seedHistory() async {
    await service.save(cap);
    await spend(db, 1200000, const DateKey(20260715));
    await spend(db, 400000, const DateKey(20260815));
    await spend(db, 900000, const DateKey(20260915));
    await spend(db, 300000, const DateKey(20261002));
  }

  Future<void> openDetail(WidgetTester tester,
          {Locale locale = const Locale('en'),
          List<Override> overrides = const []}) =>
      pumpGoals(tester, db, fake,
          location: goalDetailRoute('cap'),
          locale: locale,
          overrides: overrides);

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  Finder historyRow(int start, String text) => find.descendant(
      of: find.byKey(Key('goal-history-$start')), matching: find.text(text));

  testWidgets(
      'this period: the amounts in full, the status in words, the bar and '
      'the pace', (tester) async {
    await useEnglishDigits(db);
    await seedHistory();

    await openDetail(tester);

    expect(textOf(tester, 'goal-detail-amounts'), '300,000 of 1,000,000');
    expect(
        find.descendant(
            of: find.byKey(const Key('goal-detail-status')),
            matching: find.text('On track')),
        findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(find.descendant(
                of: find.byKey(const Key('goal-detail-bar')),
                matching: find.byType(LinearProgressIndicator)))
            .value,
        closeTo(0.3, 1e-9));
    // 300,000 over the five days of October so far, carried to 31 days.
    expect(textOf(tester, 'goal-detail-pace'),
        'At this pace: 1,860,000 by 2026/10/31');
  });

  testWidgets(
      "history runs newest first, named in the goal's own calendar, with its "
      'streak', (tester) async {
    await useEnglishDigits(db);
    await seedHistory();

    await openDetail(tester);

    expect(historyRow(20260901, '2026/09'), findsOneWidget);
    expect(historyRow(20260901, 'Met'), findsOneWidget);
    expect(historyRow(20260801, '400,000'), findsOneWidget);
    expect(historyRow(20260701, 'Over the limit'), findsOneWidget);
    expect(
        tester.getTopLeft(find.byKey(const Key('goal-history-20260901'))).dy,
        lessThan(tester
            .getTopLeft(find.byKey(const Key('goal-history-20260701')))
            .dy));
    expect(textOf(tester, 'goal-detail-streak'),
        '2 periods met in a row · best 2');
  });

  testWidgets('a goal with no finished period says so', (tester) async {
    await service.save(spendingCap(since: const DateKey(20261005)));

    await openDetail(tester);

    expect(find.byKey(const Key('goal-history-empty')), findsOneWidget);
    expect(find.text('No finished periods yet'), findsOneWidget);
    expect(find.byKey(const Key('goal-detail-streak')), findsNothing,
        reason: 'no streak to speak of');
  });

  testWidgets('a skeleton while the goals load', (tester) async {
    final never = StreamController<List<GoalRead>>();
    addTearDown(never.close);

    await openDetail(tester,
        overrides: [goalsProvider.overrideWith((ref) => never.stream)]);

    expect(find.byKey(const Key('goal-detail-loading')), findsOneWidget);
  });

  testWidgets('a failed read offers a retry and hides the raw error',
      (tester) async {
    await openDetail(tester, overrides: [
      goalsProvider.overrideWith(
          (ref) => Stream<List<GoalRead>>.error(Exception('boom'))),
    ]);

    expect(find.byKey(const Key('goal-detail-error')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
  });

  testWidgets('a failed history says so in its place; the rest stands',
      (tester) async {
    await useEnglishDigits(db);
    await seedHistory();

    await openDetail(tester, overrides: [
      goalHistoryProvider(cap).overrideWith(
          (ref) => Future<GoalHistoryResult>.error(Exception('boom'))),
    ]);

    expect(find.byKey(const Key('goal-history-error')), findsOneWidget);
    expect(find.text('Could not load the history'), findsOneWidget);
    expect(textOf(tester, 'goal-detail-amounts'), '300,000 of 1,000,000');
    expect(find.text('Exception: boom'), findsNothing);
  });

  testWidgets('a goal that is gone says so and offers the way back',
      (tester) async {
    await openDetail(tester);

    expect(find.byKey(const Key('goal-detail-gone')), findsOneWidget);
    expect(find.text('This goal is gone'), findsOneWidget);
  });

  testWidgets('pause stops the evaluation and keeps the history; resume '
      'restarts it', (tester) async {
    await useEnglishDigits(db);
    await seedHistory();
    await openDetail(tester);

    await tester.tap(find.byKey(const Key('goal-detail-pause')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const Key('goal-detail-status')),
            matching: find.text('Paused')),
        findsOneWidget);
    expect(find.byKey(const Key('goal-detail-bar')), findsNothing,
        reason: 'a paused goal is not evaluated');
    expect(find.byTooltip('Resume'), findsOneWidget);
    expect(find.byKey(const Key('goal-history-20260901')), findsOneWidget,
        reason: 'its history stands');

    await tester.tap(find.byKey(const Key('goal-detail-pause')));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const Key('goal-detail-status')),
            matching: find.text('On track')),
        findsOneWidget);
  });

  testWidgets('delete returns to the list, with an undo that brings it back',
      (tester) async {
    await useEnglishDigits(db);
    await seedHistory();
    await pumpGoals(tester, db, fake);
    await tester.tap(find.byKey(const Key('goal-card-cap')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-detail')), findsOneWidget);

    await tester.tap(find.byKey(const Key('goal-detail-delete')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goals-empty')), findsOneWidget,
        reason: 'back on the list, without it');
    expect(find.text('Goal deleted'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-card-cap')), findsOneWidget);
  });

  testWidgets(
      "Persian: right to left, Persian digits, and still the goal's own "
      'calendar', (tester) async {
    await seedHistory();

    await openDetail(tester, locale: const Locale('fa'));

    expect(Directionality.of(tester.element(find.byKey(const Key('goal-detail')))),
        TextDirection.rtl);
    expect(textOf(tester, 'goal-detail-amounts'), '۳۰۰٬۰۰۰ از ۱٬۰۰۰٬۰۰۰');
    expect(historyRow(20260901, '۲۰۲۶/۰۹'), findsOneWidget);
  });

  testWidgets('at twice the font size nothing overflows', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await seedHistory();

    await openDetail(tester, locale: const Locale('fa'));

    expect(tester.takeException(), isNull);
  });

  testWidgets("the bar speaks its goal's name and its percent",
      (tester) async {
    final handle = tester.ensureSemantics();
    await useEnglishDigits(db);
    await seedHistory();

    await openDetail(tester);

    final data = tester
        .getSemantics(find.byType(LinearProgressIndicator))
        .getSemanticsData();
    expect(data.label, 'Dining out');
    expect(data.value, '30%');
    handle.dispose();
  });
}
```

- [ ] **Step 3: Run the tests to confirm RED**

```bash
(cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/goal_detail_screen_test.dart)
```

Expected: FAIL. The file compiles: `goalDetailRoute` exists since Task 11, and the providers since Task 10. Every test fails because `/goals/cap` matches no route: the router's error screen (`router-error`) shows, and `goal-detail-*` finds nothing.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-goal-detail
```

- [ ] **Step 5: Add the strings**

Write the scratchpad file `keys_goal_detail.json`:

```json
{
  "en": {
    "goalsHistoryEmpty": "No finished periods yet",
    "goalsHistoryErrorTitle": "Could not load the history",
    "goalsHistoryTitle": "History",
    "goalsPace": "At this pace: {amount} by {date}",
    "@goalsPace": {"placeholders": {"amount": {"type": "String"}, "date": {"type": "String"}}},
    "goalsPause": "Pause",
    "goalsResume": "Resume",
    "goalsStreak": "{count, plural, =1{{current} period met in a row · best {best}} other{{current} periods met in a row · best {best}}}",
    "@goalsStreak": {"placeholders": {"count": {"type": "int"}, "current": {"type": "String"}, "best": {"type": "String"}}}
  },
  "fa": {
    "goalsHistoryEmpty": "هنوز دوره‌ای تمام نشده",
    "goalsHistoryErrorTitle": "سابقه بارگیری نشد",
    "goalsHistoryTitle": "سابقه",
    "goalsPace": "با همین روند: {amount} تا {date}",
    "goalsPause": "توقف",
    "goalsResume": "ادامه",
    "goalsStreak": "{count, plural, other{{current} دورهٔ موفق پشت سر هم · بهترین {best}}}"
  }
}
```

Run:

```bash
python <scratchpad>/arb_add.py <scratchpad>/keys_goal_detail.json
(cd app && flutter gen-l10n)
```

Expected: `wrote … (+9 entries)` for en and `(+7 entries)` for fa, and `gen-l10n` reports no errors.

- [ ] **Step 6: Write the history list and the screen**

Create `app/lib/features/goals/presentation/widgets/goal_history_list.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/goal_providers.dart';
import 'goal_preview.dart';

/// A goal's closed periods, newest first: met, exceeded or missed, each named
/// in the goal's own calendar (spec §5.2).
///
/// A sliver, built lazily, so years of a daily goal's history cost what is
/// on screen (screen contract §1.5). The cache serves the periods.
class GoalHistoryList extends ConsumerWidget {
  const GoalHistoryList({super.key, required this.goal, this.tracker});

  final Goal goal;
  final Tracker? tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(goalHistoryProvider(goal));
    if (history.hasError) {
      return SliverToBoxAdapter(
        child: Row(
          key: const Key('goal-history-error'),
          children: [
            Expanded(child: Text(l10n.goalsHistoryErrorTitle)),
            TextButton(
              onPressed: () => ref.invalidate(goalHistoryProvider(goal)),
              child: Text(l10n.commonRetry),
            ),
          ],
        ),
      );
    }
    if (!history.hasValue) {
      return SliverToBoxAdapter(
        child: Container(
          key: const Key('goal-history-loading'),
          height: NimbusTokens.minTapTarget,
          decoration: BoxDecoration(
            color: NimbusSemanticColors.of(context).skeleton,
            borderRadius: NimbusTokens.borderRadiusSm,
          ),
        ),
      );
    }
    final outcomes = history.requireValue.outcomes;
    if (outcomes.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NimbusTokens.space2),
          child: Text(l10n.goalsHistoryEmpty,
              key: const Key('goal-history-empty')),
        ),
      );
    }
    return SliverList.builder(
      itemCount: outcomes.length,
      itemBuilder: (context, index) {
        // Oldest first from the service; newest first on screen.
        final outcome = outcomes[outcomes.length - 1 - index];
        return GoalOutcomeRow(
          key: Key('goal-history-${outcome.period.startInclusive.value}'),
          goal: goal,
          outcome: outcome,
          tracker: tracker,
        );
      },
    );
  }
}
```

Create `app/lib/features/goals/presentation/goal_detail_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../trackers/application/tracker_providers.dart';
import '../application/goal_format.dart';
import '../application/goal_kind.dart';
import '../application/goal_providers.dart';
import '../routes.dart';
import 'widgets/goal_card.dart';
import 'widgets/goal_history_list.dart';
import 'widgets/goal_write.dart';

/// One goal: where this period stands and at what pace, its streak, and
/// its closed periods (spec §5.2). Edit, pause or resume, and delete with an
/// undo.
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final goals = ref.watch(goalsProvider);
    if (goals.hasError) {
      return Scaffold(
        appBar: AppBar(),
        body: NimbusErrorState(
          key: const Key('goal-detail-error'),
          title: l10n.goalsErrorTitle,
          retryLabel: l10n.commonRetry,
          detail: goals.error.toString(),
          onRetry: () => ref.invalidate(goalsProvider),
        ),
      );
    }
    if (!goals.hasValue) {
      return Scaffold(
        appBar: AppBar(),
        body: const NimbusLoadingList(key: Key('goal-detail-loading')),
      );
    }
    final read =
        goals.requireValue.where((read) => read.id == id).firstOrNull;
    if (read == null) {
      // A stale link: Phase 6's notification can hold a deleted goal's id.
      return Scaffold(
        appBar: AppBar(),
        body: NimbusEmptyState(
          key: const Key('goal-detail-gone'),
          icon: Icons.search_off,
          title: l10n.goalsNotFoundTitle,
          message: l10n.goalsNotFoundBody,
          actionLabel: l10n.navGoals,
          onAction: () => context.go(goalsRoute),
        ),
      );
    }
    return switch (read) {
      GoalUnreadable(:final name) => _ProblemScaffold(name: name, read: read),
      GoalReadable(:final goal) => switch (goal.scope) {
          TrackerScope(:final trackerId) =>
            _TrackerGoalDetail(goal: goal, trackerId: trackerId),
          MoneyScope() => _Detail(goal: goal),
        },
    };
  }
}

/// A goal that cannot be shown, with the Goals tab's own card and its Edit
/// and Delete. Either its tracker was deleted or its row does not parse.
class _ProblemScaffold extends StatelessWidget {
  const _ProblemScaffold({required this.name, required this.read});

  final String name;
  final GoalRead read;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: ListView(
          padding: const EdgeInsets.all(NimbusTokens.space4),
          children: [GoalCard(read: read)],
        ),
      );
}

class _TrackerGoalDetail extends ConsumerWidget {
  const _TrackerGoalDetail({required this.goal, required this.trackerId});

  final Goal goal;
  final String trackerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracker = ref.watch(trackerByIdProvider(trackerId));
    if (tracker.hasError) {
      return Scaffold(
        appBar: AppBar(),
        body: NimbusErrorState(
          title: l10n.goalsErrorTitle,
          retryLabel: l10n.commonRetry,
          detail: tracker.error.toString(),
          onRetry: () => ref.invalidate(trackerByIdProvider(trackerId)),
        ),
      );
    }
    if (!tracker.hasValue) {
      return Scaffold(appBar: AppBar(), body: const NimbusLoadingList());
    }
    final found = tracker.requireValue;
    // Deleted: the same card as on the tab (Review Focus 5).
    if (found == null) {
      return _ProblemScaffold(name: goal.name, read: GoalReadable(goal));
    }
    return _Detail(goal: goal, tracker: found);
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.goal, this.tracker});

  final Goal goal;
  final Tracker? tracker;

  /// Resume re-baselines (spec §4.3), so the goal does not alert about what
  /// crossed while it was paused. Pause writes only the flag.
  Future<void> _toggle(BuildContext context, WidgetRef ref) =>
      reportingGoalFailure(
        messenger: ScaffoldMessenger.of(context),
        l10n: AppLocalizations.of(context),
        write: () =>
            ref.read(goalServiceProvider).setActive(goal, !goal.active),
      );

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    await deleteGoalWithUndo(
      messenger: ScaffoldMessenger.of(context),
      l10n: AppLocalizations.of(context),
      service: ref.read(goalServiceProvider),
      id: goal.id,
    );
    // Back to the list, where the undo shows and the goal returns on Undo.
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(goalsRoute);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(goal.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const Key('goal-detail-edit'),
            tooltip: l10n.goalsEdit,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push(editGoalRoute(goal.id)),
          ),
          IconButton(
            key: const Key('goal-detail-pause'),
            tooltip: goal.active ? l10n.goalsPause : l10n.goalsResume,
            icon: Icon(goal.active
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline),
            onPressed: () => unawaited(_toggle(context, ref)),
          ),
          IconButton(
            key: const Key('goal-detail-delete'),
            tooltip: l10n.commonDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => unawaited(_delete(context, ref)),
          ),
        ],
      ),
      body: CustomScrollView(
        key: const Key('goal-detail'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(NimbusTokens.space4),
            sliver: SliverList.list(children: [
              if (goal.active)
                _Current(goal: goal, tracker: tracker)
              else
                const GoalStatusLine(
                    key: Key('goal-detail-status'), status: null),
              // A fixed range has one period, so no streak.
              if (goal.period is RecurringPeriod) _Streak(goal: goal),
              const SizedBox(height: NimbusTokens.space4),
              Text(l10n.goalsHistoryTitle, style: theme.textTheme.titleMedium),
            ]),
          ),
          SliverPadding(
            padding:
                const EdgeInsets.symmetric(horizontal: NimbusTokens.space4),
            sliver: GoalHistoryList(goal: goal, tracker: tracker),
          ),
        ],
      ),
    );
  }
}

/// This period: the amounts in full (D1, a detail view), the status, the bar
/// or the run-rate, and the pace.
class _Current extends ConsumerWidget {
  const _Current({required this.goal, this.tracker});

  final Goal goal;
  final Tracker? tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = ref.watch(goalProgressProvider(goal));
    if (progress.hasError) {
      return Row(
        key: const Key('goal-detail-progress-error'),
        children: [
          Expanded(child: Text(l10n.goalsCardErrorTitle)),
          TextButton(
            onPressed: () => ref.invalidate(goalProgressProvider(goal)),
            child: Text(l10n.commonRetry),
          ),
        ],
      );
    }
    if (!progress.hasValue) {
      return Container(
        key: const Key('goal-detail-progress-loading'),
        height: NimbusTokens.minTapTarget,
        decoration: BoxDecoration(
          color: NimbusSemanticColors.of(context).skeleton,
          borderRadius: NimbusTokens.borderRadiusSm,
        ),
      );
    }
    final value = progress.requireValue;
    final format = ref.watch(goalFormatProvider);
    final today = ref.watch(goalTodayProvider);
    final savings = kindOf(goal) == GoalKind.savingsTarget;
    final runRate = savings ? format.runRate(l10n, value) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.goalsProgressOf(format.amount(value.current, tracker: tracker),
              format.amount(value.target, tracker: tracker)),
          key: const Key('goal-detail-amounts'),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: NimbusTokens.space2),
        GoalStatusLine(key: const Key('goal-detail-status'), status: value.status),
        if (!savings) ...[
          const SizedBox(height: NimbusTokens.space2),
          GoalProgressBar(
              key: const Key('goal-detail-bar'), goal: goal, progress: value),
        ],
        if (runRate != null) ...[
          const SizedBox(height: NimbusTokens.space2),
          Text(runRate, key: const Key('goal-detail-run-rate')),
        ],
        // The pace is information only: an at-most status ignores it (spec
        // §2). Shown while the period is open, when there is a pace to
        // speak of.
        if (value.period.contains(today)) ...[
          const SizedBox(height: NimbusTokens.space2),
          Text(
            l10n.goalsPace(
              format.amount(value.projection.projectedEnd, tracker: tracker),
              format.date(goal.calendar, value.period.endInclusive),
            ),
            key: const Key('goal-detail-pace'),
          ),
        ],
      ],
    );
  }
}

class _Streak extends ConsumerWidget {
  const _Streak({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(goalHistoryProvider(goal));
    // The history below shows its own loading and error states, once.
    if (!history.hasValue) return const SizedBox.shrink();
    final streaks = history.requireValue.streaks;
    if (streaks.best == 0) return const SizedBox.shrink();
    final format = ref.watch(goalFormatProvider);
    return Padding(
      padding: const EdgeInsets.only(top: NimbusTokens.space2),
      child: Text(
        AppLocalizations.of(context).goalsStreak(streaks.current,
            format.digits(streaks.current), format.digits(streaks.best)),
        key: const Key('goal-detail-streak'),
      ),
    );
  }
}
```

In `app/lib/features/goals/routes.dart`:
1. Add `import 'presentation/goal_detail_screen.dart';`.
2. Append to `goalRoutes`, after the edit route:

```dart
  GoRoute(
    path: '$goalsRoute/:id',
    name: 'goal',
    builder: (context, state) =>
        GoalDetailScreen(id: state.pathParameters['id']!),
  ),
```

- [ ] **Step 7: Run the tests to confirm GREEN**

```bash
(cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/ C:/Users/nimae/Desktop/nimbustats/app/test/localization_test.dart C:/Users/nimae/Desktop/nimbustats/app/test/ux_rules_test.dart)
```

Expected: PASS.

**Mutation check.**
1. In `GoalFormat.period`, replace `GoalPeriods.calendarFor(goal.calendar)` with `GoalPeriods.calendarFor(CalendarKind.jalali)`, the app's default calendar.
2. Re-run the detail test. Expected: the history test FAILS, finding `1405/06` where `2026/09` belongs.
3. Restore it.

- [ ] **Step 8: Run the full gate**

Expected:
- `app` is 569 + 12 = **581**;
- the others are unchanged.

- [ ] **Step 9: Commit and merge**

```bash
git add app/lib/features/goals app/lib/l10n app/test/features/goals
git commit -F - <<'EOF'
feat(goals): the detail screen, with pace, streak and history

A goal's detail shows this period's amounts in full, its status in
words and an icon, the bar (or a savings target's run-rate), and the
pace: "At this pace: 1,860,000 by 2026/10/31". The pace is information
only, as the spec has it; an at-most status ignores it.

Recurring goals show their streak, and every goal its closed periods,
newest first, as met, exceeded or missed. The periods are named in
the goal's own calendar, so a Gregorian goal reads 2026/09 while the
app stays Jalali. The history is a lazy sliver served by the cache.

Pause writes only the flag. Resume re-baselines, so a goal does not
alert about what crossed while it was paused. Delete returns to the
list with an undo. A deleted tracker or an unreadable row shows the
tab's own problem card.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only feat/goal-detail
```

---

### Task 14: The alert snackbar on the shell

Branch `feat/goal-alerts-ui`, slug `goal-alerts-ui`.

**Files:**
- Create: `app/lib/features/goals/presentation/goal_alert_listener.dart`
- Modify: `app/lib/features/goals/application/goal_format.dart` (`alertMessage`)
- Modify (another owner's file, named in the commit): Phase 1's shell `app/lib/bootstrap/app_shell.dart`
- Modify: the ARBs and the generated localizations
- Test: `app/test/features/goals/goal_alert_listener_test.dart` (new), `app/test/features/goals/goal_format_test.dart`
- Scratchpad: `keys_goal_alerts.json`

**Interfaces:**
- Consumes:
  - `goalWatcherProvider` (`start`, `stop`, `alerts`), `goalTodayProvider` and `goalsProvider` (Task 10).
  - `goalDetailRoute` (Task 11) and the detail screen (Task 13).
  - `trackerClockProvider` (read-only).
- Produces:
  - `GoalAlertListener(child:)`, which wraps the shell's `Scaffold`.
  - `GoalFormat.alertMessage(AppLocalizations, GoalAlert, String period)`.
  - Each alert's snackbar is keyed `goal-alert-<goalId>`.

How the listener works:
- **Rollover.** It also carries the goals' midnight/resume rollover (Contract note 10), mirroring `TrackerDayRollover`. Its timer lives in widget state.
- **Mount.** It starts the watcher in `initState`. Its `dispose` calls `stop()`, so no provider timer outlives the tree (Contract note 1).
- **Queueing.** Snackbars go through the root `ScaffoldMessenger`, which queues them. An alert caused on a pushed screen waits behind that screen's own "Saved" or Undo snackbar, then shows on whatever screen is up.
- **`persist: false`.** A `SnackBar` with an action otherwise persists until something replaces it (see `nimbusUndoSnackBar`), and the next alert would queue behind it unseen.

- [ ] **Step 1: Branch**

```bash
git switch phase/5-goals
git switch -c feat/goal-alerts-ui
```

- [ ] **Step 2: Write the failing tests**

Append to `app/test/features/goals/goal_format_test.dart`:
1. Add `import 'package:flutter/material.dart';` and `import 'package:nimbustats/l10n/app_localizations.dart';` to the imports.
2. Add inside `main`:

```dart
  GoalAlert alert(GoalDirection direction, int percent, double fraction,
      {String name = 'Dining out'}) {
    const day = DateRange(DateKey(20261005), DateKey(20261005));
    return GoalAlert(
      goalId: 'g',
      goalName: name,
      period: day,
      percent: percent,
      direction: direction,
      progress: GoalProgress(
        period: day,
        current: QuantityAmount(fraction * 10),
        target: const QuantityAmount(10),
        status: GoalStatus.atRisk,
        fractionOfTarget: fraction,
        projection: const Projection(projectedEnd: QuantityAmount(0)),
      ),
    );
  }

  test('an alert is worded by its direction and by reaching 100% (spec §4.2)',
      () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
        english.alertMessage(en, alert(GoalDirection.atMost, 80, 0.82), 'month'),
        "Dining out: 82% of this month's limit");
    expect(
        english.alertMessage(
            en, alert(GoalDirection.atMost, 100, 1.05), 'month'),
        "Dining out: over this month's limit");
    expect(
        english.alertMessage(
            en, alert(GoalDirection.atLeast, 100, 1.0, name: 'Gym'), 'week'),
        "Gym: this week's goal met");
    expect(
        english.alertMessage(
            en, alert(GoalDirection.atLeast, 80, 0.8, name: 'Gym'), 'week'),
        "Gym: 80% of this week's goal");
    expect(english.alertMessage(en, alert(GoalDirection.atMost, 80, 0.8), 'day'),
        "Dining out: 80% of today's limit");
    expect(
        english.alertMessage(en,
            alert(GoalDirection.atLeast, 100, 1.2, name: 'Car'), 'fixedRange'),
        'Car: goal met');
  });

  test('an alert in Persian', () async {
    final fa = await AppLocalizations.delegate.load(const Locale('fa'));
    expect(
        persian.alertMessage(fa, alert(GoalDirection.atMost, 80, 0.82), 'month'),
        'Dining out: ۸۲٪ از سقف این ماه');
    expect(
        persian.alertMessage(
            fa, alert(GoalDirection.atLeast, 100, 1.0, name: 'Gym'), 'week'),
        'Gym: هدف این هفته محقق شد');
  });
```

Create `app/test/features/goals/goal_alert_listener_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/goals/application/goal_providers.dart';
import 'package:nimbustats/features/trackers/data/tracker_clock.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import '../trackers/support/tracker_fixture.dart';
import 'support/goal_test_app.dart';

void main() {
  const day5 = DateKey(20261005);

  /// The watcher's 300 ms debounce, and the evaluation after it.
  Future<void> letTheWatcherRun(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  /// A snackbar's four seconds, and its exit.
  Future<void> letASnackbarGo(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  group('on the real clock', () {
    // The add-expense screen and the tracker's quick log stamp "now", so
    // these goals stand on the real today too.
    late AppDatabase db;
    late GoalService service;
    const clock = TrackerClock();

    setUp(() {
      db = AppDatabase.openInMemory();
      service = goalServiceFor(db, clock.today);
    });
    tearDown(() => db.close());

    testWidgets(
        "a crossing from the add-expense screen alerts once, after its own "
        "'Saved'", (tester) async {
      // Review Focus 4.
      await useEnglishDigits(db);
      await service.save(spendingCap(
          id: 'all', name: 'Everything', paths: const [], since: clock.today()));
      await pumpApp(tester, database: db, seedFirstRun: true);

      await tester.tap(find.byKey(const Key('tx-add-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '900000');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();
      await letTheWatcherRun(tester);

      const message = "Everything: 90% of this month's limit";
      expect(find.text('Saved'), findsOneWidget,
          reason: "the save's own snackbar is not cut short");
      expect(find.text(message), findsNothing, reason: 'the alert waits');

      await letASnackbarGo(tester);
      expect(find.text('Saved'), findsNothing);
      expect(find.text(message), findsOneWidget);

      await letASnackbarGo(tester);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text(message), findsNothing, reason: 'shown once, only');
    });

    testWidgets("a crossing from a tracker's detail waits behind its Undo",
        (tester) async {
      await useEnglishDigits(db);
      final trackers = TrackerRepository(db.trackersDao, db.trackerEntriesDao,
          AnalyticsEngine(db, calendar: const JalaliCalendar()), clock);
      final cig = await trackers.create(cigarettes);
      await service.save(habitGoal(cig,
          id: 'smoke', target: 1, alerts: const [100], since: clock.today()));
      await pumpApp(tester, database: db, initialLocation: trackersRoute);
      await tester.tap(find.byKey(Key('tracker-tile-${cig.id}')));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
          of: find.byKey(const Key('tracker-quick-log')),
          matching: find.byType(InkWell)));
      await tester.pumpAndSettle();
      await letTheWatcherRun(tester);

      const message = "Cigarettes: over today's limit";
      expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget,
          reason: "the tap's undo stays in reach");
      expect(find.text(message), findsNothing);

      // The undo bar's five seconds.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
    });
  });

  group('on a fake clock', () {
    late FakeClock fake;
    late AppDatabase db;
    late GoalService service;

    setUp(() async {
      fake = FakeClock();
      db = AppDatabase.openInMemory();
      service = goalServiceFor(db, fake.clock.today);
      await seedCategories(db);
    });
    tearDown(() => db.close());

    testWidgets('crossings made while the app was closed queue, each once',
        (tester) async {
      await useEnglishDigits(db);
      await service.save(spendingCap());
      await service.save(
          spendingCap(id: 'fuel', name: 'Fuel', paths: const [transportPath]));
      await spend(db, 850000, day5);
      await spend(db, 1200000, day5, category: 'seed-transport');

      await pumpGoals(tester, db, fake);
      await letTheWatcherRun(tester);

      const dining = "Dining out: 85% of this month's limit";
      const fuel = "Fuel: over this month's limit";
      expect(find.text(dining), findsOneWidget);
      expect(find.text(fuel), findsNothing, reason: 'queued behind the first');

      await letASnackbarGo(tester);
      expect(find.text(dining), findsNothing);
      expect(find.text(fuel), findsOneWidget);

      await letASnackbarGo(tester);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text(dining), findsNothing);
      expect(find.text(fuel), findsNothing);
    });

    testWidgets("View opens the goal's detail", (tester) async {
      await useEnglishDigits(db);
      await service.save(spendingCap());
      await spend(db, 850000, day5);
      await pumpGoals(tester, db, fake);
      await letTheWatcherRun(tester);

      await tester.tap(find.widgetWithText(SnackBarAction, 'View'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('goal-detail')), findsOneWidget);
    });

    testWidgets("the goals' day moves at midnight and on resume",
        (tester) async {
      late ProviderContainer container;
      await pumpGoals(tester, db, fake, onContainer: (c) => container = c);
      expect(container.read(goalTodayProvider), day5);

      // 12:30 in Tehran: midnight is eleven and a half hours away.
      fake.advance(const Duration(hours: 12));
      await tester.pump(const Duration(hours: 12));
      expect(container.read(goalTodayProvider), const DateKey(20261006));

      fake.advance(const Duration(days: 1));
      await backgroundAndResume(tester);
      expect(container.read(goalTodayProvider), const DateKey(20261007));
    });
  });
}
```

- [ ] **Step 3: Run the tests to confirm RED**

```bash
(cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/goal_alert_listener_test.dart C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/goal_format_test.dart)
```

Expected:
- The format test FAILS to compile, naming `alertMessage`.
- The listener test compiles and FAILS: nothing starts the watcher, so no alert ever shows. The rollover test fails at its second expectation, still on `20261005`.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-goal-alerts-ui
```

- [ ] **Step 5: Add the strings**

Write the scratchpad file `keys_goal_alerts.json`. Each message picks its period words with an ICU `select` on the goal's `period.storedName`. A fixed range falls to `other`.

```json
{
  "en": {
    "goalsAlertGoalMet": "{name}: {period, select, day{today's goal met} week{this week's goal met} month{this month's goal met} quarter{this quarter's goal met} year{this year's goal met} other{goal met}}",
    "@goalsAlertGoalMet": {"placeholders": {"name": {"type": "String"}, "period": {"type": "String"}}},
    "goalsAlertGoalPercent": "{name}: {percent} of {period, select, day{today's goal} week{this week's goal} month{this month's goal} quarter{this quarter's goal} year{this year's goal} other{the goal}}",
    "@goalsAlertGoalPercent": {"placeholders": {"name": {"type": "String"}, "percent": {"type": "String"}, "period": {"type": "String"}}},
    "goalsAlertLimitOver": "{name}: over {period, select, day{today's limit} week{this week's limit} month{this month's limit} quarter{this quarter's limit} year{this year's limit} other{the limit}}",
    "@goalsAlertLimitOver": {"placeholders": {"name": {"type": "String"}, "period": {"type": "String"}}},
    "goalsAlertLimitPercent": "{name}: {percent} of {period, select, day{today's limit} week{this week's limit} month{this month's limit} quarter{this quarter's limit} year{this year's limit} other{the limit}}",
    "@goalsAlertLimitPercent": {"placeholders": {"name": {"type": "String"}, "percent": {"type": "String"}, "period": {"type": "String"}}},
    "goalsAlertView": "View"
  },
  "fa": {
    "goalsAlertGoalMet": "{name}: {period, select, day{هدف امروز محقق شد} week{هدف این هفته محقق شد} month{هدف این ماه محقق شد} quarter{هدف این فصل محقق شد} year{هدف امسال محقق شد} other{هدف محقق شد}}",
    "goalsAlertGoalPercent": "{name}: {percent} از {period, select, day{هدف امروز} week{هدف این هفته} month{هدف این ماه} quarter{هدف این فصل} year{هدف امسال} other{هدف}}",
    "goalsAlertLimitOver": "{name}: از {period, select, day{سقف امروز} week{سقف این هفته} month{سقف این ماه} quarter{سقف این فصل} year{سقف امسال} other{سقف}} گذشت",
    "goalsAlertLimitPercent": "{name}: {percent} از {period, select, day{سقف امروز} week{سقف این هفته} month{سقف این ماه} quarter{سقف این فصل} year{سقف امسال} other{سقف}}",
    "goalsAlertView": "مشاهده"
  }
}
```

Run:

```bash
python <scratchpad>/arb_add.py <scratchpad>/keys_goal_alerts.json
(cd app && flutter gen-l10n)
```

Expected:
- `wrote … (+9 entries)` for en and `(+5 entries)` for fa;
- `gen-l10n` reports no errors;
- `AppLocalizations` gains `goalsAlertLimitPercent(String name, String percent, String period)` and its siblings.

These are the first `select` messages in the ARBs. If `gen-l10n` rejects one, fix the message, never the generated file.

- [ ] **Step 6: Word the alert**

In `app/lib/features/goals/application/goal_format.dart`, inside `GoalFormat`, after `runRate`:

```dart
  /// What the shell's snackbar says about [alert] (spec §4.2).
  ///
  /// Below 100% it gives the percent reached, from the progress itself:
  /// "82%", not the 80 that fired. At 100% a limit is "over" and a goal
  /// "met". [period] is the goal's `period.storedName`, which picks
  /// "today's", "this week's" and so on; a fixed range reads plainly.
  /// Every at-most goal says "limit", because an alert does not carry a
  /// goal's kind (Contract note 11).
  String alertMessage(AppLocalizations l10n, GoalAlert alert, String period) {
    final name = alert.goalName;
    final reached = alert.percent >= 100;
    final percent = this.percent(alert.progress.fractionOfTarget);
    return switch (alert.direction) {
      GoalDirection.atMost => reached
          ? l10n.goalsAlertLimitOver(name, period)
          : l10n.goalsAlertLimitPercent(name, percent, period),
      GoalDirection.atLeast => reached
          ? l10n.goalsAlertGoalMet(name, period)
          : l10n.goalsAlertGoalPercent(name, percent, period),
    };
  }
```

- [ ] **Step 7: Write the listener and mount it on the shell**

Create `app/lib/features/goals/presentation/goal_alert_listener.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../trackers/application/tracker_providers.dart';
import '../application/goal_format.dart';
import '../application/goal_providers.dart';
import '../application/goal_watcher.dart';
import '../routes.dart';

/// Shows each goal alert as a snackbar, until Phase 6 makes them
/// notifications (spec §4.2). It also moves the goals' today at local
/// midnight and on every resume.
///
/// It sits on the shell, which is mounted for as long as the app runs, so
/// `trackers/` and `transactions/` stay untouched.
///
/// Snackbars go through the root `ScaffoldMessenger`, which queues them. An
/// alert caused on a pushed screen, such as the add-expense screen or a
/// tracker's detail, waits behind that screen's own "Saved" or Undo. It then
/// shows on whatever screen is up.
class GoalAlertListener extends ConsumerStatefulWidget {
  const GoalAlertListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GoalAlertListener> createState() => _GoalAlertListenerState();
}

class _GoalAlertListenerState extends ConsumerState<GoalAlertListener> {
  late final GoalWatcher _watcher;
  late final StreamSubscription<GoalAlert> _alerts;
  late final AppLifecycleListener _lifecycle;
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _watcher = ref.read(goalWatcherProvider);
    _alerts = _watcher.alerts.listen(_show);
    _watcher.start();
    _lifecycle = AppLifecycleListener(onResume: _rollOver);
    _schedule();
    // After the first frame: a provider cannot change while the tree is
    // building. On an ordinary day refresh changes nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rollOver();
    });
  }

  void _show(GoalAlert alert) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final router = GoRouter.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      key: Key('goal-alert-${alert.goalId}'),
      content: Text(ref
          .read(goalFormatProvider)
          .alertMessage(l10n, alert, _periodOf(alert.goalId))),
      // A snackbar with an action otherwise stays until something replaces
      // it, and the next alert would queue behind it unseen.
      persist: false,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(NimbusTokens.space4),
      action: SnackBarAction(
        label: l10n.goalsAlertView,
        onPressed: () => router.push(goalDetailRoute(alert.goalId)),
      ),
    ));
  }

  /// The goal's period type, for the wording. A goal deleted since its
  /// alert fired reads plainly, through the message's `other` case.
  String _periodOf(String goalId) {
    for (final read in ref.read(goalsProvider).value ?? const <GoalRead>[]) {
      if (read case GoalReadable(:final goal) when goal.id == goalId) {
        return goal.period.storedName;
      }
    }
    return 'other';
  }

  /// Arms a timer for just past the next local midnight, from the wall clock
  /// each time, as `TrackerDayRollover` does. A daylight-saving night then
  /// shifts only one firing.
  void _schedule() {
    _midnight?.cancel();
    final clock = ref.read(trackerClockProvider);
    final local = clock.toLocal(clock.nowUtc());
    final sinceMidnight = Duration(
      hours: local.hour,
      minutes: local.minute,
      seconds: local.second,
      milliseconds: local.millisecond,
    );
    _midnight = Timer(
      const Duration(days: 1) - sinceMidnight + const Duration(seconds: 1),
      _rollOver,
    );
  }

  void _rollOver() {
    ref.read(goalTodayProvider.notifier).refresh();
    _schedule();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _lifecycle.dispose();
    unawaited(_alerts.cancel());
    // The watcher outlives this widget in its provider. Its debounce timer
    // must not (Contract note 1).
    _watcher.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

In Phase 1's `app/lib/bootstrap/app_shell.dart`:
1. Add `import '../features/goals/presentation/goal_alert_listener.dart';` after the goals routes import.
2. Wrap the returned `Scaffold`: `return GoalAlertListener(child: Scaffold(...));`. Put this comment above it:

```dart
    // Goal alerts show over whichever screen is up, queued behind any
    // snackbar already showing. Mounted here because the shell is mounted
    // for as long as the app runs (spec §4.2).
```

- [ ] **Step 8: Run the tests to confirm GREEN**

```bash
(cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/goals/ C:/Users/nimae/Desktop/nimbustats/app/test/bootstrap/ C:/Users/nimae/Desktop/nimbustats/app/test/features/transactions/ C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/ C:/Users/nimae/Desktop/nimbustats/app/test/localization_test.dart)
```

Expected: PASS.

The transactions and trackers suites are here because every test that pumps the shell now starts the watcher. A failure reading "A Timer is still pending even after the widget tree was disposed" means a timer was left running. Find which one. Do not loosen the test.

**Mutation check.**
1. Delete `persist: false` from the alert's `SnackBar`.
2. Re-run the listener test. Expected: "crossings made while the app was closed queue, each once" FAILS. The first alert, which has an action, stays up, and `Fuel: over this month's limit` never shows.
3. Restore it.
4. Then delete `_watcher.stop();` from `dispose`.
5. Re-run. Expected: at least one test FAILS with "A Timer is still pending even after the widget tree was disposed".
6. Restore it.

- [ ] **Step 9: Run the full gate**

Expected:
- `app` is 581 + 7 = **588**: the listener 5, format 2.
- The others are unchanged.

- [ ] **Step 10: Commit and merge**

```bash
git add app/lib/features/goals app/lib/bootstrap/app_shell.dart app/lib/l10n app/test/features/goals
git commit -F - <<'EOF'
feat(goals): goal alerts show as a snackbar on the shell

Until Phase 6 delivers notifications, each crossing the GoalWatcher
records is shown once as a snackbar, with a View action to the goal.
The wording follows direction and percent: "Dining out: 82% of this
month's limit", "...: over this month's limit", "Gym: this week's goal
met".

Alerts go through the root ScaffoldMessenger, which queues them. A
crossing caused on the add-expense screen or a tracker's detail
appears after that screen's own Saved or Undo, never over it (Review
Focus 4). Several crossings found at start queue, and each is shown
once.

The listener sits on the shell, which is always mounted. It starts
the watcher and, on unmount, stops it, so no provider timer outlives
the widget tree. It also moves the goals' today at midnight and on
resume, because the trackers' rollover is mounted only on tracker
screens.

Touches Phase 1's app_shell.dart (one wrapper) and the shared ARBs.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only feat/goal-alerts-ui
```

---

### Task 15: The Phase 5 gate: device check, Persian review, docs, `phase-5-complete`

Branch `docs/phase-5-complete`, from `phase/5-goals`.

**Files:**
- Docs:
  - `docs/superpowers/screen-contract.md` (§2, §7, the index);
  - `docs/phases/phase-5-goals.md` (the definition of done and the gate record);
  - `docs/phases/README.md` (the status board);
  - `docs/superpowers/specs/2026-10-10-goals-5-design.md` (its status line);
  - `docs/phases/DEFERRED.md`, only if the check finds something.
- Scratchpad: `verify_goals_db.py`, the uiautomator dumps, and the database copies

- [ ] **Step 1: Branch**

```bash
git switch phase/5-goals
git switch -c docs/phase-5-complete
```

- [ ] **Step 2: Run the gate on the phase branch's tip**

From the repo root, run the six commands of the commit routine. Record each suite's count for the gate record.

Expected:
- `app` **588**;
- architecture, `nimbus_domain` and `nimbus_data` as Task 9's gate recorded them, with architecture including Task 6's kind-free test.

If a count differs, find out why before going on. A fix round may have added tests; record the real number, never the planned one.

- [ ] **Step 3: Device check on the Galaxy A53 (operator in the loop)**

The A53 (`RZCT209E3QX`) is the operator's daily phone, with their real data.
- **Before touching it, ask the operator to confirm it is free and unlocked.** Change none of its settings without saying so first.
- adb lives at `C:\dev\android-sdk\platform-tools\adb.exe`, and is not on Git Bash's PATH. Below, `ADB=/c/dev/android-sdk/platform-tools/adb.exe`.
- uiautomator dumps expose Flutter's semantics tree. Delete the old dump first, because a failed dump leaves a stale file.
- Prefix device paths with `MSYS_NO_PATHCONV=1` in Git Bash.

The scenarios add expenses and goals to the operator's real log. **Ask which category to use** (or create a "Goal test" category) and agree to delete everything afterwards, with the app's own undoable deletes.

Write the scratchpad file `verify_goals_db.py`:

```python
"""Prints what the v40 upgrade must preserve and add, for one database copy.
Run only on a scratch copy, never on the backup: closing the connection can
checkpoint or delete the -wal and -shm files beside it."""
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
print('user_version', db.execute('PRAGMA user_version').fetchone()[0])
print('live transactions', db.execute(
    'SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL').fetchone()[0])
tables = {r[0] for r in db.execute(
    "SELECT name FROM sqlite_master WHERE type = 'table'")}
print('goal tables', sorted(t for t in tables if t.startswith('goal')))
if 'goals' in tables:
    print('goals', db.execute(
        'SELECT name, metric, direction, period, calendar, active '
        'FROM goals WHERE deleted_at IS NULL').fetchall())
    print('alert state', db.execute(
        'SELECT goal_id, period_start, last_alerted_percent '
        'FROM goal_period_results ORDER BY goal_id, period_start').fetchall())
```

1. **Back up first.** Stop the app so nothing is mid-write, then copy all three files:

   ```bash
   ADB=/c/dev/android-sdk/platform-tools/adb.exe
   $ADB shell am force-stop com.nimbustats.app
   STAMP=$(date +%Y%m%d-%H%M)
   mkdir -p ~/nimbustats-backups
   for f in nimbustats.sqlite nimbustats.sqlite-wal nimbustats.sqlite-shm; do
     $ADB exec-out run-as com.nimbustats.app cat "app_flutter/$f" > ~/nimbustats-backups/"pre-v40-$STAMP-$f"
   done
   cp ~/nimbustats-backups/pre-v40-$STAMP-nimbustats.sqlite <scratchpad>/pre-v40-copy.sqlite
   python <scratchpad>/verify_goals_db.py <scratchpad>/pre-v40-copy.sqlite
   ```

   Expected:
   - `user_version 32`, the Phase 4 gate's version;
   - a live-transaction count, **write it down**;
   - `goal tables []`.

   A missing `-wal` makes `run-as` print an error and leaves an empty file. That is harmless.

2. **Build and install,** which upgrades v32 → v40 on the device:

   ```bash
   cd app && flutter build apk --profile --no-pub
   $ADB install -r build/app/outputs/flutter-apk/app-profile.apk
   $ADB shell monkey -p com.nimbustats.app -c android.intent.category.LAUNCHER 1
   ```

   Expected: `Success`, the app opens on Home with its data, and the nav bar shows five destinations, Goals third.

3. **Prove the upgrade from the database, not the screen.** Force-stop, copy the three files to `<scratchpad>/post-v40-*`, and run `verify_goals_db.py` on the copy.

   Expected:
   - `user_version 40`;
   - the **same** live-transaction count;
   - `goal tables ['goal_period_results', 'goals']`;
   - `goals []`.

4. **One goal of each kind,** created by tapping on the device, by the operator or over `input tap` with coordinates from a dump:
   - a spending cap of 100,000 on the agreed category;
   - a habit limit on Cigarettes, 5 a day;
   - a habit goal on Gym, 3 a week;
   - a savings target, 10,000,000 by the end of the sixth month.

   Dump the Goals tab and read each card's spoken sentence, e.g. "Goal test, 0 of 100K, On track". The savings card reads its run-rate, and has no bar.

5. **Cross 80% and 100% with real expenses.**
   1. Add an expense of 85,000 in the agreed category.
   2. Expected: "Saved", and only after it, one snackbar "<cap name>: 85% of this month's limit".
   3. Add 20,000.
   4. Expected: one snackbar "<cap name>: over this month's limit".
   5. Dump after each, and record the snackbar texts.

6. **No re-fire on recompute.**
   1. Force-stop and relaunch, then wait 5 s on the Goals tab.
   2. Expected: no snackbar.
   3. Then edit an unrelated transaction's note.
   4. Expected: no snackbar.
   5. Copy the database and run the script. Expected: the cap's current period has `last_alerted_percent 100`.

7. **Drop and re-cross.**
   1. Delete the 20,000 expense from its detail screen, with the undo snackbar, and do not undo.
   2. Expected: no alert. The cap reads 85K of 100K, At risk.
   3. Re-add 20,000.
   4. Expected: one "over this month's limit" snackbar again.
   5. In the database, the state went 100 → 80 → 100.

8. **A calendar switch keeps the goal's calendar.**
   1. Settings → Calendar → Gregorian.
   2. Open the cap's detail. Its pace line's date and its history names stay in the goal's calendar (Jalali, `1405/…`), while the transaction list turns Gregorian.
   3. Expected: no snackbar on the switch.
   4. Switch back to Jalali.

9. **Persian and English.**
   - If the operator agrees, switch the language and look at the Goals tab, a detail and one alert: Persian digits, right to left, and the alert in Persian. Switch back afterwards.
   - If they decline, record that the Persian device check was waived, as Phases 3 and 4 did. The Persian widget tests stand in for it:
     - `goals_screen_test.dart`: "Persian: right to left, Persian digits and words";
     - `goal_editor_screen_test.dart` and `goal_detail_screen_test.dart`: their Persian tests;
     - `goal_format_test.dart`: "an alert in Persian".

10. **Clean up,** as agreed: delete the test expenses and goals with the app's undoable deletes. Copy the database once more and record the final goal and transaction counts.

11. **Save the evidence.** Keep the dumps and the copies in the scratchpad, never the repo. Write down what was observed, including anything that did not match. A new problem becomes a numbered DEFERRED item, not a fix in this commit.

- [ ] **Step 4: Operator review of the Persian strings**

Show the operator every Persian value added in Tasks 11–14, beside its English, listed from `git diff main..phase/5-goals -- app/lib/l10n/app_fa.arb`.

If corrections come:
1. Make them a separate commit, `fix(l10n): …`.
2. Write a `keys_fix.json` with only the changed `fa` values, and `"en": {}`.
3. Run `python <scratchpad>/arb_add.py <scratchpad>/keys_fix.json --update`, then `flutter gen-l10n`.
4. Re-run the widget tests whose Persian text changed, then the gate.

- [ ] **Step 5: Update the screen contract**

In `docs/superpowers/screen-contract.md`:

1. In §2, replace `` `Goal`, `GoalEvaluation` (Phase 5). `` with `` `Goal`, `GoalProgress` (Phase 5; this contract first called it `GoalEvaluation`). ``
2. In the index, add a row after "Goal editor":

```markdown
| 20 | Goal detail | 5 | [§7.3](#73-goal-detail--phase-5) |
```

3. Replace §7.1's items 2–4 with:

```markdown
2. **Data in.** `List<GoalRead>`: each readable `Goal` with a
   `GoalProgress` (`{period, current, target, status, fractionOfTarget,
   projection}`) for its current period, computed in the goal's own
   calendar, not the app's.
3. **States.** All four, plus the statuses as designed states rather than
   colour swaps, each a word and an icon: **not started**, **on track**,
   **at risk** (a limit at its lowest alert percent, or a goal behind
   pace), **exceeded** (a limit gone over), **met**, **missed** (a closed
   `atLeast` period short of its target), and **paused**. Degenerate:
   - D1 on targets (`formatCompact` on the cards);
   - a savings goal, which reports its required run-rate ("900K/month for
     6 more months") instead of a progress bar;
   - a goal whose tracker was deleted: an error card with Edit and Delete;
   - an unreadable row: a card with Delete.
4. **Actions out.** `onGoalTapped(String id)`, `onGoalCreated()`,
   `onGoalDeleted(String id)` (undo). Pause and resume live on the detail
   (§7.3).
```

4. Append to §7.1's item 5: "Until Phase 6 delivers them as notifications, each crossing is one snackbar on the shell, queued behind any snackbar already showing."
5. In §7.2's item 2, after "The `Goal` under construction;", insert "for a new goal, four kind tiles first (spending cap, habit limit, habit goal, savings target), each setting the metric, direction and default period;".
6. After §7.2, add:

```markdown
### 7.3 Goal detail — Phase 5

1. **Purpose.** One goal: where this period stands and at what pace, its
   streak, and how its past periods ended.
2. **Data in.** One `Goal`, its `GoalProgress`, and its `GoalHistoryResult`
   (closed periods as `PeriodOutcome`s, and `GoalStreaks`). Period names in
   the goal's own calendar.
3. **States.** All four. The history is empty for a goal with no finished
   period. A deleted tracker or an unreadable row shows the Goals tab's
   error card. Degenerate: years of a daily goal's history, which is built
   lazily.
4. **Actions out.** `onGoalEdited(String id)`, `onGoalPaused(String id)`,
   `onGoalResumed(String id)`, `onGoalDeleted(String id)` (undo).
5. **UX budget.** The pace ("At this pace: 1,860,000 by 2026/10/31") is
   information only; an at-most status never turns on projection.
```

- [ ] **Step 6: Tick the brief's definition of done and write the gate record**

In `docs/phases/phase-5-goals.md`, "Definition of done", tick each item with its evidence. Take each test's file and name from the repo with `grep -rn "test(" <file>`; never paraphrase or invent a name.
- **One `evaluate` for all four types, proved by grep:** Task 6's test in `test/architecture_test.dart`.
- **Alerts on first crossing, no re-fire on recomputation, re-fire after a drop:**
  - Task 5's `crossing` tests in `packages/nimbus_domain/test/goals/goal_alert_test.dart`;
  - Task 9's re-baseline and concurrency tests;
  - `goal_watcher_test.dart` ("a crossing made while the app was closed alerts once, at start", "a calendar switch keeps each goal's own calendar and re-fires nothing").
- **Cache drop with identical results:** `packages/nimbus_data/test/goals/goal_cache_drop_test.dart`.
- **Both calendars, across a year boundary:** Task 3's and 4's tests in `goal_periods_test.dart` and `goal_assess_test.dart`.
- **`git tag phase-5-complete`.**

After the definition of done, add **"Gate record (date), against `CONVENTIONS.md` §5 on `<tip hash>`"**. Use `git log -1 --format=%h` for the hash; never invent one. Give one bullet per item:
- `dart analyze --fatal-infos`;
- the five suite counts from Step 2, with `--concurrency=4` for the app;
- the device upgrade: the backup path, `user_version` 32 → 40, and the live-transaction count before and after;
- the device scenarios from Step 3, each with what was observed: the snackbar texts, the alert-state rows, the calendar switch;
- strings: the counts per task (Task 11: 24, Task 12: 40, Task 13: 7, Task 14: 5, plus `navGoals` among Task 11's), both ARBs CRLF and sorted, and the operator's review;
- RTL and Persian digits: the widget tests named in Step 3.9, and the device check or its waiver;
- states: the Goals tab's, the editor's and the detail's loading, empty, error and populated tests, by name;
- accessibility, by name:
  - the card's single spoken sentence ("a card reads as one sentence: name, progress, status");
  - the bar's spoken name and percent ("the bar speaks its goal's name and its percent");
  - status as word and icon;
  - the 48-point tap targets;
  - the twice-the-font-size tests on the tab, the editor and the detail;
- Review Focus 1–5, each with its pinning test;
- the schema registry at v40;
- anything deferred, as numbered DEFERRED items.

In `docs/phases/README.md`'s status board:
- The Phase 5 row's status becomes `**Complete** (date). Goals tab, editor, detail and in-app alerts on Phase 3's engine; schema v40 ran on the Galaxy A53's data.`, followed by `Carried forward: …` if any item was deferred.
- The Phase 6 row's status becomes `Ready: phase-4-complete and phase-5-complete exist; it subscribes to goalWatcherProvider's alerts`.

In `docs/superpowers/specs/2026-10-10-goals-5-design.md`, replace the status line with `**Status:** implemented; the gate record is in the brief.`

- [ ] **Step 7: Commit, merge and tag**

```bash
git add docs/superpowers/screen-contract.md docs/phases docs/superpowers/specs/2026-10-10-goals-5-design.md
git commit -F - <<'EOF'
docs: Phase 5 is complete

Ticks the brief's definition of done with its evidence. The one-
evaluate rule is a test (architecture_test.dart), so it holds after
this gate as well as at it. Crossings are tested from the pure
crossing function up to the shell's snackbar, and the cache-drop test
proves every number re-derives from source.

The gate record follows CONVENTIONS §5: the suites, the v32 -> v40
upgrade on the A53's real data after a backup, and the device run.
One goal of each kind was created. A cap crossed 80% and 100%, each
alerting once, behind the save's own snackbar. Nothing re-fired on a
restart or an edit, and a drop and re-cross warned again. A calendar
switch left the goal's own calendar alone.

The screen contract catches up: GoalProgress replaces GoalEvaluation,
missed and paused join the statuses, and the goal detail gets its own
entry.

Phase 6 is unblocked: it subscribes to goalWatcherProvider's alerts.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/5-goals
git merge --ff-only docs/phase-5-complete
git switch main
git merge --ff-only phase/5-goals
git tag phase-5-complete
git tag --list 'phase-*-complete'
```

Expected:
- the list ends with `phase-5-complete`;
- `git merge --ff-only` succeeds, because `main` has not moved since Task 1's schema lock.

If `main` has moved, stop and ask the operator how to integrate; never rebase or force. Nothing is pushed until the operator asks.
