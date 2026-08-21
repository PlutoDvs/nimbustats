# Phase 1 — Expenses (usable daily)

## Kickoff prompt

```
Read docs/phases/CONVENTIONS.md and docs/phases/phase-1-expenses.md, then
execute Phase 1. Do not read the other phase briefs or plans.
```

**Goal:** make the app genuinely usable for daily expense logging — categories,
tags, payment methods, a fast add flow, and a transaction list.

**Ships:** the user logs a real expense in under five seconds and sees it in a
list. **Real daily use starts here**, which is what makes every later analytics
decision grounded rather than speculative.

**Schema versions:** v2–v9 reserved; **expect to use none** — Phase 0 already
created every table Phase 1 needs. If you find yourself needing a column, take
v2 and follow the schema lock in `CONVENTIONS.md` §2.

**Branch:** `phase/1-expenses` · **Gate tag:** `phase-1-complete`

---

## Prerequisites — verify, do not assume

```bash
git tag --list 'phase-*-complete'     # must include phase-0-complete
dart analyze --fatal-infos            # must be clean before you add anything
ls docs/superpowers/screen-contract.md
```

If the screen contract is missing, Phase 0 is not actually done — stop.

**Design input:** the token sheet from Claude Design (named colors, type ramp,
spacing scale). If it does not exist yet, build `nimbus_design` tokens from the
screen contract's constraints and treat them as provisional — but say so, and do
not scatter raw colors through the UI in the meantime.

---

## Required reading

- Spec: "User experience: the primary constraint" and the `categories`, `tags`,
  `transactions`, `transaction_tags`, `payment_methods` table definitions
- `docs/superpowers/screen-contract.md` — the screens this phase builds
- `packages/nimbus_domain/lib/nimbus_domain.dart` (the barrel — signatures only)
- `packages/nimbus_data/lib/nimbus_data.dart` (the barrel — signatures only)

---

## Owns

```
packages/nimbus_design/**                          tokens, theme, shared widgets
packages/nimbus_data/lib/src/seed/**               first-run category/tag seeding
packages/nimbus_domain/lib/src/prediction/**       CategoryPredictor interface + MRU impl
app/lib/features/transactions/**
app/lib/features/categories/**
app/lib/features/tags/**
app/lib/features/payment_methods/**
app/lib/features/onboarding/**
app/lib/features/settings/**
```

Additive-only edits to `nimbus_data`'s DAOs (new methods, no signature changes).

**Must not touch:** anything under `capture/`, `analytics/`, `trackers/`,
`goals/`, `backup/`.

---

## Scope

**In:**

- Category manager: create, rename, recolor, pick icon, **move within the
  tree**, archive, reorder. Colors and a predefined icon set.
- Tag manager: same, including nesting (`#travel > #turkey-2026`).
- Payment method manager: name, kind, last4, color, icon, archive.
- Add-expense flow: amount first, category chips, optional tags, optional
  payment method, optional note, date defaulting to today.
- Edit and delete a transaction. Delete is soft, with undo.
- Transaction list: paginated, grouped by day, day subtotals, running month
  total, text search, basic filters (date range, category, direction).
- Income entry — same flow, `direction: income`.
- **Necessity × satisfaction on the edit screen only.** Deliberately absent
  from the add flow; extra taps in the add path are what kill daily tracking.
- First-run: seed a localized default category tree, ask for currency,
  calendar, and locale. Nothing else.
- Settings: currency, calendar, locale, first day of week, theme.

**Out:** SMS capture, charts beyond the running month total, saved views,
trackers, goals, the home widget, backup. Recurring transactions and receipt
OCR are out of the whole project.

---

## UX acceptance criteria — these are tests, not aspirations

From the spec's north star. Each is verified in this phase and re-verified in
every later phase that adds a screen.

| Criterion | How it is verified |
|---|---|
| Repeat purchase logged in **≤ 3 taps** | Widget test counting taps on the golden path |
| Any expense in **≤ 5 seconds** | Manual, on a real mid-range device |
| Cold start to usable list **< 1 s** | `flutter run --profile`, measured on device |
| List holds **60 fps** | Frame timings on a seeded DB of 5,000+ transactions |
| Amount is the **only required field** | Widget test: save with amount alone succeeds |
| Keypad opens focused on amount | Widget test asserting initial focus |
| **No spinner on save** | Writes are local and optimistic; UI updates first |
| **Undo, never confirm** | No modal confirmation dialog exists in the codebase |
| Primary actions in the bottom third | Reviewed against the screen contract |
| Haptic on capture | Present on save and on chip selection |

A phase that ships without measuring the top four has not met its acceptance
criteria — measure them on hardware, not on an emulator.

---

## Interfaces produced (Phases 2, 3, 5, 6 consume these)

Name them exactly as written; later briefs reference these identifiers.

- `TransactionRepository` — the single write path. Every insert in the app goes
  through it, including (later) captured SMS and the home widget. No second
  insert path is ever created.
  - `Future<Transaction> add(TransactionDraft draft)`
  - `Future<void> update(Transaction tx)`
  - `Future<void> softDelete(String id)` / `Future<void> restore(String id)`
- `TransactionDraft` — value object carrying `Money amount`, `TxDirection`,
  `String categoryId`, `DateTime occurredAtUtc`, and the optional fields.
- `CategoryPredictor` (in `nimbus_domain`) —
  `List<String> predict({String? merchant, DateTime? at, int limit = 4})`.
  Phase 1 implements it as most-recently-used plus most-frequent. **Phase 2
  swaps in merchant-rule-backed prediction behind this same interface**, which
  is why it is an interface in Phase 1 rather than a helper function.
- `PaginatedTransactionQuery` — keyset pagination by `(local_date_key, id)`.
- Route names for add-expense and transaction-detail, exported from
  `app/lib/features/transactions/routes.dart`.

---

## Known traps

- **Pagination from day one.** The spec says "never load all transactions". Use
  keyset pagination on `(local_date_key, id)`, not `LIMIT/OFFSET` — offset
  degrades exactly when the user has enough history for the app to matter.
- **The "Uncategorized" system row.** Phase 0 creates it; Phase 1 must make it
  undeletable and unrenameable, and must never show it in the picker as a
  normal choice. Every chart depends on `category_id` being non-null.
- **Moving a subtree rebuilds materialized paths transactionally.** Phase 0
  built the helper and its recursive-CTE oracle test. Phase 1 must exercise it
  through the UI path and assert descendants moved with the parent.
- **Persian and Latin digits in the amount field.** Input must accept both
  (`nimbus_domain/src/money/digits.dart`), and render in the locale's numerals.
  A user typing `۱۲۳۴۵` must not produce a parse error.
- **Money parsing must never touch `double`.** Parse the string to minor units
  directly. `double.parse` on a Toman amount silently loses precision at large
  values.
- **Archive is not delete.** Archived categories disappear from pickers but must
  still resolve in historical transactions, or old charts break.
- **Tag input needs a create-on-the-fly path.** Forcing a trip to the tag
  manager before tagging is precisely the friction this app exists to remove.
- **Do not build a chart here.** A running month total is in scope; anything
  more belongs to Phase 3 and will be rewritten on the QuerySpec engine.

---

## Task outline

Expand into a step-by-step TDD plan at kickoff. Rough shape, each ending in a
committable, tested deliverable:

1. Design tokens and theme in `nimbus_design` (from the Claude Design token
   sheet), light and dark, RTL-first.
2. First-run seeding: localized default category tree + settings bootstrap.
3. Category manager — CRUD, tree move, archive, reorder.
4. Tag manager — CRUD, nesting, create-on-the-fly.
5. Payment method manager.
6. `TransactionRepository` + `TransactionDraft` with full DAO-level tests.
7. `CategoryPredictor` (MRU + frequency) with tests on a seeded DB.
8. Add-expense screen — amount-first, chips, ≤3-tap golden path.
9. Transaction list — keyset pagination, day grouping, month total.
10. Edit/delete with undo; necessity × satisfaction on edit.
11. Settings screen — currency, calendar, locale, first day of week, theme.
12. UX budget verification on a real device; record the numbers in the plan.

---

## Definition of done

`CONVENTIONS.md` §5, plus:

- [ ] All ten UX acceptance criteria above measured and recorded.
- [ ] A seeded 5,000-transaction database used for the list performance check.
- [ ] `TransactionRepository` is the only insert path; grep proves no DAO insert
      is called directly from UI code.
- [ ] Every screen built here is reflected back into
      `docs/superpowers/screen-contract.md` if reality diverged from the design.
- [ ] `git tag phase-1-complete`.

---

## Parallelism notes

Phase 1 runs safely alongside **Phase 2A** (the pure-Dart parsing domain), which
touches only `nimbus_domain/src/parsing/` and shares no file with this phase.

Finishing Phase 1 unblocks Phases 2B, 3, 4, and 7 — the widest fan-out in the
project. Prioritise it accordingly.
