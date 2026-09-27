# Saved views and the dashboard — design

**Date:** 2026-09-27 · **Phase:** 3, tasks 13 (saved views) and 14 (dashboard)
**Branch:** `phase/3-saved-views`, from `ade2fcc` (`main`, `phase-1-complete`)
**Brief:** [`docs/phases/phase-3-analytics.md`](../../phases/phase-3-analytics.md) ·
**Screens:** [`screen-contract.md`](../screen-contract.md) §5.1 (dashboard), §5.7 (builder)

Task 15 (performance pass) is **not** designed here. It measures what this
builds, so it is planned once 13 and 14 are on the device — see §8.

---

## 1. Decisions taken with the operator

| Question | Decision | Why |
|---|---|---|
| Where the dashboard lives | **First tab of Analytics.** Home stays the expense list. | Home is where Phase 1's cold start and 3-tap add were measured; nothing on it changes. |
| How a view is made | **Pin what a tab shows.** No filter builder. | Smallest thing that makes the dashboard real. Cost: a tag-scoped view ("#travel by category") cannot be pinned until the builder exists — recorded as **D10**. |
| Tapping a card | **Opens the view full screen**, over the shell. | One screen draws any view; a card never depends on a tab's current state. |
| Empty dashboard | **Offer starter cards** on a button. | Works on existing installs without a data wipe, and nothing appears that the user did not ask for. |

## 2. What exists today

- `saved_views` table (schema v20): `name`, `spec_json`, `chart_type`,
  `pinned`, `sort_order`, plus the base columns. No `period`, although the
  design spec lists one.
- `SavedViewsDao`: `byId`, `pinned`, `upsert`, `softDelete`. Nothing calls it.
- Four analytics tabs, each building its own `QuerySpec` over **one month**
  (Trends: **six months**, grouped by month).
- Two defects found while reading, both removed by this work (§3.4, §3.5):
  - `upsert` uses `insertOnConflictUpdate` with `createdAt: now`, so every
    save — a rename included — resets the creation time.
  - `_parse` throws for a malformed row, so `pinned()` fails as a whole: one
    bad row blanks every card, which §5.1 forbids.

## 3. Data

### 3.1 Schema v21 — the period moves out of the spec

A stored `QuerySpec` has an absolute `dateRange`. Pinned as-is, "this month"
would stay September forever. So:

- `saved_views` gains `period_type TEXT NOT NULL DEFAULT 'month'` and
  `period_count INTEGER NOT NULL DEFAULT 1`.
- The stored spec carries **no** `dateRange`. The DAO **throws
  `ArgumentError`** on a spec that has one — silently stripping it would hide
  the caller's bug.
- Taken under the schema lock (`CONVENTIONS.md` §2): one commit containing only
  the column additions, the `schemaVersion` bump to 21, the migration step, the
  `drift_schema_v21.json` snapshot, migration tests (v20→v21 and v1→v21, each
  asserting the upgraded schema equals a fresh one), and the registry row. It
  lands on `main` before any feature commit.
- No existing rows need backfilling — no UI has ever written one — and the
  column defaults cover any that exist.

### 3.2 `ViewPeriod` (nimbus_domain)

```dart
final class ViewPeriod {
  const ViewPeriod(this.type, this.count);  // count >= 1, else ArgumentError
  final PeriodType type;
  final int count;
  /// The [count] periods of [type] ending with the one containing [anchor].
  DateRange resolve(DateKey anchor, AppCalendar calendar, {int firstDayOfWeek});
}
```

Built on `PeriodBoundaries.forPeriod` and `AppCalendar.shiftPeriod`, so a card's
range comes through the same door as the engine's bucketing. Value equality.

### 3.3 `SavedViewChart` (nimbus_domain)

`enum SavedViewChart { breakdown, trend, crossTab, hourOfDay, dayOfWeek, reflection }`,
stored by name in the existing `chart_type` column. The chart is **fixed by
where the view was pinned from** — there is no chart picker, so a spec can
never be paired with a chart that cannot draw it. This answers the screen
contract's open question 3 for now; the builder (D10) reopens it.

### 3.4 Reading views: one bad row, one bad card

```dart
sealed class SavedViewEntry { String get id; String get name; int get sortOrder; }
final class SavedView extends SavedViewEntry { ... spec, period, chart ... }
final class UnreadableSavedView extends SavedViewEntry { final Object error; }
```

The DAO parses each row on its own. A row whose spec, period or chart does not
parse becomes an `UnreadableSavedView` carrying the error — never a guessed
default, which would draw some other chart under the user's name for it.

### 3.5 DAO surface after this work

| Method | Behaviour |
|---|---|
| `watchPinned()` | `Stream<List<SavedViewEntry>>`, live, in `sort_order`. The dashboard updates when a view is pinned from another tab. Uses `idx_saved_views_pinned`. |
| `watchById(id)` | `Stream<SavedViewEntry?>` for the full-screen view, so a rename shows at once. |
| `create(...)` | Inserts at the end (`max(sort_order) + 1`) inside one transaction. |
| `rename(id, name)` | Touches `name` and `updated_at` only. |
| `reorder(List<String> ids)` | Rewrites `sort_order` for all given ids in one transaction. |
| `softDelete(id)` / `restore(id)` | Remove, and the snackbar's undo. |

`upsert`, `byId` and `pinned` are removed: none has a caller outside its own
tests, and `create`, `rename` and the watchers replace them. Removing `upsert`
removes its `createdAt` defect with it; the rename test below is what keeps it
from coming back. (The in-chat design listed a separate fix commit for it —
dropped as fixing code that the same branch deletes.)

Every view created is pinned. There is no unpinned library: without a builder
there is nowhere to find one. `pinned` stays in the schema for D10.

## 4. App layer

- `app/lib/features/dashboard/` (Phase 3 owns it):
  - `data/saved_views_repository.dart` — ids via `Ids.newId()`, wraps the DAO,
    the only way the app writes a view.
  - `application/` — `pinnedViewsProvider` (stream),
    `dashboardAnchorProvider` (a `DateKey`, today by default, shifted a month
    at a time), and `resolvedSpec(view, anchor)` → the stored spec with the
    `dateRange` from `view.period.resolve(...)`. A card never runs a spec
    without a date range; an unbounded query over all history is a bug here.
  - `presentation/` — dashboard tab, card, full-screen view, pin sheet.
- `QuerySpec.withDateRange(DateRange?)` is added to nimbus_domain: the one
  copy operation this needs. `QueryFilters` gets the matching `copyWith`.
- Each card resolves through the existing `analyticsResultProvider(spec)`, so
  a card and the tab it came from share one query when they ask the same
  question. **One engine; no dashboard-specific SQL.**
- Router: a full-screen route `/view/:id`, appended beside the other pushed
  routes in `app_router.dart` (a shared file — one line).

## 5. Screens

### 5.1 Pinning

- A 📌 `IconButton` (tooltip and semantics label) in each tab's controls:
  Breakdown, Trends, Cross-tab, and one per chart on Patterns (hour, weekday,
  regret matrix). Patterns' body is split into three public chart widgets
  first, as a behaviour-neutral refactor, so each can be pinned and drawn
  alone.
- The pin sheet: **Name**, pre-filled from what is shown (the deepest crumb's
  name when drilled in, otherwise the tab's or chart's title); one read-only
  line saying what the card will cover ("the current month" / "the last 6
  months"); **Save**. A blank name cannot be saved. The drill level and the
  confirmed-only switch travel in the spec.
- Saving is optimistic: no spinner, the sheet closes, a "Pinned to dashboard"
  snackbar.
- A view pinned while the tab shows a past month still means "the current
  month" — the sheet's coverage line says so before saving.

### 5.2 Dashboard tab

- First tab; the Analytics screen opens on it. Tab count becomes five.
- One ◀ month ▶ bar (label via the existing `periodLabel`). Every card
  resolves against this anchor, so going back a month moves them together.
- A `ReorderableListView` of cards: long-press to drag, with the screen
  reader's move actions. The new order persists via `reorder`.
- A card: name, period label, the view's **true total** in full `format`
  (scaled down rather than truncated — D1), and a compact chart about 120 dp
  tall:

  | Chart | Card body |
  |---|---|
  | breakdown | mini pie + top 3 categories |
  | trend | mini line over the window |
  | crossTab | top 3 tag × category cells + the "does not sum to 100%" note |
  | hourOfDay / dayOfWeek | mini bars, every hour/weekday present |
  | reflection | small necessity × satisfaction grid + the unlabelled total |

- A ⋮ menu on each card: Rename, Remove.
- **States, per card** (§5.1 of the contract): loading skeleton, "nothing in
  this period", error with Retry, and an unreadable-view card offering Remove.
  One card's state never affects another's.
- **Empty dashboard:** "Nothing pinned yet", **Add starter cards** (pins
  "This month by category" — breakdown, month × 1 — and "Last 6 months" —
  trend, month × 6 — with names in the current language), and **Go to
  Breakdown** (switches tab).
- Semantics: each card reads as "name, period, total".

### 5.3 Full-screen view (`/view/:id`)

Pushed over the shell. App bar: the name, ⋮ with Rename and Remove. Its own
◀ ▶, starting at the dashboard's anchor. The full-size chart is the same body
widget the tab uses. No drilling past the pinned level. Remove pops back to the
dashboard and shows **Undo** — never a confirmation dialog.

### 5.4 Not in scope

- The filter builder (§5.7 of the contract) → **D10**.
- The `advancedAnalytics` Pro gate: the contract gates the builder, not pinning
  what the user can already see.
- Changing a pinned view's query or period after the fact.

## 6. Strings

New user-facing strings go into both `app_en.arb` and `app_fa.arb`: the tab
label, pin tooltip, sheet title and fields, coverage lines, snackbars, card
menu items, empty-state copy, starter-card names, and the unreadable-view text.
Existing strings (overlap disclosure, empty-period, retry) are reused.

## 7. Testing

- **nimbus_domain:** `ViewPeriod.resolve` — Gregorian and Jalali; count 1 and
  6; a six-month window crossing each calendar's year boundary; week periods
  honour `firstDayOfWeek`; count 0 rejected. `SavedViewChart` name round trip.
  `QuerySpec.withDateRange` keeps every other field.
- **nimbus_data:**
  - migrations: v20→v21 and v1→v21 end on the fresh-install schema; defaults
    applied.
  - `createdAt` survives a rename and a reorder; `updatedAt` moves.
  - `watchPinned` emits after `create`, `rename`, `reorder`, `softDelete`,
    `restore`.
  - one unreadable row (bad JSON, unknown chart, unknown period type) sits
    beside a good one and both are returned.
  - `create` appends; `reorder` is atomic (a failure mid-way changes nothing).
  - a spec with a `dateRange` is refused.
  - `EXPLAIN QUERY PLAN`: the pinned query uses `idx_saved_views_pinned`. The
    brief's done-criteria need plan assertions on the dashboard's queries; the
    starter cards' specs are checked against the existing query-plan tests and
    any gap is added.
- **app (widget):** pin from a Food drill-down → a card named "Food" whose total
  matches a hand-computed fixture; each tab/chart pins the right
  `SavedViewChart`; a broken card beside a working one; starter cards; the
  month bar moves every card; card → full screen; rename; remove + undo;
  reorder persists; `fa` locale renders Persian digits in RTL; semantics labels
  present.

Every commit follows `CONVENTIONS.md`: failing tests first, `pre-<slug>` tag,
green, the full definition-of-done gate, a commit that explains why,
fast-forward.

## 8. Task 15 — what will be measured

Planned after 13–14 are on the device, with fixes only where numbers point:

- Seed the phone at ~5,000 rows and at ~50,000.
- Profile build, the D1 frame tool: Dashboard tab tap → every card resolved
  (six cards); frame times scrolling the dashboard and switching tabs; each
  tab's query time.
- Proposed budgets: all cards resolved within 1 s (the contract places the
  dashboard under the < 1 s cold start); no card query over 100 ms at 5,000
  rows; no frame over 16.7 ms while scrolling.
- **Leading hypothesis, not yet a finding:** `AppDatabase.openAtPath` uses
  `NativeDatabase(File(path))`, which runs every query on the UI isolate. D1's
  list reads small pages, so it never showed; a dashboard running six
  month-wide aggregations may. If the numbers confirm it, the candidate fix is
  `NativeDatabase.createInBackground`.
- Then the results table, the brief's remaining done-criteria, and
  `phase-3-complete`.
