# Phase 0 — Foundation

## Kickoff prompt

```
Read docs/phases/CONVENTIONS.md and docs/phases/phase-0-foundation.md, then
execute Phase 0 from its full plan at
docs/superpowers/plans/2026-08-20-nimbustats-phase-0-foundation.md.
Do not read the other phase briefs.
```

**Goal:** the tested, non-visual foundation — a Dart workspace with
compiler-enforced module boundaries, a pure-Dart domain layer (money, dual
calendar, entitlements), the SQLite schema with migration tooling, RTL
localization, and the screen contract that unblocks UI design.

**Ships:** nothing a user can see. Everything after this depends on it.
**Schema versions:** v1 (used).
**Branch:** `phase/0-foundation`, fast-forward merged into `main` (nothing runs
in parallel with it, but the branch keeps the workflow uniform).
**Gate tag:** `phase-0-complete`

---

## This phase already has a full plan

Unlike the other briefs, Phase 0 is planned to the step: 12 tasks, exact code,
exact commands.

**→ `docs/superpowers/plans/2026-08-20-nimbustats-phase-0-foundation.md`**

Execute it directly. This brief exists only to place Phase 0 in the phase
system and to record the three things a later phase needs to know.

---

## Prerequisites

None — this is the first phase. But **Task 1 is operator-run and blocks
everything**: nothing is installed on this machine (no Flutter, no Dart, no
Android SDK, no Android Studio; JDK 17.0.2 is present, `JAVA_HOME` unset).
`flutter doctor --android-licenses` is interactive and cannot be automated.

---

## What Phase 0 produces that later phases consume

The single most useful thing to know when starting any later phase:

| Produced | Where | Consumed by |
|---|---|---|
| `Money`, `Currency`, `MoneyFormatter`, digit normalization | `nimbus_domain/src/money/` | every phase |
| `DateKey`, `DateRange`, `AppCalendar`, `PeriodType`, `GregorianCalendar`, `JalaliCalendar` | `nimbus_domain/src/calendar/` | 1, 3, 4, 5, 6 |
| `Feature`, `Entitlements`, `EntitlementSource` | `nimbus_domain/src/entitlements/` | 2, 3, 7, 8 |
| `AppDatabase` (schemaVersion 1), `openTestDatabase()`, `BaseColumns`, `DateKeyConverter`, `MoneyConverter` | `nimbus_data/src/database/` | every data-touching phase |
| Tables: settings, categories, tags, payment_methods, transactions, transaction_tags | `nimbus_data/src/tables/` | 1, 2, 3, 5 |
| Materialized-path helpers (build, move, subtree query) | `nimbus_data/src/tree/` | 1, 3 |
| DAOs: `categoriesDao`, `tagsDao`, `transactionsDao`, `settingsDao` | `nimbus_data/src/daos/` | 1, 2, 3 |
| `test/architecture_test.dart` | repo root | every phase (it must stay green) |
| **The screen contract** | `docs/superpowers/screen-contract.md` | Claude Design, and every UI phase |

---

## Three uncertainties Phase 0 resolves empirically

Flagged rather than assumed, because each is expensive to discover late. If any
of them disagrees with what the plan says, **stop and reconcile before
continuing** — do not paper over it.

1. **Task 1 Step 5** — that native SQLite loads for host tests.
   `sqlite3_flutter_libs` is `0.6.0+eol`; the replacement mechanism could not be
   confirmed without an installed toolchain.
2. **Task 6 Step 2** — `shamsi_date`'s actual behavior (Nowruz 1403 =
   2024-03-20, plus a decade of round-trips) before the Jalali calendar is built
   on it.
3. **Task 8 Step 5** — the `drift_dev schema` CLI surface, before the migration
   tooling depends on its exact flags.

---

## Definition of done

`CONVENTIONS.md` §5, plus:

- [ ] `docs/superpowers/screen-contract.md` exists and covers every screen in
      the inventory with all five required facets.
- [ ] `docs/DEVELOPMENT.md` records the exact installed versions.
- [ ] `pubspec.lock` is committed.
- [ ] `git tag phase-0-complete` and `git tag pre-phase-1`.

---

## What unblocks next

Tagging `phase-0-complete` unblocks **Phase 1** and **Phase 2A** (the pure-Dart
parsing domain), which can run in parallel. The screen contract unblocks design
work in Claude Design, which should start immediately — its output (a token
sheet) is what Phase 1 needs first.
