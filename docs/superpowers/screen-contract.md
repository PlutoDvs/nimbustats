# NimbuStats — Screen Contract

**Status:** Phase 0 deliverable. Written before any screen exists, which is the
point: design that starts without knowing each screen's states produces screens
that cannot be built.

**Sources.** Budgets and interaction rules come from
[`specs/2026-08-20-nimbustats-design.md`](specs/2026-08-20-nimbustats-design.md)
("User experience: the primary constraint"); global engineering rules from
[`../phases/CONVENTIONS.md`](../phases/CONVENTIONS.md); screen ownership from the
per-phase briefs in [`../phases/`](../phases/). Where this document and those
disagree, they win and this file is wrong — say so rather than working around it.

**How to read a screen entry.** Every screen documents five things: purpose,
data in, states, actions out, UX budget. Section 1 holds the rules that apply to
*all* of them, so each entry lists only what is specific to it.

---

## Index

| # | Screen | Phase | Section |
|---|---|---|---|
| 1 | Onboarding | 1 | [§3.1](#31-onboarding--phase-1) |
| 2 | Add / edit transaction | 1 | [§3.2](#32-add--edit-transaction--phase-1) |
| 3 | Transaction list | 1 | [§3.3](#33-transaction-list--phase-1) |
| 4 | Category manager | 1 | [§3.4](#34-category-manager--phase-1) |
| 5 | Tag manager | 1 | [§3.5](#35-tag-manager--phase-1) |
| 6 | Settings | 1 (extended later) | [§3.6](#36-settings--phase-1-extended-by-later-phases) |
| 7 | Review inbox | 2 | [§4.1](#41-review-inbox--phase-2) |
| 8 | Teach template | 2 | [§4.2](#42-teach-template--phase-2) |
| 9 | Dashboard | 3 | [§5.1](#51-dashboard--phase-3) |
| 10 | Analytics — breakdown | 3 | [§5.2](#52-analytics--breakdown--phase-3) |
| 11 | Analytics — trends | 3 | [§5.3](#53-analytics--trends--phase-3) |
| 12 | Analytics — cross-tab | 3 | [§5.4](#54-analytics--cross-tab--phase-3) |
| 13 | Analytics — patterns | 3 | [§5.5](#55-analytics--patterns--phase-3) |
| 14 | Regret matrix | 3 | [§5.6](#56-regret-matrix--phase-3) |
| 15 | Saved-view builder | 3 | [§5.7](#57-saved-view-builder--phase-3) |
| 16 | Trackers | 4 | [§6.1](#61-trackers--phase-4) |
| 17 | Tracker detail | 4 | [§6.2](#62-tracker-detail--phase-4) |
| 18 | Goals | 5 | [§7.1](#71-goals--phase-5) |
| 19 | Goal editor | 5 | [§7.2](#72-goal-editor--phase-5) |

---

## 1. Rules that apply to every screen

### 1.1 The four mandatory states

No screen is done with only its happy path. Every screen implements:

- **`loading`** — first paint before data arrives. Skeleton or placeholder, never
  a blocking spinner. Exception: **saves never show a spinner at all** (§1.3).
- **`empty`** — the query succeeded and returned nothing. Distinct from loading
  and from error, and it must say what to do next, not just "no data".
- **`error`** — the read failed. Shows what failed and offers a retry. Never a
  bare exception string, never a silent blank.
- **`populated`** — data present.

### 1.2 Degenerate cases to design once

These recur across screens. Design them here; each screen entry names which
apply rather than restating them.

| ID | Case | Requirement |
|---|---|---|
| D1 | Nine-digit Toman amount (`999٬999٬999`) | Must not truncate, wrap mid-number, or push the row's actions off-screen. Dense contexts use `formatCompact`; detail views use full grouped `format`. |
| D2 | Forty-character merchant name | Single line, ellipsised at the end; full value reachable (detail view or long-press). Never reflow the row height. |
| D3 | Twenty tags on one expense | Chips collapse to a bounded row plus a `+N` affordance. Never an unbounded wrapping field that eats the screen. |
| D4 | Category tree six levels deep | Indentation must degrade — cap the visual indent and rely on the breadcrumb/path instead. RTL indents from the right. |
| D5 | Failed SMS parse | Never silent. Surfaces as a gentle "teach me this?" prompt, never a modal, never an error the user must dismiss. |
| D6 | Mixed direction in one list | Income and expense are visually distinguishable without relying on colour alone (an arrow or sign as well). |
| D7 | Negative / refund amounts | `Money` may be negative. Sign renders on the correct side in both directions of text. |
| D8 | VPS unreachable | Every screen works fully offline. Anything server-backed degrades silently and is never on a critical path. |

### 1.3 Interaction rules (non-negotiable)

- **Amount is the only required field.** The numeric keypad opens focused on the
  amount immediately.
- **Never show a spinner for a save.** Writes are local and optimistic — a
  SQLite insert is sub-millisecond, so the UI updates first and persists behind.
- **Undo, never confirm.** Destructive actions show a snackbar with undo. Modal
  confirmation dialogs are friction and are not used.
- **Smart defaults over blank fields.** Category is predicted from merchant, time
  of day, and recent history; the top four candidates appear as one-tap chips.
- **Nothing blocks on the review queue.** Unconfirmed captures show a badge,
  never a modal.
- **One-handed reach.** Primary actions sit in the bottom third of the screen
  (`NimbusTokens.minTapTarget` is the floor for any tap target).
- **Zero-config first run.** A localized default category tree is seeded at
  install. Nobody builds a taxonomy before logging their first expense.
- **Haptic confirmation** on capture and on habit increments.

### 1.4 Accessibility

Part of the definition of done for every screen, not a later audit:
dynamic type, sufficient contrast, and screen-reader labels on every interactive
element. Charts additionally need a non-visual equivalent — a screen reader must
be able to reach the same numbers a sighted user reads off the bars.

### 1.5 Data access rules

- Every query filters `deleted_at IS NULL` through the shared helper.
- Lists are **paginated**. "Load all transactions" is never acceptable.
- Period boundaries are computed in the **active calendar** (`AppCalendar`),
  then converted to a `DateKey` range. No calendar math in SQL.

---

## 2. Types this contract references

**Exists today (Phase 0):** `Money`, `Currency`, `MoneyFormatter` (`format`,
`formatCompact`, `parse`), `Digits`, `DateKey`, `DateRange`, `PeriodType`,
`AppCalendar` (`GregorianCalendar`, `JalaliCalendar`), `Category`, `Tag`,
`Transaction`, `PaymentMethod`, `TxDirection`, `TxSource`, `Necessity`,
`Satisfaction`, `Feature`, `Entitlements`, and the DAOs `categoriesDao`,
`tagsDao`, `transactionsDao`, `settingsDao`.

**Does not exist yet** — named here so design has a stable target, to be built by
the phase that owns it: `QuerySpec`, `AnalyticsResult`, `SavedView` (Phase 3),
`CapturedMessage`, `Template`, `MerchantRule` (Phase 2), `Tracker`,
`TrackerEntry` (Phase 4), `Goal`, `GoalEvaluation` (Phase 5).

A screen entry naming a type from the second list is describing a contract, not
an API that can be called today.

---

## 3. Phase 1 — Expenses

### 3.1 Onboarding — Phase 1

1. **Purpose.** Get the user to their first logged expense without asking them to
   configure anything.
2. **Data in.** Nothing read; writes `settingsDao` keys (currency, calendar,
   locale, first day of week, theme) and triggers the seeded `Category` tree.
3. **States.** `loading` (seeding in progress — the only place a brief progress
   indicator is acceptable, because it is genuinely doing work), `error` (seeding
   failed — must offer retry, never leave a half-seeded tree), `populated` (the
   choice steps). No `empty`. Degenerate: D8.
4. **Actions out.** `onCurrencySelected(Currency)`, `onCalendarSelected(CalendarKind)`,
   `onLocaleSelected(Locale)`, `onFinished()`, `onSkipped()` — skipping must be
   possible and must still produce a working app.
5. **UX budget.** Skippable in one tap. Nothing here may block reaching the add
   screen; defaults are already valid before the first question is answered.

### 3.2 Add / edit transaction — Phase 1

1. **Purpose.** Log an expense in under five seconds, and a repeat purchase in
   three taps.
2. **Data in.** `MoneyFormatter`, active `Currency`, predicted `List<Category>`
   (top four), recent `List<PaymentMethod>`, `List<Tag>` for the picker; in edit
   mode the existing `Transaction` plus `tagsOf(id)`.
3. **States.** `populated` is the default — the screen opens ready to type, so
   there is no meaningful `loading` for the amount field; category chips may
   arrive after first paint and must not reflow the keypad. `error` covers a
   rejected parse (`MoneyFormatter.parse` on malformed input) and a failed write.
   `empty` applies to the tag and payment-method pickers. Degenerate: D1, D2, D3,
   D7.
4. **Actions out.** `onAmountSubmitted(Money)`, `onCategorySelected(String id)`,
   `onTagsChanged(List<String> tagIds)`, `onPaymentMethodSelected(String? id)`,
   `onMerchantChanged(String?)`, `onNoteChanged(String?)`, `onDateChanged(DateKey)`,
   `onDirectionChanged(TxDirection)`, `onSaved()`, `onDeleted()` (edit only, with
   undo).
5. **UX budget.** **≤ 3 taps** for a repeat purchase, **≤ 5 seconds** for any
   expense. Keypad focused on amount at open. No save spinner.

> **Deliberately absent: necessity and satisfaction.** They appear on the *edit*
> screen and in the review inbox only. Extra taps in the add path are exactly
> what kills daily tracking.

### 3.3 Transaction list — Phase 1

1. **Purpose.** See what was spent, and reach any entry to correct it.
2. **Data in.** `transactionsDao.inRange(DateRange, {confirmedOnly})` paginated,
   `totalInRange(DateRange)` for the header, `MoneyFormatter`, active
   `AppCalendar` for period labels and grouping.
3. **States.** All four. `empty` is the first-run state and must point at the add
   action rather than reading as a failure. Degenerate: D1, D2, D6, D7.
4. **Actions out.** `onPeriodChanged(DateRange, PeriodType)`,
   `onTransactionTapped(String id)`, `onTransactionDeleted(String id)` (undo
   snackbar), `onFilterChanged(...)`, `onLoadMore()`.
5. **UX budget.** **Cold start to a usable list < 1 s** on a mid-range device.
   Lists hold **60 fps**; queries are paginated.

### 3.4 Category manager — Phase 1

1. **Purpose.** Reshape the category tree without breaking the history attached
   to it.
2. **Data in.** `categoriesDao.subtreeOf(id)`, root list, per-node child counts.
3. **States.** All four; `empty` is unreachable in practice because the tree is
   seeded, but must still exist for the case where a user deletes everything.
   Degenerate: D4 (six levels deep) is the primary case here.
4. **Actions out.** `onNodeCreated({name, parentId, iconKey, color})`,
   `onNodeRenamed(String id, String name)`, `onNodeMoved(String id, String? newParentId)`,
   `onNodeArchived(String id)`, `onNodeDeleted(String id)` (undo).
5. **UX budget.** A move is a drag or a two-tap "move to…", never a form. The
   screen must reject a move beneath the node's own descendant *before* the drop
   completes — the DAO throws `ArgumentError`, and surfacing that as an error
   toast after the fact is not acceptable.

### 3.5 Tag manager — Phase 1

1. **Purpose.** Same as §3.4 for tags, which nest identically.
2. **Data in.** `tagsDao.subtreeOf(id)`, usage counts per tag.
3. **States.** All four; `empty` is the real first-run state here — unlike
   categories, tags are **not** seeded, so this screen opens empty and must
   explain what a tag is for. Degenerate: D3, D4.
4. **Actions out.** Same shape as §3.4, against `tagsDao`.
5. **UX budget.** Creating a tag inline from the add screen must not require
   visiting this screen first.

### 3.6 Settings — Phase 1 (extended by later phases)

1. **Purpose.** Change the few things that alter how everything else renders.
2. **Data in.** `settingsDao` key/values; `Entitlements` for the "Pro — free
   during early access" labels.
3. **States.** `populated` and `error` (a failed write must revert the control,
   not leave the UI showing a value the database does not hold). Degenerate: D8.
4. **Actions out.** `onCurrencyChanged(Currency)`, `onCalendarChanged(CalendarKind)`,
   `onLocaleChanged(Locale)`, `onFirstDayOfWeekChanged(int)`, `onThemeChanged(ThemeMode)`.
5. **UX budget.** Changing calendar or locale re-renders the app without a
   restart. Sections owned by later phases (backup — Phase 7; capture sources —
   Phase 2) append here rather than creating sibling screens.

---

## 4. Phase 2 — Capture

### 4.1 Review inbox — Phase 2

1. **Purpose.** Turn unconfirmed captures into confirmed transactions fast, and
   teach the app while doing it.
2. **Data in.** Unconfirmed `List<Transaction>` (`confirmedOnly: false` minus
   confirmed), source `CapturedMessage` for each, predicted `Category`.
3. **States.** All four. `empty` is the **goal state** and should read as an
   achievement, not a void — the queue shrinks toward zero as the app learns.
   Degenerate: D1, D2, D5, and the Rial/Toman scale trap below.
4. **Actions out.** `onCategoryConfirmed(String txId, String categoryId)`,
   `onNecessitySet(String txId, Necessity)`, `onSatisfactionSet(String txId, Satisfaction)`,
   `onAmountCorrected(String txId, Money)`, `onRejected(String txId)`,
   `onTeachRequested(String capturedMessageId)`.
5. **UX budget.** **One tap sets category**; necessity and satisfaction are two
   optional further taps. A swipe-through, never a form per item. Never modal —
   the queue shows a badge and nothing blocks on it.

> **Scale trap.** Iranian bank SMS quote **Rial** while the app stores **Toman**.
> A per-template ÷10 applies. The review screen is where a mis-scaled amount is
> caught, so the captured raw text must be visible next to the parsed amount.

### 4.2 Teach template — Phase 2

1. **Purpose.** Let the user teach the app a bank's SMS format by tapping, with
   no regex ever shown.
2. **Data in.** The raw `CapturedMessage` text, its tokenization, the roles
   already assigned, a live preview of what the generated `Template` would
   extract.
3. **States.** `populated` (tokens shown), `error` (the generated template
   matches nothing, or matches the sample ambiguously — must be caught here, not
   after it silently mis-parses future messages), plus a **preview** state
   showing the parse result before saving. `loading` while generating.
   Degenerate: D5 is the entry point to this screen; D1 for the amount token.
4. **Actions out.** `onTokenRoleAssigned(int tokenIndex, TokenRole role)` where
   roles are amount, merchant, date, card, balance; `onAmountScaleSet(int divisor)`;
   `onTemplateSaved()`, `onCancelled()`.
5. **UX budget.** One screen, not a wizard. The user taps tokens and sees the
   parse update live; a template that fails its own sample cannot be saved.

---

## 5. Phase 3 — Analytics

All Phase 3 screens are views over one `QuerySpec` engine. They differ by
filters, group-by, and chart type — not by code path.

### 5.1 Dashboard — Phase 3

1. **Purpose.** Answer "how am I doing this period" in one glance, assembled from
   the user's own pinned saved views.
2. **Data in.** `List<SavedView>` in pin order, each resolved to an
   `AnalyticsResult`; current-period `DateRange` from the active `AppCalendar`.
3. **States.** All four. `empty` = nothing pinned yet, and must offer a way to
   pin the first thing. **Per-card** loading and error: one failing card must not
   blank the dashboard. Degenerate: D1, D8.
4. **Actions out.** `onCardTapped(String savedViewId)`, `onCardsReordered(List<String>)`,
   `onCardUnpinned(String id)`, `onPeriodChanged(DateRange)`.
5. **UX budget.** Falls under the **< 1 s cold start**; cards resolve
   independently and progressively rather than waiting on the slowest.

### 5.2 Analytics — breakdown — Phase 3

1. **Purpose.** Where the money went, with drill-down into any slice.
2. **Data in.** `QuerySpec` (filters + group-by category/tag/payment method/
   merchant), `AnalyticsResult` with buckets **and the true total**.
3. **States.** All four. Degenerate: D1 on every axis label, D3 and D4 in the
   grouping dimension.
4. **Actions out.** `onSliceTapped(...)` (drill down one level),
   `onDrillUp()`, `onGroupByChanged(...)`, `onFilterChanged(QuerySpec)`,
   `onSavedAsView(QuerySpec)`.
5. **UX budget.** Axis and dense labels use `formatCompact`; the detail panel
   uses full `format`.

> **Tag breakdowns double-count and the UI must say so.** An expense tagged
> `#travel` *and* `#food` lands in both buckets, so tag sums exceed the true
> total. The engine returns the true total alongside the buckets; any tag-grouped
> chart **must** carry a visible note that percentages do not sum to 100. A pie
> chart that quietly lies here is a defect, not a styling choice.

### 5.3 Analytics — trends — Phase 3

1. **Purpose.** Is this getting better or worse over time.
2. **Data in.** `QuerySpec` grouped by `PeriodType`, plus a comparison range.
3. **States.** All four, plus a **partial-period** state: the current period is
   incomplete and must be marked as such rather than rendered as a collapse in
   spending. Degenerate: D1; sparse series with gaps.
4. **Actions out.** `onPeriodTypeChanged(PeriodType)`, `onRangeChanged(DateRange)`,
   `onComparisonToggled(bool)`, `onPointTapped(DateKey)`.
5. **UX budget.** Period boundaries follow the **active calendar** — a Jalali
   month is not a Gregorian one, and a trend that silently uses the wrong one is
   wrong in a way users will notice and not be able to articulate.

### 5.4 Analytics — cross-tab — Phase 3

1. **Purpose.** Two dimensions at once — tag × category is the motivating case.
2. **Data in.** `QuerySpec` with two group-by dimensions, `AnalyticsResult` as a
   matrix plus row/column totals and the true grand total.
3. **States.** All four, plus **sparse** (most cells empty) as an explicit design
   case rather than an accident. Degenerate: D1 in every cell, D3/D4 on both
   axes, and a matrix wider than the screen — which scrolls in its own container
   and never makes the page scroll sideways.
4. **Actions out.** `onCellTapped(rowKey, colKey)`, `onAxisChanged(...)`,
   `onTransposed()`.
5. **UX budget.** Same double-counting warning as §5.2 whenever a tag axis is
   present. Row and column totals are **not** the sum of visible cells when tags
   are involved, and must be labelled accordingly.

### 5.5 Analytics — patterns — Phase 3

1. **Purpose.** Behavioural regularities — hour-of-day, day-of-week, merchant
   frequency.
2. **Data in.** `QuerySpec` grouped by hour-of-day / day-of-week / merchant.
3. **States.** All four, plus **insufficient data** as distinct from `empty`: a
   pattern claim from six transactions is noise, and the screen must say "not
   enough data yet" rather than draw a confident-looking chart.
4. **Actions out.** `onDimensionChanged(...)`, `onBucketTapped(...)`,
   `onSavedAsView(QuerySpec)`.
5. **UX budget.** Day-of-week ordering follows the user's configured first day of
   week, which differs between the `fa` and `en` defaults.

### 5.6 Regret matrix — Phase 3

1. **Purpose.** The reflective payoff: how much money went to things that were
   avoidable *and* regretted.
2. **Data in.** `QuerySpec` grouped by `Necessity` × `Satisfaction`, over a
   `DateRange`; cell totals as `Money`.
3. **States.** All four, plus **unlabelled**: transactions with null necessity or
   satisfaction are excluded from cells and their total must be shown separately,
   never silently dropped. That figure is also the honest prompt to label more.
   Degenerate: D1.
4. **Actions out.** `onCellTapped(Necessity, Satisfaction)` (drill to the list),
   `onPeriodChanged(DateRange)`, `onSavedAsView(QuerySpec)`.
5. **UX budget.** Tone is factual, never scolding — this screen exists to inform
   a decision, not to deliver a verdict. Avoid a colour scheme that reads as
   punishment.

### 5.7 Saved-view builder — Phase 3

1. **Purpose.** Name a query so it can be pinned and re-read without rebuilding
   it.
2. **Data in.** The `QuerySpec` under construction, a live preview of its
   `AnalyticsResult`, available chart types.
3. **States.** `populated`, `loading` (preview resolving), `error` (a spec that
   cannot compile or returns nothing — surfaced before saving, not after).
   Degenerate: a filter combination matching zero rows, which is a valid saved
   view and must be savable with a clear preview that it is currently empty.
4. **Actions out.** `onSpecChanged(QuerySpec)`, `onChartTypeChanged(...)`,
   `onPeriodTypeChanged(PeriodType)`, `onNamed(String)`, `onSaved()`,
   `onPinnedToDashboard(bool)`.
5. **UX budget.** The preview updates as the spec changes; the user never saves
   blind. `advancedAnalytics` is a gated `Feature` — the gate lives in one
   `FeatureGate` widget and is labelled "Pro — free during early access".

---

## 6. Phase 4 — Trackers

### 6.1 Trackers — Phase 4

1. **Purpose.** Log a non-money thing — cigarettes, water, gym — in one tap.
2. **Data in.** `List<Tracker>` with today's totals.
3. **States.** All four; `empty` explains what a tracker is and offers the first
   one. Degenerate: D8; a tracker with a `double` quantity (the one place a
   non-integer numeric is allowed — money never is).
4. **Actions out.** `onIncrement(String trackerId)`, `onDecrement(String trackerId)`
   (undo), `onTrackerTapped(String id)`, `onTrackerCreated(...)`.
5. **UX budget.** **One tap** to increment, with haptic confirmation. Increments
   are optimistic and never show a spinner.

### 6.2 Tracker detail — Phase 4

1. **Purpose.** Today's total for one tracker, plus its history.
2. **Data in.** One `Tracker`, today's aggregate, paginated `List<TrackerEntry>`.
3. **States.** All four. Degenerate: a long history (paginated, D8).
4. **Actions out.** `onQuickIncrement()`, `onEntryDeleted(String id)` (undo),
   `onEntryEdited(String id, double quantity)`, `onTrackerEdited(...)`,
   `onTrackerArchived(String id)`.
5. **UX budget.** Quick increment stays reachable in the bottom third while the
   history scrolls.

---

## 7. Phase 5 — Goals & limits

### 7.1 Goals — Phase 5

1. **Purpose.** See at a glance whether each goal or limit is on track.
2. **Data in.** `List<Goal>` each with a `GoalEvaluation`
   (`{current, target, status, projection}`), active `AppCalendar` for period
   boundaries.
3. **States.** All four, plus the evaluation statuses as designed states rather
   than colour swaps: **on track**, **at risk** (80% threshold), **exceeded**
   (100%), and **period not started**. Degenerate: D1 on targets; a savings goal,
   which reports required run-rate rather than period progress and therefore
   cannot use the same progress bar semantics.
4. **Actions out.** `onGoalTapped(String id)`, `onGoalCreated()`,
   `onGoalPaused(String id)`, `onGoalDeleted(String id)` (undo).
5. **UX budget.** Threshold crossings drive alerts (80%, 100%) so a warning
   arrives while there is still time to act; the screen never nags on a schedule.

### 7.2 Goal editor — Phase 5

1. **Purpose.** Define a goal without the user needing to know that all four
   goal types are one formula.
2. **Data in.** The `Goal` under construction; category and tag trees for scope
   selection; `PeriodType` and `CalendarKind` options; a live evaluation preview
   against recent history.
3. **States.** `populated`, `loading` (preview), `error` (a goal that cannot be
   evaluated — e.g. an empty scope — caught before saving). Degenerate: D4 in the
   scope picker; a target of zero, which is legitimate for a habit maximum
   ("zero cigarettes") and must not be rejected as empty input.
4. **Actions out.** `onMetricChanged(...)`, `onScopeChanged(...)`,
   `onDirectionChanged(...)`, `onTargetChanged(Money | double)`,
   `onPeriodChanged(PeriodType)`, `onCalendarChanged(CalendarKind)`,
   `onThresholdsChanged(List<int>)`, `onSaved()`.
5. **UX budget.** The preview shows what the goal *would* have said over the last
   few periods, so a target is chosen against reality rather than guessed.

---

## 8. RTL and numeral rules

These are the constraints most often missed and the most expensive to retrofit.

- **Every layout is authored RTL first; LTR is derived.** `fa` is the primary
  locale and the app's default. A layout that is designed LTR and mirrored later
  reliably breaks on icons, chart axes, progress direction, and swipe gestures.
- **Numerals follow the locale, not the data.** Persian digits (`۰۱۲۳۴۵۶۷۸۹`) in
  `fa`, Latin in `en`, via `Digits` / `MoneyFormatter(persianDigits:)`. This
  includes chart axes, counts, dates, and percentages — not just amounts.
- **Input accepts all three digit sets.** `MoneyFormatter.parse` already accepts
  Persian, Arabic-Indic, and Latin digits with any of the group separators; input
  fields must not filter them out before parsing.
- **Amount formatting by context.** `formatCompact` on chart axes and in dense
  lists; full `format` in detail views and totals. Never mix the two inside one
  visual grouping.
- **Dates follow the active calendar**, not the locale. A user may read `en` and
  keep the Jalali calendar; both combinations must render correctly.
- **Swipe direction mirrors.** In RTL, a "swipe right to confirm" gesture reads
  as the opposite action. Gestures are specified semantically (forward /
  backward), never as left / right.
- **Tag charts carry the double-count note in both locales.** It is a
  user-facing string in both ARBs, not a hardcoded English caption.

---

## 9. Open questions for design

Recorded rather than silently decided:

1. **Does a soft-deleted category hide its descendants** in analytics rollup?
   `subtreeOf` (path-based) keeps a deleted node's children; a parent-walking
   query would prune them. Nothing depends on the answer yet, but §3.4 and every
   Phase 3 screen do once soft delete is used in anger.
2. **What "total" means on a mixed list.** `totalInRange` currently sums income
   and expense alike and includes unconfirmed rows. Phase 3 must decide, per
   screen, whether a total is net, expense-only, and confirmed-only.
3. **Chart type per saved view** — *answered 2026-09-27 for pinning:* the
   chart is fixed by where a view was pinned from (`SavedViewChart`), so a
   spec can never be paired with a chart that cannot draw it, and a view's
   spec cannot change after pinning. The builder (D10) reopens this: which
   chart types it offers for which group-by combinations.
