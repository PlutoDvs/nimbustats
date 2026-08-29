# NimbuStats — Shared Conventions

Every phase brief in this folder implicitly includes this file. A session
executing a phase reads **this file plus its own phase brief** — nothing else
from `docs/phases/`.

**Spec:** `docs/superpowers/specs/2026-08-20-nimbustats-design.md`

---

## 1. Global constraints (apply to every phase)

- **Flutter 3.47.1 / Dart 3.13.1.** `pubspec.lock` is committed. Do not bump the
  SDK or a dependency as a side effect of feature work.
- **Package boundaries — enforced by `test/architecture_test.dart`, not by discipline:**
  - `nimbus_domain` MUST NOT depend on `flutter`, `drift`, `sqlite3`,
    `flutter_riverpod`, `nimbus_data`, or `nimbus_design`.
  - `nimbus_data` MUST NOT depend on `flutter`, `flutter_riverpod`,
    `path_provider`, or `nimbus_design`. It is pure Dart and receives its
    database path by injection.
  - `nimbus_design` MUST NOT depend on `drift`, `sqlite3`, or `nimbus_data`.
  - `app` may depend on all three.
  - If a phase needs a new dependency in a package, it updates the architecture
    test in the same commit and states why in the message.
- **Money is always `int` minor units.** `double` must never represent money
  anywhere. (Tracker quantities are `double` — that is deliberate, and the only
  place a non-integer numeric is allowed.)
- **Dates:** `occurred_at_utc` (epoch ms, UTC) **plus** `local_date_key`
  (`int`, `yyyymmdd`, local Gregorian). Period boundaries are computed in the
  *active calendar*, then converted to a `DateKey` range. Never do calendar
  math in SQL.
- **Every table carries** `id TEXT PRIMARY KEY` (UUIDv7), `created_at INTEGER`,
  `updated_at INTEGER`, `deleted_at INTEGER NULL`.
- **Every query filters `deleted_at IS NULL`** through the one shared helper.
  A query that forgets this is a data-correctness bug, not a style issue.
- **Locales:** `fa` (RTL, primary) and `en` (LTR). Every user-facing string goes
  through ARB localization. No hardcoded UI text, ever.
- **No `print`. No swallowed exceptions. No hardcoded fallback that masks a
  config error.** Lints enforce the first two; review enforces the third.
- **The app must function completely with the VPS unreachable.** Anything
  server-side is a convenience that degrades silently and is never on a
  critical path.
- **TDD order is mandatory:** failing test → observe the failure → minimal
  implementation → observe the pass → broader suite → commit.

---

## 2. Schema version registry

Drift migrations are numbered and stepwise. Two branches that both bump
`schemaVersion` from *N* to *N+1* produce a **broken migration on merge** —
one of the two steps silently disappears. Ranges are therefore reserved up
front so parallel phases never contend for the same number.

| Phase | Reserved | Used | Tables added |
|---|---|---|---|
| 0 — Foundation | v1 | **v1** | settings, categories, tags, payment_methods, transactions, transaction_tags |
| 1 — Expenses | v2–v9 | — | (none expected; Phase 0 creates what Phase 1 needs) |
| 2 — Capture | v10–v19 | — | captured_messages, message_templates, merchant_rules |
| 3 — Analytics | v20–v29 | **v20** | saved_views |
| 4 — Trackers | v30–v39 | — | trackers, tracker_entries |
| 5 — Goals | v40–v49 | — | goals, goal_period_results |
| 6 — Outside the app | v50–v59 | — | (none expected) |
| 7 — Backup | v60–v69 | — | (none expected) |
| 8 — Release | v70–v79 | — | (none expected) |

**Update the "Used" column in the same commit that bumps the version.** This
table is the registry; a version not written here does not exist.

### The schema lock

Reserved ranges prevent *number* collisions. They do not prevent two branches
from editing `app_database.dart` and the schema snapshot directory at once —
that conflict is textual and painful.

**Protocol: a schema change is a serialization point.**

1. Before writing feature code, the phase lands its migration **alone**, in one
   small commit on `main`: the new table files, the `schemaVersion` bump, the
   migration step, the exported schema snapshot, a migration test, and this
   registry row.
2. Every other active branch immediately rebases onto that commit.
3. Only then does feature work diverge again.

Taking the lock costs minutes. Skipping it costs an afternoon of untangling a
migration chain, and the failure mode is a *silently* skipped migration on a
user's device — the worst kind.

---

## 3. File ownership

Parallel phases stay mergeable by owning disjoint directories. A phase may
freely create, modify, and delete anything it owns; it must not modify another
phase's files without saying so explicitly in the commit message.

| Path | Owner |
|---|---|
| `packages/nimbus_domain/lib/src/{money,calendar,entitlements}/**` | Phase 0 |
| `packages/nimbus_domain/lib/src/parsing/**` | Phase 2 |
| `packages/nimbus_domain/lib/src/analytics/**` | Phase 3 |
| `packages/nimbus_domain/lib/src/trackers/**` | Phase 4 |
| `packages/nimbus_domain/lib/src/goals/**` | Phase 5 |
| `packages/nimbus_data/lib/src/{database,tree}/**` | Phase 0 |
| `packages/nimbus_data/lib/src/tables/**` | the phase that created each table (see registry) |
| `packages/nimbus_data/lib/src/capture/**` | Phase 2 |
| `packages/nimbus_data/lib/src/analytics/**` | Phase 3 |
| `packages/nimbus_data/lib/src/backup/**` | Phase 7 |
| `packages/nimbus_design/**` | Phase 1 (tokens land with the first screens) |
| `app/lib/features/{transactions,categories,tags,payment_methods,onboarding,settings}/**` | Phase 1 |
| `app/lib/features/capture/**` | Phase 2 |
| `app/lib/features/{analytics,dashboard}/**` | Phase 3 |
| `app/lib/features/trackers/**` | Phase 4 |
| `app/lib/features/goals/**` | Phase 5 |
| `app/lib/features/notifications/**` | Phase 6 |
| `app/lib/features/backup/**` | Phase 7 |
| `app/android/**/capture/**` | Phase 2 |
| `app/android/**/widget/**` | Phase 6 |

### Shared files — the four real collision points

These cannot be owned by one phase, so they get rules that make git's
line-based merge succeed instead of conflict:

1. **Package barrels** (`lib/nimbus_domain.dart`, `lib/nimbus_data.dart`) —
   one `export` per line, alphabetically sorted, no grouping comments. Two
   phases appending different lines then merge cleanly.
2. **ARB files** (`app/lib/l10n/app_{en,fa}.arb`) — JSON, so keys appended at
   the same position *do* conflict. Each phase prefixes its keys with its
   feature name (`analyticsEmptyTitle`, `captureTeachHint`) and inserts them in
   alphabetical position. Conflicts become one line and obvious.
3. **Route registry** — no central `switch`. Each feature exposes its own
   `routes.dart`; the app router composes the list. Adding a feature adds one
   line.
4. **Providers** — no central provider file. Each feature owns its providers
   next to its code.

Whoever merges second resolves. The rules above are what keep that to seconds.

---

## 4. Branches, worktrees, tags

- One branch per phase: `phase/<N>-<slug>` (e.g. `phase/3-analytics`).
- Parallel phases get **separate git worktrees**, so two sessions never share a
  working directory or a build cache:

  ```bash
  git worktree add ../nimbustats-p3 -b phase/3-analytics main
  ```

  Cost to know before choosing this: each worktree carries its own
  `.dart_tool/`, `build/`, and Gradle output — budget a few GB and one slow
  first build per worktree.
- **Per-commit rollback tags:** before implementing, tag the parent commit
  `pre-<commit-slug>`. Reverting is then `git checkout <tag>`.
- **Phase gate tags:** a phase ends by tagging `phase-<N>-complete`. This tag is
  how a later phase *verifies* its prerequisites rather than trusting a
  checkbox:

  ```bash
  git tag --list 'phase-*-complete'
  ```

  Two phases split into halves that land separately (2A/2B and 4a/4b) also tag
  the first half — `phase-2a-complete`, `phase-4a-complete` — because another
  phase gates on it.
- Merge to `main` fast-forward where possible. Never force-push `main`.
- Commit messages: `type: summary` (`feat:`, `fix:`, `test:`, `chore:`,
  `docs:`), and the body explains **why**, not what.

---

## 5. Definition of done (every phase)

A phase is not done until all of these pass. No exceptions, no "I will fix it
in the next phase."

```bash
dart analyze --fatal-infos                 # clean
dart test test/architecture_test.dart      # boundaries intact
cd packages/nimbus_domain && dart test     # green
cd packages/nimbus_data   && dart test     # green, incl. migration tests
cd app && flutter test                     # green
```

Plus:

- [ ] Every new user-facing string exists in both `app_en.arb` and `app_fa.arb`.
- [ ] Every new screen works in RTL and LTR, with Persian and Latin numerals.
- [ ] Every new screen implements its `empty`, `loading`, `error`, and
      `populated` states — not just the happy path.
- [ ] Accessibility: dynamic type, contrast, and screen-reader labels on every
      new interactive element.
- [ ] The schema registry above is updated if a version was consumed.
- [ ] The status board in `docs/phases/README.md` is updated.
- [ ] `git tag phase-<N>-complete`.

---

## 6. Context budget for a phase session

The reason these briefs exist. A session executing a phase reads:

1. `docs/phases/CONVENTIONS.md` (this file)
2. `docs/phases/phase-<N>-<slug>.md` (its own brief)
3. The spec sections its brief names — **not the whole spec**
4. The source files its brief names under "Interfaces consumed"

**Do not read other phases' briefs or plans.** They are exactly the context
this structure exists to keep out. If a phase genuinely needs something from a
neighbouring phase, that thing belongs in its own brief under "Interfaces
consumed" — add it there rather than reading across.

At kickoff, expand the brief into a step-by-step TDD plan with
`superpowers:writing-plans`, saved to
`docs/superpowers/plans/YYYY-MM-DD-nimbustats-phase-<N>-<slug>.md`. The brief
fixes *what and why*; the plan fixes *how*, against the code that actually
exists by then.
