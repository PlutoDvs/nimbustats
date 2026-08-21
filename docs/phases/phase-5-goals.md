# Phase 5 — Goals & Limits

## Kickoff prompt

```
Read docs/phases/CONVENTIONS.md and docs/phases/phase-5-goals.md, then
execute Phase 5. Do not read the other phase briefs or plans.
```

**Goal:** one engine that covers all four goal types, because a dining-out
budget and a five-cigarettes-a-day limit differ only by field values.

**Ships:** the user sets a monthly spending cap, a daily smoking limit, a weekly
gym minimum, and a savings target — and gets warned at 80% while there is still
time to act.

**Schema versions:** v40–v49 reserved. Expect to use **v40**.
**Branch:** `phase/5-goals` · **Gate tag:** `phase-5-complete`

---

## Prerequisites — verify, do not assume

```bash
git tag --list 'phase-*-complete'   # must include phase-3-complete and phase-4-complete
dart analyze --fatal-infos
```

Phase 5 has the hardest prerequisites in the project: it needs money metrics
from Phase 3 *and* tracker metrics from Phase 4b. Starting before both have
landed means inventing their interfaces, then rewriting against the real ones.

---

## Required reading

- Spec: "3. Goal engine", and the `goals` and `goal_period_results` table
  definitions
- `QuerySpec`, `AnalyticsEngine`, `AnalyticsResult`, `PeriodBoundaries` from
  Phase 3
- Tracker metric interface from Phase 4b
- `packages/nimbus_domain/lib/src/calendar/` — `PeriodType`, `AppCalendar`

---

## Owns

```
packages/nimbus_domain/lib/src/goals/**          goal types, evaluation, projection
packages/nimbus_data/lib/src/tables/goals_table.dart
packages/nimbus_data/lib/src/tables/goal_period_results_table.dart
app/lib/features/goals/**
```

**Must not touch:** `analytics/`, `trackers/`, `capture/`. Phase 5 *uses* the
analytics engine; it does not extend it. If a goal needs a metric the engine
cannot express, that is a Phase 3 gap — raise it, do not work around it.

---

## Scope

**In:**

- One `goals` table covering all four types, distinguished only by field values:
  - **spending cap** — `money_sum`, `at_most`, monthly
  - **habit limit** — `tracker_count`, `at_most`, daily
  - **habit goal** — `tracker_count`, `at_least`, weekly
  - **savings target** — `net_savings`, `at_least`, `fixed_range`
- `evaluate(goal, period) → GoalProgress` — pure and unit-testable.
- Goal editor: metric, scope, direction, target, period, calendar, thresholds.
- Progress UI: current vs target, pace, projection, streaks and history.
- Threshold alerts at 80% and 100% by default, **fired on crossing**.
- `goal_period_results` as a cache for streaks and history.

**Out:** shared or social goals, goal templates, notification delivery
scheduling (Phase 6 owns the notification channel; Phase 5 owns deciding *that*
an alert should fire).

---

## Data model delta (schema v40)

Take the schema lock per `CONVENTIONS.md` §2.

- `goals` — `metric` (money_sum | txn_count | tracker_sum | tracker_count |
  net_savings), `scope` (JSON — a serialized `QuerySpec` for money metrics, or a
  tracker id), `direction` (at_most | at_least), `target_value`,
  `period` (day|week|month|quarter|year|rolling_n_days|fixed_range),
  `calendar` (jalali|gregorian), `start_date`, `end_date?`,
  `alert_thresholds` (JSON, default `[0.8, 1.0]`), `active`.
- `goal_period_results` — cached per-period outcome, plus
  **`last_alerted_threshold REAL NULL`** and a **source watermark** (see traps).

---

## Interfaces produced (Phase 6 consumes these)

- `GoalProgress` — `{ Money|double current, target, GoalStatus status, double
  fractionOfTarget, Projection projection }`.
- `GoalStatus` — `onTrack`, `atRisk`, `exceeded`, `met`, `notStarted`.
- `GoalEngine.evaluate(Goal goal, DateRange period) → Future<GoalProgress>`.
- `GoalAlert` — the event Phase 6 turns into a notification. Phase 5 decides an
  alert is due; Phase 6 delivers it.

---

## Known traps

- **`calendar` is required, not optional.** A period is meaningless without one
   — "this month" in Jalali and Gregorian are different ranges, and a goal that
  silently uses the app's current setting changes meaning when the user switches
  calendars.
- **Alerts fire on crossing, not on a schedule.** That requires remembering what
  has already fired: store `last_alerted_threshold` per period, and only fire
  for a threshold strictly above it. Without this, every recomputation re-fires
  the 80% warning and the user disables notifications within a day.
- **A crossing can go backwards.** Deleting or editing a transaction can drop
  progress below a threshold that already fired. Decide the rule and document
  it — recommended: reset `last_alerted_threshold` when progress falls below it,
  so a genuine re-crossing warns again.
- **`goal_period_results` is a cache and must be invalidated.** Store a
  watermark (the maximum `updated_at` of the source data in scope) and recompute
  when it moves. The cached value must always be re-derivable from source data;
  a test should delete the whole cache table and assert every number is
  unchanged.
- **Savings targets are not period progress.** `fixed_range` goals report a
  required run-rate ("you need 4.2M/month for the next five months"), not "68%
  of the way through the period".
- **Empty and partial periods.** A goal created mid-month, a period with zero
  transactions, and a period that has not started yet each need a defined
  status. `notStarted` exists for exactly this.
- **`at_most` goals invert the language.** 90% of a spending cap is *bad*; 90%
  of a gym goal is *good*. One shared status calculation with the direction as
  input, not two copies of the logic with the comparison flipped.
- **Money stays `int`; tracker values stay `double`.** `GoalProgress` is generic
  over the metric's numeric type, or carries both explicitly. Do not unify them
  by converting money to `double`.
- **Reuse Phase 3's `PeriodBoundaries`.** Do not recompute period ranges here —
  a second implementation will drift from the first at year boundaries.

---

## Task outline

1. Goal value types and `GoalProgress` in `nimbus_domain`, pure.
2. `evaluate` for `money_sum` / `at_most`, against fixture data.
3. `at_least` direction, with the shared status calculation.
4. Tracker metrics (`tracker_count`, `tracker_sum`).
5. `net_savings` and `fixed_range` with run-rate projection.
6. Empty, partial, and not-yet-started period cases.
7. Schema v40 (take the lock), including `last_alerted_threshold` and the
   watermark.
8. `goal_period_results` caching, with the "delete the cache, numbers unchanged"
   test.
9. Threshold crossing detection, including the backwards case.
10. Goal editor UI.
11. Progress UI: current, pace, projection.
12. Streaks and history from the cache.
13. `GoalAlert` emission (delivery is Phase 6).

---

## Definition of done

`CONVENTIONS.md` §5, plus:

- [ ] All four goal types work through the **same** `evaluate` implementation —
      grep proves there is no per-type branch beyond field values.
- [ ] Threshold alerts tested for: first crossing, no re-fire on recomputation,
      and re-fire after a genuine drop and re-crossing.
- [ ] Cache invalidation tested by dropping the cache and asserting identical
      results.
- [ ] Goals evaluated correctly in both calendars, including across a year
      boundary.
- [ ] `git tag phase-5-complete`.

---

## Parallelism notes

Phase 5 can run alongside **4b** if the tracker metric interface is agreed
first, though landing 4b before starting is simpler. It should **not** run
alongside Phase 3 — it consumes Phase 3's engine, and a moving `QuerySpec`
underneath a goal engine is a bad trade.

Finishing Phase 5, together with Phases 1 and 4, unblocks **Phase 6**.
