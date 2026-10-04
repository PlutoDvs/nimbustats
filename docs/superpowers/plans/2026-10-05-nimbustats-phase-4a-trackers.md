# Phase 4a — Trackers: CRUD and entry — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Log non-money things — cigarettes, water, gym, sleep — in one tap, from a Trackers tab. The four tracker types, a manager, a detail screen with history and entry edit/delete with undo, and a timer that survives the app being killed.

**Architecture:**
- **Schema v30** adds `trackers` and `tracker_entries`. A partial unique index makes "done" once per day. A nullable `timer_started_at_utc` column holds a running timer, one per tracker.
- **Domain value types** live in `nimbus_domain/lib/src/trackers/`.
- **DAOs** live in a new Phase-4-owned `nimbus_data/lib/src/trackers/`. They return domain types, so the app never sees drift rows.
- **`TrackerRepository`** (app) is the single write path. It reads time through an injectable `TrackerClock`.
- **Screens** live in `app/lib/features/trackers/`: the tab (a fourth nav destination), the manager and the detail screen. They share one `TrackerActionButton` and one `TrackerLogger`, so a tap means the same thing everywhere.
- **No aggregation beyond a one-day DAO `SUM … GROUP BY tracker_id`**: 4b replaces it with `QuerySpec`.

**Tech Stack:** Flutter 3.47.1 / Dart 3.13.1, Riverpod 3.4.2, go_router 17.5.0, drift 2.34.3 (+ drift_dev 2.34.5), sqlite3 3.5.2, intl 0.20.3.

**Spec:** `docs/superpowers/specs/2026-10-04-trackers-4a-design.md` — read it first; this plan argues from it. The brief is `docs/phases/phase-4-trackers.md` (4a only), and the conventions are in `docs/phases/CONVENTIONS.md`.

## Global Constraints

**Toolchain and scope**
- Flutter 3.47.1 / Dart 3.13.1, with `pubspec.lock` committed. No SDK or dependency changes.
- **Schema.** Phase 4 owns v30–v39, and this plan takes **v30** only.
- **Owns:**
  - `packages/nimbus_domain/lib/src/trackers/**`;
  - `packages/nimbus_data/lib/src/tables/{trackers,tracker_entries}_table.dart`;
  - `packages/nimbus_data/lib/src/trackers/**` (new; the ownership row is added in Task 3);
  - `app/lib/features/trackers/**`.
- **Must not touch:** `transactions/`, `analytics/`, `capture/` or `goals/`.
- **Touches to other owners' files.** Each task names them, and its commit message says so (CONVENTIONS §3):
  - `app_database.dart` and `database_test.dart` (Phase 0);
  - `saved_views_test.dart` (Phase 3);
  - `nimbus_design`'s `icon_picker.dart` (Phase 1);
  - `app_shell.dart`, `app_router.dart` and `app_shell_navigation_test.dart`;
  - `ux_rules_test.dart`;
  - the shared ARBs and barrels;
  - `CONVENTIONS.md`, the design spec and the brief.

**Data rules**
- **Money is never `double`.** `tracker_entries.value` is the one deliberate `REAL`, with the comment at the column saying so.
- Every query filters `deleted_at IS NULL`.
- `local_date_key` is computed **at write time**, from the device's local date, and is never recomputed on read.

**Strings**
- Every user-facing string goes in **both** `app/lib/l10n/app_en.arb` and `app_fa.arb`.
  - Keys are prefixed `tracker`, except `navTrackers` beside the other `nav*` keys.
  - The Persian value never equals the English one (`test/localization_test.dart`).
  - Regenerate with `cd app && flutter gen-l10n`; the generated files are committed.
- ARB files are **CRLF** on disk, sorted case-insensitively and stored with literal (unescaped) characters. Add keys only through the helper `arb_add.py` (Task 5, Step 1), never by hand.
- **No `int` placeholders.** Every number reaches a string already formatted by `TrackerFormat`, as a `String` placeholder.
  - **Why:** gen_l10n's number formatting follows the *strings'* locale, while the app's digits follow the *settings* locale (`localeProvider`, default `fa`). One formatter keeps them from disagreeing.

**UI rules**
- **No confirmation dialogs** (`showDialog`, `AlertDialog`); `app/test/ux_rules_test.dart` fails on them. Destructive actions use `nimbusUndoSnackBar`. `showModalBottomSheet`, `showDatePicker` and `showTimePicker` are allowed.
- **Package boundaries:**
  - Presentation code never touches a DAO.
  - `app` never imports `drift` or `sqlite3`.
  - App tests read through the repository, or `db.customStatement` for failure triggers.
- **Colours.** No raw `Color(0x…)` in `app/lib`. Preset colours come from `NimbusColors.categorySwatches`, and `Color(tracker.color)` is fine.
- **Lints:**
  - `unawaited_futures` is an **error**;
  - `dart analyze --fatal-infos` must be clean;
  - use `onReorderItem`, never the deprecated `onReorder`.
- **Digits follow settings.** The app's default settings locale is `fa`, so numbers render in **Persian digits even when a widget test pumps `locale: Locale('en')`**. A test asserting Latin digits must call `useEnglishDigits(db)` first (Task 5 fixture).
- **Interaction:**
  - Tap targets are at least `NimbusTokens.minTapTarget` (48).
  - Haptics: `lightImpact` on counter and quantity; `mediumImpact` on boolean and timer start/stop.
  - No spinner on any save.

**File editing**
- Edit files with the Write/Edit tools, or with Python scripts written to the scratchpad.
- **Never** use Bash heredocs or `printf` for content containing backslashes: Git Bash collapses `\\`, and that once turned a regex `\b` into a backspace and made a test assertion dead.

### Commit routine (every task)

1. **Branch.**
   - Task 1: `git switch main && git switch -c feat/schema-v30`.
   - Every later task: `git switch phase/4-trackers && git switch -c <branch named in the task>`.
2. **Write the task's tests and run them.** Confirm they fail **for the stated reason**. A compile error counts only when it names the missing symbol.
3. **Tag the parent:** `git tag pre-<slug>`, while nothing of the task is committed. These tags stay local and are never pushed.
4. **Implement.** Run the task's tests until they are green.
5. **Run the full gate from the repo root, all green.**
   - Baseline before this plan: architecture 4, `nimbus_domain` 251, `nimbus_data` 171, `app` 340. Task 1 records the `nimbus_design` count.
   - Commands:
     ```bash
     dart analyze --fatal-infos
     dart test test/architecture_test.dart
     (cd packages/nimbus_domain && dart test)
     (cd packages/nimbus_data && dart test)
     (cd packages/nimbus_design && flutter test --no-pub)
     (cd app && flutter test --no-pub)
     ```
   - `--no-pub` is required because pub.dev returns 403 on the current VPN exit.
   - When running one test file, give `flutter test` an **absolute** path.
   - A first run after edits occasionally fails while "loading" a file. Re-run once before treating it as real.
6. **Commit.** `git add` the task's files and commit with the message given. The body ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
7. **Merge.**
   - Task 1: `git switch main && git merge --ff-only feat/schema-v30 && git switch -c phase/4-trackers`.
   - Every later task: `git switch phase/4-trackers && git merge --ff-only <branch>`.
   - Nothing is pushed until the operator asks.

## Review Focus

These are the input classes the spec implies but no spec test exercises, most likely first. Each has a pinning test in the task named.

1. **An undo or an edit that would put a second live "done" on one day.** For example: un-done Gym, mark it done again, then tap the first snackbar's Undo. The result must be `DayWrite.dayAlreadyDone` and a calm message, not a unique-constraint crash. Pinned in Task 3 (DAO) and Task 10 (UI).
2. **A timer stopped under a second after starting, or with the device clock set back before its start.** No zero- or negative-second entry is written. The timer clears and the user is told (`TimerDiscarded`). Pinned in Tasks 2, 4 and 8.
3. **Editing only an entry's note after flying to another timezone.** The entry must stay on the day it was logged. `local_date_key` is recomputed only when the time changes. Pinned in Task 4.
4. **Amounts typed in Persian or Arabic-Indic digits, with `٫` or `/` as the decimal point.** `۱٫۵`, `۲/۵` and `1,250` must parse; `0`, `-1`, `1e3` and `NaN` must be refused. Pinned in Task 2 (parser) and Task 7 (sheet).
5. **A tracker screen left open across midnight, or resumed the next morning.** Today's totals must move to the new day. Pinned in Task 5.

## Decisions taken in this plan (beyond the design)

Each is a small, reasoned change to the spec, named here so a reviewer can reject it explicitly.

1. **`idx_tracker_entries_day` is `(local_date_key, tracker_id)`,** not the design's `(tracker_id, local_date_key)`.
   - **Why:** its reader is today's totals, every tracker for one day grouped by tracker. A tracker-first index cannot seek on the day.
   - Task 3's plan test proves the seek and the absence of a temp B-tree. Task 1 corrects the design doc.
2. **The DAOs live in `packages/nimbus_data/lib/src/trackers/`,** a new Phase-4-owned directory, rather than inside Phase 0's `app_database.dart`. That file gains only two `late final` fields. Task 3 adds the ownership row.
3. **Commit order.**
   - DAOs and repository are two tasks (3, 4), because each is separately reviewable.
   - The habit icons arrive with the presets in Task 5, which need them, instead of with the manager.
   - "Create your own" and the tab's manage button arrive with the manager in Task 9, so no button ever leads nowhere.
4. **Result types are prefixed** (`EntryLogged`, `TimerStarted`, `TimerStopped`, …), because they are exported through the shared domain barrel. Bare `Started` or `Logged` would collide easily.
5. **Stopping a timer within a second logs nothing** (`TimerDiscarded`): a 0:00 entry is noise, not data.
6. **The empty tab's presets are multi-select, with one "Start tracking" button.** The empty state disappears after the first creation, so tap-to-create-one would let a user pick only one preset.
7. **The manager list is reversed like the tab.** In both, the first tracker sits nearest the thumb, so dragging a row down in the manager moves it down on the tab.
8. **The timer-stop snackbar names the session, not today's total** ("Sleep · 7:30 logged"). An entry stamped at its start can belong to yesterday, so "today" could be false.
9. **`TrackerRepository.update` replaces the design's `updateAppearance`, `updateUnit` and `updatePerTapValue`.** It is one UPDATE statement, so an edit is never half-applied.
10. **`TrackerClock` is new.** The app reads `DateTime.now()` directly elsewhere. Trackers need a testable instant and a testable timezone, for the timer, the midnight rollover and the timezone rule.

## File map

**nimbus_domain** (`packages/nimbus_domain/lib/src/trackers/`)

| File | Contents | Task |
|---|---|---|
| `tracker_type.dart` | `TrackerType` | 1 |
| `tracker.dart` | `Tracker` | 2 |
| `tracker_entry.dart` | `TrackerEntry` | 2 |
| `running_timer.dart` | `RunningTimer` | 2 |
| `tracker_values.dart` | `TrackerValues`: per-type semantics, validation, amount parsing | 2 |
| `tracker_results.dart` | `LogResult`, `TimerStartResult`, `TimerStopResult`, `DayWrite` | 2 |
| `lib/nimbus_domain.dart` | barrel, six export lines | 1, 2 |

**nimbus_data** (`packages/nimbus_data/`)

| File | Contents | Task |
|---|---|---|
| `lib/src/tables/trackers_table.dart`, `lib/src/tables/tracker_entries_table.dart` | the two tables | 1 |
| `lib/src/database/app_database.dart` | v30 step; DAO fields | 1, 3 |
| `lib/src/trackers/trackers_dao.dart`, `lib/src/trackers/tracker_entries_dao.dart` | the DAOs | 3 |
| `drift_schemas/drift_schema_v30.json`, `test/generated/*` | generated | 1 |
| `lib/nimbus_data.dart` | barrel, two export lines | 3 |

**app** (`app/lib/features/trackers/`)

| Path | Files | Task |
|---|---|---|
| `data/` | `tracker_clock.dart`, `tracker_draft.dart`, `tracker_entry_page.dart`, `tracker_repository.dart` | 4 |
| `data/` | `tracker_presets.dart` | 5 |
| `application/` | `tracker_providers.dart` | 5, extended in 9 and 10 |
| `application/` | `tracker_format.dart` | 5 |
| `application/` | `tracker_history_controller.dart` | 10 |
| `presentation/` | `trackers_screen.dart` | 5 |
| `presentation/` | `tracker_manager_screen.dart` | 9 |
| `presentation/` | `tracker_detail_screen.dart` | 10 |
| `presentation/widgets/` | `tracker_tile.dart`, `tracker_today_text.dart`, `tracker_presets_empty.dart`, `tracker_day_rollover.dart`, `tracker_write.dart` | 5 |
| `presentation/widgets/` | `tracker_action_button.dart`, `tracker_logger.dart` | 6 |
| `presentation/widgets/` | `tracker_amount_sheet.dart` | 7 |
| `presentation/widgets/` | `tracker_elapsed_text.dart` | 8 |
| `presentation/widgets/` | `tracker_editor_sheet.dart` | 9 |
| `presentation/widgets/` | `tracker_entry_sheet.dart`, `tracker_duration_fields.dart`, `tracker_duration_sheet.dart` | 10 |
| `routes.dart` | the feature's routes | 5, 9, 10 |

Shared files outside the feature:
- `app/lib/bootstrap/app_shell.dart` and `app/lib/bootstrap/app_router.dart` (Tasks 5, 9).
- `packages/nimbus_design/lib/src/widgets/icon_picker.dart` (Task 5).
- The ARBs and generated localizations.

**Tests**

| Path | Files | Task |
|---|---|---|
| `packages/nimbus_domain/test/trackers/` | `tracker_values_test.dart`, `running_timer_test.dart`, `tracker_value_types_test.dart` | 2 |
| `packages/nimbus_data/test/` | `migration_test.dart` (rewritten), `database_test.dart` | 1 |
| `packages/nimbus_data/test/analytics/` | `saved_views_test.dart` | 1 |
| `packages/nimbus_data/test/trackers/` | `support/tracker_rows.dart`, `trackers_dao_test.dart`, `tracker_entries_dao_test.dart`, `timer_persistence_test.dart` | 3 |
| `app/test/features/trackers/` | `support/tracker_fixture.dart` | 4, extended in 5 and 6 |
| `app/test/features/trackers/` | `tracker_repository_test.dart` | 4 |
| `app/test/features/trackers/` | `tracker_format_test.dart`, `tracker_presets_test.dart`, `trackers_screen_test.dart` | 5 |
| `app/test/features/trackers/` | `tracker_entry_test.dart` | 6 |
| `app/test/features/trackers/` | `tracker_quantity_test.dart` | 7 |
| `app/test/features/trackers/` | `tracker_timer_test.dart` | 8 |
| `app/test/features/trackers/` | `tracker_manager_screen_test.dart` | 9 |
| `app/test/features/trackers/` | `tracker_detail_screen_test.dart` | 10 |
| `app/test/` | `ux_rules_test.dart` | 4 |
| `app/test/bootstrap/` | `app_shell_navigation_test.dart` | 5 |

---

### Task 1: Schema v30 — trackers and their entries (the schema lock)

Branch `feat/schema-v30`, slug `schema-v30`. Lands on **`main`** alone (CONVENTIONS §2), then `phase/4-trackers` is cut from it.

**Files:**
- Create: `packages/nimbus_domain/lib/src/trackers/tracker_type.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (one export line)
- Create: `packages/nimbus_data/lib/src/tables/trackers_table.dart`
- Create: `packages/nimbus_data/lib/src/tables/tracker_entries_table.dart`
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` (imports, `tables:`, `schemaVersion`, `onUpgrade`)
- Generated: `lib/src/database/app_database.g.dart`, `drift_schemas/drift_schema_v30.json`, `test/generated/schema_v30.dart`, `test/generated/schema.dart`
- Rewrite: `packages/nimbus_data/test/migration_test.dart`
- Modify: `packages/nimbus_data/test/database_test.dart:13-18`, `packages/nimbus_data/test/analytics/saved_views_test.dart:64-66`
- Modify: `docs/phases/CONVENTIONS.md` (registry row), `docs/superpowers/specs/2026-08-20-nimbustats-design.md:194-197`, `docs/phases/phase-4-trackers.md` (data model delta), `docs/superpowers/specs/2026-10-04-trackers-4a-design.md` (the day index)

**Interfaces:**
- Produces:
  - `enum TrackerType { counter, boolean, quantity, duration }`, exported from `package:nimbus_domain/nimbus_domain.dart`.
  - drift tables `db.trackers` (row class `TrackerRow`, companion `TrackersCompanion`) and `db.trackerEntries` (row `TrackerEntryRow`, companion `TrackerEntriesCompanion`).
  - Index getters `idxTrackersLive`, `idxTrackerEntriesDay`, `idxTrackerEntriesHistory`, `idxTrackerEntriesOncePerDay`.
  - `TrackerRow` fields:
    `id, createdAt, updatedAt, deletedAt, name, iconKey, color (int), type (TrackerType), unit (String?), perTapValue (double?), archived (bool), sortOrder (int), timerStartedAtUtc (int?)`.
  - `TrackerEntryRow` fields:
    `id, createdAt, updatedAt, deletedAt, trackerId, value (double), occurredAtUtc (int), localDateKey (DateKey), note (String?), oncePerDay (bool)`.

- [ ] **Step 1: Record the `nimbus_design` baseline**

Run: `cd packages/nimbus_design && flutter test --no-pub`
Expected: all pass. Write the count into this plan's commit routine as the baseline, replacing "Task 1 records the `nimbus_design` count".

- [ ] **Step 2: Write the failing tests**

Replace `packages/nimbus_data/test/migration_test.dart` entirely. The v21-era tests keep their meaning but now migrate to v30:

```dart
import 'package:drift_dev/api/migrations_native.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:test/test.dart';

import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  // The point of a migration test is not that the upgrade runs -- it is that
  // the schema it produces is identical to the one a new install creates.
  // A migration that half-works leaves two populations of users on subtly
  // different schemas, and the divergence surfaces phases later.
  for (final from in [1, 20, 21]) {
    test('a v$from database upgrades to v30 and matches a fresh install',
        () async {
      final db = AppDatabase(await verifier.startAt(from));
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, 30);
    });
  }

  test('a view saved under v20 covers one month after the upgrade', () async {
    // Written with raw SQL against the v20 schema, as an installed v20 app
    // would have left it.
    final schema = await verifier.schemaAt(20);
    schema.rawDatabase.execute(
      'INSERT INTO saved_views (id, name, spec_json, chart_type, pinned, '
      'sort_order, created_at, updated_at) '
      "VALUES ('old', 'Old view', '{}', 'breakdown', 1, 0, 0, 0)",
    );
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 30);

    final row = await db
        .customSelect(
            "SELECT period_type, period_count FROM saved_views WHERE id = 'old'")
        .getSingle();
    expect(row.read<String>('period_type'), 'month');
    expect(row.read<int>('period_count'), 1);
  });

  test('a database upgraded from v1 takes a view through the DAO', () async {
    // Validating the shape is not the same as proving the table works.
    final db = AppDatabase(await verifier.startAt(1));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 30);

    await db.savedViewsDao.create([
      (
        id: 'after-migration',
        name: 'Still works',
        spec: const QuerySpec(
            filters: QueryFilters(),
            groupBy: GroupByNone(),
            aggregate: Aggregate.sum),
        period: ViewPeriod(PeriodType.month, 1),
        chart: SavedViewChart.breakdown,
      ),
    ]);

    expect((await db.savedViewsDao.watchPinned().first).single,
        isA<SavedView>());
  });

  group('an upgraded v21 database enforces one live "done" per day', () {
    // The once-per-day index is a correctness rule, not a speed-up. A device
    // that upgraded without it could log "done" twice and every streak in 4b
    // would be wrong -- so it is proven on the upgraded path, not only on a
    // fresh install.
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(await verifier.startAt(21));
      await verifier.migrateAndValidate(db, 30);
      await db.customStatement(
        'INSERT INTO trackers (id, name, icon_key, color, type, created_at, '
        "updated_at) VALUES ('gym', 'Gym', 'fitness_center', 0, 'boolean', "
        '0, 0)',
      );
    });
    tearDown(() => db.close());

    Future<void> insert(String id, {int day = 20261005, bool once = true}) =>
        db.customStatement(
          'INSERT INTO tracker_entries (id, tracker_id, value, '
          'occurred_at_utc, local_date_key, once_per_day, created_at, '
          "updated_at) VALUES (?, 'gym', 1.0, 0, ?, ?, 0, 0)",
          [id, day, once ? 1 : 0],
        );

    test('a second live done on the same day is refused', () async {
      await insert('first');
      await expectLater(insert('second'), throwsA(isA<SqliteException>()));
    });

    test('a soft-deleted done does not block a new one', () async {
      await insert('first');
      await db.customStatement(
          "UPDATE tracker_entries SET deleted_at = 1 WHERE id = 'first'");
      await insert('second');
    });

    test('another day, and rows without the flag, are unaffected', () async {
      await insert('monday');
      await insert('tuesday', day: 20261006);
      await insert('plain-1', once: false);
      await insert('plain-2', once: false);
    });
  });
}
```

In `packages/nimbus_data/test/database_test.dart`, replace the version test (lines 13–18):

```dart
  test('opens at schema version 30', () async {
    // Phase 3 took v20 and v21, Phase 4 v30. Ranges are reserved per phase,
    // so this number jumps rather than increments; see the registry in
    // CONVENTIONS.md.
    expect(db.schemaVersion, 30);
    await db.customSelect('SELECT 1').get();
  });
```

In `packages/nimbus_data/test/analytics/saved_views_test.dart`, replace lines 64–66:

```dart
  test('the schema version is 30', () async {
    expect(db.schemaVersion, 30);
  });
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_data && dart test test/migration_test.dart test/database_test.dart test/analytics/saved_views_test.dart`

Expected: FAIL.
- The migration tests fail with `MissingSchemaException` for version 30: the generated helper only knows 1, 20 and 21.
- The once-per-day group fails at its `setUp` the same way.
- The two version tests fail with `Expected: <30> Actual: <21>`.

- [ ] **Step 4: Tag the rollback target**

Run: `git tag pre-schema-v30`

- [ ] **Step 5: Create `TrackerType`**

`packages/nimbus_domain/lib/src/trackers/tracker_type.dart`:

```dart
/// What a tracker counts.
///
/// Fixed when the tracker is created. An entry's value means something
/// different under each type -- one cigarette, a day done, 2.5 litres, 5400
/// seconds -- so changing the type afterwards would silently reinterpret every
/// entry already logged.
///
/// Stored by name: reordering these values is free, renaming one is a
/// migration.
enum TrackerType { counter, boolean, quantity, duration }
```

Append to `packages/nimbus_domain/lib/nimbus_domain.dart`, after the last `src/prediction/` line:

```dart
export 'src/trackers/tracker_type.dart';
```

- [ ] **Step 6: Create the two tables**

`packages/nimbus_data/lib/src/tables/trackers_table.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../database/columns.dart';

/// Something the user counts that is not money: cigarettes, water, gym days,
/// sleep.
///
/// The row class is named explicitly: drift would otherwise generate one
/// called `Tracker`, which is the domain value type the DAO returns.
///
/// `idx_trackers_live` is partial because every reader asks only for live
/// trackers, archived or not, in the user's order.
@DataClassName('TrackerRow')
@TableIndex.sql('CREATE INDEX idx_trackers_live ON trackers '
    '(archived, sort_order) WHERE deleted_at IS NULL')
class Trackers extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get iconKey => text()();
  IntColumn get color => integer()();
  TextColumn get type => textEnum<TrackerType>()();

  /// Free text, quantity trackers only: `L`, `pages`, `لیتر`.
  TextColumn get unit => text().nullable()();

  /// What one tap logs on a quantity tracker, and required for one. Null for
  /// every other type, whose taps log 1 or start a timer.
  RealColumn get perTapValue => real().nullable()();

  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Epoch ms of the running timer's start; duration trackers only, null when
  /// no timer runs.
  ///
  /// A column rather than a table or an open entry row: it holds at most one
  /// start per tracker by construction -- the brief's "one running timer per
  /// tracker", enforced by the schema instead of the UI. It is written the
  /// moment the timer starts, so the timer survives the process being killed;
  /// elapsed time is always now minus this, never a value held in memory.
  IntColumn get timerStartedAtUtc => integer().nullable()();
}
```

`packages/nimbus_data/lib/src/tables/tracker_entries_table.dart`:

```dart
import 'package:drift/drift.dart';

import '../database/columns.dart';
import '../database/converters.dart';
import 'trackers_table.dart';

/// One logged increment.
///
/// Five cigarettes are five rows with five timestamps, never a daily total:
/// that is what makes time-of-day patterns free in 4b, and collapsing to a
/// total would be a one-way loss.
///
/// The three indexes:
/// - `idx_tracker_entries_day` leads with the date, because its main reader
///   is today's totals -- every tracker's entries for one day, grouped by
///   tracker.
/// - `idx_tracker_entries_history` serves the detail screen's newest-first
///   keyset pages.
/// - `idx_tracker_entries_once_per_day` is the boolean rule: one live "done"
///   per tracker per day, so a fast double-tap cannot log it twice.
///
/// A partial index can only test this table's own columns, and the type lives
/// on `trackers`. So the repository copies "this tracker is boolean" onto each
/// entry as [oncePerDay]. The type is fixed at creation, so the copy cannot
/// drift from it.
@DataClassName('TrackerEntryRow')
@TableIndex(
    name: 'idx_tracker_entries_day', columns: {#localDateKey, #trackerId})
@TableIndex(name: 'idx_tracker_entries_history', columns: {
  #trackerId,
  IndexedColumn(#occurredAtUtc, orderBy: OrderingMode.desc),
  IndexedColumn(#id, orderBy: OrderingMode.desc),
})
@TableIndex.sql('CREATE UNIQUE INDEX idx_tracker_entries_once_per_day '
    'ON tracker_entries (tracker_id, local_date_key) '
    'WHERE once_per_day = 1 AND deleted_at IS NULL')
class TrackerEntries extends Table with BaseColumns {
  TextColumn get trackerId => text().references(Trackers, #id)();

  /// What this entry logs: 1 for a counter or a boolean, the amount for a
  /// quantity, whole seconds for a duration.
  ///
  /// The one deliberate `double` in this project -- 2.5 litres is a real
  /// quantity. It is NOT a precedent for money, which is always `int` minor
  /// units (see `MoneyConverter`). A reader reaching for `real()` on an amount
  /// column should stop here.
  RealColumn get value => real()();

  IntColumn get occurredAtUtc => integer()();

  /// Local Gregorian yyyymmdd, computed when the entry is written from the
  /// device's local date at that moment. Never recomputed on read: an entry
  /// logged before a flight belongs to the day it was logged on.
  IntColumn get localDateKey => integer().map(const DateKeyConverter())();

  TextColumn get note => text().nullable()();

  /// True on a boolean tracker's entries; the once-per-day index tests it.
  BoolColumn get oncePerDay => boolean().withDefault(const Constant(false))();
}
```

- [ ] **Step 7: Register the tables and write the migration step**

In `packages/nimbus_data/lib/src/database/app_database.dart`:

1. Add two imports beside the other table imports:
   ```dart
   import '../tables/tracker_entries_table.dart';
   import '../tables/trackers_table.dart';
   ```
2. Append `Trackers,` and `TrackerEntries,` to the `@DriftDatabase(tables: [...])` list, after `SavedViews,`.
3. Change `int get schemaVersion => 21;` to `int get schemaVersion => 30;`.
4. In `onUpgrade`, after the closing brace of the existing `if (from < 20) {...} else if (from < 21) {...}` chain, add a separate `if`:

```dart
          // v21 -> v30: Phase 4 adds trackers and their entries. New tables
          // only, so every older version takes this same step, after the
          // saved-views chain above.
          if (from < 30) {
            await m.createTable(trackers);
            await m.createTable(trackerEntries);
            // As with saved_views: createTable leaves the indexes behind, and
            // the once-per-day index is a correctness rule rather than a
            // speed-up -- an upgraded device without it could log "done"
            // twice where a fresh install cannot.
            await m.create(idxTrackersLive);
            await m.create(idxTrackerEntriesDay);
            await m.create(idxTrackerEntriesHistory);
            await m.create(idxTrackerEntriesOncePerDay);
          }
```

- [ ] **Step 8: Generate code, the snapshot and the test schemas**

```bash
cd packages/nimbus_data
dart run build_runner build --delete-conflicting-outputs
grep -n "late final Index idxTracker" lib/src/database/app_database.g.dart
dart run drift_dev schema dump lib/src/database/app_database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated/
```

Expected:
- The `grep` prints four lines, naming `idxTrackersLive`, `idxTrackerEntriesDay`, `idxTrackerEntriesHistory` and `idxTrackerEntriesOncePerDay`. If drift named the `.sql` indexes differently, use the generated names in Step 7 and record the difference in the commit body.
- `drift_schemas/drift_schema_v30.json` and `test/generated/schema_v30.dart` exist.
- `test/generated/schema.dart` lists `const [1, 20, 21, 30]`.

- [ ] **Step 9: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_data && dart test test/migration_test.dart test/database_test.dart test/analytics/saved_views_test.dart`
Expected: PASS. That is eight migration tests (three upgrade paths, two v20 and v1 tests, three once-per-day tests) plus the two version tests.

**Mutation check.**
1. Comment out `await m.create(idxTrackerEntriesOncePerDay);`.
2. Re-run `migration_test.dart`. Expected: the v1, v20 and v21 validations FAIL on a missing index, and "a second live done on the same day is refused" FAILS.
3. Restore the line.

- [ ] **Step 10: Update the registry and the docs**

`docs/phases/CONVENTIONS.md`, the registry row:
- old: `| 4 — Trackers | v30–v39 | — | trackers, tracker_entries |`
- new: `| 4 — Trackers | v30–v39 | **v30** | trackers, tracker_entries |`

`docs/superpowers/specs/2026-08-20-nimbustats-design.md`. Replace the two table paragraphs (from the line starting `` **`trackers`** `` through the line ending `` `note?`. ``) with:

```markdown
**`trackers`** — `name`, `icon_key`, `color`, `type` (counter|boolean|quantity|duration), `unit?`,
`per_tap_value?` (what one tap logs on a quantity tracker), `archived`, `sort_order`,
`timer_started_at_utc?` (a running timer's persisted start: one per tracker, survives process death).
**`tracker_entries`** — `tracker_id`, `value REAL`, `occurred_at_utc`, `local_date_key`, `note?`,
`once_per_day` (copied from a boolean tracker, so a partial unique index allows one live "done" a day).
```

Leave the next line, "Per-increment timestamps mean…", untouched.

`docs/phases/phase-4-trackers.md`. In "Data model delta (schema v30)", replace the two bullets with:

```markdown
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
```

`docs/superpowers/specs/2026-10-04-trackers-4a-design.md`, under "Indexes":
- old: ``- `idx_tracker_entries_day` on `(tracker_id, local_date_key)` — today's totals``
- new: ``- `idx_tracker_entries_day` on `(local_date_key, tracker_id)` — today's totals``

Change the continuation line `  and the day's entries.` to:

```markdown
  and the day's entries. Date first, because today's totals read every
  tracker for one day (changed in the implementation plan).
```

- [ ] **Step 11: Run the full gate**

Run the six commands in the commit routine. Expected: all green, and `nimbus_data` is up by the new migration tests.

- [ ] **Step 12: Commit and land on `main`**

```bash
git add packages/nimbus_domain/lib/src/trackers/tracker_type.dart packages/nimbus_domain/lib/nimbus_domain.dart \
  packages/nimbus_data/lib/src/tables/trackers_table.dart packages/nimbus_data/lib/src/tables/tracker_entries_table.dart \
  packages/nimbus_data/lib/src/database/app_database.dart packages/nimbus_data/lib/src/database/app_database.g.dart \
  packages/nimbus_data/drift_schemas/drift_schema_v30.json packages/nimbus_data/test/generated/ \
  packages/nimbus_data/test/migration_test.dart packages/nimbus_data/test/database_test.dart \
  packages/nimbus_data/test/analytics/saved_views_test.dart \
  docs/phases/CONVENTIONS.md docs/phases/phase-4-trackers.md \
  docs/superpowers/specs/2026-08-20-nimbustats-design.md docs/superpowers/specs/2026-10-04-trackers-4a-design.md \
  docs/superpowers/plans/2026-10-05-nimbustats-phase-4a-trackers.md
git commit -m "$(cat <<'EOF'
feat(schema): v30 -- trackers and their entries

Takes the schema lock (CONVENTIONS §2). This commit carries only:
- the two table files and the TrackerType enum they store;
- the version bump and the migration step;
- the v30 snapshot and the migration tests;
- the registry row.
It lands on main before any tracker feature code.

Three columns go beyond the brief, each because a rule has to hold at
the data layer rather than in the UI:
- trackers.timer_started_at_utc holds a running timer's start. It
  survives a killed process and holds one start per tracker by
  construction.
- tracker_entries.once_per_day lets a partial unique index allow one
  live "done" per boolean tracker per day. A partial index can only
  test its own table's columns.
- trackers.per_tap_value is what one tap logs on a quantity tracker.

idx_tracker_entries_day leads with local_date_key, not tracker_id as
the 4a design had it. Its reader is today's totals, every tracker for
one day grouped by tracker, which a tracker-first index cannot seek.
The design doc is corrected here.

The upgraded path is proven to refuse a second live "done": the index
is a correctness rule, not a speed-up.

Touches other owners' files, as the lock requires:
- app_database.dart (Phase 0);
- the schema-version assertions in database_test.dart (Phase 0) and
  saved_views_test.dart (Phase 3);
- the CONVENTIONS registry, the design spec's table definitions and
  the Phase 4 brief.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git switch main && git merge --ff-only feat/schema-v30 && git switch -c phase/4-trackers
```

The heredoc here is safe: the message contains no backslashes. If the plan file is already committed on `main` (see the handoff), leave it out of `git add`.

---

### Task 2: Domain — tracker value types and value semantics

Branch `feat/tracker-domain`, slug `tracker-domain`.

**Files:**
- Create: `packages/nimbus_domain/lib/src/trackers/tracker.dart`, `tracker_entry.dart`, `running_timer.dart`, `tracker_values.dart`, `tracker_results.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (five export lines)
- Test: `packages/nimbus_domain/test/trackers/tracker_values_test.dart`, `running_timer_test.dart`, `tracker_value_types_test.dart`

**Interfaces:**
- Consumes: `TrackerType` (Task 1); `DateKey` (`calendar/date_key.dart`); `Digits` (`money/digits.dart`).
- Produces (all exported from `package:nimbus_domain/nimbus_domain.dart`):
  - Value types:
    - `Tracker({required String id, required String name, required String iconKey, required int color, required TrackerType type, String? unit, double? perTapValue, required bool archived, required int sortOrder, DateTime? timerStartedAtUtc})`, with `RunningTimer? get runningTimer` and value equality.
    - `TrackerEntry({required String id, required String trackerId, required double value, required DateTime occurredAtUtc, required DateKey localDateKey, String? note})`, with value equality.
    - `RunningTimer(DateTime startedAtUtc)`, with `Duration elapsed(DateTime nowUtc)`. It throws `ArgumentError` for a non-UTC start.
  - `TrackerValues` (static methods):
    - `perTap(TrackerType, {double? perTapValue}) → double?`;
    - `isValid(TrackerType, double) → bool`;
    - `isDone(double total) → bool`;
    - `secondsOf(Duration) → double`;
    - `durationOf(double seconds) → Duration`;
    - `checkDefinition(TrackerType, {String? unit, double? perTapValue})`, which throws `ArgumentError`;
    - `parseAmount(String) → double?`.
  - Result types:
    - `sealed class LogResult`: `EntryLogged(TrackerEntry entry)` | `AlreadyDoneToday()`.
    - `sealed class TimerStartResult`: `TimerStarted(RunningTimer timer)` | `TimerAlreadyRunning()`.
    - `sealed class TimerStopResult`: `TimerStopped(TrackerEntry entry)` | `TimerNotRunning()` | `TimerDiscarded()`.
    - `enum DayWrite { written, dayAlreadyDone }`.

- [ ] **Step 1: Write the failing tests**

`packages/nimbus_domain/test/trackers/tracker_values_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('perTap', () {
    test('a counter and a boolean log exactly one', () {
      expect(TrackerValues.perTap(TrackerType.counter), 1.0);
      expect(TrackerValues.perTap(TrackerType.boolean), 1.0);
    });

    test('a quantity logs its per-tap amount', () {
      expect(
          TrackerValues.perTap(TrackerType.quantity, perTapValue: 0.25), 0.25);
    });

    test('a quantity without a per-tap amount is a bug, not a zero', () {
      expect(() => TrackerValues.perTap(TrackerType.quantity),
          throwsArgumentError);
    });

    test('a duration tap logs nothing: it starts or stops the timer', () {
      expect(TrackerValues.perTap(TrackerType.duration), isNull);
    });
  });

  group('isValid', () {
    test('counter and boolean entries are exactly one', () {
      for (final type in [TrackerType.counter, TrackerType.boolean]) {
        expect(TrackerValues.isValid(type, 1), isTrue, reason: '$type');
        expect(TrackerValues.isValid(type, 2), isFalse, reason: '$type');
        expect(TrackerValues.isValid(type, 0), isFalse, reason: '$type');
      }
    });

    test('a quantity is any finite amount above zero', () {
      expect(TrackerValues.isValid(TrackerType.quantity, 2.5), isTrue);
      expect(TrackerValues.isValid(TrackerType.quantity, 0), isFalse);
      expect(TrackerValues.isValid(TrackerType.quantity, -1), isFalse);
      expect(TrackerValues.isValid(TrackerType.quantity, double.nan), isFalse);
      expect(TrackerValues.isValid(TrackerType.quantity, double.infinity),
          isFalse);
    });

    test('a duration is whole seconds, at least one', () {
      expect(TrackerValues.isValid(TrackerType.duration, 5400), isTrue);
      expect(TrackerValues.isValid(TrackerType.duration, 1), isTrue);
      expect(TrackerValues.isValid(TrackerType.duration, 0), isFalse);
      expect(TrackerValues.isValid(TrackerType.duration, 1.5), isFalse);
    });
  });

  test('a boolean total above zero reads as done', () {
    expect(TrackerValues.isDone(1), isTrue);
    expect(TrackerValues.isDone(0), isFalse);
  });

  group('durations', () {
    test('an entry holds whole seconds, rounded down', () {
      // A timer stopped at 59.9 seconds logs 59, never a second it did not
      // run.
      expect(
          TrackerValues.secondsOf(
              const Duration(seconds: 59, milliseconds: 900)),
          59.0);
    });

    test('a stored value reads back as a duration', () {
      expect(TrackerValues.durationOf(5400),
          const Duration(hours: 1, minutes: 30));
    });
  });

  group('checkDefinition', () {
    test('a quantity needs a positive per-tap amount; its unit is optional',
        () {
      TrackerValues.checkDefinition(TrackerType.quantity, perTapValue: 0.25);
      TrackerValues.checkDefinition(TrackerType.quantity,
          unit: 'L', perTapValue: 0.25);
      expect(() => TrackerValues.checkDefinition(TrackerType.quantity),
          throwsArgumentError);
      expect(
          () => TrackerValues.checkDefinition(TrackerType.quantity,
              perTapValue: 0),
          throwsArgumentError);
    });

    test('only a quantity has a unit or a per-tap amount', () {
      for (final type in [
        TrackerType.counter,
        TrackerType.boolean,
        TrackerType.duration,
      ]) {
        TrackerValues.checkDefinition(type);
        expect(() => TrackerValues.checkDefinition(type, unit: 'L'),
            throwsArgumentError,
            reason: '$type');
        expect(() => TrackerValues.checkDefinition(type, perTapValue: 1),
            throwsArgumentError,
            reason: '$type');
      }
    });
  });

  group('parseAmount', () {
    // Persian keyboards, the Arabic-Indic set and copy-paste all reach this
    // field. Refusing them would turn a correct amount into a "wrong amount"
    // error the user cannot fix.
    const accepted = {
      '2.5': 2.5,
      '۲٫۵': 2.5,
      '۲/۵': 2.5,
      '٢٫٥': 2.5,
      '1,250': 1250.0,
      '۱٬۲۵۰': 1250.0,
      ' 3 ': 3.0,
      '.5': 0.5,
      '2.': 2.0,
    };
    accepted.forEach((input, value) {
      test('reads "$input" as $value', () {
        expect(TrackerValues.parseAmount(input), value);
      });
    });

    for (final input in [
      '',
      '0',
      '0.0',
      '-1',
      'abc',
      '1e3',
      'NaN',
      'Infinity',
      '2.5.1',
      '.',
    ]) {
      test('refuses "$input"', () {
        expect(TrackerValues.parseAmount(input), isNull);
      });
    }
  });
}
```

`packages/nimbus_domain/test/trackers/running_timer_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  test('elapsed is now minus the stored start', () {
    final timer = RunningTimer(DateTime.utc(2026, 10, 4, 23, 50));
    expect(timer.elapsed(DateTime.utc(2026, 10, 5, 7, 20)),
        const Duration(hours: 7, minutes: 30));
  });

  test('a timer rebuilt from its stored start reads the same', () {
    // What a process death does: the timer is rebuilt from the persisted
    // epoch milliseconds, and nothing about it may change.
    final start = DateTime.utc(2026, 10, 4, 23, 50);
    final before = RunningTimer(start);
    final after = RunningTimer(DateTime.fromMillisecondsSinceEpoch(
        start.millisecondsSinceEpoch,
        isUtc: true));
    final now = DateTime.utc(2026, 10, 5, 1);

    expect(after, before);
    expect(after.elapsed(now), before.elapsed(now));
  });

  test('a timezone change does not warp it: it is between two instants', () {
    final timer = RunningTimer(DateTime.utc(2026, 10, 5, 9));
    final nowUtc = DateTime.utc(2026, 10, 5, 10);
    expect(timer.elapsed(nowUtc.toLocal()), const Duration(hours: 1));
  });

  test('a clock set back past the start reads zero, never negative', () {
    final timer = RunningTimer(DateTime.utc(2026, 10, 5, 9));
    expect(timer.elapsed(DateTime.utc(2026, 10, 5, 8)), Duration.zero);
  });

  test('the start must be UTC', () {
    expect(() => RunningTimer(DateTime(2026, 10, 5, 9)), throwsArgumentError);
  });
}
```

`packages/nimbus_domain/test/trackers/tracker_value_types_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

Tracker water({DateTime? timerStartedAtUtc}) => Tracker(
      id: 'water',
      name: 'Water',
      iconKey: 'water_drop',
      color: 0xFF1565C0,
      type: TrackerType.quantity,
      unit: 'L',
      perTapValue: 0.25,
      archived: false,
      sortOrder: 0,
      timerStartedAtUtc: timerStartedAtUtc,
    );

void main() {
  test('trackers with the same fields are equal', () {
    expect(water(), water());
    expect(water().hashCode, water().hashCode);
  });

  test('a tracker with no stored start has no running timer', () {
    expect(water().runningTimer, isNull);
  });

  test('a stored start is the running timer', () {
    final start = DateTime.utc(2026, 10, 5, 9);
    expect(water(timerStartedAtUtc: start).runningTimer, RunningTimer(start));
  });

  test('entries with the same fields are equal; a different note is not', () {
    TrackerEntry entry({String? note}) => TrackerEntry(
          id: 'e1',
          trackerId: 'water',
          value: 0.25,
          occurredAtUtc: DateTime.utc(2026, 10, 5, 9),
          localDateKey: const DateKey(20261005),
          note: note,
        );

    expect(entry(), entry());
    expect(entry().hashCode, entry().hashCode);
    expect(entry(note: 'after lunch'), isNot(entry()));
  });
}
```

- [ ] **Step 2: Run the tests to confirm RED**

Run: `cd packages/nimbus_domain && dart test test/trackers/`
Expected: FAIL to compile, with `Undefined name 'TrackerValues'`, `'RunningTimer' isn't a type` and `'Tracker' isn't a type`.

- [ ] **Step 3: Tag the rollback target**

Run: `git tag pre-tracker-domain`

- [ ] **Step 4: Implement**

`packages/nimbus_domain/lib/src/trackers/running_timer.dart`:

```dart
import 'package:meta/meta.dart';

/// A duration tracker's timer while it runs: when it started, and nothing
/// else.
///
/// The start is persisted the moment the timer starts (the tracker's
/// `timer_started_at_utc`), and elapsed time is always computed from it. So a
/// process death, a reboot or a timezone change cannot lose or warp a running
/// timer: nothing about it is held only in memory.
@immutable
final class RunningTimer {
  RunningTimer(this.startedAtUtc) {
    if (!startedAtUtc.isUtc) {
      throw ArgumentError.value(startedAtUtc, 'startedAtUtc', 'must be UTC');
    }
  }

  final DateTime startedAtUtc;

  /// Time since the start, never negative: a device clock set back past the
  /// start reads as zero rather than as a negative session.
  Duration elapsed(DateTime nowUtc) {
    final elapsed = nowUtc.toUtc().difference(startedAtUtc);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  @override
  bool operator ==(Object other) =>
      other is RunningTimer && other.startedAtUtc == startedAtUtc;

  @override
  int get hashCode => startedAtUtc.hashCode;

  @override
  String toString() => 'RunningTimer($startedAtUtc)';
}
```

`packages/nimbus_domain/lib/src/trackers/tracker.dart`:

```dart
import 'package:meta/meta.dart';

import 'running_timer.dart';
import 'tracker_type.dart';

/// A tracker: what it is called, how it looks, what it counts.
///
/// [type] is fixed at creation (see [TrackerType]). [unit] and [perTapValue]
/// belong to quantity trackers only, and [timerStartedAtUtc] to duration
/// trackers only. The repository refuses any other combination when writing,
/// so this type does not re-check rows it is built from.
@immutable
final class Tracker {
  const Tracker({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.color,
    required this.type,
    this.unit,
    this.perTapValue,
    required this.archived,
    required this.sortOrder,
    this.timerStartedAtUtc,
  });

  final String id;
  final String name;

  /// A `nimbusIcons` key.
  final String iconKey;

  /// ARGB, as categories and payment methods store it.
  final int color;
  final TrackerType type;
  final String? unit;
  final double? perTapValue;
  final bool archived;
  final int sortOrder;

  /// The persisted start of a running timer, or null when none runs.
  final DateTime? timerStartedAtUtc;

  RunningTimer? get runningTimer {
    final start = timerStartedAtUtc;
    return start == null ? null : RunningTimer(start);
  }

  @override
  bool operator ==(Object other) =>
      other is Tracker &&
      other.id == id &&
      other.name == name &&
      other.iconKey == iconKey &&
      other.color == color &&
      other.type == type &&
      other.unit == unit &&
      other.perTapValue == perTapValue &&
      other.archived == archived &&
      other.sortOrder == sortOrder &&
      other.timerStartedAtUtc == timerStartedAtUtc;

  @override
  int get hashCode => Object.hash(id, name, iconKey, color, type, unit,
      perTapValue, archived, sortOrder, timerStartedAtUtc);

  @override
  String toString() => 'Tracker($id, $name, ${type.name})';
}
```

`packages/nimbus_domain/lib/src/trackers/tracker_entry.dart`:

```dart
import 'package:meta/meta.dart';

import '../calendar/date_key.dart';

/// One logged increment of a tracker.
///
/// [value]'s meaning depends on the tracker's type (see `TrackerValues`).
/// [localDateKey] is the local day the entry was written on, not one derived
/// from [occurredAtUtc] on read: an entry logged before a flight keeps its day.
@immutable
final class TrackerEntry {
  const TrackerEntry({
    required this.id,
    required this.trackerId,
    required this.value,
    required this.occurredAtUtc,
    required this.localDateKey,
    this.note,
  });

  final String id;
  final String trackerId;
  final double value;
  final DateTime occurredAtUtc;
  final DateKey localDateKey;
  final String? note;

  @override
  bool operator ==(Object other) =>
      other is TrackerEntry &&
      other.id == id &&
      other.trackerId == trackerId &&
      other.value == value &&
      other.occurredAtUtc == occurredAtUtc &&
      other.localDateKey == localDateKey &&
      other.note == note;

  @override
  int get hashCode =>
      Object.hash(id, trackerId, value, occurredAtUtc, localDateKey, note);

  @override
  String toString() => 'TrackerEntry($id, $trackerId, $value, $localDateKey)';
}
```

`packages/nimbus_domain/lib/src/trackers/tracker_values.dart`:

```dart
import '../money/digits.dart';
import 'tracker_type.dart';

/// What an entry's value means under each [TrackerType], in one place.
///
/// | type     | one entry's value          | a day's total         |
/// |----------|----------------------------|-----------------------|
/// | counter  | 1                          | the sum, a count      |
/// | boolean  | 1, at most one live a day  | done when above zero  |
/// | quantity | the amount                 | the sum               |
/// | duration | whole seconds              | the sum               |
abstract final class TrackerValues {
  /// What one tap logs, or null for a duration tracker: a tap on one starts or
  /// stops its timer instead.
  ///
  /// Throws [ArgumentError] for a quantity tracker without a per-tap amount.
  /// The repository refuses to create one, so meeting one here is a bug, and
  /// logging a guessed amount would hide it.
  static double? perTap(TrackerType type, {double? perTapValue}) =>
      switch (type) {
        TrackerType.counter || TrackerType.boolean => 1.0,
        TrackerType.quantity => perTapValue ??
            (throw ArgumentError.value(perTapValue, 'perTapValue',
                'a quantity tracker logs its per-tap amount')),
        TrackerType.duration => null,
      };

  /// Whether [value] may be stored as one entry of a [type] tracker.
  static bool isValid(TrackerType type, double value) => switch (type) {
        TrackerType.counter || TrackerType.boolean => value == 1.0,
        TrackerType.quantity => value.isFinite && value > 0,
        TrackerType.duration =>
          value.isFinite && value >= 1 && value == value.roundToDouble(),
      };

  /// A boolean tracker's day total, read as done.
  static bool isDone(double total) => total > 0;

  /// A duration entry's value: whole seconds, rounded down, so a timer stopped
  /// at 59.9 seconds logs 59 -- never a second it did not run.
  static double secondsOf(Duration duration) =>
      duration.inSeconds.toDouble();

  /// A duration entry's value read back as a [Duration].
  static Duration durationOf(double seconds) =>
      Duration(seconds: seconds.round());

  /// Checks a tracker's definition before it is stored.
  ///
  /// A quantity tracker needs a valid per-tap amount, and its unit is
  /// optional. Every other type has neither. Throws [ArgumentError] otherwise:
  /// the editor validates for the user, so a bad definition reaching here is a
  /// caller's bug.
  static void checkDefinition(
    TrackerType type, {
    String? unit,
    double? perTapValue,
  }) {
    if (type == TrackerType.quantity) {
      if (perTapValue == null || !isValid(TrackerType.quantity, perTapValue)) {
        throw ArgumentError.value(perTapValue, 'perTapValue',
            'a quantity tracker needs a per-tap amount above zero');
      }
      return;
    }
    if (unit != null) {
      throw ArgumentError.value(
          unit, 'unit', 'only a quantity tracker has a unit');
    }
    if (perTapValue != null) {
      throw ArgumentError.value(perTapValue, 'perTapValue',
          'only a quantity tracker has a per-tap amount');
    }
  }

  static final _decimal = RegExp(r'^(\d+(\.\d*)?|\.\d+)$');

  /// Reads an amount the user typed, or null unless it is a finite number
  /// above zero.
  ///
  /// Accepts:
  /// - Latin, Persian and Arabic-Indic digits;
  /// - `.`, the Arabic decimal separator `٫` (U+066B) or `/` for the decimal
  ///   point (`/` is how many Persian speakers type one);
  /// - `,` and `٬` (U+066C) as grouping, which is dropped.
  ///
  /// Matched against a strict pattern before parsing, because `double.parse`
  /// alone would accept `1e3`, `NaN` and `Infinity`.
  static double? parseAmount(String input) {
    final normalised = Digits.toLatin(input.trim())
        .replaceAll('٫', '.')
        .replaceAll('/', '.')
        .replaceAll('٬', '')
        .replaceAll(',', '');
    if (!_decimal.hasMatch(normalised)) return null;
    final value = double.parse(normalised);
    return value.isFinite && value > 0 ? value : null;
  }
}
```

`packages/nimbus_domain/lib/src/trackers/tracker_results.dart`:

```dart
import 'running_timer.dart';
import 'tracker_entry.dart';

/// What logging an entry did.
///
/// Expected outcomes are results, not exceptions. A second "done" on the same
/// day is a normal double-tap, and a caller has to handle it, not catch it.
sealed class LogResult {
  const LogResult();
}

final class EntryLogged extends LogResult {
  const EntryLogged(this.entry);

  final TrackerEntry entry;

  @override
  String toString() => 'EntryLogged($entry)';
}

/// A boolean tracker already holds a live "done" for that day; nothing was
/// written.
final class AlreadyDoneToday extends LogResult {
  const AlreadyDoneToday();

  @override
  String toString() => 'AlreadyDoneToday()';
}

sealed class TimerStartResult {
  const TimerStartResult();
}

final class TimerStarted extends TimerStartResult {
  const TimerStarted(this.timer);

  final RunningTimer timer;
}

/// A timer was already running; its start is unchanged.
final class TimerAlreadyRunning extends TimerStartResult {
  const TimerAlreadyRunning();
}

sealed class TimerStopResult {
  const TimerStopResult();
}

final class TimerStopped extends TimerStopResult {
  const TimerStopped(this.entry);

  final TrackerEntry entry;
}

/// No timer was running -- typically the second tap of a double-tap on stop.
final class TimerNotRunning extends TimerStopResult {
  const TimerNotRunning();
}

/// Stopped under a second after it started, or with the clock set back past
/// its start: the timer is cleared and nothing is logged. A 0:00 entry is
/// noise, not data.
final class TimerDiscarded extends TimerStopResult {
  const TimerDiscarded();
}

/// The outcome of a write that can meet a boolean tracker's once-per-day
/// rule: an edit that moves an entry to another day, or an undo that restores
/// one.
enum DayWrite { written, dayAlreadyDone }
```

In `packages/nimbus_domain/lib/nimbus_domain.dart`, the `src/trackers/` lines become (alphabetical, `tracker.dart` before `tracker_entry.dart` because `.` sorts before `_`):

```dart
export 'src/trackers/running_timer.dart';
export 'src/trackers/tracker.dart';
export 'src/trackers/tracker_entry.dart';
export 'src/trackers/tracker_results.dart';
export 'src/trackers/tracker_type.dart';
export 'src/trackers/tracker_values.dart';
```

- [ ] **Step 5: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_domain && dart test test/trackers/`
Expected: PASS.

**Mutation checks:**
- In `parseAmount`, replace the `_decimal` guard with `final value = double.tryParse(normalised); if (value == null) return null;`. The `1e3`, `NaN` and `Infinity` refusals must FAIL.
- In `RunningTimer.elapsed`, return `elapsed` unclamped. "a clock set back…" must FAIL.

Restore both.

- [ ] **Step 6: Run the full gate**

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add packages/nimbus_domain/lib/src/trackers/ packages/nimbus_domain/lib/nimbus_domain.dart packages/nimbus_domain/test/trackers/
git commit -m "$(cat <<'EOF'
feat(trackers): domain value types and value semantics

Tracker, TrackerEntry and RunningTimer are the interfaces Phases 5 and
6 consume. TrackerValues puts in one place what an entry's value means
under each type: what a tap logs, what is valid, how a definition must
look, and how a typed amount is read.

RunningTimer computes elapsed time from the persisted start and clamps
at zero, so a process death or a clock set backwards can neither lose
a running timer nor produce a negative session.

parseAmount takes Persian and Arabic-Indic digits and `٫` or `/` as
the decimal point, because that is what Persian keyboards produce. It
is matched against a strict pattern first, since double.parse alone
accepts 1e3, NaN and Infinity.

The result types are prefixed (EntryLogged, TimerStarted, ...) because
they travel through the shared domain barrel, where Started or Logged
would collide.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git switch phase/4-trackers && git merge --ff-only feat/tracker-domain
```

The message contains `٫` but no backslash, so the heredoc is safe.

---

### Task 3: DAOs — trackers, entries, timers

Branch `feat/tracker-daos`, slug `tracker-daos`.

**Files:**
- Create: `packages/nimbus_data/lib/src/trackers/trackers_dao.dart`
- Create: `packages/nimbus_data/lib/src/trackers/tracker_entries_dao.dart`
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` (two imports, two `late final` fields)
- Modify: `packages/nimbus_data/lib/nimbus_data.dart` (two export lines)
- Modify: `docs/phases/CONVENTIONS.md` (ownership row), `docs/phases/phase-4-trackers.md` ("Owns" block)
- Test: `packages/nimbus_data/test/trackers/support/tracker_rows.dart`, `trackers_dao_test.dart`, `tracker_entries_dao_test.dart`, `timer_persistence_test.dart`

**Interfaces:**
- Consumes: the Task 1 tables and index names; the Task 2 domain types.
- Produces (exported from `package:nimbus_data/nimbus_data.dart`):
  - Records:
    - `typedef NewTracker = ({String id, String name, String iconKey, int color, TrackerType type, String? unit, double? perTapValue})`;
    - `typedef NewTrackerEntry = ({String id, String trackerId, double value, DateTime occurredAtUtc, DateKey localDateKey, String? note, bool oncePerDay})`;
    - `typedef TrackerEntryCursorRow = ({DateTime occurredAtUtc, String id})`.
  - `db.trackersDao` (`TrackersDao`):
    - `insertAll(List<NewTracker>)`;
    - `byId(String) → Future<Tracker?>` and `watchById(String) → Stream<Tracker?>`;
    - `liveQuery({required bool archived})` and `watchLive({required bool archived}) → Stream<List<Tracker>>`;
    - `updateTracker(String id, {required String name, required String iconKey, required int color, String? unit, double? perTapValue})`;
    - `setArchived(String, bool)` and `reorder(List<String>)`;
    - `startTimer(String id, int startedAtUtcMs) → Future<bool>`;
    - `finishTimer(String id, {required int startedAtUtcMs, required NewTrackerEntry? entry}) → Future<bool>`.
    - Writes to a stale id throw `StateError`.
  - `db.trackerEntriesDao` (`TrackerEntriesDao`):
    - `insertEntry(NewTrackerEntry) → Future<LogResult>` and `byId(String) → Future<TrackerEntry?>`;
    - `updateEntry(String id, {required double value, required DateTime occurredAtUtc, required DateKey localDateKey, required String? note}) → Future<DayWrite>`;
    - `softDelete(String)`;
    - `softDeleteOn(String trackerId, DateKey day) → Future<List<String>>`;
    - `restore(List<String>) → Future<DayWrite>`;
    - `watchDayTotals(DateKey) → Stream<Map<String, double>>` and `dayTotalsQuery(DateKey)`;
    - `historyQuery(String trackerId, {TrackerEntryCursorRow? after, int limit = 40})` and `pageAfter(...) → Future<List<TrackerEntry>>`;
    - `changes() → Stream<void>`.

- [ ] **Step 1: Write the failing tests**

`packages/nimbus_data/test/trackers/support/tracker_rows.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

/// 2026-10-05 09:00 UTC, the instant most rows here are logged at.
final morning = DateTime.utc(2026, 10, 5, 9);
const today = DateKey(20261005);

NewTracker newTracker(
  String id,
  TrackerType type, {
  String? unit,
  double? perTapValue,
}) =>
    (
      id: id,
      name: id,
      iconKey: 'tag',
      color: 0xFF1565C0,
      type: type,
      unit: unit,
      perTapValue: perTapValue,
    );

NewTrackerEntry newEntry(
  String id,
  String trackerId, {
  double value = 1,
  DateTime? at,
  DateKey day = today,
  String? note,
  bool oncePerDay = false,
}) =>
    (
      id: id,
      trackerId: trackerId,
      value: value,
      occurredAtUtc: at ?? morning,
      localDateKey: day,
      note: note,
      oncePerDay: oncePerDay,
    );

/// Live rows for [trackerId], counted in SQL so the test does not lean on the
/// DAO it is checking.
Future<int> liveEntries(AppDatabase db, String trackerId) async {
  final row = await db.customSelect(
    'SELECT COUNT(*) AS n FROM tracker_entries '
    'WHERE tracker_id = ? AND deleted_at IS NULL',
    variables: [Variable.withString(trackerId)],
  ).getSingle();
  return row.read<int>('n');
}

/// The query plan of [query], joined into one string.
Future<String> planOf(AppDatabase db, Query query) async {
  final compiled = query.constructQuery();
  final rows = await db.customSelect(
    'EXPLAIN QUERY PLAN ${compiled.sql}',
    variables: compiled.boundVariables
        .map<Variable<Object>>(
            (v) => v is int ? Variable<int>(v) : Variable<String>('$v'))
        .toList(),
  ).get();
  return rows.map((r) => r.read<String>('detail')).join(' | ');
}
```

`packages/nimbus_data/test/trackers/trackers_dao_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import 'support/tracker_rows.dart';

void main() {
  late AppDatabase db;
  late TrackersDao dao;

  setUp(() {
    db = openTestDatabase();
    dao = db.trackersDao;
  });
  tearDown(() => db.close());

  Future<List<String>> liveIds({bool archived = false}) async =>
      [for (final t in await dao.watchLive(archived: archived).first) t.id];

  test('insertAll round-trips every field as a domain Tracker', () async {
    await dao.insertAll(
        [newTracker('water', TrackerType.quantity, unit: 'L', perTapValue: 0.25)]);

    expect(
      await dao.byId('water'),
      const Tracker(
        id: 'water',
        name: 'water',
        iconKey: 'tag',
        color: 0xFF1565C0,
        type: TrackerType.quantity,
        unit: 'L',
        perTapValue: 0.25,
        archived: false,
        sortOrder: 0,
      ),
    );
  });

  test('insertAll appends after existing trackers, in the order given',
      () async {
    await dao.insertAll([newTracker('a', TrackerType.counter)]);
    await dao.insertAll([
      newTracker('b', TrackerType.boolean),
      newTracker('c', TrackerType.duration),
    ]);

    expect(await liveIds(), ['a', 'b', 'c']);
    expect((await dao.byId('c'))!.sortOrder, 2);
  });

  test('insertAll is one transaction: a bad row inserts none', () async {
    await expectLater(
      dao.insertAll([
        newTracker('ok', TrackerType.counter),
        newTracker('ok', TrackerType.counter), // duplicate primary key
      ]),
      throwsA(anything),
    );
    expect(await liveIds(), isEmpty);
  });

  test('the live lists split archived from unarchived', () async {
    await dao.insertAll([
      newTracker('a', TrackerType.counter),
      newTracker('b', TrackerType.counter),
    ]);
    await dao.setArchived('b', true);

    expect(await liveIds(), ['a']);
    expect(await liveIds(archived: true), ['b']);

    await dao.setArchived('b', false);
    expect(await liveIds(), ['a', 'b']);
  });

  test('reorder makes the given order the stored one', () async {
    await dao.insertAll([
      newTracker('a', TrackerType.counter),
      newTracker('b', TrackerType.counter),
      newTracker('c', TrackerType.counter),
    ]);
    await dao.reorder(['c', 'a', 'b']);
    expect(await liveIds(), ['c', 'a', 'b']);
  });

  test('a write to an unknown tracker says so instead of succeeding',
      () async {
    expect(() => dao.setArchived('nope', true), throwsStateError);
    expect(() => dao.reorder(['nope']), throwsStateError);
    expect(
        () => dao.updateTracker('nope', name: 'x', iconKey: 'tag', color: 0),
        throwsStateError);
  });

  test('updateTracker rewrites appearance and quantity fields in one write',
      () async {
    await dao.insertAll(
        [newTracker('w', TrackerType.quantity, unit: 'L', perTapValue: 0.25)]);
    await dao.updateTracker('w',
        name: 'Water', iconKey: 'water_drop', color: 1, unit: null,
        perTapValue: 0.5);

    final tracker = (await dao.byId('w'))!;
    expect(tracker.name, 'Water');
    expect(tracker.iconKey, 'water_drop');
    expect(tracker.color, 1);
    expect(tracker.unit, isNull);
    expect(tracker.perTapValue, 0.5);
    expect(tracker.type, TrackerType.quantity);
  });

  group('timers', () {
    setUp(() => dao.insertAll([
          newTracker('sleep', TrackerType.duration),
          newTracker('cig', TrackerType.counter),
        ]));

    test('a start is persisted; a second start is refused and changes nothing',
        () async {
      final first = morning.millisecondsSinceEpoch;
      expect(await dao.startTimer('sleep', first), isTrue);
      expect(await dao.startTimer('sleep', first + 5000), isFalse);

      expect((await dao.byId('sleep'))!.timerStartedAtUtc,
          DateTime.fromMillisecondsSinceEpoch(first, isUtc: true));
    });

    test('two racing starts leave exactly one', () async {
      final ms = morning.millisecondsSinceEpoch;
      final results = await Future.wait(
          [dao.startTimer('sleep', ms), dao.startTimer('sleep', ms + 1)]);
      expect(results.where((started) => started), hasLength(1));
    });

    test('a counter cannot start a timer', () async {
      expect(await dao.startTimer('cig', morning.millisecondsSinceEpoch),
          isFalse);
    });

    test('finish clears the start and logs the entry together', () async {
      final ms = morning.millisecondsSinceEpoch;
      await dao.startTimer('sleep', ms);

      expect(
          await dao.finishTimer('sleep',
              startedAtUtcMs: ms,
              entry: newEntry('e1', 'sleep', value: 27000)),
          isTrue);

      expect((await dao.byId('sleep'))!.runningTimer, isNull);
      expect(await liveEntries(db, 'sleep'), 1);
    });

    test('a second finish of the same start logs nothing', () async {
      final ms = morning.millisecondsSinceEpoch;
      await dao.startTimer('sleep', ms);
      await dao.finishTimer('sleep',
          startedAtUtcMs: ms, entry: newEntry('e1', 'sleep', value: 60));

      expect(
          await dao.finishTimer('sleep',
              startedAtUtcMs: ms, entry: newEntry('e2', 'sleep', value: 60)),
          isFalse);
      expect(await liveEntries(db, 'sleep'), 1);
    });

    test('finish without an entry only clears the start', () async {
      final ms = morning.millisecondsSinceEpoch;
      await dao.startTimer('sleep', ms);
      expect(await dao.finishTimer('sleep', startedAtUtcMs: ms, entry: null),
          isTrue);

      expect((await dao.byId('sleep'))!.runningTimer, isNull);
      expect(await liveEntries(db, 'sleep'), 0);
    });

    test('a failed entry insert leaves the timer running', () async {
      // The proof that stop is one transaction: an entry pointing at a
      // missing tracker fails its foreign key, and the clear must roll back
      // with it.
      final ms = morning.millisecondsSinceEpoch;
      await dao.startTimer('sleep', ms);

      await expectLater(
        dao.finishTimer('sleep',
            startedAtUtcMs: ms, entry: newEntry('e1', 'missing', value: 60)),
        throwsA(anything),
      );
      expect((await dao.byId('sleep'))!.runningTimer, isNotNull);
    });
  });

  test("the live list's plan uses idx_trackers_live", () async {
    final plan = await planOf(db, dao.liveQuery(archived: false));
    expect(plan, contains('idx_trackers_live'), reason: 'plan: $plan');
  });
}
```

`packages/nimbus_data/test/trackers/tracker_entries_dao_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import 'support/tracker_rows.dart';

void main() {
  late AppDatabase db;
  late TrackerEntriesDao dao;

  setUp(() async {
    db = openTestDatabase();
    dao = db.trackerEntriesDao;
    await db.trackersDao.insertAll([
      newTracker('cig', TrackerType.counter),
      newTracker('gym', TrackerType.boolean),
      newTracker('yoga', TrackerType.boolean),
      newTracker('water', TrackerType.quantity, perTapValue: 0.25),
    ]);
  });
  tearDown(() => db.close());

  test('insertEntry returns the stored entry', () async {
    final result = await dao.insertEntry(
        newEntry('e1', 'water', value: 2.5, note: 'after lunch'));

    expect(
      (result as EntryLogged).entry,
      TrackerEntry(
        id: 'e1',
        trackerId: 'water',
        value: 2.5,
        occurredAtUtc: morning,
        localDateKey: today,
        note: 'after lunch',
      ),
    );
  });

  group('one live "done" per day', () {
    test('a second done on the same day is refused and writes nothing',
        () async {
      expect(await dao.insertEntry(newEntry('a', 'gym', oncePerDay: true)),
          isA<EntryLogged>());
      expect(await dao.insertEntry(newEntry('b', 'gym', oncePerDay: true)),
          isA<AlreadyDoneToday>());
      expect(await liveEntries(db, 'gym'), 1);
    });

    test('a fast double-tap logs exactly one', () async {
      final results = await Future.wait([
        dao.insertEntry(newEntry('a', 'gym', oncePerDay: true)),
        dao.insertEntry(newEntry('b', 'gym', oncePerDay: true)),
      ]);
      expect(results.whereType<EntryLogged>(), hasLength(1));
      expect(results.whereType<AlreadyDoneToday>(), hasLength(1));
    });

    test('a soft-deleted done no longer holds the day', () async {
      await dao.insertEntry(newEntry('a', 'gym', oncePerDay: true));
      await dao.softDelete('a');
      expect(await dao.insertEntry(newEntry('b', 'gym', oncePerDay: true)),
          isA<EntryLogged>());
    });

    test('the rule is per tracker and per day, and only for flagged rows',
        () async {
      await dao.insertEntry(newEntry('a', 'gym', oncePerDay: true));
      expect(
          await dao.insertEntry(newEntry('b', 'gym',
              oncePerDay: true, day: today.addDays(1))),
          isA<EntryLogged>());
      expect(await dao.insertEntry(newEntry('c', 'yoga', oncePerDay: true)),
          isA<EntryLogged>());
      for (final id in ['d', 'e', 'f']) {
        expect(await dao.insertEntry(newEntry(id, 'cig')), isA<EntryLogged>());
      }
    });

    test('an edit that moves a done onto a done day is refused', () async {
      await dao.insertEntry(newEntry('mon', 'gym', oncePerDay: true));
      await dao.insertEntry(newEntry('tue', 'gym',
          oncePerDay: true, day: today.addDays(1)));

      final result = await dao.updateEntry('tue',
          value: 1, occurredAtUtc: morning, localDateKey: today, note: null);

      expect(result, DayWrite.dayAlreadyDone);
      expect((await dao.byId('tue'))!.localDateKey, today.addDays(1));
    });

    test('an undo onto a day marked done again is refused, all or nothing',
        () async {
      await dao.insertEntry(newEntry('first', 'gym', oncePerDay: true));
      final cleared = await dao.softDeleteOn('gym', today);
      await dao.insertEntry(newEntry('again', 'gym', oncePerDay: true));

      expect(await dao.restore(cleared), DayWrite.dayAlreadyDone);
      expect(await liveEntries(db, 'gym'), 1);
      expect(await dao.byId('first'), isNull);
    });
  });

  test('updateEntry rewrites value, time, day and note', () async {
    await dao.insertEntry(newEntry('e1', 'water', value: 0.25));
    final later = morning.add(const Duration(hours: 2));

    expect(
        await dao.updateEntry('e1',
            value: 0.5,
            occurredAtUtc: later,
            localDateKey: today.addDays(-1),
            note: 'fixed'),
        DayWrite.written);
    expect(
      await dao.byId('e1'),
      TrackerEntry(
        id: 'e1',
        trackerId: 'water',
        value: 0.5,
        occurredAtUtc: later,
        localDateKey: today.addDays(-1),
        note: 'fixed',
      ),
    );
  });

  test('a write to an unknown or deleted entry says so', () async {
    expect(() => dao.softDelete('nope'), throwsStateError);
    expect(
        () => dao.updateEntry('nope',
            value: 1, occurredAtUtc: morning, localDateKey: today, note: null),
        throwsStateError);
    expect(() => dao.restore(['nope']), throwsStateError);
  });

  test('softDeleteOn removes the day and restore brings exactly it back',
      () async {
    await dao.insertEntry(newEntry('a', 'cig'));
    await dao.insertEntry(newEntry('b', 'cig'));
    await dao.insertEntry(newEntry('old', 'cig', day: today.addDays(-1)));

    final cleared = await dao.softDeleteOn('cig', today);
    expect(cleared.toSet(), {'a', 'b'});
    expect(await liveEntries(db, 'cig'), 1);

    expect(await dao.restore(cleared), DayWrite.written);
    expect(await liveEntries(db, 'cig'), 3);
  });

  test("day totals sum each tracker's live entries for that day only",
      () async {
    await dao.insertEntry(newEntry('c1', 'cig'));
    await dao.insertEntry(newEntry('c2', 'cig'));
    await dao.insertEntry(newEntry('c3', 'cig'));
    await dao.softDelete('c3');
    await dao.insertEntry(newEntry('old', 'cig', day: today.addDays(-1)));
    await dao.insertEntry(newEntry('w1', 'water', value: 0.25));
    await dao.insertEntry(newEntry('w2', 'water', value: 0.5));

    expect(await dao.watchDayTotals(today).first, {'cig': 2.0, 'water': 0.75});
    expect(await dao.watchDayTotals(today.addDays(1)).first, isEmpty);
  });

  test('day totals follow writes', () async {
    final totals = dao.watchDayTotals(today);
    final seen = expectLater(
        totals,
        emitsInOrder([
          <String, double>{},
          {'cig': 1.0},
        ]));
    await pumpEventQueue();
    await dao.insertEntry(newEntry('c1', 'cig'));
    await seen;
  });

  group('history pages', () {
    setUp(() async {
      // Five entries; two share a timestamp, so id breaks the tie.
      await dao.insertEntry(newEntry('e1', 'cig', at: morning));
      await dao.insertEntry(newEntry('e2', 'cig', at: morning));
      for (final (i, id) in ['e3', 'e4', 'e5'].indexed) {
        await dao.insertEntry(
            newEntry(id, 'cig', at: morning.add(Duration(minutes: i + 1))));
      }
    });

    test('newest first, continued from a cursor without repeats or gaps',
        () async {
      final first = await dao.pageAfter('cig', limit: 3);
      expect(first.map((e) => e.id), ['e5', 'e4', 'e3']);

      final last = first.last;
      final rest = await dao.pageAfter('cig',
          after: (occurredAtUtc: last.occurredAtUtc, id: last.id), limit: 3);
      expect(rest.map((e) => e.id), ['e2', 'e1']);
    });

    test('a write between two pages neither repeats nor drops a row',
        () async {
      final first = await dao.pageAfter('cig', limit: 2);
      await dao.insertEntry(newEntry('new', 'cig',
          at: morning.add(const Duration(hours: 1))));

      final last = first.last;
      final rest = await dao.pageAfter('cig',
          after: (occurredAtUtc: last.occurredAtUtc, id: last.id), limit: 10);
      expect(rest.map((e) => e.id), ['e3', 'e2', 'e1']);
    });
  });

  test('changes fires on an entry write', () async {
    final fired = expectLater(dao.changes(), emits(anything));
    await dao.insertEntry(newEntry('c1', 'cig'));
    await fired;
  });

  group('query plans', () {
    // Asserted on the plan, not on a stopwatch, so the guarantee survives a
    // fast machine.
    test('day totals seek the day index and need no temp B-tree', () async {
      final plan = await planOf(db, dao.dayTotalsQuery(today));
      expect(plan, contains('idx_tracker_entries_day'), reason: plan);
      expect(plan, isNot(contains('SCAN tracker_entries')), reason: plan);
      expect(plan, isNot(contains('TEMP B-TREE')), reason: plan);
    });

    test('history pages walk the history index in order', () async {
      for (final after in [
        null,
        (occurredAtUtc: morning, id: 'e1'),
      ]) {
        final plan = await planOf(db, dao.historyQuery('cig', after: after));
        expect(plan, contains('idx_tracker_entries_history'), reason: plan);
        expect(plan, isNot(contains('TEMP B-TREE')), reason: plan);
      }
    });
  });
}
```

`packages/nimbus_data/test/trackers/timer_persistence_test.dart`:

```dart
import 'dart:io';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/tracker_rows.dart';

void main() {
  test('a running timer survives the database closing and reopening',
      () async {
    // A killed process, as close as a test gets: the first connection is
    // closed with the timer running, and a fresh one opens the same file.
    // Nothing but the stored start may carry over. The first database is
    // closed before the second opens, so drift never sees two at once.
    final dir = Directory.systemTemp.createTempSync('nimbus_timer_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/nimbus.db';
    final start = DateTime.utc(2026, 10, 4, 20, 30);

    final first = AppDatabase.openAtPath(path);
    await first.trackersDao
        .insertAll([newTracker('sleep', TrackerType.duration)]);
    expect(
        await first.trackersDao
            .startTimer('sleep', start.millisecondsSinceEpoch),
        isTrue);
    await first.close();

    final second = AppDatabase.openAtPath(path);
    addTearDown(second.close);
    final timer = (await second.trackersDao.byId('sleep'))!.runningTimer;

    expect(timer, RunningTimer(start));
    expect(timer!.elapsed(start.add(const Duration(hours: 7, minutes: 30))),
        const Duration(hours: 7, minutes: 30));
  });
}
```

- [ ] **Step 2: Run the tests to confirm RED**

Run: `cd packages/nimbus_data && dart test test/trackers/`
Expected: FAIL to compile, with `Undefined name 'NewTracker'`, `The getter 'trackersDao' isn't defined for the type 'AppDatabase'` and `'TrackerEntriesDao' isn't a type`.

- [ ] **Step 3: Tag the rollback target**

Run: `git tag pre-tracker-daos`

- [ ] **Step 4: Implement `TrackersDao`**

`packages/nimbus_data/lib/src/trackers/trackers_dao.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../database/app_database.dart';
import 'tracker_entries_dao.dart';

/// A tracker as the repository hands it over for insertion.
typedef NewTracker = ({
  String id,
  String name,
  String iconKey,
  int color,
  TrackerType type,
  String? unit,
  double? perTapValue,
});

/// Trackers and their running timers.
///
/// Reads return the domain [Tracker], never drift's row. The app layer may not
/// depend on drift, and this is the one place a row becomes a value.
class TrackersDao {
  TrackersDao(this._db);

  final AppDatabase _db;

  /// Appends [trackers] after every existing one, in the order given, as one
  /// transaction: the presets arrive together or not at all.
  Future<void> insertAll(List<NewTracker> trackers) =>
      _db.transaction(() async {
        final highest = _db.trackers.sortOrder.max();
        final top = await (_db.selectOnly(_db.trackers)..addColumns([highest]))
            .map((row) => row.read(highest))
            .getSingle();
        var next = (top ?? -1) + 1;
        final now = _now();
        for (final tracker in trackers) {
          await _db.into(_db.trackers).insert(TrackersCompanion.insert(
                id: tracker.id,
                name: tracker.name,
                iconKey: tracker.iconKey,
                color: tracker.color,
                type: tracker.type,
                unit: Value(tracker.unit),
                perTapValue: Value(tracker.perTapValue),
                sortOrder: Value(next++),
                createdAt: now,
                updatedAt: now,
              ));
        }
      });

  /// A live tracker, archived or not, or null.
  Future<Tracker?> byId(String id) async {
    final row = await _byId(id).getSingleOrNull();
    return row == null ? null : _toTracker(row);
  }

  Stream<Tracker?> watchById(String id) => _byId(id)
      .watchSingleOrNull()
      .map((row) => row == null ? null : _toTracker(row));

  /// Live trackers in the user's order: the unarchived ones for the tab, or
  /// the archived ones for the manager's section. Exposed so a test can assert
  /// its plan uses `idx_trackers_live`.
  SimpleSelectStatement<$TrackersTable, TrackerRow> liveQuery({
    required bool archived,
  }) =>
      _db.select(_db.trackers)
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.archived.equals(archived))
        ..orderBy([
          (t) => OrderingTerm.asc(t.sortOrder),
          (t) => OrderingTerm.asc(t.id),
        ]);

  Stream<List<Tracker>> watchLive({required bool archived}) =>
      liveQuery(archived: archived)
          .watch()
          .map((rows) => rows.map(_toTracker).toList());

  /// Rewrites a tracker's editable fields in one statement, so an edit is
  /// never half-applied. The type is not among them: it is fixed at creation.
  /// The repository checks that [unit] and [perTapValue] fit the type.
  Future<void> updateTracker(
    String id, {
    required String name,
    required String iconKey,
    required int color,
    String? unit,
    double? perTapValue,
  }) async {
    final written =
        await (_db.update(_db.trackers)..where((t) => t.id.equals(id)))
            .write(TrackersCompanion(
      name: Value(name),
      iconKey: Value(iconKey),
      color: Value(color),
      unit: Value(unit),
      perTapValue: Value(perTapValue),
      updatedAt: Value(_now()),
    ));
    _expectOne(written, id);
  }

  Future<void> setArchived(String id, bool archived) async {
    final written =
        await (_db.update(_db.trackers)..where((t) => t.id.equals(id)))
            .write(TrackersCompanion(
      archived: Value(archived),
      updatedAt: Value(_now()),
    ));
    _expectOne(written, id);
  }

  /// Makes [ids] the stored order: each tracker's position becomes its sort
  /// order. One transaction, so no two trackers ever claim the same slot.
  Future<void> reorder(List<String> ids) => _db.transaction(() async {
        final now = _now();
        for (final (index, id) in ids.indexed) {
          final written =
              await (_db.update(_db.trackers)..where((t) => t.id.equals(id)))
                  .write(TrackersCompanion(
            sortOrder: Value(index),
            updatedAt: Value(now),
          ));
          _expectOne(written, id);
        }
      });

  /// Starts [id]'s timer at [startedAtUtcMs], unless one is already running.
  ///
  /// One conditional UPDATE, `WHERE timer_started_at_utc IS NULL`, so of two
  /// racing starts exactly one writes. That is the brief's "one running timer
  /// per tracker", held by the data layer.
  ///
  /// False when nothing was written: a timer was already running, or [id] is
  /// not a live duration tracker.
  Future<bool> startTimer(String id, int startedAtUtcMs) async {
    final written = await (_db.update(_db.trackers)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.type.equalsValue(TrackerType.duration))
          ..where((t) => t.timerStartedAtUtc.isNull()))
        .write(TrackersCompanion(
      timerStartedAtUtc: Value(startedAtUtcMs),
      updatedAt: Value(_now()),
    ));
    return written == 1;
  }

  /// Ends the timer that started at [startedAtUtcMs] and logs [entry], or
  /// logs nothing when [entry] is null. One transaction, so a timer is never
  /// cleared without its entry or logged while still running.
  ///
  /// Compare-and-clear: the column is cleared only if it still holds
  /// [startedAtUtcMs]. Two racing stops read the same start; the first clears
  /// it and logs, and the second matches nothing and logs nothing.
  ///
  /// False when the timer was no longer running from that start.
  Future<bool> finishTimer(
    String id, {
    required int startedAtUtcMs,
    required NewTrackerEntry? entry,
  }) =>
      _db.transaction(() async {
        final cleared = await (_db.update(_db.trackers)
              ..where((t) => t.id.equals(id))
              ..where((t) => t.timerStartedAtUtc.equals(startedAtUtcMs)))
            .write(TrackersCompanion(
          timerStartedAtUtc: const Value(null),
          updatedAt: Value(_now()),
        ));
        if (cleared != 1) return false;
        if (entry != null) {
          final logged = await _db.trackerEntriesDao.insertEntry(entry);
          if (logged is! EntryLogged) {
            // A duration entry never carries the once-per-day flag, so this
            // is a caller's bug. Throwing rolls the clear back with it.
            throw StateError('a timer entry was refused: $logged');
          }
        }
        return true;
      });

  SimpleSelectStatement<$TrackersTable, TrackerRow> _byId(String id) =>
      _db.select(_db.trackers)
        ..where((t) => t.id.equals(id))
        ..where((t) => t.deletedAt.isNull());

  static Tracker _toTracker(TrackerRow row) {
    final start = row.timerStartedAtUtc;
    return Tracker(
      id: row.id,
      name: row.name,
      iconKey: row.iconKey,
      color: row.color,
      type: row.type,
      unit: row.unit,
      perTapValue: row.perTapValue,
      archived: row.archived,
      sortOrder: row.sortOrder,
      timerStartedAtUtc: start == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
    );
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  /// A write that matched nothing is a caller holding a stale id. Saying so
  /// beats reporting success for an archive that archived nothing.
  static void _expectOne(int written, String id) {
    if (written != 1) throw StateError('no tracker "$id"');
  }
}
```

- [ ] **Step 5: Implement `TrackerEntriesDao`**

`packages/nimbus_data/lib/src/trackers/tracker_entries_dao.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:sqlite3/common.dart' show SqlExtendedError, SqliteException;

import '../database/app_database.dart';

/// An entry as the repository hands it over for insertion. [oncePerDay] is
/// true for a boolean tracker's entries; the repository sets it.
typedef NewTrackerEntry = ({
  String id,
  String trackerId,
  double value,
  DateTime occurredAtUtc,
  DateKey localDateKey,
  String? note,
  bool oncePerDay,
});

/// A keyset cursor into one tracker's history: the last entry a page returned.
typedef TrackerEntryCursorRow = ({DateTime occurredAtUtc, String id});

/// Tracker entries: one row per increment, never a daily total.
class TrackerEntriesDao {
  TrackerEntriesDao(this._db);

  final AppDatabase _db;

  /// Inserts [entry], or reports that its day already holds a live "done".
  ///
  /// The once-per-day index does the deciding, not a read before the write. A
  /// read first would let two fast taps both see "not done" and both write.
  Future<LogResult> insertEntry(NewTrackerEntry entry) async {
    final now = _now();
    try {
      await _db.into(_db.trackerEntries).insert(
            TrackerEntriesCompanion.insert(
              id: entry.id,
              trackerId: entry.trackerId,
              value: entry.value,
              occurredAtUtc: entry.occurredAtUtc.millisecondsSinceEpoch,
              localDateKey: entry.localDateKey,
              note: Value(entry.note),
              oncePerDay: Value(entry.oncePerDay),
              createdAt: now,
              updatedAt: now,
            ),
          );
    } on Object catch (error) {
      if (_isOncePerDayViolation(error)) return const AlreadyDoneToday();
      rethrow;
    }
    final logged = await byId(entry.id);
    if (logged == null) {
      // A row that vanishes between insert and read did not commit, and
      // returning a fabricated entry would let the UI undo something that
      // does not exist.
      throw StateError('tracker entry ${entry.id} was not persisted');
    }
    return EntryLogged(logged);
  }

  /// A live entry, or null.
  Future<TrackerEntry?> byId(String id) async {
    final row = await (_db.select(_db.trackerEntries)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .getSingleOrNull();
    return row == null ? null : _toEntry(row);
  }

  /// Rewrites an entry's value, time, day and note.
  ///
  /// Returns [DayWrite.dayAlreadyDone], writing nothing, when the edit would
  /// put a second live "done" on one day.
  Future<DayWrite> updateEntry(
    String id, {
    required double value,
    required DateTime occurredAtUtc,
    required DateKey localDateKey,
    required String? note,
  }) async {
    try {
      final written = await (_db.update(_db.trackerEntries)
            ..where((t) => t.id.equals(id))
            ..where((t) => t.deletedAt.isNull()))
          .write(TrackerEntriesCompanion(
        value: Value(value),
        occurredAtUtc: Value(occurredAtUtc.millisecondsSinceEpoch),
        localDateKey: Value(localDateKey),
        note: Value(note),
        updatedAt: Value(_now()),
      ));
      _expectOne(written, id);
      return DayWrite.written;
    } on Object catch (error) {
      if (_isOncePerDayViolation(error)) return DayWrite.dayAlreadyDone;
      rethrow;
    }
  }

  Future<void> softDelete(String id) async {
    final now = _now();
    final written = await (_db.update(_db.trackerEntries)
          ..where((t) => t.id.equals(id))
          ..where((t) => t.deletedAt.isNull()))
        .write(TrackerEntriesCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
    _expectOne(written, id);
  }

  /// Soft-deletes [trackerId]'s live entries on [day] and returns their ids,
  /// so an undo restores exactly these. This is a boolean tracker's "not done
  /// any more".
  Future<List<String>> softDeleteOn(String trackerId, DateKey day) =>
      _db.transaction(() async {
        final rows = await (_db.select(_db.trackerEntries)
              ..where((t) => t.trackerId.equals(trackerId))
              ..where((t) => t.localDateKey.equals(day.value))
              ..where((t) => t.deletedAt.isNull()))
            .get();
        final ids = [for (final row in rows) row.id];
        if (ids.isEmpty) return ids;
        final now = _now();
        await (_db.update(_db.trackerEntries)..where((t) => t.id.isIn(ids)))
            .write(TrackerEntriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ));
        return ids;
      });

  /// The undo behind a delete: makes [ids] live again, all of them or none.
  ///
  /// Returns [DayWrite.dayAlreadyDone] when one of them would be a second live
  /// "done" on its day, because the user marked the day done again meanwhile.
  Future<DayWrite> restore(List<String> ids) async {
    try {
      await _db.transaction(() async {
        final now = _now();
        for (final id in ids) {
          final written = await (_db.update(_db.trackerEntries)
                ..where((t) => t.id.equals(id)))
              .write(TrackerEntriesCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ));
          _expectOne(written, id);
        }
      });
      return DayWrite.written;
    } on Object catch (error) {
      if (_isOncePerDayViolation(error)) return DayWrite.dayAlreadyDone;
      rethrow;
    }
  }

  /// Every tracker's total for [day]: one GROUP BY over one day, keyed by
  /// tracker id.
  ///
  /// This is the brief's "today's total from a DAO count", and the only
  /// aggregate in 4a. Anything with a range or another dimension waits for 4b
  /// and goes through `QuerySpec`.
  Stream<Map<String, double>> watchDayTotals(DateKey day) {
    final (:query, :total) = _dayTotals(day);
    final trackerId = _db.trackerEntries.trackerId;
    return query.watch().map((rows) => {
          for (final row in rows) row.read(trackerId)!: row.read(total) ?? 0,
        });
  }

  /// [watchDayTotals]'s statement, so a test can assert its plan.
  JoinedSelectStatement<$TrackerEntriesTable, TrackerEntryRow> dayTotalsQuery(
          DateKey day) =>
      _dayTotals(day).query;

  ({
    JoinedSelectStatement<$TrackerEntriesTable, TrackerEntryRow> query,
    Expression<double> total,
  }) _dayTotals(DateKey day) {
    final entries = _db.trackerEntries;
    final total = entries.value.sum();
    final query = _db.selectOnly(entries)
      ..addColumns([entries.trackerId, total])
      ..where(entries.localDateKey.equals(day.value) &
          entries.deletedAt.isNull())
      ..groupBy([entries.trackerId]);
    return (query: query, total: total);
  }

  /// One tracker's live entries, newest first, after [after].
  ///
  /// Keyset over `(occurred_at_utc DESC, id DESC)`, like the transaction list,
  /// and for the same reasons. Offset pages re-count skipped rows, and they
  /// repeat or drop rows when a write lands between two fetches. On a detail
  /// screen with a quick-log button, that is the normal case.
  ///
  /// Exposed so a test can assert the plan walks
  /// `idx_tracker_entries_history`.
  SimpleSelectStatement<$TrackerEntriesTable, TrackerEntryRow> historyQuery(
    String trackerId, {
    TrackerEntryCursorRow? after,
    int limit = 40,
  }) {
    final query = _db.select(_db.trackerEntries)
      ..where((t) => t.trackerId.equals(trackerId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.occurredAtUtc),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);
    if (after != null) {
      final at = after.occurredAtUtc.millisecondsSinceEpoch;
      query.where((t) =>
          t.occurredAtUtc.isSmallerThanValue(at) |
          (t.occurredAtUtc.equals(at) & t.id.isSmallerThanValue(after.id)));
    }
    return query;
  }

  Future<List<TrackerEntry>> pageAfter(
    String trackerId, {
    TrackerEntryCursorRow? after,
    int limit = 40,
  }) async =>
      [
        for (final row in await historyQuery(trackerId,
                after: after, limit: limit)
            .get())
          _toEntry(row),
      ];

  /// Fires after any write to tracker entries, so a loaded history knows to
  /// reload.
  Stream<void> changes() => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.trackerEntries))
      .map((_) {});

  static TrackerEntry _toEntry(TrackerEntryRow row) => TrackerEntry(
        id: row.id,
        trackerId: row.trackerId,
        value: row.value,
        occurredAtUtc:
            DateTime.fromMillisecondsSinceEpoch(row.occurredAtUtc, isUtc: true),
        localDateKey: row.localDateKey,
        note: row.note,
      );

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  static void _expectOne(int written, String id) {
    if (written != 1) throw StateError('no tracker entry "$id"');
  }
}

/// The once-per-day index refusing a write.
///
/// It is the only unique index on tracker_entries. The primary key's violation
/// has its own code (SQLITE_CONSTRAINT_PRIMARYKEY), so SQLITE_CONSTRAINT_UNIQUE
/// alone identifies this index.
///
/// Drift's remote wrapper is unwrapped too. That is what a database opened on
/// a background isolate throws, so moving the database off the UI isolate
/// cannot turn a double-tap into a crash.
bool _isOncePerDayViolation(Object error) => switch (error) {
      SqliteException(:final extendedResultCode) =>
        extendedResultCode == SqlExtendedError.SQLITE_CONSTRAINT_UNIQUE,
      DriftRemoteException(:final remoteCause) =>
        _isOncePerDayViolation(remoteCause),
      _ => false,
    };
```

- [ ] **Step 6: Wire the DAOs and the barrel**

In `app_database.dart`:

1. Add the imports:
   ```dart
   import '../trackers/tracker_entries_dao.dart';
   import '../trackers/trackers_dao.dart';
   ```
2. After `late final SavedViewsDao savedViewsDao = SavedViewsDao(this);`, add:
   ```dart
     late final TrackersDao trackersDao = TrackersDao(this);
     late final TrackerEntriesDao trackerEntriesDao = TrackerEntriesDao(this);
   ```

In `packages/nimbus_data/lib/nimbus_data.dart`, insert in alphabetical position, after `export 'src/tables/transactions_table.dart';`:

```dart
export 'src/trackers/tracker_entries_dao.dart';
export 'src/trackers/trackers_dao.dart';
```

`trackers_dao.dart` and `app_database.dart` import each other. Dart allows the cycle, and it is what lets the DAO live outside Phase 0's file.

- [ ] **Step 7: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_data && dart test test/trackers/`
Expected: PASS.

**If "day totals seek the day index" fails** because SQLite chose another index, stop: the planner disagrees with Decision 1. Paste the plan into the task report. Do **not** loosen the assertion.

**Mutation checks:**
- In `_isOncePerDayViolation`, return `false` for `SqliteException`. "a second done on the same day is refused" must FAIL with an uncaught `SqliteException`.
- In `finishTimer`, move the entry insert **outside** `_db.transaction` (clear in one call, insert after). "a failed entry insert leaves the timer running" must FAIL.
- In `startTimer`, drop the `timerStartedAtUtc.isNull()` condition. "a second start is refused" must FAIL.

Restore all three.

- [ ] **Step 8: Record ownership**

`docs/phases/CONVENTIONS.md`, §3 table. After the row `` | `packages/nimbus_data/lib/src/analytics/**` | Phase 3 | ``, insert:

```markdown
| `packages/nimbus_data/lib/src/trackers/**` | Phase 4 |
```

`docs/phases/phase-4-trackers.md`, "Owns" block. After the `tracker_entries_table.dart` line, add:

```
packages/nimbus_data/lib/src/trackers/**         tracker DAOs (added in 4a: kept out of app_database.dart)
```

- [ ] **Step 9: Run the full gate**

Expected: all green.

- [ ] **Step 10: Commit**

```bash
git add packages/nimbus_data/lib/src/trackers/ packages/nimbus_data/lib/src/database/app_database.dart \
  packages/nimbus_data/lib/nimbus_data.dart packages/nimbus_data/test/trackers/ \
  docs/phases/CONVENTIONS.md docs/phases/phase-4-trackers.md
git commit -m "$(cat <<'EOF'
feat(trackers): DAOs for trackers, entries and running timers

The data layer holds the rules the brief says the UI must not:
- One live "done" per day: insertEntry leans on the partial unique
  index and turns its violation into AlreadyDoneToday rather than
  reading first, which two fast taps would both pass.
- One running timer: start is a conditional UPDATE.
- Stop: a compare-and-clear on the stored start, plus the entry
  insert, in one transaction. A double-tap logs once, and a failed
  insert leaves the timer running.

Today's totals are one GROUP BY over one day, the brief's "DAO count";
anything with a range waits for 4b's QuerySpec. Its plan, and the
history pages', are asserted.

The DAOs live in a new Phase-4-owned nimbus_data/lib/src/trackers/
directory rather than in Phase 0's app_database.dart, which gains two
fields. Touches app_database.dart and the CONVENTIONS ownership table
to say so.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git switch phase/4-trackers && git merge --ff-only feat/tracker-daos
```

---

### Task 4: `TrackerRepository` — the single write path, and `TrackerClock`

Branch `feat/tracker-repository`, slug `tracker-repository`.

**Files:**
- Create: `app/lib/features/trackers/data/tracker_clock.dart`
- Create: `app/lib/features/trackers/data/tracker_draft.dart`
- Create: `app/lib/features/trackers/data/tracker_entry_page.dart`
- Create: `app/lib/features/trackers/data/tracker_repository.dart`
- Modify: `app/test/ux_rules_test.dart` (two DAO names; Phase 1's test)
- Test: `app/test/features/trackers/support/tracker_fixture.dart`, `app/test/features/trackers/tracker_repository_test.dart`

**Interfaces:**
- Consumes: Task 3 DAOs and records; Task 2 domain types; `Ids.newId()` (`nimbus_data`).
- Produces:
  - `TrackerClock`:
    - constructor `TrackerClock({DateTime Function() nowUtc, DateTime Function(DateTime utc) toLocal, DateTime Function(DateTime wall) fromLocal})`, where every parameter defaults to the system clock;
    - methods `nowUtc()`, `toLocal(DateTime utc)`, `fromLocal(DateTime wall)`, `localDateOf(DateTime utc) → DateKey` and `today() → DateKey`.
  - `TrackerDraft({required String name, required String iconKey, required int color, required TrackerType type, String? unit, double? perTapValue})`.
  - `TrackerEntryCursor({required DateTime occurredAtUtc, required String id})`, with `.of(TrackerEntry)` and `row`.
  - `TrackerEntryPage({required List<TrackerEntry> items, required TrackerEntryCursor? cursor})`, with `hasMore`.
  - `TrackerRepository(TrackersDao, TrackerEntriesDao, TrackerClock)`:
    - Reads:
      - `watchTrackers()` and `watchArchived()` (`Stream<List<Tracker>>`);
      - `watchTracker(id)` (`Stream<Tracker?>`);
      - `watchTotals(DateKey)` (`Stream<Map<String, double>>`);
      - `totalOn(trackerId, DateKey)` (`Future<double>`);
      - `entryChanges()` (`Stream<void>`);
      - `today()` (`DateKey`);
      - `entriesPage(trackerId, {TrackerEntryCursor? after, int limit = 40})` (`Future<TrackerEntryPage>`).
    - Tracker writes:
      - `create(TrackerDraft)` (`Future<Tracker>`) and `createAll(List<TrackerDraft>)` (`Future<List<Tracker>>`);
      - `update(id, {required String name, required String iconKey, required int color, String? unit, double? perTapValue})`;
      - `archive(id)`, `unarchive(id)` and `reorder(List<String>)`.
    - Entry writes:
      - `logEntry(trackerId, {double? value, DateTime? at, String? note})` (`Future<LogResult>`);
      - `clearToday(trackerId)` (`Future<List<String>>`);
      - `startTimer(id)` (`Future<TimerStartResult>`) and `stopTimer(id)` (`Future<TimerStopResult>`);
      - `addDuration(id, Duration, {DateTime? startedAt})` (`Future<LogResult>`);
      - `updateEntry(TrackerEntry)` (`Future<DayWrite>`);
      - `deleteEntry(id)` and `restoreEntries(List<String>)` (`Future<DayWrite>`).
    - Errors:
      - a programming error (wrong type, invalid value, blank name) throws `ArgumentError`;
      - a stale id throws `StateError`.
  - Test fixture:
    - `FakeClock` (`nowUtc`, `offset`, `advance`, `clock`);
    - drafts `cigarettes` (counter), `gym` (boolean), `water` (quantity, `L`, 0.25) and `sleep` (duration);
    - `repositoryFor(AppDatabase, FakeClock)`.

- [ ] **Step 1: Write the failing tests**

`app/test/features/trackers/support/tracker_fixture.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_clock.dart';
import 'package:nimbustats/features/trackers/data/tracker_draft.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';

/// A clock the test moves by hand.
///
/// Starts at 2026-10-05 09:00 UTC, which is 12:30 in Tehran, the default zone
/// here, so "today" is 20261005.
final class FakeClock {
  FakeClock({DateTime? nowUtc, this.offset = tehran})
      : nowUtc = nowUtc ?? DateTime.utc(2026, 10, 5, 9);

  static const tehran = Duration(hours: 3, minutes: 30);
  static const newYork = Duration(hours: -4);

  DateTime nowUtc;

  /// The device's UTC offset. Change it to fly.
  Duration offset;

  void advance(Duration by) => nowUtc = nowUtc.add(by);

  /// Reads this fake's fields on every call, so moving the fake also moves a
  /// clock already handed to a repository or a provider.
  TrackerClock get clock => TrackerClock(
        nowUtc: () => nowUtc,
        toLocal: (utc) => utc.add(offset),
        fromLocal: (wall) => DateTime.utc(wall.year, wall.month, wall.day,
                wall.hour, wall.minute, wall.second)
            .subtract(offset),
      );
}

const cigarettes = TrackerDraft(
    name: 'Cigarettes',
    iconKey: 'smoking_rooms',
    color: 0xFF546E7A,
    type: TrackerType.counter);
const gym = TrackerDraft(
    name: 'Gym',
    iconKey: 'fitness_center',
    color: 0xFF2E7D32,
    type: TrackerType.boolean);
const water = TrackerDraft(
    name: 'Water',
    iconKey: 'water_drop',
    color: 0xFF1565C0,
    type: TrackerType.quantity,
    unit: 'L',
    perTapValue: 0.25);
const sleep = TrackerDraft(
    name: 'Sleep',
    iconKey: 'bedtime',
    color: 0xFF4527A0,
    type: TrackerType.duration);

TrackerRepository repositoryFor(AppDatabase db, FakeClock fake) =>
    TrackerRepository(db.trackersDao, db.trackerEntriesDao, fake.clock);
```

`app/test/features/trackers/tracker_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_draft.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';

import 'support/tracker_fixture.dart';

void main() {
  late AppDatabase db;
  late FakeClock fake;
  late TrackerRepository repo;

  setUp(() {
    db = AppDatabase.openInMemory();
    fake = FakeClock();
    repo = repositoryFor(db, fake);
  });
  tearDown(() => db.close());

  Future<List<TrackerEntry>> entriesOf(String id) async =>
      (await repo.entriesPage(id, limit: 1000)).items;

  group('create', () {
    test('trims the name and drops a blank unit', () async {
      final created = await repo.create(const TrackerDraft(
          name: '  Water ',
          iconKey: 'water_drop',
          color: 1,
          type: TrackerType.quantity,
          unit: '  ',
          perTapValue: 0.25));
      expect(created.name, 'Water');
      expect(created.unit, isNull);
    });

    test('refuses a blank name and definitions that do not fit the type',
        () async {
      expect(
          () => repo.create(const TrackerDraft(
              name: ' ', iconKey: 'tag', color: 1, type: TrackerType.counter)),
          throwsArgumentError);
      expect(
          () => repo.create(const TrackerDraft(
              name: 'W',
              iconKey: 'tag',
              color: 1,
              type: TrackerType.quantity)),
          throwsArgumentError);
      expect(
          () => repo.create(const TrackerDraft(
              name: 'C',
              iconKey: 'tag',
              color: 1,
              type: TrackerType.counter,
              unit: 'L')),
          throwsArgumentError);
    });

    test('createAll keeps the order and appends after existing trackers',
        () async {
      await repo.create(cigarettes);
      await repo.createAll([gym, water]);
      expect([for (final t in await repo.watchTrackers().first) t.name],
          ['Cigarettes', 'Gym', 'Water']);
    });
  });

  group('logEntry', () {
    test('a counter logs one, as many times as it is tapped', () async {
      final cig = await repo.create(cigarettes);
      await repo.logEntry(cig.id);
      await repo.logEntry(cig.id);
      expect(await repo.totalOn(cig.id, repo.today()), 2);
    });

    test('a boolean logs done once a day; the second tap is a result',
        () async {
      final g = await repo.create(gym);
      expect(await repo.logEntry(g.id), isA<EntryLogged>());
      expect(await repo.logEntry(g.id), isA<AlreadyDoneToday>());
      expect(await entriesOf(g.id), hasLength(1));
    });

    test('a quantity logs its per-tap amount, or the amount given', () async {
      final w = await repo.create(water);
      await repo.logEntry(w.id);
      await repo.logEntry(w.id, value: 1.5);
      expect(await repo.totalOn(w.id, repo.today()), 1.75);
    });

    test('values that do not fit the type are refused', () async {
      final cig = await repo.create(cigarettes);
      final w = await repo.create(water);
      final s = await repo.create(sleep);
      expect(() => repo.logEntry(cig.id, value: 2), throwsArgumentError);
      expect(() => repo.logEntry(w.id, value: 0), throwsArgumentError);
      // A duration has no per-tap value: its taps go through the timer.
      expect(() => repo.logEntry(s.id), throwsArgumentError);
    });

    test('an unknown tracker is a stale id, not a silent no-op', () async {
      expect(() => repo.logEntry('nope'), throwsStateError);
    });

    test('the note is trimmed, and a blank one is none', () async {
      final cig = await repo.create(cigarettes);
      final logged =
          await repo.logEntry(cig.id, note: '  after lunch ') as EntryLogged;
      expect(logged.entry.note, 'after lunch');
      final blank = await repo.logEntry(cig.id, note: '   ') as EntryLogged;
      expect(blank.entry.note, isNull);
    });
  });

  group('the local date is taken at write time', () {
    // 2026-10-04 22:00 UTC is already the 5th in Tehran, still the 4th in
    // New York.
    final lateEvening = DateTime.utc(2026, 10, 4, 22);

    test('from the device timezone, not from UTC', () async {
      final cig = await repo.create(cigarettes);
      final tehran =
          await repo.logEntry(cig.id, at: lateEvening) as EntryLogged;
      fake.offset = FakeClock.newYork;
      final newYork =
          await repo.logEntry(cig.id, at: lateEvening) as EntryLogged;

      expect(tehran.entry.localDateKey, const DateKey(20261005));
      expect(newYork.entry.localDateKey, const DateKey(20261004));
    });

    test('a flight does not move entries already logged', () async {
      // Correct, and pinned so nobody "fixes" it later: an entry belongs to
      // the local day the user was in when they logged it.
      final cig = await repo.create(cigarettes);
      final before =
          await repo.logEntry(cig.id, at: lateEvening) as EntryLogged;
      fake.offset = FakeClock.newYork;
      await repo.logEntry(cig.id);

      final stored = (await entriesOf(cig.id))
          .singleWhere((e) => e.id == before.entry.id);
      expect(stored.localDateKey, const DateKey(20261005));
    });

    test('editing only the note after a flight keeps the day', () async {
      final cig = await repo.create(cigarettes);
      final logged =
          await repo.logEntry(cig.id, at: lateEvening) as EntryLogged;
      fake.offset = FakeClock.newYork;

      final e = logged.entry;
      await repo.updateEntry(TrackerEntry(
          id: e.id,
          trackerId: e.trackerId,
          value: e.value,
          occurredAtUtc: e.occurredAtUtc,
          localDateKey: e.localDateKey,
          note: 'remembered'));

      final stored = (await entriesOf(cig.id)).single;
      expect(stored.note, 'remembered');
      expect(stored.localDateKey, const DateKey(20261005));
    });

    test('changing the time re-derives the day, where the device is now',
        () async {
      final cig = await repo.create(cigarettes);
      final e = (await repo.logEntry(cig.id) as EntryLogged).entry;

      await repo.updateEntry(TrackerEntry(
          id: e.id,
          trackerId: e.trackerId,
          value: e.value,
          occurredAtUtc: lateEvening,
          localDateKey: e.localDateKey,
          note: null));

      expect((await entriesOf(cig.id)).single.localDateKey,
          const DateKey(20261005));
    });
  });

  group('timers', () {
    late Tracker s;
    setUp(() async => s = await repo.create(sleep));

    test('start persists the start; a second start is a result', () async {
      final started = await repo.startTimer(s.id) as TimerStarted;
      expect(started.timer.startedAtUtc, fake.nowUtc);
      expect(await repo.startTimer(s.id), isA<TimerAlreadyRunning>());
      expect((await repo.watchTracker(s.id).first)!.runningTimer,
          started.timer);
    });

    test('stop logs the session in whole seconds, stamped at its start',
        () async {
      final start = fake.nowUtc;
      await repo.startTimer(s.id);
      fake.advance(const Duration(hours: 7, minutes: 30, seconds: 12));

      final stopped = await repo.stopTimer(s.id) as TimerStopped;
      expect(stopped.entry.value, 27012);
      expect(stopped.entry.occurredAtUtc, start);
      expect((await repo.watchTracker(s.id).first)!.runningTimer, isNull);
    });

    test('a session across midnight counts for the day it started', () async {
      fake.nowUtc = DateTime.utc(2026, 10, 5, 20, 20); // 23:50 in Tehran
      await repo.startTimer(s.id);
      fake.advance(const Duration(hours: 7, minutes: 30));

      final stopped = await repo.stopTimer(s.id) as TimerStopped;
      expect(stopped.entry.localDateKey, const DateKey(20261005));
    });

    test('a second stop is a result and logs nothing more', () async {
      await repo.startTimer(s.id);
      fake.advance(const Duration(minutes: 5));
      await repo.stopTimer(s.id);
      expect(await repo.stopTimer(s.id), isA<TimerNotRunning>());
      expect(await entriesOf(s.id), hasLength(1));
    });

    test('a stop under a second is discarded: cleared, nothing logged',
        () async {
      await repo.startTimer(s.id);
      fake.advance(const Duration(milliseconds: 900));
      expect(await repo.stopTimer(s.id), isA<TimerDiscarded>());
      expect(await entriesOf(s.id), isEmpty);
      expect((await repo.watchTracker(s.id).first)!.runningTimer, isNull);
    });

    test('a clock set back past the start is discarded, never negative',
        () async {
      await repo.startTimer(s.id);
      fake.advance(const Duration(hours: -1));
      expect(await repo.stopTimer(s.id), isA<TimerDiscarded>());
      expect(await entriesOf(s.id), isEmpty);
    });

    test('only a duration tracker has a timer', () async {
      final cig = await repo.create(cigarettes);
      expect(() => repo.startTimer(cig.id), throwsArgumentError);
      expect(() => repo.stopTimer(cig.id), throwsArgumentError);
    });

    test('a forgotten session is added as a duration ending now', () async {
      final logged = await repo.addDuration(
          s.id, const Duration(minutes: 45)) as EntryLogged;
      expect(logged.entry.value, 2700);
      expect(logged.entry.occurredAtUtc,
          fake.nowUtc.subtract(const Duration(minutes: 45)));
      expect(() => repo.addDuration(s.id, const Duration(milliseconds: 500)),
          throwsArgumentError);
    });
  });

  group('entries', () {
    test('pages report a next page exactly when one exists', () async {
      final cig = await repo.create(cigarettes);
      for (var i = 0; i < 4; i++) {
        await repo.logEntry(cig.id,
            at: fake.nowUtc.subtract(Duration(minutes: i)));
      }
      final first = await repo.entriesPage(cig.id, limit: 2);
      expect(first.items, hasLength(2));
      expect(first.hasMore, isTrue);

      // Four entries in pages of two: the second page is the last, even
      // though it is full -- the case items.length == limit gets wrong.
      final second =
          await repo.entriesPage(cig.id, after: first.cursor, limit: 2);
      expect(second.items, hasLength(2));
      expect(second.hasMore, isFalse);
    });

    test('clearToday removes the done, and restore brings it back', () async {
      final g = await repo.create(gym);
      await repo.logEntry(g.id);
      final cleared = await repo.clearToday(g.id);
      expect(await repo.totalOn(g.id, repo.today()), 0);

      expect(await repo.restoreEntries(cleared), DayWrite.written);
      expect(await repo.totalOn(g.id, repo.today()), 1);
    });

    test('an undo after marking done again reports the day is done',
        () async {
      final g = await repo.create(gym);
      await repo.logEntry(g.id);
      final cleared = await repo.clearToday(g.id);
      await repo.logEntry(g.id);

      expect(await repo.restoreEntries(cleared), DayWrite.dayAlreadyDone);
    });

    test('an edit must fit the type', () async {
      final cig = await repo.create(cigarettes);
      final e = (await repo.logEntry(cig.id) as EntryLogged).entry;
      expect(
          () => repo.updateEntry(TrackerEntry(
              id: e.id,
              trackerId: e.trackerId,
              value: 3,
              occurredAtUtc: e.occurredAtUtc,
              localDateKey: e.localDateKey)),
          throwsArgumentError);
    });
  });

  test('update rewrites the appearance and a quantity\'s amount', () async {
    final w = await repo.create(water);
    await repo.update(w.id,
        name: ' Aab ', iconKey: 'local_cafe', color: 7, unit: 'cup',
        perTapValue: 1);
    final stored = (await repo.watchTracker(w.id).first)!;
    expect(stored.name, 'Aab');
    expect(stored.unit, 'cup');
    expect(stored.perTapValue, 1);

    final cig = await repo.create(cigarettes);
    expect(
        () => repo.update(cig.id,
            name: 'C', iconKey: 'tag', color: 1, unit: 'L'),
        throwsArgumentError);
  });
}
```

In `app/test/ux_rules_test.dart`, extend the DAO name list in "presentation code never calls a DAO directly". After `'settingsDao',`, add:

```dart
        'trackersDao',
        'trackerEntriesDao',
```

- [ ] **Step 2: Run the tests to confirm RED**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/tracker_repository_test.dart`
Expected: FAIL to compile, with `Target of URI doesn't exist: 'package:nimbustats/features/trackers/data/tracker_clock.dart'`.

- [ ] **Step 3: Tag the rollback target**

Run: `git tag pre-tracker-repository`

- [ ] **Step 4: Implement**

`app/lib/features/trackers/data/tracker_clock.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';

/// The wall clock the trackers feature reads, injectable so a test can stand
/// at any instant and in any timezone.
///
/// Two questions, kept apart on purpose:
/// - *When* something happens is an instant ([nowUtc]).
/// - *Which day* it belongs to depends on where the device is when it is
///   written ([toLocal]).
/// A flight between two entries changes the second answer and not the first.
final class TrackerClock {
  const TrackerClock({
    DateTime Function() nowUtc = _systemNowUtc,
    DateTime Function(DateTime utc) toLocal = _systemToLocal,
    DateTime Function(DateTime wall) fromLocal = _systemFromLocal,
  })  : _nowUtc = nowUtc,
        _toLocal = toLocal,
        _fromLocal = fromLocal;

  final DateTime Function() _nowUtc;
  final DateTime Function(DateTime utc) _toLocal;
  final DateTime Function(DateTime wall) _fromLocal;

  DateTime nowUtc() => _nowUtc().toUtc();

  /// The wall-clock time [utc] reads as, in the device's timezone right now.
  DateTime toLocal(DateTime utc) => _toLocal(utc.toUtc());

  /// The instant a wall-clock time picked on this device means. Only [wall]'s
  /// date and time fields are read.
  DateTime fromLocal(DateTime wall) => _fromLocal(wall).toUtc();

  /// The local date [utc] falls on, here and now.
  DateKey localDateOf(DateTime utc) => DateKey.fromDateTime(toLocal(utc));

  DateKey today() => localDateOf(nowUtc());

  static DateTime _systemNowUtc() => DateTime.now().toUtc();

  static DateTime _systemToLocal(DateTime utc) => utc.toLocal();

  static DateTime _systemFromLocal(DateTime wall) => DateTime(wall.year,
          wall.month, wall.day, wall.hour, wall.minute, wall.second)
      .toUtc();
}
```

`app/lib/features/trackers/data/tracker_draft.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';

/// A tracker about to be created: what the editor sheet and the presets hand
/// to `TrackerRepository.create`.
final class TrackerDraft {
  const TrackerDraft({
    required this.name,
    required this.iconKey,
    required this.color,
    required this.type,
    this.unit,
    this.perTapValue,
  });

  final String name;
  final String iconKey;
  final int color;
  final TrackerType type;
  final String? unit;
  final double? perTapValue;
}
```

`app/lib/features/trackers/data/tracker_entry_page.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

/// Where the last history page stopped: a position in the ordering, not a
/// row offset, so it stays valid when entries are logged around it.
final class TrackerEntryCursor {
  const TrackerEntryCursor({required this.occurredAtUtc, required this.id});

  factory TrackerEntryCursor.of(TrackerEntry entry) =>
      TrackerEntryCursor(occurredAtUtc: entry.occurredAtUtc, id: entry.id);

  final DateTime occurredAtUtc;
  final String id;

  TrackerEntryCursorRow get row => (occurredAtUtc: occurredAtUtc, id: id);

  @override
  bool operator ==(Object other) =>
      other is TrackerEntryCursor &&
      other.occurredAtUtc == occurredAtUtc &&
      other.id == id;

  @override
  int get hashCode => Object.hash(occurredAtUtc, id);

  @override
  String toString() => 'TrackerEntryCursor($occurredAtUtc, $id)';
}

/// One page of a tracker's history.
final class TrackerEntryPage {
  const TrackerEntryPage({required this.items, required this.cursor});

  final List<TrackerEntry> items;

  /// Where to continue from, or null when this was the last page.
  final TrackerEntryCursor? cursor;

  bool get hasMore => cursor != null;
}
```

`app/lib/features/trackers/data/tracker_repository.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import 'tracker_clock.dart';
import 'tracker_draft.dart';
import 'tracker_entry_page.dart';

/// The single write path for trackers and their entries.
///
/// Every entry in this app is written here: the tab's one-tap buttons, the
/// detail screen, and Phase 6's home-screen widget, which writes through this
/// and nothing else. That keeps three things in one place instead of three:
/// - the per-type default value;
/// - the boolean once-per-day flag;
/// - the local date key, computed at write time.
final class TrackerRepository {
  /// Positional to keep the DAOs private, as `TransactionRepository` does.
  const TrackerRepository(this._trackers, this._entries, this._clock);

  final TrackersDao _trackers;
  final TrackerEntriesDao _entries;
  final TrackerClock _clock;

  // --- reads ---------------------------------------------------------------

  /// Live, unarchived trackers in the user's order: the tab.
  Stream<List<Tracker>> watchTrackers() => _trackers.watchLive(archived: false);

  /// Live archived trackers: the manager's "Archived" section.
  Stream<List<Tracker>> watchArchived() => _trackers.watchLive(archived: true);

  Stream<Tracker?> watchTracker(String id) => _trackers.watchById(id);

  /// Every tracker's total for [day], keyed by tracker id.
  Stream<Map<String, double>> watchTotals(DateKey day) =>
      _entries.watchDayTotals(day);

  /// One tracker's total for [day], read once: the snackbar after a tap.
  Future<double> totalOn(String trackerId, DateKey day) async =>
      (await _entries.watchDayTotals(day).first)[trackerId] ?? 0;

  /// Fires after any entry write, so a loaded history can reload.
  Stream<void> entryChanges() => _entries.changes();

  DateKey today() => _clock.today();

  /// One history page, newest first.
  ///
  /// Asks for one row more than requested. That row is never returned; it is
  /// how this knows whether a next page exists, rather than guessing from
  /// `items.length == limit`, which is wrong exactly when the total is a
  /// multiple of the page size.
  Future<TrackerEntryPage> entriesPage(
    String trackerId, {
    TrackerEntryCursor? after,
    int limit = 40,
  }) async {
    final rows =
        await _entries.pageAfter(trackerId, after: after?.row, limit: limit + 1);
    final hasMore = rows.length > limit;
    final items = hasMore ? rows.take(limit).toList() : rows;
    return TrackerEntryPage(
      items: items,
      cursor: hasMore ? TrackerEntryCursor.of(items.last) : null,
    );
  }

  // --- trackers -------------------------------------------------------------

  Future<Tracker> create(TrackerDraft draft) async =>
      (await createAll([draft])).single;

  /// Creates [drafts] in order, after every existing tracker, in one
  /// transaction.
  Future<List<Tracker>> createAll(List<TrackerDraft> drafts) async {
    final rows = [for (final draft in drafts) _validNew(draft)];
    await _trackers.insertAll(rows);
    return [for (final row in rows) await _require(row.id)];
  }

  /// Rewrites a tracker's name, look and -- for a quantity -- its unit and
  /// per-tap amount. Its type cannot change (see [TrackerType]).
  Future<void> update(
    String id, {
    required String name,
    required String iconKey,
    required int color,
    String? unit,
    double? perTapValue,
  }) async {
    final tracker = await _require(id);
    final cleanUnit = _validUnit(unit);
    TrackerValues.checkDefinition(tracker.type,
        unit: cleanUnit, perTapValue: perTapValue);
    await _trackers.updateTracker(id,
        name: _validName(name),
        iconKey: iconKey,
        color: color,
        unit: cleanUnit,
        perTapValue: perTapValue);
  }

  Future<void> archive(String id) => _trackers.setArchived(id, true);

  Future<void> unarchive(String id) => _trackers.setArchived(id, false);

  Future<void> reorder(List<String> ids) => _trackers.reorder(ids);

  // --- entries --------------------------------------------------------------

  /// Logs one entry: by default what one tap logs (1, or the per-tap amount).
  ///
  /// [at] defaults to now. Returns [AlreadyDoneToday] instead of writing when
  /// a boolean tracker already holds that day. Throws [ArgumentError] for a
  /// value that does not fit the type, or for a duration tracker without a
  /// value -- a duration's taps go through [startTimer] and [stopTimer].
  Future<LogResult> logEntry(
    String trackerId, {
    double? value,
    DateTime? at,
    String? note,
  }) async {
    final tracker = await _require(trackerId);
    final amount = value ??
        TrackerValues.perTap(tracker.type, perTapValue: tracker.perTapValue) ??
        (throw ArgumentError.value(value, 'value',
            'a duration tracker logs through its timer or addDuration'));
    if (!TrackerValues.isValid(tracker.type, amount)) {
      throw ArgumentError.value(
          amount, 'value', 'not a valid ${tracker.type.name} entry');
    }
    final atUtc = (at ?? _clock.nowUtc()).toUtc();
    return _entries.insertEntry((
      id: Ids.newId(),
      trackerId: trackerId,
      value: amount,
      occurredAtUtc: atUtc,
      // The local date where the device is now, not the UTC one. A glass of
      // water at 01:00 in Tehran belongs to that day even though it is still
      // yesterday in UTC.
      localDateKey: _clock.localDateOf(atUtc),
      note: _validNote(note),
      oncePerDay: tracker.type == TrackerType.boolean,
    ));
  }

  /// Takes back today's "done" on a boolean tracker. Returns what to restore
  /// for an undo.
  Future<List<String>> clearToday(String trackerId) =>
      _entries.softDeleteOn(trackerId, _clock.today());

  Future<TimerStartResult> startTimer(String trackerId) async {
    final tracker = await _require(trackerId);
    _expectType(tracker, TrackerType.duration);
    final startMs = _clock.nowUtc().millisecondsSinceEpoch;
    final started = await _trackers.startTimer(trackerId, startMs);
    return started
        ? TimerStarted(RunningTimer(
            DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true)))
        : const TimerAlreadyRunning();
  }

  /// Stops the running timer and logs the session.
  ///
  /// The entry is stamped at the start (a night's sleep belongs to the evening
  /// it began) and holds whole seconds. A session under a second is discarded:
  /// the timer is cleared and nothing is logged.
  Future<TimerStopResult> stopTimer(String trackerId) async {
    final tracker = await _require(trackerId);
    _expectType(tracker, TrackerType.duration);
    final timer = tracker.runningTimer;
    if (timer == null) return const TimerNotRunning();

    final startMs = timer.startedAtUtc.millisecondsSinceEpoch;
    final elapsed = timer.elapsed(_clock.nowUtc());
    if (elapsed.inSeconds < 1) {
      final cleared = await _trackers.finishTimer(trackerId,
          startedAtUtcMs: startMs, entry: null);
      return cleared ? const TimerDiscarded() : const TimerNotRunning();
    }

    final entryId = Ids.newId();
    final finished = await _trackers.finishTimer(
      trackerId,
      startedAtUtcMs: startMs,
      entry: (
        id: entryId,
        trackerId: trackerId,
        value: TrackerValues.secondsOf(elapsed),
        occurredAtUtc: timer.startedAtUtc,
        localDateKey: _clock.localDateOf(timer.startedAtUtc),
        note: null,
        oncePerDay: false,
      ),
    );
    // Lost a race with another stop: that one logged the session.
    if (!finished) return const TimerNotRunning();
    final logged = await _entries.byId(entryId);
    if (logged == null) {
      throw StateError('timer entry $entryId was not persisted');
    }
    return TimerStopped(logged);
  }

  /// Logs a session the user forgot to time, ending now unless [startedAt]
  /// says when it began.
  Future<LogResult> addDuration(
    String trackerId,
    Duration duration, {
    DateTime? startedAt,
  }) async {
    final tracker = await _require(trackerId);
    _expectType(tracker, TrackerType.duration);
    final seconds = TrackerValues.secondsOf(duration);
    if (!TrackerValues.isValid(TrackerType.duration, seconds)) {
      throw ArgumentError.value(
          duration, 'duration', 'a session lasts at least a second');
    }
    final start = (startedAt ?? _clock.nowUtc().subtract(duration)).toUtc();
    return _entries.insertEntry((
      id: Ids.newId(),
      trackerId: trackerId,
      value: seconds,
      occurredAtUtc: start,
      localDateKey: _clock.localDateOf(start),
      note: null,
      oncePerDay: false,
    ));
  }

  /// Writes an edited entry.
  ///
  /// The local date is recomputed only when the time changed. Editing a note
  /// after a flight must not move the entry to another day, while moving the
  /// time is a new write and takes the device's date now.
  Future<DayWrite> updateEntry(TrackerEntry edited) async {
    final current = await _entries.byId(edited.id);
    if (current == null) throw StateError('no tracker entry "${edited.id}"');
    final tracker = await _require(current.trackerId);
    if (!TrackerValues.isValid(tracker.type, edited.value)) {
      throw ArgumentError.value(
          edited.value, 'value', 'not a valid ${tracker.type.name} entry');
    }
    final atUtc = edited.occurredAtUtc.toUtc();
    return _entries.updateEntry(
      edited.id,
      value: edited.value,
      occurredAtUtc: atUtc,
      localDateKey: atUtc == current.occurredAtUtc
          ? current.localDateKey
          : _clock.localDateOf(atUtc),
      note: _validNote(edited.note),
    );
  }

  Future<void> deleteEntry(String id) => _entries.softDelete(id);

  Future<DayWrite> restoreEntries(List<String> ids) => _entries.restore(ids);

  // --- validation -----------------------------------------------------------

  NewTracker _validNew(TrackerDraft draft) {
    final unit = _validUnit(draft.unit);
    TrackerValues.checkDefinition(draft.type,
        unit: unit, perTapValue: draft.perTapValue);
    return (
      id: Ids.newId(),
      name: _validName(draft.name),
      iconKey: draft.iconKey,
      color: draft.color,
      type: draft.type,
      unit: unit,
      perTapValue: draft.perTapValue,
    );
  }

  Future<Tracker> _require(String id) async =>
      await _trackers.byId(id) ?? (throw StateError('no tracker "$id"'));

  static void _expectType(Tracker tracker, TrackerType type) {
    if (tracker.type != type) {
      throw ArgumentError.value(tracker.type, 'tracker.type',
          'expected a ${type.name} tracker');
    }
  }

  static String _validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'a tracker needs a name');
    }
    return trimmed;
  }

  static String? _validUnit(String? unit) {
    final trimmed = unit?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _validNote(String? note) {
    final trimmed = note?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
```

- [ ] **Step 5: Run the tests to confirm GREEN**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/tracker_repository_test.dart C:/Users/nimae/Desktop/nimbustats/app/test/ux_rules_test.dart`
Expected: PASS.

**Mutation checks:**
- In `updateEntry`, always use `_clock.localDateOf(atUtc)`. "editing only the note after a flight keeps the day" must FAIL.
- In `logEntry`, derive the key from UTC: `DateKey.fromDateTime(atUtc)`. "from the device timezone, not from UTC" must FAIL.
- In `stopTimer`, drop the under-a-second branch. "a stop under a second is discarded" must FAIL: the DAO does not validate values, so a 0-second entry is written and the test finds it.

Restore all three.

- [ ] **Step 6: Run the full gate**

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/trackers/data/ app/test/features/trackers/ app/test/ux_rules_test.dart
git commit -m "$(cat <<'EOF'
feat(trackers): the repository, the single write path

TrackerRepository is the only way an entry gets written: the tab, the
detail screen and Phase 6's widget all come through logEntry. That
keeps the per-type default, the boolean flag and the local date key in
one place.

The local date is taken at write time from where the device is. An
edit re-derives it only when the time changed, so fixing a note after
a flight does not move the entry to another day.

A stop under a second, or with the clock set back past the start,
clears the timer and logs nothing rather than writing a 0:00 entry.

TrackerClock is new because nothing in the app had an injectable
clock, and timers, midnight and timezones are untestable without one.

Touches Phase 1's ux_rules_test to add the two tracker DAOs to the
"presentation never calls a DAO" list.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git switch phase/4-trackers && git merge --ff-only feat/tracker-repository
```

---

### Task 5: The Trackers tab — shell destination, states, presets, today's totals

Branch `feat/trackers-tab`, slug `trackers-tab`.

**Files:**
- Create, in the session scratchpad (not the repo): `arb_add.py`, the ARB helper reused by Tasks 6–10. `<scratchpad>` below means that directory.
- Modify: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_fa.arb`; regenerate `app/lib/l10n/app_localizations*.dart`
- Modify: `packages/nimbus_design/lib/src/widgets/icon_picker.dart` (eight habit icons; Phase 1's file)
- Create: `app/lib/features/trackers/data/tracker_presets.dart`
- Create: `app/lib/features/trackers/application/tracker_providers.dart`, `tracker_format.dart`
- Create: `app/lib/features/trackers/presentation/trackers_screen.dart`
- Create: `app/lib/features/trackers/presentation/widgets/tracker_tile.dart`, `tracker_today_text.dart`, `tracker_presets_empty.dart`, `tracker_day_rollover.dart`, `tracker_write.dart`
- Create: `app/lib/features/trackers/routes.dart`
- Modify: `app/lib/bootstrap/app_shell.dart`, `app/lib/bootstrap/app_router.dart`
- Modify: `app/test/bootstrap/app_shell_navigation_test.dart`
- Modify: `app/test/features/trackers/support/tracker_fixture.dart`
- Test: `app/test/features/trackers/tracker_format_test.dart`, `tracker_presets_test.dart`, `trackers_screen_test.dart`

**Interfaces:**
- Consumes: Task 4's `TrackerRepository`, `TrackerClock` and `TrackerDraft`; `localeProvider`, `moneyFormatterProvider` and `calendarProvider` (`features/settings/application/settings_providers.dart`).
- Produces:
  - Providers:
    - `trackerClockProvider` (`Provider<TrackerClock>`);
    - `trackerRepositoryProvider` (`Provider<TrackerRepository>`);
    - `trackerTodayProvider` (`NotifierProvider<TrackerToday, DateKey>`, with `refresh()`);
    - `trackersProvider` (`StreamProvider<List<Tracker>>`);
    - `trackerTotalsProvider` (`StreamProvider<Map<String, double>>`).
  - `TrackerFormat({required String localeTag, required bool persianDigits, required AppCalendar calendar})`, with methods `number(double)`, `total(Tracker, double)`, `duration(Duration)`, `elapsed(Duration)`, `time(DateTime local)` and `date(DateKey)`. `trackerFormatProvider` supplies it.
  - `List<TrackerDraft> trackerPresets(AppLocalizations l10n)`.
  - Widgets:
    - `TrackersScreen`;
    - `TrackerTile({required Tracker tracker, required double total})`;
    - `TrackerTodayText({required Tracker tracker, required double total, TextStyle? style})`;
    - `TrackerPresetsEmpty`;
    - `TrackerDayRollover({required Widget child})`.
  - `Future<T> reportingTrackerFailure<T>({required ScaffoldMessengerState messenger, required AppLocalizations l10n, required Future<T> Function() write})`.
  - Routes: `trackersRoute = '/trackers'`, `trackerShellRoutes`.
  - Keys:
    - `trackers-list`;
    - `tracker-tile-<id>` and `tracker-total-<id>`;
    - `tracker-presets`, `tracker-preset-{water,cigarettes,gym,sleep}` and `tracker-presets-add`.
  - ARB keys:
    - `navTrackers`;
    - `trackerDoneToday`, `trackerEmptyMessage`, `trackerEmptyTitle`, `trackerErrorTitle`, `trackerNotDoneToday`;
    - `trackerPresetCigarettes`, `trackerPresetGym`, `trackerPresetSleep`, `trackerPresetWater`, `trackerPresetWaterUnit`, `trackerPresetsAdd`;
    - `trackerScreenTitle`, `trackerTodayTotal(String total)`, `trackerWriteFailed`.
  - Fixture: `trackerOverrides(FakeClock)`, `useEnglishDigits(AppDatabase)`, `textIn(WidgetTester, Key)`, `backgroundAndResume(WidgetTester)`.

- [ ] **Step 1: Write the ARB helper and prove it preserves the files**

Write the scratchpad file `arb_add.py` with the Write tool:

```python
"""Adds keys to app_en.arb and app_fa.arb without disturbing anything else.

Usage: python arb_add.py <keys.json>
keys.json: {"en": {"key": "value", "@key": {...}}, "fa": {"key": "value"}}

The ARBs are CRLF, store characters literally, and keep keys sorted
case-insensitively with each "@key" right after its key. This re-sorts with
that rule and writes the same format back, so a run that adds nothing changes
nothing.
"""
import json
import os
import sys

ROOT = r'C:\Users\nimae\Desktop\nimbustats\app\lib\l10n'


def order(key):
    return (key.lstrip('@').lower(), key.startswith('@'))


def plain(keys):
    return {k for k in keys if not k.startswith('@')}


new = json.load(open(sys.argv[1], encoding='utf-8'))
assert set(new) == {'en', 'fa'}, 'need exactly "en" and "fa"'
assert plain(new['en']) == plain(new['fa']), 'en and fa must add the same keys'

for lang in ('en', 'fa'):
    path = os.path.join(ROOT, 'app_' + lang + '.arb')
    data = json.loads(open(path, 'rb').read().decode('utf-8'))
    clash = set(new[lang]) & set(data)
    assert not clash, 'already present: %s' % sorted(clash)
    data.update(new[lang])
    out = {'@@locale': data.pop('@@locale')}
    for key in sorted(data, key=order):
        out[key] = data[key]
    text = json.dumps(out, ensure_ascii=False, indent=2) + '\n'
    open(path, 'wb').write(text.replace('\n', '\r\n').encode('utf-8'))
    print('wrote %s (+%d entries)' % (path, len(new[lang])))
```

Prove it is a no-op on today's files:
1. Write the scratchpad file `keys_empty.json` containing `{"en": {}, "fa": {}}`.
2. Run `python <scratchpad>/arb_add.py <scratchpad>/keys_empty.json`, then `git diff --stat app/lib/l10n/`.
3. Expected: **no diff**.
4. If the existing files are not in the order `order()` assumes, the diff shows it. Then stop: fix the helper to match the file's order, never reorder the file.

- [ ] **Step 2: Write the failing tests**

Append to `app/test/features/trackers/support/tracker_fixture.dart`. Add these imports at the top, beside the existing ones:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';
import 'package:nimbustats/features/trackers/application/tracker_providers.dart';
```

Then add at the end:

```dart
/// What a tracker widget test overrides: the clock, so "today" and the timer
/// are the fake's.
List<Override> trackerOverrides(FakeClock fake) =>
    [trackerClockProvider.overrideWithValue(fake.clock)];

/// Saves English as the settings locale, so numbers render in Latin digits.
///
/// Without it they are Persian whatever locale the test pumps: digits follow
/// the settings locale, whose default is fa.
Future<void> useEnglishDigits(AppDatabase db) =>
    SettingsRepository(db.settingsDao)
        .save(AppSettings.defaults.copyWith(locale: const Locale('en')));

/// The text shown under a keyed widget.
String textIn(WidgetTester tester, Key key) => tester
    .widget<Text>(find
        .descendant(of: find.byKey(key), matching: find.byType(Text))
        .first)
    .data!;

/// Sends the app to the background and back, one lifecycle step at a time,
/// as Android does. AppLifecycleListener asserts each step is a legal one.
Future<void> backgroundAndResume(WidgetTester tester) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
}
```

`app/test/features/trackers/tracker_format_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/application/tracker_format.dart';

Tracker tracker(TrackerType type, {String? unit}) => Tracker(
      id: 't',
      name: 'T',
      iconKey: 'tag',
      color: 0,
      type: type,
      unit: unit,
      perTapValue: type == TrackerType.quantity ? 0.25 : null,
      archived: false,
      sortOrder: 0,
    );

void main() {
  final persian = TrackerFormat(
      localeTag: 'fa', persianDigits: true, calendar: const GregorianCalendar());
  final english = TrackerFormat(
      localeTag: 'en', persianDigits: false, calendar: const GregorianCalendar());

  test("numbers use the locale's digits and separators", () {
    expect(persian.number(2.5), '۲٫۵');
    expect(persian.number(1250), '۱٬۲۵۰');
    expect(english.number(2.5), '2.5');
    expect(english.number(1250), '1,250');
  });

  test('two decimals at most, so a float sum reads cleanly', () {
    expect(english.number(0.1 + 0.2), '0.3');
    expect(english.number(1 / 3), '0.33');
    expect(english.number(5), '5');
  });

  test("a total reads in its tracker's terms", () {
    expect(english.total(tracker(TrackerType.counter), 5), '5');
    expect(english.total(tracker(TrackerType.quantity, unit: 'L'), 0.75),
        '0.75 L');
    expect(english.total(tracker(TrackerType.quantity), 3), '3');
    expect(english.total(tracker(TrackerType.duration), 5400), '1:30');
    expect(persian.total(tracker(TrackerType.quantity, unit: 'لیتر'), 0.75),
        '۰٫۷۵ لیتر');
  });

  test('durations are h:mm; a running timer is h:mm:ss', () {
    const d = Duration(hours: 1, minutes: 2, seconds: 5);
    expect(english.duration(d), '1:02');
    expect(english.elapsed(d), '1:02:05');
    expect(persian.elapsed(d), '۱:۰۲:۰۵');
    expect(english.duration(const Duration(minutes: 12)), '0:12');
  });

  test('times and dates follow the digits and the active calendar', () {
    expect(english.time(DateTime.utc(2026, 10, 5, 7, 5)), '07:05');
    expect(persian.time(DateTime.utc(2026, 10, 5, 14, 30)), '۱۴:۳۰');
    expect(english.date(const DateKey(20261005)), '2026/10/05');
    expect(persian.date(const DateKey(20261005)), '۲۰۲۶/۱۰/۰۵');
  });
}
```

`app/test/features/trackers/tracker_presets_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_presets.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

void main() {
  final swatches =
      NimbusColors.categorySwatches.values.map((c) => c.toARGB32()).toSet();

  for (final locale in const [Locale('en'), Locale('fa')]) {
    test('the $locale presets: one of each type, known icons, swatch colours',
        () {
      final presets = trackerPresets(lookupAppLocalizations(locale));

      expect(presets.map((p) => p.type), [
        TrackerType.quantity,
        TrackerType.counter,
        TrackerType.boolean,
        TrackerType.duration,
      ]);
      for (final preset in presets) {
        expect(nimbusIcons.containsKey(preset.iconKey), isTrue,
            reason: '${preset.name}: ${preset.iconKey}');
        expect(swatches, contains(preset.color), reason: preset.name);
      }
      expect(presets.first.perTapValue, 0.25);
    });
  }

  test('the presets are named, and Water measured, in the current language',
      () {
    final en = trackerPresets(lookupAppLocalizations(const Locale('en')));
    final fa = trackerPresets(lookupAppLocalizations(const Locale('fa')));
    expect(en.map((p) => p.name), ['Water', 'Cigarettes', 'Gym', 'Sleep']);
    expect(fa.map((p) => p.name), ['آب', 'سیگار', 'باشگاه', 'خواب']);
    expect(en.first.unit, 'L');
    expect(fa.first.unit, 'لیتر');
  });
}
```

`app/test/features/trackers/trackers_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/application/tracker_providers.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  setUp(() => fake = FakeClock());

  Future<void> openTab(WidgetTester tester, AppDatabase db,
          {Locale locale = const Locale('en')}) =>
      pumpApp(tester,
          database: db,
          initialLocation: trackersRoute,
          locale: locale,
          overrides: trackerOverrides(fake));

  Future<AppDatabase> freshDb() async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    return db;
  }

  testWidgets('loading shows a skeleton, never a spinner', (tester) async {
    final never = StreamController<List<Tracker>>();
    addTearDown(never.close);
    await pumpApp(tester, initialLocation: trackersRoute, overrides: [
      ...trackerOverrides(fake),
      trackersProvider.overrideWith((ref) => never.stream),
    ]);

    expect(find.byType(NimbusLoadingList), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the error state retries and hides the raw exception',
      (tester) async {
    await pumpApp(tester, initialLocation: trackersRoute, overrides: [
      ...trackerOverrides(fake),
      trackersProvider.overrideWith(
          (ref) => Stream<List<Tracker>>.error(Exception('boom'))),
    ]);

    expect(find.byType(NimbusErrorState), findsOneWidget);
    expect(find.text('Could not load trackers'), findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('the empty state explains trackers and offers four presets',
      (tester) async {
    await openTab(tester, await freshDb());

    expect(find.text('Track more than money'), findsOneWidget);
    for (final (slug, name) in const [
      ('water', 'Water'),
      ('cigarettes', 'Cigarettes'),
      ('gym', 'Gym'),
      ('sleep', 'Sleep'),
    ]) {
      expect(
          find.descendant(
              of: find.byKey(Key('tracker-preset-$slug')),
              matching: find.text(name)),
          findsOneWidget);
    }
    // Nothing chosen yet, so nothing to add.
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('tracker-presets-add')))
            .onPressed,
        isNull);
  });

  testWidgets('choosing presets creates exactly those, in their order',
      (tester) async {
    final db = await freshDb();
    await openTab(tester, db);

    await tester.tap(find.byKey(const Key('tracker-preset-gym')));
    await tester.tap(find.byKey(const Key('tracker-preset-water')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tracker-presets-add')));
    await tester.pumpAndSettle();

    final stored = await repositoryFor(db, fake).watchTrackers().first;
    expect(stored.map((t) => t.name), ['Water', 'Gym']);
    expect(stored.first.unit, 'L');
    expect(stored.first.perTapValue, 0.25);
    expect(find.byKey(Key('tracker-tile-${stored.first.id}')), findsOneWidget);
    expect(find.text('Track more than money'), findsNothing);
  });

  testWidgets('the presets are offered in Persian in Persian', (tester) async {
    await openTab(tester, await freshDb(), locale: const Locale('fa'));
    for (final name in ['آب', 'سیگار', 'باشگاه', 'خواب']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
  });

  group('populated', () {
    testWidgets("each tile shows today's total in the tracker's own terms",
        (tester) async {
      final db = await freshDb();
      await useEnglishDigits(db);
      final repo = repositoryFor(db, fake);
      final [cig, g, w, s] = await repo.createAll([cigarettes, gym, water, sleep]);
      for (var i = 0; i < 3; i++) {
        await repo.logEntry(cig.id);
        await repo.logEntry(w.id);
      }
      await repo.logEntry(cig.id,
          at: fake.nowUtc.subtract(const Duration(days: 1))); // yesterday
      await repo.addDuration(s.id, const Duration(minutes: 90));

      await openTab(tester, db);

      expect(textIn(tester, Key('tracker-total-${cig.id}')), '3 today');
      expect(textIn(tester, Key('tracker-total-${g.id}')), 'Not done today');
      expect(textIn(tester, Key('tracker-total-${w.id}')), '0.75 L today');
      expect(textIn(tester, Key('tracker-total-${s.id}')), '1:30 today');
    });

    testWidgets('Persian digits, right to left, in Persian', (tester) async {
      final db = await freshDb();
      final repo = repositoryFor(db, fake);
      final cig = await repo.create(cigarettes);
      for (var i = 0; i < 3; i++) {
        await repo.logEntry(cig.id);
      }

      await openTab(tester, db, locale: const Locale('fa'));

      expect(textIn(tester, Key('tracker-total-${cig.id}')), 'امروز ۳');
      expect(
          Directionality.of(
              tester.element(find.byKey(Key('tracker-tile-${cig.id}')))),
          TextDirection.rtl);
    });

    testWidgets('the first tracker sits lowest, in the bottom third',
        (tester) async {
      final db = await freshDb();
      final [cig, g, w] =
          await repositoryFor(db, fake).createAll([cigarettes, gym, water]);

      await openTab(tester, db);

      double centreOf(Tracker t) =>
          tester.getCenter(find.byKey(Key('tracker-tile-${t.id}'))).dy;
      final height =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(centreOf(cig), greaterThan(centreOf(g)));
      expect(centreOf(g), greaterThan(centreOf(w)));
      expect(centreOf(cig), greaterThan(height * 2 / 3));
    });

    testWidgets('archived trackers stay off the tab', (tester) async {
      final db = await freshDb();
      final repo = repositoryFor(db, fake);
      final [cig, g] = await repo.createAll([cigarettes, gym]);
      await repo.archive(g.id);

      await openTab(tester, db);

      expect(find.byKey(Key('tracker-tile-${cig.id}')), findsOneWidget);
      expect(find.byKey(Key('tracker-tile-${g.id}')), findsNothing);
    });
  });

  group('dynamic type', () {
    // Screen contract §1.4. Set on the platform dispatcher rather than in a
    // local MediaQuery, so it reaches the real tree the way a device-wide
    // setting does -- the approach card_previews_test.dart takes.
    testWidgets('a populated tab at twice the font size overflows nothing',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final db = await freshDb();
      await useEnglishDigits(db);
      final repo = repositoryFor(db, fake);
      final [_, _, w, _] =
          await repo.createAll([cigarettes, gym, water, sleep]);
      await repo.logEntry(w.id, value: 1234.5);

      await openTab(tester, db);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the Persian empty state at twice the font size overflows '
        'nothing', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openTab(tester, await freshDb(), locale: const Locale('fa'));

      expect(tester.takeException(), isNull);
    });
  });

  group('a new day', () {
    testWidgets('at local midnight the totals move to the new day',
        (tester) async {
      fake = FakeClock(nowUtc: DateTime.utc(2026, 10, 5, 20, 29, 30)); // 23:59:30
      final db = await freshDb();
      await useEnglishDigits(db);
      final repo = repositoryFor(db, fake);
      final cig = await repo.create(cigarettes);
      for (var i = 0; i < 3; i++) {
        await repo.logEntry(cig.id);
      }
      await openTab(tester, db);
      expect(textIn(tester, Key('tracker-total-${cig.id}')), '3 today');

      fake.advance(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(textIn(tester, Key('tracker-total-${cig.id}')), '0 today');
    });

    testWidgets('coming back to the app on a new day shows the new day',
        (tester) async {
      final db = await freshDb();
      await useEnglishDigits(db);
      final repo = repositoryFor(db, fake);
      final cig = await repo.create(cigarettes);
      await repo.logEntry(cig.id);
      await repo.logEntry(cig.id);
      await openTab(tester, db);
      expect(textIn(tester, Key('tracker-total-${cig.id}')), '2 today');

      fake.advance(const Duration(days: 1));
      await backgroundAndResume(tester);
      await tester.pumpAndSettle();

      expect(textIn(tester, Key('tracker-total-${cig.id}')), '0 today');
    });
  });
}
```

`app/test/bootstrap/app_shell_navigation_test.dart`:
- Rename the first test to `'the shell offers home, trackers, analytics and settings'`, and add `expect(navItem('Trackers'), findsOneWidget);` after the Home line.
- In "the destination the user is on is the selected one", make the body after `expect(bar().selectedIndex, 0);`:

```dart
    await tester.tap(navItem('Trackers'));
    await tester.pumpAndSettle();
    expect(bar().selectedIndex, 1);

    await tester.tap(navItem('Analytics'));
    await tester.pumpAndSettle();
    expect(bar().selectedIndex, 2);

    await tester.tap(navItem('Settings'));
    await tester.pumpAndSettle();
    expect(bar().selectedIndex, 3);
```

- Add a test after "tapping analytics shows the analytics screen":

```dart
  testWidgets('tapping trackers shows the trackers tab', (tester) async {
    await pumpApp(tester);

    await tester.tap(navItem('Trackers'));
    await tester.pumpAndSettle();

    // An empty database: the tab opens on its presets.
    expect(find.byKey(const Key('tracker-presets')), findsOneWidget);
  });
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/ C:/Users/nimae/Desktop/nimbustats/app/test/bootstrap/app_shell_navigation_test.dart`
Expected: FAIL to compile, with `Target of URI doesn't exist: 'package:nimbustats/features/trackers/application/tracker_providers.dart'`.

- [ ] **Step 4: Tag the rollback target**

Run: `git tag pre-trackers-tab`

- [ ] **Step 5: Add the strings**

Write the scratchpad file `keys_task5.json`. Persian ZWNJ is written as the JSON escape `\u200c`, which `json.load` decodes, so the ARB stores the literal character as it already does:

```json
{
  "en": {
    "navTrackers": "Trackers",
    "trackerDoneToday": "Done today",
    "trackerEmptyMessage": "A tracker counts what you do besides spending: cigarettes, glasses of water, gym days, hours of sleep. Pick some to start.",
    "trackerEmptyTitle": "Track more than money",
    "trackerErrorTitle": "Could not load trackers",
    "trackerNotDoneToday": "Not done today",
    "trackerPresetCigarettes": "Cigarettes",
    "trackerPresetGym": "Gym",
    "trackerPresetSleep": "Sleep",
    "trackerPresetWater": "Water",
    "trackerPresetWaterUnit": "L",
    "trackerPresetsAdd": "Start tracking",
    "trackerScreenTitle": "Trackers",
    "trackerTodayTotal": "{total} today",
    "@trackerTodayTotal": {"placeholders": {"total": {"type": "String"}}},
    "trackerWriteFailed": "Could not save. Try again."
  },
  "fa": {
    "navTrackers": "عادت\u200cها",
    "trackerDoneToday": "امروز انجام شد",
    "trackerEmptyMessage": "هر عادت چیزی جز خرج کردن را می\u200cشمارد: سیگار، لیوان آب، روز باشگاه، ساعت خواب. چندتا را برای شروع انتخاب کنید.",
    "trackerEmptyTitle": "فراتر از پول را دنبال کنید",
    "trackerErrorTitle": "عادت\u200cها بارگیری نشدند",
    "trackerNotDoneToday": "امروز انجام نشده",
    "trackerPresetCigarettes": "سیگار",
    "trackerPresetGym": "باشگاه",
    "trackerPresetSleep": "خواب",
    "trackerPresetWater": "آب",
    "trackerPresetWaterUnit": "لیتر",
    "trackerPresetsAdd": "شروع پیگیری",
    "trackerScreenTitle": "عادت\u200cها",
    "trackerTodayTotal": "امروز {total}",
    "trackerWriteFailed": "ذخیره نشد. دوباره تلاش کنید."
  }
}
```

Run:

```bash
python <scratchpad>/arb_add.py <scratchpad>/keys_task5.json
git diff --numstat app/lib/l10n/
cd app && flutter gen-l10n
```

Expected: `numstat` shows additions only (`0` deletions on both ARBs), and gen-l10n reports no errors.

- [ ] **Step 6: Add the habit icons**

In `packages/nimbus_design/lib/src/widgets/icon_picker.dart`, append inside `nimbusIcons`, after `'help_outline': Icons.help_outline,`:

```dart
  // Habit trackers' glyphs (Phase 4). The presets use the first four.
  'water_drop': Icons.water_drop_outlined,
  'smoking_rooms': Icons.smoking_rooms_outlined,
  'fitness_center': Icons.fitness_center_outlined,
  'bedtime': Icons.bedtime_outlined,
  'self_improvement': Icons.self_improvement_outlined,
  'menu_book': Icons.menu_book_outlined,
  'directions_run': Icons.directions_run_outlined,
  'timer': Icons.timer_outlined,
```

All eight constants were verified to exist in Flutter 3.47.1's `icons.dart`.

- [ ] **Step 7: Providers, format, presets, and the write reporter**

`app/lib/features/trackers/application/tracker_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../bootstrap/database_provider.dart';
import '../data/tracker_clock.dart';
import '../data/tracker_repository.dart';

/// The clock every tracker read and write goes through. Tests override it to
/// stand at a chosen instant, in a chosen timezone.
final trackerClockProvider =
    Provider<TrackerClock>((ref) => const TrackerClock());

final trackerRepositoryProvider = Provider<TrackerRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TrackerRepository(
      db.trackersDao, db.trackerEntriesDao, ref.watch(trackerClockProvider));
});

/// Today's local date, as the tracker screens see it.
///
/// Not re-read on every build: a screen left open overnight has to be told
/// the day changed. `TrackerDayRollover` does that at local midnight and on
/// every resume.
class TrackerToday extends Notifier<DateKey> {
  @override
  DateKey build() => ref.watch(trackerClockProvider).today();

  /// Re-reads the clock. Changes nothing until the date has moved, so a resume
  /// at noon rebuilds nothing.
  void refresh() {
    final today = ref.read(trackerClockProvider).today();
    if (today != state) state = today;
  }
}

final trackerTodayProvider =
    NotifierProvider<TrackerToday, DateKey>(TrackerToday.new);

/// The tab's trackers: live, unarchived, in the user's order.
final trackersProvider = StreamProvider<List<Tracker>>(
    (ref) => ref.watch(trackerRepositoryProvider).watchTrackers());

/// Every tracker's total for today, keyed by tracker id.
final trackerTotalsProvider = StreamProvider<Map<String, double>>((ref) => ref
    .watch(trackerRepositoryProvider)
    .watchTotals(ref.watch(trackerTodayProvider)));
```

`app/lib/features/trackers/application/tracker_format.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';

/// How tracker numbers read: digits, separators, units, times and dates.
///
/// Digits follow the settings locale, like every other number in the app
/// (screen contract §8). Amounts go through `NumberFormat.decimalPattern` for
/// that locale, and times and durations through [Digits]. Every string that
/// shows a tracker number gets it from here, as a ready string, so the ARB
/// strings never format a number themselves.
final class TrackerFormat {
  TrackerFormat({
    required String localeTag,
    required this.persianDigits,
    required this.calendar,
  }) : _number = NumberFormat.decimalPattern(localeTag)
          ..maximumFractionDigits = 2;

  final bool persianDigits;
  final AppCalendar calendar;
  final NumberFormat _number;

  /// A count or an amount: `2.5`, `۲٫۵`, `1,250`. Two decimals at most, so a
  /// float sum like 0.1 + 0.2 reads as 0.3.
  String number(double value) => _number.format(value);

  /// A tracker's total as its type shows it: a count, an amount with its unit,
  /// or a time as h:mm.
  ///
  /// A boolean's total is the times done, which the screens put into words
  /// instead.
  String total(Tracker tracker, double total) => switch (tracker.type) {
        TrackerType.counter || TrackerType.boolean => number(total),
        TrackerType.quantity => tracker.unit == null
            ? number(total)
            : '${number(total)} ${tracker.unit}',
        TrackerType.duration => duration(TrackerValues.durationOf(total)),
      };

  /// h:mm, for totals: `1:30`, `0:12`.
  String duration(Duration value) =>
      _digits('${value.inHours}:${_two(value.inMinutes % 60)}');

  /// h:mm:ss, for a running timer, which ticks.
  String elapsed(Duration value) => _digits('${value.inHours}:'
      '${_two(value.inMinutes % 60)}:${_two(value.inSeconds % 60)}');

  /// A wall-clock time, 24-hour: `07:05`.
  String time(DateTime local) =>
      _digits('${_two(local.hour)}:${_two(local.minute)}');

  /// A date in the active calendar, written as the transaction list writes
  /// one.
  String date(DateKey day) {
    final parts = calendar.partsOf(day);
    return _digits('${parts.year}/${_two(parts.month)}/${_two(parts.day)}');
  }

  String _digits(String latin) =>
      persianDigits ? Digits.toPersian(latin) : latin;

  static String _two(int value) => value.toString().padLeft(2, '0');
}

final trackerFormatProvider = Provider<TrackerFormat>((ref) => TrackerFormat(
      localeTag: ref.watch(localeProvider).languageCode,
      persianDigits: ref.watch(moneyFormatterProvider).persianDigits,
      calendar: ref.watch(calendarProvider),
    ));
```

`app/lib/features/trackers/data/tracker_presets.dart`:

```dart
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import 'tracker_draft.dart';

/// The four trackers the empty tab offers, named in the current language.
///
/// Colours come from the category swatches rather than literals, so a
/// token-sheet swap recolours them with everything else.
List<TrackerDraft> trackerPresets(AppLocalizations l10n) => [
      TrackerDraft(
        name: l10n.trackerPresetWater,
        iconKey: 'water_drop',
        color: _swatch('blue'),
        type: TrackerType.quantity,
        unit: l10n.trackerPresetWaterUnit,
        perTapValue: 0.25,
      ),
      TrackerDraft(
        name: l10n.trackerPresetCigarettes,
        iconKey: 'smoking_rooms',
        color: _swatch('slate'),
        type: TrackerType.counter,
      ),
      TrackerDraft(
        name: l10n.trackerPresetGym,
        iconKey: 'fitness_center',
        color: _swatch('green'),
        type: TrackerType.boolean,
      ),
      TrackerDraft(
        name: l10n.trackerPresetSleep,
        iconKey: 'bedtime',
        color: _swatch('indigo'),
        type: TrackerType.duration,
      ),
    ];

int _swatch(String name) {
  final color = NimbusColors.categorySwatches[name];
  if (color == null) throw StateError('no category swatch "$name"');
  return color.toARGB32();
}
```

`app/lib/features/trackers/presentation/widgets/tracker_write.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// Runs a tracker write. If it fails, says so and rethrows.
///
/// The rule the saved-view writes follow: a failed local write is rare, but
/// when it happens the user hears about it instead of watching a tap do
/// nothing, and the error still reaches the framework's error handler.
///
/// Takes its dependencies rather than a context, so it can finish after the
/// widget that started it is gone.
Future<T> reportingTrackerFailure<T>({
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required Future<T> Function() write,
}) async {
  try {
    return await write();
  } on Object {
    messenger.showSnackBar(SnackBar(content: Text(l10n.trackerWriteFailed)));
    rethrow;
  }
}
```

- [ ] **Step 8: The tab's widgets**

`app/lib/features/trackers/presentation/widgets/tracker_today_text.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';

/// What a tracker has done today, in its own terms: "3 today", "Done today",
/// "0.75 L today", "1:30 today". The tab's tiles and the detail header say it
/// the same way.
class TrackerTodayText extends ConsumerWidget {
  const TrackerTodayText({
    super.key,
    required this.tracker,
    required this.total,
    this.style,
  });

  final Tracker tracker;
  final double total;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final format = ref.watch(trackerFormatProvider);
    final text = switch (tracker.type) {
      TrackerType.boolean => TrackerValues.isDone(total)
          ? l10n.trackerDoneToday
          : l10n.trackerNotDoneToday,
      _ => l10n.trackerTodayTotal(format.total(tracker, total)),
    };
    return Text(text, style: style);
  }
}
```

`app/lib/features/trackers/presentation/widgets/tracker_tile.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import 'tracker_today_text.dart';

/// One tracker on the tab: its icon, its name and today's total.
class TrackerTile extends StatelessWidget {
  const TrackerTile({super.key, required this.tracker, required this.total});

  final Tracker tracker;
  final double total;

  @override
  Widget build(BuildContext context) => ListTile(
        key: Key('tracker-tile-${tracker.id}'),
        minTileHeight: NimbusTokens.minTapTarget + NimbusTokens.space6,
        leading: ExcludeSemantics(
          child: Icon(nimbusIconFor(tracker.iconKey),
              color: Color(tracker.color)),
        ),
        title: Text(tracker.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: TrackerTodayText(
          key: Key('tracker-total-${tracker.id}'),
          tracker: tracker,
          total: total,
        ),
      );
}
```

`app/lib/features/trackers/presentation/widgets/tracker_presets_empty.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_providers.dart';
import '../../data/tracker_presets.dart';
import 'tracker_write.dart';

/// The tab's empty state: what a tracker is, and the four presets to start
/// with.
///
/// Several can be chosen at once and added together. The empty state
/// disappears with the first tracker, so a tap-to-create-one would only ever
/// let a user pick one preset.
class TrackerPresetsEmpty extends ConsumerStatefulWidget {
  const TrackerPresetsEmpty({super.key});

  @override
  ConsumerState<TrackerPresetsEmpty> createState() =>
      _TrackerPresetsEmptyState();
}

class _TrackerPresetsEmptyState extends ConsumerState<TrackerPresetsEmpty> {
  /// Stable test keys, in the presets' order.
  static const _slugs = ['water', 'cigarettes', 'gym', 'sleep'];

  final _chosen = <int>{};

  void _add() {
    final l10n = AppLocalizations.of(context);
    final presets = trackerPresets(l10n);
    final chosen = [
      for (final (index, preset) in presets.indexed)
        if (_chosen.contains(index)) preset,
    ];
    unawaited(reportingTrackerFailure(
      messenger: ScaffoldMessenger.of(context),
      l10n: l10n,
      write: () => ref.read(trackerRepositoryProvider).createAll(chosen),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final presets = trackerPresets(l10n);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NimbusTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.checklist_outlined,
                  size: NimbusTokens.space8 * 1.5,
                  color: theme.colorScheme.primary),
            ),
            const SizedBox(height: NimbusTokens.space4),
            Text(l10n.trackerEmptyTitle,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: NimbusTokens.space2),
            Text(l10n.trackerEmptyMessage,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: NimbusTokens.space6),
            Wrap(
              key: const Key('tracker-presets'),
              alignment: WrapAlignment.center,
              spacing: NimbusTokens.space2,
              runSpacing: NimbusTokens.space2,
              children: [
                for (final (index, preset) in presets.indexed)
                  FilterChip(
                    key: Key('tracker-preset-${_slugs[index]}'),
                    avatar: Icon(nimbusIconFor(preset.iconKey)),
                    label: Text(preset.name),
                    selected: _chosen.contains(index),
                    onSelected: (on) => setState(
                        () => on ? _chosen.add(index) : _chosen.remove(index)),
                  ),
              ],
            ),
            const SizedBox(height: NimbusTokens.space6),
            FilledButton(
              key: const Key('tracker-presets-add'),
              onPressed: _chosen.isEmpty ? null : _add,
              child: Text(l10n.trackerPresetsAdd),
            ),
          ],
        ),
      ),
    );
  }
}
```

`app/lib/features/trackers/presentation/widgets/tracker_day_rollover.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/tracker_providers.dart';

/// Moves `trackerTodayProvider` to the new day while a tracker screen is
/// open: at local midnight, and whenever the app returns to the foreground.
/// A phone left on the tab overnight must not keep showing yesterday's
/// totals.
///
/// The timer lives in this widget's state rather than in a provider, so it
/// ends with the screen that needs it.
class TrackerDayRollover extends ConsumerStatefulWidget {
  const TrackerDayRollover({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TrackerDayRollover> createState() =>
      _TrackerDayRolloverState();
}

class _TrackerDayRolloverState extends ConsumerState<TrackerDayRollover> {
  Timer? _midnight;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _rollOver);
    _schedule();
  }

  /// Arms a timer for just past the next local midnight.
  ///
  /// Computed from the wall clock each time rather than as a fixed 24 hours.
  /// A daylight-saving night (23 or 25 hours) then shifts only one firing,
  /// and the re-arm after it lands on the true midnight.
  void _schedule() {
    _midnight?.cancel();
    final clock = ref.read(trackerClockProvider);
    final local = clock.toLocal(clock.nowUtc());
    final sinceMidnight = Duration(
      hours: local.hour,
      minutes: local.minute,
      seconds: local.second,
      milliseconds: local.millisecond,
    );
    _midnight = Timer(
      const Duration(days: 1) - sinceMidnight + const Duration(seconds: 1),
      _rollOver,
    );
  }

  void _rollOver() {
    ref.read(trackerTodayProvider.notifier).refresh();
    _schedule();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

- [ ] **Step 9: The screen and the route**

`app/lib/features/trackers/presentation/trackers_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../application/tracker_providers.dart';
import 'widgets/tracker_day_rollover.dart';
import 'widgets/tracker_presets_empty.dart';
import 'widgets/tracker_tile.dart';

/// The Trackers tab: every tracker with today's total and its one-tap action.
class TrackersScreen extends ConsumerWidget {
  const TrackersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final trackers = ref.watch(trackersProvider);
    final totals = ref.watch(trackerTotalsProvider);

    // hasError and hasValue rather than a switch on the AsyncValue subtype: a
    // refresh carries the previous value, and blanking the list to a skeleton
    // between two emissions reads as a flicker.
    final Widget body;
    if (trackers.hasError || totals.hasError) {
      body = NimbusErrorState(
        title: l10n.trackerErrorTitle,
        retryLabel: l10n.commonRetry,
        detail: (trackers.error ?? totals.error).toString(),
        onRetry: () {
          ref.invalidate(trackersProvider);
          ref.invalidate(trackerTotalsProvider);
        },
      );
    } else if (!trackers.hasValue || !totals.hasValue) {
      body = const NimbusLoadingList(rows: 4);
    } else if (trackers.requireValue.isEmpty) {
      body = const TrackerPresetsEmpty();
    } else {
      final list = trackers.requireValue;
      final today = totals.requireValue;
      body = ListView.builder(
        key: const Key('trackers-list'),
        // Anchored to the bottom: the first trackers sit in thumb reach above
        // the nav bar (screen contract §1.3, one-handed reach).
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: NimbusTokens.space2),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final tracker = list[index];
          return TrackerTile(tracker: tracker, total: today[tracker.id] ?? 0);
        },
      );
    }

    return TrackerDayRollover(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.trackerScreenTitle)),
        body: body,
      ),
    );
  }
}
```

`app/lib/features/trackers/routes.dart`:

```dart
import 'package:go_router/go_router.dart';

import 'presentation/trackers_screen.dart';

const trackersRoute = '/trackers';

/// A nav-shell destination, so it keeps the bottom bar.
final trackerShellRoutes = <RouteBase>[
  GoRoute(
    path: trackersRoute,
    name: 'trackers',
    builder: (context, state) => const TrackersScreen(),
  ),
];
```

`app/lib/bootstrap/app_shell.dart`:
- Add `import '../features/trackers/routes.dart';`.
- Make `destinations` `[transactionListRoute, trackersRoute, analyticsRoute, settingsRoute]`.
- Update the class comment's "Only these three" to "Only these four".
- Insert a second `NavigationDestination` between Home and Analytics:

```dart
          NavigationDestination(
            icon: const Icon(Icons.checklist_outlined),
            selectedIcon: const Icon(Icons.checklist),
            label: l10n.navTrackers,
          ),
```

`app/lib/bootstrap/app_router.dart`:
- Add `import '../features/trackers/routes.dart';`, keeping the feature imports alphabetical.
- Add `...trackerShellRoutes,` inside the `ShellRoute`'s routes, between `...transactionShellRoutes,` and `...analyticsShellRoutes,`. The list order is the bar's order.

- [ ] **Step 10: Run the tests to confirm GREEN**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/ C:/Users/nimae/Desktop/nimbustats/app/test/bootstrap/ C:/Users/nimae/Desktop/nimbustats/app/test/localization_test.dart`
Expected: PASS.

**Mutation checks:**
- Remove `reverse: true` from the tab's list. "the first tracker sits lowest" must FAIL.
- In `TrackerDayRollover.initState`, delete the `AppLifecycleListener` line, and make `dispose` skip it. "coming back to the app on a new day" must FAIL.
- In `_schedule`, comment out the `Timer(...)` assignment. "at local midnight…" must FAIL.

Restore all three.

- [ ] **Step 11: Run the full gate**

Expected: all green.

- [ ] **Step 12: Commit**

```bash
git add app/lib/features/trackers/ app/lib/bootstrap/app_shell.dart app/lib/bootstrap/app_router.dart \
  app/lib/l10n/ packages/nimbus_design/lib/src/widgets/icon_picker.dart \
  app/test/features/trackers/ app/test/bootstrap/app_shell_navigation_test.dart
git commit -m "$(cat <<'EOF'
feat(trackers): the Trackers tab, with presets and today's totals

A fourth nav destination: Home, Trackers, Analytics, Settings. The
list is anchored to the bottom, so the first trackers sit in thumb
reach. Each tile says what the tracker did today in its own terms. The
empty tab explains trackers and offers Water, Cigarettes, Gym and
Sleep, named in the current language. Several can be chosen at once,
because the empty state is gone after the first.

Today rolls over at local midnight and on every resume, so a phone
left on the tab overnight stops showing yesterday.

Every tracker number is formatted by TrackerFormat and handed to the
ARB strings ready-made, so digits follow the settings locale like the
rest of the app rather than the strings' locale.

Touches other owners' files:
- nimbus_design's icon map (Phase 1) gains eight habit glyphs;
- app_shell.dart and app_router.dart gain the destination;
- app_shell_navigation_test.dart's indexes move up by one.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git switch phase/4-trackers && git merge --ff-only feat/trackers-tab
```

---

### Task 6: Counter and boolean entry — one tap, haptic, undo

Branch `feat/tracker-tap`, slug `tracker-tap`.

**Files:**
- Create: `app/lib/features/trackers/presentation/widgets/tracker_action_button.dart`
- Create: `app/lib/features/trackers/presentation/widgets/tracker_logger.dart`
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_tile.dart` (the trailing action)
- Modify: the ARBs (six keys) and the generated localizations
- Modify: `app/test/features/trackers/support/tracker_fixture.dart` (`captureHaptics`)
- Test: `app/test/features/trackers/tracker_entry_test.dart`

**Interfaces:**
- Consumes:
  - Task 4: `TrackerRepository.logEntry`, `clearToday`, `restoreEntries`, `deleteEntry` and `totalOn`.
  - Task 5: `trackerRepositoryProvider`, `trackerFormatProvider`, `reportingTrackerFailure` and `TrackerTile`.
- Produces:
  - `TrackerActionButton({required Tracker tracker, required double total})`, keyed `tracker-action-<id>` (one semantics node, label and actions declared on it).
  - `TrackerLogger({required ScaffoldMessengerState messenger, required AppLocalizations l10n, required TrackerRepository repository, required TrackerFormat format, required Tracker tracker})`, with:
    - `Future<void> log({double? value})`;
    - `Future<void> toggleDone({required bool done})`.
  - ARB keys:
    - `trackerAddOne(String name)`;
    - `trackerLoggedToday(String name, String total)`;
    - `trackerMarkDone(String name)` and `trackerMarkNotDone(String name)`;
    - `trackerMarkedDone(String name)` and `trackerMarkedNotDone(String name)`.
  - Fixture: `List<String> captureHaptics(WidgetTester)`.

- [ ] **Step 1: Write the failing tests**

Append to `app/test/features/trackers/support/tracker_fixture.dart`, adding `import 'package:flutter/services.dart';` at the top:

```dart
/// Records every haptic the app asks for, as the platform channel sees it:
/// `HapticFeedbackType.lightImpact` and so on.
List<String> captureHaptics(WidgetTester tester) {
  final haptics = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments.toString());
      }
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return haptics;
}
```

`app/test/features/trackers/tracker_entry_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late TrackerRepository repo;
  late Tracker cig;
  late Tracker g;

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    await useEnglishDigits(db);
    repo = repositoryFor(db, fake);
    [cig, g] = await repo.createAll([cigarettes, gym]);
  });
  tearDown(() => db.close());

  Future<void> openTab(WidgetTester tester) => pumpApp(tester,
      database: db,
      initialLocation: trackersRoute,
      overrides: trackerOverrides(fake));

  Finder action(Tracker t) => find.byKey(Key('tracker-action-${t.id}'));
  Future<int> count(Tracker t) async =>
      (await repo.entriesPage(t.id, limit: 1000)).items.length;

  group('counter', () {
    testWidgets('one tap adds one cigarette and says so', (tester) async {
      await openTab(tester);
      await tester.tap(action(cig));
      await tester.pumpAndSettle();

      expect(await count(cig), 1);
      expect(textIn(tester, Key('tracker-total-${cig.id}')), '1 today');
      expect(find.text('Cigarettes · 1 today'), findsOneWidget);
    });

    testWidgets('a tap fires a light haptic', (tester) async {
      final haptics = captureHaptics(tester);
      await openTab(tester);
      await tester.tap(action(cig));
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('each tap replaces the snackbar instead of queueing behind it',
        (tester) async {
      await openTab(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(action(cig));
        await tester.pumpAndSettle();
      }
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Cigarettes · 3 today'), findsOneWidget);
    });

    testWidgets('undo removes exactly the entry that tap logged',
        (tester) async {
      await openTab(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(action(cig));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(await count(cig), 2);
      expect(textIn(tester, Key('tracker-total-${cig.id}')), '2 today');
    });
  });

  group('boolean', () {
    testWidgets('a tap marks gym done for today, with a medium haptic',
        (tester) async {
      final haptics = captureHaptics(tester);
      await openTab(tester);
      await tester.tap(action(g));
      await tester.pumpAndSettle();

      expect(textIn(tester, Key('tracker-total-${g.id}')), 'Done today');
      expect(find.text('Gym · done today'), findsOneWidget);
      expect(haptics, ['HapticFeedbackType.mediumImpact']);
    });

    testWidgets('a tap on a done gym takes it back, and undo restores it',
        (tester) async {
      await openTab(tester);
      await tester.tap(action(g));
      await tester.pumpAndSettle();
      await tester.tap(action(g));
      await tester.pumpAndSettle();

      expect(textIn(tester, Key('tracker-total-${g.id}')), 'Not done today');
      expect(find.text('Gym · not done today'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(textIn(tester, Key('tracker-total-${g.id}')), 'Done today');
      expect(await count(g), 1);
    });

    testWidgets('a double-tap logs done once', (tester) async {
      await openTab(tester);
      // No pump between the taps: the second lands before the tile has
      // rebuilt as done, exactly as a fast double-tap would.
      await tester.tap(action(g));
      await tester.tap(action(g));
      await tester.pumpAndSettle();

      expect(await count(g), 1);
      expect(textIn(tester, Key('tracker-total-${g.id}')), 'Done today');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the buttons say what they do to a screen reader',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openTab(tester);

    expect(
        tester.getSemantics(action(cig)),
        containsSemantics(
            label: 'Add one to Cigarettes', isButton: true, hasTapAction: true));
    expect(tester.getSemantics(action(g)),
        containsSemantics(label: 'Mark Gym done', isButton: true));

    await tester.tap(action(g));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(action(g)),
        containsSemantics(label: 'Mark Gym not done'));
    semantics.dispose();
  });

  testWidgets('the action is at least a minimum tap target', (tester) async {
    await openTab(tester);
    final size = tester.getSize(action(cig));
    expect(size.width, greaterThanOrEqualTo(NimbusTokens.minTapTarget));
    expect(size.height, greaterThanOrEqualTo(NimbusTokens.minTapTarget));
  });

  testWidgets('a failed write says so and still reaches the error handler',
      (tester) async {
    // A write failure injected where SQLite itself would raise one.
    await db.customStatement(
        'CREATE TEMP TRIGGER fail_entry BEFORE INSERT ON tracker_entries '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END");
    await openTab(tester);

    // Caught here because it comes from a detached future the tap never
    // awaits, which is how it reaches the framework's handler in the app.
    Object? caught;
    await runZonedGuarded(() async {
      await tester.tap(action(cig));
      await tester.pumpAndSettle();
    }, (error, stack) => caught = error);

    expect(find.text('Could not save. Try again.'), findsOneWidget);
    expect(caught, isNotNull);
    expect(await count(cig), 0);
  });
}
```

- [ ] **Step 2: Run the tests to confirm RED**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/tracker_entry_test.dart`
Expected: FAIL. Every `tap(action(...))` throws `Bad state: No element`, because no widget is keyed `tracker-action-<id>` yet.

- [ ] **Step 3: Tag the rollback target**

Run: `git tag pre-tracker-tap`

- [ ] **Step 4: Add the strings**

Write the scratchpad file `keys_task6.json`:

```json
{
  "en": {
    "trackerAddOne": "Add one to {name}",
    "@trackerAddOne": {"placeholders": {"name": {"type": "String"}}},
    "trackerLoggedToday": "{name} · {total} today",
    "@trackerLoggedToday": {"placeholders": {"name": {"type": "String"}, "total": {"type": "String"}}},
    "trackerMarkDone": "Mark {name} done",
    "@trackerMarkDone": {"placeholders": {"name": {"type": "String"}}},
    "trackerMarkNotDone": "Mark {name} not done",
    "@trackerMarkNotDone": {"placeholders": {"name": {"type": "String"}}},
    "trackerMarkedDone": "{name} · done today",
    "@trackerMarkedDone": {"placeholders": {"name": {"type": "String"}}},
    "trackerMarkedNotDone": "{name} · not done today",
    "@trackerMarkedNotDone": {"placeholders": {"name": {"type": "String"}}}
  },
  "fa": {
    "trackerAddOne": "یکی به {name} اضافه کن",
    "trackerLoggedToday": "{name} · امروز {total}",
    "trackerMarkDone": "{name} را انجام\u200cشده علامت بزن",
    "trackerMarkNotDone": "علامت انجام {name} را بردار",
    "trackerMarkedDone": "{name} · امروز انجام شد",
    "trackerMarkedNotDone": "{name} · امروز انجام نشده"
  }
}
```

Run `python <scratchpad>/arb_add.py <scratchpad>/keys_task6.json`, then `git diff --numstat app/lib/l10n/` (deletions 0), then `cd app && flutter gen-l10n`.

- [ ] **Step 5: The logger**

`app/lib/features/trackers/presentation/widgets/tracker_logger.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../data/tracker_repository.dart';
import 'tracker_write.dart';

/// What a tap on a tracker does, wherever it happens: the tab or the detail
/// screen's quick-log bar.
///
/// Holds its dependencies rather than a BuildContext. The write and its
/// snackbar finish after the frame that started them, and the widget may be
/// gone by then.
final class TrackerLogger {
  const TrackerLogger({
    required this.messenger,
    required this.l10n,
    required this.repository,
    required this.format,
    required this.tracker,
  });

  final ScaffoldMessengerState messenger;
  final AppLocalizations l10n;
  final TrackerRepository repository;
  final TrackerFormat format;
  final Tracker tracker;

  /// Logs one tap, or [value] as a custom amount, and says so with an undo.
  ///
  /// The haptic fires before the write. Logging is optimistic, and for a
  /// one-tap counter the haptic is the whole of the feedback (brief trap).
  Future<void> log({double? value}) async {
    unawaited(tracker.type == TrackerType.boolean
        ? HapticFeedback.mediumImpact()
        : HapticFeedback.lightImpact());
    final result =
        await _write(() => repository.logEntry(tracker.id, value: value));
    switch (result) {
      case EntryLogged(:final entry):
        final total = await repository.totalOn(tracker.id, entry.localDateKey);
        _showUndo(
          tracker.type == TrackerType.boolean
              ? l10n.trackerMarkedDone(tracker.name)
              : l10n.trackerLoggedToday(
                  tracker.name, format.total(tracker, total)),
          () => repository.deleteEntry(entry.id),
        );
      case AlreadyDoneToday():
        // A double-tap on "done". The first tap's entry already holds the
        // day, and the tile shows it.
        break;
    }
  }

  /// A boolean tracker's tap: done when it is not, not done when it is.
  Future<void> toggleDone({required bool done}) async {
    if (!done) return log();
    unawaited(HapticFeedback.mediumImpact());
    final cleared = await _write(() => repository.clearToday(tracker.id));
    _showUndo(
      l10n.trackerMarkedNotDone(tracker.name),
      // DayWrite.dayAlreadyDone here means the day was marked done again in
      // the meantime, which is what the undo wanted anyway.
      () => repository.restoreEntries(cleared),
    );
  }

  Future<T> _write<T>(Future<T> Function() write) =>
      reportingTrackerFailure(messenger: messenger, l10n: l10n, write: write);

  /// Shows [message] with an undo, replacing whatever snackbar is up, so
  /// rapid taps leave one snackbar with the latest total rather than a queue.
  void _showUndo(String message, Future<Object?> Function() undo) {
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(nimbusUndoSnackBar(
        message: message,
        undoLabel: l10n.commonUndo,
        onUndo: () => unawaited(_write(undo)),
      ));
  }
}
```

- [ ] **Step 6: The action button, and the tile's trailing slot**

`app/lib/features/trackers/presentation/widgets/tracker_action_button.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../application/tracker_providers.dart';
import 'tracker_logger.dart';

/// A tracker's one-tap action: +1, done, +amount, or start/stop.
///
/// The same widget on the tab and in the detail screen's quick-log bar, so a
/// tap means the same thing, and writes through the same path, wherever it
/// happens.
class TrackerActionButton extends ConsumerWidget {
  const TrackerActionButton({
    super.key,
    required this.tracker,
    required this.total,
  });

  final Tracker tracker;

  /// Today's total, which decides a boolean tracker's done state.
  final double total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    TrackerLogger logger() => TrackerLogger(
          messenger: ScaffoldMessenger.of(context),
          l10n: l10n,
          repository: ref.read(trackerRepositoryProvider),
          format: ref.read(trackerFormatProvider),
          tracker: tracker,
        );
    final key = Key('tracker-action-${tracker.id}');
    final done = TrackerValues.isDone(total);

    return switch (tracker.type) {
      TrackerType.counter => _ActionButton(
          key: key,
          label: l10n.trackerAddOne(tracker.name),
          onTap: () => unawaited(logger().log()),
          child: const Icon(Icons.add),
        ),
      TrackerType.boolean => _ActionButton(
          key: key,
          label: done
              ? l10n.trackerMarkNotDone(tracker.name)
              : l10n.trackerMarkDone(tracker.name),
          selected: done,
          onTap: () => unawaited(logger().toggleDone(done: done)),
          child: Icon(done ? Icons.check : Icons.check_box_outline_blank),
        ),
      // Quantity arrives in the next task and the timer in the one after;
      // until then those tiles show their totals only.
      TrackerType.quantity || TrackerType.duration => const SizedBox.shrink(),
    };
  }
}

/// The stadium-shaped button every action uses.
///
/// One semantics node says what the tap does, and the glyph inside is
/// decoration. `excludeSemantics` drops the InkWell's own actions, so they are
/// declared on the node instead.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.longPressHint,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? longPressHint;
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected ? scheme.primary : scheme.secondaryContainer;
    final foreground =
        selected ? scheme.onPrimary : scheme.onSecondaryContainer;

    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressHint: longPressHint,
      excludeSemantics: true,
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: NimbusTokens.minTapTarget + NimbusTokens.space4,
              minHeight: NimbusTokens.minTapTarget,
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: NimbusTokens.space3),
              child: Center(
                widthFactor: 1,
                child: IconTheme.merge(
                  data: IconThemeData(color: foreground),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                        color: foreground, fontWeight: FontWeight.w600),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

In `tracker_tile.dart`, add `import 'tracker_action_button.dart';`, and a `trailing` to the `ListTile`:

```dart
        trailing: TrackerActionButton(tracker: tracker, total: total),
```

- [ ] **Step 7: Run the tests to confirm GREEN**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/`
Expected: PASS.

**Mutation checks:**
- In `TrackerLogger._showUndo`, drop `..removeCurrentSnackBar()`. "each tap replaces the snackbar" must FAIL.
- In `toggleDone`, call `log()` whatever `done` is. "a tap on a done gym takes it back" must FAIL.
- In the boolean branch of `TrackerActionButton`, always pass `l10n.trackerMarkDone(...)` as the label. The screen-reader test must FAIL on "Mark Gym not done".

Restore all three.

- [ ] **Step 8: Run the full gate**

Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add app/lib/features/trackers/presentation/widgets/ app/lib/l10n/ app/test/features/trackers/
git commit -m "$(cat <<'EOF'
feat(trackers): one-tap counter and boolean entry, with undo

A counter's +1 and a boolean's done are one tap, with a haptic fired
before the write: for a counter it is the whole of the feedback.
Each tap replaces the snackbar ("Cigarettes · 3 today"), and its undo
removes exactly the entry that tap logged.

A tap on a done boolean takes today back, with undo. A double-tap on
"done" writes once: the second tap meets the once-per-day index and
comes back as AlreadyDoneToday, which the screen treats as nothing to
say.

TrackerActionButton and TrackerLogger are shared with the detail
screen's quick-log bar later, so a tap writes through one path
wherever it happens. A failed write is said and rethrown to the
framework's error handler, never swallowed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git switch phase/4-trackers && git merge --ff-only feat/tracker-tap
```

---

### Task 7: Quantity entry — the per-tap amount, and another amount on long-press

Branch `feat/tracker-quantity`, slug `tracker-quantity`.

**Files:**
- Create: `app/lib/features/trackers/presentation/widgets/tracker_amount_sheet.dart`
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_action_button.dart` (the quantity branch)
- Modify: the ARBs (five keys) and the generated localizations
- Test: `app/test/features/trackers/tracker_quantity_test.dart`

**Interfaces:**
- Consumes:
  - Task 2: `TrackerValues.parseAmount` and `TrackerValues.perTap`.
  - Task 6: `TrackerLogger.log({double? value})` and `_ActionButton(onLongPress:, longPressHint:)`.
- Produces:
  - `Future<double?> showTrackerAmountSheet(BuildContext context, {required Tracker tracker})`.
  - Keys `tracker-amount-field` and `tracker-amount-log`.
  - ARB keys:
    - `trackerAddAmount(String amount, String name)`;
    - `trackerAmountInvalid`, `trackerAmountLabel`, `trackerLogAction` and `trackerOtherAmount`.

- [ ] **Step 1: Write the failing tests**

`app/test/features/trackers/tracker_quantity_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_draft.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late TrackerRepository repo;
  late Tracker w;

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    repo = repositoryFor(db, fake);
  });
  tearDown(() => db.close());

  Future<void> openTab(WidgetTester tester, {Locale locale = const Locale('en')}) =>
      pumpApp(tester,
          database: db,
          initialLocation: trackersRoute,
          locale: locale,
          overrides: trackerOverrides(fake));

  Finder action() => find.byKey(Key('tracker-action-${w.id}'));
  String total(WidgetTester tester) =>
      textIn(tester, Key('tracker-total-${w.id}'));

  Future<void> logOther(WidgetTester tester, String typed) async {
    await tester.longPress(action());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tracker-amount-field')), typed);
    await tester.tap(find.byKey(const Key('tracker-amount-log')));
    await tester.pumpAndSettle();
  }

  group('in English', () {
    setUp(() async {
      await useEnglishDigits(db);
      w = await repo.create(water);
    });

    testWidgets('one tap logs the per-tap amount', (tester) async {
      await openTab(tester);
      expect(
          find.descendant(of: action(), matching: find.text('+0.25')),
          findsOneWidget);

      await tester.tap(action());
      await tester.pumpAndSettle();
      await tester.tap(action());
      await tester.pumpAndSettle();

      expect(total(tester), '0.5 L today');
      expect(find.text('Water · 0.5 L today'), findsOneWidget);
    });

    testWidgets('a quantity tap fires a light haptic', (tester) async {
      final haptics = captureHaptics(tester);
      await openTab(tester);
      await tester.tap(action());
      await tester.pumpAndSettle();
      expect(haptics, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('a long-press logs another amount', (tester) async {
      await openTab(tester);
      await logOther(tester, '1.5');
      expect(total(tester), '1.5 L today');
    });

    testWidgets('the sheet reads Persian digits and the Persian decimal point',
        (tester) async {
      await openTab(tester);
      await logOther(tester, '۱٫۵');
      expect(total(tester), '1.5 L today');
    });

    testWidgets('an amount of zero is refused in the sheet; nothing is logged',
        (tester) async {
      await openTab(tester);
      await logOther(tester, '0');

      expect(find.text('Enter an amount above zero'), findsOneWidget);
      expect(find.byKey(const Key('tracker-amount-field')), findsOneWidget);
      expect((await repo.entriesPage(w.id)).items, isEmpty);
    });

    testWidgets("undo removes the custom amount it logged", (tester) async {
      await openTab(tester);
      await tester.tap(action());
      await tester.pumpAndSettle();
      await logOther(tester, '1.5');
      expect(find.text('Water · 1.75 L today'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(total(tester), '0.25 L today');
    });

    testWidgets('the long-press is announced, with what it does',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await openTab(tester);
      expect(
        tester.getSemantics(action()),
        containsSemantics(
          label: 'Add 0.25 L to Water',
          isButton: true,
          hasTapAction: true,
          hasLongPressAction: true,
          onLongPressHint: 'Log another amount',
        ),
      );
      semantics.dispose();
    });
  });

  testWidgets('Persian digits and unit in Persian', (tester) async {
    w = await repo.create(const TrackerDraft(
        name: 'آب',
        iconKey: 'water_drop',
        color: 0xFF1565C0,
        type: TrackerType.quantity,
        unit: 'لیتر',
        perTapValue: 0.25));
    await openTab(tester, locale: const Locale('fa'));

    await tester.tap(action());
    await tester.pumpAndSettle();

    expect(total(tester), 'امروز ۰٫۲۵ لیتر');
    expect(find.descendant(of: action(), matching: find.text('+۰٫۲۵')),
        findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to confirm RED**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/tracker_quantity_test.dart`
Expected: FAIL. `action()` finds nothing (a `SizedBox.shrink` stands in the quantity branch), so taps throw `Bad state: No element`.

- [ ] **Step 3: Tag the rollback target**

Run: `git tag pre-tracker-quantity`

- [ ] **Step 4: Add the strings**

Write the scratchpad file `keys_task7.json`:

```json
{
  "en": {
    "trackerAddAmount": "Add {amount} to {name}",
    "@trackerAddAmount": {"placeholders": {"amount": {"type": "String"}, "name": {"type": "String"}}},
    "trackerAmountInvalid": "Enter an amount above zero",
    "trackerAmountLabel": "Amount",
    "trackerLogAction": "Log",
    "trackerOtherAmount": "Log another amount"
  },
  "fa": {
    "trackerAddAmount": "{amount} به {name} اضافه کن",
    "trackerAmountInvalid": "مقداری بیشتر از صفر وارد کنید",
    "trackerAmountLabel": "مقدار",
    "trackerLogAction": "ثبت",
    "trackerOtherAmount": "ثبت مقدار دیگر"
  }
}
```

Run the helper, check `numstat` (0 deletions), and run `flutter gen-l10n`.

- [ ] **Step 5: The amount sheet**

`app/lib/features/trackers/presentation/widgets/tracker_amount_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';

/// Asks for an amount other than the tracker's per-tap one.
///
/// Resolves to the amount, or null when dismissed. Accepts every digit set
/// and decimal point a Persian keyboard produces (`TrackerValues.parseAmount`),
/// and refuses zero or less in place rather than logging it.
Future<double?> showTrackerAmountSheet(
  BuildContext context, {
  required Tracker tracker,
}) =>
    showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AmountSheet(tracker: tracker),
    );

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({required this.tracker});

  final Tracker tracker;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final value = TrackerValues.parseAmount(_amount.text);
    if (value == null) {
      setState(() => _error = AppLocalizations.of(context).trackerAmountInvalid);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: NimbusTokens.space4,
        right: NimbusTokens.space4,
        top: NimbusTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NimbusTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.trackerOtherAmount, style: theme.textTheme.titleMedium),
          const SizedBox(height: NimbusTokens.space4),
          TextField(
            key: const Key('tracker-amount-field'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.trackerAmountLabel,
              suffixText: widget.tracker.unit,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: NimbusTokens.space4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: NimbusTokens.space2),
              FilledButton(
                key: const Key('tracker-amount-log'),
                onPressed: _submit,
                child: Text(l10n.trackerLogAction),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: The quantity branch**

In `tracker_action_button.dart`:

1. Add `import 'tracker_amount_sheet.dart';`.
2. Read the format once in `build`: `final format = ref.watch(trackerFormatProvider);`.
3. Replace `TrackerType.quantity || TrackerType.duration => const SizedBox.shrink(),` with:

```dart
      TrackerType.quantity => _quantityButton(context, l10n, format, logger, key),
      // The timer arrives in the next task; until then a duration tile shows
      // its total only.
      TrackerType.duration => const SizedBox.shrink(),
```

4. Add this method to `TrackerActionButton`:

```dart
  Widget _quantityButton(
    BuildContext context,
    AppLocalizations l10n,
    TrackerFormat format,
    TrackerLogger Function() logger,
    Key key,
  ) {
    final perTap =
        TrackerValues.perTap(tracker.type, perTapValue: tracker.perTapValue)!;
    return _ActionButton(
      key: key,
      label: l10n.trackerAddAmount(format.total(tracker, perTap), tracker.name),
      longPressHint: l10n.trackerOtherAmount,
      onTap: () => unawaited(logger().log()),
      onLongPress: () => unawaited(_logOther(context, logger())),
      child: Text('+${format.number(perTap)}'),
    );
  }

  /// The logger is built before the sheet opens: once it closes, this widget
  /// may no longer be mounted, and nothing here may read its context.
  Future<void> _logOther(BuildContext context, TrackerLogger logger) async {
    final amount = await showTrackerAmountSheet(context, tracker: tracker);
    if (amount != null) await logger.log(value: amount);
  }
```

- [ ] **Step 7: Run the tests to confirm GREEN**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/`
Expected: PASS.

**Mutation checks:**
- In `_AmountSheetState._submit`, use `double.tryParse(_amount.text)`. The Persian-digits test must FAIL, and so must the zero test, since `0` parses.
- Drop `onLongPressHint: longPressHint` from `_ActionButton`'s `Semantics`. The announcement test must FAIL.

Restore both.

- [ ] **Step 8: Run the full gate**

Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add app/lib/features/trackers/presentation/widgets/ app/lib/l10n/ app/test/features/trackers/tracker_quantity_test.dart
git commit -m "$(cat <<'EOF'
feat(trackers): quantity entry -- a per-tap amount, another on long-press

One tap logs the tracker's per-tap amount ("+0.25"), per the operator's
choice. A long-press, which TalkBack announces with its hint, opens a
sheet for another amount. The sheet takes Persian and Arabic-Indic
digits and `٫` or `/` as the decimal point, and refuses zero in place
rather than logging it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git switch phase/4-trackers && git merge --ff-only feat/tracker-quantity
```

---

### Task 8: The duration timer — persisted start, live elapsed time, survives a killed process

Branch `feat/tracker-timer`, slug `tracker-timer`.

**Files:**
- Create: `app/lib/features/trackers/presentation/widgets/tracker_elapsed_text.dart`
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_action_button.dart` (the duration branch)
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_logger.dart` (`toggleTimer`)
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_today_text.dart` (a running timer shows its elapsed time)
- Modify: the ARBs (five keys) and the generated localizations
- Test: `app/test/features/trackers/tracker_timer_test.dart`

**Interfaces:**
- Consumes: Task 4's `TrackerRepository.startTimer` and `stopTimer`; Task 2's `Tracker.runningTimer` and `RunningTimer.elapsed`; Task 5's `trackerClockProvider` and `TrackerFormat.elapsed`/`duration`.
- Produces:
  - `TrackerElapsedText({required RunningTimer timer, TextStyle? style})`. It ticks once a second while mounted and reads the clock from `trackerClockProvider`.
  - `TrackerLogger.toggleTimer()`.
  - ARB keys:
    - `trackerStartTimer(String name)` and `trackerStopTimer(String name)`;
    - `trackerTimerDiscarded`;
    - `trackerTimerLogged(String name, String duration)`;
    - `trackerTimerRunning(String elapsed)`.

- [ ] **Step 1: Write the failing tests**

`app/test/features/trackers/tracker_timer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late TrackerRepository repo;
  late Tracker s;

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    await useEnglishDigits(db);
    repo = repositoryFor(db, fake);
    s = await repo.create(sleep);
  });
  tearDown(() => db.close());

  Future<void> openTab(WidgetTester tester) => pumpApp(tester,
      database: db,
      initialLocation: trackersRoute,
      overrides: trackerOverrides(fake));

  Finder action() => find.byKey(Key('tracker-action-${s.id}'));
  String status(WidgetTester tester) =>
      textIn(tester, Key('tracker-total-${s.id}'));
  Future<Tracker> stored() async => (await repo.watchTracker(s.id).first)!;

  testWidgets('start persists the start at once and shows a running timer',
      (tester) async {
    await openTab(tester);
    await tester.tap(action());
    await tester.pumpAndSettle();

    expect((await stored()).runningTimer, RunningTimer(fake.nowUtc));
    expect(status(tester), 'Running · 0:00:00');
  });

  testWidgets('the running time ticks once a second', (tester) async {
    await openTab(tester);
    await tester.tap(action());
    await tester.pumpAndSettle();

    fake.advance(const Duration(minutes: 1, seconds: 5));
    await tester.pump(const Duration(seconds: 1));

    expect(status(tester), 'Running · 0:01:05');
  });

  testWidgets('stop logs the session, stamped at its start, and says so',
      (tester) async {
    final start = fake.nowUtc;
    await openTab(tester);
    await tester.tap(action());
    await tester.pumpAndSettle();

    fake.advance(const Duration(hours: 7, minutes: 30));
    await tester.tap(action());
    await tester.pumpAndSettle();

    final entry = (await repo.entriesPage(s.id)).items.single;
    expect(entry.value, 27000);
    expect(entry.occurredAtUtc, start);
    expect(find.text('Sleep · 7:30 logged'), findsOneWidget);
    expect(status(tester), '7:30 today');
    expect((await stored()).runningTimer, isNull);
  });

  testWidgets('undo after a stop removes the session it logged',
      (tester) async {
    await openTab(tester);
    await tester.tap(action());
    await tester.pumpAndSettle();
    fake.advance(const Duration(minutes: 20));
    await tester.tap(action());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await repo.entriesPage(s.id)).items, isEmpty);
  });

  testWidgets('a double-tap on start starts one timer', (tester) async {
    final start = fake.nowUtc;
    await openTab(tester);
    await tester.tap(action());
    fake.advance(const Duration(milliseconds: 300));
    await tester.tap(action());
    await tester.pumpAndSettle();

    expect((await stored()).runningTimer, RunningTimer(start));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stopping within a second logs nothing and says so',
      (tester) async {
    await openTab(tester);
    await tester.tap(action());
    await tester.pumpAndSettle();
    await tester.tap(action());
    await tester.pumpAndSettle();

    expect(find.text('Under a second — nothing logged'), findsOneWidget);
    expect((await repo.entriesPage(s.id)).items, isEmpty);
    expect((await stored()).runningTimer, isNull);
  });

  testWidgets('a timer started before the app was killed is still running',
      (tester) async {
    // The previous process started the timer two hours ago and died. This
    // run knows only what that one persisted.
    final earlier =
        FakeClock(nowUtc: fake.nowUtc.subtract(const Duration(hours: 2)));
    await repositoryFor(db, earlier).startTimer(s.id);

    await openTab(tester);

    expect(status(tester), 'Running · 2:00:00');
  });

  testWidgets('start and stop use a medium haptic', (tester) async {
    final haptics = captureHaptics(tester);
    await openTab(tester);
    await tester.tap(action());
    await tester.pumpAndSettle();
    fake.advance(const Duration(minutes: 1));
    await tester.tap(action());
    await tester.pumpAndSettle();

    expect(haptics,
        ['HapticFeedbackType.mediumImpact', 'HapticFeedbackType.mediumImpact']);
  });

  testWidgets('the timer button is named for a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await openTab(tester);
    expect(tester.getSemantics(action()),
        containsSemantics(label: 'Start Sleep timer', isButton: true));

    await tester.tap(action());
    await tester.pumpAndSettle();
    expect(tester.getSemantics(action()),
        containsSemantics(label: 'Stop Sleep timer', isButton: true));
    semantics.dispose();
  });
}
```

- [ ] **Step 2: Run the tests to confirm RED**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/tracker_timer_test.dart`
Expected: FAIL. `action()` finds nothing, because the duration branch is still `SizedBox.shrink`. "a timer started before the app was killed" fails on `'0:00 today'`, not `'Running · 2:00:00'`.

- [ ] **Step 3: Tag the rollback target**

Run: `git tag pre-tracker-timer`

- [ ] **Step 4: Add the strings**

Write the scratchpad file `keys_task8.json`:

```json
{
  "en": {
    "trackerStartTimer": "Start {name} timer",
    "@trackerStartTimer": {"placeholders": {"name": {"type": "String"}}},
    "trackerStopTimer": "Stop {name} timer",
    "@trackerStopTimer": {"placeholders": {"name": {"type": "String"}}},
    "trackerTimerDiscarded": "Under a second — nothing logged",
    "trackerTimerLogged": "{name} · {duration} logged",
    "@trackerTimerLogged": {"placeholders": {"name": {"type": "String"}, "duration": {"type": "String"}}},
    "trackerTimerRunning": "Running · {elapsed}",
    "@trackerTimerRunning": {"placeholders": {"elapsed": {"type": "String"}}}
  },
  "fa": {
    "trackerStartTimer": "شروع زمان\u200cسنج {name}",
    "trackerStopTimer": "توقف زمان\u200cسنج {name}",
    "trackerTimerDiscarded": "کمتر از یک ثانیه — چیزی ثبت نشد",
    "trackerTimerLogged": "{name} · {duration} ثبت شد",
    "trackerTimerRunning": "در حال اجرا · {elapsed}"
  }
}
```

Run the helper, check `numstat` (0 deletions), and run `flutter gen-l10n`.

- [ ] **Step 5: The ticking text**

`app/lib/features/trackers/presentation/widgets/tracker_elapsed_text.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../application/tracker_providers.dart';

/// "Running · 0:12:05", computed from the persisted start on every tick.
///
/// Ticks once a second, and only while this widget is mounted: a timer tile
/// scrolled off the list stops costing anything. The time shown is always
/// now minus the stored start, never a count kept here, so a tick that is late
/// or missed changes nothing.
class TrackerElapsedText extends ConsumerStatefulWidget {
  const TrackerElapsedText({super.key, required this.timer, this.style});

  final RunningTimer timer;
  final TextStyle? style;

  @override
  ConsumerState<TrackerElapsedText> createState() => _TrackerElapsedTextState();
}

class _TrackerElapsedTextState extends ConsumerState<TrackerElapsedText> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker =
        Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed =
        widget.timer.elapsed(ref.watch(trackerClockProvider).nowUtc());
    return Text(
      AppLocalizations.of(context)
          .trackerTimerRunning(ref.watch(trackerFormatProvider).elapsed(elapsed)),
      style: widget.style,
    );
  }
}
```

In `tracker_today_text.dart`, add `import 'tracker_elapsed_text.dart';`. At the start of `build`, before `l10n`, add:

```dart
    final running = tracker.runningTimer;
    if (running != null) {
      return TrackerElapsedText(timer: running, style: style);
    }
```

- [ ] **Step 6: Start and stop**

Add to `TrackerLogger`:

```dart
  /// A duration tracker's tap: start when idle, stop when running.
  ///
  /// Start says nothing more: the tile turns into a ticking timer, which is
  /// the confirmation. Stop names the session it logged rather than today's
  /// total. The entry is stamped at the start, so it can belong to yesterday,
  /// and "today" would then be false.
  Future<void> toggleTimer() async {
    unawaited(HapticFeedback.mediumImpact());
    if (tracker.runningTimer == null) {
      // TimerAlreadyRunning is the second tap of a double-tap; the stored
      // start is already on screen either way.
      await _write(() => repository.startTimer(tracker.id));
      return;
    }
    final result = await _write(() => repository.stopTimer(tracker.id));
    switch (result) {
      case TimerStopped(:final entry):
        _showUndo(
          l10n.trackerTimerLogged(tracker.name,
              format.duration(TrackerValues.durationOf(entry.value))),
          () => repository.deleteEntry(entry.id),
        );
      case TimerDiscarded():
        messenger
          ..removeCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.trackerTimerDiscarded)));
      case TimerNotRunning():
        // The second tap of a double-tap on stop; the first logged it.
        break;
    }
  }
```

In `tracker_action_button.dart`, replace the duration branch:

```dart
      TrackerType.duration => _ActionButton(
          key: key,
          label: tracker.runningTimer == null
              ? l10n.trackerStartTimer(tracker.name)
              : l10n.trackerStopTimer(tracker.name),
          selected: tracker.runningTimer != null,
          onTap: () => unawaited(logger().toggleTimer()),
          child: Icon(
              tracker.runningTimer == null ? Icons.play_arrow : Icons.stop),
        ),
```

- [ ] **Step 7: Run the tests to confirm GREEN**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/`
Expected: PASS.

**Mutation checks:**
- In `TrackerElapsedText`, remove the `Timer.periodic` and its `cancel`. "the running time ticks once a second" must FAIL.
- In `TrackerTodayText`, delete the running-timer branch. "a timer started before the app was killed" must FAIL.

Restore both.

The ticking timer is a `State` member cancelled in `dispose`, so no test ends with a pending timer. If a test fails with "A Timer is still pending", the ticker is being created somewhere other than this widget. Fix that; never add a `pump` to hide it.

- [ ] **Step 8: Run the full gate**

Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add app/lib/features/trackers/presentation/widgets/ app/lib/l10n/ app/test/features/trackers/tracker_timer_test.dart
git commit -m "$(cat <<'EOF'
feat(trackers): the duration timer, which survives a killed process

Start persists the start the moment it is tapped, and the tile then
shows now minus that start, ticking once a second only while it is on
screen. A timer started before the app was killed is running when it
reopens, because nothing about it was ever held in memory.

Stop logs the session stamped at its start and says "Sleep · 7:30
logged" rather than today's total, since a session that began last
night belongs to yesterday. Under a second it logs nothing and says
so. A double-tap starts or stops once.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git switch phase/4-trackers && git merge --ff-only feat/tracker-timer
```

---

### Task 9: The tracker manager — create, edit, reorder, archive

Branch `feat/tracker-manager`, slug `tracker-manager`.

**Files:**
- Create: `app/lib/features/trackers/presentation/tracker_manager_screen.dart`
- Create: `app/lib/features/trackers/presentation/widgets/tracker_editor_sheet.dart`
- Modify: `app/lib/features/trackers/application/tracker_providers.dart` (`archivedTrackersProvider`)
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_logger.dart` (`archive`)
- Modify: `app/lib/features/trackers/presentation/trackers_screen.dart` (the manage button)
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_presets_empty.dart` ("Create your own")
- Modify: `app/lib/features/trackers/routes.dart`, `app/lib/bootstrap/app_router.dart` (one line)
- Modify: the ARBs (17 keys) and the generated localizations
- Test: `app/test/features/trackers/tracker_manager_screen_test.dart`

**Interfaces:**
- Consumes:
  - Task 4: `TrackerRepository.create`, `update`, `archive`, `unarchive`, `reorder` and `watchArchived`.
  - Task 5: `trackersProvider` and `reportingTrackerFailure`.
  - Task 6: `TrackerLogger`.
  - From `nimbus_design`: `IconPicker`, `ColorPicker`, `NimbusColors.defaultSwatch` and `nimbusIconFor`.
- Produces:
  - `archivedTrackersProvider` (`StreamProvider<List<Tracker>>`) and `TrackerManagerScreen`.
  - `Future<Tracker?> showTrackerEditorSheet(BuildContext context, {required TrackerRepository repository, Tracker? tracker})`.
  - `String trackerTypeLabel(AppLocalizations l10n, TrackerType type)`.
  - `TrackerLogger.archive()`.
  - Routes: `trackerManagerRoute = '/trackers/manage'`, `trackerRoutes`.
  - Keys:
    - on the screens: `tracker-manager-list`, `tracker-row-<id>`, `tracker-menu-<id>`, `tracker-menu-edit`, `tracker-menu-archive`, `tracker-archived-<id>`, `tracker-unarchive-<id>`, `tracker-add`, `trackers-manage` and `tracker-create-own`;
    - in the editor: `tracker-name-field`, `tracker-type-<name>`, `tracker-type-fixed`, `tracker-per-tap-field`, `tracker-unit-field` and `tracker-save`.
  - ARB keys:
    - `trackerArchived(String name)`, `trackerArchivedSection`;
    - `trackerCreateOwn`, `trackerEditTitle`;
    - `trackerManagerEmptyMessage`, `trackerManagerEmptyTitle`, `trackerManagerTitle`;
    - `trackerNameLabel`, `trackerNew`, `trackerPerTapLabel`;
    - `trackerTypeBoolean`, `trackerTypeCounter`, `trackerTypeDuration`, `trackerTypeFixedHint`, `trackerTypeLabel`, `trackerTypeQuantity`;
    - `trackerUnitLabel`.

- [ ] **Step 1: Write the failing tests**

`app/test/features/trackers/tracker_manager_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/application/tracker_providers.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late TrackerRepository repo;

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    await useEnglishDigits(db);
    repo = repositoryFor(db, fake);
  });
  tearDown(() => db.close());

  Future<void> openManager(WidgetTester tester) => pumpApp(tester,
      database: db,
      initialLocation: trackerManagerRoute,
      overrides: trackerOverrides(fake));

  Future<List<String>> liveNames() async =>
      [for (final t in await repo.watchTrackers().first) t.name];

  testWidgets('loading shows a skeleton', (tester) async {
    final never = StreamController<List<Tracker>>();
    addTearDown(never.close);
    await pumpApp(tester, initialLocation: trackerManagerRoute, overrides: [
      ...trackerOverrides(fake),
      trackersProvider.overrideWith((ref) => never.stream),
    ]);
    expect(find.byType(NimbusLoadingList), findsOneWidget);
  });

  testWidgets('the error state retries and hides the raw exception',
      (tester) async {
    await pumpApp(tester, initialLocation: trackerManagerRoute, overrides: [
      ...trackerOverrides(fake),
      archivedTrackersProvider.overrideWith(
          (ref) => Stream<List<Tracker>>.error(Exception('boom'))),
    ]);
    expect(find.byType(NimbusErrorState), findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
  });

  testWidgets('the empty state offers to create a tracker', (tester) async {
    await openManager(tester);
    expect(find.text('No trackers yet'), findsOneWidget);
    await tester.tap(find.text('New tracker'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tracker-name-field')), findsOneWidget);
  });

  testWidgets('creating a counter: name, icon, colour, type', (tester) async {
    await openManager(tester);
    await tester.tap(find.text('New tracker'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('tracker-name-field')), 'Coffee');
    await tester.tap(find.byKey(const Key('icon-option-local_cafe')));
    await tester.tap(find.byKey(const Key('color-option-orange')));
    await tester.tap(find.byKey(const Key('tracker-type-counter')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tracker-save')));
    await tester.pumpAndSettle();

    final coffee = (await repo.watchTrackers().first).single;
    expect(coffee.name, 'Coffee');
    expect(coffee.type, TrackerType.counter);
    expect(coffee.iconKey, 'local_cafe');
    expect(coffee.color, NimbusColors.categorySwatches['orange']!.toARGB32());
    expect(find.byKey(Key('tracker-row-${coffee.id}')), findsOneWidget);
  });

  testWidgets('a quantity cannot be saved without an amount per tap',
      (tester) async {
    await openManager(tester);
    await tester.tap(find.text('New tracker'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tracker-name-field')), 'Reading');
    await tester.tap(find.byKey(const Key('tracker-type-quantity')));
    await tester.pump();

    FilledButton save() =>
        tester.widget<FilledButton>(find.byKey(const Key('tracker-save')));
    expect(save().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('tracker-per-tap-field')), '0');
    await tester.pump();
    expect(find.text('Enter an amount above zero'), findsOneWidget);
    expect(save().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('tracker-per-tap-field')), '۱۰');
    await tester.enterText(find.byKey(const Key('tracker-unit-field')), 'pages');
    await tester.pump();
    await tester.tap(find.byKey(const Key('tracker-save')));
    await tester.pumpAndSettle();

    final reading = (await repo.watchTrackers().first).single;
    expect(reading.perTapValue, 10);
    expect(reading.unit, 'pages');
  });

  testWidgets('editing keeps the type fixed and saves the rest',
      (tester) async {
    final cig = await repo.create(cigarettes);
    await openManager(tester);

    await tester.tap(find.byKey(Key('tracker-row-${cig.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Edit tracker'), findsOneWidget);
    expect(find.byKey(const Key('tracker-type-counter')), findsNothing);
    expect(find.byKey(const Key('tracker-type-fixed')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('tracker-name-field')), 'Smokes');
    await tester.tap(find.byKey(const Key('tracker-save')));
    await tester.pumpAndSettle();

    expect(await liveNames(), ['Smokes']);
  });

  testWidgets('archive moves a tracker to the Archived section, undo returns it',
      (tester) async {
    final [cig, g] = await repo.createAll([cigarettes, gym]);
    await openManager(tester);

    await tester.tap(find.byKey(Key('tracker-menu-${cig.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tracker-menu-archive')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('tracker-archived-${cig.id}')), findsOneWidget);
    expect(find.text('Archived Cigarettes'), findsOneWidget);
    expect(await liveNames(), ['Gym']);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('tracker-row-${cig.id}')), findsOneWidget);
    expect(await liveNames(), ['Cigarettes', 'Gym']);
    expect(find.byKey(Key('tracker-row-${g.id}')), findsOneWidget);
  });

  testWidgets('unarchive returns a tracker to the tab', (tester) async {
    final cig = await repo.create(cigarettes);
    await repo.archive(cig.id);
    await openManager(tester);

    await tester.tap(find.byKey(Key('tracker-unarchive-${cig.id}')));
    await tester.pumpAndSettle();

    expect(await liveNames(), ['Cigarettes']);
  });

  Future<void> dragFirstAboveSecond(WidgetTester tester, Tracker first) async {
    // Reversed like the tab: the first tracker is the bottom row, so moving
    // it after the second is a drag *up*. Same gesture as the dashboard's
    // reorder test: a long press starts the drag on a phone, and 2.2 row
    // heights clears the neighbour's midpoint.
    final row = find.byKey(Key('tracker-row-${first.id}'));
    final height = tester.getSize(row).height;
    final gesture = await tester.startGesture(tester.getCenter(row),
        kind: PointerDeviceKind.touch);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.moveBy(Offset(0, -height * 2.2));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('dragging reorders, and the stored order follows',
      (tester) async {
    final [cig, _] = await repo.createAll([cigarettes, gym]);
    await openManager(tester);
    await dragFirstAboveSecond(tester, cig);
    expect(await liveNames(), ['Gym', 'Cigarettes']);
  });

  testWidgets('a failed reorder says so and puts the rows back',
      (tester) async {
    final [cig, g] = await repo.createAll([cigarettes, gym]);
    await db.customStatement(
        'CREATE TEMP TRIGGER fail_tracker BEFORE UPDATE ON trackers '
        "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END");
    await openManager(tester);

    Object? caught;
    await runZonedGuarded(() => dragFirstAboveSecond(tester, cig),
        (error, stack) => caught = error);

    expect(find.text('Could not save. Try again.'), findsOneWidget);
    expect(caught, isNotNull);
    expect(await liveNames(), ['Cigarettes', 'Gym']);
    // On screen too: the first tracker is back at the bottom.
    expect(tester.getCenter(find.byKey(Key('tracker-row-${cig.id}'))).dy,
        greaterThan(tester.getCenter(find.byKey(Key('tracker-row-${g.id}'))).dy));
  });

  testWidgets('the tab opens the manager from its app bar', (tester) async {
    await repo.create(cigarettes);
    await pumpApp(tester,
        database: db,
        initialLocation: trackersRoute,
        overrides: trackerOverrides(fake));

    await tester.tap(find.byKey(const Key('trackers-manage')));
    await tester.pumpAndSettle();
    expect(find.text('Manage trackers'), findsOneWidget);
  });

  testWidgets('the empty tab offers "Create your own"', (tester) async {
    await pumpApp(tester,
        database: db,
        initialLocation: trackersRoute,
        overrides: trackerOverrides(fake));

    await tester.tap(find.byKey(const Key('tracker-create-own')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tracker-name-field')), 'Reading');
    await tester.tap(find.byKey(const Key('tracker-save')));
    await tester.pumpAndSettle();

    final reading = (await repo.watchTrackers().first).single;
    expect(find.byKey(Key('tracker-tile-${reading.id}')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to confirm RED**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/tracker_manager_screen_test.dart`
Expected: FAIL to compile, with `Undefined name 'trackerManagerRoute'` and `Undefined name 'archivedTrackersProvider'`.

- [ ] **Step 3: Tag the rollback target**

Run: `git tag pre-tracker-manager`

- [ ] **Step 4: Add the strings**

Write the scratchpad file `keys_task9.json`:

```json
{
  "en": {
    "trackerArchived": "Archived {name}",
    "@trackerArchived": {"placeholders": {"name": {"type": "String"}}},
    "trackerArchivedSection": "Archived",
    "trackerCreateOwn": "Create your own",
    "trackerEditTitle": "Edit tracker",
    "trackerManagerEmptyMessage": "Create one to count anything you do.",
    "trackerManagerEmptyTitle": "No trackers yet",
    "trackerManagerTitle": "Manage trackers",
    "trackerNameLabel": "Name",
    "trackerNew": "New tracker",
    "trackerPerTapLabel": "Amount per tap",
    "trackerTypeBoolean": "Done or not",
    "trackerTypeCounter": "Count",
    "trackerTypeDuration": "Time",
    "trackerTypeFixedHint": "The type is fixed once the tracker exists.",
    "trackerTypeLabel": "Type",
    "trackerTypeQuantity": "Amount",
    "trackerUnitLabel": "Unit (optional)"
  },
  "fa": {
    "trackerArchived": "{name} بایگانی شد",
    "trackerArchivedSection": "بایگانی\u200cشده",
    "trackerCreateOwn": "خودتان بسازید",
    "trackerEditTitle": "ویرایش عادت",
    "trackerManagerEmptyMessage": "یکی بسازید تا هر کاری را که انجام می\u200cدهید بشمارید.",
    "trackerManagerEmptyTitle": "هنوز عادتی ندارید",
    "trackerManagerTitle": "مدیریت عادت\u200cها",
    "trackerNameLabel": "نام",
    "trackerNew": "عادت جدید",
    "trackerPerTapLabel": "مقدار هر لمس",
    "trackerTypeBoolean": "انجام یا نه",
    "trackerTypeCounter": "شمارش",
    "trackerTypeDuration": "زمان",
    "trackerTypeFixedHint": "نوع عادت پس از ساخت تغییر نمی\u200cکند.",
    "trackerTypeLabel": "نوع",
    "trackerTypeQuantity": "مقدار",
    "trackerUnitLabel": "واحد (اختیاری)"
  }
}
```

Run the helper, check `numstat` (0 deletions), and run `flutter gen-l10n`. The strings avoid apostrophes on purpose: in an ICU message a `'` can start an escape.

- [ ] **Step 5: Provider, logger and routes**

Append to `tracker_providers.dart`:

```dart
/// The manager's "Archived" section.
final archivedTrackersProvider = StreamProvider<List<Tracker>>(
    (ref) => ref.watch(trackerRepositoryProvider).watchArchived());
```

Add to `TrackerLogger`:

```dart
  /// Archives the tracker, with an undo. Undo, never confirm (screen contract
  /// §1.3): archiving loses nothing, and the undo puts it back.
  Future<void> archive() async {
    await _write(() => repository.archive(tracker.id));
    _showUndo(l10n.trackerArchived(tracker.name),
        () => repository.unarchive(tracker.id));
  }
```

Replace `app/lib/features/trackers/routes.dart` with:

```dart
import 'package:go_router/go_router.dart';

import 'presentation/tracker_manager_screen.dart';
import 'presentation/trackers_screen.dart';

const trackersRoute = '/trackers';

/// Pushed over the shell: managing trackers owns the whole screen.
const trackerManagerRoute = '/trackers/manage';

/// A nav-shell destination, so it keeps the bottom bar.
final trackerShellRoutes = <RouteBase>[
  GoRoute(
    path: trackersRoute,
    name: 'trackers',
    builder: (context, state) => const TrackersScreen(),
  ),
];

/// This feature's full-screen routes, composed by `app_router.dart`.
final trackerRoutes = <RouteBase>[
  GoRoute(
    path: trackerManagerRoute,
    name: 'tracker-manager',
    builder: (context, state) => const TrackerManagerScreen(),
  ),
];
```

In `app/lib/bootstrap/app_router.dart`, append `...trackerRoutes,` to the full-screen routes, after `...analyticsRoutes,`.

- [ ] **Step 6: The editor sheet**

`app/lib/features/trackers/presentation/widgets/tracker_editor_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../data/tracker_draft.dart';
import '../../data/tracker_repository.dart';
import 'tracker_write.dart';

/// Localised name for a [TrackerType]. It lives here rather than on the enum
/// because `nimbus_domain` has no ARB bundle.
String trackerTypeLabel(AppLocalizations l10n, TrackerType type) =>
    switch (type) {
      TrackerType.counter => l10n.trackerTypeCounter,
      TrackerType.boolean => l10n.trackerTypeBoolean,
      TrackerType.quantity => l10n.trackerTypeQuantity,
      TrackerType.duration => l10n.trackerTypeDuration,
    };

/// Opens the create/edit sheet for a tracker.
///
/// Resolves to the tracker just created. It is null when the sheet was
/// dismissed or an existing tracker was edited.
Future<Tracker?> showTrackerEditorSheet(
  BuildContext context, {
  required TrackerRepository repository,
  Tracker? tracker,
}) =>
    showModalBottomSheet<Tracker>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          TrackerEditorSheet(repository: repository, tracker: tracker),
    );

class TrackerEditorSheet extends ConsumerStatefulWidget {
  const TrackerEditorSheet({super.key, required this.repository, this.tracker});

  final TrackerRepository repository;
  final Tracker? tracker;

  @override
  ConsumerState<TrackerEditorSheet> createState() => _TrackerEditorSheetState();
}

class _TrackerEditorSheetState extends ConsumerState<TrackerEditorSheet> {
  late final _name = TextEditingController(text: widget.tracker?.name ?? '');
  late final _unit = TextEditingController(text: widget.tracker?.unit ?? '');
  // In the user's digits, which parseAmount reads back.
  late final _perTap = TextEditingController(
      text: switch (widget.tracker?.perTapValue) {
        final value? => ref.read(trackerFormatProvider).number(value),
        null => '',
      });
  late TrackerType _type = widget.tracker?.type ?? TrackerType.counter;
  late String _iconKey = widget.tracker?.iconKey ?? 'tag';
  late int _color =
      widget.tracker?.color ?? NimbusColors.defaultSwatch.toARGB32();

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _perTap.dispose();
    super.dispose();
  }

  double? get _perTapValue => TrackerValues.parseAmount(_perTap.text);

  bool get _isQuantity => _type == TrackerType.quantity;

  /// Save stays disabled until the tracker is complete. The repository throws
  /// on a bad definition, which is right for a programming error and wrong as
  /// the way to tell a user a field is empty.
  bool get _canSave =>
      _name.text.trim().isNotEmpty && (!_isQuantity || _perTapValue != null);

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final unit = _isQuantity ? _unit.text : null;
    final perTap = _isQuantity ? _perTapValue : null;

    final existing = widget.tracker;
    if (existing == null) {
      final created = await reportingTrackerFailure(
        messenger: messenger,
        l10n: l10n,
        write: () => widget.repository.create(TrackerDraft(
          name: _name.text,
          iconKey: _iconKey,
          color: _color,
          type: _type,
          unit: unit,
          perTapValue: perTap,
        )),
      );
      navigator.pop(created);
      return;
    }
    await reportingTrackerFailure(
      messenger: messenger,
      l10n: l10n,
      write: () => widget.repository.update(
        existing.id,
        name: _name.text,
        iconKey: _iconKey,
        color: _color,
        unit: unit,
        perTapValue: perTap,
      ),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final perTapInvalid = _perTap.text.trim().isNotEmpty && _perTapValue == null;

    return Padding(
      padding: EdgeInsets.only(
        left: NimbusTokens.space4,
        right: NimbusTokens.space4,
        top: NimbusTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NimbusTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.tracker == null ? l10n.trackerNew : l10n.trackerEditTitle,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: NimbusTokens.space4),
            TextField(
              key: const Key('tracker-name-field'),
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.trackerNameLabel,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: NimbusTokens.space4),
            if (widget.tracker == null)
              Semantics(
                label: l10n.trackerTypeLabel,
                container: true,
                // Chips that wrap rather than a segmented button: four labels
                // in Persian at a large font scale do not fit one row.
                child: Wrap(
                  spacing: NimbusTokens.space2,
                  runSpacing: NimbusTokens.space2,
                  children: [
                    for (final type in TrackerType.values)
                      ChoiceChip(
                        key: Key('tracker-type-${type.name}'),
                        label: Text(trackerTypeLabel(l10n, type)),
                        selected: _type == type,
                        onSelected: (_) => setState(() => _type = type),
                      ),
                  ],
                ),
              )
            else
              ListTile(
                key: const Key('tracker-type-fixed'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.trackerTypeLabel),
                subtitle: Text(
                    '${trackerTypeLabel(l10n, _type)} · ${l10n.trackerTypeFixedHint}'),
              ),
            if (_isQuantity) ...[
              const SizedBox(height: NimbusTokens.space4),
              TextField(
                key: const Key('tracker-per-tap-field'),
                controller: _perTap,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.trackerPerTapLabel,
                  errorText: perTapInvalid ? l10n.trackerAmountInvalid : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: NimbusTokens.space4),
              TextField(
                key: const Key('tracker-unit-field'),
                controller: _unit,
                decoration: InputDecoration(
                  labelText: l10n.trackerUnitLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: NimbusTokens.space4),
            IconPicker(
              selected: _iconKey,
              semanticsLabel: l10n.categoryIconLabel,
              onSelected: (key) => setState(() => _iconKey = key),
            ),
            const SizedBox(height: NimbusTokens.space4),
            ColorPicker(
              selected: _color,
              semanticsLabel: l10n.categoryColorLabel,
              onSelected: (value) => setState(() => _color = value),
            ),
            const SizedBox(height: NimbusTokens.space6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: NimbusTokens.space2),
                FilledButton(
                  key: const Key('tracker-save'),
                  onPressed: _canSave ? _save : null,
                  child: Text(l10n.commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: The manager screen**

`app/lib/features/trackers/presentation/tracker_manager_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../application/tracker_format.dart';
import '../application/tracker_providers.dart';
import '../data/tracker_repository.dart';
import 'widgets/tracker_editor_sheet.dart';
import 'widgets/tracker_logger.dart';
import 'widgets/tracker_write.dart';

/// Create, edit, reorder and archive trackers.
///
/// Phase 1's manager shape: the live list, which can be dragged into order,
/// an "Archived" section, and an editor sheet. There is no delete: archiving
/// keeps every entry and is undone with one tap.
class TrackerManagerScreen extends ConsumerWidget {
  const TrackerManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final live = ref.watch(trackersProvider);
    final archived = ref.watch(archivedTrackersProvider);
    final repository = ref.watch(trackerRepositoryProvider);

    final Widget body;
    var hasRows = false;
    if (live.hasError || archived.hasError) {
      body = NimbusErrorState(
        title: l10n.trackerErrorTitle,
        retryLabel: l10n.commonRetry,
        detail: (live.error ?? archived.error).toString(),
        onRetry: () {
          ref.invalidate(trackersProvider);
          ref.invalidate(archivedTrackersProvider);
        },
      );
    } else if (!live.hasValue || !archived.hasValue) {
      body = const NimbusLoadingList(rows: 4);
    } else if (live.requireValue.isEmpty && archived.requireValue.isEmpty) {
      body = NimbusEmptyState(
        icon: Icons.checklist_outlined,
        title: l10n.trackerManagerEmptyTitle,
        message: l10n.trackerManagerEmptyMessage,
        actionLabel: l10n.trackerNew,
        onAction: () => showTrackerEditorSheet(context, repository: repository),
      );
    } else {
      hasRows = true;
      body = _ManagerList(
        live: live.requireValue,
        archived: archived.requireValue,
        repository: repository,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.trackerManagerTitle)),
      body: body,
      floatingActionButton: hasRows
          ? FloatingActionButton.extended(
              key: const Key('tracker-add'),
              onPressed: () =>
                  showTrackerEditorSheet(context, repository: repository),
              icon: const Icon(Icons.add),
              label: Text(l10n.trackerNew),
            )
          : null,
    );
  }
}

class _ManagerList extends ConsumerStatefulWidget {
  const _ManagerList({
    required this.live,
    required this.archived,
    required this.repository,
  });

  final List<Tracker> live;
  final List<Tracker> archived;
  final TrackerRepository repository;

  @override
  ConsumerState<_ManagerList> createState() => _ManagerListState();
}

class _ManagerListState extends ConsumerState<_ManagerList> {
  /// The order the user just dragged to, shown until the stream catches up.
  /// If the write fails it is put back.
  List<Tracker>? _dragged;

  @override
  void didUpdateWidget(covariant _ManagerList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new list from the stream is the stored order. Stop overriding it.
    if (!identical(oldWidget.live, widget.live)) _dragged = null;
  }

  Future<void> _move(int oldIndex, int newIndex) async {
    // onReorderItem reports the final index, already adjusted for the
    // removal, so this is a plain remove-then-insert.
    final order = [...(_dragged ?? widget.live)];
    order.insert(newIndex, order.removeAt(oldIndex));
    setState(() => _dragged = order);
    try {
      await reportingTrackerFailure(
        messenger: ScaffoldMessenger.of(context),
        l10n: AppLocalizations.of(context),
        write: () => widget.repository.reorder([for (final t in order) t.id]),
      );
    } on Object {
      // The stored order never changed, so the screen must not keep showing
      // the dragged one.
      if (mounted) setState(() => _dragged = null);
      rethrow;
    }
  }

  TrackerLogger _logger(Tracker tracker) => TrackerLogger(
        messenger: ScaffoldMessenger.of(context),
        l10n: AppLocalizations.of(context),
        repository: widget.repository,
        format: ref.read(trackerFormatProvider),
        tracker: tracker,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final live = _dragged ?? widget.live;

    return ReorderableListView.builder(
      key: const Key('tracker-manager-list'),
      // Reversed like the tab, so the row at the bottom here is the tracker
      // nearest the thumb there.
      reverse: true,
      padding: const EdgeInsets.only(bottom: NimbusTokens.space8 * 3),
      itemCount: live.length,
      onReorderItem: (oldIndex, newIndex) =>
          unawaited(_move(oldIndex, newIndex)),
      footer: widget.archived.isEmpty
          ? null
          : _ArchivedSection(
              archived: widget.archived,
              onUnarchive: (tracker) => unawaited(reportingTrackerFailure(
                messenger: ScaffoldMessenger.of(context),
                l10n: l10n,
                write: () => widget.repository.unarchive(tracker.id),
              )),
            ),
      itemBuilder: (context, index) {
        final tracker = live[index];
        return ListTile(
          key: Key('tracker-row-${tracker.id}'),
          minTileHeight: NimbusTokens.minTapTarget,
          leading: ExcludeSemantics(
            child: Icon(nimbusIconFor(tracker.iconKey),
                color: Color(tracker.color)),
          ),
          title: Text(tracker.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(trackerTypeLabel(l10n, tracker.type)),
          onTap: () => showTrackerEditorSheet(context,
              repository: widget.repository, tracker: tracker),
          trailing: PopupMenuButton<_RowAction>(
            key: Key('tracker-menu-${tracker.id}'),
            onSelected: (action) {
              switch (action) {
                case _RowAction.edit:
                  unawaited(showTrackerEditorSheet(context,
                      repository: widget.repository, tracker: tracker));
                case _RowAction.archive:
                  unawaited(_logger(tracker).archive());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                key: const Key('tracker-menu-edit'),
                value: _RowAction.edit,
                child: Text(l10n.trackerEditTitle),
              ),
              PopupMenuItem(
                key: const Key('tracker-menu-archive'),
                value: _RowAction.archive,
                child: Text(l10n.commonArchive),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _RowAction { edit, archive }

class _ArchivedSection extends StatelessWidget {
  const _ArchivedSection({required this.archived, required this.onUnarchive});

  final List<Tracker> archived;
  final ValueChanged<Tracker> onUnarchive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(NimbusTokens.space4,
              NimbusTokens.space6, NimbusTokens.space4, NimbusTokens.space2),
          child: Text(l10n.trackerArchivedSection,
              style: theme.textTheme.titleSmall),
        ),
        for (final tracker in archived)
          ListTile(
            key: Key('tracker-archived-${tracker.id}'),
            leading: ExcludeSemantics(
              child: Icon(nimbusIconFor(tracker.iconKey),
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            title: Text(tracker.name,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: TextButton(
              key: Key('tracker-unarchive-${tracker.id}'),
              onPressed: () => onUnarchive(tracker),
              child: Text(l10n.commonUnarchive),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 8: The tab's way in**

In `trackers_screen.dart`:
1. Add the imports:
   ```dart
   import 'package:go_router/go_router.dart';
   import '../routes.dart';
   ```
2. Give the `AppBar` an action:

```dart
        appBar: AppBar(
          title: Text(l10n.trackerScreenTitle),
          actions: [
            IconButton(
              key: const Key('trackers-manage'),
              tooltip: l10n.trackerManagerTitle,
              icon: const Icon(Icons.tune),
              onPressed: () => context.push(trackerManagerRoute),
            ),
          ],
        ),
```

`routes.dart` imports `trackers_screen.dart`, which now imports `routes.dart`. Dart allows the import cycle.

In `tracker_presets_empty.dart`:
1. Add `import 'tracker_editor_sheet.dart';`.
2. Below the "Start tracking" `FilledButton`, add:

```dart
            const SizedBox(height: NimbusTokens.space2),
            TextButton(
              key: const Key('tracker-create-own'),
              onPressed: () => showTrackerEditorSheet(context,
                  repository: ref.read(trackerRepositoryProvider)),
              child: Text(l10n.trackerCreateOwn),
            ),
```

- [ ] **Step 9: Run the tests to confirm GREEN**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/ C:/Users/nimae/Desktop/nimbustats/app/test/ux_rules_test.dart`
Expected: PASS.

**If the drag tests do not reorder** ("dragging reorders" sees the old order):
- Check the direction first. The list is reversed, so the first row moves toward the end with a drag **up**.
- Then check the factor: the dashboard needed 2.2 row heights.
- Never change the assertion to fit.

**Mutation checks:**
- In `_ManagerListState._move`, drop the `on Object` block. "a failed reorder says so and puts the rows back" must FAIL on the on-screen order.
- Make the editor's `_canSave` return `_name.text.trim().isNotEmpty` only. "a quantity cannot be saved without an amount per tap" must FAIL.

Restore both.

- [ ] **Step 10: Run the full gate**

Expected: all green.

- [ ] **Step 11: Commit**

```bash
git add app/lib/features/trackers/ app/lib/bootstrap/app_router.dart app/lib/l10n/ \
  app/test/features/trackers/tracker_manager_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(trackers): the tracker manager

Create, rename, recolour, re-icon, reorder and archive trackers, in
Phase 1's manager shape. The type is chosen once, on creation, and
shown fixed afterwards: an entry's value means something different
under each type, so changing it would reinterpret history. A quantity
cannot be saved without an amount per tap, and the field reads Persian
digits.

The list is reversed like the tab, so the bottom row here is the
tracker nearest the thumb there. A failed reorder says so and puts the
rows back on screen as well as in storage. Archiving has an undo and
there is no delete, because archiving keeps every entry.

The tab gains its way in: a manage button, and "Create your own" on
the empty state.

Touches app_router.dart for the route line.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git switch phase/4-trackers && git merge --ff-only feat/tracker-manager
```

---

### Task 10: Tracker detail — today's total, paginated history, entry edit and delete with undo

Branch `feat/tracker-detail`, slug `tracker-detail`.

**Files:**
- Create: `app/lib/features/trackers/application/tracker_history_controller.dart`
- Create: `app/lib/features/trackers/presentation/tracker_detail_screen.dart`
- Create: `app/lib/features/trackers/presentation/widgets/tracker_entry_sheet.dart`, `tracker_duration_fields.dart`, `tracker_duration_sheet.dart`
- Modify: `app/lib/features/trackers/application/tracker_providers.dart` (`trackerByIdProvider`)
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_logger.dart` (`addDuration`, `deleteEntry`)
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_tile.dart` (tap opens detail)
- Modify: `app/lib/features/trackers/routes.dart`
- Modify: the ARBs (18 keys) and the generated localizations
- Test: `app/test/features/trackers/tracker_detail_screen_test.dart`

**Interfaces:**
- Consumes:
  - Task 4: `TrackerRepository.entriesPage`, `entryChanges`, `updateEntry`, `deleteEntry`, `restoreEntries` and `addDuration`; `TrackerEntryPage` and `TrackerEntryCursor`.
  - Task 5: `TrackerClock.toLocal` and `fromLocal`; `TrackerFormat`; `TrackerTodayText`; `TrackerDayRollover`.
  - Task 6: `TrackerActionButton`.
  - Task 9: `showTrackerEditorSheet` and `TrackerLogger.archive`.
- Produces:
  - `trackerByIdProvider` (`StreamProvider.autoDispose.family<Tracker?, String>`).
  - History:
    - `TrackerHistoryState({required List<TrackerEntry> entries, required TrackerEntryCursor? cursor, bool isLoadingMore})`, with `hasMore`;
    - `TrackerHistoryController(String trackerId)`, with `loadMore()`;
    - `trackerHistoryProvider` (`AsyncNotifierProvider.autoDispose.family<TrackerHistoryController, TrackerHistoryState, String>`).
  - `TrackerDetailScreen({required String id})`.
  - Sheets:
    - `Future<void> showTrackerEntrySheet(BuildContext, {required Tracker tracker, required TrackerEntry entry})`;
    - `Future<Duration?> showAddDurationSheet(BuildContext)`.
  - `TrackerDurationFields({required TextEditingController hours, required TextEditingController minutes, required String keyPrefix, String? errorText, ValueChanged<String>? onChanged})`, with `static Duration? read(TextEditingController hours, TextEditingController minutes)`.
  - `TrackerLogger.addDuration(Duration)` and `TrackerLogger.deleteEntry(TrackerEntry)`.
  - Routes: `trackerDetailRoute = '/tracker'`, `String trackerLocation(String id)`.
  - Keys:
    - on the screen: `tracker-detail-total`, `tracker-history`, `tracker-entry-<id>`, `tracker-entry-menu-<id>`, `tracker-entry-edit`, `tracker-entry-delete`, `tracker-quick-log`, `tracker-add-duration`, `tracker-menu`, `tracker-menu-edit-tracker` and `tracker-menu-archive-tracker`;
    - in the sheets: `tracker-entry-date`, `tracker-entry-time`, `tracker-entry-note`, `tracker-entry-amount`, `tracker-entry-hours`, `tracker-entry-minutes`, `tracker-entry-save`, `tracker-entry-day-error`, `tracker-duration-hours`, `tracker-duration-minutes` and `tracker-duration-save`.
  - ARB keys:
    - `trackerAddDuration`, `trackerDayAlreadyDone`, `trackerDone`, `trackerDurationInvalid`;
    - `trackerEntryDateLabel`, `trackerEntryDeleted`, `trackerEntryEditTitle`, `trackerEntryNoteLabel`, `trackerEntryOptions`, `trackerEntryTimeLabel`;
    - `trackerHistoryEmptyMessage`, `trackerHistoryEmptyTitle`, `trackerHistoryErrorTitle`;
    - `trackerHoursLabel`, `trackerMinutesLabel`;
    - `trackerNotFoundMessage`, `trackerNotFoundTitle`, `trackerOptions`.

**Out of this task's tests, deliberately:** driving the date and time pickers.
- Flutter's picker dialogs are the framework's, and fiddly to drive in a widget test.
- The rule they feed is pinned in Task 4: a changed time re-derives the day, and an unchanged one keeps it.
- Here the sheet is tested for showing the entry's own date and time, and for passing the original instant through untouched when only the note or value changes.

- [ ] **Step 1: Write the failing tests**

`app/test/features/trackers/tracker_detail_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/application/tracker_providers.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late TrackerRepository repo;

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    repo = repositoryFor(db, fake);
  });
  tearDown(() => db.close());

  Future<void> openDetail(WidgetTester tester, String id,
          {Locale locale = const Locale('en')}) =>
      pumpApp(tester,
          database: db,
          initialLocation: trackerLocation(id),
          locale: locale,
          overrides: trackerOverrides(fake));

  Finder row(String entryId) => find.byKey(Key('tracker-entry-$entryId'));
  Finder quickLog() => find.descendant(
      of: find.byKey(const Key('tracker-quick-log')),
      matching: find.byType(InkWell));
  Future<String> logged(Tracker t, {DateTime? at, double? value}) async =>
      (await repo.logEntry(t.id, at: at, value: value) as EntryLogged).entry.id;
  double screenHeight(WidgetTester tester) =>
      tester.view.physicalSize.height / tester.view.devicePixelRatio;

  group('states', () {
    testWidgets('loading shows a skeleton', (tester) async {
      final never = StreamController<Tracker?>();
      addTearDown(never.close);
      await pumpApp(tester, initialLocation: trackerLocation('x'), overrides: [
        ...trackerOverrides(fake),
        trackerByIdProvider('x').overrideWith((ref) => never.stream),
      ]);
      expect(find.byType(NimbusLoadingList), findsOneWidget);
    });

    testWidgets('the error state retries and hides the raw exception',
        (tester) async {
      await pumpApp(tester, initialLocation: trackerLocation('x'), overrides: [
        ...trackerOverrides(fake),
        trackerByIdProvider('x')
            .overrideWith((ref) => Stream<Tracker?>.error(Exception('boom'))),
      ]);
      expect(find.byType(NimbusErrorState), findsOneWidget);
      expect(find.text('Exception: boom'), findsNothing);
    });

    testWidgets('an unknown tracker says it is gone, with a way back',
        (tester) async {
      await openDetail(tester, 'missing');
      expect(find.text('This tracker is gone'), findsOneWidget);
      expect(find.text('Trackers'), findsOneWidget);
    });

    testWidgets('an empty history says so, with the quick log below',
        (tester) async {
      await useEnglishDigits(db);
      final cig = await repo.create(cigarettes);
      await openDetail(tester, cig.id);

      expect(textIn(tester, const Key('tracker-detail-total')), '0 today');
      expect(find.text('Nothing logged yet'), findsOneWidget);
      expect(quickLog(), findsOneWidget);
    });
  });

  group('history', () {
    setUp(() => useEnglishDigits(db));

    testWidgets('newest first, each with its day and time', (tester) async {
      final cig = await repo.create(cigarettes);
      final early = await logged(cig, at: DateTime.utc(2026, 10, 5, 9));
      final late = await logged(cig, at: DateTime.utc(2026, 10, 5, 11));
      await openDetail(tester, cig.id);

      expect(tester.getCenter(row(late)).dy,
          lessThan(tester.getCenter(row(early)).dy));
      expect(
          find.descendant(
              of: row(late), matching: find.textContaining('2026/10/05 · 14:30')),
          findsOneWidget);
      expect(textIn(tester, const Key('tracker-detail-total')), '2 today');
    });

    testWidgets('scrolling down loads older pages', (tester) async {
      final cig = await repo.create(cigarettes);
      late String oldest;
      for (var i = 0; i < 45; i++) {
        oldest = await logged(cig,
            at: fake.nowUtc.subtract(Duration(minutes: i)));
      }
      await openDetail(tester, cig.id);
      expect(row(oldest), findsNothing);

      await tester.scrollUntilVisible(row(oldest), 300,
          scrollable: find.descendant(
              of: find.byKey(const Key('tracker-history')),
              matching: find.byType(Scrollable)));
      expect(row(oldest), findsOneWidget);
    });

    testWidgets('the quick log stays in the bottom third while history scrolls',
        (tester) async {
      final cig = await repo.create(cigarettes);
      for (var i = 0; i < 30; i++) {
        await logged(cig, at: fake.nowUtc.subtract(Duration(minutes: i)));
      }
      await openDetail(tester, cig.id);
      final before = tester.getCenter(quickLog()).dy;

      await tester.drag(
          find.byKey(const Key('tracker-history')), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(tester.getCenter(quickLog()).dy, before);
      expect(before, greaterThan(screenHeight(tester) * 2 / 3));
    });

    testWidgets('a quick log adds a row and moves the header', (tester) async {
      final cig = await repo.create(cigarettes);
      await openDetail(tester, cig.id);

      await tester.tap(quickLog());
      await tester.pumpAndSettle();

      expect(textIn(tester, const Key('tracker-detail-total')), '1 today');
      final entry = (await repo.entriesPage(cig.id)).items.single;
      expect(row(entry.id), findsOneWidget);
    });
  });

  group('editing an entry', () {
    setUp(() => useEnglishDigits(db));

    testWidgets("the sheet shows the entry's own day and time", (tester) async {
      final cig = await repo.create(cigarettes);
      final id = await logged(cig);
      await openDetail(tester, cig.id);

      await tester.tap(row(id));
      await tester.pumpAndSettle();
      expect(find.text('Edit entry'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('tracker-entry-date')),
              matching: find.text('2026/10/05')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('tracker-entry-time')),
              matching: find.text('12:30')),
          findsOneWidget);
    });

    testWidgets('a note is saved and the instant is left alone',
        (tester) async {
      // Logged in Tehran at an instant with seconds and milliseconds, then
      // edited after flying to New York. A note-only edit must change neither
      // the instant nor the day; rebuilding the instant from the picker's
      // wall time would drop the milliseconds and move the day.
      final cig = await repo.create(cigarettes);
      final id =
          await logged(cig, at: DateTime.utc(2026, 10, 4, 22, 0, 7, 500));
      final before = (await repo.entriesPage(cig.id)).items.single;
      expect(before.localDateKey, const DateKey(20261005));
      fake.offset = FakeClock.newYork;
      await openDetail(tester, cig.id);

      await tester.tap(row(id));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('tracker-entry-note')), 'after lunch');
      await tester.tap(find.byKey(const Key('tracker-entry-save')));
      await tester.pumpAndSettle();

      final after = (await repo.entriesPage(cig.id)).items.single;
      expect(after.note, 'after lunch');
      expect(after.occurredAtUtc, before.occurredAtUtc);
      expect(after.localDateKey, before.localDateKey);
      expect(find.descendant(of: row(id), matching: find.textContaining('after lunch')),
          findsOneWidget);
    });

    testWidgets("a quantity's amount can be changed", (tester) async {
      final w = await repo.create(water);
      final id = await logged(w);
      await openDetail(tester, w.id);

      await tester.tap(row(id));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('tracker-entry-amount')), '0.5');
      await tester.tap(find.byKey(const Key('tracker-entry-save')));
      await tester.pumpAndSettle();

      expect(find.descendant(of: row(id), matching: find.text('0.5 L')),
          findsOneWidget);
      expect(textIn(tester, const Key('tracker-detail-total')), '0.5 L today');
    });

    testWidgets('a counter entry has no value to edit', (tester) async {
      final cig = await repo.create(cigarettes);
      final id = await logged(cig);
      await openDetail(tester, cig.id);

      await tester.tap(row(id));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tracker-entry-amount')), findsNothing);
      expect(find.byKey(const Key('tracker-entry-hours')), findsNothing);
    });

    testWidgets("a timed session's seconds survive a note-only edit",
        (tester) async {
      final s = await repo.create(sleep);
      await repo.startTimer(s.id);
      fake.advance(const Duration(hours: 7, minutes: 30, seconds: 15));
      final stopped = await repo.stopTimer(s.id) as TimerStopped;
      await openDetail(tester, s.id);

      await tester.tap(row(stopped.entry.id));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tracker-entry-note')), 'ok');
      await tester.tap(find.byKey(const Key('tracker-entry-save')));
      await tester.pumpAndSettle();

      expect((await repo.entriesPage(s.id)).items.single.value, 27015);
    });
  });

  group('deleting an entry', () {
    setUp(() => useEnglishDigits(db));

    Future<void> deleteRow(WidgetTester tester, String id) async {
      await tester.tap(find.byKey(Key('tracker-entry-menu-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracker-entry-delete')));
      await tester.pumpAndSettle();
    }

    testWidgets('delete removes the row, and undo brings it back',
        (tester) async {
      final cig = await repo.create(cigarettes);
      final id = await logged(cig);
      await openDetail(tester, cig.id);

      await deleteRow(tester, id);
      expect(row(id), findsNothing);
      expect(find.text('Entry deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(row(id), findsOneWidget);
    });

    testWidgets('an undo onto a day marked done again says so', (tester) async {
      final g = await repo.create(gym);
      final id = await logged(g);
      await openDetail(tester, g.id);

      await deleteRow(tester, id);
      // Done again from somewhere else while the snackbar is still up.
      await repo.logEntry(g.id);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('That day is already marked done'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('time', () {
    setUp(() => useEnglishDigits(db));

    testWidgets('a forgotten session is added from the detail screen',
        (tester) async {
      final s = await repo.create(sleep);
      await openDetail(tester, s.id);

      await tester.tap(find.byKey(const Key('tracker-add-duration')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('tracker-duration-hours')), '1');
      await tester.enterText(
          find.byKey(const Key('tracker-duration-minutes')), '15');
      await tester.tap(find.byKey(const Key('tracker-duration-save')));
      await tester.pumpAndSettle();

      final entry = (await repo.entriesPage(s.id)).items.single;
      expect(entry.value, 4500);
      expect(find.descendant(of: row(entry.id), matching: find.text('1:15')),
          findsOneWidget);
      expect(textIn(tester, const Key('tracker-detail-total')), '1:15 today');
    });

    testWidgets('less than a minute is refused in the sheet', (tester) async {
      final s = await repo.create(sleep);
      await openDetail(tester, s.id);

      await tester.tap(find.byKey(const Key('tracker-add-duration')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracker-duration-save')));
      await tester.pumpAndSettle();

      expect(find.text('Enter at least one minute'), findsOneWidget);
      expect((await repo.entriesPage(s.id)).items, isEmpty);
    });
  });

  group('from the tab', () {
    setUp(() => useEnglishDigits(db));

    Future<void> openFromTab(WidgetTester tester, Tracker t) async {
      await pumpApp(tester,
          database: db,
          initialLocation: trackersRoute,
          overrides: trackerOverrides(fake));
      await tester.tap(find.descendant(
          of: find.byKey(Key('tracker-tile-${t.id}')),
          matching: find.text(t.name)));
      await tester.pumpAndSettle();
    }

    testWidgets('a tile opens its tracker', (tester) async {
      final cig = await repo.create(cigarettes);
      await openFromTab(tester, cig);
      expect(find.byKey(const Key('tracker-detail-total')), findsOneWidget);
    });

    testWidgets('the menu edits the tracker', (tester) async {
      final cig = await repo.create(cigarettes);
      await openFromTab(tester, cig);

      await tester.tap(find.byKey(const Key('tracker-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracker-menu-edit-tracker')));
      await tester.pumpAndSettle();
      expect(find.text('Edit tracker'), findsOneWidget);
    });

    testWidgets('archive goes back to the tab, with an undo', (tester) async {
      final [cig, g] = await repo.createAll([cigarettes, gym]);
      await openFromTab(tester, cig);

      await tester.tap(find.byKey(const Key('tracker-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracker-menu-archive-tracker')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tracker-detail-total')), findsNothing);
      expect(find.byKey(Key('tracker-tile-${cig.id}')), findsNothing);
      expect(find.byKey(Key('tracker-tile-${g.id}')), findsOneWidget);
      expect(find.text('Archived Cigarettes'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('tracker-tile-${cig.id}')), findsOneWidget);
    });
  });

  testWidgets('Persian digits in the header and the history', (tester) async {
    final cig = await repo.create(cigarettes);
    final id = await logged(cig);
    await openDetail(tester, cig.id, locale: const Locale('fa'));

    expect(textIn(tester, const Key('tracker-detail-total')), 'امروز ۱');
    expect(
        find.descendant(of: row(id), matching: find.textContaining('۱۲:۳۰')),
        findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to confirm RED**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/tracker_detail_screen_test.dart`
Expected: FAIL to compile, with `Undefined name 'trackerLocation'` and `Undefined name 'trackerByIdProvider'`.

- [ ] **Step 3: Tag the rollback target**

Run: `git tag pre-tracker-detail`

- [ ] **Step 4: Add the strings**

Write the scratchpad file `keys_task10.json`:

```json
{
  "en": {
    "trackerAddDuration": "Add time",
    "trackerDayAlreadyDone": "That day is already marked done",
    "trackerDone": "Done",
    "trackerDurationInvalid": "Enter at least one minute",
    "trackerEntryDateLabel": "Date",
    "trackerEntryDeleted": "Entry deleted",
    "trackerEntryEditTitle": "Edit entry",
    "trackerEntryNoteLabel": "Note",
    "trackerEntryOptions": "Entry options",
    "trackerEntryTimeLabel": "Time",
    "trackerHistoryEmptyMessage": "Log the first one with the button below.",
    "trackerHistoryEmptyTitle": "Nothing logged yet",
    "trackerHistoryErrorTitle": "Could not load the history",
    "trackerHoursLabel": "Hours",
    "trackerMinutesLabel": "Minutes",
    "trackerNotFoundMessage": "It may have been removed.",
    "trackerNotFoundTitle": "This tracker is gone",
    "trackerOptions": "Tracker options"
  },
  "fa": {
    "trackerAddDuration": "افزودن زمان",
    "trackerDayAlreadyDone": "آن روز از قبل انجام\u200cشده است",
    "trackerDone": "انجام شد",
    "trackerDurationInvalid": "دست\u200cکم یک دقیقه وارد کنید",
    "trackerEntryDateLabel": "تاریخ",
    "trackerEntryDeleted": "مورد حذف شد",
    "trackerEntryEditTitle": "ویرایش مورد",
    "trackerEntryNoteLabel": "یادداشت",
    "trackerEntryOptions": "گزینه\u200cهای مورد",
    "trackerEntryTimeLabel": "ساعت",
    "trackerHistoryEmptyMessage": "اولین مورد را با دکمه پایین ثبت کنید.",
    "trackerHistoryEmptyTitle": "هنوز چیزی ثبت نشده",
    "trackerHistoryErrorTitle": "تاریخچه بارگیری نشد",
    "trackerHoursLabel": "ساعت",
    "trackerMinutesLabel": "دقیقه",
    "trackerNotFoundMessage": "شاید حذف شده باشد.",
    "trackerNotFoundTitle": "این عادت دیگر نیست",
    "trackerOptions": "گزینه\u200cهای عادت"
  }
}
```

Run the helper, check `numstat` (0 deletions), and run `flutter gen-l10n`.

- [ ] **Step 5: Provider, history controller, logger**

Append to `tracker_providers.dart`:

```dart
/// One live tracker, archived or not, or null once it no longer exists: the
/// detail screen.
final trackerByIdProvider = StreamProvider.autoDispose.family<Tracker?, String>(
    (ref, id) => ref.watch(trackerRepositoryProvider).watchTracker(id));
```

`app/lib/features/trackers/application/tracker_history_controller.dart`:

```dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../data/tracker_entry_page.dart';
import 'tracker_providers.dart';

final class TrackerHistoryState {
  const TrackerHistoryState({
    required this.entries,
    required this.cursor,
    this.isLoadingMore = false,
  });

  final List<TrackerEntry> entries;
  final TrackerEntryCursor? cursor;
  final bool isLoadingMore;

  bool get hasMore => cursor != null;
}

/// One tracker's history, a page at a time, newest first.
class TrackerHistoryController extends AsyncNotifier<TrackerHistoryState> {
  TrackerHistoryController(this.trackerId);

  final String trackerId;

  static const pageSize = 40;

  @override
  Future<TrackerHistoryState> build() async {
    final repository = ref.watch(trackerRepositoryProvider);
    // Any entry write reloads what is shown. An edit, a delete, an undo or a
    // quick log then appears at once, without each caller having to remember
    // to refresh.
    final changes =
        repository.entryChanges().listen((_) => unawaited(_reload()));
    ref.onDispose(changes.cancel);
    final page = await repository.entriesPage(trackerId, limit: pageSize);
    return TrackerHistoryState(entries: page.items, cursor: page.cursor);
  }

  /// Appends the next page.
  ///
  /// Guarded by [TrackerHistoryState.isLoadingMore]: a fling fires scroll
  /// notifications far faster than a page resolves.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;
    final loading = TrackerHistoryState(
        entries: current.entries, cursor: current.cursor, isLoadingMore: true);
    state = AsyncData(loading);

    final TrackerEntryPage page;
    try {
      page = await ref
          .read(trackerRepositoryProvider)
          .entriesPage(trackerId, after: current.cursor, limit: pageSize);
    } on Object {
      // Not stuck "loading" forever: the next scroll may try again.
      if (ref.mounted && identical(state.value, loading)) {
        state = AsyncData(current);
      }
      rethrow;
    }
    // If a reload replaced the list while this page was on its way, its cursor
    // belongs to a list no longer shown, so the page is dropped.
    if (!ref.mounted || !identical(state.value, loading)) return;
    state = AsyncData(TrackerHistoryState(
      entries: [...current.entries, ...page.items],
      cursor: page.cursor,
    ));
  }

  /// Reloads from the top, as deep as the user has scrolled, so a write does
  /// not snap the list back to its first page.
  Future<void> _reload() async {
    final depth = math.max(pageSize, state.value?.entries.length ?? 0);
    final next = await AsyncValue.guard(() async {
      final page = await ref
          .read(trackerRepositoryProvider)
          .entriesPage(trackerId, limit: depth);
      return TrackerHistoryState(entries: page.items, cursor: page.cursor);
    });
    if (ref.mounted) state = next;
  }
}

final trackerHistoryProvider = AsyncNotifierProvider.autoDispose
    .family<TrackerHistoryController, TrackerHistoryState, String>(
        TrackerHistoryController.new);
```

Add to `TrackerLogger`:

```dart
  /// Logs a session the user forgot to time, ending now, with an undo.
  Future<void> addDuration(Duration duration) async {
    final result =
        await _write(() => repository.addDuration(tracker.id, duration));
    if (result case EntryLogged(:final entry)) {
      _showUndo(l10n.trackerTimerLogged(tracker.name, format.duration(duration)),
          () => repository.deleteEntry(entry.id));
    }
  }

  /// Deletes one entry, with an undo. If the undo would make a second "done"
  /// on that day, because the day was marked done again meanwhile, it says so
  /// instead of failing.
  Future<void> deleteEntry(TrackerEntry entry) async {
    await _write(() => repository.deleteEntry(entry.id));
    _showUndo(l10n.trackerEntryDeleted, () async {
      final restored = await repository.restoreEntries([entry.id]);
      if (restored == DayWrite.dayAlreadyDone) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.trackerDayAlreadyDone)));
      }
    });
  }
```

- [ ] **Step 6: The duration fields and sheet**

`app/lib/features/trackers/presentation/widgets/tracker_duration_fields.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';

/// Hours and minutes, side by side. The add-time sheet and the entry editor
/// both use it.
class TrackerDurationFields extends StatelessWidget {
  const TrackerDurationFields({
    super.key,
    required this.hours,
    required this.minutes,
    required this.keyPrefix,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController hours;
  final TextEditingController minutes;

  /// The fields are keyed `<keyPrefix>-hours` and `<keyPrefix>-minutes`.
  final String keyPrefix;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  /// The duration typed, or null when a field is not a whole number or the
  /// total is under a minute.
  ///
  /// Accepts every digit set, and an empty field reads as zero.
  static Duration? read(
      TextEditingController hours, TextEditingController minutes) {
    int? field(TextEditingController controller) {
      final text = Digits.toLatin(controller.text.trim());
      return text.isEmpty ? 0 : int.tryParse(text);
    }

    final h = field(hours);
    final m = field(minutes);
    if (h == null || m == null || h < 0 || m < 0) return null;
    final duration = Duration(hours: h, minutes: m);
    return duration.inMinutes < 1 ? null : duration;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    InputDecoration decoration(String label, {String? error}) =>
        InputDecoration(
          labelText: label,
          errorText: error,
          border: const OutlineInputBorder(),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: Key('$keyPrefix-hours'),
            controller: hours,
            keyboardType: TextInputType.number,
            decoration: decoration(l10n.trackerHoursLabel, error: errorText),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: NimbusTokens.space4),
        Expanded(
          child: TextField(
            key: Key('$keyPrefix-minutes'),
            controller: minutes,
            keyboardType: TextInputType.number,
            decoration: decoration(l10n.trackerMinutesLabel),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
```

`app/lib/features/trackers/presentation/widgets/tracker_duration_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import 'tracker_duration_fields.dart';

/// Asks how long a session lasted, for one the user forgot to time. Resolves
/// to the duration, or null when dismissed.
Future<Duration?> showAddDurationSheet(BuildContext context) =>
    showModalBottomSheet<Duration>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _AddDurationSheet(),
    );

class _AddDurationSheet extends StatefulWidget {
  const _AddDurationSheet();

  @override
  State<_AddDurationSheet> createState() => _AddDurationSheetState();
}

class _AddDurationSheetState extends State<_AddDurationSheet> {
  final _hours = TextEditingController();
  final _minutes = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _save() {
    final duration = TrackerDurationFields.read(_hours, _minutes);
    if (duration == null) {
      setState(() =>
          _error = AppLocalizations.of(context).trackerDurationInvalid);
      return;
    }
    Navigator.of(context).pop(duration);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: NimbusTokens.space4,
        right: NimbusTokens.space4,
        top: NimbusTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NimbusTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.trackerAddDuration,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: NimbusTokens.space4),
          TrackerDurationFields(
            hours: _hours,
            minutes: _minutes,
            keyPrefix: 'tracker-duration',
            errorText: _error,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: NimbusTokens.space4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: NimbusTokens.space2),
              FilledButton(
                key: const Key('tracker-duration-save'),
                onPressed: _save,
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: The entry sheet**

`app/lib/features/trackers/presentation/widgets/tracker_entry_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../application/tracker_providers.dart';
import 'tracker_duration_fields.dart';
import 'tracker_write.dart';

/// Edits one entry: its time and note always, its amount for a quantity, its
/// length for a timed session. Counter and boolean values are fixed at 1.
Future<void> showTrackerEntrySheet(
  BuildContext context, {
  required Tracker tracker,
  required TrackerEntry entry,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EntrySheet(tracker: tracker, entry: entry),
    );

class _EntrySheet extends ConsumerStatefulWidget {
  const _EntrySheet({required this.tracker, required this.entry});

  final Tracker tracker;
  final TrackerEntry entry;

  @override
  ConsumerState<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends ConsumerState<_EntrySheet> {
  late final TrackerFormat _format = ref.read(trackerFormatProvider);
  late DateTime _wall =
      ref.read(trackerClockProvider).toLocal(widget.entry.occurredAtUtc);

  /// Whether a date or time was picked. Until one is, the stored instant is
  /// passed through untouched, so the entry keeps the day it was logged on.
  /// Rebuilding it from the wall time would drop its seconds and re-derive
  /// the day where the device is now.
  bool _timeChanged = false;

  /// Likewise for the value. A timed session's seconds and an amount's third
  /// decimal survive an edit that never touched them.
  bool _valueEdited = false;

  late final _note = TextEditingController(text: widget.entry.note ?? '');
  late final _amount = TextEditingController(
      text: _isQuantity ? _format.number(widget.entry.value) : '');
  late final Duration _length = TrackerValues.durationOf(widget.entry.value);
  late final _hours =
      TextEditingController(text: _isDuration ? _digits(_length.inHours) : '');
  late final _minutes = TextEditingController(
      text: _isDuration ? _digits(_length.inMinutes % 60) : '');
  String? _valueError;
  String? _dayError;

  bool get _isQuantity => widget.tracker.type == TrackerType.quantity;
  bool get _isDuration => widget.tracker.type == TrackerType.duration;

  String _digits(int value) =>
      _format.persianDigits ? Digits.toPersian('$value') : '$value';

  @override
  void dispose() {
    _note.dispose();
    _amount.dispose();
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _valueChanged(String _) => setState(() {
        _valueEdited = true;
        _valueError = null;
      });

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _wall,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _wall = DateTime(
          picked.year, picked.month, picked.day, _wall.hour, _wall.minute);
      _timeChanged = true;
      _dayError = null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _wall.hour, minute: _wall.minute),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _wall = DateTime(
          _wall.year, _wall.month, _wall.day, picked.hour, picked.minute);
      _timeChanged = true;
      _dayError = null;
    });
  }

  double? _value() {
    if (!_valueEdited) return widget.entry.value;
    if (_isQuantity) return TrackerValues.parseAmount(_amount.text);
    if (_isDuration) {
      final length = TrackerDurationFields.read(_hours, _minutes);
      return length == null ? null : TrackerValues.secondsOf(length);
    }
    return widget.entry.value;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final value = _value();
    if (value == null) {
      setState(() => _valueError = _isDuration
          ? l10n.trackerDurationInvalid
          : l10n.trackerAmountInvalid);
      return;
    }
    final navigator = Navigator.of(context);
    final clock = ref.read(trackerClockProvider);
    final repository = ref.read(trackerRepositoryProvider);
    final entry = widget.entry;

    final result = await reportingTrackerFailure(
      messenger: ScaffoldMessenger.of(context),
      l10n: l10n,
      write: () => repository.updateEntry(TrackerEntry(
        id: entry.id,
        trackerId: entry.trackerId,
        value: value,
        occurredAtUtc:
            _timeChanged ? clock.fromLocal(_wall) : entry.occurredAtUtc,
        // The repository re-derives it when the time changed.
        localDateKey: entry.localDateKey,
        note: _note.text,
      )),
    );
    if (!mounted) return;
    switch (result) {
      case DayWrite.written:
        navigator.pop();
      case DayWrite.dayAlreadyDone:
        setState(() => _dayError = l10n.trackerDayAlreadyDone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final day =
        _timeChanged ? DateKey.fromDateTime(_wall) : widget.entry.localDateKey;

    return Padding(
      padding: EdgeInsets.only(
        left: NimbusTokens.space4,
        right: NimbusTokens.space4,
        top: NimbusTokens.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + NimbusTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.trackerEntryEditTitle, style: theme.textTheme.titleMedium),
            ListTile(
              key: const Key('tracker-entry-date'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.trackerEntryDateLabel),
              trailing: Text(_format.date(day)),
              onTap: _pickDate,
            ),
            ListTile(
              key: const Key('tracker-entry-time'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.trackerEntryTimeLabel),
              trailing: Text(_format.time(_wall)),
              onTap: _pickTime,
            ),
            if (_isQuantity) ...[
              const SizedBox(height: NimbusTokens.space2),
              TextField(
                key: const Key('tracker-entry-amount'),
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l10n.trackerAmountLabel,
                  suffixText: widget.tracker.unit,
                  errorText: _valueError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: _valueChanged,
              ),
            ],
            if (_isDuration) ...[
              const SizedBox(height: NimbusTokens.space2),
              TrackerDurationFields(
                hours: _hours,
                minutes: _minutes,
                keyPrefix: 'tracker-entry',
                errorText: _valueError,
                onChanged: _valueChanged,
              ),
            ],
            const SizedBox(height: NimbusTokens.space4),
            TextField(
              key: const Key('tracker-entry-note'),
              controller: _note,
              decoration: InputDecoration(
                labelText: l10n.trackerEntryNoteLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_dayError != null) ...[
              const SizedBox(height: NimbusTokens.space2),
              Text(
                _dayError!,
                key: const Key('tracker-entry-day-error'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: NimbusTokens.space6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: NimbusTokens.space2),
                FilledButton(
                  key: const Key('tracker-entry-save'),
                  onPressed: _save,
                  child: Text(l10n.commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: The detail screen**

`app/lib/features/trackers/presentation/tracker_detail_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../application/tracker_format.dart';
import '../application/tracker_history_controller.dart';
import '../application/tracker_providers.dart';
import '../routes.dart';
import 'widgets/tracker_action_button.dart';
import 'widgets/tracker_day_rollover.dart';
import 'widgets/tracker_duration_sheet.dart';
import 'widgets/tracker_editor_sheet.dart';
import 'widgets/tracker_entry_sheet.dart';
import 'widgets/tracker_logger.dart';
import 'widgets/tracker_today_text.dart';

/// One tracker: today's total, its history newest first, and the quick log
/// pinned in the bottom third while the history scrolls (screen contract
/// §6.2).
class TrackerDetailScreen extends ConsumerWidget {
  const TrackerDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracker = ref.watch(trackerByIdProvider(id));
    final totals = ref.watch(trackerTotalsProvider);

    if (tracker.hasError || totals.hasError) {
      return Scaffold(
        appBar: AppBar(),
        body: NimbusErrorState(
          title: l10n.trackerErrorTitle,
          retryLabel: l10n.commonRetry,
          detail: (tracker.error ?? totals.error).toString(),
          onRetry: () {
            ref.invalidate(trackerByIdProvider(id));
            ref.invalidate(trackerTotalsProvider);
          },
        ),
      );
    }
    if (!tracker.hasValue || !totals.hasValue) {
      return Scaffold(appBar: AppBar(), body: const NimbusLoadingList(rows: 6));
    }
    final current = tracker.requireValue;
    if (current == null) {
      // A stale link -- Phase 6's widget can hold an old id. Say so, and
      // offer the way back rather than a blank screen.
      return Scaffold(
        appBar: AppBar(),
        body: NimbusEmptyState(
          icon: Icons.search_off,
          title: l10n.trackerNotFoundTitle,
          message: l10n.trackerNotFoundMessage,
          actionLabel: l10n.navTrackers,
          onAction: () => context.go(trackersRoute),
        ),
      );
    }

    final total = totals.requireValue[id] ?? 0;
    return TrackerDayRollover(
      child: Scaffold(
        appBar: AppBar(
          title:
              Text(current.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [_TrackerMenu(tracker: current)],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(tracker: current, total: total),
            const Divider(height: 1),
            Expanded(child: _History(tracker: current)),
          ],
        ),
        // Outside the scrolling body, so it stays put while history scrolls.
        bottomNavigationBar: _QuickLogBar(tracker: current, total: total),
      ),
    );
  }
}

/// What a tap anywhere on this screen writes through. Built before any await,
/// because it holds the context's messenger and the widget may be gone after.
TrackerLogger _loggerFor(BuildContext context, WidgetRef ref, Tracker tracker) =>
    TrackerLogger(
      messenger: ScaffoldMessenger.of(context),
      l10n: AppLocalizations.of(context),
      repository: ref.read(trackerRepositoryProvider),
      format: ref.read(trackerFormatProvider),
      tracker: tracker,
    );

class _Header extends StatelessWidget {
  const _Header({required this.tracker, required this.total});

  final Tracker tracker;
  final double total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(NimbusTokens.space4),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(nimbusIconFor(tracker.iconKey),
                color: Color(tracker.color), size: NimbusTokens.space8 * 1.25),
          ),
          const SizedBox(width: NimbusTokens.space4),
          Expanded(
            child: TrackerTodayText(
              key: const Key('tracker-detail-total'),
              tracker: tracker,
              total: total,
              style: theme.textTheme.headlineSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickLogBar extends ConsumerWidget {
  const _QuickLogBar({required this.tracker, required this.total});

  final Tracker tracker;
  final double total;

  Future<void> _addDuration(BuildContext context, WidgetRef ref) async {
    final logger = _loggerFor(context, ref, tracker);
    final duration = await showAddDurationSheet(context);
    if (duration != null) await logger.addDuration(duration);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(NimbusTokens.space4),
        child: Row(
          key: const Key('tracker-quick-log'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TrackerActionButton(tracker: tracker, total: total),
            if (tracker.type == TrackerType.duration) ...[
              const SizedBox(width: NimbusTokens.space4),
              OutlinedButton.icon(
                key: const Key('tracker-add-duration'),
                onPressed: () => unawaited(_addDuration(context, ref)),
                icon: const Icon(Icons.more_time),
                label: Text(l10n.trackerAddDuration),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.tracker});

  final Tracker tracker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = trackerHistoryProvider(tracker.id);
    final history = ref.watch(provider);

    if (history.hasError) {
      return NimbusErrorState(
        title: l10n.trackerHistoryErrorTitle,
        retryLabel: l10n.commonRetry,
        detail: history.error.toString(),
        onRetry: () => ref.invalidate(provider),
      );
    }
    if (!history.hasValue) return const NimbusLoadingList(rows: 6);
    final entries = history.requireValue.entries;
    if (entries.isEmpty) {
      return NimbusEmptyState(
        icon: Icons.history,
        title: l10n.trackerHistoryEmptyTitle,
        message: l10n.trackerHistoryEmptyMessage,
      );
    }
    return NotificationListener<ScrollNotification>(
      // Near the end, ask for the next page. The controller ignores repeats
      // while one is loading.
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 400) {
          unawaited(ref.read(provider.notifier).loadMore());
        }
        return false;
      },
      child: ListView.builder(
        key: const Key('tracker-history'),
        itemCount: entries.length,
        itemBuilder: (context, index) =>
            _EntryRow(tracker: tracker, entry: entries[index]),
      ),
    );
  }
}

enum _EntryAction { edit, delete }

class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.tracker, required this.entry});

  final Tracker tracker;
  final TrackerEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final format = ref.watch(trackerFormatProvider);
    final clock = ref.watch(trackerClockProvider);
    // The day shown is the stored one, the day the entry belongs to, even if
    // the device has since crossed timezones.
    final when = '${format.date(entry.localDateKey)} · '
        '${format.time(clock.toLocal(entry.occurredAtUtc))}';
    final note = entry.note;

    return ListTile(
      key: Key('tracker-entry-${entry.id}'),
      title: Text(tracker.type == TrackerType.boolean
          ? l10n.trackerDone
          : format.total(tracker, entry.value)),
      subtitle: Text(note == null ? when : '$when\n$note'),
      isThreeLine: note != null,
      onTap: () => showTrackerEntrySheet(context, tracker: tracker, entry: entry),
      trailing: PopupMenuButton<_EntryAction>(
        key: Key('tracker-entry-menu-${entry.id}'),
        tooltip: l10n.trackerEntryOptions,
        onSelected: (action) {
          switch (action) {
            case _EntryAction.edit:
              unawaited(showTrackerEntrySheet(context,
                  tracker: tracker, entry: entry));
            case _EntryAction.delete:
              unawaited(_loggerFor(context, ref, tracker).deleteEntry(entry));
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            key: const Key('tracker-entry-edit'),
            value: _EntryAction.edit,
            child: Text(l10n.trackerEntryEditTitle),
          ),
          PopupMenuItem(
            key: const Key('tracker-entry-delete'),
            value: _EntryAction.delete,
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
  }
}

enum _TrackerAction { edit, archive }

class _TrackerMenu extends ConsumerWidget {
  const _TrackerMenu({required this.tracker});

  final Tracker tracker;

  /// Archives, then goes back to the tab, where the tracker has just left and
  /// the undo is showing.
  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final logger = _loggerFor(context, ref, tracker);
    final router = GoRouter.of(context);
    await logger.archive();
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(trackersRoute);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<_TrackerAction>(
      key: const Key('tracker-menu'),
      tooltip: l10n.trackerOptions,
      onSelected: (action) {
        switch (action) {
          case _TrackerAction.edit:
            unawaited(showTrackerEditorSheet(context,
                repository: ref.read(trackerRepositoryProvider),
                tracker: tracker));
          case _TrackerAction.archive:
            unawaited(_archive(context, ref));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          key: const Key('tracker-menu-edit-tracker'),
          value: _TrackerAction.edit,
          child: Text(l10n.trackerEditTitle),
        ),
        PopupMenuItem(
          key: const Key('tracker-menu-archive-tracker'),
          value: _TrackerAction.archive,
          child: Text(l10n.commonArchive),
        ),
      ],
    );
  }
}
```

- [ ] **Step 9: Routes, and the tile's tap**

In `app/lib/features/trackers/routes.dart`:
1. Add `import 'presentation/tracker_detail_screen.dart';`.
2. Add the constants:

```dart
/// The detail screen's prefix. The `:id` segment is appended where the route
/// is declared.
const trackerDetailRoute = '/tracker';

/// Where a tile opens: [id]'s detail screen.
String trackerLocation(String id) => '$trackerDetailRoute/$id';
```

3. Append to `trackerRoutes`:

```dart
  GoRoute(
    path: '$trackerDetailRoute/:id',
    name: 'tracker',
    builder: (context, state) =>
        TrackerDetailScreen(id: state.pathParameters['id']!),
  ),
```

In `tracker_tile.dart`:
1. Add the imports:
   ```dart
   import 'package:go_router/go_router.dart';
   import '../../routes.dart';
   ```
2. Add to the `ListTile`:

```dart
        onTap: () => context.push(trackerLocation(tracker.id)),
```

- [ ] **Step 10: Run the tests to confirm GREEN**

Run: `cd app && flutter test --no-pub C:/Users/nimae/Desktop/nimbustats/app/test/features/trackers/`
Expected: PASS.

**Mutation checks:**
- Delete the `entryChanges` listener in `TrackerHistoryController.build`. "a note is saved…" and "delete removes the row" must FAIL, because the history no longer follows writes.
- In `_EntrySheetState._save`, always pass `clock.fromLocal(_wall)`. "a note is saved and the instant is left alone" must FAIL: the milliseconds are dropped, and the day re-derives in New York.
- In `_EntrySheetState._value`, drop the `if (!_valueEdited)` guard. "a timed session's seconds survive a note-only edit" must FAIL (27000, not 27015).
- In `TrackerLogger.deleteEntry`'s undo, drop the `dayAlreadyDone` message. "an undo onto a day marked done again says so" must FAIL.

Restore all four.

- [ ] **Step 11: Run the full gate**

Expected: all green.

- [ ] **Step 12: Commit**

```bash
git add app/lib/features/trackers/ app/lib/l10n/ app/test/features/trackers/tracker_detail_screen_test.dart
git commit -m "$(cat <<'EOF'
feat(trackers): tracker detail, history, and entry edit and delete

The detail screen shows today's total and the history newest first.
The history is a keyset page at a time, and reloads as deep as the
user scrolled whenever an entry changes. The quick log is the same
button as on the tab, pinned below the scrolling history so it stays
in the bottom third.

An entry's time and note can always be edited, and its amount or
length for quantities and timed sessions. The sheet passes the stored
instant through untouched unless a date or time was picked, so a
note-only edit after a flight keeps the entry's day and its seconds.

Delete has an undo. An undo that would be a second "done" on a day
marked done again says so instead of failing. Timed trackers can add
a forgotten session. The menu edits or archives the tracker; archive
goes back to the tab, where the undo is.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git switch phase/4-trackers && git merge --ff-only feat/tracker-detail
```

---

### Task 11: The 4a gate — device check on the A53, docs, `phase-4a-complete`

Branch `docs/phase-4a-complete`, slug `phase-4a-complete`. No production code. If the device check finds a bug, stop and report it. Do not fix it inside this task: the fix gets its own TDD commit before the gate resumes.

**Files:**
- Modify: `docs/phases/phase-4-trackers.md` (4a's DoD ticked with evidence; a gate record)
- Modify: `docs/phases/README.md` (status board)
- Modify: `docs/phases/DEFERRED.md` (only if the gate finds something to carry)

- [ ] **Step 1: Run the gate on the phase branch's tip**

From the repo root, on `phase/4-trackers`, run the six commands of the commit routine. Record each suite's count for the gate record.

Then prove the brief's aggregation rule for 4a, that the only aggregate is today's one-day `SUM`:

```bash
grep -rn "\.sum()\|\.count()\|SUM(\|COUNT(\|GROUP BY\|groupBy" packages/nimbus_data/lib/src/trackers/ app/lib/features/trackers/
```

Expected: exactly the `entries.value.sum()` and `..groupBy([entries.trackerId])` lines in `tracker_entries_dao.dart`'s `_dayTotals`, plus the `sortOrder.max()` in `insertAll`, which is not an aggregate over entries. Anything else is a 4a scope breach. Stop and report it.

- [ ] **Step 2: Device check on the Galaxy A53 (operator in the loop)**

The A53 is the operator's daily phone. **Before touching it, ask the operator to confirm it is free and unlocked**, and do not change any of its settings. Follow `docs/DEVELOPMENT.md`'s device steps and the project memory "Driving a device check over adb":
- uiautomator dumps expose Flutter semantics;
- delete the old dump first, because a failed dump leaves a stale file;
- the display runs at 120 Hz.

1. **Copy the phone's database off first**, as in `DEVELOPMENT.md`'s backup step, into `~/nimbustats-backups/`. It holds demo data, but the v21 → v30 migration on the device cannot be undone.
2. Build and install:
   ```bash
   cd app && flutter build apk --profile --no-pub
   adb install -r build/app/outputs/flutter-apk/app-profile.apk
   ```
   Expected: `Success`, and the app opens on Home with the demo data intact. This is the real-device v21 → v30 upgrade.
3. **The tab.** Open Trackers.
   - The four presets are shown.
   - Add all four.
   - Dump the UI and confirm the semantics labels read "Add one to Cigarettes", "Mark Gym done", "Add 0.25 L to Water" and "Start Sleep timer".
4. **The one-tap budget.**
   - Tap Cigarettes' +1 once. Dump: the tile reads "1 today", and the snackbar reads "Cigarettes · 1 today".
   - Ask the operator whether they felt the haptic.
5. **Kill with a timer running.**
   - Tap Sleep's start and note the time.
   - Run `adb shell am force-stop com.nimbustats.app` and wait at least two minutes.
   - Relaunch with `adb shell monkey -p com.nimbustats.app -c android.intent.category.LAUNCHER 1`.
   - Open Trackers and dump: Sleep reads "Running · 0:0M:SS", where M is at least 2.
   - Tap stop. The snackbar reads "Sleep · 0:0M logged", and the detail screen's history shows the entry.
6. **Persian.** If the operator agrees to switch the app's language for the check, look at the tab in Persian: right to left, Persian digits. Switch it back afterwards. If they decline, record that the Persian check was waived, as Phase 3 did; the widget tests stand in for it.
7. Save the dumps to the scratchpad, never the repo. Write down the evidence as observed, including anything that did not match.

- [ ] **Step 3: Operator review of the Persian strings**

Show the operator every Persian value added in Tasks 5–10. List them from `git diff main..phase/4-trackers -- app/lib/l10n/app_fa.arb`. Ask for corrections, and confirm the word chosen for "tracker", `عادت` ("habit").

If corrections come, they are a separate commit, `fix(l10n): …`. Make them with a copy of `arb_add.py` that **updates** existing `fa` keys: replace the `clash` assertion with one that every key already exists. Then run `flutter gen-l10n`, and the gate.

- [ ] **Step 4: Tick the brief's 4a DoD, with evidence**

In `docs/phases/phase-4-trackers.md`, "Definition of done", tick these four items, each with its evidence. Leave the 4b item and `phase-4-complete` unticked.

- **All four tracker types implemented and tested:**
  - `tracker_entry_test.dart` (counter, boolean);
  - `tracker_quantity_test.dart`;
  - `tracker_timer_test.dart`;
  - `tracker_repository_test.dart`;
  - `tracker_entries_dao_test.dart`.
- **Timer state survives a killed process:**
  - `timer_persistence_test.dart` (close and reopen the file);
  - "a timer started before the app was killed is still running" (widget);
  - the A53 check of Step 2.5, dated.
- **Partial unique index proven by a test that logs twice:**
  - `migration_test.dart`, "an upgraded v21 database enforces one live done per day";
  - `tracker_entries_dao_test.dart`, "a second done on the same day is refused…" and "a fast double-tap logs exactly one".
- **One-tap budget:**
  - the widget tests' single `tap` per entry;
  - the A53 check of Step 2.4.

Under the list, add a **4a gate record**, in the shape of Phase 3's, against CONVENTIONS §5:
- **Gate run:** the date, the tip SHA, the analyzer result and the five suites' counts.
- **Strings:** in both ARBs, enforced by `localization_test.dart`; the Persian strings reviewed by the operator (Step 3).
- **RTL and LTR, Persian and Latin digits:**
  - `trackers_screen_test.dart`'s Persian test;
  - `tracker_quantity_test.dart`'s Persian test;
  - `tracker_detail_screen_test.dart`'s Persian test;
  - `tracker_format_test.dart`.
- **The four states:** tested on the tab, the manager and the detail screen, including history and not-found.
- **Accessibility:**
  - semantics labels tested (`containsSemantics`) and read on the A53;
  - dynamic type: the populated tab and the Persian empty state at twice the
    font size (`trackers_screen_test.dart`, "dynamic type");
  - tap targets at least 48;
  - contrast from `nimbus_design` tokens, with no contrast tool run (as in Phases 1 and 3).
- **Schema registry:** v30.
- **Aggregation:** only today's one-day `SUM` (Step 1's grep, quoted).

- [ ] **Step 5: The status board**

In `docs/phases/README.md`, replace the Phase 4 row's status cell with:

```markdown
**4a complete** (<date>) — trackers CRUD and entry, all four types, the timer verified across a killed process on the Galaxy A53. 4b ready: history charts, streaks and patterns on Phase 3's engine
```

Keep the gate-tag cell as `phase-4-complete`, since that tag waits for 4b.

Phase 5's row says "Blocked on 4 (needs 4b's tracker metrics)" and stays as it is. Phase 6's row says "Blocked on 4, 5" and stays as well: the widget needs 4a, but the alerts need 5.

- [ ] **Step 6: Commit, tag, and land**

```bash
git switch phase/4-trackers && git switch -c docs/phase-4a-complete
# edit the docs per Steps 4-5 with the Edit tool or a Python script, never a heredoc
git add docs/phases/phase-4-trackers.md docs/phases/README.md docs/phases/DEFERRED.md
git commit -m "$(cat <<'EOF'
docs: Phase 4a is complete

Ticks 4a's definition of done with its evidence:
- the four types' tests;
- the timer surviving a killed process, in tests and on the A53;
- the once-per-day index proven by logging twice, on fresh and
  upgraded databases;
- the one-tap budget, checked on the device.

The gate record follows CONVENTIONS §5, and the grep shows today's
one-day SUM is the only aggregate in 4a.

4b, on Phase 3's engine, is next. phase-4-complete waits for it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git switch phase/4-trackers && git merge --ff-only docs/phase-4a-complete
git switch main && git merge --ff-only phase/4-trackers
git tag phase-4a-complete
```

`phase-4a-complete` is lightweight, like the other phase tags (CONVENTIONS §4). Then **ask the operator** before pushing:

```bash
git push origin main phase-4a-complete
```

The `pre-*` rollback tags stay local.
