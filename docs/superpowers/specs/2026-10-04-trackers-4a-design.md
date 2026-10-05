# Phase 4a — Trackers: CRUD and entry — design

**Status:** approved in conversation 2026-10-04; this document awaits the
operator's review before the implementation plan is written.
**Brief:** `docs/phases/phase-4-trackers.md` (4a only; 4b is out of scope here).
**Branch:** `phase/4-trackers` · **Schema:** v30 · **Gate:** `phase-4-complete`
(after 4b).

## Context

Phase 4 tracks the non-money things — cigarettes, water, gym, sleep — with the
same one-tap ease as an expense. 4a ships the tables, the four tracker types, the
tracker manager, the entry surfaces, entry edit/delete with undo, and a detail
screen with today's total and a history list. **No charts and no aggregation
beyond a DAO count**: 4b replaces today's totals with `QuerySpec` results, so no
second query engine grows here.

### Decisions taken with the operator (2026-10-04)

| Question | Decision |
|---|---|
| Where trackers live | A fourth bottom-nav destination: **Home · Trackers · Analytics · Settings** |
| One tap on a quantity tracker | Logs the tracker's **per-tap amount**, set on creation; long-press logs a different amount |
| Empty tracker list | **Four localized presets** (Water, Cigarettes, Gym, Sleep) plus "Create your own" |
| A timer crossing midnight | Stamped at its **start**; counts for the day it started |
| Where a running timer lives | A nullable `timer_started_at_utc` column on the tracker (see §1) |

## 1. Data model — schema v30

Lands **alone** first, per the schema lock (`CONVENTIONS.md` §2): table files,
`schemaVersion` 21 → 30, the migration step, the snapshot
(`drift_dev schema dump` + `schema generate`, as `546343b` did for v21), a
migration test, and the registry row.

### `trackers`

| Column | Type | Notes |
|---|---|---|
| `id`, `created_at`, `updated_at`, `deleted_at` | per CONVENTIONS §1 | UUIDv7; soft delete |
| `name` | TEXT | |
| `icon_key` | TEXT | a `nimbusIcons` key |
| `color` | INTEGER | ARGB, as categories and payment methods |
| `type` | TEXT enum | `counter` \| `boolean` \| `quantity` \| `duration` — **fixed at creation** |
| `unit` | TEXT NULL | free text, quantity only (`L`, `pages`, `لیتر`) |
| `per_tap_value` | REAL NULL | **added to the spec's columns:** the amount one tap logs; quantity only, required for it |
| `archived` | BOOLEAN | default false |
| `sort_order` | INTEGER | user order |
| `timer_started_at_utc` | INTEGER NULL | **added:** epoch ms of the running timer's start; duration only |

### `tracker_entries`

| Column | Type | Notes |
|---|---|---|
| `id`, `created_at`, `updated_at`, `deleted_at` | per CONVENTIONS §1 | |
| `tracker_id` | TEXT FK → trackers | |
| `value` | REAL | **the one deliberate `double` in the project** — a comment at the column says so and that it is no precedent for money (brief trap) |
| `occurred_at_utc` | INTEGER | epoch ms |
| `local_date_key` | INTEGER | `yyyymmdd`, local, computed at write time |
| `note` | TEXT NULL | |
| `once_per_day` | BOOLEAN | **added:** set by the repository for boolean trackers |

### Indexes

- `idx_tracker_entries_day` on `(local_date_key, tracker_id)` — today's totals
  and the day's entries. Date first, because today's totals read every
  tracker for one day (changed in the implementation plan).
- `idx_tracker_entries_history` on `(tracker_id, occurred_at_utc DESC, id DESC)`
  — the detail screen's cursor pagination.
- `idx_tracker_entries_once_per_day` — **UNIQUE** `(tracker_id, local_date_key)`
  `WHERE once_per_day = 1 AND deleted_at IS NULL`. This is the brief's partial
  unique index: a fast double-tap cannot log "done" twice.
- `idx_trackers_live` on `(archived, sort_order)` `WHERE deleted_at IS NULL`.

### Why the three added columns

- **`timer_started_at_utc`.** A running timer must survive process death, so its
  start is persisted the moment it starts. A column holds *one* per tracker by
  construction — the brief's "only one running timer per tracker, enforced at
  the data layer" — and start is a conditional update
  (`WHERE timer_started_at_utc IS NULL`), so a double-tap cannot start two.
  Rejected: a `running_timers` table (the same guarantee plus a table carrying
  the four convention columns for one timestamp), and an "open" entry row with
  no value (every total and every 4b query would have to exclude open rows — a
  second `deleted_at`-style trap).
- **`once_per_day`.** SQLite partial indexes can only test the indexed table's own
  columns, and the type lives on `trackers`. The repository copies "this tracker
  is boolean" onto each entry; because the type is fixed at creation, the copy
  cannot drift.
- **`per_tap_value`.** One tap logs a quantity, per the operator's choice.

The spec's `trackers`/`tracker_entries` definitions and the brief's data model
delta are updated in the schema commit, with these reasons.

### Value semantics

| Type | One entry's `value` | Today's total | Shown as |
|---|---|---|---|
| counter | `1.0` | sum (= count) | `5` |
| boolean | `1.0`, at most one live per day | done if any | ✓ / — |
| quantity | the amount (`per_tap_value` or entered) | sum | `2.5 L` |
| duration | seconds | sum | `1:30` (h:mm), `0:12` |

## 2. Domain — `nimbus_domain/lib/src/trackers/`

Pure Dart, no Flutter:

- `TrackerType` enum (the interface Phase 5 and 6 consume).
- `Tracker`, `TrackerEntry` value types with value equality.
- `RunningTimer` — `startedAtUtc`; `elapsed(DateTime nowUtc)`. Elapsed is
  always `now − start` in UTC, which is correct across process death, reboot and
  a timezone change. Never held only in memory.
- Value semantics per type: what one tap logs, how a day's entries total, and
  whether a value is valid (positive; quantity and duration finite; boolean and
  counter exactly 1).

Formatting with digits and units is the app's job (it needs the locale); the
domain returns the number or `Duration`.

## 3. Data access — DAO and `TrackerRepository`

`TrackersDao` / `TrackerEntriesDao` in `nimbus_data` (every read filters
`deletedAt.isNull()`), and `TrackerRepository` in
`app/lib/features/trackers/data/`, which mirrors Phase 1's `TransactionRepository`
as **the only write path** (Phase 6's widget writes through it and nothing else).

- `logEntry(String trackerId, {double? value, DateTime? at, String? note})`
  — `value` defaults from the type (1.0, or `per_tap_value`); sets
  `once_per_day` for boolean trackers; computes `local_date_key` from the local
  date at write time. Returns a result, not an exception, for the expected
  outcomes: `Logged(entry)` or `AlreadyDoneToday` (the unique index caught it).
- `startTimer(trackerId)` → `Started(RunningTimer)` | `AlreadyRunning`;
  `stopTimer(trackerId)` → `Stopped(entry)` | `NotRunning`. Stop writes the
  entry (stamped at the start, value = elapsed seconds) and clears the column in
  **one transaction**.
- `addDuration(trackerId, Duration, {DateTime? startedAt})` — manual entry for
  timer trackers; goes through the same insert.
- `updateEntry`, `deleteEntry` (soft) and `restoreEntry` (undo).
- Tracker CRUD: `create` (type fixed here), `updateAppearance` (name, icon,
  color), `updateUnit` / `updatePerTapValue` (quantity), `archive` /
  `unarchive`, `reorder`, `createPresets(l10n)`.
- Reads: `watchTrackers()` (live, unarchived, by `sort_order`),
  `watchArchived()`, `watchTodayTotals(DateKey today)` →
  `Map<String, double>` — one query,
  `SUM(value) … WHERE local_date_key = ? GROUP BY tracker_id`. That is a single
  day keyed by tracker, no range and no other dimension: the brief's "today's
  total from a DAO count". 4b replaces it with `QuerySpec`. Plus
  `entriesPage(trackerId, cursor)` with a cursor like `TransactionCursor`
  (`occurred_at_utc`, `id`).
- Write failures surface through a trackers-owned reporter mirroring
  `saved_view_write.dart`'s `reportingFailure` (analytics is off-limits to this
  phase).

**Today** is a provider that rolls over at local midnight and on resume, so a
screen left open overnight does not keep yesterday's totals.

**Timezones.** `local_date_key` is computed at write time from the device's
local date; an entry logged after flying across timezones belongs to the local
day the user was in. That is correct and gets a test so nobody "fixes" it.

## 4. Screens — `app/lib/features/trackers/`

Own `routes.dart` (the router composes it, per CONVENTIONS §3); own providers.
Keys and l10n strings are prefixed `tracker`.

### 4.1 Trackers tab — shell destination `/trackers` (screen contract §6.1)

- A list **anchored to the bottom** (`reverse: true`): the first trackers sit in
  thumb reach above the nav bar — the contract's bottom-third rule.
- Each tile: icon, name, today's total, and one large action:
  counter **+1** · boolean **✓** (tapping when done removes today's entry, with
  undo) · quantity **+per-tap amount** (long-press, or a TalkBack action, opens a
  small keypad for another amount) · duration **▶ / ■** with live elapsed time,
  ticking once a second only while that tile is on screen.
- Logging is optimistic: haptic (`lightImpact` on counter and quantity,
  `mediumImpact` on done and timer start/stop), no spinner, and a snackbar
  "Cigarettes · 5 today · Undo" that each tap replaces. Undo removes that entry —
  the contract's decrement.
- Tapping the tile body opens detail. The app bar opens the manager.
- **States.** Loading skeleton; error with retry; **empty** explains what a
  tracker is and offers the four presets — Water (quantity, 0.25 per tap, unit
  `L`/`لیتر`), Cigarettes (counter), Gym (boolean), Sleep (duration), named in
  the current language — plus "Create your own".

### 4.2 Tracker manager — pushed `/trackers/manage`

Phase 1's manager shape: the live list with drag-to-reorder, an "Archived"
section with unarchive, archive with undo, and an editor sheet with name, the
shared `IconPicker` and `ColorPicker`, the type (on create only), and for
quantity the unit and per-tap amount. `nimbusIcons` gains habit icons (water
drop, smoking, fitness, bedtime, meditation, book, running, timer) — a noted
touch of Phase 1's `nimbus_design`.

### 4.3 Tracker detail — pushed `/tracker/:id` (screen contract §6.2)

- Header with today's total; a paginated history of entries (time, value, note),
  newest first; the quick-log button pinned in the bottom third while the history
  scrolls.
- Edit an entry: time and note always; the value for quantity; the duration for
  timer entries (counter and boolean values are fixed at 1). Delete with undo.
- Timer trackers: start/stop here too, and "add duration" for a session the user
  forgot to time.
- Menu: edit tracker (the manager's sheet), archive with undo.

### 4.4 Shared rules

All four states on every screen; RTL and LTR with Persian and Latin digits
(values through `NumberFormat.decimalPattern(locale)`, durations through the
same digits — the gate check that `f84f14c` added applies); screen-reader labels
on every action ("Add one cigarette", "Mark gym done", "Start sleep timer");
dynamic type; no modal confirmations.

## 5. Testing

TDD per commit (failing test → observe → minimal code → pass → broader suite).

- **Data:** migration from v1, v20 and v21 to v30 against a fresh install;
  logging boolean twice keeps one row (the partial unique index); starting a
  timer twice keeps one start; a timer survives a simulated process death — close
  the database, reopen it, and elapsed comes from the stored start; stop writes
  the entry and clears the start atomically; today's totals per type; cursor
  pagination; soft delete and restore.
- **Domain:** value semantics and validation per type; `RunningTimer.elapsed`.
- **Repository:** the single write path; defaults per type; result outcomes;
  `local_date_key` at write time, including the timezone case.
- **Widgets:** each tile action per type, the snackbar undo, the presets, the
  manager, detail pagination and editing, all four states, Persian digits.
- **Device (A53, at the end):** kill the app with a timer running and reopen; the
  one-tap budget on the tab.

## 6. Commit order (detailed in the plan)

1. Schema v30 alone (the lock), with its docs updates.
2. Domain types and value semantics.
3. DAOs and `TrackerRepository` with DAO-level tests.
4. Trackers tab shell destination, empty state and presets.
5. Counter and boolean entry, with the per-day uniqueness tested.
6. Quantity entry with per-tap and custom amounts.
7. Duration timer with persisted start, tested across a simulated process death.
8. Tracker manager.
9. Entry edit/delete with undo, and tracker detail with history.

## Out of scope

4b (charts, streaks, time-of-day and day-of-week patterns on `QuerySpec`);
goals and limits on trackers (Phase 5); the home-screen widget and reminders
(Phase 6); deleting a tracker outright (archive covers it).
