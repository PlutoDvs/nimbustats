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

**Schema versions:** v30–v39 reserved. Expect to use **v30**.
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

- [ ] All four tracker types implemented and tested.
- [ ] Timer state verified to survive a killed process (test the persisted-start
      calculation; verify once on a real device).
- [ ] Partial unique index on boolean trackers proven by a test that logs twice.
- [ ] **[4b]** No aggregation SQL exists outside Phase 3's engine — grep proves
      it.
- [ ] Entry surfaces meet the one-tap budget from the spec's UX constraints.
- [ ] `git tag phase-4-complete`.

---

## Parallelism notes

**4a runs safely alongside Phase 3, 2B, and 7** — no shared files.

**4b runs alongside Phase 5** once Phase 3 has landed, though Phase 5 consumes
tracker metrics, so landing 4b first makes Phase 5 simpler. If they run
together, agree the metric interface up front and do not change it mid-flight.
