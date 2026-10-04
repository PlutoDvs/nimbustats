# Phase 3 — Analytics

## Kickoff prompt

```
Read docs/phases/CONVENTIONS.md and docs/phases/phase-3-analytics.md, then
execute Phase 3. Do not read the other phase briefs or plans.
```

**Goal:** one query engine that serves every chart, every saved view, and every
goal evaluation — so "within #travel, break down by category" and "how much
avoidable-and-regretted money did I spend this month" are the same code path
with different arguments.

**Ships:** the analysis the whole app exists for — drill-down, tag × category
cross-tab, trends and period comparison, behavioral patterns, the necessity ×
satisfaction matrix, and pinnable saved views on the dashboard.

**Schema versions:** v20–v29 reserved. Expect to use **v20** (`saved_views`).
**Branch:** `phase/3-analytics` · **Gate tag:** `phase-3-complete`

---

## Prerequisites — verify, do not assume

```bash
git tag --list 'phase-*-complete'   # must include phase-0-complete and phase-1-complete
dart analyze --fatal-infos
```

> **Amended 2026-08-29 — `phase-1-complete` is waived, for the engine only.**
> That tag is withheld on **D1** alone (Google Maven unreachable), and the four
> criteria it waits on are hardware *performance* measurements that cannot
> affect whether an analytics engine compiles and passes tests against Phase 1's
> DAOs — which are merged on `main` and green. The waiver covers **tasks 1–8**
> and nothing else; it does not waive Phase 3's own gate, which still needs
> `phase-1-complete` to exist. Rationale and limits: `DEFERRED.md` §D1.
>
> **Tasks 9–14 are separately blocked by D7** — `fl_chart` is in neither the
> lockfile nor the local pub cache, and D3 currently returns 403 from pub.dev
> for archives *and* metadata. Build the engine; the charts wait.

You need **real data** to design against. If Phase 1 has been in daily use,
work from that database (a copy). If not, seed a realistic one — a few thousand
transactions across a two-year span, an uneven category tree, and transactions
carrying two or three tags each. Analytics designed against ten rows makes
decisions that fall apart at ten thousand.

---

## Required reading

- Spec: "2. Analytics engine" (in full — including both correctness traps), and
  the `saved_views` and `transactions` table definitions
- `packages/nimbus_domain/lib/src/calendar/` — `DateKey`, `DateRange`,
  `AppCalendar`, `PeriodType`
- `packages/nimbus_data/lib/src/tree/materialized_path.dart` — subtree queries
- Phase 1's `PaginatedTransactionQuery` for the pagination idiom already in use

---

## Owns

```
packages/nimbus_domain/lib/src/analytics/**      QuerySpec, filters, GroupBy, Aggregate, result types
packages/nimbus_data/lib/src/analytics/**        QuerySpec → SQL compiler
packages/nimbus_data/lib/src/tables/saved_views_table.dart
app/lib/features/analytics/**
app/lib/features/dashboard/**
```

**Must not touch:** `capture/`, `trackers/`, `goals/`, `backup/`, or Phase 1's
add/edit flow.

---

## Scope

**In:**

- `QuerySpec` value object in `nimbus_domain` — pure, serializable, with no
  knowledge of SQL.
  - **Filters:** date range, direction, category subtree(s), tags with
    AND/OR/NOT over subtrees, payment method, necessity, satisfaction, amount
    range, confirmed-only, text search.
  - **Group by:** category at any depth, tag, day/week/month/quarter/year,
    payment method, merchant, necessity × satisfaction, hour-of-day,
    day-of-week.
  - **Aggregate:** sum, count, average, min, max.
- The compiler in `nimbus_data` that turns a `QuerySpec` into one SQL statement.
- Screens: breakdown with drill-down, trends over time, period comparison,
  tag × category cross-tab, hour/day-of-week patterns, the necessity ×
  satisfaction matrix.
- Saved views: name a `QuerySpec` + group-by + chart type + period, pin it to
  the dashboard, reorder.
- Dashboard assembled from pinned saved views.
- `QuerySpec` JSON round-trip — **Phase 5 stores a `QuerySpec` as a goal's
  scope**, so serialization is a hard requirement, not a convenience.

**Out:** tracker metrics (Phase 4b), goal evaluation (Phase 5), export of chart
data, forecasting beyond a simple run-rate.

---

## Interfaces produced (Phase 4b and Phase 5 consume these)

- `QuerySpec` — immutable, `fromJson` / `toJson`, value equality.
- `AnalyticsResult` — carries `List<Bucket> buckets` **and** `Money trueTotal`
  (see the first trap below).
- `AnalyticsEngine.run(QuerySpec spec) → Future<AnalyticsResult>`.
- `PeriodBoundaries.forPeriod(PeriodType, DateKey anchor, AppCalendar) →
  DateRange` — the one place a period becomes a key range.

---

## Known traps

The first two are correctness bugs that ship silently and make every number
wrong in a way users will not catch. Both get explicit tests.

- **Tag breakdowns double-count.** A transaction tagged `#travel` *and* `#food`
  lands in both buckets, so tag sums exceed the true total. The engine returns
  `trueTotal` alongside the buckets, and **the UI must say so** rather than
  render a pie chart that quietly lies. Write the test that asserts
  `sum(buckets) > trueTotal` for a known fixture — an assertion that they are
  equal is the bug.
- **Nested tag rollup must deduplicate.** A transaction tagged with both a
  parent and its child counts **once** when rolled up to the parent.
- **Period boundaries are computed in the active calendar, then converted.**
  Never `strftime` in SQL. A Jalali month is not a Gregorian month, and the
  bug only appears near year boundaries where nobody is looking.
- **Every query filters `deleted_at IS NULL`.** One shared helper, tested once,
  used everywhere. A single query that forgets it resurrects deleted rows in
  exactly one chart.
- **Assert the query plan, not just the result.** For the hot aggregations, run
  `EXPLAIN QUERY PLAN` in a test and assert an index is used. A correct query
  that degrades to a full scan at 50,000 rows is a bug that only appears once
  the app matters to the user.
- **Decide and document whether unconfirmed captures are included.** Default:
  yes, with a visible toggle. Whatever you choose, it must be the same
  everywhere — a dashboard that includes them and a goal that does not is
  indefensible.
- **Archived categories still appear in history.** Filter them from pickers,
  never from results.
- **Money stays `int` through the entire aggregation path**, including
  averages. Round explicitly and document the rule.
- **One engine, not two.** If a screen needs a bespoke query, that is a missing
  `QuerySpec` capability. Add it to the spec type rather than writing SQL beside
  the engine — the second query path is how this becomes unmaintainable.

---

## Task outline

1. `QuerySpec` and its filter/group/aggregate types, pure, with JSON round-trip
   tests.
2. `PeriodBoundaries` across both calendars, including year-boundary cases.
3. The SQL compiler: filters first, verified against hand-computed fixtures.
4. Group-by dimensions, one at a time, each with a fixture test.
5. **The tag double-count test and `trueTotal`** — before any tag UI exists.
6. Nested tag rollup with deduplication.
7. `EXPLAIN QUERY PLAN` assertions on the hot paths.
8. Schema v20: `saved_views` (take the schema lock).
9. Breakdown screen with drill-down.
10. Trends and period comparison.
11. Cross-tab (tag × category) with the double-count disclosure in the UI.
12. Patterns (hour-of-day, day-of-week) and the necessity × satisfaction matrix.
13. Saved views: create, pin, reorder.
14. Dashboard composed of pinned views.
15. Performance pass on the seeded database.

---

## Definition of done

`CONVENTIONS.md` §5, plus:

- [ ] Every aggregation verified against a hand-computed fixture, not against
      another query.
- [ ] The tag double-count test exists and asserts the *inequality*.
- [ ] Nested-tag rollup deduplication test exists.
- [ ] `EXPLAIN QUERY PLAN` assertions cover the dashboard's queries.
- [ ] `QuerySpec` JSON round-trip is lossless (Phase 5 depends on this).
- [ ] Charts render correctly in RTL with Persian numerals on the axes.
- [ ] Every tag-based chart carries the "does not sum to 100%" disclosure.
- [ ] `git tag phase-3-complete`.

---

## Performance pass (task 15) — measured 2026-10-04

**Result: every measured pass meets the bar; no fix was needed.**

**The bar** (agreed with the operator 2026-10-04). Each measured pass needs:
- p99 build, p99 raster and p99 frame-start delay (`vsyncOverhead`) all
  ≤ 16.67 ms;
- every analytics query ≤ 100 ms, timed from asking to the answer, so time
  spent waiting behind other queries counts.

**Setup.**
- **Device:** Samsung Galaxy A53 5G (SM-A536E) running a profile build of
  `4ed0bd4`. The tool ran at `1944d3d`, which changed only the tool.
- **Refresh rate: 120 Hz, not the 60 Hz of Phase 1's run.** The display was
  in adaptive mode.
  - Read after the run: `mActiveRenderFrameRate=120`,
    `refresh_rate_mode=2`.
  - The frame counts agree: about 71 frames per month tap, with taps about a
    second apart, only fits 120 fps.
  - The bar stays the agreed 16.67 ms. See D16 for what 120 Hz means.
- **Settings:** UI in English, so the tool's default button labels match;
  currency IRT; Jalali calendar.
- **Data:** the demo seeder (`3f464ac`) wrote 5,000 rows after a reset:
  - dated 2024-10-05 to 2026-10-04;
  - 2 or 3 tags on every row;
  - 25 categories in use, from 1,311 rows down to 49;
  - 8.6 % income, 4.8 % unconfirmed, 72 % of expenses rated, 81 % with a
    payment method.
- **Dashboard:** 8 cards. The two starters, plus one pin from every tab:
  Breakdown, Trends, Tags × categories, and Patterns' hour, weekday and
  reflection charts.
- **Method:** `app/tool/frame_timings.dart`, one warm-up pass and then three
  measured passes per scenario (`docs/DEVELOPMENT.md`, *Measuring on a
  device*).

| Scenario | Inputs per pass | Worst p99 build | Worst p99 raster | Worst p99 start delay | Queries per pass | Worst query |
|---|---|---|---|---|---|---|
| Dashboard scroll | 10 + 10 swipes | 3.69 ms | 10.34 ms | 1.67 ms | 6 | 5.79 ms |
| Dashboard month steps | 10 back + 10 forward | 12.98 ms | 6.02 ms | 1.51 ms | 100 | 25.92 ms |
| Swipe across the 5 tabs | 4 forward + 4 back | 8.51 ms | 10.09 ms | 1.67 ms | 11 | 14.82 ms |
| Breakdown month steps | 10 back + 10 forward | 14.37 ms | 9.79 ms | 1.91 ms | 20 | 11.20 ms |

- Each "worst" is the highest of the three measured passes.
- Each pass recorded between 776 and 1,487 frames.
- 0–3 frames per pass ran over 16.67 ms in build or raster. The worst single
  frame was 21.66 ms.

What the numbers say:
- **Queries are cheap; waiting for each other is what costs.** One query (two
  statements) takes 3–11 ms. A dashboard month step asks all five visible
  cards at once. They share one connection, so the last one waits for the
  others: a p50 of 20 ms and a worst of 26 ms. That is still a quarter of the
  budget.
- **The database on the UI isolate is not a problem at this size.** Start
  delay never passed 2 ms at p99. Moving SQLite to a background isolate
  (`NativeDatabase.createInBackground`) is not needed to meet this bar. It
  remains the first change to make if the data grows.
- **Build time on a month change has the least headroom.** Breakdown's p99
  build reached 14.37 ms, 86 % of the frame budget, as its chart and list
  rebuild. If the bar is ever missed, look there first.
- **At 120 Hz a frame has 8.33 ms, and month changes overrun it.** The
  measured p99 build was 12–14 ms on month steps, and one tabs pass reached
  8.51 ms. The worst p99 raster was 10.34 ms, on one scroll pass. Against the
  agreed 60 fps bar these pass. On this screen they are
  dropped frames during the rebuild. The operator chose to pass task 15 on
  the agreed bar and track the 120 Hz work as
  [D16](DEFERRED.md#d16--month-change-rebuilds-drop-frames-on-a-120-hz-display).

The same session also closed two device checks:
- D13: the add button is read as "Add expense".
- D14: pinning Breakdown over the starters shows the warning, and Save stays
  enabled.

---

## Parallelism notes

The best partner in the project is **Phase 7 (backup)** — mechanically
independent, no shared files, and it does not care which tables exist. Phase 3
is the largest and most intricate phase; pairing it with something mechanical
rather than with another large phase is the right call.

Also safe alongside **2B** and **4a**. Finishing Phase 3 unblocks **4b** and,
together with Phase 4, **Phase 5**.
