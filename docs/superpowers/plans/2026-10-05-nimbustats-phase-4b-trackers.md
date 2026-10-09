# Phase 4b — Trackers: analytics on Phase 3's engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every tracker a history chart, a streak and time-of-day and day-of-week patterns, all answered by Phase 3's `AnalyticsEngine`, so that no aggregation SQL is left outside it.

**Architecture:**
- **Schema v31** adds `tracker_entries.tz_offset_minutes` and a `(tracker_id, local_date_key)` index. **v32** drops 4a's day index once its only reader is gone.
- **Domain types** in `nimbus_domain/lib/src/trackers/`: a serializable `TrackerQuerySpec` with a sealed `TrackerGroupBy`, a `double`-valued `TrackerResult`, the `TrackerQueries` builders, and a pure `TrackerStreaks`.
- **The engine:** `AnalyticsEngine` compiles a tracker spec against `tracker_entries`. It reuses Phase 3's hour, weekday and period SQL through `GroupExpressions`, which gains alias-taking helpers.
- **The app:**
  - Today's totals, the snackbar's total and the detail header come from the engine through `trackerResultProvider`. 4a's DAO `SUM` is deleted.
  - The detail screen gains streak lines and a `History | Insights` tab bar. Insights holds a range control, a history chart and the two patterns.

**Tech Stack:** Flutter 3.47.1 / Dart 3.13.1, Riverpod 3.4.2, drift 2.34.3 (+ drift_dev 2.34.5), sqlite3 3.5.2, fl_chart (as locked), intl 0.20.3.

**Spec:** `docs/superpowers/specs/2026-10-05-trackers-4b-design.md`. Read it first; this plan argues from it. The brief is `docs/phases/phase-4-trackers.md` (4b: tasks 10–13), and the conventions are in `docs/phases/CONVENTIONS.md`.

## Global Constraints

**Toolchain and scope**
- Flutter 3.47.1 / Dart 3.13.1, with `pubspec.lock` committed. No SDK or dependency changes.
- **Schema.** Phase 4 owns v30–v39. 4a took v30; this plan takes **v31** (Task 1) and **v32** (Task 7), each landing alone on `main` (CONVENTIONS §2).
- **Owns:**
  - `packages/nimbus_domain/lib/src/trackers/**`
  - `packages/nimbus_data/lib/src/tables/{trackers,tracker_entries}_table.dart`
  - `packages/nimbus_data/lib/src/trackers/**`
  - `app/lib/features/trackers/**`
- **Must not touch** `app/lib/features/analytics/**` (Phase 3's screens). Importing `weekdaysFrom` from it, read-only, is allowed.
- **Touches to other owners' files.** Each task names them, and its commit message says so (CONVENTIONS §3):
  - Phase 3's `nimbus_domain/lib/src/analytics/analytics_result.dart` (Task 3);
  - Phase 3's `nimbus_data/lib/src/analytics/group_expressions.dart` (Task 4);
  - Phase 3's `nimbus_data/lib/src/analytics/analytics_engine.dart` (Task 5);
  - Phase 0's `app_database.dart` and `database_test.dart` (Tasks 1, 7);
  - Phase 0's `test/architecture_test.dart` (Task 6);
  - the shared ARBs and barrels;
  - `CONVENTIONS.md`, the main spec and the brief.

**Data rules**
- **Money is never `double`.** Tracker values are the one deliberate `REAL`. `TrackerBucket.value` is `double` because tracker values are, and `Bucket.money` stays `Money`.
- Every query filters `deleted_at IS NULL`, through `AnalyticsPredicates.notDeleted`.
- **Calendar math stays out of SQL.**
  - Period boundaries come from `PeriodBoundaries`.
  - `day` grouping reads `local_date_key` itself.
  - `strftime('%w')` stays where Phase 3 allowed it: the seven-day cycle, which both calendars share.
- **Offsets at write time.** `local_date_key` and `tz_offset_minutes` are stamped when an entry is written and never recomputed on read.

**Strings**
- Every user-facing string goes in **both** `app/lib/l10n/app_en.arb` and `app_fa.arb`.
  - Keys are prefixed `tracker`, as 4a's are.
  - The Persian value never equals the English one (`test/localization_test.dart`).
  - Regenerate with `cd app && flutter gen-l10n`; the generated files are committed.
- ARB files are **CRLF** on disk, sorted case-insensitively, with literal (unescaped) characters. Add keys only through `arb_add.py` (Task 8, Step 1), never by hand.
- **No displayed `int` placeholders.** Every number reaches a string already formatted by `TrackerFormat`, as a `String`.
  - A plural takes an extra `int count`, which only selects the branch and is never printed.
  - **Why:** gen_l10n would format a printed int in the strings' locale, while digits follow the settings locale (`localeProvider`, default `fa`).

**UI rules**
- **No confirmation dialogs** (`app/test/ux_rules_test.dart`). No spinner on any save.
- **Package boundaries.** Presentation code never touches a DAO, and `app` never imports `drift` or `sqlite3`.
- **Colours.** No raw `Color(0x…)` in `app/lib`. `Color(tracker.color)` is fine.
- **Lints:**
  - `unawaited_futures` is an **error**;
  - `dart analyze --fatal-infos` must be clean;
  - `fl_chart` types follow Phase 3's usage (e.g. `FlGridData(show: false)` without `const`).
- **Digits follow settings.** The default settings locale is `fa`, so numbers render in **Persian digits even when a widget test pumps `locale: Locale('en')`**. A test asserting Latin digits calls `useEnglishDigits(db)` first.
- **Accessibility.**
  - Tap targets are at least `NimbusTokens.minTapTarget` (48).
  - Every chart has a spoken summary.
  - Dynamic type is tested at `textScaleFactorTestValue = 2.0`.

**File editing**
- Edit files with the Write/Edit tools, or with Python scripts written to the scratchpad.
- **Never** use Bash heredocs or `printf` for content containing backslashes. Git Bash collapses `\\`, and that once turned a regex `\b` into a backspace and made a test assertion dead. Several tests in this plan contain `\b` and `\s`.

### Commit routine (every task)

1. **Branch.**
   - Tasks 1 and 7 (schema): from `main`, as each task says.
   - Every other task: `git switch phase/4-trackers && git switch -c <branch named in the task>`.
2. **Write the task's tests and run them.** Confirm they fail **for the stated reason**. A compile error counts only when it names the missing symbol.
3. **Tag the parent:** `git tag pre-<slug>`, while nothing of the task is committed. These tags stay local and are never pushed.
4. **Implement.** Run the task's tests until they are green.
5. **Run the full gate from the repo root, all green.**
   - Baseline before this plan (the 4a gate record): architecture 4, `nimbus_domain` 296, `nimbus_data` 209, `nimbus_design` 36, `app` 453. Each task's expected new counts are given in its last step.
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
   - Tasks 1 and 7: as each task says.
   - Every other task: `git switch phase/4-trackers && git merge --ff-only <branch>`.
   - Nothing is pushed until the operator asks.

## Review Focus

These are the input classes the spec implies but none of its tests exercise, most likely first. Each has a pinning test in the task named.

1. **The app killed in the middle of the v31 upgrade.** The next start must upgrade cleanly, not crash on a column that is already there. drift runs `onUpgrade` with no transaction (verified in drift 2.34.3's `engines.dart`) and writes the new version only afterwards. Pinned in Task 1 by a backfill that throws part-way.
2. **An entry logged at an instant that is not on a whole second.** `offsetMinutesOf` must answer 210, not 209, or every such entry lands an hour early in the time-of-day chart. Pinned in Task 2.
3. **The detail screen of an archived tracker.** Its header must still show today's total, although the tab's totals only cover unarchived trackers. Pinned in Task 6.
4. **A detail screen left open across midnight.** "Last entry: today" must become "yesterday", and the streak must hold. Pinned in Task 8.
5. **The calendar switched in Settings while Insights is open.** The range must re-anchor to the new calendar's month, not keep a Jalali range under a Gregorian label. Pinned in Task 9.

## Decisions taken in this plan (beyond the design)

Each is a small, reasoned change to the spec, named here so a reviewer can reject it explicitly.

1. **The day index is dropped in v32, not v31.** This was the operator's choice on 2026-10-05.
   - **Why:** 4a's DAO `SUM` reads `idx_tracker_entries_day`, and without it SQLite falls back to `SCAN … USING INDEX idx_tracker_entries_tracker_day` (measured).
   - v31 adds the new index. v32 drops the old one in its own commit, after Task 6 deletes the `SUM`. Task 1 records this in the spec.
2. **The v31 step runs in a transaction that also writes `PRAGMA user_version = 31`.** drift runs `onUpgrade` outside any transaction and sets the version only after it returns. The transaction makes the backfill all-or-nothing, and writing the version inside it closes the gap between its commit and drift's own write.
3. **`TrackerClock.offsetMinutesOf` is read off `toLocal`,** not injected separately, so it can never disagree with `localDateOf`. `FakeClock` needs no change.
4. **The DAO's `updateEntry` takes `required int? tzOffsetMinutes`,** where null leaves the stored offset alone. This mirrors `TransactionsDao.updateTransaction`. `TrackerEntry` does not gain the field: no screen reads it.
5. **Task order differs from the spec's §6:** the domain types (Task 3) come before the shared fragments (Task 4), because `GroupExpressions.forTrackerDimension` switches over `TrackerGroupBy`.
6. **`TrackerQueries`, the spec builders, live in `nimbus_domain`,** so the repository (data layer) and the providers (application layer) use the same ones. The repository must not import from `application/`.
7. **The detail header reads `trackerDayTotalProvider(id)`, not the tab's map,** because an archived tracker is not on the tab and so not in the map.
   - The derived providers (`trackerTotalsProvider`, `trackerDayTotalProvider`, `trackerStreaksProvider`) are synchronous `Provider<AsyncValue<…>>` views over `trackerResultProvider`, not futures that await one another.
   - **Why:** no `ref` is used after an `await`, which Riverpod 3 can reject once a provider has rebuilt. A write's refresh keeps the previous value, so the tab does not flicker. **That does not hold for a reload (a dependency change) or a new question (a new family member), and it shipped corrected:**
     - the derived providers use a value-keeping derivation (`deriveKeepingValue`);
     - the tab's totals are a non-disposing Notifier that keeps its last map while a new question loads;
     - the detail screen keeps its last day total (fb0410f, 2ae8ee1).
   - Consumers keep using `hasError`/`hasValue`/`requireValue` unchanged.
   - A retry invalidates `trackerResultProvider` as a whole family, so whichever question failed is asked again.
8. **The definition-of-done grep becomes a test** in `test/architecture_test.dart`, so it cannot be forgotten at a later gate.
   - It skips comments.
   - It matches uppercase SQL (`SUM(`, `COUNT(`, `AVG(`, `MIN(`, `MAX(`, `GROUP BY`), drift's empty-paren aggregates (`.sum()` … `.max()`) and `.groupBy(`.
   - It allows exactly one line: `final highest = _db.trackers.sortOrder.max();`.
9. **Period labels are numeric** (`1405/07`, `1405`) in the range bar and the spoken summaries, as Phase 3's `periodLabel` writes them. The spec's "Mehr" was an illustration.
10. **Charts are not mirrored in RTL, following Phase 3's charts.** The range arrows mirror, as Phase 3's `MonthBar` does. This keeps the app's charts consistent; mirroring every chart would be a separate change. **It departs from the spec's "axes run RTL in fa".**
11. **Chart touch tooltips are off.** fl_chart's default tooltip prints the raw `double`, e.g. `3600.0` for an hour. The caption and the spoken summary carry the numbers instead.
12. **A boolean tracker's history caption reads "Done on 9 of 13 days"** instead of a per-day average, which would print a fraction of a "done".
13. **The Insights tab keeps itself alive** (`AutomaticKeepAliveClientMixin`), so its range survives a trip to the History tab and back.
14. **No query timing for tracker queries.** Phase 3's `queryTimingProvider` takes a `QuerySpec`, and nothing measures tracker queries yet.
15. **v32 lands on `main` after `main` fast-forwards to the phase branch.** The lock protocol puts every migration on `main`. Tasks 1–6 are each complete and green, so `main` stays usable with them on it.
16. **ARB keys use the `tracker` prefix**, matching 4a's 65 keys. The spec said `trackers…`.

## File map

**nimbus_domain** (`packages/nimbus_domain/`)

| File | Contents | Task |
|---|---|---|
| `lib/src/trackers/tracker_group_by.dart` | `TrackerGroupBy` and its six cases | 3 |
| `lib/src/trackers/tracker_query_spec.dart` | `TrackerQuerySpec` | 3 |
| `lib/src/trackers/tracker_result.dart` | `TrackerBucket`, `TrackerResult` | 3 |
| `lib/src/analytics/analytics_result.dart` (Phase 3) | gains `TrackerKey` | 3 |
| `lib/src/trackers/tracker_queries.dart` | `TrackerQueries` | 6, extended in 8, 9, 10 |
| `lib/src/trackers/tracker_streaks.dart` | `TrackerStreaks` | 8 |
| `lib/nimbus_domain.dart` | barrel, five export lines | 3, 6, 8 |

**nimbus_data** (`packages/nimbus_data/`)

| File | Contents | Task |
|---|---|---|
| `lib/src/tables/tracker_entries_table.dart` | `tzOffsetMinutes`; the tracker-day index; the day index removed | 1, 7 |
| `lib/src/database/app_database.dart` | the v31 and v32 steps; `trackerOffsetAt` | 1, 7 |
| `lib/src/trackers/tracker_entries_dao.dart` | the offset written; the day totals deleted | 2, 6 |
| `lib/src/analytics/group_expressions.dart` (Phase 3) | alias helpers, `forTrackerDimension` | 4 |
| `lib/src/analytics/analytics_engine.dart` (Phase 3) | `compileTracker`, `runTracker`, `trackerChanges` | 5 |
| `drift_schemas/drift_schema_v31.json`, `drift_schema_v32.json`, `test/generated/*` | generated | 1, 7 |

**app** (`app/lib/features/trackers/`)

| Path | Files | Task |
|---|---|---|
| `data/` | `tracker_clock.dart`, `tracker_repository.dart` | 2, 6 |
| `application/` | `tracker_providers.dart` | 6, extended in 8 |
| `application/` | `tracker_format.dart` | 8, 9 |
| `application/` | `tracker_insights_controller.dart`, `tracker_insights_data.dart` | 9, extended in 10 |
| `presentation/` | `tracker_detail_screen.dart` | 6, 8, 9 |
| `presentation/widgets/` | `tracker_streak_lines.dart` | 8 |
| `presentation/widgets/` | `tracker_bar_chart.dart`, `tracker_range_bar.dart`, `tracker_chart_section.dart`, `tracker_insights.dart` | 9, extended in 10 |

**Tests**

| Path | Files | Task |
|---|---|---|
| `packages/nimbus_data/test/` | `migration_test.dart`, `database_test.dart` | 1, 7 |
| `packages/nimbus_data/test/trackers/` | `support/tracker_rows.dart`, `tracker_entries_dao_test.dart` | 2, 6 |
| `packages/nimbus_data/test/analytics/` | `group_expressions_test.dart` | 4 |
| `packages/nimbus_data/test/analytics/` | `tracker_engine_test.dart`, `tracker_query_plan_test.dart` | 5 |
| `packages/nimbus_domain/test/trackers/` | `tracker_query_spec_test.dart`, `tracker_result_test.dart` | 3 |
| `packages/nimbus_domain/test/trackers/` | `tracker_queries_test.dart` | 6, extended in 8, 9, 10 |
| `packages/nimbus_domain/test/trackers/` | `tracker_streaks_test.dart` | 8 |
| `test/` (root) | `architecture_test.dart` | 6 |
| `app/test/features/trackers/` | `support/tracker_fixture.dart` | 6 |
| `app/test/features/trackers/` | `tracker_repository_test.dart` | 2 |
| `app/test/features/trackers/` | `tracker_detail_screen_test.dart` | 6 |
| `app/test/features/trackers/` | `tracker_streak_lines_test.dart` | 8 |
| `app/test/features/trackers/` | `tracker_format_test.dart` | 8, 9 |
| `app/test/features/trackers/` | `tracker_insights_data_test.dart`, `tracker_insights_test.dart` | 9, extended in 10 |

---

### Task 1: Schema v31 — entries carry their timezone offset (the schema lock)

Branch `feat/schema-v31`, slug `schema-v31`. This task lands on **`main`** alone (CONVENTIONS §2), and then `phase/4-trackers` fast-forwards to it.

**Files:**
- Modify: `packages/nimbus_data/lib/src/tables/tracker_entries_table.dart`
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` (Phase 0)
- Generate: `packages/nimbus_data/drift_schemas/drift_schema_v31.json`, `packages/nimbus_data/test/generated/schema_v31.dart`, `packages/nimbus_data/test/generated/schema.dart`, `packages/nimbus_data/lib/src/database/app_database.g.dart`
- Test: `packages/nimbus_data/test/migration_test.dart`, `packages/nimbus_data/test/database_test.dart` (Phase 0)
- Docs: `docs/phases/CONVENTIONS.md`, `docs/phases/phase-4-trackers.md`, `docs/superpowers/specs/2026-08-20-nimbustats-design.md`, `docs/superpowers/specs/2026-10-05-trackers-4b-design.md`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - Column `tracker_entries.tz_offset_minutes INTEGER NOT NULL DEFAULT 0`. Its drift getter is `trackerEntries.tzOffsetMinutes`, and the companion field is `TrackerEntriesCompanion.tzOffsetMinutes`.
  - Index `idx_tracker_entries_tracker_day ON tracker_entries (tracker_id, local_date_key)`, with generated getter `idxTrackerEntriesTrackerDay`.
  - `AppDatabase(QueryExecutor e, {int Function(DateTime utc)? trackerOffsetAt})`. The factories `openAtPath` and `openInMemory` are unchanged.

- [ ] **Step 1: Branch**

```bash
git switch main
git switch -c feat/schema-v31
```

- [ ] **Step 2: Write the failing tests**

In `packages/nimbus_data/test/database_test.dart`, replace the version test with:

```dart
  test('opens at schema version 31', () async {
    // Phase 3 took v20 and v21, Phase 4 v30 and v31. Ranges are reserved per
    // phase, so this number jumps rather than increments; see the registry in
    // CONVENTIONS.md.
    expect(db.schemaVersion, 31);
    await db.customSelect('SELECT 1').get();
  });

  test('a fresh install has the tracker-day index', () async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_tracker_entries_tracker_day'")
        .get();
    expect(rows, hasLength(1));
  });
```

Replace `packages/nimbus_data/test/migration_test.dart` with:

```dart
import 'package:drift_dev/api/migrations_native.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:sqlite3/common.dart' show CommonDatabase, SqliteException;
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
  for (final from in [1, 20, 21, 30]) {
    test('a v$from database upgrades to v31 and matches a fresh install',
        () async {
      final db = AppDatabase(await verifier.startAt(from));
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, 31);
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

    await verifier.migrateAndValidate(db, 31);

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
    await verifier.migrateAndValidate(db, 31);

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
      await verifier.migrateAndValidate(db, 31);
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

  group('v30 -> v31: each entry learns the offset it was logged at', () {
    // One instant in each half of the year, so a zone with daylight saving can
    // tell them apart.
    final winter = DateTime.utc(2026, 1, 15, 5).millisecondsSinceEpoch;
    final summer = DateTime.utc(2026, 7, 15, 5).millisecondsSinceEpoch;

    /// Two entries as an installed v30 app left them, in raw SQL.
    void seedV30(CommonDatabase raw) {
      raw
        ..execute(
          'INSERT INTO trackers (id, name, icon_key, color, type, created_at, '
          "updated_at) VALUES ('cig', 'Cigarettes', 'smoking_rooms', 0, "
          "'counter', 0, 0)",
        )
        ..execute(
          'INSERT INTO tracker_entries (id, tracker_id, value, '
          'occurred_at_utc, local_date_key, once_per_day, created_at, '
          "updated_at) VALUES ('winter', 'cig', 1.0, ?, 20260115, 0, 0, 0)",
          [winter],
        )
        ..execute(
          'INSERT INTO tracker_entries (id, tracker_id, value, '
          'occurred_at_utc, local_date_key, once_per_day, created_at, '
          "updated_at) VALUES ('summer', 'cig', 1.0, ?, 20260715, 0, 0, 0)",
          [summer],
        );
    }

    /// A zone with daylight saving: +3:30 in winter, +4:30 in summer.
    int seasonal(DateTime utc) => utc.month >= 4 && utc.month <= 9 ? 270 : 210;

    Future<Map<String, int>> offsets(AppDatabase db) async => {
          for (final row in await db
              .customSelect('SELECT id, tz_offset_minutes FROM tracker_entries')
              .get())
            row.read<String>('id'): row.read<int>('tz_offset_minutes'),
        };

    test("each entry takes the offset its own instant had, not today's",
        () async {
      final schema = await verifier.schemaAt(30);
      seedV30(schema.rawDatabase);
      final db =
          AppDatabase(schema.newConnection(), trackerOffsetAt: seasonal);
      addTearDown(db.close);

      await verifier.migrateAndValidate(db, 31);

      expect(await offsets(db), {'winter': 210, 'summer': 270});
    });

    test('a backfill that fails part-way leaves the database at v30',
        () async {
      // The app killed in the middle of the upgrade. Without a transaction the
      // column would already exist, and every later start would fail adding
      // it again -- a phone on which the app never opens.
      final schema = await verifier.schemaAt(30);
      seedV30(schema.rawDatabase);
      var calls = 0;
      final failing = AppDatabase(schema.newConnection(),
          trackerOffsetAt: (utc) =>
              ++calls == 2 ? throw StateError('killed mid-backfill') : 210);
      // The error's type is drift's business. What matters is that the open
      // fails and leaves nothing half-done behind.
      await expectLater(
          failing.customSelect('SELECT 1').get(), throwsA(anything));
      await failing.close();

      expect(schema.rawDatabase.userVersion, 30);
      expect(
        [
          for (final column in schema.rawDatabase
              .select('PRAGMA table_info(tracker_entries)'))
            column['name'] as String,
        ],
        isNot(contains('tz_offset_minutes')),
      );

      final db =
          AppDatabase(schema.newConnection(), trackerOffsetAt: seasonal);
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 31);
      expect(await offsets(db), {'winter': 210, 'summer': 270});
    });
  });
}
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_data && dart test test/migration_test.dart test/database_test.dart`

Expected: FAIL to compile, with `No named parameter with the name 'trackerOffsetAt'`.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-schema-v31
```

- [ ] **Step 5: Add the column and the index to the table**

In `packages/nimbus_data/lib/src/tables/tracker_entries_table.dart`:

1. Add a fourth annotation after the `idx_tracker_entries_history` one:

```dart
@TableIndex(
    name: 'idx_tracker_entries_tracker_day',
    columns: {#trackerId, #localDateKey})
```

2. In the class doc, replace the line `/// The three indexes:` with `/// The four indexes:`. After the `idx_tracker_entries_once_per_day` bullet, add:

```dart
/// - `idx_tracker_entries_tracker_day` serves every engine query (4b): one
///   tracker, or a short list of them, over a range of days. Tracker first,
///   because every such query names its trackers.
```

3. After the `note` column, add:

```dart
  /// The device's UTC offset when the entry was logged, in minutes: what turns
  /// [occurredAtUtc] back into the local hour the entry happened at.
  ///
  /// Stamped at write time like [localDateKey], and for the same reason: an
  /// entry logged before a flight keeps the hour it was logged at. It mirrors
  /// `transactions.tz_offset_minutes`, and the engine's hour-of-day and
  /// weekday buckets read both the same way.
  IntColumn get tzOffsetMinutes => integer().withDefault(const Constant(0))();
```

- [ ] **Step 6: Add the migration step and the backfill**

In `packages/nimbus_data/lib/src/database/app_database.dart`:

1. Replace `AppDatabase(super.e);` with:

```dart
  AppDatabase(super.e, {int Function(DateTime utc)? trackerOffsetAt})
      : _trackerOffsetAt = trackerOffsetAt ?? _deviceOffsetAt;

  /// The UTC offset, in minutes, that the device's zone had at an instant.
  ///
  /// Read only by the v31 backfill. A parameter so the migration test can pin
  /// it; the default is the device's real zone.
  final int Function(DateTime utc) _trackerOffsetAt;

  static int _deviceOffsetAt(DateTime utc) =>
      utc.toLocal().timeZoneOffset.inMinutes;
```

2. Bump `int get schemaVersion => 30;` to `31`.

3. Replace the whole `if (from < 30) { ... }` block in `onUpgrade`, including its leading comment, with:

```dart
          // v21 -> v30: Phase 4 adds trackers and their entries. New tables
          // only, so every older version takes this same step, after the
          // saved-views chain above. createTable builds the tables as they are
          // declared *now*, so this path already has v31's offset column and
          // index -- and with no entries yet there is nothing to backfill,
          // which is why the v31 step below is an else.
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
            await m.create(idxTrackerEntriesTrackerDay);
          } else if (from < 31) {
            // v30 -> v31: entries learn the UTC offset they were logged at,
            // without which no hour-of-day pattern can be right.
            //
            // In a transaction because drift runs onUpgrade without one and
            // records the new version only after it returns. A process killed
            // half-way through the backfill would otherwise leave a v30
            // database with the column already added, and every later start
            // would fail on addColumn. The version is written inside too, so
            // nothing separates this step's commit from its record.
            await transaction(() async {
              await m.addColumn(
                  trackerEntries, trackerEntries.tzOffsetMinutes);
              await _backfillTrackerOffsets();
              await m.create(idxTrackerEntriesTrackerDay);
              await customStatement('PRAGMA user_version = 31');
            });
          }
```

4. Add this method to `AppDatabase`, after the `migration` getter:

```dart
  /// Gives every existing entry the offset the device's zone had at that
  /// entry's own instant -- not today's, which in a zone with daylight saving
  /// would put a winter entry an hour off. Exact under Iran's fixed +3:30.
  Future<void> _backfillTrackerOffsets() async {
    final rows = await customSelect(
            'SELECT id, occurred_at_utc FROM tracker_entries')
        .get();
    for (final row in rows) {
      final at = DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('occurred_at_utc'),
          isUtc: true);
      await customStatement(
        'UPDATE tracker_entries SET tz_offset_minutes = ? WHERE id = ?',
        [_trackerOffsetAt(at), row.read<String>('id')],
      );
    }
  }
```

- [ ] **Step 7: Generate code, the snapshot and the test schemas**

```bash
cd packages/nimbus_data
dart run build_runner build --delete-conflicting-outputs
grep -n "late final Index idxTracker" lib/src/database/app_database.g.dart
dart run drift_dev schema dump lib/src/database/app_database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated/
```

Expected:
- The `grep` prints five lines, now including `idxTrackerEntriesTrackerDay`. If drift named it differently, use the generated name in Step 6 and record the difference in the commit body.
- `drift_schemas/drift_schema_v31.json` and `test/generated/schema_v31.dart` exist.
- `test/generated/schema.dart` lists `const [1, 20, 21, 30, 31]`.

- [ ] **Step 8: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_data && dart test test/migration_test.dart test/database_test.dart`

Expected: PASS. That is eleven migration tests:
- four upgrade paths;
- the v20 and v1 tests;
- three once-per-day tests;
- two v30 → v31 tests.

Plus three in `database_test.dart` that this task touches (the version test, the index test, and the unchanged rest).

**Mutation check.**
1. In the v31 step, replace `await transaction(() async { ... });` with its four statements run directly, without the `PRAGMA` line.
2. Re-run `migration_test.dart`. Expected: "a backfill that fails part-way leaves the database at v30" FAILS, on the column already being there.
3. Restore the transaction.

- [ ] **Step 9: Update the registry and the docs**

`docs/phases/CONVENTIONS.md`, the registry row:
- old: `| 4 — Trackers | v30–v39 | **v30** | trackers, tracker_entries |`
- new: `| 4 — Trackers | v30–v39 | **v30, v31** | trackers, tracker_entries; v31 adds tracker_entries.tz_offset_minutes |`

`docs/phases/phase-4-trackers.md`:
- Replace `**Schema versions:** v30–v39 reserved. Expect to use **v30**.` with `**Schema versions:** v30–v39 reserved. 4a used **v30**; 4b uses **v31** (entry offsets) and **v32** (drops 4a's day index).`
- After the line ``- `per_tap_value` is what one tap logs on a quantity tracker.``, add:

```markdown

4b adds one column (v31), because no hour-of-day pattern can be right without
it: `tz_offset_minutes`, the device's UTC offset when the entry was logged, as
transactions already store. It also adds the index every engine query uses,
`(tracker_id, local_date_key)`, and v32 drops 4a's `(local_date_key,
tracker_id)` once its only reader, the DAO's day total, is gone.
```

`docs/superpowers/specs/2026-08-20-nimbustats-design.md`: in the line beginning ``**`tracker_entries`** —``, replace `` `local_date_key`, `note?`, `` with `` `local_date_key`, `tz_offset_minutes` (the offset when logged, for the local hour), `note?`, ``.

`docs/superpowers/specs/2026-10-05-trackers-4b-design.md`:
- In the header, replace `**Schema:** v31` with `**Schema:** v31, v32`.
- In §1's index table, replace the `idx_tracker_entries_day` row with:

```markdown
| `idx_tracker_entries_day (local_date_key, tracker_id)` | **dropped in v32** | Its only reader is 4a's DAO `SUM`, which §3 deletes. Dropping it in v31 would make that `SUM` scan an index for five commits (measured: `SCAN … USING INDEX idx_tracker_entries_tracker_day`), so v32 drops it alone, after the `SUM` is gone (operator, 2026-10-05) |
```

- Replace the sentence `The migration creates the new index with \`m.create(...)\` and drops the old one by name.` with `v31 creates the new index with \`m.create(...)\`; v32 drops the old one by name.`

- [ ] **Step 10: Run the full gate**

Run the commands in the commit routine. Expected: all green.
- `nimbus_data` is 209 + 4 = **213**: four tests are new (one database test and three migration tests); the rest are re-pointed.
- The other suites are unchanged.

- [ ] **Step 11: Commit and merge**

```bash
git add packages/nimbus_data docs/phases/CONVENTIONS.md docs/phases/phase-4-trackers.md docs/superpowers/specs/2026-08-20-nimbustats-design.md docs/superpowers/specs/2026-10-05-trackers-4b-design.md
git commit -F - <<'EOF'
feat(schema): v31 -- entries carry their timezone offset

No hour-of-day pattern can be right for a tracker entry that does not
know the offset it was logged at. Transactions have always stored
one, and the engine's hour and weekday buckets read it. Tracker
entries now store it too.

Existing entries are backfilled with the offset the device's zone
had at each entry's own instant, not today's, so in a zone with
daylight saving a winter entry is not put an hour off. drift runs
onUpgrade without a transaction and records the version only
afterwards. The step therefore runs in a transaction that also
writes the version, so an app killed mid-backfill does not leave a
column that every later start fails to add.

Also adds (tracker_id, local_date_key), the index every engine query
on tracker entries will seek. 4a's (local_date_key, tracker_id) stays
until v32, because its one reader -- the DAO's day total -- is not
deleted until Task 6.

Touches Phase 0's app_database.dart and database_test.dart for the
step, and updates the registry, the brief, the main spec and the 4b
design.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch main
git merge --ff-only feat/schema-v31
git switch phase/4-trackers
git merge --ff-only main
```

---

### Task 2: Every entry records the offset it was logged at

Branch `feat/tracker-offset`, slug `tracker-offset`.

**Files:**
- Modify: `app/lib/features/trackers/data/tracker_clock.dart`
- Modify: `app/lib/features/trackers/data/tracker_repository.dart`
- Modify: `packages/nimbus_data/lib/src/trackers/tracker_entries_dao.dart`
- Test: `app/test/features/trackers/tracker_repository_test.dart`, `packages/nimbus_data/test/trackers/tracker_entries_dao_test.dart`, `packages/nimbus_data/test/trackers/support/tracker_rows.dart`

**Interfaces:**
- Consumes: `trackerEntries.tzOffsetMinutes` (Task 1).
- Produces:
  - `int TrackerClock.offsetMinutesOf(DateTime utc)`.
  - `NewTrackerEntry` gains `int tzOffsetMinutes`.
  - `TrackerEntriesDao.updateEntry(..., required int? tzOffsetMinutes)`, where null leaves the stored offset alone.
  - In tests: `newEntry(..., int tzOffsetMinutes = 210)` and `offsetOf(AppDatabase db, String entryId)`.

- [ ] **Step 1: Branch**

```bash
git switch phase/4-trackers
git switch -c feat/tracker-offset
```

- [ ] **Step 2: Write the failing tests**

In `packages/nimbus_data/test/trackers/support/tracker_rows.dart`:
1. Add the parameter `int tzOffsetMinutes = 210,` to `newEntry`, after `bool oncePerDay = false,`.
2. Add `tzOffsetMinutes: tzOffsetMinutes,` to the record it returns.
3. Append:

```dart
/// The offset stored on [entryId], read in SQL: no domain type carries it.
Future<int> offsetOf(AppDatabase db, String entryId) async {
  final row = await db.customSelect(
    'SELECT tz_offset_minutes AS o FROM tracker_entries WHERE id = ?',
    variables: [Variable.withString(entryId)],
  ).getSingle();
  return row.read<int>('o');
}
```

In `packages/nimbus_data/test/trackers/tracker_entries_dao_test.dart`:
1. The three existing `dao.updateEntry(` calls (near lines 86, 110 and 132) each gain the argument `tzOffsetMinutes: null,`.
2. Append inside `main`:

```dart
  group('timezone offset', () {
    test('insertEntry stores the offset it is given', () async {
      await dao.insertEntry(newEntry('ny', 'cig', tzOffsetMinutes: -240));
      expect(await offsetOf(db, 'ny'), -240);
    });

    test('updateEntry leaves the offset alone given null, else rewrites it',
        () async {
      await dao.insertEntry(newEntry('e', 'cig'));

      await dao.updateEntry('e',
          value: 1,
          occurredAtUtc: morning,
          localDateKey: today,
          note: 'kept',
          tzOffsetMinutes: null);
      expect(await offsetOf(db, 'e'), 210);

      await dao.updateEntry('e',
          value: 1,
          occurredAtUtc: morning,
          localDateKey: today,
          note: 'moved',
          tzOffsetMinutes: -240);
      expect(await offsetOf(db, 'e'), -240);
    });
  });
```

In `app/test/features/trackers/tracker_repository_test.dart`:
1. Add the import `import 'package:nimbustats/features/trackers/data/tracker_clock.dart';`.
2. Append inside `main`:

```dart
  group('the offset is taken at write time', () {
    // Read in SQL: no domain type carries the offset, and app tests may not
    // import drift, so the id goes into the statement. Ids are UUIDv7 hex.
    Future<int> offsetOf(String entryId) async => (await db
            .customSelect('SELECT tz_offset_minutes AS o FROM tracker_entries '
                "WHERE id = '$entryId'")
            .getSingle())
        .read<int>('o');

    test('a tap stores the offset of wherever the device is', () async {
      final cig = await repo.create(cigarettes);
      final tehran = (await repo.logEntry(cig.id) as EntryLogged).entry;
      fake.offset = FakeClock.newYork;
      final newYork = (await repo.logEntry(cig.id) as EntryLogged).entry;

      expect(await offsetOf(tehran.id), 210);
      expect(await offsetOf(newYork.id), -240);
    });

    test('a timed session takes the offset at its start', () async {
      final s = await repo.create(sleep);
      await repo.startTimer(s.id);
      fake.advance(const Duration(hours: 1));
      final stopped = await repo.stopTimer(s.id) as TimerStopped;

      expect(await offsetOf(stopped.entry.id), 210);
    });

    test('a session added by hand takes the offset at its start', () async {
      final s = await repo.create(sleep);
      final added = await repo.addDuration(s.id, const Duration(minutes: 30))
          as EntryLogged;

      expect(await offsetOf(added.entry.id), 210);
    });

    test('a note-only edit after a flight keeps the offset; moving the time '
        'takes the new one', () async {
      final cig = await repo.create(cigarettes);
      final e = (await repo.logEntry(cig.id) as EntryLogged).entry;
      fake.offset = FakeClock.newYork;

      await repo.updateEntry(TrackerEntry(
          id: e.id,
          trackerId: e.trackerId,
          value: e.value,
          occurredAtUtc: e.occurredAtUtc,
          localDateKey: e.localDateKey,
          note: 'remembered'));
      expect(await offsetOf(e.id), 210);

      await repo.updateEntry(TrackerEntry(
          id: e.id,
          trackerId: e.trackerId,
          value: e.value,
          occurredAtUtc: e.occurredAtUtc.subtract(const Duration(hours: 1)),
          localDateKey: e.localDateKey,
          note: 'remembered'));
      expect(await offsetOf(e.id), -240);
    });

    test('an instant off the whole second still reads a whole offset', () {
      // 210 minutes, not 209. Dropping the milliseconds would put every such
      // entry an hour early in the time-of-day chart.
      expect(
          fake.clock.offsetMinutesOf(DateTime.utc(2026, 10, 5, 9, 0, 0, 500)),
          210);
      fake.offset = FakeClock.newYork;
      expect(
          fake.clock
              .offsetMinutesOf(DateTime.utc(2026, 10, 5, 9, 0, 0, 999, 999)),
          -240);
    });

    test("the system clock answers the device's own offset", () {
      final now = DateTime.now();
      expect(const TrackerClock().offsetMinutesOf(now.toUtc()),
          now.timeZoneOffset.inMinutes);
    });
  });
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_data && dart test test/trackers/tracker_entries_dao_test.dart`
Expected: FAIL to compile, naming `tzOffsetMinutes` (no such record field / named parameter).

Run: `cd app && flutter test --no-pub <absolute path>/app/test/features/trackers/tracker_repository_test.dart`
Expected: FAIL to compile, naming `offsetMinutesOf`.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-tracker-offset
```

- [ ] **Step 5: Store the offset in the DAO**

In `packages/nimbus_data/lib/src/trackers/tracker_entries_dao.dart`:

1. In the `NewTrackerEntry` typedef, after `bool oncePerDay,`, add:

```dart
  /// The device's UTC offset when the entry was logged, in minutes.
  int tzOffsetMinutes,
```

2. In `insertEntry`'s companion, after `oncePerDay: Value(entry.oncePerDay),`, add `tzOffsetMinutes: Value(entry.tzOffsetMinutes),`.

3. Replace `updateEntry`'s doc and signature with the following; the body is unchanged except for the companion:

```dart
  /// Rewrites an entry's value, time, day and note, and its offset when
  /// [tzOffsetMinutes] is given. Null leaves the stored offset as it is:
  /// editing a note after a flight must not move the entry's hour.
  ///
  /// Returns [DayWrite.dayAlreadyDone], writing nothing, when the edit would
  /// put a second live "done" on one day.
  Future<DayWrite> updateEntry(
    String id, {
    required double value,
    required DateTime occurredAtUtc,
    required DateKey localDateKey,
    required String? note,
    required int? tzOffsetMinutes,
  }) async {
```

4. In its companion, after `note: Value(note),`, add:

```dart
        tzOffsetMinutes: tzOffsetMinutes == null
            ? const Value.absent()
            : Value(tzOffsetMinutes),
```

`TrackersDao.finishTimer` inserts through `insertEntry`, so it needs no change.

- [ ] **Step 6: Read the offset off the clock**

In `app/lib/features/trackers/data/tracker_clock.dart`, after `localDateOf`, add:

```dart
  /// The device's UTC offset at [utc], in whole minutes, as the device's zone
  /// reads it now: what an entry written now is stamped with.
  ///
  /// Read off [toLocal] rather than injected separately, so it can never
  /// disagree with [localDateOf] about where the device is. Every field down
  /// to the microsecond is carried over: dropping the milliseconds would make
  /// an offset of 210 minutes read as 209 for any instant off a whole second.
  int offsetMinutesOf(DateTime utc) {
    final instant = utc.toUtc();
    final wall = toLocal(instant);
    return DateTime.utc(wall.year, wall.month, wall.day, wall.hour,
            wall.minute, wall.second, wall.millisecond, wall.microsecond)
        .difference(instant)
        .inMinutes;
  }
```

- [ ] **Step 7: Stamp it on every write path**

In `app/lib/features/trackers/data/tracker_repository.dart`:

1. Update the class doc's list. Replace `/// - the local date key, computed at write time.` with:

```dart
/// - the local date key and the UTC offset, both taken at write time.
```

2. In `logEntry`'s record, after `localDateKey: _clock.localDateOf(atUtc),`, add `tzOffsetMinutes: _clock.offsetMinutesOf(atUtc),`.
3. In `stopTimer`'s record, after `localDateKey: _clock.localDateOf(timer.startedAtUtc),`, add `tzOffsetMinutes: _clock.offsetMinutesOf(timer.startedAtUtc),`.
4. In `addDuration`'s record, after `localDateKey: _clock.localDateOf(start),`, add `tzOffsetMinutes: _clock.offsetMinutesOf(start),`.
5. In `updateEntry`, replace the doc's first paragraph with:

```dart
  /// The local date and the offset are recomputed only when the time changed.
  /// Editing a note after a flight must not move the entry to another day or
  /// hour, while moving the time is a new write and takes the device's date
  /// and offset now.
```

   and after the `localDateKey:` argument of `_entries.updateEntry`, add:

```dart
      tzOffsetMinutes: atUtc == current.occurredAtUtc
          ? null
          : _clock.offsetMinutesOf(atUtc),
```

- [ ] **Step 8: Run the tests to confirm GREEN**

Run both commands from Step 3. Expected: PASS.

**Mutation check.**
1. In `offsetMinutesOf`, drop `wall.millisecond, wall.microsecond`.
2. Re-run the repository test. Expected: "an instant off the whole second still reads a whole offset" FAILS with 209.
3. Restore them.

- [ ] **Step 9: Run the full gate**

Expected:
- `nimbus_data` is 213 + 2 = **215**;
- `app` is 453 + 6 = **459**;
- the rest are unchanged.

- [ ] **Step 10: Commit and merge**

```bash
git add app/lib/features/trackers/data packages/nimbus_data/lib/src/trackers packages/nimbus_data/test/trackers app/test/features/trackers/tracker_repository_test.dart
git commit -F - <<'EOF'
feat(trackers): entries record the offset they were logged at

v31 gave tracker entries a tz_offset_minutes column. Every write path
now fills it, exactly as it fills local_date_key: a tap, a timer's
stop, a session typed in, and an edit that moves the time. A timed
session takes the offset at its start, where it is stamped.

An edit that keeps the time keeps the offset. Editing a note after a
flight must not move an entry's hour any more than its day. The DAO
takes a nullable offset for that, as TransactionsDao does.

TrackerClock reads the offset off the same toLocal it reads the date
from, so the two can never disagree about where the device is. It
carries the milliseconds over: without them an instant off a whole
second reads 209 minutes for Tehran instead of 210.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/4-trackers
git merge --ff-only feat/tracker-offset
```

---

### Task 3: Domain — `TrackerQuerySpec`, `TrackerGroupBy`, `TrackerResult`

Branch `feat/tracker-query-spec`, slug `tracker-query-spec`.

**Files:**
- Create: `packages/nimbus_domain/lib/src/trackers/tracker_group_by.dart`
- Create: `packages/nimbus_domain/lib/src/trackers/tracker_query_spec.dart`
- Create: `packages/nimbus_domain/lib/src/trackers/tracker_result.dart`
- Modify: `packages/nimbus_domain/lib/src/analytics/analytics_result.dart` (Phase 3: adds `TrackerKey`)
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart`
- Test: `packages/nimbus_domain/test/trackers/tracker_query_spec_test.dart`, `packages/nimbus_domain/test/trackers/tracker_result_test.dart`

**Interfaces:**
- Consumes: `Aggregate`, `BucketKey` and its subclasses, `DateRange`, `DateKey` and `PeriodType` (Phases 0 and 3).
- Produces:
  - `sealed class TrackerGroupBy` with `String get kind`, `Map<String, Object?> toJson()` and `factory TrackerGroupBy.fromJson(Map<String, Object?>)`. Its cases are the `const` `TrackerGroupByNone()`, `TrackerGroupByTracker()`, `TrackerGroupByDay()`, `TrackerGroupByHourOfDay()` and `TrackerGroupByDayOfWeek()`, plus `TrackerGroupByPeriod(PeriodType period)`, which is not const.
  - `TrackerQuerySpec({required List<String> trackerIds, DateRange? dateRange, required TrackerGroupBy groupBy, required Aggregate aggregate})`, with `toJson()`, `fromJson(...)`, `withDateRange(DateRange?)` and value equality.
  - `TrackerKey(String trackerId)`, a `BucketKey`.
  - `TrackerBucket({required BucketKey key, required double value, required int count})`.
  - `TrackerResult({required List<TrackerBucket> buckets, required double sum, required int count})`.

- [ ] **Step 1: Branch**

```bash
git switch phase/4-trackers
git switch -c feat/tracker-query-spec
```

- [ ] **Step 2: Write the failing tests**

Create `packages/nimbus_domain/test/trackers/tracker_query_spec_test.dart`:

```dart
import 'dart:convert';

import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

// Not const: TrackerGroupByPeriod validates its period, so it has a body.
final everyDimension = <TrackerGroupBy>[
  const TrackerGroupByNone(),
  const TrackerGroupByTracker(),
  const TrackerGroupByDay(),
  TrackerGroupByPeriod(PeriodType.month),
  const TrackerGroupByHourOfDay(),
  const TrackerGroupByDayOfWeek(),
];

/// Exhaustive on purpose: a new case makes this a compile error rather than a
/// dimension that is never round-tripped.
String kindOf(TrackerGroupBy dimension) => switch (dimension) {
      TrackerGroupByNone() => 'none',
      TrackerGroupByTracker() => 'tracker',
      TrackerGroupByDay() => 'day',
      TrackerGroupByPeriod() => 'period',
      TrackerGroupByHourOfDay() => 'hourOfDay',
      TrackerGroupByDayOfWeek() => 'dayOfWeek',
    };

void main() {
  const october = DateRange(DateKey(20261001), DateKey(20261031));

  TrackerQuerySpec spec({
    List<String> ids = const ['cig'],
    DateRange? range = october,
    TrackerGroupBy groupBy = const TrackerGroupByDay(),
    Aggregate aggregate = Aggregate.sum,
  }) =>
      TrackerQuerySpec(
          trackerIds: ids,
          dateRange: range,
          groupBy: groupBy,
          aggregate: aggregate);

  group('TrackerGroupBy', () {
    test('every dimension round-trips as its own kind', () {
      for (final dimension in everyDimension) {
        final json = dimension.toJson();
        expect(json['kind'], kindOf(dimension));
        final restored = TrackerGroupBy.fromJson(json);
        expect(restored, dimension, reason: 'round trip changed $dimension');
        expect(restored.runtimeType, dimension.runtimeType);
      }
    });

    test('the period survives the round trip', () {
      final restored = TrackerGroupBy.fromJson(
          TrackerGroupByPeriod(PeriodType.quarter).toJson());
      expect((restored as TrackerGroupByPeriod).period, PeriodType.quarter);
    });

    test('days are asked for one way only', () {
      expect(() => TrackerGroupByPeriod(PeriodType.day), throwsArgumentError);
      expect(
          () => TrackerGroupBy.fromJson({'kind': 'period', 'period': 'day'}),
          throwsFormatException);
    });

    test('an unknown kind or period is refused, not guessed', () {
      expect(() => TrackerGroupBy.fromJson({'kind': 'merchant'}),
          throwsFormatException);
      expect(
          () => TrackerGroupBy.fromJson({'kind': 'period', 'period': 'decade'}),
          throwsFormatException);
    });
  });

  group('TrackerQuerySpec', () {
    test('round-trips every dimension and aggregate, dated or not', () {
      for (final dimension in everyDimension) {
        for (final aggregate in Aggregate.values) {
          for (final range in [october, null]) {
            final original =
                spec(groupBy: dimension, aggregate: aggregate, range: range);
            expect(TrackerQuerySpec.fromJson(original.toJson()), original,
                reason: 'round trip changed $original');
          }
        }
      }
    });

    test('survives being stored as JSON text', () {
      // Phase 5 stores the spec as text; ints must come back as ints.
      final original = spec(ids: ['cig', 'water']);
      final text = jsonEncode(original.toJson());
      expect(
          TrackerQuerySpec.fromJson(jsonDecode(text) as Map<String, Object?>),
          original);
    });

    test('an empty tracker list is refused', () {
      expect(() => spec(ids: const []), throwsArgumentError);
    });

    test('stored tracker ids must be a non-empty list of strings', () {
      final json = spec().toJson();
      for (final bad in [null, <String>[], 'cig', [1]]) {
        expect(
            () => TrackerQuerySpec.fromJson({...json, 'trackerIds': bad}),
            throwsFormatException,
            reason: 'accepted trackerIds "$bad"');
      }
    });

    test('a half-open date range is refused', () {
      final json = spec().toJson();
      expect(
          () => TrackerQuerySpec.fromJson({
                ...json,
                'dateRange': {'start': 20261001},
              }),
          throwsFormatException);
    });

    test('an unknown aggregate is refused', () {
      expect(
          () => TrackerQuerySpec.fromJson(
              {...spec().toJson(), 'aggregate': 'median'}),
          throwsFormatException);
    });

    test('withDateRange replaces only the range', () {
      final original = spec(groupBy: const TrackerGroupByHourOfDay());
      const november = DateRange(DateKey(20261101), DateKey(20261130));
      expect(original.withDateRange(november),
          spec(groupBy: const TrackerGroupByHourOfDay(), range: november));
      expect(original.withDateRange(null).dateRange, isNull);
    });

    test('equal specs are equal and hash alike; ids compare in order', () {
      expect(spec(ids: ['a', 'b']), spec(ids: ['a', 'b']));
      expect(spec(ids: ['a', 'b']).hashCode, spec(ids: ['a', 'b']).hashCode);
      expect(spec(ids: ['a', 'b']), isNot(spec(ids: ['b', 'a'])));
      expect(spec(), isNot(spec(aggregate: Aggregate.count)));
    });

    test('the ids cannot change after construction', () {
      // The spec keys a provider cache; a list mutated after hashing would
      // strand its entry.
      final ids = ['cig'];
      final s = spec(ids: ids);
      ids.add('water');
      expect(s.trackerIds, ['cig']);
      expect(() => s.trackerIds.add('x'), throwsUnsupportedError);
    });
  });
}
```

Create `packages/nimbus_domain/test/trackers/tracker_result_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  test('a tracker key compares by id, and is no other kind of key', () {
    expect(const TrackerKey('cig'), const TrackerKey('cig'));
    expect(const TrackerKey('cig').hashCode, const TrackerKey('cig').hashCode);
    expect(const TrackerKey('cig'), isNot(const TrackerKey('water')));
    expect(const TrackerKey('cig'), isNot(const TagKey('cig', '/cig/')));
  });

  test('buckets compare by key, value and count', () {
    const a = TrackerBucket(key: TrackerKey('cig'), value: 2, count: 2);
    expect(a, const TrackerBucket(key: TrackerKey('cig'), value: 2, count: 2));
    expect(
        a,
        isNot(
            const TrackerBucket(key: TrackerKey('cig'), value: 2, count: 1)));
  });
}
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_domain && dart test test/trackers/tracker_query_spec_test.dart test/trackers/tracker_result_test.dart`
Expected: FAIL to compile, naming `TrackerGroupBy`, `TrackerQuerySpec`, `TrackerKey` and `TrackerBucket`.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-tracker-query-spec
```

- [ ] **Step 5: Write `TrackerGroupBy`**

Create `packages/nimbus_domain/lib/src/trackers/tracker_group_by.dart`:

```dart
import 'package:meta/meta.dart';

import '../calendar/calendar.dart';

/// The dimension a tracker query buckets its entries along.
///
/// Sealed and separate from Phase 3's `GroupBy`, which buckets transactions.
/// A tracker has no category, tag or merchant, and a type that cannot name
/// them cannot be asked for them: only time and the tracker itself are here.
@immutable
sealed class TrackerGroupBy {
  const TrackerGroupBy();

  /// Throws [FormatException] on anything it does not recognise. A stored
  /// spec read back wrong would change what a Phase 5 goal measures.
  factory TrackerGroupBy.fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'none' => const TrackerGroupByNone(),
        'tracker' => const TrackerGroupByTracker(),
        'day' => const TrackerGroupByDay(),
        'period' => TrackerGroupByPeriod(_periodOf(json['period'])),
        'hourOfDay' => const TrackerGroupByHourOfDay(),
        'dayOfWeek' => const TrackerGroupByDayOfWeek(),
        final other =>
          throw FormatException('unknown tracker group-by kind "$other"'),
      };

  /// Stable discriminator, also the JSON tag.
  String get kind;

  Map<String, Object?> toJson() => {'kind': kind};

  static PeriodType _periodOf(Object? raw) {
    for (final period in PeriodType.values) {
      if (period.name != raw) continue;
      if (period == PeriodType.day) {
        throw const FormatException(
            'a tracker groups by day with kind "day", not "period"');
      }
      return period;
    }
    throw FormatException('unknown period type "$raw"');
  }
}

/// One bucket holding everything the query matched.
final class TrackerGroupByNone extends TrackerGroupBy {
  const TrackerGroupByNone();
  @override
  String get kind => 'none';
  @override
  bool operator ==(Object other) => other is TrackerGroupByNone;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'TrackerGroupByNone()';
}

/// One bucket per tracker: the tab's totals.
final class TrackerGroupByTracker extends TrackerGroupBy {
  const TrackerGroupByTracker();
  @override
  String get kind => 'tracker';
  @override
  bool operator ==(Object other) => other is TrackerGroupByTracker;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'TrackerGroupByTracker()';
}

/// The local day an entry was written on, read from `local_date_key` itself.
///
/// Needs no date range and no calendar, because a local day is the same day
/// in Jalali and Gregorian. That is what lets the streaks read a tracker's
/// whole history, where a period ladder would need a bounded range and one
/// CASE arm per day.
final class TrackerGroupByDay extends TrackerGroupBy {
  const TrackerGroupByDay();
  @override
  String get kind => 'day';
  @override
  bool operator ==(Object other) => other is TrackerGroupByDay;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'TrackerGroupByDay()';
}

/// A calendar period -- week, month, quarter or year -- on Phase 3's
/// `PeriodBoundaries` ladder, so a Jalali month is a Jalali month.
///
/// Refuses [PeriodType.day]. [TrackerGroupByDay] answers that, and two ways to
/// ask for days would be two cache keys and two plans for one question.
final class TrackerGroupByPeriod extends TrackerGroupBy {
  TrackerGroupByPeriod(this.period) {
    if (period == PeriodType.day) {
      throw ArgumentError.value(
          period, 'period', 'group by TrackerGroupByDay for days');
    }
  }

  final PeriodType period;

  @override
  String get kind => 'period';
  @override
  Map<String, Object?> toJson() => {'kind': kind, 'period': period.name};
  @override
  bool operator ==(Object other) =>
      other is TrackerGroupByPeriod && other.period == period;
  @override
  int get hashCode => Object.hash(kind, period);
  @override
  String toString() => 'TrackerGroupByPeriod(${period.name})';
}

/// The local hour an entry happened at, from its instant and the offset it
/// was logged with.
final class TrackerGroupByHourOfDay extends TrackerGroupBy {
  const TrackerGroupByHourOfDay();
  @override
  String get kind => 'hourOfDay';
  @override
  bool operator ==(Object other) => other is TrackerGroupByHourOfDay;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'TrackerGroupByHourOfDay()';
}

/// The ISO weekday an entry happened on.
final class TrackerGroupByDayOfWeek extends TrackerGroupBy {
  const TrackerGroupByDayOfWeek();
  @override
  String get kind => 'dayOfWeek';
  @override
  bool operator ==(Object other) => other is TrackerGroupByDayOfWeek;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'TrackerGroupByDayOfWeek()';
}
```

- [ ] **Step 6: Write `TrackerQuerySpec`**

Create `packages/nimbus_domain/lib/src/trackers/tracker_query_spec.dart`:

```dart
import 'package:meta/meta.dart';

import '../analytics/aggregate.dart';
import '../analytics/json_support.dart';
import '../calendar/date_key.dart';
import 'tracker_group_by.dart';

/// One question about trackers: which trackers, over which days, bucketed
/// how, computing what.
///
/// The tracker counterpart of `QuerySpec`, answered by the same
/// `AnalyticsEngine`. Pure and serializable, because Phase 5 stores one as a
/// tracker goal's scope: a field that does not survive a JSON round trip
/// would change what a goal measures.
@immutable
final class TrackerQuerySpec {
  /// Throws [ArgumentError] when [trackerIds] is empty. "Every tracker" is not
  /// a question: litres and cigarettes do not add up.
  TrackerQuerySpec({
    required List<String> trackerIds,
    this.dateRange,
    required this.groupBy,
    required this.aggregate,
  }) : trackerIds = List.unmodifiable(trackerIds) {
    if (trackerIds.isEmpty) {
      throw ArgumentError.value(
          trackerIds, 'trackerIds', 'name at least one tracker');
    }
  }

  /// Throws [FormatException] on anything malformed, never guesses: a dropped
  /// or defaulted field would quietly change what a stored goal measures.
  factory TrackerQuerySpec.fromJson(Map<String, Object?> json) =>
      TrackerQuerySpec(
        trackerIds: _idsOf(json['trackerIds']),
        dateRange: _rangeOf(json['dateRange']),
        groupBy:
            TrackerGroupBy.fromJson(jsonMapOf(json['groupBy'], 'groupBy')),
        aggregate: _aggregateOf(json['aggregate']),
      );

  /// Unmodifiable, in the order given. Equality compares them in that order.
  final List<String> trackerIds;
  final DateRange? dateRange;
  final TrackerGroupBy groupBy;
  final Aggregate aggregate;

  Map<String, Object?> toJson() => {
        'trackerIds': trackerIds,
        if (dateRange != null)
          'dateRange': {
            'start': dateRange!.startInclusive.value,
            'end': dateRange!.endInclusive.value,
          },
        'groupBy': groupBy.toJson(),
        'aggregate': aggregate.name,
      };

  /// This question over [range] instead; null makes it undated.
  TrackerQuerySpec withDateRange(DateRange? range) => TrackerQuerySpec(
        trackerIds: trackerIds,
        dateRange: range,
        groupBy: groupBy,
        aggregate: aggregate,
      );

  static List<String> _idsOf(Object? raw) {
    if (raw is! List || raw.isEmpty || raw.any((id) => id is! String)) {
      throw FormatException(
          'trackerIds needs a non-empty list of strings, got "$raw"');
    }
    return raw.cast<String>();
  }

  static DateRange? _rangeOf(Object? raw) {
    if (raw == null) return null;
    final map = jsonMapOf(raw, 'dateRange');
    final start = map['start'];
    final end = map['end'];
    if (start is! int || end is! int) {
      // Both ends are required. Defaulting one would quietly widen or narrow
      // every answer computed from the stored spec.
      throw FormatException('dateRange needs int start and end, got '
          '"$start" and "$end"');
    }
    return DateRange(DateKey(start), DateKey(end));
  }

  static Aggregate _aggregateOf(Object? raw) {
    for (final value in Aggregate.values) {
      if (value.name == raw) return value;
    }
    throw FormatException('unknown aggregate "$raw"');
  }

  @override
  bool operator ==(Object other) =>
      other is TrackerQuerySpec &&
      _sameIds(other.trackerIds, trackerIds) &&
      other.dateRange == dateRange &&
      other.groupBy == groupBy &&
      other.aggregate == aggregate;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(trackerIds), dateRange, groupBy, aggregate);

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'TrackerQuerySpec($trackerIds, $groupBy, ${aggregate.name})';
}
```

- [ ] **Step 7: Write `TrackerKey` and the result types**

In `packages/nimbus_domain/lib/src/analytics/analytics_result.dart`, insert this after the `TagCategoryKey` class and before `/// One row of an answer.`:

```dart
/// One tracker's bucket, when a tracker query groups by tracker.
///
/// Here rather than beside the tracker types because a sealed class's
/// subclasses must share its library. Phase 3's screens match keys with
/// `case` patterns, not exhaustive switches, so a new key changes nothing
/// for them.
final class TrackerKey extends BucketKey {
  const TrackerKey(this.trackerId);
  final String trackerId;
  @override
  bool operator ==(Object other) =>
      other is TrackerKey && other.trackerId == trackerId;
  @override
  int get hashCode => trackerId.hashCode;
  @override
  String toString() => 'TrackerKey($trackerId)';
}
```

Create `packages/nimbus_domain/lib/src/trackers/tracker_result.dart`:

```dart
import 'package:meta/meta.dart';

import '../analytics/analytics_result.dart';

/// One row of a tracker answer.
@immutable
final class TrackerBucket {
  const TrackerBucket({
    required this.key,
    required this.value,
    required this.count,
  });

  /// `TotalKey`, `TrackerKey`, `PeriodKey`, `HourOfDayKey` or
  /// `DayOfWeekKey`, following the query's `TrackerGroupBy`.
  final BucketKey key;

  /// The aggregate's answer for this bucket: the sum for `Aggregate.sum`, the
  /// entry count for `Aggregate.count`, and so on. Unlike Phase 3's
  /// `Bucket.money`, a double can hold a count, so a count is not left at
  /// zero.
  final double value;

  /// How many entries fell in this bucket, whatever the aggregate.
  final int count;

  @override
  bool operator ==(Object other) =>
      other is TrackerBucket &&
      other.key == key &&
      other.value == value &&
      other.count == count;

  @override
  int get hashCode => Object.hash(key, value, count);

  @override
  String toString() => 'TrackerBucket($key, $value, n=$count)';
}

/// The answer to one `TrackerQuerySpec`.
///
/// No tracker dimension lets an entry land in two buckets, so [sum] and
/// [count] are the buckets' own, added up. There is no separate true total to
/// report, as Phase 3 must for tags.
@immutable
final class TrackerResult {
  const TrackerResult({
    required this.buckets,
    required this.sum,
    required this.count,
  });

  final List<TrackerBucket> buckets;

  /// The sum of every matched entry's value, whatever the aggregate.
  final double sum;

  /// How many entries matched.
  final int count;

  @override
  String toString() =>
      'TrackerResult(${buckets.length} buckets, sum $sum, n=$count)';
}
```

In `packages/nimbus_domain/lib/nimbus_domain.dart`, add three export lines in alphabetical position. They go between `export 'src/trackers/tracker_entry.dart';` and `export 'src/trackers/tracker_results.dart';`:

```dart
export 'src/trackers/tracker_group_by.dart';
export 'src/trackers/tracker_query_spec.dart';
export 'src/trackers/tracker_result.dart';
```

- [ ] **Step 8: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_domain && dart test test/trackers/ test/analytics/`
Expected: PASS. That includes Phase 3's analytics tests, unchanged by the new key.

Then run `dart analyze --fatal-infos` from the repo root.
- Expected: clean.
- If any exhaustive `switch` over `BucketKey` exists anywhere, analyze reports it as non-exhaustive. In that case, add a `TrackerKey()` arm that throws `StateError('a tracker key in a transaction answer')` and name the file in the commit body. A design-time grep found none.

- [ ] **Step 9: Run the full gate**

Expected:
- `nimbus_domain` is 296 + 15 = **311**: 13 spec tests and 2 result tests.
- The rest are unchanged.

- [ ] **Step 10: Commit and merge**

```bash
git add packages/nimbus_domain
git commit -F - <<'EOF'
feat(trackers): TrackerQuerySpec, TrackerGroupBy and TrackerResult

4b answers tracker questions with Phase 3's engine rather than a
second one. This is the question it will be asked. The question is
a spec rather than a call because Phase 5 stores one as a tracker
goal's scope, so it round-trips through JSON and refuses anything
malformed instead of guessing.

TrackerGroupBy is sealed and separate from Phase 3's GroupBy, so a
tracker grouped by category or merchant cannot be written down at
all. It has one way to ask for days: "day" reads local_date_key
directly and needs no range, which is what lets a streak read a
tracker's whole history. "period" refuses day.

Buckets hold a double, because tracker values are one; Bucket.money
stays Money. TrackerKey is added to Phase 3's analytics_result.dart,
because a sealed class's subclasses must share its file. Phase 3's
screens match keys with case patterns, so nothing of theirs changes.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/4-trackers
git merge --ff-only feat/tracker-query-spec
```

---

### Task 4: `GroupExpressions` — tracker fragments on Phase 3's SQL

Branch `feat/tracker-fragments`, slug `tracker-fragments`.

**Files:**
- Modify: `packages/nimbus_data/lib/src/analytics/group_expressions.dart` (Phase 3)
- Test: `packages/nimbus_data/test/analytics/group_expressions_test.dart` (new)

**Interfaces:**
- Consumes: `TrackerGroupBy` and its cases (Task 3).
- Produces:
  - `static String GroupExpressions.hourOfDaySql(String alias)` and `static String GroupExpressions.dayOfWeekSql(String alias)`.
  - `static GroupFragment GroupExpressions.forTrackerDimension(TrackerGroupBy dimension, {DateRange? span, AppCalendar? calendar})`. It always reads `tracker_entries` aliased **`te`**, and its bucket column is aliased `bucket`.
  - `forDimension` keeps its signature and emits byte-identical SQL.

- [ ] **Step 1: Branch**

```bash
git switch phase/4-trackers
git switch -c feat/tracker-fragments
```

- [ ] **Step 2: Write the failing tests**

Create `packages/nimbus_data/test/analytics/group_expressions_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  const janFeb = DateRange(DateKey(20260101), DateKey(20260228));

  group("Phase 3's transaction fragments are unchanged", () {
    // Pinned as text: the alias refactor must not move a character of the SQL
    // that Phase 3's plan tests and device measurements were made on.
    test('hour of day', () {
      expect(GroupExpressions.forDimension(const GroupByHourOfDay()).selectSql,
          'CAST(((t.occurred_at_utc + t.tz_offset_minutes*60000)/3600000) '
          '% 24 AS INTEGER) AS bucket');
    });

    test('day of week', () {
      expect(GroupExpressions.forDimension(const GroupByDayOfWeek()).selectSql,
          "CAST(strftime('%w', (t.occurred_at_utc + t.tz_offset_minutes*60000)"
          "/1000, 'unixepoch') AS INTEGER) AS bucket");
    });

    test('period', () {
      final fragment = GroupExpressions.forDimension(
          const GroupByPeriod(PeriodType.month),
          span: janFeb,
          calendar: const GregorianCalendar());
      expect(
          fragment.selectSql,
          'CASE WHEN t.local_date_key BETWEEN ? AND ? THEN 0 '
          'WHEN t.local_date_key BETWEEN ? AND ? THEN 1 END AS bucket');
      expect(fragment.variables.map((v) => v.value),
          [20260101, 20260131, 20260201, 20260228]);
    });
  });

  group('tracker fragments read tracker_entries as te', () {
    test('hour and weekday share the transaction arithmetic', () {
      expect(
          GroupExpressions.forTrackerDimension(const TrackerGroupByHourOfDay())
              .selectSql,
          'CAST(((te.occurred_at_utc + te.tz_offset_minutes*60000)/3600000) '
          '% 24 AS INTEGER) AS bucket');
      expect(
          GroupExpressions.forTrackerDimension(const TrackerGroupByDayOfWeek())
              .selectSql,
          "CAST(strftime('%w', (te.occurred_at_utc + "
          "te.tz_offset_minutes*60000)/1000, 'unixepoch') AS INTEGER) "
          'AS bucket');
    });

    test('a period walks the same Dart-computed ladder', () {
      final fragment = GroupExpressions.forTrackerDimension(
          TrackerGroupByPeriod(PeriodType.month),
          span: janFeb,
          calendar: const GregorianCalendar());
      expect(
          fragment.selectSql,
          'CASE WHEN te.local_date_key BETWEEN ? AND ? THEN 0 '
          'WHEN te.local_date_key BETWEEN ? AND ? THEN 1 END AS bucket');
      expect(fragment.variables.map((v) => v.value),
          [20260101, 20260131, 20260201, 20260228]);
    });

    test('a period without a range is refused', () {
      expect(
          () => GroupExpressions.forTrackerDimension(
              TrackerGroupByPeriod(PeriodType.month),
              calendar: const GregorianCalendar()),
          throwsArgumentError);
    });

    test('day, tracker and none need no calendar', () {
      expect(
          GroupExpressions.forTrackerDimension(const TrackerGroupByDay())
              .selectSql,
          'te.local_date_key AS bucket');
      expect(
          GroupExpressions.forTrackerDimension(const TrackerGroupByTracker())
              .selectSql,
          'te.tracker_id AS bucket');
      expect(
          GroupExpressions.forTrackerDimension(const TrackerGroupByNone())
              .selectSql,
          '0 AS bucket');
    });

    test('every tracker fragment groups by its bucket and joins nothing', () {
      for (final dimension in <TrackerGroupBy>[
        const TrackerGroupByNone(),
        const TrackerGroupByTracker(),
        const TrackerGroupByDay(),
        TrackerGroupByPeriod(PeriodType.month),
        const TrackerGroupByHourOfDay(),
        const TrackerGroupByDayOfWeek(),
      ]) {
        final fragment = GroupExpressions.forTrackerDimension(dimension,
            span: janFeb, calendar: const GregorianCalendar());
        expect(fragment.groupSql, 'bucket', reason: '$dimension');
        expect(fragment.joinSql, isEmpty, reason: '$dimension');
      }
    });
  });
}
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_data && dart test test/analytics/group_expressions_test.dart`
Expected: FAIL to compile, naming `forTrackerDimension`. (The three Phase 3 tests would pass on their own; they pin the text through the refactor.)

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-tracker-fragments
```

- [ ] **Step 5: Share the expressions and add the tracker switch**

In `packages/nimbus_data/lib/src/analytics/group_expressions.dart`:

1. Replace the `GroupByHourOfDay()` and `GroupByDayOfWeek()` arms of `forDimension` with:

```dart
        GroupByHourOfDay() => (
            selectSql: '${hourOfDaySql('t')} AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        GroupByDayOfWeek() => (
            selectSql: '${dayOfWeekSql('t')} AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
```

2. Replace its period arm `GroupByPeriod(:final period) => _periodFragment(period, span, calendar),` with:

```dart
        GroupByPeriod(:final period) =>
          _periodFragment(period, span, calendar, alias: 't'),
```

3. After `forDimension`, add:

```dart
  /// Builds the fragment for a tracker query's [dimension], against
  /// `tracker_entries` aliased as `te`.
  ///
  /// The dimensions trackers share with transactions -- hour, weekday,
  /// period -- come from the same expressions as [forDimension], so a
  /// tracker's hours and an expense's hours cannot be computed two ways.
  static GroupFragment forTrackerDimension(
    TrackerGroupBy dimension, {
    DateRange? span,
    AppCalendar? calendar,
  }) =>
      switch (dimension) {
        TrackerGroupByNone() => (
            selectSql: '0 AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        TrackerGroupByTracker() => (
            selectSql: 'te.tracker_id AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        // A local day is the same day in every calendar, so this needs
        // neither a range nor a calendar: only the key stamped at write time.
        TrackerGroupByDay() => (
            selectSql: 'te.local_date_key AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        TrackerGroupByPeriod(:final period) =>
          _periodFragment(period, span, calendar, alias: 'te'),
        TrackerGroupByHourOfDay() => (
            selectSql: '${hourOfDaySql('te')} AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        TrackerGroupByDayOfWeek() => (
            selectSql: '${dayOfWeekSql('te')} AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
      };

  /// A row's local hour, 0..23, from its UTC instant and the offset stamped
  /// on it: integer arithmetic on an absolute instant, no calendar involved.
  ///
  /// [alias] names the table: `t` for transactions, `te` for tracker entries.
  /// Both carry `occurred_at_utc` and `tz_offset_minutes`, so one expression
  /// serves both.
  static String hourOfDaySql(String alias) =>
      'CAST((($alias.occurred_at_utc + $alias.tz_offset_minutes*60000)'
      '/3600000) % 24 AS INTEGER)';

  /// A row's local weekday as SQLite's `%w` counts it, 0 = Sunday; the engine
  /// maps it to an ISO weekday.
  ///
  /// strftime is permitted here and nowhere else: the seven-day cycle is
  /// identical in both calendars, so no calendar decision is being made.
  static String dayOfWeekSql(String alias) => "CAST(strftime('%w', "
      '($alias.occurred_at_utc + $alias.tz_offset_minutes*60000)/1000, '
      "'unixepoch') AS INTEGER)";
```

4. Change `_periodFragment`'s signature and its `WHEN` line to take the alias:

```dart
  static GroupFragment _periodFragment(
      PeriodType period, DateRange? span, AppCalendar? calendar,
      {required String alias}) {
```

```dart
      buffer.write(' WHEN $alias.local_date_key BETWEEN ? AND ? THEN $i');
```

The rest of `_periodFragment`, and `periodsOf`, are unchanged.

- [ ] **Step 6: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_data && dart test test/analytics/`
Expected: PASS, including every Phase 3 analytics test unchanged.

- [ ] **Step 7: Run the full gate**

Expected:
- `nimbus_data` is 215 + 8 = **223**.
- The rest are unchanged.

- [ ] **Step 8: Commit and merge**

```bash
git add packages/nimbus_data/lib/src/analytics/group_expressions.dart packages/nimbus_data/test/analytics/group_expressions_test.dart
git commit -F - <<'EOF'
feat(analytics): group expressions for tracker queries

Trackers are about to be grouped by hour, weekday and calendar
period, the three dimensions they share with expenses. Writing that
SQL a second time would let a tracker's hours and an expense's hours
be computed two ways. So the hour and weekday expressions and the
period ladder now take a table alias, and forTrackerDimension builds
tracker fragments from them, against tracker_entries as te.

forDimension emits byte-identical SQL for transactions. A test pins
the three shared fragments as text, so the refactor provably moved
nothing that Phase 3's plan tests and device measurements stand on.

This edits Phase 3's group_expressions.dart.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/4-trackers
git merge --ff-only feat/tracker-fragments
```

---

### Task 5: The engine runs tracker queries

Branch `feat/tracker-engine`, slug `tracker-engine`.

**Files:**
- Modify: `packages/nimbus_data/lib/src/analytics/analytics_engine.dart` (Phase 3)
- Test: `packages/nimbus_data/test/analytics/tracker_engine_test.dart`, `packages/nimbus_data/test/analytics/tracker_query_plan_test.dart` (both new)

**Interfaces:**
- Consumes:
  - `GroupExpressions.forTrackerDimension` and `periodsOf` (Task 4);
  - `TrackerQuerySpec`, `TrackerResult`, `TrackerBucket` and `TrackerKey` (Task 3);
  - `newTracker`, `newEntry` and the `tzOffsetMinutes` parameter (Task 2) in `test/trackers/support/tracker_rows.dart`.
- Produces:
  - `CompiledQuery AnalyticsEngine.compileTracker(TrackerQuerySpec spec)`;
  - `Future<TrackerResult> AnalyticsEngine.runTracker(TrackerQuerySpec spec)`;
  - `Stream<void> AnalyticsEngine.trackerChanges()`, which fires on writes to `tracker_entries` only.

- [ ] **Step 1: Branch**

```bash
git switch phase/4-trackers
git switch -c feat/tracker-engine
```

- [ ] **Step 2: Write the failing tests**

Create `packages/nimbus_data/test/analytics/tracker_engine_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import '../trackers/support/tracker_rows.dart';

void main() {
  late AppDatabase db;
  late AnalyticsEngine engine;

  /// [hourUtc] o'clock UTC on that day. At 05:00 UTC, Tehran reads 08:30.
  DateTime at(int month, int day, [int hourUtc = 5]) =>
      DateTime.utc(2026, month, day, hourUtc);

  TrackerQuerySpec spec(List<String> ids, TrackerGroupBy groupBy,
          {DateRange? range, Aggregate aggregate = Aggregate.sum}) =>
      TrackerQuerySpec(
          trackerIds: ids,
          dateRange: range,
          groupBy: groupBy,
          aggregate: aggregate);

  Map<BucketKey, double> valuesOf(TrackerResult result) =>
      {for (final bucket in result.buckets) bucket.key: bucket.value};

  DateRange oneDay(int key) => DateRange(DateKey(key), DateKey(key));

  // Hand-computed expectations depend on these rows; change one and recompute.
  // Every entry is logged in Tehran (+3:30) unless it says otherwise.
  // - cig: Mon 5 Jan at 08:30 and 19:30, Tue 6 Jan, Sun 25 Jan, Tue 10 Feb,
  //   plus one soft-deleted on 5 Jan.
  // - water: 0.5 and 0.25 on 5 Jan, at 08:30 and 09:30.
  // - gym: done on 6 Jan.
  // - empty: nothing.
  setUp(() async {
    db = openTestDatabase();
    engine = AnalyticsEngine(db, calendar: const GregorianCalendar());
    await db.trackersDao.insertAll([
      newTracker('cig', TrackerType.counter),
      newTracker('water', TrackerType.quantity, perTapValue: 0.25),
      newTracker('gym', TrackerType.boolean),
      newTracker('empty', TrackerType.counter),
    ]);
    final dao = db.trackerEntriesDao;
    await dao.insertEntry(
        newEntry('c1', 'cig', at: at(1, 5), day: const DateKey(20260105)));
    await dao.insertEntry(newEntry('c2', 'cig',
        at: at(1, 5, 16), day: const DateKey(20260105)));
    await dao.insertEntry(
        newEntry('c3', 'cig', at: at(1, 6), day: const DateKey(20260106)));
    await dao.insertEntry(
        newEntry('c4', 'cig', at: at(1, 25), day: const DateKey(20260125)));
    await dao.insertEntry(
        newEntry('c5', 'cig', at: at(2, 10), day: const DateKey(20260210)));
    await dao.insertEntry(
        newEntry('gone', 'cig', at: at(1, 5), day: const DateKey(20260105)));
    await dao.softDelete('gone');
    await dao.insertEntry(newEntry('w1', 'water',
        value: 0.5, at: at(1, 5), day: const DateKey(20260105)));
    await dao.insertEntry(newEntry('w2', 'water',
        value: 0.25, at: at(1, 5, 6), day: const DateKey(20260105)));
    await dao.insertEntry(newEntry('g1', 'gym',
        at: at(1, 6), day: const DateKey(20260106), oncePerDay: true));
  });
  tearDown(() => db.close());

  test('no grouping answers one bucket, and the totals beside it', () async {
    final result =
        await engine.runTracker(spec(['cig'], const TrackerGroupByNone()));
    expect(result.buckets,
        [const TrackerBucket(key: TotalKey(), value: 5, count: 5)]);
    expect(result.sum, 5);
    expect(result.count, 5);
  });

  test('soft-deleted entries and other trackers are left out', () async {
    final result = await engine.runTracker(spec(
        ['cig'], const TrackerGroupByNone(),
        range: oneDay(20260105)));
    // c1 and c2. Not "gone", not water's two.
    expect(result.sum, 2);
    expect(result.count, 2);
  });

  test('grouping by tracker keys each tracker that has entries', () async {
    final result = await engine.runTracker(spec(
        ['cig', 'water', 'empty'], const TrackerGroupByTracker(),
        range: oneDay(20260105)));
    expect(valuesOf(result),
        {const TrackerKey('cig'): 2.0, const TrackerKey('water'): 0.75});
    expect(result.sum, 2.75);
    expect(result.count, 4);
  });

  test('grouping by day needs no date range, and comes oldest first',
      () async {
    final result =
        await engine.runTracker(spec(['cig'], const TrackerGroupByDay()));
    expect(result.buckets.map((b) => (b.key, b.value)), [
      (PeriodKey(oneDay(20260105)), 2.0),
      (PeriodKey(oneDay(20260106)), 1.0),
      (PeriodKey(oneDay(20260125)), 1.0),
      (PeriodKey(oneDay(20260210)), 1.0),
    ]);
  });

  test("grouping by month uses the calendar's months", () async {
    final result = await engine.runTracker(spec(
        ['cig'], TrackerGroupByPeriod(PeriodType.month),
        range: const DateRange(DateKey(20260101), DateKey(20260228))));
    expect(valuesOf(result), {
      const PeriodKey(DateRange(DateKey(20260101), DateKey(20260131))): 4.0,
      const PeriodKey(DateRange(DateKey(20260201), DateKey(20260228))): 1.0,
    });
  });

  test('a Jalali month is not a Gregorian one', () async {
    // Dey 1404 is 22 Dec - 20 Jan and Bahman 21 Jan - 19 Feb, so 25 Jan moves
    // from January's bucket into Bahman's.
    final jalali = AnalyticsEngine(db, calendar: const JalaliCalendar());
    final result = await jalali.runTracker(spec(
        ['cig'], TrackerGroupByPeriod(PeriodType.month),
        range: const DateRange(DateKey(20251222), DateKey(20260219))));
    expect(valuesOf(result), {
      const PeriodKey(DateRange(DateKey(20251222), DateKey(20260120))): 3.0,
      const PeriodKey(DateRange(DateKey(20260121), DateKey(20260219))): 2.0,
    });
  });

  test('grouping by period without a date range is refused', () async {
    await expectLater(
        engine.runTracker(
            spec(['cig'], TrackerGroupByPeriod(PeriodType.month))),
        throwsArgumentError);
  });

  test("hour of day reads each entry's own offset", () async {
    // The same instant, logged in Tehran (+3:30) and in Kabul (+4:30): two
    // different local hours.
    await db.trackersDao.insertAll([newTracker('trip', TrackerType.counter)]);
    final dao = db.trackerEntriesDao;
    await dao.insertEntry(newEntry('home', 'trip',
        at: at(3, 1), day: const DateKey(20260301), tzOffsetMinutes: 210));
    await dao.insertEntry(newEntry('away', 'trip',
        at: at(3, 1), day: const DateKey(20260301), tzOffsetMinutes: 270));

    final result = await engine
        .runTracker(spec(['trip'], const TrackerGroupByHourOfDay()));
    expect(valuesOf(result), {HourOfDayKey(8): 1.0, HourOfDayKey(9): 1.0});
  });

  test('hour of day over the fixture', () async {
    final result = await engine
        .runTracker(spec(['cig'], const TrackerGroupByHourOfDay()));
    // c2 at 16:00 UTC reads 19:30; every other one 08:30.
    expect(valuesOf(result), {HourOfDayKey(8): 4.0, HourOfDayKey(19): 1.0});
  });

  test('day of week answers ISO weekdays, Sunday as 7', () async {
    final result = await engine
        .runTracker(spec(['cig'], const TrackerGroupByDayOfWeek()));
    expect(valuesOf(result), {
      DayOfWeekKey(DateTime.monday): 2.0,
      DayOfWeekKey(DateTime.tuesday): 2.0,
      DayOfWeekKey(DateTime.sunday): 1.0,
    });
  });

  test('each aggregate answers in value; count is always the entry count',
      () async {
    Future<TrackerBucket> one(Aggregate aggregate) async => (await engine
            .runTracker(spec(['water'], const TrackerGroupByNone(),
                range: oneDay(20260105), aggregate: aggregate)))
        .buckets
        .single;

    expect((await one(Aggregate.sum)).value, 0.75);
    expect((await one(Aggregate.count)).value, 2);
    expect((await one(Aggregate.average)).value, 0.375);
    expect((await one(Aggregate.min)).value, 0.25);
    expect((await one(Aggregate.max)).value, 0.5);
    expect((await one(Aggregate.max)).count, 2);
  });

  test('a tracker with no entries answers no buckets and zeros', () async {
    final result =
        await engine.runTracker(spec(['empty'], const TrackerGroupByNone()));
    expect(result.buckets, isEmpty);
    expect(result.sum, 0);
    expect(result.count, 0);
  });

  test('trackerChanges fires on an entry write', () async {
    final fired = expectLater(engine.trackerChanges(), emits(anything));
    await db.trackerEntriesDao.insertEntry(newEntry('new', 'cig'));
    await fired;
  });

  test('trackerChanges ignores a settings write', () async {
    var fired = false;
    final subscription = engine.trackerChanges().listen((_) => fired = true);
    addTearDown(subscription.cancel);
    await db.settingsDao.put('locale', 'en');
    await pumpEventQueue();
    expect(fired, isFalse);
  });
}
```

Create `packages/nimbus_data/test/analytics/tracker_query_plan_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';

void main() {
  late AppDatabase db;
  late AnalyticsEngine engine;

  setUp(() {
    db = openTestDatabase();
    engine = AnalyticsEngine(db, calendar: const JalaliCalendar());
  });
  tearDown(() => db.close());

  /// The plan of the statement the engine will actually run.
  Future<String> planFor(TrackerQuerySpec spec) async {
    final compiled = engine.compileTracker(spec);
    final rows = await db
        .customSelect('EXPLAIN QUERY PLAN ${compiled.sql}',
            variables: compiled.variables)
        .get();
    return rows.map((r) => r.data['detail']).join(' | ');
  }

  // SQLite names an aliased table by its alias, so a full pass reads
  // "SCAN te", with or without an index after it.
  final scansEntries = matches(RegExp(r'SCAN te\b'));

  const today = DateRange(DateKey(20261005), DateKey(20261005));
  const mehr = DateRange(DateKey(20260923), DateKey(20261022));
  const year = DateRange(DateKey(20260321), DateKey(20270320));

  // Every shape the app issues (Tasks 6, 8, 9 and 10).
  final shapes = <String, TrackerQuerySpec>{
    "today's totals by tracker": TrackerQuerySpec(
        trackerIds: ['cig', 'water', 'gym'],
        dateRange: today,
        groupBy: const TrackerGroupByTracker(),
        aggregate: Aggregate.sum),
    'a range by day': TrackerQuerySpec(
        trackerIds: ['cig'],
        dateRange: mehr,
        groupBy: const TrackerGroupByDay(),
        aggregate: Aggregate.sum),
    'the whole history by day': TrackerQuerySpec(
        trackerIds: ['cig'],
        groupBy: const TrackerGroupByDay(),
        aggregate: Aggregate.count),
    'a range by hour': TrackerQuerySpec(
        trackerIds: ['cig'],
        dateRange: mehr,
        groupBy: const TrackerGroupByHourOfDay(),
        aggregate: Aggregate.sum),
    'a range by weekday': TrackerQuerySpec(
        trackerIds: ['cig'],
        dateRange: mehr,
        groupBy: const TrackerGroupByDayOfWeek(),
        aggregate: Aggregate.sum),
    'a year by month': TrackerQuerySpec(
        trackerIds: ['cig'],
        dateRange: year,
        groupBy: TrackerGroupByPeriod(PeriodType.month),
        aggregate: Aggregate.sum),
  };

  for (final MapEntry(key: name, value: spec) in shapes.entries) {
    test('$name seeks the tracker-day index', () async {
      final plan = await planFor(spec);
      expect(plan, contains('idx_tracker_entries_tracker_day'),
          reason: 'every tap re-runs the open tracker queries; one that '
              "walks a tracker's whole history slows with every day "
              'logged.\nPlan was: $plan');
      expect(plan, isNot(scansEntries), reason: 'plan: $plan');
    });
  }

  test('the whole history by day reads in index order, with no sort',
      () async {
    final plan = await planFor(shapes['the whole history by day']!);
    expect(plan, isNot(contains('TEMP B-TREE')), reason: plan);
  });
}
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_data && dart test test/analytics/tracker_engine_test.dart test/analytics/tracker_query_plan_test.dart`
Expected: FAIL to compile, naming `runTracker`, `compileTracker` and `trackerChanges`.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-tracker-engine
```

- [ ] **Step 5: Teach the engine the second table**

In `packages/nimbus_data/lib/src/analytics/analytics_engine.dart`:

1. In the class doc, after the paragraph beginning `One engine, not two`, add:

```dart
///
/// Tracker questions come here too, as a [TrackerQuerySpec]: the same engine
/// over `tracker_entries`, with the same SQL for the dimensions the two
/// tables share.
```

2. After `run`, add:

```dart
  /// The statement for a tracker question: [compile]'s counterpart over
  /// `tracker_entries`.
  ///
  /// Still one engine. The dimensions trackers share with transactions come
  /// from the same [GroupExpressions], and the soft-delete rule from the same
  /// [AnalyticsPredicates.notDeleted].
  CompiledQuery compileTracker(TrackerQuerySpec spec) {
    final group = GroupExpressions.forTrackerDimension(
      spec.groupBy,
      span: spec.dateRange,
      calendar: calendar,
    );
    final placeholders = List.filled(spec.trackerIds.length, '?').join(',');
    final conditions = <String>[
      AnalyticsPredicates.notDeleted('te'),
      'te.tracker_id IN ($placeholders)',
    ];
    // Variable order must match placeholder order in the finished statement:
    // SELECT fragments first, then WHERE.
    final variables = <Variable<Object>>[
      ...group.variables,
      ...spec.trackerIds.map(Variable.withString),
    ];
    final range = spec.dateRange;
    if (range != null) {
      conditions.add('te.local_date_key BETWEEN ? AND ?');
      variables
        ..add(Variable.withInt(range.startInclusive.value))
        ..add(Variable.withInt(range.endInclusive.value));
    }

    final sql = 'SELECT ${group.selectSql}, '
        'COALESCE(SUM(te.value), 0) AS total, '
        'COUNT(*) AS n, '
        'MIN(te.value) AS low, MAX(te.value) AS high, AVG(te.value) AS mean '
        'FROM tracker_entries te '
        'WHERE ${conditions.join(' AND ')} '
        'GROUP BY ${group.groupSql} '
        'ORDER BY ${group.groupSql}';
    return CompiledQuery(sql: sql, variables: variables);
  }

  /// Fires whenever a tracker entry is written. A spec names its trackers by
  /// id, so a write to `trackers` itself changes no answer.
  Stream<void> trackerChanges() => _db
      .tableUpdates(TableUpdateQuery.onTable(_db.trackerEntries))
      .map((_) {});

  Future<TrackerResult> runTracker(TrackerQuerySpec spec) async {
    final compiled = compileTracker(spec);
    final rows = await _db
        .customSelect(compiled.sql, variables: compiled.variables)
        .get();

    final periods = switch (spec.groupBy) {
      TrackerGroupByPeriod(:final period) =>
        GroupExpressions.periodsOf(period, spec.dateRange!, calendar),
      _ => const <DateRange>[],
    };

    // No tracker dimension puts an entry in two buckets, so the totals are
    // the rows' own, added up -- no second statement.
    final buckets = <TrackerBucket>[];
    var sum = 0.0;
    var count = 0;
    for (final row in rows) {
      final n = row.data['n']! as int;
      sum += _real(row.data['total']);
      count += n;
      buckets.add(TrackerBucket(
        key: _trackerKeyOf(spec.groupBy, row, periods),
        value: _trackerValueOf(spec.aggregate, row),
        count: n,
      ));
    }
    return TrackerResult(buckets: buckets, sum: sum, count: count);
  }

  BucketKey _trackerKeyOf(
      TrackerGroupBy dimension, QueryRow row, List<DateRange> periods) {
    final bucket = row.data['bucket'];
    return switch (dimension) {
      TrackerGroupByNone() => const TotalKey(),
      TrackerGroupByTracker() => TrackerKey(bucket! as String),
      TrackerGroupByDay() => PeriodKey(
          DateRange(DateKey(bucket! as int), DateKey(bucket as int))),
      TrackerGroupByPeriod() => PeriodKey(periods[bucket! as int]),
      TrackerGroupByHourOfDay() => HourOfDayKey(bucket! as int),
      // SQLite's %w is 0=Sunday; ISO is 1=Monday..7=Sunday.
      TrackerGroupByDayOfWeek() =>
        DayOfWeekKey(bucket! as int == 0 ? DateTime.sunday : bucket as int),
    };
  }

  static double _trackerValueOf(Aggregate aggregate, QueryRow row) =>
      switch (aggregate) {
        Aggregate.sum => _real(row.data['total']),
        Aggregate.count => (row.data['n']! as int).toDouble(),
        Aggregate.min => _real(row.data['low']),
        Aggregate.max => _real(row.data['high']),
        Aggregate.average => _real(row.data['mean']),
      };

  /// SQLite hands a REAL back as a double, but it may store a whole value as
  /// an integer, and an aggregate over those can come back as an int.
  static double _real(Object? raw) => (raw! as num).toDouble();
```

- [ ] **Step 6: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_data && dart test test/analytics/`
Expected: PASS.

**If a plan test fails, read the plan in its reason before touching anything.**
- If SQLite picked `idx_tracker_entries_history` over the new index on the app's bundled build, the measurement in the spec no longer holds there. **Stop and report it.**
- Do not loosen the assertion. Do not add an `INDEXED BY` clause without the operator's agreement.

**Mutation check.**
1. In `compileTracker`, drop the `AnalyticsPredicates.notDeleted('te')` condition.
2. Re-run. Expected: "soft-deleted entries and other trackers are left out" and "no grouping answers one bucket…" FAIL, with 3 and 6.
3. Restore it.

- [ ] **Step 7: Run the full gate**

Expected:
- `nimbus_data` is 223 + 21 = **244**: 14 engine tests and 7 plan tests.
- The rest are unchanged.

- [ ] **Step 8: Commit and merge**

```bash
git add packages/nimbus_data/lib/src/analytics/analytics_engine.dart packages/nimbus_data/test/analytics/tracker_engine_test.dart packages/nimbus_data/test/analytics/tracker_query_plan_test.dart
git commit -F - <<'EOF'
feat(analytics): the engine runs tracker queries

A tracker spec compiles to one statement over tracker_entries, in
the same AnalyticsEngine as every expense question. The hour,
weekday and period buckets come from the expressions the two tables
now share, and soft deletes go through the one notDeleted helper. A
second engine for trackers would be exactly how the brief says the
numbers start disagreeing.

Buckets come back as doubles. A count answers in value, because a
double can hold one where Money could not. The engine adds the
totals up from the rows: no tracker dimension puts an entry in two
buckets, so there is no true total to fetch apart from them.

Every query shape the app will issue is plan-tested to seek the
(tracker_id, local_date_key) index, so a tap's re-run does not slow
down with every day logged. A whole-history day query reads it in
order with no sort, which is what the streaks need.

This edits Phase 3's analytics_engine.dart.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/4-trackers
git merge --ff-only feat/tracker-engine
```

---

### Task 6: Today's totals come from the engine

Branch `feat/engine-totals`, slug `engine-totals`.

**Files:**
- Create: `packages/nimbus_domain/lib/src/trackers/tracker_queries.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart`
- Modify: `packages/nimbus_data/lib/src/trackers/tracker_entries_dao.dart` (the day totals are deleted)
- Modify: `app/lib/features/trackers/data/tracker_repository.dart`
- Modify: `app/lib/features/trackers/application/tracker_providers.dart`
- Modify: `app/lib/features/trackers/presentation/trackers_screen.dart`, `app/lib/features/trackers/presentation/tracker_detail_screen.dart`
- Test: `packages/nimbus_domain/test/trackers/tracker_queries_test.dart` (new), `test/architecture_test.dart` (Phase 0), `packages/nimbus_data/test/trackers/tracker_entries_dao_test.dart`, `app/test/features/trackers/support/tracker_fixture.dart`, `app/test/features/trackers/tracker_repository_test.dart`, `app/test/features/trackers/tracker_detail_screen_test.dart`

**Interfaces:**
- Consumes: `AnalyticsEngine.runTracker` and `trackerChanges` (Task 5); `analyticsEngineProvider` (Phase 3, read-only import).
- Produces:
  - `TrackerQueries.dayTotals(List<String> trackerIds, DateKey day)` (group by tracker, sum) and `TrackerQueries.dayTotal(String trackerId, DateKey day)` (none, sum).
  - `TrackerRepository(TrackersDao, TrackerEntriesDao, AnalyticsEngine, TrackerClock)`.
  - `trackerResultProvider`: `FutureProvider.autoDispose.family<TrackerResult, TrackerQuerySpec>`.
  - `trackerTotalsProvider`: `Provider.autoDispose<AsyncValue<Map<String, double>>>`.
  - `trackerDayTotalProvider`: `Provider.autoDispose.family<AsyncValue<double>, String>`.
  - `TrackerRepository.watchTotals` is deleted. `totalOn(trackerId, day)` keeps its signature.

- [ ] **Step 1: Branch**

```bash
git switch phase/4-trackers
git switch -c feat/engine-totals
```

- [ ] **Step 2: Write the failing tests**

Append to `test/architecture_test.dart`, inside `main`:

```dart
  test('tracker code aggregates only through the analytics engine', () {
    // Phase 4b's definition of done, kept as a test rather than a one-off grep
    // so that no later change can quietly grow a second query engine beside
    // Phase 3's. Comment lines are skipped: they may name what they avoid.
    final aggregate = RegExp(r'\b(SUM|COUNT|AVG|MIN|MAX)\s*\(|GROUP BY'
        r'|\.(sum|count|avg|min|max)\(\)|\.groupBy\(');
    // Placing a new tracker at the end of the list as it is written. It reads
    // one column's maximum to choose a position and answers no analytical
    // question.
    const allowed = {'final highest = _db.trackers.sortOrder.max();'};

    final offenders = <String>[];
    for (final dir in [
      'packages/nimbus_data/lib/src/trackers',
      'app/lib/features/trackers',
    ]) {
      final files = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));
      for (final file in files) {
        for (final (index, line) in file.readAsLinesSync().indexed) {
          final code = line.trim();
          if (code.startsWith('//')) continue;
          if (aggregate.hasMatch(code) && !allowed.contains(code)) {
            offenders.add('${file.path}:${index + 1}: $code');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'aggregation belongs in AnalyticsEngine:\n'
            '${offenders.join('\n')}');
  });
```

Create `packages/nimbus_domain/test/trackers/tracker_queries_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  const day = DateKey(20261005);
  const oneDay = DateRange(day, day);

  test("the tab asks for each tracker's total that day", () {
    expect(
        TrackerQueries.dayTotals(['cig', 'water'], day),
        TrackerQuerySpec(
            trackerIds: ['cig', 'water'],
            dateRange: oneDay,
            groupBy: const TrackerGroupByTracker(),
            aggregate: Aggregate.sum));
  });

  test("the snackbar and the header ask for one tracker's total", () {
    expect(
        TrackerQueries.dayTotal('cig', day),
        TrackerQuerySpec(
            trackerIds: ['cig'],
            dateRange: oneDay,
            groupBy: const TrackerGroupByNone(),
            aggregate: Aggregate.sum));
  });
}
```

In `app/test/features/trackers/support/tracker_fixture.dart`, replace `repositoryFor` with:

```dart
TrackerRepository repositoryFor(AppDatabase db, FakeClock fake) =>
    TrackerRepository(db.trackersDao, db.trackerEntriesDao,
        AnalyticsEngine(db, calendar: const JalaliCalendar()), fake.clock);
```

Append to `app/test/features/trackers/tracker_repository_test.dart`, inside `main`:

```dart
  group('totals', () {
    test("totalOn sums one tracker's live entries on one day", () async {
      final cig = await repo.create(cigarettes);
      final w = await repo.create(water);
      await repo.logEntry(cig.id);
      final second = (await repo.logEntry(cig.id) as EntryLogged).entry;
      await repo.logEntry(cig.id,
          at: fake.nowUtc.subtract(const Duration(days: 1)));
      await repo.logEntry(w.id);
      await repo.deleteEntry(second.id);

      expect(await repo.totalOn(cig.id, const DateKey(20261005)), 1);
      expect(await repo.totalOn(w.id, const DateKey(20261005)), 0.25);
      expect(await repo.totalOn(cig.id, const DateKey(20261006)), 0);
    });
  });
```

Append to `app/test/features/trackers/tracker_detail_screen_test.dart`, inside `main` (Review Focus 3):

```dart
  testWidgets("an archived tracker's header still counts today",
      (tester) async {
    // The tab's totals cover the tab's trackers, and an archived tracker is
    // not on the tab. The header asks for its own total.
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await repo.logEntry(cig.id);
    await repo.logEntry(cig.id);
    await repo.archive(cig.id);

    await openDetail(tester, cig.id);

    expect(textIn(tester, const Key('tracker-detail-total')), '2 today');
  });
```

The repository and detail tests pass today; they guard this task's change. Its red tests are the architecture test and the domain test.

- [ ] **Step 3: Run the tests to confirm RED**

- `dart test test/architecture_test.dart` from the repo root. Expected: FAIL. The new test lists `tracker_entries_dao.dart`'s `final total = entries.value.sum();` and `..groupBy([entries.trackerId]);`.
- `cd packages/nimbus_domain && dart test test/trackers/tracker_queries_test.dart`. Expected: FAIL to compile, naming `TrackerQueries`.
- The app fixture now fails to compile until Step 7, which is expected: `TrackerRepository` takes three arguments.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-engine-totals
```

- [ ] **Step 5: Write `TrackerQueries`**

Create `packages/nimbus_domain/lib/src/trackers/tracker_queries.dart`:

```dart
import '../analytics/aggregate.dart';
import '../calendar/date_key.dart';
import 'tracker_group_by.dart';
import 'tracker_query_spec.dart';

/// The tracker questions the app asks, worded in one place.
///
/// Every screen that shows a tracker number asks through one of these, so the
/// tab, the snackbar and the detail screen cannot word one question two ways.
/// Two wordings would be two cache entries and two queries for one answer.
abstract final class TrackerQueries {
  /// Each of [trackerIds]' totals on [day]: the tab. A tracker with nothing
  /// logged that day has no bucket.
  static TrackerQuerySpec dayTotals(List<String> trackerIds, DateKey day) =>
      TrackerQuerySpec(
        trackerIds: trackerIds,
        dateRange: DateRange(day, day),
        groupBy: const TrackerGroupByTracker(),
        aggregate: Aggregate.sum,
      );

  /// One tracker's total on [day]: the snackbar after a tap, and the detail
  /// header.
  static TrackerQuerySpec dayTotal(String trackerId, DateKey day) =>
      TrackerQuerySpec(
        trackerIds: [trackerId],
        dateRange: DateRange(day, day),
        groupBy: const TrackerGroupByNone(),
        aggregate: Aggregate.sum,
      );
}
```

In `packages/nimbus_domain/lib/nimbus_domain.dart`, add `export 'src/trackers/tracker_queries.dart';` between `export 'src/trackers/tracker_group_by.dart';` and `export 'src/trackers/tracker_query_spec.dart';`.

- [ ] **Step 6: Delete the DAO's aggregate**

In `packages/nimbus_data/lib/src/trackers/tracker_entries_dao.dart`, delete these, together with their doc comments:
- `watchDayTotals`
- `dayTotals`
- `_byTracker`
- `dayTotalsQuery`
- `_dayTotals`

In `packages/nimbus_data/test/trackers/tracker_entries_dao_test.dart`, delete four tests:
- "day totals sum each tracker's live entries for that day only"
- "dayTotals reads the same totals once, without a subscription"
- "day totals follow writes"
- the plan test "day totals seek the day index and need no temp B-tree"

The engine's tests now cover what they proved: Task 5's per-tracker sums and soft-delete exclusion, and the "today's totals by tracker" plan.

- [ ] **Step 7: Read totals through the engine**

In `app/lib/features/trackers/data/tracker_repository.dart`:

1. Replace the constructor and fields with:

```dart
  /// Positional to keep the DAOs private, as `TransactionRepository` does.
  const TrackerRepository(
      this._trackers, this._entries, this._engine, this._clock);

  final TrackersDao _trackers;
  final TrackerEntriesDao _entries;

  /// Every total this repository reads comes from Phase 3's engine. The DAOs
  /// hold no aggregate of their own.
  final AnalyticsEngine _engine;
  final TrackerClock _clock;
```

2. Delete `watchTotals` with its doc, and replace `totalOn` with:

```dart
  /// One tracker's total for [day], read once: the snackbar after a tap.
  Future<double> totalOn(String trackerId, DateKey day) async =>
      (await _engine.runTracker(TrackerQueries.dayTotal(trackerId, day))).sum;
```

In `app/lib/features/trackers/application/tracker_providers.dart`:

1. Add the import `import '../../analytics/application/analytics_providers.dart';`.
2. Replace `trackerRepositoryProvider` with:

```dart
final trackerRepositoryProvider = Provider<TrackerRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TrackerRepository(db.trackersDao, db.trackerEntriesDao,
      ref.watch(analyticsEngineProvider), ref.watch(trackerClockProvider));
});
```

3. Replace `trackerTotalsProvider` and its doc with:

```dart
/// The answer to one tracker question, keyed on the question itself.
///
/// Mirrors Phase 3's `analyticsResultProvider`. It is auto-disposed, and
/// re-run whenever the engine reports a tracker entry write, so a total never
/// outlives the tap that changed it. Two widgets asking the same question
/// share one query, because `TrackerQuerySpec` has value equality.
final trackerResultProvider =
    FutureProvider.autoDispose.family<TrackerResult, TrackerQuerySpec>(
  (ref, spec) async {
    final engine = ref.watch(analyticsEngineProvider);
    final changes = engine.trackerChanges().listen((_) => ref.invalidateSelf());
    ref.onDispose(changes.cancel);
    return engine.runTracker(spec);
  },
);

/// Every tab tracker's total for today, keyed by tracker id. A tracker with
/// nothing logged today has no key.
///
/// A synchronous view over [trackerResultProvider] rather than a future that
/// awaits two others: it re-derives the moment either input changes, with no
/// `ref` used after an await. A write's refresh keeps the previous value, so the tab
/// does not flicker to a skeleton between a tap and its new total. (As
/// shipped, a reload or a new question keeps the value too: see Decision 7.)
final trackerTotalsProvider =
    Provider.autoDispose<AsyncValue<Map<String, double>>>((ref) {
  final today = ref.watch(trackerTodayProvider);
  final trackers = ref.watch(trackersProvider);
  if (trackers.hasError) {
    return AsyncError(trackers.error!, trackers.stackTrace!);
  }
  if (!trackers.hasValue) return const AsyncLoading();
  final ids = [for (final tracker in trackers.requireValue) tracker.id];
  if (ids.isEmpty) return const AsyncData({});
  return ref
      .watch(trackerResultProvider(TrackerQueries.dayTotals(ids, today)))
      .whenData((result) => {
            for (final bucket in result.buckets)
              if (bucket.key case TrackerKey(:final trackerId))
                trackerId: bucket.value,
          });
});

/// One tracker's total for today, archived or not: the detail header. The
/// tab's totals cover only the tab's trackers.
final trackerDayTotalProvider =
    Provider.autoDispose.family<AsyncValue<double>, String>((ref, id) => ref
        .watch(trackerResultProvider(
            TrackerQueries.dayTotal(id, ref.watch(trackerTodayProvider))))
        .whenData((result) => result.sum));
```

In `app/lib/features/trackers/presentation/trackers_screen.dart`, the error state's `onRetry` becomes:

```dart
        onRetry: () {
          ref.invalidate(trackersProvider);
          // The whole family: whichever question failed is asked again.
          ref.invalidate(trackerResultProvider);
        },
```

In `app/lib/features/trackers/presentation/tracker_detail_screen.dart`, in `TrackerDetailScreen.build`:
1. Replace `final totals = ref.watch(trackerTotalsProvider);` with `final dayTotal = ref.watch(trackerDayTotalProvider(id));`.
2. In the two state checks and the error state's `detail:`, rename `totals` to `dayTotal`.
3. Make the error state's `onRetry` invalidate `trackerByIdProvider(id)` and `trackerResultProvider`, the latter with the comment `// The whole family: whichever question failed is asked again.`.
4. Replace `final total = totals.requireValue[id] ?? 0;` with `final total = dayTotal.requireValue;`.

`_Header(tracker: current, total: total)` and `_QuickLogBar(tracker: current, total: total)` are unchanged.

- [ ] **Step 8: Run the tests to confirm GREEN**

Run:
- `dart test test/architecture_test.dart`
- `cd packages/nimbus_domain && dart test test/trackers/`
- `cd packages/nimbus_data && dart test test/trackers/`
- `cd app && flutter test --no-pub <absolute path>/app/test/features/trackers/`

Expected: PASS, including every 4a tab, snackbar and detail test, now answered by the engine.

**Mutation check.**
1. Point the detail screen at the tab's map again: `ref.watch(trackerTotalsProvider).whenData((m) => m[id] ?? 0)`.
2. Re-run the detail test. Expected: "an archived tracker's header still counts today" FAILS with `0 today`.
3. Restore it.

- [ ] **Step 9: Run the full gate**

Expected:
- architecture is 4 + 1 = **5**;
- `nimbus_domain` is 311 + 2 = **313**;
- `nimbus_data` is 244 − 4 = **240**;
- `app` is 459 + 2 = **461**.

- [ ] **Step 10: Commit and merge**

```bash
git add test/architecture_test.dart packages/nimbus_domain packages/nimbus_data/lib/src/trackers packages/nimbus_data/test/trackers app/lib/features/trackers app/test/features/trackers
git commit -F - <<'EOF'
refactor(trackers): today's totals come from the engine

4a's tab read today's totals from one DAO SUM ... GROUP BY, a
stand-in the brief named until 4b could ask Phase 3's engine. The
tab, the tap snackbar and the detail header now ask it, through
TrackerQueries, so the three cannot word the question differently.
The DAO's aggregate is deleted.

The detail header asks for its own tracker's total rather than
reading the tab's map. An archived tracker is not on the tab, so it
would read zero there. A test pins it.

The brief's last criterion, "no aggregation SQL outside the engine",
is now a test in architecture_test.dart rather than a grep at the
gate. It allows exactly one line: the sortOrder maximum that places
a new tracker, which answers no analytical question.

Touches Phase 0's architecture_test.dart, and imports Phase 3's
analyticsEngineProvider read-only.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/4-trackers
git merge --ff-only feat/engine-totals
```

---

### Task 7: Schema v32 — the unread day index goes (the schema lock)

Branch `feat/schema-v32`, slug `schema-v32`. This task lands on **`main`** alone (CONVENTIONS §2).
- `main` first fast-forwards to `phase/4-trackers`. Tasks 1–6 are each complete and green, so `main` stays usable.
- The phase branch then fast-forwards back.

**Files:**
- Modify: `packages/nimbus_data/lib/src/tables/tracker_entries_table.dart`
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` (Phase 0)
- Generate: `drift_schemas/drift_schema_v32.json`, `test/generated/schema_v32.dart`, `test/generated/schema.dart`, `lib/src/database/app_database.g.dart`
- Test: `packages/nimbus_data/test/migration_test.dart`, `packages/nimbus_data/test/database_test.dart` (Phase 0)
- Docs: `docs/phases/CONVENTIONS.md`

**Interfaces:**
- Consumes: Task 6, which leaves `idx_tracker_entries_day` with no reader.
- Produces: schema v32, without `idx_tracker_entries_day`. The generated getter `idxTrackerEntriesDay` disappears.

- [ ] **Step 1: Branch**

```bash
git switch main
git merge --ff-only phase/4-trackers
git switch -c feat/schema-v32
```

- [ ] **Step 2: Write the failing tests**

In `packages/nimbus_data/test/database_test.dart`:

1. The version test becomes `opens at schema version 32`, with `expect(db.schemaVersion, 32);`. Its comment's second sentence becomes `Phase 3 took v20 and v21, Phase 4 v30 to v32.`
2. Add:

```dart
  test("a fresh install has no 4a day index", () async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'idx_tracker_entries_day'")
        .get();
    expect(rows, isEmpty);
  });
```

In `packages/nimbus_data/test/migration_test.dart`:

1. The upgrade loop becomes `for (final from in [1, 20, 21, 30, 31])`, its name `'a v$from database upgrades to v32 and matches a fresh install'`, and its call `migrateAndValidate(db, 32)`.
2. Every other `migrateAndValidate(db, 31)` in the file becomes `migrateAndValidate(db, 32)`. That covers the v20 view test, the v1 DAO test, the once-per-day group's `setUp`, and both tests in the v30 group.
3. In the v30 group, the failing-backfill test's `expect(schema.rawDatabase.userVersion, 30);` stays as it is.
4. Append inside `main`:

```dart
  test("a v31 database drops 4a's day index and keeps its entries", () async {
    final schema = await verifier.schemaAt(31);
    schema.rawDatabase
      ..execute(
        'INSERT INTO trackers (id, name, icon_key, color, type, created_at, '
        "updated_at) VALUES ('cig', 'Cigarettes', 'smoking_rooms', 0, "
        "'counter', 0, 0)",
      )
      ..execute(
        'INSERT INTO tracker_entries (id, tracker_id, value, occurred_at_utc, '
        'local_date_key, tz_offset_minutes, once_per_day, created_at, '
        "updated_at) VALUES ('e', 'cig', 1.0, 0, 20261005, 210, 0, 0, 0)",
      );
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    // Validation against the v32 snapshot proves the index is gone, but only
    // with `validateDropped: true` (ruling R8): by default the verifier ignores
    // objects the snapshot does not list.
    await verifier.migrateAndValidate(db, 32,
        options: const ValidationOptions(validateDropped: true));

    final row = await db
        .customSelect(
            "SELECT tz_offset_minutes AS o FROM tracker_entries WHERE id = 'e'")
        .getSingle();
    expect(row.read<int>('o'), 210);
  });
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_data && dart test test/migration_test.dart test/database_test.dart`
Expected:
- FAIL: the version test reads 31.
- FAIL: the fresh install still has `idx_tracker_entries_day`.
- FAIL: the migration tests cannot find schema v32.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-schema-v32
```

- [ ] **Step 5: Remove the index**

In `packages/nimbus_data/lib/src/tables/tracker_entries_table.dart`:
1. Delete the annotation `@TableIndex(name: 'idx_tracker_entries_day', columns: {#localDateKey, #trackerId})`.
2. In the class doc, replace `/// The four indexes:` with `/// The three indexes:` and delete the `idx_tracker_entries_day` bullet.

In `packages/nimbus_data/lib/src/database/app_database.dart`:
1. Bump `schemaVersion` to `32`.
2. In the `if (from < 30)` block, delete `await m.create(idxTrackerEntriesDay);`.
3. In that block's comment, replace `this path already has v31's offset column and index` with `this path already has v31's offset column and index, and never had the day index v32 drops`.
4. After the `if (from < 30) {...} else if (from < 31) {...}` chain, add:

```dart
          // v31 -> v32: 4a's (local_date_key, tracker_id) index lost its one
          // reader, the DAO's day total, which 4b moved into the engine. Only
          // a database that reached v30 has it -- a table created later never
          // did. IF EXISTS keeps a re-run after an interrupted upgrade
          // harmless.
          if (from >= 30 && from < 32) {
            await customStatement(
                'DROP INDEX IF EXISTS idx_tracker_entries_day');
          }
```

- [ ] **Step 6: Generate code, the snapshot and the test schemas**

```bash
cd packages/nimbus_data
dart run build_runner build --delete-conflicting-outputs
grep -n "late final Index idxTracker" lib/src/database/app_database.g.dart
dart run drift_dev schema dump lib/src/database/app_database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated/
```

Expected:
- The `grep` prints four lines, with no `idxTrackerEntriesDay`.
- `drift_schemas/drift_schema_v32.json` and `test/generated/schema_v32.dart` exist.
- `test/generated/schema.dart` lists `const [1, 20, 21, 30, 31, 32]`.

- [ ] **Step 7: Run the tests to confirm GREEN**

Run: `cd packages/nimbus_data && dart test test/migration_test.dart test/database_test.dart`
Expected: PASS.

**Mutation check.**
1. Change the guard to `if (from >= 31 && from < 32)`.
2. Re-run. Expected: "a v30 database upgrades to v32" FAILS validation on the extra index.
3. Restore it.

- [ ] **Step 8: Update the registry**

`docs/phases/CONVENTIONS.md`, the registry row:
- old: `| 4 — Trackers | v30–v39 | **v30, v31** | trackers, tracker_entries; v31 adds tracker_entries.tz_offset_minutes |`
- new: `| 4 — Trackers | v30–v39 | **v30, v31, v32** | trackers, tracker_entries; v31 adds tracker_entries.tz_offset_minutes; v32 drops idx_tracker_entries_day |`

- [ ] **Step 9: Run the full gate**

Expected:
- `nimbus_data` is 240 + 3 = **243**: one new database test, one new upgrade path and the v31 test.
- The rest are unchanged.

- [ ] **Step 10: Commit and merge**

```bash
git add packages/nimbus_data docs/phases/CONVENTIONS.md
git commit -F - <<'EOF'
feat(schema): v32 -- the unread day index goes

4a's (local_date_key, tracker_id) index served one query, the DAO's
day total, which now lives in the engine. Kept, it would cost a
write on every tap and serve nothing. It is dropped by name, only
on databases that reached v30. IF EXISTS keeps a re-run after an
interrupted upgrade harmless.

It goes in its own version rather than in v31 because dropping it
there would have left the DAO's SUM scanning an index for the five
commits until Task 6 deleted it (measured; the operator chose this
on 2026-10-05).

Touches Phase 0's app_database.dart and database_test.dart, and the
registry.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch main
git merge --ff-only feat/schema-v32
git switch phase/4-trackers
git merge --ff-only main
```

---

### Task 8: Streaks, and how long since the last entry

Branch `feat/tracker-streaks`, slug `tracker-streaks`.

**Files:**
- Create: `packages/nimbus_domain/lib/src/trackers/tracker_streaks.dart`
- Modify: `packages/nimbus_domain/lib/src/trackers/tracker_queries.dart`, `packages/nimbus_domain/lib/nimbus_domain.dart`
- Create: `app/lib/features/trackers/presentation/widgets/tracker_streak_lines.dart`
- Modify: `app/lib/features/trackers/application/tracker_providers.dart`, `app/lib/features/trackers/application/tracker_format.dart`, `app/lib/features/trackers/presentation/tracker_detail_screen.dart`
- Modify: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_fa.arb`, and the generated `app/lib/l10n/app_localizations*.dart`
- Test: `packages/nimbus_domain/test/trackers/tracker_streaks_test.dart` (new), `packages/nimbus_domain/test/trackers/tracker_queries_test.dart`, `app/test/features/trackers/tracker_format_test.dart`, `app/test/features/trackers/tracker_streak_lines_test.dart` (new)
- Scratchpad (not the repo): `arb_add.py`, `keys_empty.json`, `keys_streaks.json`

**Interfaces:**
- Consumes: `trackerResultProvider` and `trackerTodayProvider` (Task 6).
- Produces:
  - `TrackerStreaks.of(Iterable<DateKey> loggedDays, {required DateKey today})`, with `int current`, `int longest` and `int? daysSinceLast`.
  - `TrackerQueries.loggedDays(String trackerId)`: undated, group by day, count.
  - `trackerStreaksProvider`: `Provider.autoDispose.family<AsyncValue<TrackerStreaks>, String>`.
  - `String TrackerFormat.digits(int value)`.
  - The widget `TrackerStreakLines(trackerId:)`, with keys `tracker-streak`, `tracker-last-entry` and `tracker-streak-error`.
  - The scratchpad helper `arb_add.py`, reused by Tasks 9–11.

- [ ] **Step 1: Write the ARB helper and prove it leaves the files alone**

Write the scratchpad file `arb_add.py` with the Write tool:

```python
"""Adds keys to app_en.arb and app_fa.arb -- or, with --update, changes
existing ones -- without disturbing anything else.

Usage: python arb_add.py <keys.json> [--update]
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


update = '--update' in sys.argv[2:]
new = json.load(open(sys.argv[1], encoding='utf-8'))
assert set(new) == {'en', 'fa'}, 'need exactly "en" and "fa"'
if not update:
    assert plain(new['en']) == plain(new['fa']), 'en and fa must add the same keys'

for lang in ('en', 'fa'):
    path = os.path.join(ROOT, 'app_' + lang + '.arb')
    data = json.loads(open(path, 'rb').read().decode('utf-8'))
    if update:
        missing = set(new[lang]) - set(data)
        assert not missing, 'not present, so not an update: %s' % sorted(missing)
    else:
        clash = set(new[lang]) & set(data)
        assert not clash, 'already present: %s' % sorted(clash)
    data.update(new[lang])
    out = {'@@locale': data.pop('@@locale')}
    for key in sorted(data, key=order):
        out[key] = data[key]
    text = json.dumps(out, ensure_ascii=False, indent=2) + '\n'
    open(path, 'wb').write(text.replace('\n', '\r\n').encode('utf-8'))
    print('wrote %s (%s%d entries)' % (path, '~' if update else '+', len(new[lang])))
```

Prove it is a no-op on today's files:
1. Write the scratchpad file `keys_empty.json` containing `{"en": {}, "fa": {}}`.
2. Run `python <scratchpad>/arb_add.py <scratchpad>/keys_empty.json`, then `git diff --stat app/lib/l10n/`.
3. Expected: **no diff**.
4. A diff means the files are not in the order `order()` assumes. Then stop: fix the helper to match the files' order, never reorder the files.

- [ ] **Step 2: Branch**

```bash
git switch phase/4-trackers
git switch -c feat/tracker-streaks
```

- [ ] **Step 3: Write the failing tests**

Create `packages/nimbus_domain/test/trackers/tracker_streaks_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  const today = DateKey(20261005);
  DateKey ago(int days) => today.addDays(-days);
  TrackerStreaks of(List<DateKey> days) =>
      TrackerStreaks.of(days, today: today);

  test('never logged: no streak and no last entry', () {
    expect(of([]), const TrackerStreaks(current: 0, longest: 0));
  });

  test('a run that includes today ends today', () {
    expect(of([ago(2), ago(1), today]),
        const TrackerStreaks(current: 3, longest: 3, daysSinceLast: 0));
  });

  test("today with nothing yet keeps yesterday's run alive", () {
    expect(of([ago(2), ago(1)]),
        const TrackerStreaks(current: 2, longest: 2, daysSinceLast: 1));
  });

  test('a missed day ends the run', () {
    expect(of([ago(4), ago(3), ago(1)]),
        const TrackerStreaks(current: 1, longest: 2, daysSinceLast: 1));
  });

  test('two days without an entry leave no current streak', () {
    expect(of([ago(3), ago(2)]),
        const TrackerStreaks(current: 0, longest: 2, daysSinceLast: 2));
  });

  test('the longest run can lie in the past', () {
    expect(of([ago(10), ago(9), ago(8), ago(7), ago(1), today]),
        const TrackerStreaks(current: 2, longest: 4, daysSinceLast: 0));
  });

  test('a single day long ago', () {
    expect(of([ago(5)]),
        const TrackerStreaks(current: 0, longest: 1, daysSinceLast: 5));
  });

  test('order and repeats in the input do not matter', () {
    expect(of([today, ago(1), today, ago(1)]),
        const TrackerStreaks(current: 2, longest: 2, daysSinceLast: 0));
  });

  test('days after today are ignored', () {
    // The entry sheet should not produce them, and a clock set back must not
    // become a streak.
    expect(of([today.addDays(1), today.addDays(2)]),
        const TrackerStreaks(current: 0, longest: 0));
    expect(of([ago(1), today.addDays(1)]),
        const TrackerStreaks(current: 1, longest: 1, daysSinceLast: 1));
  });

  test('a run across a month boundary is one run', () {
    expect(
        TrackerStreaks.of(const [
          DateKey(20260929),
          DateKey(20260930),
          DateKey(20261001),
        ], today: const DateKey(20261001)),
        const TrackerStreaks(current: 3, longest: 3, daysSinceLast: 0));
  });
}
```

Append to `packages/nimbus_domain/test/trackers/tracker_queries_test.dart`, inside `main`:

```dart
  test('the streaks ask for every day ever logged, undated', () {
    expect(
        TrackerQueries.loggedDays('cig'),
        TrackerQuerySpec(
            trackerIds: ['cig'],
            groupBy: const TrackerGroupByDay(),
            aggregate: Aggregate.count));
  });
```

Append to `app/test/features/trackers/tracker_format_test.dart`, inside `main`:

```dart
  test('a whole number has digits but no grouping', () {
    // number() would write the year 1405 as "1,405".
    expect(persian.digits(1405), '۱۴۰۵');
    expect(english.digits(1405), '1405');
  });
```

Create `app/test/features/trackers/tracker_streak_lines_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
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

  setUp(() {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    repo = repositoryFor(db, fake);
  });
  tearDown(() => db.close());

  Future<void> openDetail(WidgetTester tester, String id,
          {Locale locale = const Locale('en'),
          List<Override> overrides = const []}) =>
      pumpApp(tester,
          database: db,
          initialLocation: trackerLocation(id),
          locale: locale,
          overrides: [...trackerOverrides(fake), ...overrides]);

  /// One entry [daysAgo] days before the fake's now, on that local day.
  Future<void> logDaysAgo(Tracker tracker, int daysAgo) => repo.logEntry(
      tracker.id,
      at: fake.nowUtc.subtract(Duration(days: daysAgo)));

  /// The keyed Text's own string. The fixture's textIn looks for a Text below
  /// the key, and these keys sit on the Text itself.
  String line(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('a run that includes today', (tester) async {
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    for (final days in [2, 1, 0]) {
      await logDaysAgo(cig, days);
    }

    await openDetail(tester, cig.id);

    expect(line(tester, 'tracker-streak'), '3 days in a row · best 3');
    expect(line(tester, 'tracker-last-entry'), 'Last entry: today');
  });

  testWidgets('one day reads in the singular', (tester) async {
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);

    await openDetail(tester, cig.id);

    expect(line(tester, 'tracker-streak'), '1 day in a row · best 1');
  });

  testWidgets("today with nothing yet keeps yesterday's run", (tester) async {
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 2);
    await logDaysAgo(cig, 1);

    await openDetail(tester, cig.id);

    expect(line(tester, 'tracker-streak'), '2 days in a row · best 2');
    expect(line(tester, 'tracker-last-entry'), 'Last entry: yesterday');
  });

  testWidgets('a broken run leaves only the best', (tester) async {
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 6);
    await logDaysAgo(cig, 5);

    await openDetail(tester, cig.id);

    expect(line(tester, 'tracker-streak'), 'Best: 2 days');
    expect(line(tester, 'tracker-last-entry'), 'Last entry: 5 days ago');
  });

  testWidgets("a boolean's done days make its streak", (tester) async {
    await useEnglishDigits(db);
    final g = await repo.create(gym);
    await logDaysAgo(g, 1);
    await logDaysAgo(g, 0);

    await openDetail(tester, g.id);

    expect(line(tester, 'tracker-streak'), '2 days in a row · best 2');
  });

  testWidgets('a tracker never logged shows neither line', (tester) async {
    final cig = await repo.create(cigarettes);

    await openDetail(tester, cig.id);

    expect(find.byKey(const Key('tracker-streak')), findsNothing);
    expect(find.byKey(const Key('tracker-last-entry')), findsNothing);
  });

  testWidgets('a tap moves both lines', (tester) async {
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 1);
    await openDetail(tester, cig.id);
    expect(line(tester, 'tracker-last-entry'), 'Last entry: yesterday');

    await tester.tap(find.descendant(
        of: find.byKey(const Key('tracker-quick-log')),
        matching: find.byType(InkWell)));
    await tester.pumpAndSettle();

    expect(line(tester, 'tracker-streak'), '2 days in a row · best 2');
    expect(line(tester, 'tracker-last-entry'), 'Last entry: today');
  });

  testWidgets('left open across midnight, today becomes yesterday',
      (tester) async {
    // Review Focus 4.
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    await openDetail(tester, cig.id);
    expect(line(tester, 'tracker-last-entry'), 'Last entry: today');

    fake.advance(const Duration(days: 1));
    await backgroundAndResume(tester);
    await tester.pumpAndSettle();

    expect(line(tester, 'tracker-last-entry'), 'Last entry: yesterday');
    expect(line(tester, 'tracker-streak'), '1 day in a row · best 1');
  });

  testWidgets('Persian digits and words', (tester) async {
    final cig = await repo.create(cigarettes);
    for (final days in [2, 1, 0]) {
      await logDaysAgo(cig, days);
    }

    await openDetail(tester, cig.id, locale: const Locale('fa'));

    expect(line(tester, 'tracker-streak'), '۳ روز پشت سر هم · بهترین ۳');
    expect(line(tester, 'tracker-last-entry'), 'آخرین ثبت: امروز');
  });

  testWidgets('a failed streak says so, with a retry', (tester) async {
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);

    await openDetail(tester, cig.id, overrides: [
      trackerResultProvider(TrackerQueries.loggedDays(cig.id)).overrideWith(
          (ref) => Future<TrackerResult>.error(Exception('boom'))),
    ]);

    expect(find.byKey(const Key('tracker-streak-error')), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets('at twice the font size the header overflows nothing',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    for (final days in [2, 1, 0]) {
      await logDaysAgo(cig, days);
    }

    await openDetail(tester, cig.id);

    expect(tester.takeException(), isNull);
  });
}
```

Check `commonRetry`'s English value before relying on it:
- Run `grep -n '"commonRetry"' app/lib/l10n/app_en.arb`.
- If it is not `Retry`, use the value it prints in the last-but-one test.

- [ ] **Step 4: Run the tests to confirm RED**

Run: `cd packages/nimbus_domain && dart test test/trackers/`
Expected: FAIL to compile, naming `TrackerStreaks` and `loggedDays`.

Run: `cd app && flutter test --no-pub <absolute path>/app/test/features/trackers/tracker_format_test.dart <absolute path>/app/test/features/trackers/tracker_streak_lines_test.dart`
Expected: FAIL to compile, naming `digits` (and `TrackerQueries.loggedDays`).

- [ ] **Step 5: Tag the parent**

```bash
git tag pre-tracker-streaks
```

- [ ] **Step 6: Write `TrackerStreaks` and the query**

Create `packages/nimbus_domain/lib/src/trackers/tracker_streaks.dart`:

```dart
import 'package:meta/meta.dart';

import '../calendar/date_key.dart';

/// How a tracker's logged days run: the current streak, the longest, and how
/// long since the last entry.
@immutable
final class TrackerStreaks {
  const TrackerStreaks({
    required this.current,
    required this.longest,
    this.daysSinceLast,
  });

  /// Reads the streaks off the days in [loggedDays], as of [today].
  ///
  /// - A logged day has at least one live entry; for a boolean tracker, a
  ///   "done".
  /// - [current] is the run of consecutive logged days ending today, or
  ///   ending yesterday while today has nothing yet: a day is not missed until
  ///   it is over.
  /// - [longest] is the longest run anywhere, so never less than [current].
  /// - [daysSinceLast] is 0 when today is logged, and null when nothing ever
  ///   was.
  ///
  /// Days after [today] are ignored. The entry sheet should not produce them,
  /// and a clock set back must not turn into a streak. No calendar is needed:
  /// consecutive days are consecutive in every calendar.
  factory TrackerStreaks.of(Iterable<DateKey> loggedDays,
      {required DateKey today}) {
    final days =
        loggedDays.where((day) => day <= today).toSet().toList()..sort();
    if (days.isEmpty) return const TrackerStreaks(current: 0, longest: 0);

    var run = 1;
    var longest = 1;
    for (var i = 1; i < days.length; i++) {
      run = days[i - 1].addDays(1) == days[i] ? run + 1 : 1;
      if (run > longest) longest = run;
    }
    // `run` now holds the run that ends on the last logged day.
    final sinceLast = days.last.daysUntil(today);
    return TrackerStreaks(
      current: sinceLast <= 1 ? run : 0,
      longest: longest,
      daysSinceLast: sinceLast,
    );
  }

  final int current;
  final int longest;
  final int? daysSinceLast;

  @override
  bool operator ==(Object other) =>
      other is TrackerStreaks &&
      other.current == current &&
      other.longest == longest &&
      other.daysSinceLast == daysSinceLast;

  @override
  int get hashCode => Object.hash(current, longest, daysSinceLast);

  @override
  String toString() =>
      'TrackerStreaks(current $current, longest $longest, '
      'since last $daysSinceLast)';
}
```

In `packages/nimbus_domain/lib/src/trackers/tracker_queries.dart`, add inside the class:

```dart
  /// Every day [trackerId] was ever logged, one bucket each: the streaks'
  /// input. Undated on purpose, because the longest streak can be anywhere.
  static TrackerQuerySpec loggedDays(String trackerId) => TrackerQuerySpec(
        trackerIds: [trackerId],
        groupBy: const TrackerGroupByDay(),
        aggregate: Aggregate.count,
      );
```

In `packages/nimbus_domain/lib/nimbus_domain.dart`, add `export 'src/trackers/tracker_streaks.dart';` between `export 'src/trackers/tracker_results.dart';` and `export 'src/trackers/tracker_type.dart';`.

- [ ] **Step 7: Add the strings**

Write the scratchpad file `keys_streaks.json`:

```json
{
  "en": {
    "trackerLastEntryDaysAgo": "Last entry: {days} days ago",
    "@trackerLastEntryDaysAgo": {"placeholders": {"days": {"type": "String"}}},
    "trackerLastEntryToday": "Last entry: today",
    "trackerLastEntryYesterday": "Last entry: yesterday",
    "trackerStreakBestOnly": "{count, plural, =1{Best: {best} day} other{Best: {best} days}}",
    "@trackerStreakBestOnly": {"placeholders": {"count": {"type": "int"}, "best": {"type": "String"}}},
    "trackerStreakErrorTitle": "Could not load the streak",
    "trackerStreakLine": "{count, plural, =1{{days} day in a row · best {best}} other{{days} days in a row · best {best}}}",
    "@trackerStreakLine": {"placeholders": {"count": {"type": "int"}, "days": {"type": "String"}, "best": {"type": "String"}}}
  },
  "fa": {
    "trackerLastEntryDaysAgo": "آخرین ثبت: {days} روز پیش",
    "trackerLastEntryToday": "آخرین ثبت: امروز",
    "trackerLastEntryYesterday": "آخرین ثبت: دیروز",
    "trackerStreakBestOnly": "{count, plural, other{بهترین: {best} روز}}",
    "trackerStreakErrorTitle": "پیوستگی بارگیری نشد",
    "trackerStreakLine": "{count, plural, other{{days} روز پشت سر هم · بهترین {best}}}"
  }
}
```

`count` only selects the plural branch and is never printed. The days themselves arrive formatted, as `days` and `best` (Global Constraints, Strings).

Run:

```bash
python <scratchpad>/arb_add.py <scratchpad>/keys_streaks.json
cd app && flutter gen-l10n
```

Expected:
- two `wrote … (+n entries)` lines;
- `gen-l10n` reports no errors;
- `AppLocalizations` gains `trackerStreakLine(int count, String days, String best)` and `trackerStreakBestOnly(int count, String best)`.

- [ ] **Step 8: Format, provide, and show the lines**

In `app/lib/features/trackers/application/tracker_format.dart`, after `number`, add:

```dart
  /// A whole number in the settings' digits, without grouping: a day count, a
  /// day of the month, an hour, a year. [number] would write 1405 as `1,405`.
  String digits(int value) => _digits('$value');
```

In `app/lib/features/trackers/application/tracker_providers.dart`, append:

```dart
/// A tracker's streaks as of today, read from every day it was ever logged.
///
/// Synchronous over [trackerResultProvider], like [trackerTotalsProvider], and
/// it re-derives on the day rolling over as well as on a write.
final trackerStreaksProvider =
    Provider.autoDispose.family<AsyncValue<TrackerStreaks>, String>((ref, id) {
  final today = ref.watch(trackerTodayProvider);
  return ref
      .watch(trackerResultProvider(TrackerQueries.loggedDays(id)))
      .whenData((result) => TrackerStreaks.of([
            for (final bucket in result.buckets)
              if (bucket.key case PeriodKey(:final range)) range.startInclusive,
          ], today: today));
});
```

Create `app/lib/features/trackers/presentation/widgets/tracker_streak_lines.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../application/tracker_providers.dart';

/// The detail header's two quieter lines: the streak, and how long since the
/// last entry.
///
/// Nothing at all for a tracker never logged, because the History tab's empty
/// state already says what to do. Nothing while the first answer loads, so
/// the header does not jump on open; a refresh keeps the previous lines.
class TrackerStreakLines extends ConsumerWidget {
  const TrackerStreakLines({super.key, required this.trackerId});

  final String trackerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final streaks = ref.watch(trackerStreaksProvider(trackerId));

    if (streaks.hasError) {
      return Row(
        children: [
          Expanded(
            child: Text(l10n.trackerStreakErrorTitle,
                key: const Key('tracker-streak-error'), style: style),
          ),
          TextButton(
            // The whole family: the streak's question is asked again.
            onPressed: () => ref.invalidate(trackerResultProvider),
            child: Text(l10n.commonRetry),
          ),
        ],
      );
    }
    if (!streaks.hasValue) return const SizedBox.shrink();
    final value = streaks.requireValue;
    final since = value.daysSinceLast;
    if (since == null) return const SizedBox.shrink();

    final format = ref.watch(trackerFormatProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value.current > 0
              ? l10n.trackerStreakLine(value.current,
                  format.digits(value.current), format.digits(value.longest))
              : l10n.trackerStreakBestOnly(
                  value.longest, format.digits(value.longest)),
          key: const Key('tracker-streak'),
          style: style,
        ),
        Text(
          switch (since) {
            0 => l10n.trackerLastEntryToday,
            1 => l10n.trackerLastEntryYesterday,
            _ => l10n.trackerLastEntryDaysAgo(format.digits(since)),
          },
          key: const Key('tracker-last-entry'),
          style: style,
        ),
      ],
    );
  }
}
```

In `app/lib/features/trackers/presentation/tracker_detail_screen.dart`:
1. Import `widgets/tracker_streak_lines.dart`.
2. In `_Header.build`, replace the `Expanded(child: TrackerTodayText(...))` child with:

```dart
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TrackerTodayText(
                  key: const Key('tracker-detail-total'),
                  tracker: tracker,
                  total: total,
                  style: theme.textTheme.headlineSmall,
                ),
                TrackerStreakLines(trackerId: tracker.id),
              ],
            ),
          ),
```

- [ ] **Step 9: Run the tests to confirm GREEN**

Run the two commands from Step 4, then `cd app && flutter test --no-pub <absolute path>/app/test/features/trackers/` and `cd app && flutter test --no-pub <absolute path>/app/test/localization_test.dart`.
Expected: PASS.

**Mutation check.**
1. In `TrackerStreaks.of`, change `sinceLast <= 1` to `sinceLast == 0`.
2. Re-run. Expected: "today with nothing yet keeps yesterday's run alive" FAILS, in the domain and in the widget test.
3. Restore it.

- [ ] **Step 10: Run the full gate**

Expected:
- `nimbus_domain` is 313 + 11 = **324**;
- `app` is 461 + 12 = **473**;
- the rest are unchanged.

- [ ] **Step 11: Commit and merge**

```bash
git add packages/nimbus_domain app/lib/features/trackers app/lib/l10n app/test/features/trackers
git commit -F - <<'EOF'
feat(trackers): streaks, and how long since the last entry

The detail header now says how a habit is going: "6 days in a row ·
best 14", or just the best when the run has broken, and "Last entry:
3 days ago". The second line is what serves a habit being quit. A
cigarettes tracker's streak counts days smoked; days since the last
one counts days clean. Limits stay with Phase 5's goals.

Streaks come from one engine query, every day the tracker was ever
logged, read by a pure TrackerStreaks. Today with nothing yet keeps
yesterday's run alive, since a day is not missed until it is over.
Days after today are ignored, so a clock set back cannot invent a
streak.

The plurals take an int that only selects the branch. The numbers
themselves arrive formatted, so their digits follow the settings
like every other tracker number.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/4-trackers
git merge --ff-only feat/tracker-streaks
```

---

### Task 9: The Insights tab and its history chart

Branch `feat/tracker-insights`, slug `tracker-insights`.

**Files:**
- Modify: `packages/nimbus_domain/lib/src/trackers/tracker_queries.dart`
- Create:
  - `app/lib/features/trackers/application/tracker_insights_controller.dart`
  - `app/lib/features/trackers/application/tracker_insights_data.dart`
  - `app/lib/features/trackers/presentation/widgets/tracker_bar_chart.dart`
  - `app/lib/features/trackers/presentation/widgets/tracker_range_bar.dart`
  - `app/lib/features/trackers/presentation/widgets/tracker_chart_section.dart`
  - `app/lib/features/trackers/presentation/widgets/tracker_insights.dart`
- Modify: `app/lib/features/trackers/application/tracker_format.dart`, `app/lib/features/trackers/presentation/tracker_detail_screen.dart`, the ARBs and the generated localizations
- Test: `packages/nimbus_domain/test/trackers/tracker_queries_test.dart`, `app/test/features/trackers/tracker_format_test.dart`, `app/test/features/trackers/tracker_insights_data_test.dart` (new), `app/test/features/trackers/tracker_insights_test.dart` (new)

**Interfaces:**
- Consumes:
  - `trackerResultProvider`, `trackerTodayProvider` and `trackerStreaksProvider` (Tasks 6, 8);
  - `calendarProvider` and `firstDayOfWeekProvider` (settings);
  - `PeriodBoundaries.series` (Phase 3).
- Produces:
  - `TrackerQueries.byDay(String id, DateRange range)` and `TrackerQueries.byMonth(String id, DateRange range)`.
  - `enum TrackerRangeKind { week, month, year }`, each with a `PeriodType period`.
  - `TrackerInsightsView({kind, range})`, and `trackerInsightsProvider` (`NotifierProvider.autoDispose`) with `select(TrackerRangeKind)` and `shift(int)`.
  - In `tracker_insights_data.dart`: `TrackerBar(DateRange period, double value)`, `historyBars(view, result, calendar)`, `elapsedDays(range, today)`, `peakIndex(values)` and `rangeLabel(view, format)`.
  - `TrackerFormat.month(DateKey)`, `TrackerFormat.year(DateKey)` and `TrackerFormat.axis(Tracker, double)`.
  - `TrackerBarChart({values, color, labelOf, axisLabelOf, semanticsLabel, labelEvery, labelKeyPrefix, height})`.
  - `TrackerChartSection({sectionKey, title, spec, builder})`, which keys its states `tracker-<sectionKey>-loading|error|empty`.
  - `TrackerInsights(tracker:)`.
  - The detail tabs are keyed `tracker-tab-history` and `tracker-tab-insights`.

- [ ] **Step 1: Branch**

```bash
git switch phase/4-trackers
git switch -c feat/tracker-insights
```

- [ ] **Step 2: Write the failing tests**

Append to `packages/nimbus_domain/test/trackers/tracker_queries_test.dart`, inside `main`:

```dart
  test('the week and month charts ask for one bucket per day', () {
    expect(
        TrackerQueries.byDay('cig', oneDay),
        TrackerQuerySpec(
            trackerIds: ['cig'],
            dateRange: oneDay,
            groupBy: const TrackerGroupByDay(),
            aggregate: Aggregate.sum));
  });

  test('the year chart asks for one bucket per calendar month', () {
    expect(
        TrackerQueries.byMonth('cig', oneDay),
        TrackerQuerySpec(
            trackerIds: ['cig'],
            dateRange: oneDay,
            groupBy: TrackerGroupByPeriod(PeriodType.month),
            aggregate: Aggregate.sum));
  });
```

Append to `app/test/features/trackers/tracker_format_test.dart`, inside `main`:

```dart
  test('a month and a year in the active calendar', () {
    expect(english.month(const DateKey(20261005)), '2026/10');
    expect(persian.year(const DateKey(20261005)), '۲۰۲۶');
  });

  test('the value axis shows a duration as h:mm', () {
    expect(english.axis(tracker(TrackerType.duration), 5400), '1:30');
  });

  test('the value axis shows a bare number, without a unit', () {
    expect(english.axis(tracker(TrackerType.quantity, unit: 'L'), 2.5), '2.5');
  });
```

Create `app/test/features/trackers/tracker_insights_data_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/application/tracker_format.dart';
import 'package:nimbustats/features/trackers/application/tracker_insights_controller.dart';
import 'package:nimbustats/features/trackers/application/tracker_insights_data.dart';

void main() {
  const gregorian = GregorianCalendar();
  const today = DateKey(20261005);
  const october = DateRange(DateKey(20261001), DateKey(20261031));
  final english = TrackerFormat(
      localeTag: 'en', persianDigits: false, calendar: gregorian);

  TrackerResult answer(Map<DateRange, double> values) => TrackerResult(
        buckets: [
          for (final MapEntry(key: range, value: value) in values.entries)
            TrackerBucket(key: PeriodKey(range), value: value, count: 1),
        ],
        sum: values.values.fold<double>(0, (a, b) => a + b),
        count: values.length,
      );

  test('a month draws every day, quiet ones at zero', () {
    final bars = historyBars(
      const TrackerInsightsView(kind: TrackerRangeKind.month, range: october),
      answer({
        const DateRange(DateKey(20261003), DateKey(20261003)): 0.5,
        const DateRange(DateKey(20261005), DateKey(20261005)): 0.75,
      }),
      gregorian,
    );
    expect(bars, hasLength(31));
    expect(bars[2], const TrackerBar(DateRange(DateKey(20261003), DateKey(20261003)), 0.5));
    expect(bars[4].value, 0.75);
    expect(bars.where((bar) => bar.value == 0), hasLength(29));
  });

  test('a week draws seven days', () {
    const week = DateRange(DateKey(20261003), DateKey(20261009));
    final bars = historyBars(
        const TrackerInsightsView(kind: TrackerRangeKind.week, range: week),
        answer({}),
        gregorian);
    expect(bars, hasLength(7));
  });

  test("a year draws its calendar's twelve months", () {
    const year = DateRange(DateKey(20260101), DateKey(20261231));
    final bars = historyBars(
      const TrackerInsightsView(kind: TrackerRangeKind.year, range: year),
      answer({october: 12}),
      gregorian,
    );
    expect(bars, hasLength(12));
    expect(bars[9], const TrackerBar(october, 12));
  });

  test('a Jalali year draws Jalali months', () {
    const jalali = JalaliCalendar();
    final year = jalali.periodContaining(today, PeriodType.year);
    final bars = historyBars(
        TrackerInsightsView(kind: TrackerRangeKind.year, range: year),
        answer({}),
        jalali);
    expect(bars, hasLength(12));
    expect(bars.first.period,
        jalali.periodContaining(year.startInclusive, PeriodType.month));
  });

  test('a per-day average divides only by the days already begun', () {
    expect(elapsedDays(october, today), 5);
    expect(
        elapsedDays(
            const DateRange(DateKey(20260901), DateKey(20260930)), today),
        30);
    expect(
        elapsedDays(
            const DateRange(DateKey(20261101), DateKey(20261130)), today),
        0);
  });

  test('the peak is the highest bar, the earliest on a tie', () {
    expect(peakIndex([0, 3, 1, 3]), 1);
    expect(peakIndex([0, 0]), 0);
  });

  test('the range is named by its kind', () {
    expect(
        rangeLabel(
            const TrackerInsightsView(
                kind: TrackerRangeKind.week,
                range: DateRange(DateKey(20261003), DateKey(20261009))),
            english),
        '2026/10/03 – 2026/10/09');
    expect(
        rangeLabel(
            const TrackerInsightsView(
                kind: TrackerRangeKind.month, range: october),
            english),
        '2026/10');
    expect(
        rangeLabel(
            const TrackerInsightsView(
                kind: TrackerRangeKind.year,
                range: DateRange(DateKey(20260101), DateKey(20261231))),
            english),
        '2026');
  });

  test('the range name follows the digits setting', () {
    final persian = TrackerFormat(
        localeTag: 'fa', persianDigits: true, calendar: gregorian);
    expect(
        rangeLabel(
            const TrackerInsightsView(
                kind: TrackerRangeKind.month, range: october),
            persian),
        '۲۰۲۶/۱۰');
  });
}
```

Create `app/test/features/trackers/tracker_insights_test.dart`:

```dart
import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';
import 'package:nimbustats/features/trackers/application/tracker_insights_controller.dart';
import 'package:nimbustats/features/trackers/application/tracker_providers.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import 'support/tracker_fixture.dart';

void main() {
  late FakeClock fake;
  late AppDatabase db;
  late TrackerRepository repo;

  const october = DateRange(DateKey(20261001), DateKey(20261031));

  setUp(() {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    repo = repositoryFor(db, fake);
  });
  tearDown(() => db.close());

  /// English digits and the Gregorian calendar: October 2026 is the month on
  /// screen, with concrete numbers to assert.
  Future<void> useGregorianEnglish({int? firstDayOfWeek}) =>
      SettingsRepository(db.settingsDao).save(AppSettings.defaults.copyWith(
          locale: const Locale('en'),
          calendarKind: CalendarKind.gregorian,
          firstDayOfWeek:
              firstDayOfWeek ?? AppSettings.defaults.firstDayOfWeek));

  Future<void> openInsights(WidgetTester tester, String id,
      {Locale locale = const Locale('en'),
      List<Override> overrides = const []}) async {
    await pumpApp(tester,
        database: db,
        initialLocation: trackerLocation(id),
        locale: locale,
        overrides: [...trackerOverrides(fake), ...overrides]);
    await tester.tap(find.byKey(const Key('tracker-tab-insights')));
    await tester.pumpAndSettle();
  }

  Future<void> logDaysAgo(Tracker tracker, int daysAgo, {double? value}) =>
      repo.logEntry(tracker.id,
          value: value, at: fake.nowUtc.subtract(Duration(days: daysAgo)));

  List<double> barsOf(WidgetTester tester, String key) => [
        for (final group in tester
            .widget<BarChart>(find.descendant(
                of: find.byKey(Key(key)), matching: find.byType(BarChart)))
            .data
            .barGroups)
          group.barRods.single.toY,
      ];

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('Insights opens on this month, with the quick log kept',
      (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);

    await openInsights(tester, cig.id);

    expect(textOf(tester, 'tracker-range-label'), '2026/10');
    expect(find.byKey(const Key('tracker-quick-log')), findsOneWidget);
  });

  testWidgets('a month draws a bar a day and says the total and the average',
      (tester) async {
    await useGregorianEnglish();
    final w = await repo.create(water);
    for (var i = 0; i < 3; i++) {
      await logDaysAgo(w, 0);
    }
    await logDaysAgo(w, 2, value: 0.5);

    await openInsights(tester, w.id);

    final bars = barsOf(tester, 'tracker-history-chart');
    expect(bars, hasLength(31));
    expect(bars[2], 0.5);
    expect(bars[4], 0.75);
    // 1.25 L over the five days of October begun so far.
    expect(textOf(tester, 'tracker-history-caption'),
        '1.25 L in all · 0.25 L a day');
  });

  testWidgets('a boolean says on how many days it was done', (tester) async {
    await useGregorianEnglish();
    final g = await repo.create(gym);
    await logDaysAgo(g, 0);
    await logDaysAgo(g, 2);

    await openInsights(tester, g.id);

    expect(textOf(tester, 'tracker-history-caption'), 'Done on 2 of 5 days');
  });

  testWidgets('a week draws seven days and a year twelve months',
      (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    await openInsights(tester, cig.id);

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    // Saturday-first, so Monday the 5th is the third bar.
    expect(textOf(tester, 'tracker-range-label'), '2026/10/03 – 2026/10/09');
    expect(barsOf(tester, 'tracker-history-chart'),
        [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0]);

    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'tracker-range-label'), '2026');
    final months = barsOf(tester, 'tracker-history-chart');
    expect(months, hasLength(12));
    expect(months[9], 1);
  });

  testWidgets('earlier and later move the range, never past today',
      (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    await openInsights(tester, cig.id);

    IconButton next() =>
        tester.widget<IconButton>(find.byKey(const Key('tracker-range-next')));
    expect(next().onPressed, isNull);

    await tester.tap(find.byKey(const Key('tracker-range-previous')));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'tracker-range-label'), '2026/09');
    expect(next().onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('tracker-range-next')));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'tracker-range-label'), '2026/10');
  });

  testWidgets('a range with nothing in it says so', (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    await openInsights(tester, cig.id);

    await tester.tap(find.byKey(const Key('tracker-range-previous')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tracker-history-empty')), findsOneWidget);
  });

  testWidgets('a tracker never logged shows one empty state', (tester) async {
    final cig = await repo.create(cigarettes);

    await openInsights(tester, cig.id);

    expect(find.byKey(const Key('tracker-insights-empty')), findsOneWidget);
    expect(find.byKey(const Key('tracker-history-chart')), findsNothing);
  });

  testWidgets('the chart loads on its own', (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    final never = Completer<TrackerResult>();

    await openInsights(tester, cig.id, overrides: [
      trackerResultProvider(TrackerQueries.byDay(cig.id, october))
          .overrideWith((ref) => never.future),
    ]);

    expect(find.byKey(const Key('tracker-history-loading')), findsOneWidget);
    expect(find.byKey(const Key('tracker-range-label')), findsOneWidget);
  });

  testWidgets('a failed chart retries and hides the raw exception',
      (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);

    await openInsights(tester, cig.id, overrides: [
      trackerResultProvider(TrackerQueries.byDay(cig.id, october)).overrideWith(
          (ref) => Future<TrackerResult>.error(Exception('boom'))),
    ]);

    expect(
        find.descendant(
            of: find.byKey(const Key('tracker-history-error')),
            matching: find.byType(NimbusErrorState)),
        findsOneWidget);
    expect(find.text('Exception: boom'), findsNothing);
  });

  testWidgets('the chart speaks its numbers', (tester) async {
    final semantics = tester.ensureSemantics();
    await useGregorianEnglish();
    final w = await repo.create(water);
    for (var i = 0; i < 3; i++) {
      await logDaysAgo(w, 0);
    }
    await logDaysAgo(w, 2, value: 0.5);

    await openInsights(tester, w.id);

    expect(
        find.bySemanticsLabel(
            'Water, 2026/10: 1.25 L in all; most on 2026/10/05, 0.75 L'),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets('switching the calendar re-anchors the range', (tester) async {
    // Review Focus 5.
    await useEnglishDigits(db);
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    await openInsights(tester, cig.id);
    expect(textOf(tester, 'tracker-range-label'), '1405/07');

    await tester.runAsync(useGregorianEnglish);
    await tester.pumpAndSettle();

    expect(textOf(tester, 'tracker-range-label'), '2026/10');
    expect(barsOf(tester, 'tracker-history-chart'), hasLength(31));
  });

  testWidgets('Persian digits on the range', (tester) async {
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);

    await openInsights(tester, cig.id, locale: const Locale('fa'));

    expect(textOf(tester, 'tracker-range-label'), '۱۴۰۵/۰۷');
  });

  testWidgets('at twice the font size Insights overflows nothing',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await useGregorianEnglish();
    final w = await repo.create(water);
    await logDaysAgo(w, 0, value: 1234.5);

    await openInsights(tester, w.id);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the range controls are full-size tap targets', (tester) async {
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);
    await openInsights(tester, cig.id);

    for (final finder in [
      find.byKey(const Key('tracker-range-previous')),
      find.byKey(const Key('tracker-range-next')),
      find.byType(SegmentedButton<TrackerRangeKind>),
    ]) {
      expect(tester.getSize(finder).height,
          greaterThanOrEqualTo(NimbusTokens.minTapTarget),
          reason: '$finder');
    }
  });
}
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_domain && dart test test/trackers/tracker_queries_test.dart`
Expected: FAIL to compile, naming `byDay` and `byMonth`.

Run: `cd app && flutter test --no-pub <absolute path>/app/test/features/trackers/tracker_format_test.dart <absolute path>/app/test/features/trackers/tracker_insights_data_test.dart <absolute path>/app/test/features/trackers/tracker_insights_test.dart`
Expected: FAIL to compile, naming `month`, `axis`, `tracker_insights_controller.dart` and `tracker_insights_data.dart`.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-tracker-insights
```

- [ ] **Step 5: Add the queries and the formats**

In `packages/nimbus_domain/lib/src/trackers/tracker_queries.dart`:
1. Add `import '../calendar/calendar.dart';`.
2. Add inside the class:

```dart
  /// One bucket per day of [range] that has entries: the week and month
  /// charts.
  static TrackerQuerySpec byDay(String trackerId, DateRange range) =>
      TrackerQuerySpec(
        trackerIds: [trackerId],
        dateRange: range,
        groupBy: const TrackerGroupByDay(),
        aggregate: Aggregate.sum,
      );

  /// One bucket per calendar month of [range] that has entries: the year
  /// chart. Months come from the engine's calendar, so a Jalali year shows
  /// Jalali months.
  static TrackerQuerySpec byMonth(String trackerId, DateRange range) =>
      TrackerQuerySpec(
        trackerIds: [trackerId],
        dateRange: range,
        groupBy: TrackerGroupByPeriod(PeriodType.month),
        aggregate: Aggregate.sum,
      );
```

In `app/lib/features/trackers/application/tracker_format.dart`, after `date`, add:

```dart
  /// A month in the active calendar, as Phase 3's period labels write one:
  /// `1405/07`.
  String month(DateKey day) {
    final parts = calendar.partsOf(day);
    return _digits('${parts.year}/${_two(parts.month)}');
  }

  /// A year in the active calendar: `1405`.
  String year(DateKey day) => _digits('${calendar.partsOf(day).year}');

  /// A chart's value axis: the bare number, or h:mm for a duration. There is
  /// no unit, which the axis has no room for and the caption already says.
  String axis(Tracker tracker, double value) =>
      tracker.type == TrackerType.duration
          ? duration(TrackerValues.durationOf(value))
          : number(value);
```

- [ ] **Step 6: Write the range controller and the bar data**

Create `app/lib/features/trackers/application/tracker_insights_controller.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';
import 'tracker_providers.dart';

/// How much history the Insights tab shows at once.
enum TrackerRangeKind {
  week(PeriodType.week),
  month(PeriodType.month),
  year(PeriodType.year);

  const TrackerRangeKind(this.period);

  /// The calendar period one range of this kind covers.
  final PeriodType period;
}

/// What the Insights tab is showing: one week, month or year of the active
/// calendar.
@immutable
final class TrackerInsightsView {
  const TrackerInsightsView({required this.kind, required this.range});

  final TrackerRangeKind kind;
  final DateRange range;

  @override
  bool operator ==(Object other) =>
      other is TrackerInsightsView && other.kind == kind && other.range == range;

  @override
  int get hashCode => Object.hash(kind, range);

  @override
  String toString() => 'TrackerInsightsView(${kind.name}, $range)';
}

/// The Insights tab's range.
///
/// The history chart and both patterns read this one range, because they are
/// three views of one question -- when this tracker's entries happened -- and
/// three controls would be three ways to get them out of step.
class TrackerInsightsController extends Notifier<TrackerInsightsView> {
  @override
  TrackerInsightsView build() {
    // Watched, so switching calendars or the week's first day re-anchors the
    // range: a Jalali month is not a Gregorian one.
    ref
      ..watch(calendarProvider)
      ..watch(firstDayOfWeekProvider);
    return _current(TrackerRangeKind.month);
  }

  /// Shows the range of [kind] that holds today.
  void select(TrackerRangeKind kind) => state = _current(kind);

  /// Moves the range by [delta] ranges of its kind, never past the one holding
  /// today: there is nothing to chart there.
  void shift(int delta) {
    final next = ref
        .read(calendarProvider)
        .shiftPeriod(state.range, state.kind.period, delta);
    if (next.startInclusive > ref.read(trackerTodayProvider)) return;
    state = TrackerInsightsView(kind: state.kind, range: next);
  }

  TrackerInsightsView _current(TrackerRangeKind kind) => TrackerInsightsView(
        kind: kind,
        range: ref.read(calendarProvider).periodContaining(
              ref.read(trackerTodayProvider),
              kind.period,
              firstDayOfWeek: ref.read(firstDayOfWeekProvider),
            ),
      );
}

/// Auto-disposed: the Insights tab keeps itself alive while its screen is up,
/// so the range lasts as long as the screen does and no longer.
final trackerInsightsProvider =
    NotifierProvider.autoDispose<TrackerInsightsController, TrackerInsightsView>(
        TrackerInsightsController.new);
```

Create `app/lib/features/trackers/application/tracker_insights_data.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import 'tracker_format.dart';
import 'tracker_insights_controller.dart';

/// One bar of the history chart: a day, or a month in the year view.
@immutable
final class TrackerBar {
  const TrackerBar(this.period, this.value);

  final DateRange period;
  final double value;

  @override
  bool operator ==(Object other) =>
      other is TrackerBar && other.period == period && other.value == value;

  @override
  int get hashCode => Object.hash(period, value);

  @override
  String toString() => 'TrackerBar($period, $value)';
}

/// Every bar the history chart draws for [view], quiet ones included.
///
/// The engine answers only the days or months that have entries. Plotting
/// those alone would put a sparse month's bars side by side and read as a
/// habit kept every day.
List<TrackerBar> historyBars(
    TrackerInsightsView view, TrackerResult result, AppCalendar calendar) {
  final byStart = <DateKey, double>{
    for (final bucket in result.buckets)
      if (bucket.key case PeriodKey(:final range))
        range.startInclusive: bucket.value,
  };
  final periods = view.kind == TrackerRangeKind.year
      ? PeriodBoundaries.series(PeriodType.month, view.range, calendar)
      : [
          for (var day = view.range.startInclusive;
              day <= view.range.endInclusive;
              day = day.addDays(1))
            DateRange(day, day),
        ];
  return [
    for (final period in periods)
      TrackerBar(period, byStart[period.startInclusive] ?? 0),
  ];
}

/// How many days of [range] have begun by [today]: what a per-day average
/// divides by, so the days still ahead do not dilute it.
int elapsedDays(DateRange range, DateKey today) {
  if (today < range.startInclusive) return 0;
  final end = today < range.endInclusive ? today : range.endInclusive;
  return range.startInclusive.daysUntil(end) + 1;
}

/// The index of the highest bar, the earliest one on a tie.
int peakIndex(List<double> values) {
  var peak = 0;
  for (var i = 1; i < values.length; i++) {
    if (values[i] > values[peak]) peak = i;
  }
  return peak;
}

/// The range as the range bar and the spoken summaries name it:
/// `1405/07/11 – 1405/07/17` for a week, `1405/07` for a month, `1405` for a
/// year. Numeric, as Phase 3's period labels are.
String rangeLabel(TrackerInsightsView view, TrackerFormat format) =>
    switch (view.kind) {
      TrackerRangeKind.week => '${format.date(view.range.startInclusive)} – '
          '${format.date(view.range.endInclusive)}',
      TrackerRangeKind.month => format.month(view.range.startInclusive),
      TrackerRangeKind.year => format.year(view.range.startInclusive),
    };
```

- [ ] **Step 7: Add the strings**

Write the scratchpad file `keys_insights.json`:

```json
{
  "en": {
    "trackerInsightsByDay": "By day",
    "trackerInsightsByMonth": "By month",
    "trackerInsightsDoneCaption": "Done on {done} of {days} days",
    "@trackerInsightsDoneCaption": {"placeholders": {"done": {"type": "String"}, "days": {"type": "String"}}},
    "trackerInsightsEmptyMessage": "Log a few entries and your patterns show up here.",
    "trackerInsightsEmptyTitle": "No insights yet",
    "trackerInsightsErrorTitle": "Could not load this chart",
    "trackerInsightsHistorySummary": "{name}, {period}: {total} in all; most on {peak}, {peakValue}",
    "@trackerInsightsHistorySummary": {"placeholders": {"name": {"type": "String"}, "period": {"type": "String"}, "total": {"type": "String"}, "peak": {"type": "String"}, "peakValue": {"type": "String"}}},
    "trackerInsightsNothingLogged": "Nothing logged in this period",
    "trackerInsightsTotalCaption": "{total} in all · {average} a day",
    "@trackerInsightsTotalCaption": {"placeholders": {"total": {"type": "String"}, "average": {"type": "String"}}},
    "trackerRangeMonth": "Month",
    "trackerRangeNext": "Later",
    "trackerRangePrevious": "Earlier",
    "trackerRangeWeek": "Week",
    "trackerRangeYear": "Year",
    "trackerTabHistory": "History",
    "trackerTabInsights": "Insights"
  },
  "fa": {
    "trackerInsightsByDay": "روزانه",
    "trackerInsightsByMonth": "ماهانه",
    "trackerInsightsDoneCaption": "{done} روز از {days} روز انجام شد",
    "trackerInsightsEmptyMessage": "چند بار ثبت کنید تا الگوهایتان اینجا دیده شود.",
    "trackerInsightsEmptyTitle": "هنوز تحلیلی نیست",
    "trackerInsightsErrorTitle": "این نمودار بارگیری نشد",
    "trackerInsightsHistorySummary": "{name}، {period}: در کل {total}؛ بیشترین در {peak}، {peakValue}",
    "trackerInsightsNothingLogged": "در این بازه چیزی ثبت نشده",
    "trackerInsightsTotalCaption": "{total} در کل · {average} در روز",
    "trackerRangeMonth": "ماه",
    "trackerRangeNext": "بعدی",
    "trackerRangePrevious": "قبلی",
    "trackerRangeWeek": "هفته",
    "trackerRangeYear": "سال",
    "trackerTabHistory": "تاریخچه",
    "trackerTabInsights": "تحلیل"
  }
}
```

Run:

```bash
python <scratchpad>/arb_add.py <scratchpad>/keys_insights.json
cd app && flutter gen-l10n
```

Expected: two `wrote … (+n entries)` lines, and `gen-l10n` reports no errors.

- [ ] **Step 8: Write the chart, the range bar and the section**

Create `app/lib/features/trackers/presentation/widgets/tracker_bar_chart.dart`:

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// One tracker's bars, in its own colour, with a spoken summary.
///
/// The bars say nothing a screen reader can use, so the chart is one semantics
/// node carrying [semanticsLabel], and the bars beneath it are excluded.
/// Touch tooltips are off: fl_chart's default tooltip prints the raw double
/// (an hour reads `3600.0`), and the caption and the summary carry the numbers.
/// Time runs left to right in both scripts, as Phase 3's charts do.
class TrackerBarChart extends StatelessWidget {
  const TrackerBarChart({
    super.key,
    required this.values,
    required this.color,
    required this.labelOf,
    required this.axisLabelOf,
    required this.semanticsLabel,
    this.labelEvery = 1,
    this.labelKeyPrefix,
    this.height = 180,
  });

  final List<double> values;
  final Color color;

  /// The label under bar [index], already in the settings' digits.
  final String Function(int index) labelOf;

  /// A value-axis label for [value], already formatted.
  final String Function(double value) axisLabelOf;
  final String semanticsLabel;

  /// Label every n-th bar only. Thirty labels do not fit under a month.
  final int labelEvery;

  /// When set, each label is keyed `<prefix>-<index>` for tests.
  final String? labelKeyPrefix;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: BarChart(
          BarChartData(
            barGroups: [
              for (final (x, value) in values.indexed)
                BarChartGroupData(x: x, barRods: [
                  BarChartRodData(
                    toY: value,
                    color: color,
                    width: values.length > 12 ? 4 : 10,
                  ),
                ]),
            ],
            gridData: FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(enabled: false),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  getTitlesWidget: (value, meta) => Text(
                    axisLabelOf(value),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final index = value.round();
                    if (index % labelEvery != 0) return const SizedBox.shrink();
                    final prefix = labelKeyPrefix;
                    return Text(
                      labelOf(index),
                      key: prefix == null ? null : Key('$prefix-$index'),
                      style: theme.textTheme.labelSmall,
                    );
                  },
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

Create `app/lib/features/trackers/presentation/widgets/tracker_range_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_format.dart';
import '../../application/tracker_insights_controller.dart';
import '../../application/tracker_insights_data.dart';
import '../../application/tracker_providers.dart';

/// Week, month or year, and which one: the Insights tab's single control.
class TrackerRangeBar extends ConsumerWidget {
  const TrackerRangeBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(trackerInsightsProvider);
    final controller = ref.read(trackerInsightsProvider.notifier);
    final today = ref.watch(trackerTodayProvider);
    final format = ref.watch(trackerFormatProvider);
    // Back in time is "previous" whichever way the script runs, so the glyph
    // follows the direction, as Phase 3's MonthBar picks its own.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final holdsToday = view.range.endInclusive >= today;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<TrackerRangeKind>(
          segments: [
            ButtonSegment(
                value: TrackerRangeKind.week,
                label: Text(l10n.trackerRangeWeek)),
            ButtonSegment(
                value: TrackerRangeKind.month,
                label: Text(l10n.trackerRangeMonth)),
            ButtonSegment(
                value: TrackerRangeKind.year,
                label: Text(l10n.trackerRangeYear)),
          ],
          selected: {view.kind},
          showSelectedIcon: false,
          style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.padded),
          onSelectionChanged: (selection) =>
              controller.select(selection.single),
        ),
        Row(
          children: [
            IconButton(
              key: const Key('tracker-range-previous'),
              icon: Icon(rtl ? Icons.chevron_right : Icons.chevron_left),
              tooltip: l10n.trackerRangePrevious,
              onPressed: () => controller.shift(-1),
            ),
            Expanded(
              child: Center(
                child: Text(
                  rangeLabel(view, format),
                  key: const Key('tracker-range-label'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
            IconButton(
              key: const Key('tracker-range-next'),
              icon: Icon(rtl ? Icons.chevron_left : Icons.chevron_right),
              tooltip: l10n.trackerRangeNext,
              onPressed: holdsToday ? null : () => controller.shift(1),
            ),
          ],
        ),
      ],
    );
  }
}
```

Create `app/lib/features/trackers/presentation/widgets/tracker_chart_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/tracker_providers.dart';

/// One titled chart on the Insights tab, with its own four states.
///
/// Its own, so one slow or failed query does not blank the charts beside it.
/// The states are keyed `tracker-<sectionKey>-loading|error|empty`.
class TrackerChartSection extends ConsumerWidget {
  const TrackerChartSection({
    super.key,
    required this.sectionKey,
    required this.title,
    required this.spec,
    required this.builder,
  });

  final String sectionKey;
  final String title;
  final TrackerQuerySpec spec;

  /// Draws the populated state. Called only with a result that has buckets.
  final Widget Function(BuildContext context, TrackerResult result) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = ref.watch(trackerResultProvider(spec));

    final Widget body;
    if (result.hasError) {
      body = KeyedSubtree(
        key: Key('tracker-$sectionKey-error'),
        child: NimbusErrorState(
          title: l10n.trackerInsightsErrorTitle,
          retryLabel: l10n.commonRetry,
          detail: result.error.toString(),
          onRetry: () => ref.invalidate(trackerResultProvider(spec)),
        ),
      );
    } else if (!result.hasValue) {
      // A skeleton the chart's height, never a spinner: the space the chart
      // will take is held, so nothing jumps when it arrives.
      body = Container(
        key: Key('tracker-$sectionKey-loading'),
        height: 180,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: NimbusTokens.borderRadiusMd,
        ),
      );
    } else if (result.requireValue.buckets.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: NimbusTokens.space6),
        child: Text(
          l10n.trackerInsightsNothingLogged,
          key: Key('tracker-$sectionKey-empty'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    } else {
      body = builder(context, result.requireValue);
    }

    return Padding(
      padding: const EdgeInsets.only(top: NimbusTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: NimbusTokens.space2),
          body,
        ],
      ),
    );
  }
}
```

- [ ] **Step 9: Write the tab, and put it on the detail screen**

Create `app/lib/features/trackers/presentation/widgets/tracker_insights.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../settings/application/settings_providers.dart';
import '../../application/tracker_format.dart';
import '../../application/tracker_insights_controller.dart';
import '../../application/tracker_insights_data.dart';
import '../../application/tracker_providers.dart';
import 'tracker_bar_chart.dart';
import 'tracker_chart_section.dart';
import 'tracker_range_bar.dart';

/// The Insights tab: one range control, then the charts that read it.
class TrackerInsights extends ConsumerStatefulWidget {
  const TrackerInsights({super.key, required this.tracker});

  final Tracker tracker;

  @override
  ConsumerState<TrackerInsights> createState() => _TrackerInsightsState();
}

class _TrackerInsightsState extends ConsumerState<TrackerInsights>
    with AutomaticKeepAliveClientMixin {
  // Kept alive so the range survives a visit to the History tab. The
  // controller is auto-disposed, and this subtree is what watches it.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final tracker = widget.tracker;

    // One empty state for a tracker never logged, rather than three empty
    // charts that each say so.
    final streaks = ref.watch(trackerStreaksProvider(tracker.id));
    if (streaks.hasValue && streaks.requireValue.daysSinceLast == null) {
      return NimbusEmptyState(
        key: const Key('tracker-insights-empty'),
        icon: Icons.insights,
        title: l10n.trackerInsightsEmptyTitle,
        message: l10n.trackerInsightsEmptyMessage,
      );
    }

    final view = ref.watch(trackerInsightsProvider);
    return ListView(
      key: const Key('tracker-insights'),
      padding: const EdgeInsets.all(NimbusTokens.space4),
      children: [
        const TrackerRangeBar(),
        _HistorySection(tracker: tracker, view: view),
      ],
    );
  }
}

class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.tracker, required this.view});

  final Tracker tracker;
  final TrackerInsightsView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final format = ref.watch(trackerFormatProvider);
    final calendar = ref.watch(calendarProvider);
    final today = ref.watch(trackerTodayProvider);
    final year = view.kind == TrackerRangeKind.year;

    return TrackerChartSection(
      sectionKey: 'history',
      title: year ? l10n.trackerInsightsByMonth : l10n.trackerInsightsByDay,
      spec: year
          ? TrackerQueries.byMonth(tracker.id, view.range)
          : TrackerQueries.byDay(tracker.id, view.range),
      builder: (context, result) {
        final bars = historyBars(view, result, calendar);
        final values = [for (final bar in bars) bar.value];
        final peak = bars[peakIndex(values)];
        final days = elapsedDays(view.range, today);
        // A boolean's per-day average would be a fraction of a "done", so it
        // says on how many days it was done instead.
        final caption = tracker.type == TrackerType.boolean
            ? l10n.trackerInsightsDoneCaption(
                format.number(result.sum), format.digits(days))
            : l10n.trackerInsightsTotalCaption(
                format.total(tracker, result.sum),
                format.total(tracker, days == 0 ? 0 : result.sum / days));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TrackerBarChart(
              key: const Key('tracker-history-chart'),
              values: values,
              color: Color(tracker.color),
              labelEvery: view.kind == TrackerRangeKind.month ? 5 : 1,
              labelOf: (index) {
                final parts =
                    calendar.partsOf(bars[index].period.startInclusive);
                return format.digits(year ? parts.month : parts.day);
              },
              axisLabelOf: (value) => format.axis(tracker, value),
              semanticsLabel: l10n.trackerInsightsHistorySummary(
                tracker.name,
                rangeLabel(view, format),
                format.total(tracker, result.sum),
                year
                    ? format.month(peak.period.startInclusive)
                    : format.date(peak.period.startInclusive),
                format.total(tracker, peak.value),
              ),
            ),
            const SizedBox(height: NimbusTokens.space2),
            Text(caption,
                key: const Key('tracker-history-caption'),
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        );
      },
    );
  }
}
```

In `app/lib/features/trackers/presentation/tracker_detail_screen.dart`:
1. Import `widgets/tracker_insights.dart`.
2. Replace the `body: Column(...)` of the populated `Scaffold` with:

```dart
        body: DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(tracker: current, total: total),
              TabBar(tabs: [
                Tab(
                    key: const Key('tracker-tab-history'),
                    text: l10n.trackerTabHistory),
                Tab(
                    key: const Key('tracker-tab-insights'),
                    text: l10n.trackerTabInsights),
              ]),
              Expanded(
                child: TabBarView(children: [
                  _History(tracker: current),
                  TrackerInsights(tracker: current),
                ]),
              ),
            ],
          ),
        ),
```

3. Update the class doc's first line to: `/// One tracker: today's total and streak, its history and its insights, and`.

- [ ] **Step 10: Run the tests to confirm GREEN**

Run the commands from Step 3, then the whole tracker folder: `cd app && flutter test --no-pub <absolute path>/app/test/features/trackers/`.
Expected: PASS, including every 4a detail test, which now runs on the History tab.

**Mutation check.**
1. In `historyBars`, return only the bars that have buckets: `[for (final b in result.buckets) ...]` in place of the filled list.
2. Re-run `tracker_insights_data_test.dart`. Expected: "a month draws every day" FAILS.
3. Restore it.

- [ ] **Step 11: Run the full gate**

Expected:
- `nimbus_domain` is 324 + 2 = **326**;
- `app` is 473 + 25 = **498**: 3 format tests, 8 data tests and 14 widget tests;
- the rest are unchanged.

- [ ] **Step 12: Commit and merge**

```bash
git add packages/nimbus_domain app/lib/features/trackers app/lib/l10n app/test/features/trackers
git commit -F - <<'EOF'
feat(trackers): the Insights tab and its history chart

The detail screen gains History and Insights tabs under a shared
header, with the quick log still pinned in the bottom third. Insights
shows a week, a month or a year of the active calendar, a bar per day
-- or per month in the year view, so a Jalali year shows Jalali
months -- and says the total and the average per day so far. A
boolean says on how many days it was done instead of averaging a
fraction of a "done".

Every bar is drawn, quiet days at zero. The engine answers only the
days that have entries, and plotting those alone would make a sparse
month look like a habit kept daily. The chart speaks one summary,
because a screen reader cannot read bars. Its tooltips are off,
because fl_chart prints the raw double.

The range re-anchors when the calendar or the week's first day
changes, and the tab keeps itself alive so the range survives a trip
to History. Each chart has its own loading, error and empty states,
so one slow query blanks nothing beside it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/4-trackers
git merge --ff-only feat/tracker-insights
```

---

### Task 10: Time-of-day and day-of-week patterns

Branch `feat/tracker-patterns`, slug `tracker-patterns`.

**Files:**
- Modify: `packages/nimbus_domain/lib/src/trackers/tracker_queries.dart`
- Modify: `app/lib/features/trackers/application/tracker_insights_data.dart`, `app/lib/features/trackers/presentation/widgets/tracker_insights.dart`, the ARBs and the generated localizations
- Test: `packages/nimbus_domain/test/trackers/tracker_queries_test.dart`, `app/test/features/trackers/tracker_insights_data_test.dart`, `app/test/features/trackers/tracker_insights_test.dart`

**Interfaces:**
- Consumes:
  - everything Task 9 produced;
  - `weekdaysFrom(int firstDayOfWeek)` from Phase 3's `app/lib/features/analytics/application/patterns_controller.dart` (imported read-only);
  - the shared `weekday*` ARB keys.
- Produces:
  - `TrackerQueries.byHour(String id, DateRange range)` and `TrackerQueries.byWeekday(String id, DateRange range)`.
  - `hourBars(TrackerResult)` and `weekdayBars(TrackerResult, List<int> order)`.
  - The charts are keyed `tracker-hour-chart` and `tracker-weekday-chart`, with labels `tracker-hour-label-<i>` and `tracker-weekday-label-<i>`.

- [ ] **Step 1: Branch**

```bash
git switch phase/4-trackers
git switch -c feat/tracker-patterns
```

- [ ] **Step 2: Write the failing tests**

Append to `packages/nimbus_domain/test/trackers/tracker_queries_test.dart`, inside `main`:

```dart
  test('the time-of-day pattern asks by hour', () {
    expect(
        TrackerQueries.byHour('cig', oneDay),
        TrackerQuerySpec(
            trackerIds: ['cig'],
            dateRange: oneDay,
            groupBy: const TrackerGroupByHourOfDay(),
            aggregate: Aggregate.sum));
  });

  test('the day-of-week pattern asks by weekday', () {
    expect(
        TrackerQueries.byWeekday('cig', oneDay),
        TrackerQuerySpec(
            trackerIds: ['cig'],
            dateRange: oneDay,
            groupBy: const TrackerGroupByDayOfWeek(),
            aggregate: Aggregate.sum));
  });
```

Append to `app/test/features/trackers/tracker_insights_data_test.dart`, inside `main`:

```dart
  test('twenty-four hour bars, quiet hours at zero', () {
    final bars = hourBars(TrackerResult(buckets: [
      TrackerBucket(key: HourOfDayKey(7), value: 1, count: 1),
      TrackerBucket(key: HourOfDayKey(12), value: 2, count: 2),
    ], sum: 3, count: 3));
    expect(bars, hasLength(24));
    expect(bars[7], 1);
    expect(bars[12], 2);
    expect(bars.where((value) => value == 0), hasLength(22));
  });

  test("weekday bars follow the user's week, not ISO order", () {
    final result = TrackerResult(buckets: [
      TrackerBucket(key: DayOfWeekKey(DateTime.monday), value: 3, count: 3),
      TrackerBucket(key: DayOfWeekKey(DateTime.saturday), value: 1, count: 1),
    ], sum: 4, count: 4);
    const saturdayFirst = [6, 7, 1, 2, 3, 4, 5];
    expect(weekdayBars(result, saturdayFirst), [1, 0, 3, 0, 0, 0, 0]);
  });
```

Append to `app/test/features/trackers/tracker_insights_test.dart`, inside `main`:

```dart
  /// Scrolls the Insights list until [key] is on screen: the patterns sit
  /// below the history chart.
  Future<void> scrollTo(WidgetTester tester, String key) =>
      tester.scrollUntilVisible(find.byKey(Key(key)), 200,
          scrollable: find.descendant(
              of: find.byKey(const Key('tracker-insights')),
              matching: find.byType(Scrollable)));

  group('patterns', () {
    /// Two cigarettes now (12:30 in Tehran) and one at 07:30, all on Monday
    /// 5 October.
    Future<Tracker> cigarettesAtNoonAndDawn() async {
      final cig = await repo.create(cigarettes);
      await repo.logEntry(cig.id);
      await repo.logEntry(cig.id);
      await repo.logEntry(cig.id,
          at: fake.nowUtc.subtract(const Duration(hours: 5)));
      return cig;
    }

    testWidgets("the hours are local, from each entry's own offset",
        (tester) async {
      await useGregorianEnglish();
      final cig = await cigarettesAtNoonAndDawn();
      await openInsights(tester, cig.id);
      await scrollTo(tester, 'tracker-hour-chart');

      final hours = barsOf(tester, 'tracker-hour-chart');
      expect(hours, hasLength(24));
      expect(hours[12], 2);
      expect(hours[7], 1);
    });

    testWidgets("a duration's hours are its start times, and it says so",
        (tester) async {
      await useGregorianEnglish();
      final s = await repo.create(sleep);
      await repo.addDuration(s.id, const Duration(minutes: 30));
      await openInsights(tester, s.id);
      await scrollTo(tester, 'tracker-hour-chart');

      expect(find.text('Time of day · by start time'), findsOneWidget);
    });

    testWidgets("weekdays run in the user's week, Saturday first",
        (tester) async {
      await useGregorianEnglish();
      final cig = await cigarettesAtNoonAndDawn();
      await openInsights(tester, cig.id);
      await scrollTo(tester, 'tracker-weekday-chart');

      expect(barsOf(tester, 'tracker-weekday-chart'),
          [0.0, 0.0, 3.0, 0.0, 0.0, 0.0, 0.0]);
      expect(textOf(tester, 'tracker-weekday-label-0'), 'Saturday');
    });

    testWidgets('a Monday week start moves Monday to the front',
        (tester) async {
      await useGregorianEnglish(firstDayOfWeek: DateTime.monday);
      final cig = await cigarettesAtNoonAndDawn();
      await openInsights(tester, cig.id);
      await scrollTo(tester, 'tracker-weekday-chart');

      expect(barsOf(tester, 'tracker-weekday-chart').first, 3);
      expect(textOf(tester, 'tracker-weekday-label-0'), 'Monday');
    });

    testWidgets('both patterns speak their peaks', (tester) async {
      final semantics = tester.ensureSemantics();
      await useGregorianEnglish();
      final cig = await cigarettesAtNoonAndDawn();
      await openInsights(tester, cig.id);

      await scrollTo(tester, 'tracker-hour-chart');
      expect(
          find.bySemanticsLabel(
              'Cigarettes by time of day, 2026/10: most around 12:00, 2'),
          findsOneWidget);
      await scrollTo(tester, 'tracker-weekday-chart');
      expect(
          find.bySemanticsLabel(
              'Cigarettes by day of week, 2026/10: most on Monday, 3'),
          findsOneWidget);
      semantics.dispose();
    });

    testWidgets("a failed pattern blanks only itself", (tester) async {
      await useGregorianEnglish();
      final cig = await cigarettesAtNoonAndDawn();
      await openInsights(tester, cig.id, overrides: [
        trackerResultProvider(TrackerQueries.byHour(cig.id, october))
            .overrideWith(
                (ref) => Future<TrackerResult>.error(Exception('boom'))),
      ]);

      expect(find.byKey(const Key('tracker-history-chart')), findsOneWidget);
      await scrollTo(tester, 'tracker-hour-error');
      expect(find.byKey(const Key('tracker-hour-error')), findsOneWidget);
    });
  });
```

- [ ] **Step 3: Run the tests to confirm RED**

Run: `cd packages/nimbus_domain && dart test test/trackers/tracker_queries_test.dart`
Expected: FAIL to compile, naming `byHour` and `byWeekday`.

Run: `cd app && flutter test --no-pub <absolute path>/app/test/features/trackers/tracker_insights_data_test.dart <absolute path>/app/test/features/trackers/tracker_insights_test.dart`
Expected: FAIL to compile, naming `hourBars`, `weekdayBars` and `byHour`.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-tracker-patterns
```

- [ ] **Step 5: Add the queries and the bar data**

In `packages/nimbus_domain/lib/src/trackers/tracker_queries.dart`, add inside the class:

```dart
  /// [trackerId]'s entries over [range] by local hour: the time-of-day
  /// pattern.
  static TrackerQuerySpec byHour(String trackerId, DateRange range) =>
      TrackerQuerySpec(
        trackerIds: [trackerId],
        dateRange: range,
        groupBy: const TrackerGroupByHourOfDay(),
        aggregate: Aggregate.sum,
      );

  /// [trackerId]'s entries over [range] by weekday: the day-of-week pattern.
  static TrackerQuerySpec byWeekday(String trackerId, DateRange range) =>
      TrackerQuerySpec(
        trackerIds: [trackerId],
        dateRange: range,
        groupBy: const TrackerGroupByDayOfWeek(),
        aggregate: Aggregate.sum,
      );
```

In `app/lib/features/trackers/application/tracker_insights_data.dart`, append:

```dart
/// The twenty-four hour bars, quiet hours included.
List<double> hourBars(TrackerResult result) {
  final byHour = <int, double>{
    for (final bucket in result.buckets)
      if (bucket.key case HourOfDayKey(:final hour)) hour: bucket.value,
  };
  return [for (var hour = 0; hour < 24; hour++) byHour[hour] ?? 0];
}

/// The seven weekday bars, in [order]: the user's week, as Phase 3's
/// `weekdaysFrom` lists it. Iran's week starts on Saturday, and ISO order
/// would shift every bar by two days in a way that reads as data.
List<double> weekdayBars(TrackerResult result, List<int> order) {
  final byWeekday = <int, double>{
    for (final bucket in result.buckets)
      if (bucket.key case DayOfWeekKey(:final weekday)) weekday: bucket.value,
  };
  return [for (final weekday in order) byWeekday[weekday] ?? 0];
}
```

- [ ] **Step 6: Add the strings**

Write the scratchpad file `keys_patterns.json`:

```json
{
  "en": {
    "trackerInsightsByHour": "Time of day",
    "trackerInsightsByStartHour": "Time of day · by start time",
    "trackerInsightsByWeekday": "Day of week",
    "trackerInsightsHourSummary": "{name} by time of day, {period}: most around {hour}, {peakValue}",
    "@trackerInsightsHourSummary": {"placeholders": {"name": {"type": "String"}, "period": {"type": "String"}, "hour": {"type": "String"}, "peakValue": {"type": "String"}}},
    "trackerInsightsWeekdaySummary": "{name} by day of week, {period}: most on {weekday}, {peakValue}",
    "@trackerInsightsWeekdaySummary": {"placeholders": {"name": {"type": "String"}, "period": {"type": "String"}, "weekday": {"type": "String"}, "peakValue": {"type": "String"}}}
  },
  "fa": {
    "trackerInsightsByHour": "ساعت روز",
    "trackerInsightsByStartHour": "ساعت روز · بر اساس زمان شروع",
    "trackerInsightsByWeekday": "روز هفته",
    "trackerInsightsHourSummary": "{name} بر اساس ساعت، {period}: بیشترین حدود {hour}، {peakValue}",
    "trackerInsightsWeekdaySummary": "{name} بر اساس روز هفته، {period}: بیشترین در {weekday}، {peakValue}"
  }
}
```

Run:

```bash
python <scratchpad>/arb_add.py <scratchpad>/keys_patterns.json
cd app && flutter gen-l10n
```

Expected: two `wrote … (+5 entries)` lines (+7 counting `en`'s metadata), and `gen-l10n` reports no errors.

- [ ] **Step 7: Draw the two patterns**

In `app/lib/features/trackers/presentation/widgets/tracker_insights.dart`:

1. Add the import:

```dart
import '../../../analytics/application/patterns_controller.dart'
    show weekdaysFrom;
```

2. In `_TrackerInsightsState.build`, after `_HistorySection(tracker: tracker, view: view),` add:

```dart
        _HourSection(tracker: tracker, view: view),
        _WeekdaySection(tracker: tracker, view: view),
```

3. Append to the file:

```dart
class _HourSection extends ConsumerWidget {
  const _HourSection({required this.tracker, required this.view});

  final Tracker tracker;
  final TrackerInsightsView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final format = ref.watch(trackerFormatProvider);

    return TrackerChartSection(
      sectionKey: 'hour',
      // A timed session is stamped when its timer starts, so a duration's
      // hours are start times, and the title says so.
      title: tracker.type == TrackerType.duration
          ? l10n.trackerInsightsByStartHour
          : l10n.trackerInsightsByHour,
      spec: TrackerQueries.byHour(tracker.id, view.range),
      builder: (context, result) {
        final values = hourBars(result);
        final peak = peakIndex(values);
        return TrackerBarChart(
          key: const Key('tracker-hour-chart'),
          values: values,
          color: Color(tracker.color),
          // Twenty-four labels do not fit; the shape is the message here.
          labelEvery: 6,
          labelOf: format.digits,
          labelKeyPrefix: 'tracker-hour-label',
          axisLabelOf: (value) => format.axis(tracker, value),
          semanticsLabel: l10n.trackerInsightsHourSummary(
            tracker.name,
            rangeLabel(view, format),
            format.time(DateTime.utc(2000, 1, 1, peak)),
            format.total(tracker, values[peak]),
          ),
        );
      },
    );
  }
}

class _WeekdaySection extends ConsumerWidget {
  const _WeekdaySection({required this.tracker, required this.view});

  final Tracker tracker;
  final TrackerInsightsView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final format = ref.watch(trackerFormatProvider);
    final order = weekdaysFrom(ref.watch(firstDayOfWeekProvider));

    return TrackerChartSection(
      sectionKey: 'weekday',
      title: l10n.trackerInsightsByWeekday,
      spec: TrackerQueries.byWeekday(tracker.id, view.range),
      builder: (context, result) {
        final values = weekdayBars(result, order);
        final peak = peakIndex(values);
        return TrackerBarChart(
          key: const Key('tracker-weekday-chart'),
          values: values,
          color: Color(tracker.color),
          labelOf: (index) => _weekdayName(l10n, order[index]),
          labelKeyPrefix: 'tracker-weekday-label',
          axisLabelOf: (value) => format.axis(tracker, value),
          semanticsLabel: l10n.trackerInsightsWeekdaySummary(
            tracker.name,
            rangeLabel(view, format),
            _weekdayName(l10n, order[peak]),
            format.total(tracker, values[peak]),
          ),
        );
      },
    );
  }
}

/// A weekday's name, from the shared `weekday*` strings.
///
/// Phase 3 has the same switch, private to its patterns screen, which 4b does
/// not edit.
String _weekdayName(AppLocalizations l10n, int isoWeekday) =>
    switch (isoWeekday) {
      DateTime.monday => l10n.weekdayMonday,
      DateTime.tuesday => l10n.weekdayTuesday,
      DateTime.wednesday => l10n.weekdayWednesday,
      DateTime.thursday => l10n.weekdayThursday,
      DateTime.friday => l10n.weekdayFriday,
      DateTime.saturday => l10n.weekdaySaturday,
      _ => l10n.weekdaySunday,
    };
```

- [ ] **Step 8: Run the tests to confirm GREEN**

Run the commands from Step 3, then `cd app && flutter test --no-pub <absolute path>/app/test/features/trackers/`.
Expected: PASS.

**Mutation check.**
1. Pass ISO order to `weekdayBars`: `weekdayBars(result, const [1, 2, 3, 4, 5, 6, 7])`.
2. Re-run. Expected: "weekdays run in the user's week, Saturday first" FAILS.
3. Restore it.

- [ ] **Step 9: Run the full gate**

Expected:
- `nimbus_domain` is 326 + 2 = **328**;
- `app` is 498 + 8 = **506**;
- the rest are unchanged.

- [ ] **Step 10: Commit and merge**

```bash
git add packages/nimbus_domain app/lib/features/trackers app/lib/l10n app/test/features/trackers
git commit -F - <<'EOF'
feat(trackers): time-of-day and day-of-week patterns

The patterns the per-increment rows were kept for: when in the day a
habit happens, and on which days of the week, over the range the
history chart shows. Hours are local to each entry, from the offset
it was logged with, so a trip abroad does not smear the chart. A
duration's hours are start times, and its title says so.

Weekdays run in the user's week, Saturday first by default, through
Phase 3's weekdaysFrom; ISO order would shift every bar by two days.
Each pattern speaks its peak and fails on its own.

Imports Phase 3's weekdaysFrom read-only.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/4-trackers
git merge --ff-only feat/tracker-patterns
```

---

### Task 11: The 4b gate — device check, Persian review, docs, `phase-4-complete`

Branch `docs/phase-4-complete`, from `phase/4-trackers`.

**Files:**
- Docs: `docs/phases/phase-4-trackers.md`, `docs/phases/README.md`, `docs/phases/DEFERRED.md` (only if the check finds something), `docs/superpowers/specs/2026-10-05-trackers-4b-design.md`
- Scratchpad: `verify_db.py`, the uiautomator dumps, and the database copies

- [ ] **Step 1: Run the gate on the phase branch's tip**

From the repo root, on `phase/4-trackers`, run the six commands of the commit routine. Record each suite's count for the gate record.

Expected:
- architecture **5**;
- `nimbus_domain` **328**;
- `nimbus_data` **243**;
- `nimbus_design` **36**;
- `app` **506**.

If a count differs, find out why before going on. A task may have added a test this plan did not count; record the real number.

- [ ] **Step 2: Device check on the Galaxy A53 (operator in the loop)**

The A53 is the operator's daily phone. **Before touching it, ask the operator to confirm it is free and unlocked**, and change none of its settings. Follow the project memory "Driving a device check over adb":
- uiautomator dumps expose Flutter semantics;
- delete the old dump first, because a failed dump leaves a stale file;
- prefix device paths with `MSYS_NO_PATHCONV=1` in Git Bash;
- the display runs at 120 Hz.

Write the scratchpad file `verify_db.py`:

```python
"""Prints what the 4b upgrade must preserve and add, for one database copy."""
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
print('user_version', db.execute('PRAGMA user_version').fetchone()[0])
print('live entries', db.execute(
    'SELECT COUNT(*) FROM tracker_entries WHERE deleted_at IS NULL').fetchone()[0])
columns = [r[1] for r in db.execute('PRAGMA table_info(tracker_entries)')]
if 'tz_offset_minutes' in columns:
    print('offsets', db.execute(
        'SELECT tz_offset_minutes, COUNT(*) FROM tracker_entries '
        'GROUP BY tz_offset_minutes').fetchall())
else:
    print('offsets: no column yet')
print('indexes', sorted(r[0] for r in db.execute(
    "SELECT name FROM sqlite_master WHERE type = 'index' "
    "AND tbl_name = 'tracker_entries' AND name NOT LIKE 'sqlite_%'")))
```

1. **Back up first.** Stop the app so nothing is mid-write, then copy all three files, as in `docs/DEVELOPMENT.md`'s backup step:

   ```bash
   adb shell am force-stop com.nimbustats.app
   STAMP=$(date +%Y%m%d-%H%M)
   mkdir -p ~/nimbustats-backups
   for f in nimbustats.sqlite nimbustats.sqlite-wal nimbustats.sqlite-shm; do
     adb exec-out run-as com.nimbustats.app cat "app_flutter/$f" > ~/nimbustats-backups/"pre-v32-$STAMP-$f"
   done
   python <scratchpad>/verify_db.py ~/nimbustats-backups/pre-v32-$STAMP-nimbustats.sqlite
   ```

   Expected:
   - `user_version 30`;
   - a live-entry count, **write it down**;
   - `offsets: no column yet`;
   - three indexes: `idx_tracker_entries_day`, `idx_tracker_entries_history` and `idx_tracker_entries_once_per_day` (the v30 snapshot has three; "four" was a miscount).

   A missing `-wal` file prints an error from `run-as` and leaves an empty file. That is harmless: SQLite ignores an empty WAL.

2. **Build and install,** which upgrades v30 → v32 on the device:

   ```bash
   cd app && flutter build apk --profile --no-pub
   adb install -r build/app/outputs/flutter-apk/app-profile.apk
   adb shell monkey -p com.nimbustats.app -c android.intent.category.LAUNCHER 1
   ```

   Expected: `Success`, and the app opens on Home with its data.

3. **Prove the upgrade from the database, not the screen:**

   ```bash
   adb shell am force-stop com.nimbustats.app
   for f in nimbustats.sqlite nimbustats.sqlite-wal nimbustats.sqlite-shm; do
     adb exec-out run-as com.nimbustats.app cat "app_flutter/$f" > <scratchpad>/post-v32-$f
   done
   python <scratchpad>/verify_db.py <scratchpad>/post-v32-nimbustats.sqlite
   ```

   Expected:
   - `user_version 32`;
   - the **same** live-entry count as before;
   - `offsets [(210, N)]`, every entry stamped +3:30;
   - indexes including `idx_tracker_entries_tracker_day` and **not** `idx_tracker_entries_day`.

4. **Insights on real data.** Relaunch and open a tracker with entries from more than one day. Then:
   - **Header:** dump the UI and read the streak and last-entry lines.
   - **Month view:** tap the Insights tab (its coordinates come from the dump's `bounds`) and dump. The range reads `۱۴۰۵/۰۷` in Persian or `1405/07` in English. The history chart's spoken summary names the total and the peak day, and the time-of-day and day-of-week summaries name their peaks.
   - **Week, Year and Earlier:** tap each and dump after every tap. The label follows the tap, and › is disabled while the range holds today.
   - **Scrolling:** watch for dropped frames while shifting ranges. If the shifts visibly stutter at 120 Hz, record it as a new deferred item beside D16 rather than fixing it here.

5. **Persian.** If the operator agrees to switch the app's language for the check, look at Insights in Persian: Persian digits, the arrows mirrored, and the charts running left to right as Phase 3's do (Decision 10). Switch back afterwards. If they decline, record that the Persian check was waived, as Phases 3 and 4a did; the Persian widget tests stand in for it.

6. **Save the evidence.** Keep the dumps in the scratchpad, never the repo, and write down what was observed, including anything that did not match.

- [ ] **Step 3: Operator review of the Persian strings**

Show the operator every Persian value added in Tasks 8–10, listed from `git diff main..phase/4-trackers -- app/lib/l10n/app_fa.arb`, beside its English.

If corrections come:
1. Make them a separate commit, `fix(l10n): …`.
2. Write a `keys_fix.json` with only the changed `fa` values (and `"en": {}`).
3. Run `python <scratchpad>/arb_add.py <scratchpad>/keys_fix.json --update`, then `flutter gen-l10n`, then the widget tests whose Persian text changed, then the gate.

- [ ] **Step 4: Tick the brief's definition of done, and write the 4b gate record**

In `docs/phases/phase-4-trackers.md`, "Definition of done":
- Tick `**[4b]** No aggregation SQL exists outside Phase 3's engine`, with: `` `test/architecture_test.dart` ("tracker code aggregates only through the analytics engine") enforces it on every run; its one allowed line places a new tracker (`sortOrder.max()`). ``
- Tick `git tag phase-4-complete`.

After the 4a gate record, add **"4b gate record (date), against `CONVENTIONS.md` §5 on `<tip hash>`"**, with one bullet per item:
- `dart analyze --fatal-infos`;
- the five suite counts from Step 1;
- the device upgrade: the backup path, `user_version` 30 → 32, the live-entry count before and after, and the offsets;
- the A53 Insights observations from Step 2;
- strings (both ARBs, and the operator's review);
- RTL and Persian digits (the widget tests named, and the device check or its waiver);
- states (loading, error, empty and populated on each chart, and the never-logged state);
- accessibility (the spoken summaries, the 48-point range controls, twice the font size);
- the schema registry at `v30, v31, v32`.

Use `git log -1 --format=%h` for the tip hash; never invent one.

In `docs/phases/README.md`'s status board:
- The Phase 4 row becomes `**Complete** (date): 4a and 4b. History chart, streaks and patterns on Phase 3's engine; schema v31–v32 ran on the Galaxy A53's data. Carried forward: D17, D18`, plus any new deferred item.
- The Phase 5 row becomes `Ready: phase-3-complete and phase-4-complete exist; it consumes TrackerQuerySpec and TrackerQueries`.

In `docs/superpowers/specs/2026-10-05-trackers-4b-design.md`, replace the status line with `**Status:** implemented; the gate record is in the brief.`

- [ ] **Step 5: Commit, merge and tag**

```bash
git add docs/phases docs/superpowers/specs/2026-10-05-trackers-4b-design.md
git commit -F - <<'EOF'
docs: Phase 4 is complete

Ticks 4b's definition of done with its evidence. The "no aggregation
outside the engine" rule is now a test rather than a grep, so it
holds after this gate as well as at it. The gate record follows
CONVENTIONS §5: the suites, and the v30 -> v32 upgrade on the A53's
real data after a backup, with every entry kept and stamped +3:30
and the day index gone. Insights was read off the device's semantics
tree.

Phase 5 is unblocked: tracker goals can scope a TrackerQuerySpec,
the same question the screens ask.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
git switch phase/4-trackers
git merge --ff-only docs/phase-4-complete
git switch main
git merge --ff-only phase/4-trackers
git tag phase-4-complete
git tag --list 'phase-*-complete'
```

Expected: the list ends with `phase-4-complete`. Nothing is pushed until the operator asks.
