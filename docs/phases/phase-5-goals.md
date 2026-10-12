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

- [x] All four goal types work through the **same** `evaluate` implementation —
      grep proves there is no per-type branch beyond field values.
      `test/architecture_test.dart` ("goal code below the app never names a
      goal kind") runs the grep on every gate: no file under `nimbus_domain`
      or `nimbus_data` can name a goal kind, which lives only in the app
      (plan Decision 6).
- [x] Threshold alerts tested for: first crossing, no re-fire on recomputation,
      and re-fire after a genuine drop and re-crossing.
      - Domain, `goal_alert_test.dart`: "the first crossing alerts once, at the
        percent reached", "recomputing at the same level never re-fires", "a
        drop below a threshold, then a genuine re-crossing, warns again", "a
        jump over two thresholds alerts once, at the highest" and "falling
        below every threshold resets to null, without an alert".
      - Data, `goal_service_test.dart` group "alert state": "saving records
        what the goal already reaches, without an alert", "an edit drops the
        cache and re-baselines without an alert", "resuming re-baselines",
        "restoring a deleted goal re-baselines", "a stale recompute keeps the
        alert its period already gave". Concurrency:
        `goal_period_results_dao_test.dart` ("two evaluations of one crossing
        at once alert once") and the group "history racing an edit".
      - App, `goal_watcher_test.dart`: "a crossing made while the app was
        closed alerts once, at start" and "a calendar switch keeps each goal's
        own calendar and re-fires nothing".
      - On the Galaxy A53, end to end (see the gate record).
- [x] Cache invalidation tested by dropping the cache and asserting identical
      results: `goal_cache_drop_test.dart` ("a money goal", "a tracker goal")
      drops every `goal_period_results` row and gets the same history,
      streaks and progress back.
- [x] Goals evaluated correctly in both calendars, including across a year
      boundary.
      - `goal_periods_test.dart`: "a Jalali month turns over at Nowruz", "a
        Gregorian month turns over at New Year", "the goal's own calendar
        decides its month", "Jalali months close in order across Nowruz",
        "Gregorian months close in order across New Year".
      - `goal_assess_test.dart`: "months left count the current one, across
        New Year", "months left are counted in the goal's calendar".
      - `goal_service_test.dart` group "periods are the goal's, not the
        engine's": "across the Gregorian new year", "across Nowruz in a
        Jalali goal".
- [x] `git tag phase-5-complete`.

**Gate record (2026-10-12), against `CONVENTIONS.md` §5 on `1de9f89`.**
- `dart analyze --fatal-infos` reports no issues.
- Test suites, all green at `1de9f89`: architecture 6; `nimbus_domain` 417;
  `nimbus_data` 326, including the migration tests; `nimbus_design` 36; `app`
  609, run with `--no-pub --concurrency=4`. The plan expected 588 for the app;
  the fix rounds of Tasks 13 and 14 and the final-review fix wave added 12,
  and the fixes for the gaps this gate found (`4f9a05d`..`1de9f89`, reviewed
  and approved) added 9.
- **Device upgrade** (Galaxy A53 SM-A536E, `RZCT209E3QX`, profile build of
  `53a09a9`, display at 120 Hz).
  - Backup first, at
    `~/nimbustats-backups/pre-v40-20261012-1418-nimbustats.sqlite` (the app
    was closed cleanly; the phone had no -wal or -shm).
  - Before: `user_version` 32, 5,000 live transactions, no goal tables.
  - Install: Success; the app opened on Home with its data, and the nav bar
    reads "Home, Trackers, Goals, Analytics, Settings", Goals third of five.
  - After, read from a copy of the device database: `user_version` 40, 5,000
    live transactions, tables `goal_period_results` and `goals`, no goals.
- **Device scenarios** (English), read off the semantics tree and, for the
  order of snackbars, from screenshots about every 0.5 s. Test data went into a
  new "Goal test" category, as the operator chose.
  - One goal of each kind, created by tapping. The cards read "Goal test, 0 of
    100K, On track"; "Cigarettes, 0 of 5, On track"; "Gym, 0 of 3, At risk"
    (day 3 of a Saturday week); "Savings target, 0 of 10M, On track". The
    savings card shows "1.7M/month for 6 more months" and no bar.
  - An 85,000 expense: one snackbar "Goal test: 85% of this month's limit",
    about 4 s after the tap, behind the save's own.
  - Another 20,000: "Saved" from 1.2 s to 4.3 s, then one "Goal test: over
    this month's limit" with View from 5.3 s, and nothing after.
  - No re-fire: a force-stop and relaunch, then an edit of another
    transaction's note and its revert, raised no snackbar. The card read
    "Goal test, 105K of 100K, Over the limit"; the alert state of the
    current period (from 2026-09-23) was 100.
  - Drop and re-cross: deleting the 20,000 expense ("Deleted", Undo not
    taken) raised nothing, the card read "Goal test, 85K of 100K, At risk",
    and the state was 80. Re-adding 20,000 gave "Saved", then one "over this
    month's limit". The state went 100 → 80 → 100.
  - A calendar switch to Gregorian raised no snackbar. The cap's detail kept
    its own calendar ("At this pace: 157,500 by 1405/07/30") while Home's
    dates turned to `2026/10/12`. Switched back to Jalali.
  - **Not checkable on the device:** history period names (a goal made today
    has no finished period; the detail read "No finished periods yet"), and a
    long daily cap's detail open: the editor gives caps and limits no start
    date, so one cannot be made through the app. Measured instead on this PC
    against a copy of the A53's database: a daily cap over all expenses from
    2024-10-05 (737 closed days) built its history in 161 ms the first time,
    read it from the cache in 3–14 ms, and rebuilt it after a transaction
    write in 4–8 ms. The money watermark took 268 µs on the same data (the
    bar is 5 ms; 3.65 ms on 50,000 seeded rows at Task 8).
  - Cleanup: the four goals, both expenses and the category were deleted with
    the app's undoable deletes. Final copy: 5,000 live transactions, no live
    goals, and the edited note back to empty.
  - One dump after the 85,000 save did not list "Saved". A re-check with a
    1,000 expense (deleted afterwards) found `content-desc="Saved"` in a dump
    that finished 3.0 s after the tap, so the snackbar reaches accessibility;
    the miss was the dump's timing. TalkBack itself was not turned on.
- **Strings.** 77 new keys in both ARBs: Task 11 24 (with `navGoals`), Task 12
  40, Task 13 7, Task 14 6 (its planned 5 plus the "reached" alert of the
  pre-flight ruling on at-most wording). No Persian value repeats its English.
  Both ARBs are CRLF and sorted case-insensitively, and
  `localization_test.dart` is green. The operator reviewed all 77 Persian
  values on 2026-10-12 and approved them without changes. The gap fixes added
  a 78th key, `goalsCardSavingsSemantics`, whose Persian is the approved card
  sentence with one more slot (`{name}، {progress}، {status}، {runRate}`).
- **RTL and Persian digits.** The Persian tests that stand in are
  `goals_screen_test.dart` ("Persian: right to left, Persian digits and
  words"), `goal_editor_screen_test.dart` ("Persian: right to left, Persian
  digits on the chips"), `goal_detail_screen_test.dart` ("Persian: right to
  left, Persian digits, and still the goal's own calendar") and
  `goal_format_test.dart` ("an alert in Persian"). The device check in Persian
  was waived by the operator, as in Phases 3 and 4.
- **States.**
  - Tab, `goals_screen_test.dart`: "goals show a skeleton while they load",
    "with no goals the tab says what a goal is and offers one", "a failed read
    says so, retries, and hides the raw error", "a goal whose numbers fail
    says so on its own card", and the populated tests for each kind and for
    paused goals.
  - Detail, `goal_detail_screen_test.dart`: "a skeleton while the goals
    load", "a goal with no finished period says so", "a goal that is gone
    says so and offers the way back", "a failed read offers a retry and hides
    the raw error", "a failed history says so in its place; the rest
    stands", "a failed progress load says so, and Retry runs it again", and
    "this period: the amounts in full, the status in words, the bar and the
    pace".
  - Editor, `goal_editor_screen_test.dart`: "a failed save says so, keeps the
    form and the error reaches the zone", "editing a goal opens its own form,
    and saving keeps the goal", "the preview shows the last three periods'
    outcomes and this period's progress". Opening an existing goal: "the
    goals list loading shows the skeleton", "a failed goals read says so,
    hides the raw error, and Retry reads again and shows the form", "the
    goal's tracker loading shows the skeleton" and "a failed tracker read
    says so, hides the raw error, and Retry reads again and shows the form".
- **Accessibility.**
  - The card's single spoken sentence: "a card reads as one sentence: name,
    progress, status" (`goals_screen_test.dart`), read on the A53 as above.
    The A53 showed the savings card's sentence leaving out its run-rate; it
    now ends with it: "a savings card reads as one sentence ending in its
    run-rate".
  - The bar's spoken name and percent: "the bar speaks its goal's name and its
    percent" (`goal_detail_screen_test.dart`).
  - Status as a word and an icon: "a spending cap shows its status in words
    and an icon, and a bar".
  - Tap targets: every clickable node in the A53's dumps of the tab, the four
    editor forms and the detail is at least 48 dp. Pinned with Flutter's
    `androidTapTargetGuideline`: "every tap target is at least 48 dp, problem
    cards included" (tab), "the kind tiles and every kind form meet the 48 dp
    tap target" (editor), "the detail and its problem card meet the 48 dp tap
    target" (detail).
  - "Saved" after adding an expense is a live region once the screen has
    closed: `add_transaction_screen_test.dart` ("\"Saved\" is announced once
    the screen has closed"), since goal alerts queue behind it.
  - Twice the font size: "at twice the font size the tab overflows nothing",
    "at twice the font size no form overflows", "at twice the font size
    nothing overflows" (detail).
- **Review Focus.**
  1. A moved category: `engine_goal_measurer_test.dart` group "stored paths
     follow their nodes (Review Focus 1)".
  2. A calendar switch with the app open: "a calendar switch keeps each
     goal's own calendar and re-fires nothing" (`goal_watcher_test.dart`),
     and on the A53.
  3. Midnight with the app open: "the first crossing on a new day alerts
     again" (`goal_watcher_test.dart`) and "the goals' day moves at midnight
     and on resume" (`goal_alert_listener_test.dart`).
  4. A crossing from a pushed screen: "a crossing from the add-expense screen
     alerts once, after its own 'Saved'" and "a crossing from a tracker's
     detail waits behind its Undo" (`goal_alert_listener_test.dart`), and on
     the A53.
  5. Archived against deleted tracker: "an archived tracker's goal reads
     normally; a deleted one's offers Edit and Delete"
     (`goals_screen_test.dart`) and "an archived tracker is still measured"
     (`engine_goal_measurer_test.dart`).
- The schema registry holds `drift_schema_v40.json` in
  `packages/nimbus_data/drift_schemas/`, and `CONVENTIONS.md` records v40.
- Plan Decisions 9 and 10 record two wording departures from the spec: the
  pace line names a date, and a card speaks amounts, not a percent.
- **Deferred from this gate:** D23 (a tag edit's watermark stamp, from Task
  8) and D25 (the task reviews' deferred findings). D24, the gaps this gate
  found, was fixed before the merge.

---

## Parallelism notes

Phase 5 can run alongside **4b** if the tracker metric interface is agreed
first, though landing 4b before starting is simpler. It should **not** run
alongside Phase 3 — it consumes Phase 3's engine, and a moving `QuerySpec`
underneath a goal engine is a bad trade.

Finishing Phase 5, together with Phases 1 and 4, unblocks **Phase 6**.
