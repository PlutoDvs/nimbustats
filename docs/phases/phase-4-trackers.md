# Phase 4 — Trackers

## Kickoff prompt

```
Read docs/phases/CONVENTIONS.md and docs/phases/phase-4-trackers.md, then
execute Phase 4 (state whether you are doing 4a, 4b, or both).
Do not read the other phase briefs or plans.
```

**Goal:** track the non-money things — cigarettes, water, gym, sleep — with the
same one-tap ease as an expense, and with per-increment timestamps so
time-of-day patterns come free.

**Ships:** the user taps once to log a cigarette or a glass of water, starts and
stops a timer that survives the app being killed, and sees when in the day their
habits actually happen.

**Schema versions:** v30–v39 reserved. 4a used **v30**; 4b uses **v31** (entry offsets) and **v32** (drops 4a's day index).
**Branch:** `phase/4-trackers` · **Gate tag:** `phase-4-complete`

---

## This phase splits in two

| | Depends on | Nature |
|---|---|---|
| **4a — Trackers CRUD + entry** | Phase 0, 1 | Tables, four tracker types, entry surfaces. No charts. |
| **4b — Tracker analytics** | Phase 3, 4a | History and pattern views built on the `QuerySpec` engine. |

The split exists so 4a can run in parallel with Phase 3. **Do not build
tracker-specific aggregation in 4a** — a second query engine beside Phase 3's is
exactly the duplication the design is structured to avoid. 4a ships numbers that
come straight from a DAO count; 4b replaces them with `QuerySpec` results.

---

## Prerequisites — verify, do not assume

```bash
git tag --list 'phase-*-complete'   # 4a needs phase-0-complete, phase-1-complete
                                    # 4b additionally needs phase-3-complete
dart analyze --fatal-infos
```

---

## Required reading

- Spec: the `trackers` and `tracker_entries` table definitions, and "Phase 4 —
  Trackers" in the build sequence
- `packages/nimbus_domain/lib/src/calendar/` — `DateKey`, `DateRange`
- `packages/nimbus_design/` — the tokens and shared widgets Phase 1 established
- **[4b]** `QuerySpec`, `AnalyticsEngine`, `AnalyticsResult` from Phase 3

---

## Owns

```
packages/nimbus_domain/lib/src/trackers/**       tracker types, entry value semantics
packages/nimbus_data/lib/src/tables/trackers_table.dart
packages/nimbus_data/lib/src/tables/tracker_entries_table.dart
packages/nimbus_data/lib/src/trackers/**         tracker DAOs (added in 4a: kept out of app_database.dart)
app/lib/features/trackers/**
```

**Must not touch:** `transactions/`, `analytics/`, `capture/`, `goals/`.

---

## Scope

**In:**

- All four tracker shapes:
  - **counter** — tap to increment (cigarettes, coffees)
  - **boolean** — done / not done for the day (gym, meditation)
  - **quantity + unit** — a number with a unit (2.5 litres, 30 pages)
  - **duration / timer** — start and stop, or enter a duration directly
- Tracker manager: create, rename, recolor, pick icon, choose type and unit,
  archive, reorder.
- Entry surfaces: a one-tap list on the tracker screen, plus quick increment
  from the tracker detail view.
- Editing and deleting individual entries, with undo.
- Per-tracker detail: today's total, a simple history list.
- **[4b]** History charts, streaks, time-of-day and day-of-week patterns, all
  built on `QuerySpec`.

**Out:** goals and limits on trackers (Phase 5 — the goal engine owns the
"five cigarettes a day" rule, not this phase), the home-screen widget
(Phase 6), reminders (Phase 6).

---

## Data model delta (schema v30)

Take the schema lock per `CONVENTIONS.md` §2.

- `trackers` — `name`, `icon_key`, `color`, `type`
  (counter|boolean|quantity|duration), `unit?`, `per_tap_value?`, `archived`,
  `sort_order`, `timer_started_at_utc?`.
- `tracker_entries` — `tracker_id`, `value REAL`, `occurred_at_utc`,
  `local_date_key`, `note?`, `once_per_day`.

Three columns were added in 4a's design (2026-10-04), each because a rule has
to hold at the data layer:

- `timer_started_at_utc` holds a running timer's start. It survives a killed
  process and holds one start per tracker by construction.
- `once_per_day` is copied from boolean trackers so a partial unique index can
  allow one live "done" per day. A partial index can only test its own table's
  columns.
- `per_tap_value` is what one tap logs on a quantity tracker.

4b adds one column (v31), because no hour-of-day pattern can be right without
it: `tz_offset_minutes`, the device's UTC offset when the entry was logged, as
transactions already store. It also adds the index every engine query uses,
`(tracker_id, local_date_key)`, and v32 drops 4a's `(local_date_key,
tracker_id)` once its only reader, the DAO's day total, is gone.

**Per-increment rows, not daily totals.** Five cigarettes on one day is five
rows with five timestamps. That is what makes time-of-day patterns free, and
collapsing to a daily total is a one-way loss.

---

## Interfaces produced (Phases 5 and 6 consume these)

- `TrackerType` enum — `counter`, `boolean`, `quantity`, `duration`.
- `TrackerRepository.logEntry(String trackerId, {double value, DateTime? at})` —
  the single write path, mirroring Phase 1's `TransactionRepository`. Phase 6's
  home widget writes through this and nothing else.
- `Tracker` and `TrackerEntry` value types.
- `RunningTimer` — the persisted state of an in-progress duration tracker.

---

## Known traps

- **`value` is `double` here, and that is deliberate** — 2.5 litres is real.
  This is the one exception to the project's integer rule. It does **not** open
  the door to `double` for money. Say so in a comment at the column definition,
  because a future reader will otherwise take it as precedent.
- **A running timer must survive the app being killed.** Persist the start
  timestamp when the timer starts; never hold it only in memory or in a
  provider. Computing elapsed time from a persisted start is correct across a
  process death, a reboot, and a timezone change.
- **Only one running timer per tracker.** Enforce it at the data layer, not in
  the UI, or a double-tap creates two.
- **Boolean trackers need uniqueness per day.** One entry with `value = 1.0`
  per `(tracker_id, local_date_key)`. Enforce with a partial unique index, or a
  fast double-tap logs "done" twice and every streak count is wrong.
- **Undo, not confirm** — same rule as Phase 1. Deleting an entry shows a
  snackbar.
- **Do not write a second aggregation engine in 4a.** Today's total from a DAO
  count is fine; anything with a date range, a group-by, or a chart waits for
  4b and goes through `QuerySpec`.
- **Timezone changes.** `local_date_key` is computed at write time from the
  device's local date. A user who flies across timezones gets entries assigned
  to the local day they were in — which is correct, and worth a test so nobody
  "fixes" it later.
- **Haptics on increment.** The spec calls for it explicitly, and for a
  one-tap counter it is the entire feedback mechanism.

---

## Task outline

**4a** — 1. schema v30 (take the lock) · 2. `TrackerType` and value semantics
in `nimbus_domain` · 3. `TrackerRepository` with DAO-level tests ·
4. tracker manager CRUD · 5. counter and boolean entry, with the per-day
uniqueness index tested · 6. quantity + unit entry · 7. duration timer with
persisted start, tested across a simulated process death · 8. entry
edit/delete with undo · 9. tracker detail with today's total and history list.

**4b** — 10. tracker metrics expressed as `QuerySpec` · 11. history chart ·
12. streaks · 13. time-of-day and day-of-week patterns.

---

## Definition of done

`CONVENTIONS.md` §5, plus:

- [x] All four tracker types implemented and tested:
      `tracker_entry_test.dart` (counter, boolean), `tracker_quantity_test.dart`,
      `tracker_timer_test.dart`, `tracker_repository_test.dart` and
      `tracker_entries_dao_test.dart`.
- [x] Timer state verified to survive a killed process.
      - Tests: `timer_persistence_test.dart` closes and reopens the database
        file; "a timer started before the app was killed is still running" is
        the widget test.
      - On the Galaxy A53 (2026-10-05): the Sleep timer started at 16:22:22,
        the app was force-stopped at 16:22:41 and relaunched at 16:24:56, and
        at 16:26:17 the tab read "Running · 0:03:55". Stopping it logged 249 s,
        stamped at the start and dated that day, and cleared the timer.
- [x] Partial unique index on boolean trackers proven by a test that logs twice:
      `migration_test.dart` ("an upgraded v21 database enforces one live done
      per day") and `tracker_entries_dao_test.dart` ("a second done on the same
      day is refused…", "a fast double-tap logs exactly one").
- [x] **[4b]** No aggregation SQL exists outside Phase 3's engine — grep proves
      it. `test/architecture_test.dart` ("tracker code aggregates only through
      the analytics engine") enforces it on every run; its one allowed line
      places a new tracker (`sortOrder.max()`).
- [x] Entry surfaces meet the one-tap budget from the spec's UX constraints.
      Every widget test logs with a single `tap`. On the A53, one tap on
      Cigarettes' +1 read "1 today" with the snackbar "Cigarettes · 1 today ·
      Undo", which sits clear of the bottom tile.
- [x] `git tag phase-4-complete` (after 4b). 4a is tagged `phase-4a-complete`.

**4a gate record (2026-10-05), against `CONVENTIONS.md` §5 on `9403009`.**
- `dart analyze --fatal-infos` is clean.
- Test suites, all green: architecture 4; `nimbus_domain` 296; `nimbus_data`
  209, including the migration tests; `nimbus_design` 36; `app` 453, run with
  `--no-pub` because pub.dev returns 403 on the current exit.
- **Aggregation stays a DAO count.** A grep over
  `nimbus_data/lib/src/trackers/` and `app/lib/features/trackers/` finds one
  aggregate: today's one-day `SUM … GROUP BY tracker_id`. The only other hit
  is `insertAll`'s `sortOrder.max()`, which places new trackers.
- **Migration on a real device.** The A53's v21 database (5,000 demo
  transactions, backed up first to
  `~/nimbustats-backups/pre-v30-20261005-1616-nimbustats.sqlite`) upgraded to
  v30 with every transaction and all four tracker indexes.
- **Strings** exist in both ARBs; `localization_test.dart` enforces it. The
  operator reviewed every Persian string, chose عادت for "tracker", and had
  the entry sheet's time label changed to «زمان ثبت».
- **RTL and Persian digits** are covered by the Persian tests in
  `trackers_screen_test.dart`, `tracker_quantity_test.dart`,
  `tracker_detail_screen_test.dart` and `tracker_format_test.dart`. The
  device check in Persian was waived by the operator, as in Phase 3.
- **States.** Loading, error, empty and populated are tested on the tab, the
  manager and the detail screen, including the history's states and a missing
  tracker.
- **Accessibility.**
  - Semantics labels are tested with `isSemantics`, and were read on the A53:
    "Add one to Cigarettes", "Mark Gym done", "Add 0.25 L to Water", "Start
    Sleep timer".
  - Tap targets are at least 48.
  - Dynamic type: the tab and the Persian empty state are tested at twice the
    font size.
  - Contrast comes from the `nimbus_design` tokens, with no contrast tool run.
- **Haptics.**
  - The A53 (Android 15) drops Flutter's light, medium, heavy and selection
    haptics as "vibration absent". Tracker taps now use
    `HapticFeedback.vibrate()`, which plays, at the operator's choice.
  - Android logs each tap as a finished touch haptic. At the phone's lowest
    touch-feedback strength (`VIB_FEEDBACK_MAGNITUDE=1`), the operator could
    not feel it; a full 300 ms vibration was felt. See D18, and D17 for
    Phase 1's haptics.
- **Not checked on the device:** drag-to-reorder in the manager, which adb
  cannot drive. It is covered by the widget tests, including a failed reorder.
- The schema registry records v30, and the status board is updated.

**4b gate record (2026-10-09), against `CONVENTIONS.md` §5 on `7d3097e`.**
- `dart analyze --fatal-infos` reports no issues.
- Test suites, all green at `7d3097e`: architecture 5; `nimbus_domain` 328;
  `nimbus_data` 246; `nimbus_design` 36; `app` 527.
  - The app suite runs with `--concurrency=4`. At the default concurrency this
    machine hits loopback "semaphore timeout" load errors, which are
    environmental (one capped run also hit one and was re-run).
  - The plan's expected 243 and 506 predate the Task 9 fix round (+2 app) and
    the final-review fix wave (+3 data, +19 app).
- **Device upgrade** (Galaxy A53 SM-A536E, `RZCT209E3QX`, profile build of
  `7d3097e`, display at 120 Hz).
  - Backup first, at
    `~/nimbustats-backups/pre-v32-20261009-1849-nimbustats.sqlite` (the phone
    had no -wal or -shm).
  - Before: `user_version` 30, 20 live entries, no offset column, and three
    indexes: `idx_tracker_entries_day`, `idx_tracker_entries_history`,
    `idx_tracker_entries_once_per_day`. The plan said four; that was a
    miscount, and the v30 snapshot has three.
  - Install: Success, and the app opened on Home with its data.
  - After, read from a copy of the device database: `user_version` 32, 20
    live entries, offsets `[(210, 23)]` (every row, soft-deleted ones
    included, stamped +3:30), and indexes `idx_tracker_entries_history`,
    `idx_tracker_entries_once_per_day`, `idx_tracker_entries_tracker_day`. The
    day index is gone.
- **Insights on the A53**, read off the semantics tree (English). The real data
  has entries on one day only (2026-10-05: Cigarettes 18, Water 1, Sleep one
  entry of 4 min, Gym none). No entries were added to the operator's log.
  - Cigarettes header: "0 today", "Best: 1 day", "Last entry: 4 days ago".
  - Month `1405/07`: "18 in all · 1.06 a day". The history summary's peak is
    1405/07/13, 18. Time of day reads "most around 16:00, 9" (the database has
    9 entries at 16h and 9 at 17h, and a tie names the earlier). Day of week
    reads "most on Mon, 18" (2026-10-05 is a Monday).
  - Week `1405/07/11 – 1405/07/17`: "2.57 a day". Earlier goes to
    `1405/07/04 – 1405/07/10`, "Nothing logged in this period", with Later
    enabled. Year `1405` has its peak in `1405/07`; Earlier goes to `1404`,
    empty. Later is disabled whenever the range holds today.
  - Sleep (a duration): the pattern's title is "Time of day · by start time".
    The value axis shows no odd minutes; for a 4-minute peak it shows only
    `0:00` (see D19).
  - **Not checkable on the device:** a boolean's axis (Gym has no entries) and
    the one-frame flash on a tab return. Their widget tests stand in:
    `tracker_insights_test.dart` ("a boolean counts days done, never half of
    one") and `trackers_screen_test.dart` ("once totals were shown, the
    skeleton never comes back").
- **Strings.** 27 new tracker keys across Tasks 8–10 and the fix wave exist in
  both ARBs, plus `trackerInsightsDoneCaption`'s plural form. Both ARBs are
  CRLF, sorted and literal, and `localization_test.dart` is green. The
  operator reviewed all 27 new or changed Persian values on 2026-10-09 and
  approved them without changes.
- **RTL and Persian digits.** The Persian tests that stand in are
  `tracker_insights_test.dart` ("Persian digits on the range"),
  `tracker_streak_lines_test.dart` ("Persian digits and words") and
  `tracker_detail_screen_test.dart` ("Persian digits in the header and the
  history"). The device check in Persian was waived by the operator, as in
  Phases 3 and 4a. The operator explicitly approved Decision 10 on 2026-10-09:
  charts run left to right in Persian, as Phase 3's do, and the range arrows
  mirror.
- **States.** Each chart section has loading, error, empty and populated tests
  in `tracker_insights_test.dart`: "the chart loads on its own", "a failed
  chart retries and hides the raw exception", "a range with nothing in it says
  so", "a failed pattern blanks only itself" and the populated chart and
  pattern tests. The never-logged state is "a tracker never logged shows one
  empty state"; the header's version is "a tracker never logged shows neither
  line" in `tracker_streak_lines_test.dart`.
- **Accessibility.**
  - Spoken summaries on all three charts: "the chart speaks its numbers" and
    "both patterns speak their peaks".
  - 48-point range controls: "the range controls are full-size tap targets".
  - Twice the font size: "at twice the font size Insights overflows nothing"
    and "at twice the font size the header overflows nothing".
- The schema registry holds `drift_schema_v30.json`, `v31` and `v32` in
  `packages/nimbus_data/drift_schemas/`.
- **Deferred from this gate:** D19 to D22 (chart edges, a calendar switch
  rebuilding the repository, test and guard gaps, and copy edge cases), found
  by the final review and the device check.

---

## Parallelism notes

**4a runs safely alongside Phase 3, 2B, and 7** — no shared files.

**4b runs alongside Phase 5** once Phase 3 has landed, though Phase 5 consumes
tracker metrics, so landing 4b first makes Phase 5 simpler. If they run
together, agree the metric interface up front and do not change it mid-flight.
