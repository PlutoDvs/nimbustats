# Phase 5 — Goals & limits — design

**Status:** approved 2026-10-10; the plan is `docs/superpowers/plans/2026-10-10-nimbustats-phase-5-goals.md`.
**Brief:** `docs/phases/phase-5-goals.md`.
**Prerequisites:** `phase-3-complete` and `phase-4-complete` both exist.
**Schema:** v40 · **Branch:** `phase/5-goals` · **Gate:** `phase-5-complete`

## Context

One engine covers four goal types — a monthly spending cap, a daily habit
limit, a weekly habit minimum and a savings target — because they differ only
by field values: *aggregate metric M over period P, compare to target T in
direction D*. Phase 5 decides that an alert is due; Phase 6 delivers it as a
notification. Until then the app shows it in-app.

Phase 5 *uses* Phase 3's `AnalyticsEngine` and Phase 4b's `TrackerQuerySpec`;
it modifies neither (`analytics/`, `trackers/` and `capture/` are off limits).

### What the code showed before the design

1. **The engine's weekly grouping ignores week start.**
   `GroupExpressions._periodFragment` takes no `firstDayOfWeek`, so a
   `GroupByPeriod(week)` always starts weeks on Saturday. Day grouping has no
   such dependency, so history groups by day and folds into the goal's own
   periods in Dart.
2. **`AnalyticsEngine` is built with one calendar** (the app's). That only
   affects period grouping. An ungrouped query over an explicit `DateRange`
   means the same thing in any calendar, so a goal computes its own range with
   its own calendar and hands the engine plain keys.
3. **`transaction_tags` has no `updated_at`.** It is a bare join table, and its
   rows are hard-deleted (cascade). A watermark over "rows in scope" cannot see
   a tag unlinked.
4. **A watermark over rows in scope is unsound anyway.** A transaction edited
   *out* of a goal's category bumps its `updated_at`, but it is no longer in
   scope, so the in-scope maximum does not move. A category moved under
   another parent changes which transactions a subtree filter matches without
   touching any transaction.
5. **Timestamps are wall-clock** (`DateTime.now().millisecondsSinceEpoch` at
   each write site).
6. **`firstDayOfWeek` is a user setting** (`firstDayOfWeekProvider`), so it
   changes what a weekly goal covers exactly as the calendar does.
7. **The shell has four tabs** and Home owns the only FAB
   (`app/lib/bootstrap/app_shell.dart`). Snackbars show on the shell's
   Scaffold.
8. **Reusable widgets exist:** `AmountField` (transactions), the tag picker
   sheet (tags). There is no filter builder (DEFERRED D10).

### Decisions taken with the operator (2026-10-09/10)

| Question | Decision |
|---|---|
| Where goals live | A fifth bottom tab: Home · Trackers · **Goals** · Analytics · Settings |
| How a crossing reaches the user before Phase 6 | A snackbar on the shell, queued behind the save's own snackbar |
| Editor shape | Kind first (four tiles), then one form for that kind |
| `rolling_n_days` | Left out. None of the four types uses it; `period` is TEXT, so adding it later is not a migration |
| Architecture | Pure domain core + a `GoalMeasurer` port implemented in `nimbus_data` over `AnalyticsEngine` |

### Where this design departs from the brief

1. **Watermark is table-wide, not in-scope** (findings 3–4). Money goals:
   `MAX(updated_at)` over `transactions`, `categories`, `tags`, deleted rows
   included. Tracker goals: `MAX(updated_at)` over that tracker's
   `tracker_entries`, deleted rows included.
2. **Alert state survives cache invalidation.** `last_alerted_percent` lives in
   `goal_period_results` as the brief says, but recomputing a stale row
   rewrites only its value and watermark columns.
3. **`GoalStatus` gains `missed`** — a closed `atLeast` period short of target.
   The brief's five statuses have no word for it; `exceeded` is a cap's
   failure, not a minimum's.
4. **New columns:** `name` (a card needs a label) and `week_start` (finding 6).
5. **The target is two columns**, `target_minor INTEGER` and
   `target_quantity REAL`, exactly one set. One `REAL` column would store money
   as `double`.
6. **Alert thresholds are whole percents** — `[80,100]`, not `[0.8,1.0]`.
   Money crossings are then exact integer arithmetic
   (`current × 100 ≥ target × pct`), and screen-contract §7.2 already types
   them `List<int>`. `last_alerted_threshold REAL` becomes
   `last_alerted_percent INTEGER`.
7. **Scope stores filters, not a whole query.** A money goal stores
   `QueryFilters` (lossless JSON since Phase 3); a tracker goal stores a
   tracker id, as the brief says. A `QuerySpec`'s group-by, aggregate and date
   range mean nothing to a goal — the metric and period decide those.
   Consequence: Phase 5 never stores a `TrackerQuerySpec`, so DEFERRED D21
   stops blocking Phase 5 (its `fromJson` tests remain owed; owner moves to
   "next trackers work").
8. **Edits re-baseline silently** (§4.3).

---

## 1. Data model — schema v40

One migration adds both tables. Taken as the schema lock (CONVENTIONS §2),
alone, on `main`.

### `goals` (with `BaseColumns`)

| Column | Type | Rule |
|---|---|---|
| `name` | TEXT | Non-blank. The editor suggests one from the scope. |
| `metric` | TEXT (`textEnum<GoalMetric>`) | `moneySum`, `txnCount`, `trackerSum`, `trackerCount`, `netSavings` |
| `scope_json` | TEXT | `{"type":"money","filters":{…}}` or `{"type":"tracker","trackerId":"…"}` |
| `direction` | TEXT (`textEnum<GoalDirection>`) | `atMost`, `atLeast` |
| `target_minor` | INTEGER NULL | Set for `moneySum`, `netSavings`; null otherwise |
| `target_quantity` | REAL NULL | Set for `txnCount`, `trackerSum`, `trackerCount`; null otherwise |
| `period` | TEXT | A `PeriodType` name, or `fixedRange` |
| `calendar` | TEXT (`textEnum<CalendarKind>`) | Copied from settings at creation, changeable in the editor |
| `week_start` | INTEGER | 1–7, copied from settings at creation |
| `start_date` | INTEGER | `DateKey`. Recurring: history starts with the period containing it. Fixed range: the range's first day |
| `end_date` | INTEGER NULL | Fixed range: its last day. Recurring: null |
| `alert_percents` | TEXT | JSON list of ints, default `[80,100]` |
| `active` | BOOL | Default true. False = paused: not evaluated, no alerts |

The four kinds are **not stored**. The editor derives one from metric family
and direction (§5.3), so storage never branches on a kind.

### `goal_period_results` (with `BaseColumns`)

| Column | Type | Rule |
|---|---|---|
| `goal_id` | TEXT | References `goals` |
| `period_start`, `period_end` | INTEGER | `DateKey`s. UNIQUE(`goal_id`, `period_start`) |
| `current_minor` / `current_quantity` | INTEGER NULL / REAL NULL | Cached value, typed like the goal's target |
| `source_watermark` | INTEGER NULL | The watermark it was computed at. NULL = stale |
| `last_alerted_percent` | INTEGER NULL | Alert state for this period. Never touched by a cache rewrite |

### Malformed rows

The DAO parses rows into domain values; a row that fails (unknown enum name,
bad JSON, both or neither target column set) raises `FormatException`, which
the list turns into an unreadable-goal card with a delete action — the same
treatment saved views give a corrupt row. Nothing defaults.

### Same commit

- `CONVENTIONS.md`: registry row v40; ownership row for
  `packages/nimbus_data/lib/src/goals/**` → Phase 5.
- `DEFERRED.md`: D21 updated per departure 7.
- Migration test v32 → v40 on the existing snapshot harness.

---

## 2. Domain — `nimbus_domain/lib/src/goals/`

Pure Dart. Every type immutable with value equality.

### Value types

- **`GoalMetric`** enum. `isMoney` is true for `moneySum` and `netSavings`.
- **`GoalDirection`** enum: `atMost`, `atLeast`.
- **`GoalScope`** (sealed): `MoneyScope(QueryFilters filters)`,
  `TrackerScope(String trackerId)`. `toJson`/`fromJson` with the `type`
  discriminator; `fromJson` throws `FormatException` on an unknown type, a
  missing field, or money filters that carry a `dateRange`.
- **`GoalAmount`** (sealed): `MoneyAmount(Money)`, `QuantityAmount(double)`.
  Money is never converted to `double`. The ratio `current / target` is a
  `double` — a ratio, not money.
- **`GoalPeriod`** (sealed): `Recurring(PeriodType type, DateKey since)`,
  `FixedRange(DateRange range)`. Maps to `period` + `start_date` + `end_date`;
  invalid combinations cannot be built.
- **`Goal`** — `id, name, metric, scope, direction, target, period, calendar,
  weekStart, alertPercents, active`. The constructor throws `ArgumentError`
  when:
  - the scope type does not match the metric family;
  - the target type does not match the metric (`MoneyAmount` iff `isMoney`);
  - `netSavings` has a money scope with a `direction` filter (it uses both);
  - the target is negative, or zero on `atLeast` (zero on `atMost` is
    legitimate: "zero cigarettes");
  - `alertPercents` is empty, unsorted, has duplicates, or a value outside
    1–100;
  - `weekStart` is outside 1–7;
  - the name is blank.
- **`GoalStatus`** enum: `notStarted`, `onTrack`, `atRisk`, `exceeded`, `met`,
  `missed`.
- **`Projection`** — `projectedEnd` (`GoalAmount`) and `requiredRate`
  (`RequiredRate(GoalAmount perMonth, int monthsLeft)?`, fixed range only).
- **`GoalProgress`** — `current, target, status, fractionOfTarget, projection,
  period (DateRange)`.

### Periods — `GoalPeriods`

Through `PeriodBoundaries` only; no period arithmetic here.

- `current(goal, today)` — recurring:
  `PeriodBoundaries.forPeriod(type, today, calendar, firstDayOfWeek:
  goal.weekStart)`; fixed range: its range.
- `closed(goal, today)` — recurring: `PeriodBoundaries.series(type,
  DateRange(since, today), …)` without its last element (the current period).
  Fixed range: none — it is one period.
- `calendarFor(CalendarKind)` — the two-case switch, local to goals so
  `calendar/` (Phase 0) is not modified.

### `assess(goal, period, current, today) → GoalProgress`

Pure. **One status function with the direction as input.**

Position in the period:

- **not started** — `today < max(period.start, goal start)`
- **open** — `period.contains(today)`
- **closed** — `today > period.end`

A goal created mid-period counts the **whole** period: a spending cap made on
the 15th shows what was already spent this month, because the month is what
the budget covers.

| | `atMost` (cap, limit) | `atLeast` (habit goal, savings) |
|---|---|---|
| not started | `notStarted` | `notStarted` |
| over target (any time) | `exceeded` | — |
| target reached (any time) | — | `met` |
| open | `atRisk` when progress ≥ the lowest alert percent, else `onTrack` | `atRisk` when behind pace, else `onTrack` |
| closed | `met` | `missed` |

- **Behind pace:** `current < target × fullDaysElapsed / daysInPeriod`, where
  `fullDaysElapsed` counts days *before* today. Day one of a gym week with no
  visit is on track.
- **`atMost` status ignores projection.** Rent paid on day one would otherwise
  hold a month at risk all month. Projection is information only.
- **Zero target (`atMost`)**: `fractionOfTarget` is 0 when `current` is 0 and
  `double.infinity` otherwise, so anything at all is `exceeded`. No division
  by zero.
- **Empty period:** `current` is zero and the table applies.
- **Net savings** may be negative; the same rules hold.

Projection:

- `projectedEnd` = `current ÷ daysElapsedIncludingToday × daysInPeriod`.
  Money: integer arithmetic, rounded half up. Not started: zero. Closed:
  `current`.
- `requiredRate` (fixed range only, while open): `monthsLeft` =
  `PeriodBoundaries.series(month, DateRange(today, end), calendar).length` in
  the goal's calendar; `perMonth` = `(target − current) / monthsLeft`, rounded
  **up** (it is a minimum), floored at zero.

### History fold and streaks

- `foldDaily(Map<DateKey, GoalAmount> daily, List<DateRange> periods)` → one
  `GoalAmount` per period; days with no entry contribute zero.
- `GoalStreaks.of(outcomes)` → `current` (consecutive `met` closed periods
  ending at the most recent) and `best`. Recurring goals only.

### Crossing — `crossing(progress, alertPercents, lastAlerted) → CrossingResult`

- `reached` = the highest alert percent progress has reached. Money compares
  exactly: `current.minor × 100 ≥ target.minor × pct`. Quantity:
  `current × 100 ≥ target × pct`. Zero `atMost` target: any positive current
  reaches every percent.
- `reached > lastAlerted` (null below everything): **one** `GoalAlert` for
  `reached`; new state `reached`. A jump from 70% to 105% alerts once, at 100.
- `reached < lastAlerted`: no alert; new state `reached` (may be null). A
  genuine re-crossing then warns again — the brief's recommended rule.
- Otherwise: no alert, state unchanged. Recomputation never re-fires.

### `GoalAlert`

`{goalId, goalName, period, percent, direction, progress}`. Data only; the UI
words it from ARB.

### `GoalMeasurer` (port) and `GoalEngine`

```dart
abstract interface class GoalMeasurer {
  Future<GoalAmount> measure(GoalMetric metric, GoalScope scope, DateRange range);
  Future<Map<DateKey, GoalAmount>> measureDaily(
      GoalMetric metric, GoalScope scope, DateRange span);
}
```

`GoalEngine(measurer, {required DateKey Function() today})`:
`evaluate(Goal goal, DateRange period) → Future<GoalProgress>` = measure, then
`assess`. This is the brief's interface; Phase 6 calls it.

---

## 3. Data layer — `nimbus_data/lib/src/goals/`

### `EngineGoalMeasurer implements GoalMeasurer`

**The only switch on `GoalMetric` in the codebase.** Everything after it is
shared.

| Metric | `measure` | `measureDaily` |
|---|---|---|
| `moneySum` | `QuerySpec(filters.withDateRange(range), GroupByNone, sum)` → `trueTotal` | same with `GroupByPeriod(day)` → bucket money |
| `txnCount` | same, `count` → `trueCount` | → bucket count |
| `trackerSum` | `TrackerQuerySpec([id], range, TrackerGroupByNone, sum)` → `sum` | `TrackerGroupByDay` → bucket value |
| `trackerCount` | same, `count` → `count` | → bucket count |
| `netSavings` | two money queries, `direction: income` minus `direction: expense` | two day-grouped queries, subtracted per day |

`TrackerQuerySpec` is constructed directly; `TrackerQueries` (Phase 4) is not
extended.

### DAOs

- **`GoalsDao`** — `watchAll()` (live goals, active and paused), `byId`,
  `insert`, `update`, `setActive`, `softDelete`, `restore`. Insert, update and
  resume re-baseline (§4.3) in the same transaction.
- **`GoalPeriodResultsDao`** — rows for a goal; `writeValues(rows)` (upsert
  that touches only value and watermark columns); `recordCrossing(goalId,
  period, progress, alertPercents)`, which reads `last_alerted_percent`, runs
  `crossing`, writes the new state and returns the alert, **in one
  transaction**; `moneyWatermark()`; `trackerWatermark(trackerId)`.

### `GoalHistory`

`history(goal, today)` → closed periods with value and outcome, plus streaks:

1. Read the goal's cached rows and the current watermark (one query).
2. Rows whose watermark matches are used as they are.
3. Missing or stale periods are recomputed together: one `measureDaily` over
   the span they cover, `foldDaily`, `writeValues` in one transaction.

The current period is never served from cache; it is measured live. Its row
exists to hold alert state.

### The watermark

- Money: `MAX(updated_at)` over `transactions`, `categories`, `tags`, deleted
  rows included.
- Tracker: `MAX(updated_at)` over `tracker_entries WHERE tracker_id = ?`,
  deleted rows included.

**Verified in the plan, before the cache task:**

- whether editing a transaction's tags rewrites the transaction row. If not,
  `COUNT(*)` of `transaction_tags` joins the money watermark;
- whether any path hard-deletes transactions or tracker entries. If so, the
  row count joins that watermark;
- `EXPLAIN QUERY PLAN` and timing of the money `MAX` on a seeded
  50 000-transaction database. An `updated_at` index is added in v40 only if
  the scan measurably costs a frame.

`shortcut:` wall-clock stamps — a write stamped earlier than the stored
maximum (clock set back) does not move the watermark; the next ordinary write
or any goal edit heals it. Upgrade to a monotonic write counter if a user
report traces back to it.

### Concurrency

Goal evaluations are issued together (`Future.wait`), but drift runs them on
its single connection, so there is no parallelism to cap. `recordCrossing`'s
transaction is what makes two evaluators — the app and, later, Phase 6's
background isolate — unable to fire one crossing twice.

---

## 4. Alerts

### 4.1 `GoalWatcher` (`app/lib/features/goals/application/`)

- Evaluates every **active** goal's **current** period:
  - once at app start (catches crossings from background SMS capture);
  - on `engine.changes()` for money goals;
  - on `engine.trackerChanges()` for tracker goals;
  - debounced ~300 ms, so a burst of taps is evaluated once.
- Each evaluation goes through `recordCrossing`; a returned alert goes onto
  `Stream<GoalAlert>` — **the interface Phase 6 subscribes to.**
- Closed periods never alert: editing last month's transaction never warns
  about last month.

### 4.2 `GoalAlertListener` (on the shell)

- Shows each alert as a snackbar with a **View** action to the goal's detail.
- `ScaffoldMessenger` queues it behind any snackbar already showing, so a
  save's "Saved / Undo" is never hidden.
- Wording by direction and percent:
  - `atMost` below 100: "Dining out: 82% of this month's cap"
  - `atMost` at 100: "Dining out: over this month's cap"
  - `atLeast` at 100: "Gym: this week's goal met"
  - `atLeast` below 100: "Gym: 80% of this week's goal"
- On the shell, so `trackers/` and `transactions/` are untouched.

### 4.3 Edits re-baseline silently

Creating, editing or resuming a goal deletes its cached rows, evaluates the
current period, and stores `last_alerted_percent` = whatever it already
reaches — **without** emitting an alert. The user is looking at the goal while
editing it; an alert about their own edit is noise. The one rule covers every
edit, including period, calendar and week-start changes that invalidate the
old period keys.

A full `DELETE FROM goal_period_results` also clears alert state, so it is a
test and repair tool only; the app never issues it.

---

## 5. Screens — `app/lib/features/goals/`

`routes.dart` exposes `goalShellRoutes`; the router adds one line, the shell
one destination (flag icon) between Trackers and Analytics.

### 5.1 Goals tab (screen contract §7.1)

- One card per goal: name; status as text **and** icon, never colour alone;
  `current / target` in locale digits.
  - Caps and limits: a progress bar filling toward the limit.
  - Habit goals: a bar filling toward the goal.
  - Savings: no progress bar — "4.2M/month for 5 more months".
- Paused goals in a "Paused" section.
- States: `loading` (skeleton), `empty` (what a goal is + "New goal"),
  `error` (what failed + Retry), `populated`. A goal whose tracker was deleted
  shows an error card with Edit and Delete; an unreadable row (§1) shows a
  card with Delete.
- "New goal" in the app bar and the empty state. The add-expense FAB stays on
  Home.

### 5.2 Goal detail

- Current progress and a pace line: "At this pace: 12.4M by the end of Mehr".
- Current and best streak (recurring goals).
- History of closed periods: met, exceeded or missed.
- Period names in the **goal's** calendar.
- Actions: edit, pause/resume, delete with an undo snackbar.

### 5.3 Editor (screen contract §7.2)

Kind first:

| Kind | metric | direction | default period |
|---|---|---|---|
| Spending cap | `moneySum` | `atMost` | month |
| Habit limit | `trackerCount` / `trackerSum` | `atMost` | day |
| Habit goal | `trackerCount` / `trackerSum` | `atLeast` | week |
| Savings target | `netSavings` | `atLeast` | fixed range |

Tracker metric follows the tracker's type — counter and boolean →
`trackerCount`, quantity and duration → `trackerSum` — so there is no metric
picker. Editing an existing goal derives its kind from metric family and
direction.

Then one form:

- **Spending cap:** name; category subtree (or all expenses); optional tags
  (existing tag picker); amount (`AmountField`); period; calendar.
- **Habit limit / goal:** tracker; number (zero allowed for a limit); period.
- **Savings:** name; amount; start and end dates; calendar. Scope is all
  transactions.
- **Every kind:** an "Alerts" row of percent chips, default 80 and 100.
- **Live preview**, ~300 ms after the last change: the last three closed
  periods' outcomes and the current period's progress, via the same
  `measureDaily` + `foldDaily` as history.
- **Validation before save:** blank name, zero target on `atLeast`, end before
  start, missing tracker. Errors inline; save disabled until clear.

### 5.4 Every screen

RTL first, LTR derived; Persian and Latin digits; screen-reader labels
("Dining out, 82% of cap, at risk"); dynamic type; every string in both ARBs,
keys prefixed `goals…` in alphabetical position. The Phase 5 docs commit
updates screen-contract §7 (`missed`, `GoalProgress` naming).

---

## 6. Testing

### Domain (`nimbus_domain/test/goals/`)

- `Goal` rejects each invalid combination in §2; scope and alert-percent JSON
  round-trip; `fromJson` rejects unknown type, missing fields, a `dateRange`
  in filters.
- `assess`: both directions × not started / open / closed × below / at /
  over; zero target; negative net savings; mid-period creation; projection
  rounding.
- Periods and run-rate in **both calendars across a year boundary**
  (Esfand → Farvardin, December → January), and weeks starting Monday vs
  Saturday.
- `foldDaily`, `GoalStreaks`.
- `crossing`: first crossing; no re-fire on recomputation; drop then
  re-cross re-fires; a jump over two thresholds alerts once; falling below
  every threshold resets to null; money at 7 999/10 000 vs 8 000/10 000.
- **The brief's grep criterion as a test:** the evaluation files (`assess`,
  `crossing`, `goal_engine`, `goal_periods`) never mention a goal kind.

### Data (`nimbus_data/test/goals/`)

- Migration v32 → v40.
- Measurer, each metric against fixture rows: deleted rows excluded,
  unconfirmed included, net savings negative.
- Watermark moves on insert, edit out of scope, soft delete, category move,
  tag link change, tracker entry edit and delete.
- **Cache drop:** delete every `goal_period_results` row → history, streaks
  and progress identical.
- Stale recompute preserves `last_alerted_percent`; an edit re-baselines
  without an alert.
- Two concurrent `recordCrossing` calls for one crossing emit one alert.

### App (`app/test/features/goals/`)

- Goals tab: four states, RTL and LTR, Persian digits, semantics labels,
  paused section, deleted-tracker card, unreadable-row card.
- Editor: kind tiles set defaults; validation; zero target accepted for a
  limit; preview.
- Detail: history, streaks, pause, delete with undo.
- Alert listener: queued behind an existing snackbar; View navigates.
- Watcher: start-up evaluation; debounce.

Full app suite at `--concurrency=4`.

### Device check (Galaxy A53) at the gate

Create one goal of each kind; cross 80% and 100% on a cap with real
expenses; confirm one snackbar per crossing and none on recomputation; delete
the crossing expense and re-cross; switch the app calendar and confirm a goal
keeps its own; Persian and English.

---

## 7. Commit order (detailed in the plan)

1. **Schema lock, alone, on `main`:** both tables, v40 migration, snapshot,
   migration test, registry and ownership rows, D21 update.
2. Branch `phase/5-goals` from it.
3. Domain value types and validation.
4. `GoalPeriods`, `assess` for `atMost`, then `atLeast` through the same
   function.
5. Projection and fixed-range run-rate.
6. `foldDaily`, streaks, `crossing`.
7. `EngineGoalMeasurer`: money metrics, tracker metrics, net savings.
8. Watermark verification, then `GoalsDao`, `GoalPeriodResultsDao`,
   `GoalHistory` with the cache-drop test.
9. `GoalWatcher` and the `GoalAlert` stream.
10. Goals tab and shell destination.
11. Editor.
12. Detail, history and streaks.
13. Alert listener.
14. Docs: screen contract, README status board, gate record.

Each commit: failing test first, `pre-<slug>` tag, minimal code, green, full
suite.

---

## Out of scope

- `rolling_n_days` periods.
- `txnCount`, payment-method and necessity/satisfaction scope in the editor
  (storage and engine support them).
- Goals over several trackers.
- Goal reordering.
- Shared or social goals; goal templates (the brief's Out).
- Notification delivery and background evaluation scheduling (Phase 6).
