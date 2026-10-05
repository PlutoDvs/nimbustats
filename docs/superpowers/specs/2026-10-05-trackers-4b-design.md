# Phase 4b — Trackers: analytics on Phase 3's engine — design

**Status:** approved in conversation 2026-10-05; this document awaits the
operator's review before the implementation plan is written.
**Brief:** `docs/phases/phase-4-trackers.md` (4b: tasks 10–13).
**Prerequisites:** `phase-3-complete` and `phase-4a-complete` both exist.
**Schema:** v31 · **Gate:** `phase-4-complete`

## Context

4a shipped the tables, the four tracker types, the entry surfaces and a detail
screen whose only number is today's total, read from one DAO `SUM`. 4b adds a
history chart, streaks, and time-of-day and day-of-week patterns. **All of it
goes through Phase 3's `AnalyticsEngine`.** 4a's DAO aggregate goes away, so
the brief's last open criterion holds: no aggregation SQL outside the engine.

Phase 5 consumes what this phase produces. The spec's goal metrics include
`tracker_sum | tracker_count`, scoped by a tracker id, and a goal stores its
scope as JSON. So the tracker query defined here is a storage format, not just
an argument, and must not change shape after it lands.

### What the code showed before the design

1. **The engine only reads transactions.** `AnalyticsEngine.compile` emits
   `FROM transactions t`, and every `Bucket` carries `Money`, which is an int.
   Tracker values are `double`.
2. **Tracker entries have no timezone offset.** Transactions store
   `tz_offset_minutes` at write time, and the engine's hour-of-day bucket is
   `(occurred_at_utc + tz_offset_minutes*60000)/3600000 % 24`. Without the
   column there is no correct local hour for a tracker entry.
3. **Phase 3's chart widgets are `Money`-typed.** `HourOfDayChart` and
   `DayOfWeekChart` take an `AnalyticsResult` and a `MoneyFormatter`, so
   tracker charts need their own widgets.
4. **The v30 indexes make per-tracker queries walk the whole history.**
   Measured with `EXPLAIN QUERY PLAN` on SQLite 3.45.3 (Python's build, no
   `ANALYZE`), with v30's tracker indexes:
   - Every per-tracker query below picks `idx_tracker_entries_history` on
     `tracker_id`. With a date range, that reads the tracker's whole history
     to find the days asked for.
   - With `(tracker_id, local_date_key)`, these all become range seeks:
     today's totals for three trackers, one tracker's month by day, its whole
     history by day, and its month by hour.
   - Grouping by day then reads rows in index order, with no temporary
     B-tree.

### Decisions taken with the operator (2026-10-05)

| Question | Decision |
|---|---|
| What a streak counts | **Consecutive logged days, plus "days since last entry".** Every type gets a current and a longest streak; for boolean trackers a logged day is a "done". "Days since last entry" serves quit-habits such as cigarettes. Limits ("≤ 5 a day") stay in Phase 5. |
| Where an entry's local hour comes from | **A `tz_offset_minutes` column**, written at log time like transactions (schema v31) |
| Where analytics appear | **Tabs on the tracker detail screen:** `History` and `Insights`, with the header and the quick-log bar shared |
| Engine shape | **A `TrackerQuerySpec` beside `QuerySpec`**, compiled by the same `AnalyticsEngine` |
| Backfill of existing entries | The offset the device's zone had **at each entry's own instant** |
| Index | **Replace** `idx_tracker_entries_day` with `idx_tracker_entries_tracker_day` |

### Where this design departs from the brief

- **"Must not touch: `analytics/`".** Taken literally, 4b cannot be "built on
  `QuerySpec`": the engine has to learn a second table. This design reads the
  rule as `app/lib/features/analytics/`, Phase 3's screens, which 4b does not
  edit. It does edit three Phase 3 files:
  - `nimbus_domain/lib/src/analytics/analytics_result.dart`, which gains
    `TrackerKey`;
  - `nimbus_data/lib/src/analytics/analytics_engine.dart`, which gains the
    tracker methods;
  - `nimbus_data/lib/src/analytics/group_expressions.dart`, which takes a
    table alias.

  Each commit that does so says so in its message (`CONVENTIONS.md` §3).
- **"Expect to use v30".** 4b takes **v31**, within Phase 4's reserved
  v30–v39. The brief's schema line and the registry are updated in the v31
  commit.

## 1. Data model — schema v31

Lands **alone** first, per the schema lock (`CONVENTIONS.md` §2). The commit
contains:
- the table change and `schemaVersion` 30 → 31;
- the migration step;
- the snapshot `drift_schema_v31.json`, made with `drift_dev schema dump` and
  `schema generate`, as v21 and v30 were;
- the migration tests;
- the registry row, which becomes `v30, v31`.

### `tracker_entries.tz_offset_minutes`

`INTEGER NOT NULL DEFAULT 0`, declared like `transactions.tz_offset_minutes`.

- **Written at log time** from the device's UTC offset at the entry's
  instant. `TrackerClock` gains `offsetMinutesOf(DateTime utc)` beside
  `localDateOf`, and is equally injectable.
- **Every write path stamps it:** `logEntry`, a timer's stop, a typed-in
  duration, and `updateEntry`.
- **Edits follow the `local_date_key` rule.** When the time is unchanged, the
  offset is kept: editing a note after a flight must not move the entry's hour.
  When the time moves, it is a new write and takes the device's offset for the
  new instant.
- **A duration entry's offset is its start's**, because the entry is stamped
  at the start.

### Backfill

Each existing row gets the offset the device's zone had **at that row's own
instant**:
`DateTime.fromMillisecondsSinceEpoch(occurredAtUtc, isUtc: true).toLocal().timeZoneOffset`.
- In a zone with daylight saving, a winter entry gets winter time, which a
  single "today's offset" would get wrong.
- It is exact under Iran's fixed +3:30.

The function is a constructor parameter of `AppDatabase`. It defaults to the
system zone, so production behaviour is unchanged, and the migration test
pins it to known offsets. The step runs inside the migration's transaction: it
reads `id, occurred_at_utc` and writes one `UPDATE` per row.

### Indexes

| Index | Change | Serves |
|---|---|---|
| `idx_tracker_entries_tracker_day (tracker_id, local_date_key)` | **added** | Every engine query on tracker entries |
| `idx_tracker_entries_day (local_date_key, tracker_id)` | **dropped** | Its only reader is 4a's DAO `SUM`, which §3 deletes |
| `idx_tracker_entries_history` | unchanged | The detail screen's keyset pages |
| `idx_tracker_entries_once_per_day` | unchanged | The boolean rule; it is partial, so the planner cannot use it for these queries |

The migration creates the new index with `m.create(...)` and drops the old one
by name. A fresh install's `createAll` builds the same set.

## 2. Domain — `nimbus_domain/lib/src/trackers/`

### `TrackerQuerySpec`

```dart
TrackerQuerySpec({
  required List<String> trackerIds,   // non-empty; ArgumentError otherwise
  DateRange? dateRange,
  required TrackerGroupBy groupBy,
  required Aggregate aggregate,       // Phase 3's enum, reused
})
```

- **Value equality and a JSON round trip,** like `QuerySpec`.
- **Unknown values throw `FormatException`.** A dropped field would widen the
  query, which on a Phase 5 goal reports "under the limit" while the user is
  over it.
- **`withDateRange(range)`** copies the spec, so a stored spec can be undated,
  as saved views are.
- **An empty `trackerIds` is refused** rather than read as "all trackers".
  Summing litres and cigarettes answers no question.

### `TrackerGroupBy` (sealed)

| Case | JSON `kind` | Bucket key | Notes |
|---|---|---|---|
| `TrackerGroupByNone` | `none` | `TotalKey` | |
| `TrackerGroupByTracker` | `tracker` | `TrackerKey(trackerId)` | The tab's totals |
| `TrackerGroupByDay` | `day` | `PeriodKey(DateRange(d, d))` | Groups on `local_date_key` itself. Needs no date range and no calendar: a local day is the same day in Jalali and Gregorian. |
| `TrackerGroupByPeriod(PeriodType)` | `period` | `PeriodKey` | Week, month, quarter or year, on Phase 3's `PeriodBoundaries` ladder. Needs a bounded range. **Refuses `PeriodType.day`**, so there is one way to ask for days. |
| `TrackerGroupByHourOfDay` | `hourOfDay` | `HourOfDayKey` | |
| `TrackerGroupByDayOfWeek` | `dayOfWeek` | `DayOfWeekKey` (ISO) | |

The case is sealed and separate from Phase 3's `GroupBy`, so a tracker grouped
by category or merchant cannot be expressed at all. The same reason made
`GroupBy` sealed in the first place.

`TrackerKey` joins the `BucketKey` family in `analytics_result.dart`, because
Dart only allows a sealed class's subclasses in its own library. Phase 3's
screens match keys with `case` patterns, not exhaustive switches, so they need
no change. A grep at design time confirmed it.

### `TrackerResult`

```dart
TrackerBucket({required BucketKey key, required double value, required int count})
TrackerResult({required List<TrackerBucket> buckets, required double sum, required int count})
```

- **`value` is always the aggregate's answer:** a sum for `sum`, the entry
  count for `count`, and so on. Phase 3 kept a count's answer apart because
  `Money` cannot hold one. A `double` can.
- **`count` on a bucket is always its entry count.**
- **`sum` and `count` on the result** cover every matched entry. No tracker
  dimension overlaps, so they are added up from the same rows, without a
  second query.

### `TrackerStreaks`

```dart
TrackerStreaks.of(Iterable<DateKey> loggedDays, {required DateKey today})
  -> TrackerStreaks({required int current, required int longest, int? daysSinceLast})
```

- **A logged day** has at least one live entry. For a boolean tracker, that
  is a "done".
- **`current`** is the run of consecutive logged days ending today. If today
  has nothing yet, it is the run ending yesterday instead, so today never
  breaks a streak before it ends. With neither, it is 0.
- **`longest`** is the longest run anywhere, so it is always at least
  `current`.
- **`daysSinceLast`** is 0 when today is logged and null when the tracker has
  never been logged.
- **Days after `today` are ignored.** The entry sheet should not produce
  them, and a clock set back must not turn into a streak.
- It is pure and calendar-free; `DateKey.addDays` and `daysUntil` do the
  arithmetic.

Its input is one engine query: `TrackerQuerySpec([id], dateRange: null,
groupBy: day, aggregate: count)`. The keys of the buckets it returns are the
logged days.

## 3. Engine — `nimbus_data/lib/src/analytics/`

### `AnalyticsEngine` gains three members

- `CompiledQuery compileTracker(TrackerQuerySpec spec)`
- `Future<TrackerResult> runTracker(TrackerQuerySpec spec)`
- `Stream<void> trackerChanges()` fires on writes to `tracker_entries`. A spec
  names its trackers by id, so a write to `trackers` changes no answer.

One statement per spec:

```sql
SELECT <bucket>, COALESCE(SUM(te.value), 0) AS total, COUNT(*) AS n,
       MIN(te.value) AS low, MAX(te.value) AS high, AVG(te.value) AS mean
FROM tracker_entries te
WHERE te.deleted_at IS NULL
  AND te.tracker_id IN (?, …)
  [AND te.local_date_key BETWEEN ? AND ?]
GROUP BY bucket ORDER BY bucket
```

### Shared, not copied

- **Soft delete:** the filter is `AnalyticsPredicates.notDeleted('te')`.
- **Shared fragments:** `GroupExpressions` takes a table alias, defaulting to
  `t`, so every Phase 3 call is unchanged. The hour-of-day arithmetic, the
  `strftime('%w')` weekday and the `PeriodBoundaries` CASE ladder still exist
  once, for both tables.
- **New fragments:**
  - `day` is `te.local_date_key AS bucket`, with no calendar involved;
  - `tracker` is `te.tracker_id AS bucket`.

### Plan tests

Each query shape the app issues runs `EXPLAIN QUERY PLAN` on the **compiled
statement itself**, against the app's bundled SQLite, and asserts a seek on
`idx_tracker_entries_tracker_day`, never `SCAN`. The shapes:
- today's totals by tracker;
- a range by day;
- the whole history by day;
- a range by hour;
- a range by weekday;
- a year by month.

### 4a's aggregate goes away

- **The DAO:** `TrackerEntriesDao.watchDayTotals`, `dayTotals` and
  `dayTotalsQuery` are deleted, along with their plan test.
- **The tab:** today's totals become one spec: the live trackers' ids, today
  only, `tracker`, `sum`. It is read through a new `trackerResultProvider` in
  `app/lib/features/trackers/application/`.
  - The provider is a `FutureProvider.autoDispose.family` keyed by the whole
    spec, invalidated by `trackerChanges()`.
  - It mirrors Phase 3's `analyticsResultProvider` and reads
    `analyticsEngineProvider`, the app's one engine.
- **The snackbar:** `TrackerRepository` takes the engine in its constructor.
  Its `dayTotal(trackerId)`, which the tap snackbar reads, runs a `none`/`sum`
  spec for today.

### The grep the criterion runs

Scoped like 4a's gate grep: `packages/nimbus_data/lib/src/trackers/` and
`app/lib/features/trackers/`, excluding generated files, for
`SUM(`, `COUNT(`, `AVG(`, `MIN(`, `MAX(`, `GROUP BY`, `.sum()`, `.count()`,
`.avg()`.
- **Allowed hit after 4b:** `TrackersDao.insertAll`'s `sortOrder.max()`, the
  one hit, which places a new tracker at the end of the list when it is
  written.
- **What else it must find:** nothing.

### Concurrency

The Insights tab issues four independent queries: the history chart, the
hours, the weekdays, and the streak history. They are separate futures, and
drift runs them on its single connection. A thread pool or a concurrency cap
would add nothing here, so there is none.

## 4. Screens — `app/lib/features/trackers/`

### 4.1 Tracker detail (screen contract §6.2)

- **Header, shared by both tabs:**
  - today's total, unchanged;
  - `6 days in a row · best 14`; when `current` is 0 and `longest` is not,
    `Best: 14 days`;
  - `Last entry: today` / `yesterday` / `5 days ago`.

  The lines use ICU plurals and Persian digits in `fa`. Both are hidden for a
  tracker that has never been logged, because the History tab's empty state
  already says what to do.
- **Tabs:** `History` is today's paginated list, unchanged. `Insights` is
  §4.2.
- **Quick-log bar:** stays pinned in the bottom third under both tabs
  (screen contract §6.2's UX budget).

### 4.2 The Insights tab

- **Range control:** `Week | Month | Year`, with ‹ › to shift.
  - Periods come from the active calendar (`calendarProvider`) and the
    settings' first day of the week.
  - It opens on the current month, and › is disabled at the current period.
- **History chart:**
  - Week and month draw one bar per day from `TrackerGroupByDay` over the
    range. Days without entries are filled with zero in Dart.
  - Year draws one bar per month from `TrackerGroupByPeriod(month)`, so a
    Jalali year shows Jalali months.
  - A caption gives the range's total, and an average per day over the days
    of the range that have already begun. Future days don't dilute it.
- **Time of day:** 24 bars over the same range. For a duration tracker the
  caption says "by start time", because a session is stamped at its timer's
  start.
- **Day of week:** 7 bars in the user's week order, Saturday first by default.
- **What a bar measures:** the type's total, from `sum`. That is:
  - a count for a counter;
  - the amount in its unit for a quantity;
  - time for a duration, formatted as 4a's `tracker_format` does;
  - done days for a boolean.
- **Chart widget:** one `TrackerBarChart` on `fl_chart`. Values are `double`,
  labels come from `tracker_format`, numerals follow the locale, and the axes
  run RTL in `fa`. Bars take the tracker's own color.

### 4.3 States, accessibility, strings

- **States** (`CONVENTIONS.md` §5):
  - Each chart has its own loading skeleton, error-with-retry (which
    invalidates the provider), empty state ("Nothing logged this month") and
    populated state.
  - A tracker never logged shows one empty state on the Insights tab instead
    of three empty charts.
- **Accessibility:**
  - Each chart carries a spoken summary, for example "Water by day, Mehr:
    total 42 L, most on the 9th, 2.5 L". A screen reader cannot read bars.
  - The range segments and arrows are labelled, and tap targets are at least
    48.
  - The Insights tab and the header lines are tested at twice the font size.
- **Strings:** every new string is a `trackers…` key, inserted in alphabetical
  position in both `app_en.arb` and `app_fa.arb`, and enforced by
  `localization_test.dart`. The operator reviews the Persian, as in 4a.

## 5. Testing

| Layer | Tests |
|---|---|
| Migration | See the list below |
| Repository | Logging, a timer's stop, a typed-in duration and an edit that moves the time all stamp the clock's offset. An edit that keeps the time keeps the offset. Entries before and after a simulated flight carry different offsets and keep their own days. |
| Domain | `TrackerQuerySpec` JSON round trips for every `TrackerGroupBy`. Unknown kind, unknown aggregate and a half-open date range throw. Empty `trackerIds` and `period(day)` are refused. `TrackerStreaks` is a table of cases, listed below. |
| Engine | See the list below |
| Widgets | See the list below |

**Migration tests:**
- v1, v20, v21 and v30 upgrade to v31 and match a fresh install.
- The backfill gives each row the offset the injected function returns for
  that row's instant.
- The new index exists and the old one is gone.
- An upgraded database keeps every entry.

**`TrackerStreaks` cases:**
- never logged;
- today logged;
- today not yet, yesterday logged;
- a one-day gap;
- the longest run in the past;
- a single day;
- future-dated days ignored.

**Engine tests:**
- Each dimension under `sum`, `count`, `average`, `min` and `max`.
- Soft-deleted entries and other trackers are excluded.
- Hour of day uses **each entry's own offset**: two entries at the same UTC
  instant, logged at +3:30 and +4:30, land in different hours.
- `dayOfWeek` maps SQLite's Sunday 0 to ISO 7.
- A Jalali year groups into Jalali months.
- `trackerChanges` fires on an entry write.
- The plan tests in §3.

**Widget tests:**
- **Header:** the streak, best-only and never-logged lines, in `en` and in
  `fa` with Persian digits.
- **Tabs:** switching keeps the quick-log bar.
- **Insights:** its four states; range shifting, including a Jalali month's
  label; › disabled at the current period; "by start time" for a duration
  tracker; spoken summaries via `isSemantics`; twice the font size.
- **Regression:** 4a's tab and snackbar tests stay green with today's totals
  coming from the engine.

### Device check (Galaxy A53) at the gate

After confirming the phone is free and unlocked, since it is the operator's
daily phone:
1. Back up the database to `~/nimbustats-backups/`.
2. Install, which upgrades v30 → v31.
3. Confirm every entry survived and carries an offset.
4. Open Insights on the real trackers and shift Week, Month and Year.
5. Read the spoken summaries through uiautomator.

Issues found go into `DEFERRED.md` as numbered items. One is fixed mid-gate
only if it blocks the check itself.

## 6. Commit order (detailed in the plan)

Each commit: failing test first, `pre-<slug>` tag on its parent, fast-forward
into `main`.

1. `feat(schema): v31 -- entries carry their timezone offset` (the lock,
   alone). This also swaps the index and updates the registry and the brief's
   schema line.
2. `feat(trackers): entries record the offset they were logged at`
3. `refactor(analytics): group expressions take a table alias` (Phase 3 file;
   behaviour preserved)
4. `feat(trackers): TrackerQuerySpec, TrackerGroupBy and TrackerResult` (adds
   `TrackerKey` to a Phase 3 file)
5. `feat(analytics): the engine runs tracker queries` (Phase 3 file)
6. `refactor(trackers): today's totals come from the engine`, which deletes
   the DAO `SUM`
7. `feat(trackers): streaks, and how long since the last entry`
8. `feat(trackers): the Insights tab and its history chart`
9. `feat(trackers): time-of-day and day-of-week patterns`
10. `docs: Phase 4 is complete`, with the gate record, the status board and
    `phase-4-complete`

## Out of scope

- **Goals, limits and goal streaks** ("days under five cigarettes"): Phase 5.
- **Streaks or charts on the Trackers tab's tiles:** they keep showing today's
  total.
- **Comparing trackers with each other, or a trackers-wide analytics screen.**
- **Saved views or dashboard cards for trackers:** `saved_views` stores a
  `QuerySpec`, not a `TrackerQuerySpec`.
- **The home-screen widget and reminders:** Phase 6.
- **D16** (frame drops on month change at 120 Hz) is Phase 3's. If shifting
  ranges on the Insights tab drops frames at the device check, that becomes a
  new deferred item rather than a fix inside 4b.
