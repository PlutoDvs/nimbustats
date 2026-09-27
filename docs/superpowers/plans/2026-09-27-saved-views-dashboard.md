# Saved views and the dashboard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin any analytics tab or pattern chart as a named view, and show pinned views as independently-loading cards on a Dashboard tab that opens Analytics — plus the prerequisite fix that makes analytics answers follow the data.

**Architecture:** A saved view is a date-less `QuerySpec` plus a relative `ViewPeriod` and a fixed `SavedViewChart`, stored in `saved_views` (schema v21 adds the period columns). The DAO reads rows one at a time into a sealed `SavedViewEntry` so one bad row is one bad card. Each card resolves its spec against the dashboard's month and runs through the existing `analyticsResultProvider` — one engine, no dashboard SQL. Everything app-side lives in `app/lib/features/analytics/`.

**Tech Stack:** Flutter 3.47.1 / Dart 3.13.1, Riverpod 3.4.2, go_router 17.5.0, drift 2.34 (+ drift_dev 2.34.5), fl_chart 1.2.

**Spec:** `docs/superpowers/specs/2026-09-27-saved-views-dashboard-design.md` — read it first; this plan argues from it.

## Global Constraints

- Branch: `phase/3-saved-views` (from `ade2fcc`). Per task, work on a short branch `feat/<slug>` (or `fix/`/`refactor/`) cut from `phase/3-saved-views`, then fast-forward back.
- Schema: Phase 3 owns v20–v29. This plan takes **v21** and nothing else.
- Every new user-facing string goes in **both** `app/lib/l10n/app_en.arb` and `app/lib/l10n/app_fa.arb`, keys kept in alphabetical order, Persian value never equal to the English one (`test/localization_test.dart` enforces both). Regenerate with `cd app && flutter gen-l10n`.
- No confirmation dialogs (`showDialog`, `AlertDialog`) — `app/test/ux_rules_test.dart` fails on them. Destructive actions are undo snackbars (`nimbusUndoSnackBar`).
- Presentation code never touches a DAO — only repositories/providers (`ux_rules_test`). The `app` package never imports `drift` (`test/architecture_test.dart`); in app tests use `db.customSelect` / `db.customStatement` on `AppDatabase`.
- No raw `Color(0x…)` outside `nimbus_design`.
- Lints: `strict-casts`, `unawaited_futures` is an **error**, `dart analyze --fatal-infos` must be clean (deprecated APIs are infos → failures; use `onReorderItem`, never `onReorder`).
- Amounts: `formatCompact` in dense rows and axes, full `format` for totals (screen contract §8). Digits follow settings via `moneyFormatterProvider` — the app's default settings locale is `fa`, so money in widget tests renders in Persian digits even with `locale: Locale('en')`.
- Money stays `int` minor units throughout.

### Commit routine (every task)

1. `git switch phase/3-saved-views && git switch -c <branch>` (branch named in the task).
2. Write the task's tests. Run them. Confirm they fail **for the stated reason**.
3. `git tag pre-<slug>` (on the parent commit — nothing of this task is committed yet). Local only; never pushed.
4. Implement. Run the task's tests: green.
5. Full gate from the repo root, all green (baseline before this plan: 4 / 241 / 149 / 35 / 252):
   ```bash
   dart analyze --fatal-infos
   dart test test/architecture_test.dart
   (cd packages/nimbus_domain && dart test)
   (cd packages/nimbus_data && dart test)
   (cd packages/nimbus_design && flutter test)
   (cd app && flutter test)
   ```
   A first `flutter test`/`dart test` run after edits occasionally fails while "loading" a file; re-run once before treating it as real.
6. `git add` the task's files and commit with the message given (body ends with the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` line).
7. `git switch phase/3-saved-views && git merge --ff-only <branch>`.

---

## File map

**nimbus_domain** (`packages/nimbus_domain/lib/src/analytics/`)
- `view_period.dart` *(new)* — `ViewPeriod`: relative window, `resolve`, `fromStored`.
- `saved_view_chart.dart` *(new)* — `SavedViewChart` enum + `parse`.
- `query_filters.dart`, `query_spec.dart` — add `withDateRange`.

**nimbus_data** (`packages/nimbus_data/`)
- `lib/src/tables/saved_views_table.dart` — `period_type`, `period_count`.
- `lib/src/database/app_database.dart` — v21 migration; `SavedViewsDao` rewritten.
- `lib/src/analytics/saved_view.dart` — sealed `SavedViewEntry`, `SavedView`, `UnreadableSavedView`, `NewSavedView`.
- `lib/src/analytics/analytics_engine.dart` — `changes()`.
- `drift_schemas/drift_schema_v21.json`, `test/generated/*` — generated.

**app** (`app/lib/features/analytics/`)
- `data/pin_request.dart`, `data/saved_views_repository.dart`
- `application/analytics_providers.dart` (auto-dispose + self-invalidating), `application/saved_view_providers.dart`, `application/dashboard_anchor.dart`, `application/starter_views.dart`
- `presentation/analytics_screen.dart` (Dashboard tab first, pin buttons), `presentation/dashboard_tab.dart`, `presentation/saved_view_screen.dart`
- `presentation/widgets/`: `view_name_sheet.dart`, `pin_button.dart`, `month_bar.dart`, `saved_view_card.dart`, `card_previews.dart`, `saved_view_body.dart`, `saved_view_actions.dart`; `patterns_body.dart`, `trends_body.dart`, `breakdown_body.dart` modified
- `routes.dart` — `savedViewRoute`, `savedViewLocation`, `analyticsRoutes`
- `app/lib/bootstrap/app_router.dart` — one line.

---

### Task 1: Schema v21 — a saved view remembers its period (schema lock)

Branch `feat/schema-v21`, slug `schema-v21`. Lands on `main` alone (CONVENTIONS §2).

**Files:**
- Modify: `packages/nimbus_data/lib/src/tables/saved_views_table.dart`
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` (`schemaVersion`, `onUpgrade`)
- Generated: `lib/src/database/app_database.g.dart`, `drift_schemas/drift_schema_v21.json`, `test/generated/schema_v21.dart`, `test/generated/schema.dart`
- Delete: `packages/nimbus_data/test/migration_v1_to_v20_test.dart`
- Create: `packages/nimbus_data/test/migration_test.dart`
- Modify: `packages/nimbus_data/test/analytics/saved_views_test.dart` (version assertion)
- Modify: `docs/phases/CONVENTIONS.md` (registry row)

**Interfaces:**
- Produces: columns `saved_views.period_type TEXT NOT NULL DEFAULT 'month'`, `saved_views.period_count INTEGER NOT NULL DEFAULT 1`; drift getters `savedViews.periodType`, `savedViews.periodCount`; companion fields `periodType: Value<String>`, `periodCount: Value<int>`.

- [ ] **Step 1: Write the failing tests**

`git rm packages/nimbus_data/test/migration_v1_to_v20_test.dart`, then create `packages/nimbus_data/test/migration_test.dart`:

```dart
import 'package:drift_dev/api/migrations_native.dart';
import 'package:nimbus_data/nimbus_data.dart';
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
  test('a v1 database upgrades to v21 and matches a fresh install', () async {
    final db = AppDatabase(await verifier.startAt(1));
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 21);
  });

  test('a v20 database upgrades to v21 and matches a fresh install', () async {
    final db = AppDatabase(await verifier.startAt(20));
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 21);
  });

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

    await verifier.migrateAndValidate(db, 21);

    final row = await db
        .customSelect(
            "SELECT period_type, period_count FROM saved_views WHERE id = 'old'")
        .getSingle();
    expect(row.read<String>('period_type'), 'month');
    expect(row.read<int>('period_count'), 1);
  });
}
```

In `packages/nimbus_data/test/analytics/saved_views_test.dart`, change the version test:

```dart
  test('the schema version is 21', () async {
    expect(db.schemaVersion, 21);
  });
```

- [ ] **Step 2: Run to verify RED**

Run: `cd packages/nimbus_data && dart test test/migration_test.dart test/analytics/saved_views_test.dart`
Expected: FAIL — `MissingSchemaException` for version 21 (no v21 snapshot) and `Expected: <21> Actual: <20>`.

- [ ] **Step 3: Tag the rollback target**

Run: `git tag pre-schema-v21`

- [ ] **Step 4: Add the columns**

In `packages/nimbus_data/lib/src/tables/saved_views_table.dart`, after `sortOrder`:

```dart
  /// A `PeriodType` name. With [periodCount] it is the window a card covers,
  /// counted back from whichever date the dashboard is anchored on.
  ///
  /// Stored beside the spec rather than in it: the spec's own date range is
  /// absolute, so a view pinned as "this month" would stay on the month it
  /// was pinned forever. Added in v21.
  TextColumn get periodType => text().withDefault(const Constant('month'))();

  /// How many periods of [periodType], ending with the anchor's. At least 1.
  IntColumn get periodCount => integer().withDefault(const Constant(1))();
```

- [ ] **Step 5: Bump the version and add the migration step**

In `packages/nimbus_data/lib/src/database/app_database.dart`: `int get schemaVersion => 21;` and replace the `onUpgrade` body with:

```dart
        onUpgrade: (m, from, to) async {
          // v1 -> v20: Phase 3 adds saved_views. Phases 1 and 2 consumed no
          // schema version, so there is no intermediate step to write. The
          // reserved per-phase ranges in CONVENTIONS.md are what make that
          // safe rather than lucky: two branches both bumping to v2 would
          // produce a merge in which one migration silently disappears, and
          // the failure lands on a user's device, not in CI.
          if (from < 20) {
            // createTable builds the table as it is declared *now*, so this
            // path already gets v21's period columns -- which is why the v21
            // step below is an else rather than a second if. Adding them again
            // here would fail on a duplicate column.
            await m.createTable(savedViews);
            // createTable does not bring the table's indexes with it, but a
            // fresh install's createAll does. Without this line an upgraded
            // device runs the pinned-views query without its index while a
            // new install has it -- two populations on different schemas,
            // which is exactly what the migration test exists to catch.
            await m.create(idxSavedViewsPinned);
          } else if (from < 21) {
            // v20 -> v21: a saved view's period moves out of its spec, whose
            // date range is absolute. Existing rows take the defaults -- one
            // month -- which is what every v20 pin source meant.
            await m.addColumn(savedViews, savedViews.periodType);
            await m.addColumn(savedViews, savedViews.periodCount);
          }
        },
```

- [ ] **Step 6: Regenerate drift code, the v21 snapshot and the test helpers**

```bash
cd packages/nimbus_data
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema dump lib/src/database/app_database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated/
ls drift_schemas test/generated
```
Expected: `drift_schemas/drift_schema_v21.json` and `test/generated/schema_v21.dart` exist; `test/generated/schema.dart` lists `const [1, 20, 21]`.

- [ ] **Step 7: Run to verify GREEN**

Run: `cd packages/nimbus_data && dart test test/migration_test.dart test/analytics/saved_views_test.dart`
Expected: PASS (all). The older saved-views tests still pass: `upsert` omits the new columns and the defaults fill them.

- [ ] **Step 8: Update the registry**

In `docs/phases/CONVENTIONS.md`, replace the Phase 3 row:

```markdown
| 3 — Analytics | v20–v29 | **v20, v21** | saved_views; v21 adds its period_type and period_count |
```

- [ ] **Step 9: Full gate, commit, fast-forward**

Commit message:
```
feat(schema): v21 -- a saved view remembers its period

Takes the schema lock (CONVENTIONS §2): this commit carries only the
column additions, the version bump, the migration step, the v21
snapshot, the migration tests and the registry row, and lands on main
before any saved-views feature code.

A stored QuerySpec has an absolute date range, so a view pinned as
"this month" would stay on the month it was pinned. period_type and
period_count hold the relative window instead; later commits store
the spec without dates.

The v1 path creates saved_views from its current declaration, which
already has the new columns, so the v21 step is an else-branch rather
than a second if -- adding them twice would fail on a duplicate column.
Both paths are verified to end on the fresh-install schema.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

- [ ] **Step 10: Land the lock on `main`**

```bash
git switch main && git merge --ff-only phase/3-saved-views && git switch phase/3-saved-views
git branch -a --list 'phase/*' 'feat/*' 'fix/*'
```
Expected: `main` now points at the schema commit. No other branch has unmerged work (`git log main..<branch>` empty for each listed branch other than this one); if one does, stop and report — it must rebase onto this commit before continuing. Pushing is left to the phase landing.

---

### Task 2: Analytics answers follow the data

Branch `fix/analytics-follow-data`, slug `analytics-follow-data`.

**Files:**
- Modify: `packages/nimbus_data/lib/src/analytics/analytics_engine.dart`
- Create: `packages/nimbus_data/test/analytics/engine_changes_test.dart`
- Modify: `app/lib/features/analytics/application/analytics_providers.dart`
- Modify: `app/test/features/analytics/analytics_providers_test.dart`

**Interfaces:**
- Produces: `Stream<void> AnalyticsEngine.changes()`; `analyticsResultProvider` becomes `FutureProvider.autoDispose.family<AnalyticsResult, QuerySpec>` (call sites unchanged).

- [ ] **Step 1: Write the failing data test**

Create `packages/nimbus_data/test/analytics/engine_changes_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import 'support/analytics_fixture.dart';

void main() {
  late AppDatabase db;
  late AnalyticsEngine engine;

  setUp(() async {
    db = openTestDatabase();
    await seedAnalyticsFixture(db);
    engine = AnalyticsEngine(db, calendar: const GregorianCalendar());
  });
  tearDown(() => db.close());

  /// How many times [AnalyticsEngine.changes] fires across [write].
  Future<int> firingsDuring(Future<void> Function() write) async {
    var count = 0;
    final subscription = engine.changes().listen((_) => count++);
    await pumpEventQueue();
    await write();
    await pumpEventQueue();
    await subscription.cancel();
    return count;
  }

  test('a transaction write fires', () async {
    expect(
      await firingsDuring(() => db.transactionsDao.setNote('t1', 'lunch')),
      greaterThan(0),
    );
  });

  test('a transaction-tag write fires', () async {
    expect(
      await firingsDuring(() => db.transactionsDao.setTags('t3', ['food'])),
      greaterThan(0),
    );
  });

  test('a category or tag write fires', () async {
    // Their paths are what subtree filters and rollups resolve against, so a
    // moved category changes answers without touching a transaction.
    expect(
      await firingsDuring(() async => db.markTablesUpdated({db.categories})),
      greaterThan(0),
    );
    expect(
      await firingsDuring(() async => db.markTablesUpdated({db.tags})),
      greaterThan(0),
    );
  });

  test('a settings write does not fire', () async {
    // Re-running every open chart for a theme change would be wasted work.
    expect(await firingsDuring(() => db.settingsDao.put('theme', 'dark')), 0);
  });
}
```

- [ ] **Step 2: Write the failing app tests**

In `app/test/features/analytics/analytics_providers_test.dart`, inside `main()` after `januaryTotal`, add the helper:

```dart
  /// Reads an answer while holding a listener, as a screen would. The
  /// provider is auto-disposed, so a bare read could see it released before
  /// its query finished.
  Future<AnalyticsResult> answer(QuerySpec spec) async {
    final subscription =
        container.listen(analyticsResultProvider(spec), (_, __) {});
    try {
      return await container.read(analyticsResultProvider(spec).future);
    } finally {
      subscription.close();
    }
  }
```

Replace the three `await container.read(analyticsResultProvider(<spec>).future)` calls (tests "a spec resolves to hand-computed totals", "the true total survives the trip to the UI layer", "an empty range yields no buckets rather than an error") with `await answer(<spec>)`. Then add at the end of `main()`:

```dart
  test('an answer re-runs when an expense is added', () async {
    // Before this, an answer was computed once and kept for the life of the
    // app: add an expense and every open chart went on showing the old total.
    await seedTransactions();
    final subscription =
        container.listen(analyticsResultProvider(januaryTotal), (_, __) {});
    addTearDown(subscription.close);
    expect(
      (await container.read(analyticsResultProvider(januaryTotal).future))
          .trueTotal,
      const Money(1750),
    );

    await TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman)
        .add(TransactionDraft(
      amount: const Money(100),
      direction: TxDirection.expense,
      categoryId: 'seed-food',
      occurredAtUtc: DateTime(2026, 1, 25, 10).toUtc(),
    ));
    // The write is announced asynchronously; let the notification land.
    await pumpEventQueue();

    expect(
      (await container.read(analyticsResultProvider(januaryTotal).future))
          .trueTotal,
      const Money(1850),
    );
  });

  test('an answer nobody watches is released', () async {
    // Every month anyone looked at used to stay in memory for good.
    final subscription =
        container.listen(analyticsResultProvider(januaryTotal), (_, __) {});
    await container.read(analyticsResultProvider(januaryTotal).future);
    subscription.close();
    await container.pump();

    expect(container.exists(analyticsResultProvider(januaryTotal)), isFalse);
  });
```

- [ ] **Step 3: Run to verify RED**

Run: `cd packages/nimbus_data && dart test test/analytics/engine_changes_test.dart`
Expected: FAIL to compile — `The method 'changes' isn't defined for the type 'AnalyticsEngine'`.

Run: `cd app && flutter test test/features/analytics/analytics_providers_test.dart`
Expected: FAIL — "re-runs" test: `Expected: Money(1850) Actual: Money(1750)`; "released" test: `Expected: false Actual: <true>`. The other tests pass.

- [ ] **Step 4: Tag**

Run: `git tag pre-analytics-follow-data`

- [ ] **Step 5: Implement `changes()`**

In `packages/nimbus_data/lib/src/analytics/analytics_engine.dart`, after `compile`:

```dart
  /// Fires whenever a table this engine reads is written.
  ///
  /// An answer is a snapshot; this is how a screen learns it went stale. The
  /// tables are every one a [QuerySpec] can reach: transactions and their tag
  /// links for the rows, categories and tags for the subtree paths a filter
  /// or a rollup resolves against. Settings and saved views are left out --
  /// neither changes what a spec means.
  Stream<void> changes() => _db
      .tableUpdates(TableUpdateQuery.onAllTables([
        _db.transactions,
        _db.transactionTags,
        _db.categories,
        _db.tags,
      ]))
      .map((_) {});
```

- [ ] **Step 6: Make the provider auto-dispose and self-invalidating**

In `app/lib/features/analytics/application/analytics_providers.dart`, replace `analyticsResultProvider` (keep the existing doc comment and append the last paragraph):

```dart
/// The answer to one question, keyed on the question itself.
///
/// The family key is a whole [QuerySpec], which works because the spec has
/// value equality -- the same property Phase 5 depends on to store one as a
/// goal's scope. Two widgets asking the same question therefore share one
/// query rather than each issuing their own.
///
/// Auto-disposed, and re-run whenever the engine reports a write to a table
/// it reads. It used to be neither: an answer was computed once and kept for
/// the life of the app, so a tab went on showing the total from before an
/// expense was added, and every month anyone looked at stayed in memory.
final analyticsResultProvider =
    FutureProvider.autoDispose.family<AnalyticsResult, QuerySpec>(
  (ref, spec) {
    final engine = ref.watch(analyticsEngineProvider);
    final changes = engine.changes().listen((_) => ref.invalidateSelf());
    ref.onDispose(changes.cancel);
    return engine.run(spec);
  },
);
```

- [ ] **Step 7: Run to verify GREEN**

Run both commands from Step 3. Expected: PASS.

- [ ] **Step 8: Full gate, commit, fast-forward**

Commit message:
```
fix: analytics answers follow the data

An answer was computed once per question and kept for the life of the
app: analyticsResultProvider was a plain FutureProvider.family that
nothing invalidated. Add an expense and every analytics tab went on
showing the old total until the calendar changed or the app restarted
-- and the dashboard, built next, would have shown stale cards the same
way. Every month anyone looked at also stayed in memory.

The engine now exposes changes(), which fires on writes to the four
tables a spec can reach (transactions, their tag links, categories,
tags), and each answer invalidates itself on it. The provider is
auto-dispose, so a month nobody is looking at is released.

Found while planning Phase 3 tasks 13-14; the operator chose to fix it
first, in its own commit.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task 3: The domain types a saved view needs

Branch `feat/saved-view-domain`, slug `saved-view-domain`.

**Files:**
- Create: `packages/nimbus_domain/lib/src/analytics/view_period.dart`
- Create: `packages/nimbus_domain/lib/src/analytics/saved_view_chart.dart`
- Modify: `packages/nimbus_domain/lib/src/analytics/query_filters.dart`, `query_spec.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (two exports, alphabetical)
- Create: `packages/nimbus_domain/test/analytics/view_period_test.dart`, `saved_view_chart_test.dart`
- Modify: `packages/nimbus_domain/test/analytics/query_spec_test.dart`

**Interfaces:**
- Produces:
  - `ViewPeriod(PeriodType type, int count)` (throws `ArgumentError` if `count < 1`); `ViewPeriod.fromStored(String type, int count)` (throws `FormatException`); `DateRange resolve(DateKey anchor, AppCalendar calendar, {int firstDayOfWeek})`; value equality.
  - `enum SavedViewChart { breakdown, trend, crossTab, hourOfDay, dayOfWeek, reflection }` with `static SavedViewChart parse(String raw)` (throws `FormatException`).
  - `QueryFilters withDateRange(DateRange? range)`, `QuerySpec withDateRange(DateRange? range)`.

- [ ] **Step 1: Write the failing tests**

`packages/nimbus_domain/test/analytics/view_period_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  const gregorian = GregorianCalendar();
  const jalali = JalaliCalendar();

  test('one month is the month containing the anchor', () {
    expect(
      ViewPeriod(PeriodType.month, 1).resolve(const DateKey(20260215), gregorian),
      DateRange(const DateKey(20260201), const DateKey(20260228)),
    );
  });

  test('six Gregorian months end with the anchor month and cross the year', () {
    expect(
      ViewPeriod(PeriodType.month, 6).resolve(const DateKey(20260215), gregorian),
      DateRange(const DateKey(20250901), const DateKey(20260228)),
    );
  });

  test('six Jalali months cross Nowruz in Jalali months, not Gregorian ones',
      () {
    // Anchored in Farvardin 1405, the window runs Aban 1404 .. Farvardin 1405.
    // Expected keys come from the calendar's own (separately tested)
    // conversion, so this asserts the window arithmetic, not the conversion.
    expect(
      ViewPeriod(PeriodType.month, 6).resolve(jalali.keyOf(1405, 1, 15), jalali),
      DateRange(jalali.keyOf(1404, 8, 1), jalali.keyOf(1405, 1, 31)),
    );
  });

  test('a week starts on the given first day', () {
    // 2026-09-27 is a Sunday.
    final week = ViewPeriod(PeriodType.week, 1);
    expect(
      week.resolve(const DateKey(20260927), gregorian,
          firstDayOfWeek: DateTime.saturday),
      DateRange(const DateKey(20260926), const DateKey(20261002)),
    );
    expect(
      week.resolve(const DateKey(20260927), gregorian,
          firstDayOfWeek: DateTime.monday),
      DateRange(const DateKey(20260921), const DateKey(20260927)),
    );
  });

  test('a count below one is a caller error', () {
    expect(() => ViewPeriod(PeriodType.month, 0), throwsArgumentError);
  });

  test('stored values parse, and bad ones are format errors', () {
    expect(ViewPeriod.fromStored('month', 6), ViewPeriod(PeriodType.month, 6));
    expect(() => ViewPeriod.fromStored('fortnight', 1),
        throwsA(isA<FormatException>()));
    // In stored data a zero count is corruption, not a caller's mistake.
    expect(() => ViewPeriod.fromStored('month', 0),
        throwsA(isA<FormatException>()));
  });

  test('periods compare by value', () {
    expect(ViewPeriod(PeriodType.month, 6), ViewPeriod(PeriodType.month, 6));
    expect(ViewPeriod(PeriodType.month, 6).hashCode,
        ViewPeriod(PeriodType.month, 6).hashCode);
    expect(ViewPeriod(PeriodType.month, 6),
        isNot(ViewPeriod(PeriodType.month, 1)));
  });
}
```

`packages/nimbus_domain/test/analytics/saved_view_chart_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  test('every chart kind round-trips through its stored name', () {
    for (final chart in SavedViewChart.values) {
      expect(SavedViewChart.parse(chart.name), chart);
    }
  });

  test('an unknown name is a format error, never a guess', () {
    expect(() => SavedViewChart.parse('sparkline'),
        throwsA(isA<FormatException>()));
  });
}
```

Append to `packages/nimbus_domain/test/analytics/query_spec_test.dart` inside `main()`:

```dart
  test('withDateRange replaces the range and keeps every other field', () {
    final full = QuerySpec(
      filters: QueryFilters(
        dateRange: DateRange(const DateKey(20260101), const DateKey(20260131)),
        direction: MoneyDirection.expense,
        categorySubtreePaths: const ['/food/'],
        tags: TagsAny(const ['/travel/']),
        paymentMethodIds: const ['card'],
        necessity: const {NecessityLevel.avoidable},
        satisfaction: const {SatisfactionLevel.regret},
        amountRange: AmountRange(minInclusive: const Money(100)),
        confirmedOnly: true,
        searchText: 'cafe',
      ),
      groupBy: GroupByCategory(1),
      aggregate: Aggregate.sum,
    );

    final undated = full.withDateRange(null);

    expect(undated.filters.dateRange, isNull);
    // Putting the range back must give the original: proof nothing else was
    // dropped on the way out.
    expect(undated.withDateRange(full.filters.dateRange), full);
  });
```

- [ ] **Step 2: Run to verify RED**

Run: `cd packages/nimbus_domain && dart test test/analytics/view_period_test.dart test/analytics/saved_view_chart_test.dart test/analytics/query_spec_test.dart`
Expected: FAIL to compile — `ViewPeriod`, `SavedViewChart`, `withDateRange` undefined.

- [ ] **Step 3: Tag**

Run: `git tag pre-saved-view-domain`

- [ ] **Step 4: Implement `ViewPeriod`**

`packages/nimbus_domain/lib/src/analytics/view_period.dart`:

```dart
import 'package:meta/meta.dart';

import '../calendar/calendar.dart';
import '../calendar/date_key.dart';
import 'period_boundaries.dart';

/// The window a saved view covers, relative to a date chosen when it is drawn.
///
/// A `QuerySpec`'s date range is absolute, so a view pinned as "this month"
/// would otherwise stay on the month it was pinned. This is the relative
/// half: the last [count] periods of [type], ending with the one containing
/// whatever date the dashboard is showing.
@immutable
final class ViewPeriod {
  ViewPeriod(this.type, this.count) {
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'must be at least 1');
    }
  }

  /// Parses the two stored columns.
  ///
  /// Throws [FormatException] for anything unusable, a count below one
  /// included: in stored data that is corruption rather than a caller's
  /// mistake, and the saved-views DAO turns format errors into an unreadable
  /// card instead of a crash.
  factory ViewPeriod.fromStored(String type, int count) {
    for (final value in PeriodType.values) {
      if (value.name == type) {
        if (count < 1) {
          throw FormatException('period count must be at least 1, got $count');
        }
        return ViewPeriod(value, count);
      }
    }
    throw FormatException('unknown period type "$type"');
  }

  final PeriodType type;
  final int count;

  /// The [count] periods of [type] ending with the one containing [anchor].
  DateRange resolve(
    DateKey anchor,
    AppCalendar calendar, {
    int firstDayOfWeek = PeriodBoundaries.defaultFirstDayOfWeek,
  }) {
    // Through PeriodBoundaries, so a card's range is cut by the same door as
    // the engine's bucketing and the trends tab.
    final newest = PeriodBoundaries.forPeriod(type, anchor, calendar,
        firstDayOfWeek: firstDayOfWeek);
    final oldest =
        count == 1 ? newest : calendar.shiftPeriod(newest, type, -(count - 1));
    return DateRange(oldest.startInclusive, newest.endInclusive);
  }

  @override
  bool operator ==(Object other) =>
      other is ViewPeriod && other.type == type && other.count == count;

  @override
  int get hashCode => Object.hash(type, count);

  @override
  String toString() => 'ViewPeriod(${type.name} x $count)';
}
```

- [ ] **Step 5: Implement `SavedViewChart`**

`packages/nimbus_domain/lib/src/analytics/saved_view_chart.dart`:

```dart
/// How a saved view is drawn.
///
/// Fixed by where the view was pinned from -- each tab and each patterns
/// chart pins its own kind -- so a spec is never paired with a chart that
/// cannot draw it. Stored by [name].
enum SavedViewChart {
  breakdown,
  trend,
  crossTab,
  hourOfDay,
  dayOfWeek,
  reflection;

  /// Throws [FormatException] on an unknown name rather than guessing: a
  /// guessed chart would draw another answer under the user's own name for
  /// this one.
  static SavedViewChart parse(String raw) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw FormatException('unknown saved-view chart "$raw"');
  }
}
```

- [ ] **Step 6: Add `withDateRange`**

In `query_filters.dart`, inside `QueryFilters` after `toJson`:

```dart
  /// This filter set with [range] as its date range; null removes it.
  ///
  /// The one copy operation the app needs: a saved view stores its spec
  /// without dates, and a card puts the dates back when it draws.
  QueryFilters withDateRange(DateRange? range) => QueryFilters(
        dateRange: range,
        direction: direction,
        categorySubtreePaths: categorySubtreePaths,
        tags: tags,
        paymentMethodIds: paymentMethodIds,
        necessity: necessity,
        satisfaction: satisfaction,
        amountRange: amountRange,
        confirmedOnly: confirmedOnly,
        searchText: searchText,
      );
```

In `query_spec.dart`, inside `QuerySpec` after `toJson` (add `import '../calendar/date_key.dart';`):

```dart
  /// This question over [range] instead; null makes it undated.
  QuerySpec withDateRange(DateRange? range) => QuerySpec(
        filters: filters.withDateRange(range),
        groupBy: groupBy,
        aggregate: aggregate,
      );
```

In `packages/nimbus_domain/lib/nimbus_domain.dart`, add (alphabetical):
```dart
export 'src/analytics/saved_view_chart.dart';
```
after `reflection_levels.dart`, and
```dart
export 'src/analytics/view_period.dart';
```
after `tag_filter.dart`.

- [ ] **Step 7: Run to verify GREEN**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 8: Full gate, commit, fast-forward**

Commit message:
```
feat: the domain types a saved view needs

ViewPeriod is the relative half of a pinned view -- "the last N periods
ending with the anchor's" -- resolved through PeriodBoundaries so a
card's range is cut by the same door as the engine's buckets. It is
tested across a year boundary in both calendars, because a six-month
window that crosses Nowruz is where a Gregorian assumption would hide.

SavedViewChart records how a view is drawn. parse throws on an unknown
name rather than guessing: a guessed chart would draw another answer
under the user's own name for this one.

QuerySpec.withDateRange is the one copy operation the feature needs: a
stored spec carries no dates, and a card puts them back.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task 4: Saved views read one row at a time and store no dates

Branch `feat/saved-views-read`, slug `saved-views-read`.

**Files:**
- Modify: `packages/nimbus_data/lib/src/analytics/saved_view.dart` (rewrite)
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` (`SavedViewsDao`)
- Modify: `packages/nimbus_data/lib/nimbus_data.dart` (export `saved_view.dart`)
- Modify: `packages/nimbus_data/test/analytics/saved_views_test.dart` (rewrite)
- Modify: `packages/nimbus_data/test/migration_test.dart` (one test)
- Modify: `packages/nimbus_data/test/analytics/query_plan_test.dart` (three tests)

**Interfaces:**
- Consumes: `ViewPeriod`, `SavedViewChart`, `QuerySpec.withDateRange` (Task 3); v21 columns (Task 1).
- Produces:
  - `sealed class SavedViewEntry { String id; String name; int sortOrder; }`
  - `final class SavedView extends SavedViewEntry { QuerySpec spec; ViewPeriod period; SavedViewChart chart; }`
  - `final class UnreadableSavedView extends SavedViewEntry { Object error; }`
  - `typedef NewSavedView = ({String id, String name, QuerySpec spec, ViewPeriod period, SavedViewChart chart});`
  - `SavedViewsDao.watchPinned() → Stream<List<SavedViewEntry>>`, `watchById(String id) → Stream<SavedViewEntry?>`, `create(List<NewSavedView> views) → Future<void>` (throws `ArgumentError` on a dated spec), `softDelete(String id)` (unchanged).
  - Removed: `upsert`, `byId`, `pinned`.

- [ ] **Step 1: Write the failing tests**

Replace `packages/nimbus_data/test/analytics/saved_views_test.dart` entirely:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';

const _spec = QuerySpec(
  filters: QueryFilters(direction: MoneyDirection.expense),
  groupBy: GroupByNone(),
  aggregate: Aggregate.sum,
);

NewSavedView _view(
  String id, {
  QuerySpec spec = _spec,
  ViewPeriod? period,
  SavedViewChart chart = SavedViewChart.breakdown,
}) =>
    (
      id: id,
      name: id,
      spec: spec,
      period: period ?? ViewPeriod(PeriodType.month, 1),
      chart: chart,
    );

/// A row written past the DAO, as corrupt or future-version data would be.
Future<void> _insertRaw(
  AppDatabase db, {
  required String id,
  required int sortOrder,
  String specJson =
      '{"filters":{},"groupBy":{"kind":"none"},"aggregate":"sum"}',
  String chartType = 'breakdown',
  String periodType = 'month',
}) =>
    db.customStatement(
      'INSERT INTO saved_views (id, name, spec_json, chart_type, period_type, '
      'period_count, pinned, sort_order, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, 1, 1, ?, 0, 0)',
      [id, id, specJson, chartType, periodType, sortOrder],
    );

void main() {
  late AppDatabase db;
  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  Future<List<String>> pinnedIds() async =>
      [for (final e in await db.savedViewsDao.watchPinned().first) e.id];

  test('the schema version is 21', () async {
    expect(db.schemaVersion, 21);
  });

  test('a view round-trips its spec, period and chart', () async {
    final spec = QuerySpec(
      filters: QueryFilters(
        direction: MoneyDirection.expense,
        tags: TagsAny(const ['/travel/']),
      ),
      groupBy: GroupByCategory(1),
      aggregate: Aggregate.sum,
    );
    await db.savedViewsDao.create([
      _view('v1',
          spec: spec,
          period: ViewPeriod(PeriodType.month, 6),
          chart: SavedViewChart.trend),
    ]);

    final loaded =
        (await db.savedViewsDao.watchPinned().first).single as SavedView;
    expect(loaded.name, 'v1');
    expect(loaded.spec, spec);
    expect(loaded.period, ViewPeriod(PeriodType.month, 6));
    expect(loaded.chart, SavedViewChart.trend);
  });

  test('a spec that still has a date range is refused and nothing is written',
      () async {
    final dated = _spec.withDateRange(
        DateRange(const DateKey(20260101), const DateKey(20260131)));

    await expectLater(
      db.savedViewsDao.create([_view('fine'), _view('dated', spec: dated)]),
      throwsArgumentError,
    );
    expect(await pinnedIds(), isEmpty);
  });

  test('new views go to the end, in the order given', () async {
    await db.savedViewsDao.create([_view('a'), _view('b')]);
    await db.savedViewsDao.create([_view('c')]);

    expect(await pinnedIds(), ['a', 'b', 'c']);
  });

  test('the pinned list is live', () async {
    final seen = <List<String>>[];
    final subscription = db.savedViewsDao
        .watchPinned()
        .listen((entries) => seen.add([for (final e in entries) e.id]));
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(seen, [<String>[]]);

    await db.savedViewsDao.create([_view('a')]);
    await pumpEventQueue();

    expect(seen.last, ['a']);
  });

  test('one unreadable row does not hide the others', () async {
    await db.savedViewsDao.create([_view('good')]);
    await _insertRaw(db, id: 'bad-json', specJson: '{not json', sortOrder: 10);
    await _insertRaw(db, id: 'bad-chart', chartType: 'sparkline', sortOrder: 11);
    await _insertRaw(db, id: 'bad-period', periodType: 'fortnight', sortOrder: 12);
    // Valid JSON of the wrong shape: a string where a bool belongs meets a
    // cast and throws a TypeError, not a FormatException.
    await _insertRaw(
      db,
      id: 'bad-type',
      specJson: '{"filters":{"confirmedOnly":"yes"},'
          '"groupBy":{"kind":"none"},"aggregate":"sum"}',
      sortOrder: 13,
    );

    final entries = await db.savedViewsDao.watchPinned().first;

    expect(entries.map((e) => e.id),
        ['good', 'bad-json', 'bad-chart', 'bad-period', 'bad-type']);
    expect(entries.first, isA<SavedView>());
    expect(entries.skip(1), everyElement(isA<UnreadableSavedView>()));
  });

  test('watchById follows a view and ends at null once it is removed',
      () async {
    await db.savedViewsDao.create([_view('v')]);
    expect((await db.savedViewsDao.watchById('v').first)?.id, 'v');

    await db.savedViewsDao.softDelete('v');

    expect(await db.savedViewsDao.watchById('v').first, isNull);
    expect(await pinnedIds(), isEmpty);
  });
}
```

In `packages/nimbus_data/test/migration_test.dart`, add `import 'package:nimbus_domain/nimbus_domain.dart';` and this test:

```dart
  test('a database upgraded from v1 takes a view through the DAO', () async {
    // Validating the shape is not the same as proving the table works.
    final db = AppDatabase(await verifier.startAt(1));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 21);

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
```

In `packages/nimbus_data/test/analytics/query_plan_test.dart`, add inside `main()`:

```dart
  test('the pinned-views query is served by its index', () async {
    // The same predicate and order as SavedViewsDao.watchPinned, which the
    // dashboard runs on every open.
    final rows = await db
        .customSelect('EXPLAIN QUERY PLAN SELECT * FROM saved_views '
            'WHERE deleted_at IS NULL AND pinned = 1 ORDER BY sort_order')
        .get();
    final plan = rows.map((r) => r.data['detail']).join(' | ');
    expect(plan, contains('idx_saved_views_pinned'), reason: 'plan: $plan');
  });

  test("the starter breakdown card's query uses the date index", () async {
    final plan = await planFor(QuerySpec(
      filters: QueryFilters(
        dateRange: DateRange(const DateKey(20260101), const DateKey(20260131)),
        direction: MoneyDirection.expense,
      ),
      groupBy: GroupByCategory(0),
      aggregate: Aggregate.sum,
    ));
    expect(plan, contains('idx_tx_date'), reason: 'plan: $plan');
    expect(plan, isNot(contains('SCAN transactions')), reason: 'plan: $plan');
  });

  test("the starter trend card's query uses the date index", () async {
    final plan = await planFor(QuerySpec(
      filters: QueryFilters(
        dateRange: DateRange(const DateKey(20250801), const DateKey(20260131)),
        direction: MoneyDirection.expense,
      ),
      groupBy: const GroupByPeriod(PeriodType.month),
      aggregate: Aggregate.sum,
    ));
    expect(plan, contains('idx_tx_date'), reason: 'plan: $plan');
    expect(plan, isNot(contains('SCAN transactions')), reason: 'plan: $plan');
  });
```

- [ ] **Step 2: Run to verify RED**

Run: `cd packages/nimbus_data && dart test test/analytics/saved_views_test.dart test/migration_test.dart test/analytics/query_plan_test.dart`
Expected: FAIL to compile — `NewSavedView`, `watchPinned`, `create`, `SavedView.period` undefined.
Note: the three query-plan tests characterise existing behaviour and are expected to **pass** once the file compiles. If either starter-card test fails, stop: that is a performance finding for task 15 — record the plan text in the task report rather than weakening the assertion.

- [ ] **Step 3: Tag**

Run: `git tag pre-saved-views-read`

- [ ] **Step 4: Rewrite the entry types**

Replace `packages/nimbus_data/lib/src/analytics/saved_view.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';

/// One dashboard row, readable or not.
///
/// Sealed so the dashboard has to say what it draws for a row it cannot
/// read. Rows are read one at a time for exactly this: a single malformed
/// row used to fail the whole list, and one bad card must never blank the
/// dashboard (screen contract §5.1).
sealed class SavedViewEntry {
  const SavedViewEntry({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final int sortOrder;
}

/// A stored view with its spec, period and chart parsed.
///
/// [spec] never carries a date range. [period] says which dates, relative to
/// wherever the dashboard is anchored, and the card puts them back.
final class SavedView extends SavedViewEntry {
  const SavedView({
    required super.id,
    required super.name,
    required super.sortOrder,
    required this.spec,
    required this.period,
    required this.chart,
  });

  final QuerySpec spec;
  final ViewPeriod period;
  final SavedViewChart chart;

  @override
  String toString() => 'SavedView($id, $name)';
}

/// A row whose spec, period or chart could not be parsed.
///
/// Carries the error instead of a substitute view: a default chart drawn
/// under the user's own name for something else looks like it worked, which
/// is worse than an honest "cannot read this".
final class UnreadableSavedView extends SavedViewEntry {
  const UnreadableSavedView({
    required super.id,
    required super.name,
    required super.sortOrder,
    required this.error,
  });

  final Object error;

  @override
  String toString() => 'UnreadableSavedView($id, $error)';
}

/// What `SavedViewsDao.create` writes.
typedef NewSavedView = ({
  String id,
  String name,
  QuerySpec spec,
  ViewPeriod period,
  SavedViewChart chart,
});
```

In `packages/nimbus_data/lib/nimbus_data.dart` add after `group_expressions.dart`:
```dart
export 'src/analytics/saved_view.dart';
```

- [ ] **Step 5: Rewrite the DAO's read side and `create`**

In `app_database.dart`, replace the whole `SavedViewsDao` class:

```dart
/// Named `QuerySpec`s pinned to the dashboard.
///
/// Reads parse each row on its own, here, so there is one place that decides
/// what a malformed row means -- an [UnreadableSavedView], never a guessed
/// default -- and no caller can forget to look.
class SavedViewsDao {
  SavedViewsDao(this._db);

  final AppDatabase _db;

  /// Pinned views in the order the user arranged them, live.
  Stream<List<SavedViewEntry>> watchPinned() => (_db.select(_db.savedViews)
        ..where((t) => t.deletedAt.isNull())
        ..where((t) => t.pinned.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch()
      .map((rows) => rows.map(_parse).toList());

  /// One live view, or null once it is removed.
  Stream<SavedViewEntry?> watchById(String id) => (_db.select(_db.savedViews)
        ..where((t) => t.id.equals(id))
        ..where((t) => t.deletedAt.isNull()))
      .watchSingleOrNull()
      .map((row) => row == null ? null : _parse(row));

  /// Pins [views] at the end of the dashboard, in the order given, as one
  /// transaction: the starter cards arrive together or not at all.
  ///
  /// A spec that still carries a date range is refused before anything is
  /// written. The period lives in its own columns; stripping the dates here
  /// would hide the caller's bug instead of reporting it.
  Future<void> create(List<NewSavedView> views) async {
    for (final view in views) {
      if (view.spec.filters.dateRange != null) {
        throw ArgumentError.value(
          view.spec,
          'spec',
          'a saved view stores its period apart from its spec, so the spec '
              'must carry no date range -- strip it with withDateRange(null)',
        );
      }
    }
    await _db.transaction(() async {
      // Soft-deleted rows count toward the maximum, so a removal that is
      // later undone gets its old slot back instead of sharing one.
      final highest = _db.savedViews.sortOrder.max();
      final top = await (_db.selectOnly(_db.savedViews)..addColumns([highest]))
          .map((row) => row.read(highest))
          .getSingle();
      var next = (top ?? -1) + 1;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final view in views) {
        await _db.into(_db.savedViews).insert(SavedViewsCompanion.insert(
              id: view.id,
              name: view.name,
              specJson: jsonEncode(view.spec.toJson()),
              chartType: view.chart.name,
              periodType: Value(view.period.type.name),
              periodCount: Value(view.period.count),
              pinned: const Value(true),
              sortOrder: Value(next++),
              createdAt: now,
              updatedAt: now,
            ));
      }
    });
  }

  Future<void> softDelete(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (_db.update(_db.savedViews)..where((t) => t.id.equals(id)))
        .write(SavedViewsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
  }

  /// Parses one stored row.
  ///
  /// Only what malformed stored data can throw becomes an unreadable card:
  /// [FormatException] from the parsers, [TypeError] from a JSON value of the
  /// wrong type meeting a cast, [ArgumentError] from a value type rejecting
  /// its fields. Anything else is a bug in this code and surfaces as one.
  static SavedViewEntry _parse(SavedViewRow row) {
    try {
      final decoded = jsonDecode(row.specJson);
      if (decoded is! Map<String, Object?>) {
        throw FormatException('spec is not a JSON object', row.specJson);
      }
      return SavedView(
        id: row.id,
        name: row.name,
        sortOrder: row.sortOrder,
        spec: QuerySpec.fromJson(decoded),
        period: ViewPeriod.fromStored(row.periodType, row.periodCount),
        chart: SavedViewChart.parse(row.chartType),
      );
    } on Object catch (error) {
      if (error is! FormatException &&
          error is! TypeError &&
          error is! ArgumentError) {
        rethrow;
      }
      return UnreadableSavedView(
        id: row.id,
        name: row.name,
        sortOrder: row.sortOrder,
        error: error,
      );
    }
  }
}
```

- [ ] **Step 6: Run to verify GREEN**

Run the Step 2 command. Expected: PASS. Then `grep -rn "upsert\|savedViewsDao.byId\|savedViewsDao.pinned" packages app --include=*.dart` — Expected: no hits.

- [ ] **Step 7: Full gate, commit, fast-forward**

Commit message:
```
feat: saved views read one row at a time and store no dates

The dashboard reads its cards through watchPinned, a live stream, so a
view pinned from another tab appears without a refresh. Each row is
parsed on its own: a malformed spec, an unknown chart or period becomes
an UnreadableSavedView carrying the error instead of failing the whole
list -- one bad row used to blank every card, which the screen contract
forbids.

create takes a list and writes it in one transaction at the end of the
dashboard, so the two starter cards arrive together or not at all. A
spec that still carries a date range is refused before anything is
written: the period lives in its own columns now, and stripping the
dates silently would hide the caller's bug.

upsert, byId and pinned go. None had a caller outside its own tests,
and upsert reset created_at on every save, a rename included.

Query-plan checks now cover the pinned-views query and both starter
cards' queries -- the dashboard's hot path.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task 5: Saved views can be renamed, reordered and restored

Branch `feat/saved-views-edit`, slug `saved-views-edit`.

**Files:**
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` (`SavedViewsDao`)
- Modify: `packages/nimbus_data/test/analytics/saved_views_test.dart`

**Interfaces:**
- Produces: `rename(String id, String name)`, `reorder(List<String> ids)`, `restore(String id)`; `softDelete` now throws `StateError` when no row matched, as do the three new methods.

- [ ] **Step 1: Write the failing tests**

Add to `saved_views_test.dart` (top: `import 'package:drift/drift.dart' show Variable;`), a helper inside `main()`:

```dart
  Future<({int created, int updated})> stamps(String id) async {
    final row = await db.customSelect(
      'SELECT created_at, updated_at FROM saved_views WHERE id = ?',
      variables: [Variable.withString(id)],
    ).getSingle();
    return (
      created: row.read<int>('created_at'),
      updated: row.read<int>('updated_at'),
    );
  }
```

and the tests:

```dart
  test('rename changes the name and keeps the creation time', () async {
    await db.savedViewsDao.create([_view('v')]);
    final before = await stamps('v');
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await db.savedViewsDao.rename('v', 'Food watch');

    expect((await db.savedViewsDao.watchPinned().first).single.name,
        'Food watch');
    final after = await stamps('v');
    expect(after.created, before.created);
    expect(after.updated, greaterThan(before.updated));
  });

  test('reorder rewrites the order and keeps creation times', () async {
    await db.savedViewsDao.create([_view('a'), _view('b'), _view('c')]);
    final before = await stamps('a');

    await db.savedViewsDao.reorder(['c', 'a', 'b']);

    expect(await pinnedIds(), ['c', 'a', 'b']);
    expect((await stamps('a')).created, before.created);
  });

  test('reorder is all or nothing', () async {
    await db.savedViewsDao.create([_view('a'), _view('b')]);

    await expectLater(
        db.savedViewsDao.reorder(['b', 'missing', 'a']), throwsStateError);

    expect(await pinnedIds(), ['a', 'b']);
  });

  test('restore brings a removed view back in its old place', () async {
    await db.savedViewsDao.create([_view('a'), _view('b'), _view('c')]);
    await db.savedViewsDao.softDelete('b');
    expect(await pinnedIds(), ['a', 'c']);

    await db.savedViewsDao.restore('b');

    expect(await pinnedIds(), ['a', 'b', 'c']);
  });

  test('a write that matches no view says so', () async {
    // A rename that renamed nothing is a caller holding a stale id;
    // reporting success for it would be a silent failure.
    await expectLater(db.savedViewsDao.rename('nope', 'x'), throwsStateError);
    await expectLater(db.savedViewsDao.softDelete('nope'), throwsStateError);
    await expectLater(db.savedViewsDao.restore('nope'), throwsStateError);
  });

  test('the live list follows rename, reorder, removal and restore',
      () async {
    await db.savedViewsDao.create([_view('a'), _view('b')]);
    final seen = <List<String>>[];
    final subscription = db.savedViewsDao.watchPinned().listen(
        (entries) => seen.add([for (final e in entries) '${e.id}:${e.name}']));
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await db.savedViewsDao.rename('a', 'A');
    await pumpEventQueue();
    expect(seen.last, ['a:A', 'b:b']);

    await db.savedViewsDao.reorder(['b', 'a']);
    await pumpEventQueue();
    expect(seen.last, ['b:b', 'a:A']);

    await db.savedViewsDao.softDelete('b');
    await pumpEventQueue();
    expect(seen.last, ['a:A']);

    await db.savedViewsDao.restore('b');
    await pumpEventQueue();
    expect(seen.last, ['b:b', 'a:A']);
  });
```

- [ ] **Step 2: Run to verify RED**

Run: `cd packages/nimbus_data && dart test test/analytics/saved_views_test.dart`
Expected: FAIL to compile — `rename`, `reorder`, `restore` undefined.

- [ ] **Step 3: Tag**

Run: `git tag pre-saved-views-edit`

- [ ] **Step 4: Implement**

In `SavedViewsDao`, replace `softDelete` and add, before `_parse`:

```dart
  Future<void> rename(String id, String name) async {
    final written =
        await (_db.update(_db.savedViews)..where((t) => t.id.equals(id)))
            .write(SavedViewsCompanion(
      name: Value(name),
      updatedAt: Value(_now()),
    ));
    _expectOne(written, id);
  }

  /// Makes [ids] the dashboard's order: each view's position in the list
  /// becomes its sort order. One transaction -- a half-applied order would
  /// leave two cards claiming the same slot. Callers pass every pinned view.
  Future<void> reorder(List<String> ids) => _db.transaction(() async {
        final now = _now();
        for (final (index, id) in ids.indexed) {
          final written =
              await (_db.update(_db.savedViews)..where((t) => t.id.equals(id)))
                  .write(SavedViewsCompanion(
            sortOrder: Value(index),
            updatedAt: Value(now),
          ));
          _expectOne(written, id);
        }
      });

  Future<void> softDelete(String id) async {
    final now = _now();
    final written =
        await (_db.update(_db.savedViews)..where((t) => t.id.equals(id)))
            .write(SavedViewsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
    _expectOne(written, id);
  }

  /// The undo behind "Remove". The view's sort order was never reused
  /// (see [create]), so it returns to the place it left.
  Future<void> restore(String id) async {
    final written =
        await (_db.update(_db.savedViews)..where((t) => t.id.equals(id)))
            .write(SavedViewsCompanion(
      deletedAt: const Value(null),
      updatedAt: Value(_now()),
    ));
    _expectOne(written, id);
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  /// A write that matched nothing is a caller holding a stale id. Saying so
  /// beats reporting success for a rename that renamed nothing.
  static void _expectOne(int written, String id) {
    if (written != 1) throw StateError('no saved view "$id"');
  }
```

- [ ] **Step 5: Run to verify GREEN**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 6: Full gate, commit, fast-forward**

Commit message:
```
feat: saved views can be renamed, reordered and restored

reorder rewrites every given view's position in one transaction; a
half-applied order would leave two cards claiming the same slot.
restore is the undo behind "Remove", and a removed view comes back in
its old place because its sort order is never reused.

Every write now throws when no row matched. A rename that renamed
nothing is a caller holding a stale id, and reporting success for it
would be a silent failure.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task 6: Each pattern chart and the trend series stand alone (refactor)

Branch `refactor/standalone-charts`, slug `standalone-charts`. Behaviour-neutral: no new tests; the existing patterns and trends tests are the guard.

**Files:**
- Modify: `app/lib/features/analytics/presentation/widgets/patterns_body.dart`
- Modify: `app/lib/features/analytics/presentation/widgets/trends_body.dart`

**Interfaces:**
- Produces: `HourOfDayChart({required AnalyticsResult result, required MoneyFormatter formatter})`, `DayOfWeekChart({required AnalyticsResult result, required int firstDayOfWeek, required MoneyFormatter formatter})`, `ReflectionMatrix({required AnalyticsResult result, required MoneyFormatter formatter})` (all public, same keys as before); `List<Money> trendAmounts(AnalyticsResult result, List<DateRange> periods)`.

- [ ] **Step 1: Confirm the guard is green first**

Run: `cd app && flutter test test/features/analytics/patterns_screen_test.dart test/features/analytics/trends_screen_test.dart`
Expected: PASS. (Refactor rule: green before, green after.)

- [ ] **Step 2: Tag**

Run: `git tag pre-standalone-charts`

- [ ] **Step 3: Split `patterns_body.dart`**

Keep the imports. Replace `PatternsBody.build` from `final theme = Theme.of(context);` to the end of the `ListView` with:

```dart
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(NimbusTokens.space4),
      children: [
        Text(l10n.patternsHourOfDay, style: theme.textTheme.titleMedium),
        const SizedBox(height: NimbusTokens.space2),
        HourOfDayChart(result: byHour, formatter: formatter),
        const SizedBox(height: NimbusTokens.space6),
        Text(l10n.patternsDayOfWeek, style: theme.textTheme.titleMedium),
        const SizedBox(height: NimbusTokens.space2),
        DayOfWeekChart(
          result: byWeekday,
          firstDayOfWeek: firstDayOfWeek,
          formatter: formatter,
        ),
        const SizedBox(height: NimbusTokens.space6),
        Text(l10n.patternsReflection, style: theme.textTheme.titleMedium),
        const SizedBox(height: NimbusTokens.space2),
        ReflectionMatrix(result: reflection, formatter: formatter),
      ],
    );
  }
}
```

Delete the old `_barData` and `_weekdayName` methods from `PatternsBody`, and add after the class:

```dart
/// Spending by hour of day, every hour present.
///
/// Public so the dashboard can pin and draw it on its own.
class HourOfDayChart extends StatelessWidget {
  const HourOfDayChart({
    super.key,
    required this.result,
    required this.formatter,
  });

  final AnalyticsResult result;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context) {
    // Every hour gets a bar, including the quiet ones. The engine only returns
    // buckets that matched rows, so plotting those directly would put three
    // bars side by side and imply spending happens at every hour of the day.
    final hours = <int, Money>{
      for (final bucket in result.buckets)
        if (bucket.key case HourOfDayKey(:final hour)) hour: bucket.money,
    };
    return SizedBox(
      height: 180,
      child: BarChart(
        key: const Key('patterns-hour-chart'),
        _barData(
          context,
          formatter,
          [
            for (var hour = 0; hour < 24; hour++)
              (hour, hours[hour] ?? Money.zero),
          ],
          // Twenty-four labels do not fit; the shape is the message here and
          // the exact hour is available by touch.
          labelEvery: 6,
          labelOf: (hour) => '$hour',
        ),
      ),
    );
  }
}

/// Spending by day of week, in the order the user's week runs.
class DayOfWeekChart extends StatelessWidget {
  const DayOfWeekChart({
    super.key,
    required this.result,
    required this.firstDayOfWeek,
    required this.formatter,
  });

  final AnalyticsResult result;
  final int firstDayOfWeek;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final weekdays = <int, Money>{
      for (final bucket in result.buckets)
        if (bucket.key case DayOfWeekKey(:final weekday)) weekday: bucket.money,
    };
    final order = weekdaysFrom(firstDayOfWeek);
    return SizedBox(
      height: 180,
      child: BarChart(
        key: const Key('patterns-weekday-chart'),
        _barData(
          context,
          formatter,
          [
            for (final (index, weekday) in order.indexed)
              (index, weekdays[weekday] ?? Money.zero),
          ],
          labelEvery: 1,
          labelOf: (index) => _weekdayName(l10n, order[index]),
          labelKeyPrefix: 'patterns-weekday-label',
        ),
      ),
    );
  }
}

BarChartData _barData(
  BuildContext context,
  MoneyFormatter formatter,
  List<(int, Money)> bars, {
  required int labelEvery,
  required String Function(int) labelOf,
  String? labelKeyPrefix,
}) {
  final theme = Theme.of(context);
  return BarChartData(
    barGroups: [
      for (final (x, amount) in bars)
        BarChartGroupData(
          x: x,
          barRods: [
            BarChartRodData(
              toY: amount.minorUnits.toDouble(),
              color: theme.colorScheme.primary,
              width: 6,
            ),
          ],
        ),
    ],
    titlesData: FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          getTitlesWidget: (value, meta) => Text(
            trendsAxisLabel(value, formatter),
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
            return Text(
              labelOf(index),
              key: labelKeyPrefix == null ? null : Key('$labelKeyPrefix-$index'),
              style: theme.textTheme.labelSmall,
            );
          },
        ),
      ),
    ),
  );
}

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

Rename `_ReflectionMatrix` → `ReflectionMatrix` (class name and constructor), give the constructor `super.key`, and change its doc comment's first line to `/// Necessity down, satisfaction across, with the unset row and column kept. Public so the dashboard can draw it on its own.` Its body is unchanged.

- [ ] **Step 4: Extract `trendAmounts` in `trends_body.dart`**

Add above `class TrendsBody`:

```dart
/// One amount per period in [periods], in order -- zero for a quiet period.
///
/// The engine returns buckets only for periods that matched rows, so this
/// re-indexes them against the periods actually asked for. Plotting the
/// buckets directly would draw a line straight from March to June and
/// present the quiet months as a trend rather than as zero. Public so a
/// trend card can plot the same series.
List<Money> trendAmounts(AnalyticsResult result, List<DateRange> periods) {
  final found = <int, Money>{
    for (final bucket in result.buckets)
      if (bucket.key case PeriodKey(:final range))
        range.startInclusive.value: bucket.money,
  };
  return [
    for (final period in periods) found[period.startInclusive.value] ?? Money.zero,
  ];
}
```

Delete `TrendsBody._byPeriod` (getter and its doc comment) and change `final amounts = _byPeriod;` to `final amounts = trendAmounts(result, view.periods);`.

- [ ] **Step 5: Run to verify still GREEN**

Run the Step 1 command. Expected: PASS, same counts as Step 1.

- [ ] **Step 6: Full gate, commit, fast-forward**

Commit message:
```
refactor: each pattern chart and the trend series stand alone

The dashboard pins and draws the hour, weekday and reflection charts one
at a time, so they become public widgets instead of three sections of
one list. The trend body's "one amount per period, zero for the quiet
ones" step becomes a function a trend card can reuse. No behaviour
changes; the existing patterns and trends tests pass unchanged.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task 7: Pin what a tab shows

Branch `feat/pin-views`, slug `pin-views`.

**Files:**
- Create: `app/lib/features/analytics/data/pin_request.dart`
- Create: `app/lib/features/analytics/data/saved_views_repository.dart`
- Create: `app/lib/features/analytics/application/saved_view_providers.dart`
- Create: `app/lib/features/analytics/presentation/widgets/view_name_sheet.dart`
- Create: `app/lib/features/analytics/presentation/widgets/pin_button.dart`
- Modify: `app/lib/features/analytics/presentation/analytics_screen.dart`
- Modify: `app/lib/features/analytics/presentation/widgets/patterns_body.dart`
- Modify: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_fa.arb` (+ `flutter gen-l10n`)
- Create: `app/test/features/analytics/support/dashboard_fixture.dart`
- Create: `app/test/features/analytics/saved_views_repository_test.dart`
- Create: `app/test/features/analytics/pin_view_test.dart`

**Interfaces:**
- Consumes: `SavedViewsDao.create`, `NewSavedView` (Task 4); `ViewPeriod`, `SavedViewChart`, `withDateRange` (Task 3); `HourOfDayChart` etc. (Task 6).
- Produces:
  - `PinRequest.fromShown({required String name, required QuerySpec shownSpec, required ViewPeriod period, required SavedViewChart chart})`; fields `name`, `spec` (undated), `period`, `chart`; `PinRequest named(String name)`.
  - `SavedViewsRepository(SavedViewsDao)`: `Future<List<String>> pin(List<PinRequest> requests)`.
  - `savedViewsRepositoryProvider`.
  - `Future<String?> showViewNameSheet(BuildContext, {required String title, required String initialName, String? note})`.
  - `PinButton({required PinRequest request})` — key `pin-<chart.name>`.
  - `String coverageOf(AppLocalizations l10n, ViewPeriod period)`.
  - Test fixture (see Step 1).

- [ ] **Step 1: Write the shared fixture**

`app/test/features/analytics/support/dashboard_fixture.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/transactions/data/transaction_draft.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';

import '../../../support/harness.dart';

/// Food (Groceries, Dining) and Transport, plus Uncategorized.
Future<AppDatabase> categorisedDb() async {
  final db = AppDatabase.openInMemory();
  await CategorySeeder(db).seedIfEmpty(
    roots: const [
      SeedCategoryNode(id: 'seed-food', name: 'Food', children: [
        SeedCategoryNode(id: 'seed-groceries', name: 'Groceries'),
        SeedCategoryNode(id: 'seed-dining', name: 'Dining'),
      ]),
      SeedCategoryNode(id: 'seed-transport', name: 'Transport'),
    ],
    uncategorizedName: 'Uncategorized',
  );
  return db;
}

/// A day in the month the dashboard opens on: the Jalali month containing
/// today, because Jalali is the app's default calendar.
DateTime dayInThisMonth(int offset) {
  const calendar = JalaliCalendar();
  final period = calendar.periodContaining(
    DateKey.fromDateTime(DateTime.now()),
    PeriodType.month,
  );
  final start = period.startInclusive.toDateTime();
  return DateTime(start.year, start.month, start.day, 10)
      .add(Duration(days: offset));
}

/// Groceries 1000, Dining 500, Transport 250: 1750 this month.
/// Returns the three transactions' ids in that order.
Future<List<String>> seedSpending(
  AppDatabase db, {
  List<String> diningTags = const [],
  List<String> transportTags = const [],
}) async {
  final repo =
      TransactionRepository(db.transactionsDao, db.tagsDao, Currency.toman);
  Future<String> add(String category, int amount, int day, List<String> tags) async =>
      (await repo.add(TransactionDraft(
        amount: Money(amount),
        direction: TxDirection.expense,
        categoryId: category,
        occurredAtUtc: dayInThisMonth(day).toUtc(),
        tagIds: tags,
      )))
          .id;

  return [
    await add('seed-groceries', 1000, 1, const []),
    await add('seed-dining', 500, 2, diningTags),
    await add('seed-transport', 250, 3, transportTags),
  ];
}

/// A realistic phone viewport, 360x800 logical. The default test surface is
/// shorter than any phone this ships on, and lists do not build below it.
void usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Pumps the app on [db] at phone size and opens Analytics.
Future<void> openAnalytics(
  WidgetTester tester,
  AppDatabase db, {
  Locale locale = const Locale('en'),
}) async {
  usePhoneViewport(tester);
  await pumpApp(tester, database: db, locale: locale);
  await tester.tap(find.descendant(
    of: find.byKey(const Key('nav-bar')),
    matching: find.byIcon(Icons.insights_outlined),
  ));
  await tester.pumpAndSettle();
}

/// Switches Analytics to the tab keyed [tabKey]. The tab bar scrolls, so the
/// tab is brought into view first -- a tap outside the viewport lands on
/// nothing and silently leaves the current tab showing.
Future<void> showTab(WidgetTester tester, String tabKey) async {
  final tab = find.byKey(Key(tabKey));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

/// Persian digits with the U+066C separator: the app's default settings
/// locale is fa, and money follows settings, not the widget-tree locale.
const total1750 = '۱٬۷۵۰'; // 1,750
const total1000 = '۱٬۰۰۰'; // 1,000
const total750 = '۷۵۰'; // 750

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

/// A stored view as the database holds it.
typedef StoredView = ({
  String id,
  String name,
  String chart,
  String periodType,
  int periodCount,
  Map<String, Object?> spec,
});

/// Live saved views in dashboard order, read with a plain query: awaiting a
/// drift stream inside a widget test's fake clock can stall.
Future<List<StoredView>> storedViews(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT id, name, chart_type, period_type, period_count, '
          'spec_json FROM saved_views WHERE deleted_at IS NULL '
          'ORDER BY sort_order')
      .get();
  return [
    for (final row in rows)
      (
        id: row.read<String>('id'),
        name: row.read<String>('name'),
        chart: row.read<String>('chart_type'),
        periodType: row.read<String>('period_type'),
        periodCount: row.read<int>('period_count'),
        spec: jsonDecode(row.read<String>('spec_json')) as Map<String, Object?>,
      ),
  ];
}
```

- [ ] **Step 2: Write the failing tests**

`app/test/features/analytics/saved_views_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/analytics/data/pin_request.dart';
import 'package:nimbustats/features/analytics/data/saved_views_repository.dart';

import 'support/dashboard_fixture.dart';

void main() {
  late AppDatabase db;
  late SavedViewsRepository repository;
  setUp(() {
    db = AppDatabase.openInMemory();
    repository = SavedViewsRepository(db.savedViewsDao);
  });
  tearDown(() => db.close());

  final shown = QuerySpec(
    filters: QueryFilters(
      dateRange: DateRange(const DateKey(20260901), const DateKey(20260930)),
      direction: MoneyDirection.expense,
    ),
    groupBy: GroupByCategory(0),
    aggregate: Aggregate.sum,
  );

  PinRequest request(String name) => PinRequest.fromShown(
        name: name,
        shownSpec: shown,
        period: ViewPeriod(PeriodType.month, 1),
        chart: SavedViewChart.breakdown,
      );

  test("a pin request drops the tab's dates and keeps the question", () {
    final pinned = request('Food');
    expect(pinned.spec.filters.dateRange, isNull);
    expect(pinned.spec.withDateRange(shown.filters.dateRange), shown);
  });

  test('pinning trims the name and appends in order', () async {
    final ids = await repository.pin([request('  Food  '), request('Rent')]);

    final views = await storedViews(db);
    expect(views.map((v) => v.id), ids);
    expect(views.map((v) => v.name), ['Food', 'Rent']);
  });

  test('a blank name is refused and nothing is written', () async {
    await expectLater(
        repository.pin([request('Food'), request('   ')]), throwsArgumentError);
    expect(await storedViews(db), isEmpty);
  });
}
```

`app/test/features/analytics/pin_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';

import 'support/dashboard_fixture.dart';

Future<void> pinAndSave(WidgetTester tester, String pinKey) async {
  // The previous pin's "Pinned" snackbar sits over the bottom of the screen
  // for four seconds; a pin scrolled into view there would miss the tap.
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
      .clearSnackBars();
  await tester.pumpAndSettle();
  final pin = find.byKey(Key(pinKey));
  await tester.ensureVisible(pin);
  await tester.pumpAndSettle();
  await tester.tap(pin);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('view-name-save')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pinning a drilled-in breakdown saves it under the crumb name',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openAnalytics(tester, db);
    await showTab(tester, 'analytics-tab-breakdown');
    await tester.tap(find.byKey(const Key('breakdown-row-seed-food')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pin-breakdown')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('view-name-field')))
          .controller!
          .text,
      'Food',
    );
    // The sheet says what the card will cover before anything is saved.
    expect(find.text('Shows whichever month the dashboard is on'),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('view-name-save')));
    await tester.pumpAndSettle();

    final views = await storedViews(db);
    final foodPath = (await db.categoriesDao.byId('seed-food'))!.path;
    expect(views, hasLength(1));
    expect(views.single.name, 'Food');
    expect(views.single.chart, 'breakdown');
    expect((views.single.periodType, views.single.periodCount), ('month', 1));
    final filters = views.single.spec['filters']! as Map<String, Object?>;
    expect(filters['categorySubtreePaths'], [foodPath]);
    expect(filters.containsKey('dateRange'), isFalse);
    expect(find.text('Pinned to the dashboard'), findsOneWidget);
  });

  testWidgets('each tab and pattern chart pins its own kind of chart',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openAnalytics(tester, db);

    await showTab(tester, 'analytics-tab-trends');
    await pinAndSave(tester, 'pin-trend');
    await showTab(tester, 'analytics-tab-crosstab');
    await pinAndSave(tester, 'pin-crossTab');
    await showTab(tester, 'analytics-tab-patterns');
    await pinAndSave(tester, 'pin-hourOfDay');
    await pinAndSave(tester, 'pin-dayOfWeek');
    await pinAndSave(tester, 'pin-reflection');

    final views = await storedViews(db);
    expect(views.map((v) => v.chart),
        ['trend', 'crossTab', 'hourOfDay', 'dayOfWeek', 'reflection']);
    expect(views.first.name, 'Last 6 months');
    expect(views.first.periodCount, 6);
    expect(views.skip(1).map((v) => v.periodCount), everyElement(1));
  });

  testWidgets('a blank name cannot be saved', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await openAnalytics(tester, db);
    await showTab(tester, 'analytics-tab-breakdown');
    await tester.tap(find.byKey(const Key('pin-breakdown')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('view-name-field')), '   ');
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('view-name-save')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('dismissing the sheet pins nothing', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await openAnalytics(tester, db);
    await showTab(tester, 'analytics-tab-breakdown');
    await tester.tap(find.byKey(const Key('pin-breakdown')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await storedViews(db), isEmpty);
  });
}
```

- [ ] **Step 3: Run to verify RED**

Run: `cd app && flutter test test/features/analytics/saved_views_repository_test.dart test/features/analytics/pin_view_test.dart`
Expected: FAIL to compile — `pin_request.dart` / `saved_views_repository.dart` do not exist.

- [ ] **Step 4: Tag**

Run: `git tag pre-pin-views`

- [ ] **Step 5: Strings**

First confirm none exist: `grep -c "\"pinNameLastMonths\"\|\"pinNameSpendingByCategory\"\|\"pinToDashboard\"\|\"pinnedToDashboard\"\|\"viewCoversCurrentMonth\"\|\"viewCoversLastMonths\"\|\"viewNameLabel\"" app/lib/l10n/app_en.arb` → `0`.

Add to `app_en.arb` (alphabetical positions):
```json
  "pinNameLastMonths": "Last {count} months",
  "@pinNameLastMonths": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "pinNameSpendingByCategory": "Spending by category",
  "pinToDashboard": "Pin to dashboard",
  "pinnedToDashboard": "Pinned to the dashboard",
  "viewCoversCurrentMonth": "Shows whichever month the dashboard is on",
  "viewCoversLastMonths": "Shows {count} months, ending with the dashboard's month",
  "@viewCoversLastMonths": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "viewNameLabel": "Name",
```
Add to `app_fa.arb` (alphabetical positions):
```json
  "pinNameLastMonths": "{count} ماه اخیر",
  "pinNameSpendingByCategory": "هزینه‌ها به تفکیک دسته",
  "pinToDashboard": "سنجاق به داشبورد",
  "pinnedToDashboard": "به داشبورد سنجاق شد",
  "viewCoversCurrentMonth": "همان ماهی را نشان می‌دهد که داشبورد روی آن است",
  "viewCoversLastMonths": "{count} ماه را تا ماهِ داشبورد نشان می‌دهد",
  "viewNameLabel": "نام",
```
Run: `cd app && flutter gen-l10n`.

- [ ] **Step 6: `PinRequest` and the repository**

`app/lib/features/analytics/data/pin_request.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';

/// What a pin saves: a name, the question a tab is asking without its dates,
/// the window it covers, and how to draw it.
final class PinRequest {
  /// From the spec a tab is showing. Its date range is dropped here, in one
  /// place: the tab's range is the month on screen, while a pinned view means
  /// "the dashboard's month", which [period] carries.
  PinRequest.fromShown({
    required this.name,
    required QuerySpec shownSpec,
    required this.period,
    required this.chart,
  }) : spec = shownSpec.withDateRange(null);

  const PinRequest._(this.name, this.spec, this.period, this.chart);

  final String name;
  final QuerySpec spec;
  final ViewPeriod period;
  final SavedViewChart chart;

  /// The same request under the name the user typed.
  PinRequest named(String name) => PinRequest._(name, spec, period, chart);
}
```

`app/lib/features/analytics/data/saved_views_repository.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';

import 'pin_request.dart';

/// The app's only way to write a saved view.
final class SavedViewsRepository {
  const SavedViewsRepository(this._dao);

  final SavedViewsDao _dao;

  /// Pins [requests] to the end of the dashboard as one write, and returns
  /// the new views' ids in order. A blank name anywhere refuses the lot.
  Future<List<String>> pin(List<PinRequest> requests) async {
    final views = [
      for (final request in requests)
        (
          id: Ids.newId(),
          name: _validName(request.name),
          spec: request.spec,
          period: request.period,
          chart: request.chart,
        ),
    ];
    await _dao.create(views);
    return [for (final view in views) view.id];
  }

  static String _validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A saved view needs a name');
    }
    return trimmed;
  }
}
```

`app/lib/features/analytics/application/saved_view_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bootstrap/database_provider.dart';
import '../data/saved_views_repository.dart';

final savedViewsRepositoryProvider = Provider<SavedViewsRepository>(
  (ref) => SavedViewsRepository(ref.watch(appDatabaseProvider).savedViewsDao),
);
```

- [ ] **Step 7: The name sheet and the pin button**

`app/lib/features/analytics/presentation/widgets/view_name_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';

/// Asks for a saved view's name. Returns it trimmed, or null if dismissed.
///
/// One sheet for pinning and renaming: they ask the same question, and two
/// copies would drift apart on what counts as a valid name.
Future<String?> showViewNameSheet(
  BuildContext context, {
  required String title,
  required String initialName,
  String? note,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ViewNameSheet(
        title: title,
        initialName: initialName,
        note: note,
      ),
    );

class _ViewNameSheet extends StatefulWidget {
  const _ViewNameSheet({
    required this.title,
    required this.initialName,
    this.note,
  });

  final String title;
  final String initialName;
  final String? note;

  @override
  State<_ViewNameSheet> createState() => _ViewNameSheetState();
}

class _ViewNameSheetState extends State<_ViewNameSheet> {
  late final _name = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final note = widget.note;

    return Padding(
      padding: EdgeInsets.only(
        left: NimbusTokens.space4,
        right: NimbusTokens.space4,
        top: NimbusTokens.space4,
        // Above the keyboard: the name field autofocuses, so the keyboard is
        // up the moment the sheet opens.
        bottom: MediaQuery.viewInsetsOf(context).bottom + NimbusTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: NimbusTokens.space4),
          TextField(
            key: const Key('view-name-field'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.viewNameLabel),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          if (note != null) ...[
            const SizedBox(height: NimbusTokens.space2),
            Text(note, key: const Key('view-name-note'),
                style: theme.textTheme.bodySmall),
          ],
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
                key: const Key('view-name-save'),
                // Disabled rather than rejected on tap: the user sees why
                // before trying.
                onPressed: _name.text.trim().isEmpty ? null : _submit,
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

`app/lib/features/analytics/presentation/widgets/pin_button.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/saved_view_providers.dart';
import '../../data/pin_request.dart';
import 'view_name_sheet.dart';

/// The pin on a tab or chart: names what is shown and puts it on the
/// dashboard.
class PinButton extends ConsumerWidget {
  const PinButton({super.key, required this.request});

  final PinRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
        key: Key('pin-${request.chart.name}'),
        icon: const Icon(Icons.push_pin_outlined),
        tooltip: AppLocalizations.of(context).pinToDashboard,
        onPressed: () => _pin(context, ref),
      );

  Future<void> _pin(BuildContext context, WidgetRef ref) async {
    // Everything the write and the snackbar need is read before the sheet
    // opens: after it closes, this button may no longer be mounted.
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(savedViewsRepositoryProvider);

    final name = await showViewNameSheet(
      context,
      title: l10n.pinToDashboard,
      initialName: request.name,
      note: coverageOf(l10n, request.period),
    );
    if (name == null) return;

    await repository.pin([request.named(name)]);
    messenger.showSnackBar(SnackBar(content: Text(l10n.pinnedToDashboard)));
  }
}

/// The pin sheet's line saying what the card will cover.
///
/// Every pin source today is monthly. A source with another period needs its
/// own wording rather than a month sentence that would misdescribe it.
String coverageOf(AppLocalizations l10n, ViewPeriod period) =>
    switch (period) {
      ViewPeriod(type: PeriodType.month, count: 1) =>
        l10n.viewCoversCurrentMonth,
      ViewPeriod(type: PeriodType.month, :final count) =>
        l10n.viewCoversLastMonths(count),
      _ => throw UnsupportedError(
          'no coverage wording for ${period.type.name} periods yet'),
    };
```

- [ ] **Step 8: Put the pins on the tabs**

In `analytics_screen.dart` add imports:
```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import '../data/pin_request.dart';
import 'widgets/pin_button.dart';
```
and this top-level helper at the end of the file:
```dart
/// A pin for a one-month view -- every tab except Trends.
PinButton _monthPin(String name, QuerySpec shown, SavedViewChart chart) =>
    PinButton(
      request: PinRequest.fromShown(
        name: name,
        shownSpec: shown,
        period: ViewPeriod(PeriodType.month, 1),
        chart: chart,
      ),
    );
```

`_BreakdownTab.build`: add `final l10n = AppLocalizations.of(context);` and replace the `_ConfirmedOnlySwitch(...)` child with:
```dart
        Row(
          children: [
            Expanded(
              child: _ConfirmedOnlySwitch(
                value: view.confirmedOnly,
                onChanged: (value) => controller.setConfirmedOnly(value: value),
                tileKey: const Key('breakdown-confirmed-only'),
              ),
            ),
            _monthPin(
              // Drilled in, the card is about that category; at the roots it
              // is the whole breakdown.
              view.trail.isEmpty
                  ? l10n.pinNameSpendingByCategory
                  : view.trail.last.name,
              view.spec,
              SavedViewChart.breakdown,
            ),
          ],
        ),
```

`_TrendsTab.build`: add `final l10n = AppLocalizations.of(context);` and replace its `_ConfirmedOnlySwitch(...)` with:
```dart
        Row(
          children: [
            Expanded(
              child: _ConfirmedOnlySwitch(
                value: view.confirmedOnly,
                onChanged: (value) => controller.setConfirmedOnly(value: value),
                tileKey: const Key('trends-confirmed-only'),
              ),
            ),
            PinButton(
              request: PinRequest.fromShown(
                name: l10n.pinNameLastMonths(view.periods.length),
                shownSpec: view.spec,
                period: ViewPeriod(PeriodType.month, view.periods.length),
                chart: SavedViewChart.trend,
              ),
            ),
          ],
        ),
```

`_CrossTabTab.build`: add `final l10n = AppLocalizations.of(context);` and replace its `_ConfirmedOnlySwitch(...)` with:
```dart
        Row(
          children: [
            Expanded(
              child: _ConfirmedOnlySwitch(
                value: view.confirmedOnly,
                onChanged: (value) => controller.setConfirmedOnly(value: value),
                tileKey: const Key('crosstab-confirmed-only'),
              ),
            ),
            _monthPin(l10n.analyticsTabCrossTab, view.spec,
                SavedViewChart.crossTab),
          ],
        ),
```

`_PatternsTab.build`: add `final l10n = AppLocalizations.of(context);` and pass three pins to `PatternsBody(...)`:
```dart
                hourPin: _monthPin(l10n.patternsHourOfDay, view.hourSpec,
                    SavedViewChart.hourOfDay),
                weekdayPin: _monthPin(l10n.patternsDayOfWeek,
                    view.weekdaySpec, SavedViewChart.dayOfWeek),
                reflectionPin: _monthPin(l10n.patternsReflection,
                    view.reflectionSpec, SavedViewChart.reflection),
```

In `patterns_body.dart`, add three fields to `PatternsBody` (constructor `required this.hourPin, required this.weekdayPin, required this.reflectionPin,`):
```dart
  /// Each chart's own pin, beside its title. Pins are per chart rather than
  /// per tab because the dashboard draws them one at a time.
  final Widget hourPin;
  final Widget weekdayPin;
  final Widget reflectionPin;
```
and replace the three title `Text(...)` lines in `build` with rows:
```dart
        Row(children: [
          Expanded(
            child: Text(l10n.patternsHourOfDay,
                style: theme.textTheme.titleMedium),
          ),
          hourPin,
        ]),
```
(likewise `l10n.patternsDayOfWeek` with `weekdayPin`, `l10n.patternsReflection` with `reflectionPin`).

- [ ] **Step 9: Run to verify GREEN**

Run the Step 3 command. Expected: PASS. Also run `cd app && flutter test test/features/analytics test/localization_test.dart test/ux_rules_test.dart` — Expected: PASS.

- [ ] **Step 10: Full gate, commit, fast-forward**

Commit message:
```
feat: pin what a tab shows

Each analytics tab, and each pattern chart, gets a pin button. It opens
a sheet with a name taken from what is on screen -- the drilled-in
category's, or the tab's -- and a line saying what the card will
cover. Saving stores the tab's question without its dates: the period
travels separately, so a view pinned while looking at an old month
still means the dashboard's month, and the sheet says so before saving.

The chart is fixed by where the view came from, so a spec can never be
paired with a chart that cannot draw it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task 8: The dashboard, as Analytics' first tab

Branch `feat/dashboard-tab`, slug `dashboard-tab`.

**Files:**
- Create: `app/lib/features/analytics/application/dashboard_anchor.dart`
- Create: `app/lib/features/analytics/application/starter_views.dart`
- Modify: `app/lib/features/analytics/application/saved_view_providers.dart` (`pinnedViewsProvider`)
- Modify: `app/lib/features/analytics/data/saved_views_repository.dart` (`watchPinned`)
- Create: `app/lib/features/analytics/presentation/dashboard_tab.dart`
- Create: `app/lib/features/analytics/presentation/widgets/month_bar.dart`
- Create: `app/lib/features/analytics/presentation/widgets/saved_view_card.dart`
- Modify: `app/lib/features/analytics/presentation/analytics_screen.dart` (five tabs)
- Modify: ARBs (+ `flutter gen-l10n`)
- Modify: `app/test/features/analytics/breakdown_screen_test.dart` (`openBreakdown`), `app/test/features/analytics/trends_screen_test.dart` (landing-tab test)
- Create: `app/test/features/analytics/dashboard_tab_test.dart`

**Interfaces:**
- Consumes: `SavedViewEntry`/`SavedView`/`UnreadableSavedView` (Task 4), `PinRequest`, `savedViewsRepositoryProvider` (Task 7), `analyticsResultProvider` (Task 2).
- Produces:
  - `dashboardAnchorProvider` (`NotifierProvider<DashboardAnchor, DateKey>`; `shift(int months)`).
  - `DateKey shiftMonths(DateKey anchor, int months, AppCalendar calendar)`.
  - `QuerySpec resolvedSpec(SavedView view, DateKey anchor, AppCalendar calendar, {required int firstDayOfWeek})`.
  - `String viewPeriodLabel(DateRange range, AppCalendar calendar, {required bool persianDigits})`.
  - `List<PinRequest> starterViews(AppLocalizations l10n)`.
  - `pinnedViewsProvider` (`StreamProvider<List<SavedViewEntry>>`); `SavedViewsRepository.watchPinned()`.
  - `MonthBar({required DateKey anchor, required ValueChanged<int> onShift, required String keyPrefix})` — keys `<prefix>-previous|label|next`.
  - `SavedViewCard({required SavedViewEntry entry, required DateKey anchor})` — keys `saved-view-card-<id>`, `card-name-<id>`, `card-total-<id>`, `card-empty-<id>`, `card-error-<id>`, `card-unreadable-<id>`, `card-loading`.
  - `DashboardTab()` — key `dashboard-tab`; `dashboard-go-to-breakdown`.

- [ ] **Step 1: Write the failing tests**

Add to `app/test/features/analytics/support/dashboard_fixture.dart` (imports: `package:nimbustats/features/analytics/application/starter_views.dart`, `package:nimbustats/features/analytics/data/saved_views_repository.dart`, `package:nimbustats/l10n/app_localizations.dart`):

```dart
/// Pins the two starter cards the way the dashboard's button does.
/// Returns (breakdown id, trend id).
Future<(String, String)> pinStarters(
  AppDatabase db, {
  Locale locale = const Locale('en'),
}) async {
  final l10n = await AppLocalizations.delegate.load(locale);
  final ids =
      await SavedViewsRepository(db.savedViewsDao).pin(starterViews(l10n));
  return (ids[0], ids[1]);
}
```

`app/test/features/analytics/dashboard_tab_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/analytics/application/analytics_providers.dart';
import 'package:nimbustats/features/analytics/application/breakdown_controller.dart';
import 'package:nimbustats/features/analytics/application/starter_views.dart';
import 'package:nimbustats/features/analytics/application/trends_controller.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

import '../../support/harness.dart';
import 'support/dashboard_fixture.dart';

void main() {
  testWidgets('analytics opens on the dashboard', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await openAnalytics(tester, db);

    expect(find.byKey(const Key('dashboard-tab')), findsOneWidget);
    expect(find.text('Nothing pinned yet'), findsOneWidget);
  });

  testWidgets('an empty dashboard adds the two starter cards on request',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await openAnalytics(tester, db);

    await tester.tap(find.text('Add starter cards'));
    await tester.pumpAndSettle();

    expect(find.text('This month by category'), findsOneWidget);
    expect(find.text('Last 6 months'), findsOneWidget);
    final views = await storedViews(db);
    expect(views.map((v) => v.chart), ['breakdown', 'trend']);
    expect(views.map((v) => v.periodCount), [1, 6]);
  });

  test('starter cards ask exactly what their tabs ask', () async {
    // Built by hand in starter_views.dart; this keeps them from drifting away
    // from the tabs they imitate.
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final month = const JalaliCalendar()
        .periodContaining(const DateKey(20260915), PeriodType.month);
    final starters = starterViews(l10n);

    expect(starters[0].spec,
        BreakdownView(period: month).spec.withDateRange(null));
    expect(starters[1].spec,
        TrendsView(periods: [month]).spec.withDateRange(null));
  });

  testWidgets('go to breakdown switches tab', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await openAnalytics(tester, db);

    await tester.tap(find.byKey(const Key('dashboard-go-to-breakdown')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('breakdown-period-label')), findsOneWidget);
  });

  testWidgets("a card shows its view's true total for the dashboard's month",
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, trend) = await pinStarters(db);
    await openAnalytics(tester, db);

    expect(textOf(tester, 'card-total-$breakdown'), total1750);
    // The six-month window ends with this month, so it holds the same 1750.
    expect(textOf(tester, 'card-total-$trend'), total1750);
  });

  testWidgets('the month bar moves every card together', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, trend) = await pinStarters(db);
    await openAnalytics(tester, db);

    await tester.tap(find.byKey(const Key('dashboard-period-previous')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('card-empty-$breakdown')), findsOneWidget);
    expect(find.byKey(Key('card-empty-$trend')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dashboard-period-next')));
    await tester.pumpAndSettle();

    expect(textOf(tester, 'card-total-$breakdown'), total1750);
  });

  testWidgets('an unreadable view is its own card and the others still draw',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, _) = await pinStarters(db);
    await db.customStatement(
      'INSERT INTO saved_views (id, name, spec_json, chart_type, pinned, '
      'sort_order, created_at, updated_at) '
      "VALUES ('bad', 'Broken', '{not json', 'breakdown', 1, 99, 0, 0)",
    );
    await openAnalytics(tester, db);

    expect(find.byKey(const Key('card-unreadable-bad')), findsOneWidget);
    expect(textOf(tester, 'card-total-$breakdown'), total1750);
  });

  testWidgets('a failing query shows on its own card only', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, trend) = await pinStarters(db);
    usePhoneViewport(tester);
    await pumpApp(tester, database: db, overrides: [
      analyticsResultProvider.overrideWith((ref, spec) =>
          spec.groupBy is GroupByPeriod
              ? Future<AnalyticsResult>.error(StateError('trend query failed'))
              : ref.watch(analyticsEngineProvider).run(spec)),
    ]);
    await tester.tap(find.descendant(
      of: find.byKey(const Key('nav-bar')),
      matching: find.byIcon(Icons.insights_outlined),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('card-error-$trend')), findsOneWidget);
    expect(textOf(tester, 'card-total-$breakdown'), total1750);
  });

  testWidgets('a card reads as its name, period and total', (tester) async {
    final handle = tester.ensureSemantics();
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    await pinStarters(db);
    await openAnalytics(tester, db);

    expect(
      find.bySemanticsLabel(
          RegExp('This month by category.*$total1750', dotAll: true)),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('in Persian the cards are right-to-left', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, _) = await pinStarters(db, locale: const Locale('fa'));
    await openAnalytics(tester, db, locale: const Locale('fa'));

    final name = find.byKey(Key('card-name-$breakdown'));
    expect(tester.widget<Text>(name).data, 'این ماه به تفکیک دسته');
    expect(Directionality.of(tester.element(name)), TextDirection.rtl);
    expect(textOf(tester, 'card-total-$breakdown'), total1750);
  });
}
```

Update existing tests for the new landing tab:

- `app/test/features/analytics/breakdown_screen_test.dart`, in `openBreakdown`, after the `pumpAndSettle()` that follows the nav tap, add:
  ```dart
  // Analytics opens on the dashboard; Breakdown is the next tab.
  await tester.tap(find.byKey(const Key('analytics-tab-breakdown')));
  await tester.pumpAndSettle();
  ```
- `app/test/features/analytics/trends_screen_test.dart`, test `'analytics offers both a breakdown and a trend'`: rename to `'analytics opens on the dashboard and offers the other tabs'`, replace the comment and the `breakdown-period-label` expectation with:
  ```dart
    // The dashboard is the landing tab: the user's own pinned questions are
    // what somebody opening analytics most likely came back for.
    expect(find.byKey(const Key('dashboard-tab')), findsOneWidget);
  ```

- [ ] **Step 2: Run to verify RED**

Run: `cd app && flutter test test/features/analytics/dashboard_tab_test.dart`
Expected: FAIL to compile — `starter_views.dart` does not exist.

- [ ] **Step 3: Tag**

Run: `git tag pre-dashboard-tab`

- [ ] **Step 4: Strings**

Confirm absent: `grep -c "\"analyticsTabDashboard\"\|\"dashboard\|\"periodNextMonth\"\|\"periodPreviousMonth\"\|\"savedViewUnreadable\"\|\"starterThisMonthByCategory\"" app/lib/l10n/app_en.arb` → `0`.

`app_en.arb`:
```json
  "analyticsTabDashboard": "Dashboard",
  "dashboardAddStarters": "Add starter cards",
  "dashboardCardEmpty": "Nothing in this period",
  "dashboardCardError": "This card could not load",
  "dashboardEmptyBody": "Pin any chart with its pin button to keep it here, or start with two common ones.",
  "dashboardEmptyTitle": "Nothing pinned yet",
  "dashboardErrorTitle": "Could not load the dashboard",
  "dashboardGoToBreakdown": "Go to Breakdown",
  "periodNextMonth": "Next month",
  "periodPreviousMonth": "Previous month",
  "savedViewUnreadable": "This view can't be read",
  "starterThisMonthByCategory": "This month by category",
```
`app_fa.arb`:
```json
  "analyticsTabDashboard": "داشبورد",
  "dashboardAddStarters": "افزودن کارت‌های آغازین",
  "dashboardCardEmpty": "در این بازه چیزی نیست",
  "dashboardCardError": "این کارت بارگیری نشد",
  "dashboardEmptyBody": "هر نموداری را با دکمهٔ سنجاقش اینجا نگه دارید، یا با دو نمودار رایج شروع کنید.",
  "dashboardEmptyTitle": "هنوز چیزی سنجاق نشده",
  "dashboardErrorTitle": "داشبورد بارگیری نشد",
  "dashboardGoToBreakdown": "رفتن به تفکیک",
  "periodNextMonth": "ماه بعد",
  "periodPreviousMonth": "ماه قبل",
  "savedViewUnreadable": "این نما خوانا نیست",
  "starterThisMonthByCategory": "این ماه به تفکیک دسته",
```
Run: `cd app && flutter gen-l10n`.

- [ ] **Step 5: Anchor, resolution, labels, starters, providers**

`app/lib/features/analytics/application/dashboard_anchor.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../settings/application/settings_providers.dart';
import 'period_label.dart';

/// The date every dashboard card is resolved against. Today, until moved.
class DashboardAnchor extends Notifier<DateKey> {
  @override
  DateKey build() => DateKey.fromDateTime(DateTime.now());

  void shift(int months) =>
      state = shiftMonths(state, months, ref.read(calendarProvider));
}

final dashboardAnchorProvider =
    NotifierProvider<DashboardAnchor, DateKey>(DashboardAnchor.new);

/// [anchor] moved by whole months in [calendar]: the first day of the month
/// [months] away. A month at a time because every pin source is monthly; a
/// smaller step would change nothing on screen.
DateKey shiftMonths(DateKey anchor, int months, AppCalendar calendar) =>
    calendar
        .shiftPeriod(
          calendar.periodContaining(anchor, PeriodType.month),
          PeriodType.month,
          months,
        )
        .startInclusive;

/// [view]'s question with the dates it covers when the dashboard is on
/// [anchor].
///
/// The only way a card gets a runnable spec. A stored spec has no dates, and
/// run as-is it would total the whole history under a one-month label.
QuerySpec resolvedSpec(
  SavedView view,
  DateKey anchor,
  AppCalendar calendar, {
  required int firstDayOfWeek,
}) =>
    view.spec.withDateRange(
      view.period.resolve(anchor, calendar, firstDayOfWeek: firstDayOfWeek),
    );

/// `1405/07` for one month, `1405/02 – 1405/07` for a window.
String viewPeriodLabel(
  DateRange range,
  AppCalendar calendar, {
  required bool persianDigits,
}) {
  final first = periodLabel(range, calendar, persianDigits: persianDigits);
  final last = periodLabel(
    DateRange(range.endInclusive, range.endInclusive),
    calendar,
    persianDigits: persianDigits,
  );
  return first == last ? first : '$first – $last';
}
```

`app/lib/features/analytics/application/starter_views.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../data/pin_request.dart';
import 'trends_controller.dart';

/// The two cards "Add starter cards" pins: this month by category, and the
/// last six months. Offered on a button rather than seeded, so they reach
/// installs that already exist and appear only when asked for.
///
/// Their specs are the Breakdown and Trends tabs' own questions, undated; a
/// test holds them to that.
List<PinRequest> starterViews(AppLocalizations l10n) => [
      PinRequest.fromShown(
        name: l10n.starterThisMonthByCategory,
        shownSpec: QuerySpec(
          filters: const QueryFilters(direction: MoneyDirection.expense),
          groupBy: GroupByCategory(0),
          aggregate: Aggregate.sum,
        ),
        period: ViewPeriod(PeriodType.month, 1),
        chart: SavedViewChart.breakdown,
      ),
      PinRequest.fromShown(
        name: l10n.pinNameLastMonths(TrendsView.defaultPeriodCount),
        shownSpec: const QuerySpec(
          filters: QueryFilters(direction: MoneyDirection.expense),
          groupBy: GroupByPeriod(PeriodType.month),
          aggregate: Aggregate.sum,
        ),
        period: ViewPeriod(PeriodType.month, TrendsView.defaultPeriodCount),
        chart: SavedViewChart.trend,
      ),
    ];
```

In `saved_views_repository.dart` add:
```dart
  /// The dashboard's cards, live, in the user's order.
  Stream<List<SavedViewEntry>> watchPinned() => _dao.watchPinned();
```
In `saved_view_providers.dart` add (import `package:nimbus_data/nimbus_data.dart`):
```dart
/// The dashboard's cards, live, in the user's order.
final pinnedViewsProvider = StreamProvider<List<SavedViewEntry>>(
  (ref) => ref.watch(savedViewsRepositoryProvider).watchPinned(),
);
```

- [ ] **Step 6: Month bar and card**

`app/lib/features/analytics/presentation/widgets/month_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../settings/application/settings_providers.dart';
import '../../application/period_label.dart';

/// ◀ month ▶, for the dashboard and the full-screen view.
class MonthBar extends ConsumerWidget {
  const MonthBar({
    super.key,
    required this.anchor,
    required this.onShift,
    required this.keyPrefix,
  });

  final DateKey anchor;
  final ValueChanged<int> onShift;

  /// Keys are `<prefix>-previous`, `<prefix>-label`, `<prefix>-next`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final calendar = ref.watch(calendarProvider);
    return Row(
      children: [
        IconButton(
          key: Key('$keyPrefix-previous'),
          icon: const Icon(Icons.chevron_left),
          tooltip: l10n.periodPreviousMonth,
          onPressed: () => onShift(-1),
        ),
        Expanded(
          child: Center(
            child: Text(
              periodLabel(
                calendar.periodContaining(anchor, PeriodType.month),
                calendar,
                persianDigits: ref.watch(moneyFormatterProvider).persianDigits,
              ),
              key: Key('$keyPrefix-label'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        IconButton(
          key: Key('$keyPrefix-next'),
          icon: const Icon(Icons.chevron_right),
          tooltip: l10n.periodNextMonth,
          onPressed: () => onShift(1),
        ),
      ],
    );
  }
}
```

`app/lib/features/analytics/presentation/widgets/saved_view_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../settings/application/settings_providers.dart';
import '../../application/analytics_providers.dart';
import '../../application/dashboard_anchor.dart';

/// One pinned view on the dashboard.
///
/// Each card resolves, loads and fails on its own. The dashboard is a list
/// of independent questions; one slow or broken answer must not hold up or
/// blank the others (screen contract §5.1).
class SavedViewCard extends StatelessWidget {
  const SavedViewCard({super.key, required this.entry, required this.anchor});

  final SavedViewEntry entry;
  final DateKey anchor;

  @override
  Widget build(BuildContext context) => Card(
        key: Key('saved-view-card-${entry.id}'),
        child: Padding(
          padding: const EdgeInsets.all(NimbusTokens.space4),
          child: switch (entry) {
            final SavedView view => _Readable(view: view, anchor: anchor),
            final UnreadableSavedView view => _Unreadable(view: view),
          },
        ),
      );
}

class _Readable extends ConsumerWidget {
  const _Readable({required this.view, required this.anchor});

  final SavedView view;
  final DateKey anchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final calendar = ref.watch(calendarProvider);
    final formatter = ref.watch(moneyFormatterProvider);
    final spec = resolvedSpec(view, anchor, calendar,
        firstDayOfWeek: ref.watch(firstDayOfWeekProvider));
    final result = ref.watch(analyticsResultProvider(spec));

    // hasError/hasValue rather than a switch over the AsyncValue subtypes:
    // while an answer re-runs after a write it is a loading value that still
    // holds the old answer, and the card should keep showing it.
    final data = result.hasError ? null : result.value;
    final total = data == null || data.trueCount == 0
        ? null
        : formatter.format(data.trueTotal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One node for a screen reader: name, period, total.
        MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      view.name,
                      key: Key('card-name-${view.id}'),
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: NimbusTokens.space2),
                  Text(
                    // resolvedSpec always sets the range.
                    viewPeriodLabel(spec.filters.dateRange!, calendar,
                        persianDigits: formatter.persianDigits),
                    style: theme.textTheme.labelMedium,
                  ),
                ],
              ),
              if (total != null)
                // Full format -- the total is the card's headline -- scaled
                // down rather than cut when a nine-digit amount meets a narrow
                // phone (degenerate case D1).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    total,
                    key: Key('card-total-${view.id}'),
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: NimbusTokens.space2),
        if (result.hasError)
          _CardError(
            id: view.id,
            error: result.error!,
            onRetry: () => ref.invalidate(analyticsResultProvider(spec)),
          )
        else if (data == null)
          const _CardSkeleton()
        else if (data.trueCount == 0)
          Text(
            l10n.dashboardCardEmpty,
            key: Key('card-empty-${view.id}'),
            style: theme.textTheme.bodyMedium,
          ),
      ],
    );
  }
}

class _CardError extends StatelessWidget {
  const _CardError({
    required this.id,
    required this.error,
    required this.onRetry,
  });

  final String id;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.dashboardCardError, key: Key('card-error-$id')),
              // What failed, not just that something did.
              Text('$error',
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
      ],
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('card-loading'),
        height: NimbusTokens.minTapTarget,
        decoration: BoxDecoration(
          color: NimbusSemanticColors.of(context).skeleton,
          borderRadius: NimbusTokens.borderRadiusSm,
        ),
      );
}

class _Unreadable extends StatelessWidget {
  const _Unreadable({required this.view});

  final UnreadableSavedView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          view.name,
          key: Key('card-name-${view.id}'),
          style: theme.textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: NimbusTokens.space2),
        Text(l10n.savedViewUnreadable, key: Key('card-unreadable-${view.id}')),
        Text('${view.error}',
            style: theme.textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
```

- [ ] **Step 7: The tab, and Analytics opening on it**

`app/lib/features/analytics/presentation/dashboard_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../application/dashboard_anchor.dart';
import '../application/saved_view_providers.dart';
import '../application/starter_views.dart';
import 'widgets/month_bar.dart';
import 'widgets/saved_view_card.dart';

/// Analytics' first tab: the user's pinned views as cards.
class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pinned = ref.watch(pinnedViewsProvider);
    final entries = pinned.hasError ? null : pinned.value;

    final Widget body;
    if (pinned.hasError) {
      body = NimbusErrorState(
        title: l10n.dashboardErrorTitle,
        detail: pinned.error.toString(),
        retryLabel: l10n.commonRetry,
        onRetry: () => ref.invalidate(pinnedViewsProvider),
      );
    } else if (entries == null) {
      body = const NimbusLoadingList(rows: 3);
    } else if (entries.isEmpty) {
      body = const _EmptyDashboard();
    } else {
      body = _CardList(entries: entries);
    }

    return Column(
      key: const Key('dashboard-tab'),
      children: [
        MonthBar(
          anchor: ref.watch(dashboardAnchorProvider),
          onShift: ref.read(dashboardAnchorProvider.notifier).shift,
          keyPrefix: 'dashboard-period',
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _EmptyDashboard extends ConsumerWidget {
  const _EmptyDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Expanded(
          child: NimbusEmptyState(
            icon: Icons.dashboard_outlined,
            title: l10n.dashboardEmptyTitle,
            message: l10n.dashboardEmptyBody,
            actionLabel: l10n.dashboardAddStarters,
            onAction: () =>
                ref.read(savedViewsRepositoryProvider).pin(starterViews(l10n)),
          ),
        ),
        TextButton(
          key: const Key('dashboard-go-to-breakdown'),
          // Breakdown is the tab after this one in AnalyticsScreen's order.
          onPressed: () => DefaultTabController.of(context).animateTo(1),
          child: Text(l10n.dashboardGoToBreakdown),
        ),
        const SizedBox(height: NimbusTokens.space4),
      ],
    );
  }
}

class _CardList extends ConsumerWidget {
  const _CardList({required this.entries});

  final List<SavedViewEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchor = ref.watch(dashboardAnchorProvider);
    return ListView.builder(
      padding: const EdgeInsets.all(NimbusTokens.space2),
      itemCount: entries.length,
      itemBuilder: (context, index) => SavedViewCard(
        key: ValueKey(entries[index].id),
        entry: entries[index],
        anchor: anchor,
      ),
    );
  }
}
```

In `analytics_screen.dart`: import `'dashboard_tab.dart'`; set `length: 5`; add as the **first** tab
```dart
              Tab(
                key: const Key('analytics-tab-dashboard'),
                text: l10n.analyticsTabDashboard,
              ),
```
and make the `TabBarView` children `[DashboardTab(), _BreakdownTab(), _TrendsTab(), _CrossTabTab(), _PatternsTab()]` with the comment:
```dart
            // The dashboard lands first: the user's own pinned questions are
            // what somebody coming back to analytics most likely wants.
```
Replace the class doc comment's second paragraph (`Two tabs answering...`) with:
```dart
/// Five tabs: the user's pinned views first, then the four ways to ask a new
/// question -- where the money went, whether that is changing, tag against
/// category, and when it happens. They are tabs rather than one scrolling
/// screen because each takes different controls.
```

- [ ] **Step 8: Run to verify GREEN**

Run: `cd app && flutter test test/features/analytics test/bootstrap/app_shell_navigation_test.dart`
Expected: PASS, including the updated breakdown and trends tests.

- [ ] **Step 9: Full gate, commit, fast-forward**

Commit message:
```
feat: the dashboard, as Analytics' first tab

Pinned views become cards, each resolving its own question against one
month bar, so going back a month moves them together. Every card loads,
fails and empties on its own -- a broken row or a failing query never
blanks the rest -- and reads to a screen reader as its name, period and
total.

An empty dashboard offers the two starter cards on a button rather than
seeding them: that reaches installs that already exist, and nothing
appears that the user did not ask for. The starters' questions are held
by a test to the Breakdown and Trends tabs' own.

Analytics now opens on the dashboard instead of Breakdown; the tests
that assumed Breakdown landed first open it explicitly.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task 9: Card previews

Branch `feat/card-previews`, slug `card-previews`.

**Files:**
- Create: `app/lib/features/analytics/presentation/widgets/card_previews.dart`
- Modify: `app/lib/features/analytics/presentation/widgets/saved_view_card.dart`
- Modify: `app/lib/features/analytics/presentation/widgets/patterns_body.dart` (`height`, `showAxes`)
- Modify: `app/lib/features/analytics/application/dashboard_anchor.dart` (`trendPeriods`)
- Modify: ARBs (+ `flutter gen-l10n`)
- Create: `app/test/features/analytics/card_previews_test.dart`

**Interfaces:**
- Consumes: `trendAmounts`, `HourOfDayChart`, `DayOfWeekChart` (Task 6); `resolvedSpec` (Task 8).
- Produces: `CardPreview({required SavedView view, required QuerySpec spec, required AnalyticsResult result})`, `CardPreview.height = 120`; `List<DateRange> trendPeriods(QuerySpec resolved, AppCalendar calendar, {required int firstDayOfWeek})`; `HourOfDayChart`/`DayOfWeekChart` gain `double height = 180`, `bool showAxes = true`. Keys: `card-row-<categoryId>`, `card-trend-chart`, `card-overlap-note`, `card-regretted`, `card-unlabelled`.

- [ ] **Step 1: Write the failing tests**

`app/test/features/analytics/card_previews_test.dart`:

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/analytics/application/breakdown_controller.dart';
import 'package:nimbustats/features/analytics/application/cross_tab_controller.dart';
import 'package:nimbustats/features/analytics/application/patterns_controller.dart';
import 'package:nimbustats/features/analytics/application/trends_controller.dart';
import 'package:nimbustats/features/analytics/data/pin_request.dart';
import 'package:nimbustats/features/analytics/data/saved_views_repository.dart';
import 'package:nimbustats/features/tags/data/tag_repository.dart';

import 'support/dashboard_fixture.dart';

final _month = const JalaliCalendar()
    .periodContaining(DateKey.fromDateTime(DateTime.now()), PeriodType.month);

Future<String> _pin(AppDatabase db, QuerySpec shown, SavedViewChart chart,
        {int months = 1}) async =>
    (await SavedViewsRepository(db.savedViewsDao).pin([
      PinRequest.fromShown(
        name: chart.name,
        shownSpec: shown,
        period: ViewPeriod(PeriodType.month, months),
        chart: chart,
      ),
    ]))
        .single;

Finder _inCard(String id, Finder matching) => find.descendant(
    of: find.byKey(Key('saved-view-card-$id')), matching: matching);

void main() {
  testWidgets('a breakdown card lists its top categories beside a pie',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final id = await _pin(
        db, BreakdownView(period: _month).spec, SavedViewChart.breakdown);
    await openAnalytics(tester, db);

    expect(_inCard(id, find.byType(PieChart)), findsOneWidget);
    expect(_inCard(id, find.text('Food')), findsOneWidget);
    expect(_inCard(id, find.text('Transport')), findsOneWidget);
    expect(_inCard(id, find.byKey(const Key('card-row-seed-food'))),
        findsOneWidget);
  });

  testWidgets('a trend card plots one point per month of its window',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final id = await _pin(
        db, TrendsView(periods: [_month]).spec, SavedViewChart.trend,
        months: 6);
    await openAnalytics(tester, db);

    final chart = tester.widget<LineChart>(
        _inCard(id, find.byKey(const Key('card-trend-chart'))));
    expect(chart.data.lineBarsData.single.spots, hasLength(6));
  });

  testWidgets('a cross-tab card names its top cells and says tags overlap',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final tags = TagRepository(db.tagsDao);
    final travel = await tags.create(name: 'Travel');
    await seedSpending(db, diningTags: [travel], transportTags: [travel]);
    final id = await _pin(
        db, CrossTabView(period: _month).spec, SavedViewChart.crossTab);
    await openAnalytics(tester, db);

    expect(_inCard(id, find.byKey(const Key('card-overlap-note'))),
        findsOneWidget);
    expect(_inCard(id, find.text('Travel · Food')), findsOneWidget);
  });

  testWidgets('hour and weekday cards draw bars', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final patterns = PatternsView(period: _month);
    final hour = await _pin(db, patterns.hourSpec, SavedViewChart.hourOfDay);
    final day =
        await _pin(db, patterns.weekdaySpec, SavedViewChart.dayOfWeek);
    await openAnalytics(tester, db);

    expect(_inCard(hour, find.byType(BarChart)), findsOneWidget);
    await tester.ensureVisible(find.byKey(Key('saved-view-card-$day')));
    await tester.pumpAndSettle();
    expect(_inCard(day, find.byType(BarChart)), findsOneWidget);
  });

  testWidgets('a reflection card shows what was avoidable and regretted',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final ids = await seedSpending(db);
    // Groceries (1000) is avoidable and regretted; the other 750 is not
    // labelled at all.
    await db.transactionsDao.setReflection(ids[0],
        necessity: Necessity.avoidable, satisfaction: Satisfaction.regret);
    final id = await _pin(db, PatternsView(period: _month).reflectionSpec,
        SavedViewChart.reflection);
    await openAnalytics(tester, db);

    expect(
      tester.widget<Text>(_inCard(id, find.byKey(const Key('card-regretted')))).data,
      total1000,
    );
    expect(
      tester.widget<Text>(_inCard(id, find.byKey(const Key('card-unlabelled')))).data,
      total750,
    );
  });
}
```

(The cross-tab's category axis is depth 0, so Dining rolls up to Food: expected cells are `Travel · Food` 500 and `Travel · Transport` 250.)

- [ ] **Step 2: Run to verify RED**

Run: `cd app && flutter test test/features/analytics/card_previews_test.dart`
Expected: FAIL — no `PieChart` / `card-trend-chart` / `card-overlap-note` / `BarChart` / `card-regretted` inside the cards (Task 8 cards show only the total).

- [ ] **Step 3: Tag**

Run: `git tag pre-card-previews`

- [ ] **Step 4: Strings**

Confirm absent: `grep -c "\"dashboardAvoidableRegretted\"\|\"dashboardOverlapNote\"" app/lib/l10n/app_en.arb` → `0`.
`app_en.arb`:
```json
  "dashboardAvoidableRegretted": "Avoidable and regretted",
  "dashboardOverlapNote": "Tags overlap, so cells add up to more than the total.",
```
`app_fa.arb`:
```json
  "dashboardAvoidableRegretted": "قابل اجتناب و پشیمان",
  "dashboardOverlapNote": "برچسب‌ها هم‌پوشانی دارند؛ جمع خانه‌ها از کل بیشتر است.",
```
Run: `cd app && flutter gen-l10n`.

- [ ] **Step 5: Compact bar charts**

In `patterns_body.dart`, give `HourOfDayChart` and `DayOfWeekChart` two constructor parameters and fields:
```dart
    this.height = 180,
    this.showAxes = true,
```
```dart
  final double height;

  /// False on a dashboard card: the shape is the message at that size, and
  /// axis labels would take half the room.
  final bool showAxes;
```
use `height: height` in their `SizedBox`, and pass `showAxes: showAxes` into `_barData`. In `_barData`, add the parameter `bool showAxes = true,` and at the top of the function body:
```dart
  if (!showAxes) {
    return BarChartData(
      barGroups: [
        for (final (x, amount) in bars)
          BarChartGroupData(x: x, barRods: [
            BarChartRodData(
              toY: amount.minorUnits.toDouble(),
              color: Theme.of(context).colorScheme.primary,
              width: 4,
            ),
          ]),
      ],
      titlesData: FlTitlesData(show: false),
      gridData: FlGridData(show: false),
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(enabled: false),
    );
  }
```

- [ ] **Step 6: `trendPeriods` and the previews**

In `dashboard_anchor.dart` add:
```dart
/// The periods a trend view plots: its resolved window, cut into the periods
/// it groups by.
List<DateRange> trendPeriods(
  QuerySpec resolved,
  AppCalendar calendar, {
  required int firstDayOfWeek,
}) {
  final groupBy = resolved.groupBy;
  if (groupBy is! GroupByPeriod) {
    throw ArgumentError.value(groupBy, 'resolved', 'a trend groups by period');
  }
  return PeriodBoundaries.series(
    groupBy.period,
    resolved.filters.dateRange!,
    calendar,
    firstDayOfWeek: firstDayOfWeek,
  );
}
```

`app/lib/features/analytics/presentation/widgets/card_previews.dart`:

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../categories/application/category_providers.dart';
import '../../../settings/application/settings_providers.dart';
import '../../../tags/application/tag_providers.dart';
import '../../application/dashboard_anchor.dart';
import 'patterns_body.dart';
import 'trends_body.dart';

/// The small chart under a card's total.
///
/// Deliberately partial -- a top three, a shape without axes. The whole
/// answer is one tap away, and a card that tried to be the full chart would
/// be one nobody could read at this size.
class CardPreview extends ConsumerWidget {
  const CardPreview({
    super.key,
    required this.view,
    required this.spec,
    required this.result,
  });

  final SavedView view;

  /// [view]'s question with its dates resolved.
  final QuerySpec spec;
  final AnalyticsResult result;

  static const height = 120.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatter = ref.watch(moneyFormatterProvider);
    final firstDayOfWeek = ref.watch(firstDayOfWeekProvider);
    return SizedBox(
      height: height,
      child: switch (view.chart) {
        SavedViewChart.breakdown =>
          _BreakdownPreview(result: result, formatter: formatter),
        SavedViewChart.trend => _TrendPreview(
            amounts: trendAmounts(
              result,
              trendPeriods(spec, ref.watch(calendarProvider),
                  firstDayOfWeek: firstDayOfWeek),
            ),
          ),
        SavedViewChart.crossTab =>
          _CrossTabPreview(result: result, formatter: formatter),
        SavedViewChart.hourOfDay => HourOfDayChart(
            result: result,
            formatter: formatter,
            height: height,
            showAxes: false,
          ),
        SavedViewChart.dayOfWeek => DayOfWeekChart(
            result: result,
            firstDayOfWeek: firstDayOfWeek,
            formatter: formatter,
            height: height,
            showAxes: false,
          ),
        SavedViewChart.reflection =>
          _ReflectionPreview(result: result, formatter: formatter),
      },
    );
  }
}

/// Shown when the names a preview needs failed to load.
class _PreviewUnavailable extends StatelessWidget {
  const _PreviewUnavailable({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Text(
        '${AppLocalizations.of(context).dashboardCardError}: $error',
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
}

class _BreakdownPreview extends ConsumerWidget {
  const _BreakdownPreview({required this.result, required this.formatter});

  final AnalyticsResult result;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodes = ref.watch(categoryNodesByIdProvider);
    if (nodes.hasError) return _PreviewUnavailable(error: nodes.error!);
    // Names gate the preview, as they gate the tab: a slice labelled with a
    // raw id is not a smaller answer, it is an unreadable one.
    final byId = nodes.value;
    if (byId == null) return const SizedBox.shrink();

    final rows = [
      for (final bucket in result.buckets)
        if (bucket.key case CategoryKey(:final categoryId))
          (id: categoryId, money: bucket.money),
    ]..sort((a, b) => b.money.minorUnits.compareTo(a.money.minorUnits));
    // Over every row, as the breakdown tab assigns them, so a category keeps
    // its colour between the card and the full chart.
    final colours = NimbusChartColors.of(context).assign(rows.map((r) => r.id));

    return Row(
      children: [
        SizedBox(
          width: CardPreview.height,
          child: PieChart(
            PieChartData(
              sectionsSpace: 1,
              centerSpaceRadius: 24,
              sections: [
                for (final row in rows)
                  PieChartSectionData(
                    value: row.money.minorUnits.toDouble(),
                    color: colours[row.id],
                    showTitle: false,
                    radius: 28,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: NimbusTokens.space4),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final row in rows.take(3))
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: NimbusTokens.space1),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colours[row.id],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: NimbusTokens.space2),
                      Expanded(
                        child: Text(
                          byId[row.id]?.category.name ?? row.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Compact: a dense row (screen contract §8).
                      Text(formatter.formatCompact(row.money),
                          key: Key('card-row-${row.id}')),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendPreview extends StatelessWidget {
  const _TrendPreview({required this.amounts});

  final List<Money> amounts;

  @override
  Widget build(BuildContext context) => LineChart(
        key: const Key('card-trend-chart'),
        LineChartData(
          titlesData: FlTitlesData(show: false),
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (final (index, amount) in amounts.indexed)
                  FlSpot(index.toDouble(), amount.minorUnits.toDouble()),
              ],
              color: Theme.of(context).colorScheme.primary,
              barWidth: 2,
              dotData: FlDotData(show: false),
            ),
          ],
        ),
      );
}

class _CrossTabPreview extends ConsumerWidget {
  const _CrossTabPreview({required this.result, required this.formatter});

  final AnalyticsResult result;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final categories = ref.watch(categoryNodesByIdProvider);
    final tags = ref.watch(tagNodesByIdProvider);
    final failure = categories.error ?? tags.error;
    if (failure != null) return _PreviewUnavailable(error: failure);
    final byCategory = categories.value;
    final byTag = tags.value;
    if (byCategory == null || byTag == null) return const SizedBox.shrink();

    final cells = [
      for (final bucket in result.buckets)
        if (bucket.key case TagCategoryKey(:final tagId, :final categoryId))
          (tagId: tagId, categoryId: categoryId, money: bucket.money),
    ]..sort((a, b) => b.money.minorUnits.compareTo(a.money.minorUnits));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cells.isEmpty)
          Text(l10n.dashboardCardEmpty)
        else
          for (final cell in cells.take(3))
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${byTag[cell.tagId]?.value.name ?? cell.tagId} · '
                    '${byCategory[cell.categoryId]?.category.name ?? cell.categoryId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(formatter.formatCompact(cell.money)),
              ],
            ),
        const Spacer(),
        // Unconditional, as on the full matrix: a tag axis always overlaps.
        Text(
          l10n.dashboardOverlapNote,
          key: const Key('card-overlap-note'),
          style: theme.textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _ReflectionPreview extends StatelessWidget {
  const _ReflectionPreview({required this.result, required this.formatter});

  final AnalyticsResult result;
  final MoneyFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // The two numbers the regret matrix exists for (screen contract §5.6):
    // what was avoidable and regretted, and what is not labelled yet -- the
    // honest prompt to label more. The full grid is on the full screen.
    final regretted = Money.sum([
      for (final bucket in result.buckets)
        if (bucket.key
            case ReflectionKey(
              necessity: NecessityLevel.avoidable,
              satisfaction: SatisfactionLevel.regret,
            ))
          bucket.money,
    ]);
    final unlabelled = Money.sum([
      for (final bucket in result.buckets)
        if (bucket.key case ReflectionKey(:final necessity, :final satisfaction)
            when necessity == null || satisfaction == null)
          bucket.money,
    ]);

    Widget line(String label, Money amount, String key) => Row(
          children: [
            Expanded(child: Text(label)),
            Text(formatter.format(amount),
                key: Key(key), style: theme.textTheme.titleMedium),
          ],
        );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        line(l10n.dashboardAvoidableRegretted, regretted, 'card-regretted'),
        const SizedBox(height: NimbusTokens.space2),
        line(l10n.reflectionUnset, unlabelled, 'card-unlabelled'),
      ],
    );
  }
}
```

In `saved_view_card.dart`, import `'card_previews.dart'` and extend the last `else if` chain in `_Readable.build` with a final branch:
```dart
        else
          CardPreview(view: view, spec: spec, result: data),
```

- [ ] **Step 7: Run to verify GREEN**

Run: `cd app && flutter test test/features/analytics`
Expected: PASS.

- [ ] **Step 8: Full gate, commit, fast-forward**

Commit message:
```
feat: each card shows a small chart of its answer

Breakdown cards show a pie and the top three categories, trend cards the
line over their window, cross-tab cards the top three tag-by-category
cells with the "tags overlap" note, pattern cards their bars without
axes, and reflection cards the two numbers that matrix exists for:
avoidable-and-regretted, and not labelled yet. A card is deliberately
partial; the whole answer is one tap away.

The regret card departs from the first design's small grid: four by
four does not fit a card, and those two numbers are its point.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task 10: Reorder cards, remove with undo, rename

Branch `feat/dashboard-edit`, slug `dashboard-edit`.

**Files:**
- Modify: `app/lib/features/analytics/data/saved_views_repository.dart` (`rename`, `reorder`, `remove`, `restore`)
- Create: `app/lib/features/analytics/presentation/widgets/saved_view_actions.dart`
- Modify: `app/lib/features/analytics/presentation/widgets/saved_view_card.dart` (menu)
- Modify: `app/lib/features/analytics/presentation/dashboard_tab.dart` (`ReorderableListView`)
- Modify: ARBs (+ `flutter gen-l10n`)
- Create: `app/test/features/analytics/dashboard_edit_test.dart`

**Interfaces:**
- Consumes: `SavedViewsDao.rename/reorder/softDelete/restore` (Task 5).
- Produces: `SavedViewsRepository.rename(String id, String name)`, `reorder(List<String> ids)`, `remove(String id)`, `restore(String id)`; `Future<void> removeSavedView({required SavedViewsRepository repository, required ScaffoldMessengerState messenger, required AppLocalizations l10n, required String id})`; `Future<void> renameSavedView(BuildContext context, {required SavedViewsRepository repository, required String id, required String currentName})`. Keys: `card-menu-<id>`, `card-menu-rename`, `card-menu-remove`.

- [ ] **Step 1: Write the failing tests**

`app/test/features/analytics/dashboard_edit_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/dashboard_fixture.dart';

Future<void> openMenu(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('card-menu-$id')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('remove offers undo, and undo puts the card back in its place',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final (first, second) = await pinStarters(db);
    await openAnalytics(tester, db);

    await openMenu(tester, first);
    await tester.tap(find.byKey(const Key('card-menu-remove')));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('saved-view-card-$first')), findsNothing);
    expect(find.text('Removed from the dashboard'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect((await storedViews(db)).map((v) => v.id), [first, second]);
    expect(find.byKey(Key('saved-view-card-$first')), findsOneWidget);
  });

  testWidgets('rename shows the new name on the card', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final (first, _) = await pinStarters(db);
    await openAnalytics(tester, db);

    await openMenu(tester, first);
    await tester.tap(find.byKey(const Key('card-menu-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('view-name-field')), 'Where it went');
    await tester.tap(find.byKey(const Key('view-name-save')));
    await tester.pumpAndSettle();

    expect(textOf(tester, 'card-name-$first'), 'Where it went');
  });

  testWidgets('dragging a card below another saves the new order',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final (first, second) = await pinStarters(db);
    await openAnalytics(tester, db);

    final card = find.byKey(Key('saved-view-card-$first'));
    final height = tester.getSize(card).height;
    final gesture = await tester.startGesture(tester.getCenter(card),
        kind: PointerDeviceKind.touch);
    // A long press starts the drag on a phone.
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(Offset(0, height * 1.5));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect((await storedViews(db)).map((v) => v.id), [second, first]);
  });

  testWidgets('an unreadable card can be removed but not renamed',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await db.customStatement(
      'INSERT INTO saved_views (id, name, spec_json, chart_type, pinned, '
      'sort_order, created_at, updated_at) '
      "VALUES ('bad', 'Broken', '{not json', 'breakdown', 1, 0, 0, 0)",
    );
    await openAnalytics(tester, db);

    await openMenu(tester, 'bad');
    expect(find.byKey(const Key('card-menu-rename')), findsNothing);
    await tester.tap(find.byKey(const Key('card-menu-remove')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('saved-view-card-bad')), findsNothing);
  });
}
```

- [ ] **Step 2: Run to verify RED**

Run: `cd app && flutter test test/features/analytics/dashboard_edit_test.dart`
Expected: FAIL — `card-menu-<id>` not found; the drag test's order stays `[first, second]`.

- [ ] **Step 3: Tag**

Run: `git tag pre-dashboard-edit`

- [ ] **Step 4: Strings**

Confirm absent: `grep -c "\"cardOptions\"\|\"removeView\"\|\"renameView\"\|\"viewRemoved\"" app/lib/l10n/app_en.arb` → `0`.
`app_en.arb`:
```json
  "cardOptions": "Card options",
  "removeView": "Remove",
  "renameView": "Rename",
  "viewRemoved": "Removed from the dashboard",
```
`app_fa.arb`:
```json
  "cardOptions": "گزینه‌های کارت",
  "removeView": "حذف",
  "renameView": "تغییر نام",
  "viewRemoved": "از داشبورد حذف شد",
```
Run: `cd app && flutter gen-l10n`.

- [ ] **Step 5: Repository writes and shared actions**

In `saved_views_repository.dart` add:
```dart
  Future<void> rename(String id, String name) =>
      _dao.rename(id, _validName(name));

  /// [ids] is every pinned view, in the new order.
  Future<void> reorder(List<String> ids) => _dao.reorder(ids);

  Future<void> remove(String id) => _dao.softDelete(id);

  /// The undo behind [remove].
  Future<void> restore(String id) => _dao.restore(id);
```

`app/lib/features/analytics/presentation/widgets/saved_view_actions.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/saved_views_repository.dart';
import 'view_name_sheet.dart';

/// Removes [id] and offers undo.
///
/// Takes its dependencies rather than a context, so it can run after the
/// screen that asked has already closed.
Future<void> removeSavedView({
  required SavedViewsRepository repository,
  required ScaffoldMessengerState messenger,
  required AppLocalizations l10n,
  required String id,
}) async {
  await repository.remove(id);
  // Undo, never confirm (screen contract §1.3).
  messenger.showSnackBar(nimbusUndoSnackBar(
    message: l10n.viewRemoved,
    undoLabel: l10n.commonUndo,
    onUndo: () => repository.restore(id),
  ));
}

/// Asks for a new name and saves it; dismissing changes nothing.
Future<void> renameSavedView(
  BuildContext context, {
  required SavedViewsRepository repository,
  required String id,
  required String currentName,
}) async {
  final l10n = AppLocalizations.of(context);
  final name = await showViewNameSheet(
    context,
    title: l10n.renameView,
    initialName: currentName,
  );
  if (name == null) return;
  await repository.rename(id, name);
}
```

- [ ] **Step 6: The card menu**

In `saved_view_card.dart` import `'../../application/saved_view_providers.dart'` and `'saved_view_actions.dart'`; change `SavedViewCard.build`'s `Padding` child to:
```dart
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: switch (entry) {
                  final SavedView view => _Readable(view: view, anchor: anchor),
                  final UnreadableSavedView view => _Unreadable(view: view),
                },
              ),
              // Outside the card's merged semantics, so a screen reader
              // reaches it as its own button.
              _CardMenu(entry: entry),
            ],
          ),
```
and add:
```dart
enum _CardAction { rename, remove }

class _CardMenu extends ConsumerWidget {
  const _CardMenu({required this.entry});

  final SavedViewEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<_CardAction>(
      key: Key('card-menu-${entry.id}'),
      tooltip: l10n.cardOptions,
      onSelected: (action) => _run(context, ref, action),
      itemBuilder: (context) => [
        // An unreadable view can only go: renaming something that cannot be
        // drawn would suggest it can be fixed from here.
        if (entry is SavedView)
          PopupMenuItem(
            key: const Key('card-menu-rename'),
            value: _CardAction.rename,
            child: Text(l10n.renameView),
          ),
        PopupMenuItem(
          key: const Key('card-menu-remove'),
          value: _CardAction.remove,
          child: Text(l10n.removeView),
        ),
      ],
    );
  }

  Future<void> _run(
      BuildContext context, WidgetRef ref, _CardAction action) async {
    final repository = ref.read(savedViewsRepositoryProvider);
    switch (action) {
      case _CardAction.rename:
        await renameSavedView(context,
            repository: repository, id: entry.id, currentName: entry.name);
      case _CardAction.remove:
        await removeSavedView(
          repository: repository,
          messenger: ScaffoldMessenger.of(context),
          l10n: AppLocalizations.of(context),
          id: entry.id,
        );
    }
  }
}
```

- [ ] **Step 7: Reorderable list**

In `dashboard_tab.dart` import `'../application/saved_view_providers.dart'` (already) and replace `_CardList` with:

```dart
class _CardList extends ConsumerStatefulWidget {
  const _CardList({required this.entries});

  final List<SavedViewEntry> entries;

  @override
  ConsumerState<_CardList> createState() => _CardListState();
}

class _CardListState extends ConsumerState<_CardList> {
  /// The order on screen. It follows the database, except between a drag and
  /// the write it causes: a reorderable list needs the new order in the same
  /// frame, or the card snaps back until the stream catches up.
  late List<SavedViewEntry> _shown = widget.entries;

  @override
  void didUpdateWidget(_CardList old) {
    super.didUpdateWidget(old);
    if (!identical(old.entries, widget.entries)) _shown = widget.entries;
  }

  Future<void> _move(int oldIndex, int newIndex) async {
    // onReorderItem reports the final index, already adjusted for the item
    // removed at oldIndex.
    final next = [..._shown];
    next.insert(newIndex, next.removeAt(oldIndex));
    setState(() => _shown = next);
    await ref
        .read(savedViewsRepositoryProvider)
        .reorder([for (final entry in next) entry.id]);
  }

  @override
  Widget build(BuildContext context) {
    final anchor = ref.watch(dashboardAnchorProvider);
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(NimbusTokens.space2),
      itemCount: _shown.length,
      onReorderItem: _move,
      itemBuilder: (context, index) => SavedViewCard(
        key: ValueKey(_shown[index].id),
        entry: _shown[index],
        anchor: anchor,
      ),
    );
  }
}
```

- [ ] **Step 8: Run to verify GREEN**

Run: `cd app && flutter test test/features/analytics`
Expected: PASS.

- [ ] **Step 9: Full gate, commit, fast-forward**

Commit message:
```
feat: reorder cards, remove them with undo, rename them

Long-press and drag moves a card; the new order is written in one
transaction, and the list keeps it on screen in the same frame so the
card does not snap back while the write lands. Each card's menu renames
it or removes it -- removal is a soft delete with Undo in a snackbar,
never a confirmation, and an undone card returns to its old place.

An unreadable card offers Remove only: renaming something that cannot
be drawn would suggest it can be fixed from there.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task 11: Open a saved view full screen

Branch `feat/saved-view-screen`, slug `saved-view-screen`.

**Files:**
- Modify: `app/lib/features/analytics/routes.dart`
- Modify: `app/lib/bootstrap/app_router.dart` (one line)
- Modify: `app/lib/features/analytics/data/saved_views_repository.dart` (`watchById`)
- Modify: `app/lib/features/analytics/application/saved_view_providers.dart` (`savedViewByIdProvider`)
- Create: `app/lib/features/analytics/presentation/saved_view_screen.dart`
- Create: `app/lib/features/analytics/presentation/widgets/saved_view_body.dart`
- Modify: `app/lib/features/analytics/presentation/widgets/breakdown_body.dart` (`onDrill` nullable)
- Modify: `app/lib/features/analytics/presentation/widgets/saved_view_card.dart` (tap)
- Modify: ARBs (+ `flutter gen-l10n`)
- Create: `app/test/features/analytics/saved_view_screen_test.dart`

**Interfaces:**
- Consumes: `removeSavedView`, `renameSavedView` (Task 10); `MonthBar`, `resolvedSpec`, `shiftMonths` (Task 8); `trendPeriods` (Task 9).
- Produces: `savedViewRoute = '/view'`, `String savedViewLocation(String id, DateKey anchor)`, `analyticsRoutes`; `savedViewByIdProvider` (`StreamProvider.autoDispose.family<SavedViewEntry?, String>`); `SavedViewScreen({required String id, DateKey? initialAnchor})`; `SavedViewBody({required SavedView view, required DateKey anchor})`. Keys: `saved-view-title`, `saved-view-menu`, `saved-view-menu-rename`, `saved-view-menu-remove`, `saved-view-period-previous|label|next`.

- [ ] **Step 1: Write the failing tests**

`app/test/features/analytics/saved_view_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/dashboard_fixture.dart';

Future<void> openCard(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('card-name-$id')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping a card opens its view full screen, over the shell',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, _) = await pinStarters(db);
    await openAnalytics(tester, db);

    await openCard(tester, breakdown);

    expect(textOf(tester, 'saved-view-title'), 'This month by category');
    expect(textOf(tester, 'breakdown-total-amount'), total1750);
    expect(find.byKey(const Key('nav-bar')), findsNothing);
  });

  testWidgets(
      "it starts on the dashboard's month and moves without moving the dashboard",
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, _) = await pinStarters(db);
    await openAnalytics(tester, db);
    await tester.tap(find.byKey(const Key('dashboard-period-previous')));
    await tester.pumpAndSettle();
    final dashboardMonth = textOf(tester, 'dashboard-period-label');

    await openCard(tester, breakdown);
    expect(textOf(tester, 'saved-view-period-label'), dashboardMonth);
    expect(find.byKey(const Key('breakdown-total-amount')), findsNothing);

    await tester.tap(find.byKey(const Key('saved-view-period-next')));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'breakdown-total-amount'), total1750);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(textOf(tester, 'dashboard-period-label'), dashboardMonth);
  });

  testWidgets('a pinned breakdown does not drill past its level',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, _) = await pinStarters(db);
    await openAnalytics(tester, db);

    await openCard(tester, breakdown);

    expect(
      tester.widget<ListTile>(find.byKey(const Key('breakdown-row-seed-food'))).onTap,
      isNull,
    );
  });

  testWidgets('a trend view draws the full trend chart', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (_, trend) = await pinStarters(db);
    await openAnalytics(tester, db);

    await openCard(tester, trend);

    expect(find.byKey(const Key('trends-chart')), findsOneWidget);
  });

  testWidgets('rename from the full screen updates its title', (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final (breakdown, _) = await pinStarters(db);
    await openAnalytics(tester, db);
    await openCard(tester, breakdown);

    await tester.tap(find.byKey(const Key('saved-view-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-view-menu-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('view-name-field')), 'Food watch');
    await tester.tap(find.byKey(const Key('view-name-save')));
    await tester.pumpAndSettle();

    expect(textOf(tester, 'saved-view-title'), 'Food watch');
  });

  testWidgets('remove from the full screen returns to the dashboard with undo',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    final (breakdown, trend) = await pinStarters(db);
    await openAnalytics(tester, db);
    await openCard(tester, breakdown);

    await tester.tap(find.byKey(const Key('saved-view-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saved-view-menu-remove')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dashboard-tab')), findsOneWidget);
    expect(find.byKey(Key('saved-view-card-$breakdown')), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect((await storedViews(db)).map((v) => v.id), [breakdown, trend]);
  });
}
```

- [ ] **Step 2: Run to verify RED**

Run: `cd app && flutter test test/features/analytics/saved_view_screen_test.dart`
Expected: FAIL — tapping the card does nothing; `saved-view-title` not found.

- [ ] **Step 3: Tag**

Run: `git tag pre-saved-view-screen`

- [ ] **Step 4: Strings**

Confirm absent: `grep -c "\"savedViewMissing" app/lib/l10n/app_en.arb` → `0`.
`app_en.arb`:
```json
  "savedViewMissing": "This view no longer exists",
  "savedViewMissingBody": "It was removed. You can pin it again from its tab.",
```
`app_fa.arb`:
```json
  "savedViewMissing": "این نما دیگر وجود ندارد",
  "savedViewMissingBody": "حذف شده است. می‌توانید دوباره از زبانه‌اش سنجاقش کنید.",
```
Run: `cd app && flutter gen-l10n`.

- [ ] **Step 5: Route, provider, no-drill breakdown**

Replace `app/lib/features/analytics/routes.dart`:

```dart
import 'package:go_router/go_router.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import 'presentation/analytics_screen.dart';
import 'presentation/saved_view_screen.dart';

const analyticsRoute = '/analytics';

/// The full-screen saved view's prefix. The `:id` segment is appended where
/// the route is declared.
const savedViewRoute = '/view';

/// Where a card opens: [id]'s view, starting on the dashboard's month.
String savedViewLocation(String id, DateKey anchor) =>
    '$savedViewRoute/$id?anchor=${anchor.value}';

/// A nav-shell destination rather than a pushed screen, so it keeps the bottom
/// bar and the user can leave it the way they arrived.
final analyticsShellRoutes = <RouteBase>[
  GoRoute(
    path: analyticsRoute,
    name: 'analytics',
    builder: (context, state) => const AnalyticsScreen(),
  ),
];

/// Pushed over the shell, like expense detail: a saved view owns the whole
/// screen, with its own month arrows.
final analyticsRoutes = <RouteBase>[
  GoRoute(
    path: '$savedViewRoute/:id',
    name: 'saved-view',
    builder: (context, state) {
      final anchor = state.uri.queryParameters['anchor'];
      return SavedViewScreen(
        id: state.pathParameters['id']!,
        // A malformed anchor throws rather than falling back to today: the
        // link is built by savedViewLocation, so a bad one is a bug to see.
        initialAnchor: anchor == null ? null : DateKey(int.parse(anchor)),
      );
    },
  ),
];
```

In `app/lib/bootstrap/app_router.dart`, append after `...onboardingRoutes,`:
```dart
      ...analyticsRoutes,
```

In `saved_views_repository.dart` add:
```dart
  /// One view, live; null once removed.
  Stream<SavedViewEntry?> watchById(String id) => _dao.watchById(id);
```
In `saved_view_providers.dart` add:
```dart
/// One saved view, live, for its full screen. Auto-disposed: a closed screen
/// has no reason to keep watching.
final savedViewByIdProvider =
    StreamProvider.autoDispose.family<SavedViewEntry?, String>(
  (ref, id) => ref.watch(savedViewsRepositoryProvider).watchById(id),
);
```

In `breakdown_body.dart`: change both `onDrill` fields to `final void Function(CategoryCrumb)? onDrill;`, make the `BreakdownBody` constructor parameter `this.onDrill` (not required) with the doc comment `/// Null for a pinned view, which shows the level it was pinned at.`, and in `_BreakdownRow.build` replace the `onTap:` expression with:
```dart
      onTap: canDrill && category != null && onDrill != null
          ? () => onDrill!(CategoryCrumb(
                id: category.id,
                path: category.path,
                name: category.name,
              ))
          : null,
```
(the existing `_BreakdownTab` keeps passing `onDrill: controller.drillInto`).

- [ ] **Step 6: Body and screen**

`app/lib/features/analytics/presentation/widgets/saved_view_body.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../categories/application/category_providers.dart';
import '../../../settings/application/settings_providers.dart';
import '../../../tags/application/tag_providers.dart';
import '../../application/analytics_providers.dart';
import '../../application/dashboard_anchor.dart';
import '../../application/trends_controller.dart';
import 'breakdown_body.dart';
import 'cross_tab_body.dart';
import 'patterns_body.dart';
import 'trends_body.dart';

/// A saved view at full size, drawn by the same body its tab uses.
class SavedViewBody extends ConsumerWidget {
  const SavedViewBody({super.key, required this.view, required this.anchor});

  final SavedView view;
  final DateKey anchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final calendar = ref.watch(calendarProvider);
    final firstDayOfWeek = ref.watch(firstDayOfWeekProvider);
    final formatter = ref.watch(moneyFormatterProvider);
    final spec =
        resolvedSpec(view, anchor, calendar, firstDayOfWeek: firstDayOfWeek);
    final result = ref.watch(analyticsResultProvider(spec));
    final categories = ref.watch(categoryNodesByIdProvider);
    final tags = ref.watch(tagNodesByIdProvider);

    // Names gate the chart with the answer, as on the tabs: a chart labelled
    // with raw ids is an unreadable answer, not a partial one.
    final failure = result.error ?? categories.error ?? tags.error;
    if (failure != null) {
      return NimbusErrorState(
        title: l10n.analyticsErrorTitle,
        detail: failure.toString(),
        retryLabel: l10n.commonRetry,
        onRetry: () => ref.invalidate(analyticsResultProvider(spec)),
      );
    }
    final data = result.value;
    final byCategory = categories.value;
    final byTag = tags.value;
    if (data == null || byCategory == null || byTag == null) {
      return const NimbusLoadingList();
    }
    if (data.trueCount == 0) {
      return NimbusEmptyState(
        icon: Icons.insights_outlined,
        title: l10n.analyticsEmptyTitle,
        message: l10n.analyticsEmptyBody,
      );
    }

    Widget padded(Widget chart) => ListView(
          padding: const EdgeInsets.all(NimbusTokens.space4),
          children: [chart],
        );

    return switch (view.chart) {
      SavedViewChart.breakdown => BreakdownBody(
          result: data,
          nodesById: byCategory,
          formatter: formatter,
        ),
      SavedViewChart.trend => TrendsBody(
          view: TrendsView(
            periods:
                trendPeriods(spec, calendar, firstDayOfWeek: firstDayOfWeek),
            confirmedOnly: spec.filters.confirmedOnly,
          ),
          result: data,
          formatter: formatter,
        ),
      SavedViewChart.crossTab => CrossTabBody(
          result: data,
          categoriesById: byCategory,
          tagsById: byTag,
          formatter: formatter,
        ),
      SavedViewChart.hourOfDay =>
        padded(HourOfDayChart(result: data, formatter: formatter)),
      SavedViewChart.dayOfWeek => padded(DayOfWeekChart(
          result: data,
          firstDayOfWeek: firstDayOfWeek,
          formatter: formatter,
        )),
      SavedViewChart.reflection =>
        padded(ReflectionMatrix(result: data, formatter: formatter)),
    };
  }
}
```

`app/lib/features/analytics/presentation/saved_view_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/application/settings_providers.dart';
import '../application/dashboard_anchor.dart';
import '../application/saved_view_providers.dart';
import 'widgets/month_bar.dart';
import 'widgets/saved_view_actions.dart';
import 'widgets/saved_view_body.dart';

enum _ViewAction { rename, remove }

/// One saved view, full screen.
class SavedViewScreen extends ConsumerStatefulWidget {
  const SavedViewScreen({super.key, required this.id, this.initialAnchor});

  final String id;

  /// The dashboard's month when the card was tapped; today when absent.
  final DateKey? initialAnchor;

  @override
  ConsumerState<SavedViewScreen> createState() => _SavedViewScreenState();
}

class _SavedViewScreenState extends ConsumerState<SavedViewScreen> {
  // Its own anchor, seeded from the dashboard's: moving months here must not
  // move the dashboard behind it.
  late DateKey _anchor =
      widget.initialAnchor ?? DateKey.fromDateTime(DateTime.now());

  void _shift(int months) => setState(
      () => _anchor = shiftMonths(_anchor, months, ref.read(calendarProvider)));

  Future<void> _remove() async {
    final repository = ref.read(savedViewsRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final router = GoRouter.of(context);
    // Leave first: once the row is gone this screen would show "no longer
    // exists" for a frame before closing.
    if (router.canPop()) router.pop();
    await removeSavedView(
        repository: repository, messenger: messenger, l10n: l10n, id: widget.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(savedViewByIdProvider(widget.id));
    final entry = async.hasError ? null : async.value;

    final Widget body;
    if (async.hasError) {
      body = NimbusErrorState(
        title: l10n.analyticsErrorTitle,
        detail: async.error.toString(),
        retryLabel: l10n.commonRetry,
        onRetry: () => ref.invalidate(savedViewByIdProvider(widget.id)),
      );
    } else if (!async.hasValue) {
      body = const NimbusLoadingList();
    } else {
      body = switch (entry) {
        null => NimbusEmptyState(
            icon: Icons.visibility_off_outlined,
            title: l10n.savedViewMissing,
            message: l10n.savedViewMissingBody,
          ),
        final UnreadableSavedView view => NimbusEmptyState(
            icon: Icons.error_outline,
            title: l10n.savedViewUnreadable,
            message: '${view.error}',
          ),
        final SavedView view => Column(
            children: [
              MonthBar(
                anchor: _anchor,
                onShift: _shift,
                keyPrefix: 'saved-view-period',
              ),
              Expanded(child: SavedViewBody(view: view, anchor: _anchor)),
            ],
          ),
      };
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(entry?.name ?? '', key: const Key('saved-view-title')),
        actions: [
          if (entry != null)
            PopupMenuButton<_ViewAction>(
              key: const Key('saved-view-menu'),
              tooltip: l10n.cardOptions,
              onSelected: (action) => switch (action) {
                _ViewAction.rename => renameSavedView(
                    context,
                    repository: ref.read(savedViewsRepositoryProvider),
                    id: widget.id,
                    currentName: entry.name,
                  ),
                _ViewAction.remove => _remove(),
              },
              itemBuilder: (context) => [
                if (entry is SavedView)
                  PopupMenuItem(
                    key: const Key('saved-view-menu-rename'),
                    value: _ViewAction.rename,
                    child: Text(l10n.renameView),
                  ),
                PopupMenuItem(
                  key: const Key('saved-view-menu-remove'),
                  value: _ViewAction.remove,
                  child: Text(l10n.removeView),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}
```

- [ ] **Step 7: Cards open their view**

In `saved_view_card.dart` import `package:go_router/go_router.dart` and `'../../routes.dart'`, and replace `SavedViewCard.build` with:
```dart
  @override
  Widget build(BuildContext context) => Card(
        key: Key('saved-view-card-${entry.id}'),
        // Clip so the ink splash follows the card's rounded corners.
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(savedViewLocation(entry.id, anchor)),
          child: Padding(
            padding: const EdgeInsets.all(NimbusTokens.space4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: switch (entry) {
                    final SavedView view =>
                      _Readable(view: view, anchor: anchor),
                    final UnreadableSavedView view => _Unreadable(view: view),
                  },
                ),
                // Outside the card's merged semantics, so a screen reader
                // reaches it as its own button.
                _CardMenu(entry: entry),
              ],
            ),
          ),
        ),
      );
```

- [ ] **Step 8: Run to verify GREEN**

Run: `cd app && flutter test test/features/analytics test/bootstrap`
Expected: PASS.

- [ ] **Step 9: Full gate, commit, fast-forward**

Commit message:
```
feat: open a saved view full screen

Tapping a card pushes its view over the shell, drawn by the same body
its tab uses, starting on the dashboard's month with its own arrows --
moving months there leaves the dashboard where it was. Rename and
Remove live in its menu; Remove closes the screen first and offers
Undo on the dashboard, never a confirmation.

A pinned breakdown shows the level it was pinned at and does not drill
further: the view is a saved question, not a second breakdown tab.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

### Task 12: Docs — D10, D11, the contract's open question, the status board

Branch `docs/saved-views`, slug `docs-saved-views`. No code; no RED step.

**Files:**
- Modify: `docs/phases/DEFERRED.md` (D10, D11 — open items above the resolved ones, matching the table's existing order)
- Modify: `docs/superpowers/screen-contract.md` (§9 question 3)
- Modify: `docs/phases/README.md` (Phase 3 row)

- [ ] **Step 1: Tag** — `git tag pre-docs-saved-views`

- [ ] **Step 2: DEFERRED.md** — add table rows (open section) and sections, following the existing entries' format:

```markdown
| D10 | No saved-view builder: views can only be pinned from what a tab shows | "#travel by category" and other tag-scoped views cannot be pinned | Next analytics phase, or on demand |
| D11 | Breakdown header reads "This month" for whichever month is shown | Nothing blocked; the label is wrong on past months, in the tab and the full-screen view | Next change touching the breakdown |
```

```markdown
## D10 — No saved-view builder

**Status:** open. Decided 2026-09-27 with the operator while designing
Phase 3 tasks 13–14 (`docs/superpowers/specs/2026-09-27-saved-views-dashboard-design.md`).

Views are pinned from what a tab shows. The screen contract's §5.7 builder —
every filter, the grouping, the chart and the period, with a live preview —
was deferred as the largest piece of the phase. Until it exists a view cannot
be scoped by tag, payment method, necessity, amount or text, and a pinned
view's question cannot be edited after the fact (rename only). The
`saved_views.pinned` column stays in the schema for the builder's unpinned
library. When it lands it reopens the screen contract's open question 3:
which charts a builder offers for which groupings.

## D11 — Breakdown header reads "This month" for any month

**Status:** open. Found 2026-09-27 while planning the full-screen saved view.

`BreakdownBody` labels its total with `txMonthTotal` ("This month") whatever
the period. The Breakdown tab's ◀ ▶ can show a past month under that label,
and the full-screen saved view, which reuses the body, inherits it. Fix: label
with the period (`periodLabel`) or a neutral "Total".
```

- [ ] **Step 3: screen-contract.md §9 question 3** — replace the item's text with:

```markdown
3. **Chart type per saved view** — *answered 2026-09-27 for pinning:* the
   chart is fixed by where a view was pinned from (`SavedViewChart`), so a
   spec can never be paired with a chart that cannot draw it, and a view's
   spec cannot change after pinning. The builder (D10) reopens this: which
   chart types it offers for which group-by combinations.
```

- [ ] **Step 4: README.md** — Phase 3 row's status becomes:

```markdown
**Engine complete** (2026-08-29); tasks 9–12 (breakdown, trends and period comparison, tag × category cross-tab, patterns and the necessity × satisfaction matrix) done 2026-09-07, on `main` since 2026-09-27; 13–14 (saved views, dashboard) done 2026-09-27 on `phase/3-saved-views`, awaiting the device check; 15 (performance pass) remains — builder deferred as [D10](DEFERRED.md#d10--no-saved-view-builder)
```

- [ ] **Step 5: Gate, commit, fast-forward**

Run `dart analyze --fatal-infos` (docs only; the rest unchanged). Commit message:
```
docs: saved views and the dashboard are in; D10 and D11 recorded

D10 records the builder the operator deferred: views are pinned from
what a tab shows, so tag-scoped views wait for it. D11 records a
pre-existing label bug the full-screen view inherits. The screen
contract's open question on chart types is answered for pinning and
left open for the builder.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

---

## After the tasks: device check (operator)

Build and install the debug APK over the existing install (data kept; `adb` is at `C:/dev/android-sdk/platform-tools/adb.exe`, not on PATH):

```bash
cd app && flutter build apk --debug
C:/dev/android-sdk/platform-tools/adb.exe -s RZCT209E3QX install -r build/app/outputs/flutter-apk/app-debug.apk
```

On the A53, then report what you see:
1. Analytics opens on **Dashboard**, empty → **Add starter cards** → two cards with totals.
2. Add an expense from Home, return to Analytics → the "This month by category" total includes it (the Task 2 fix).
3. Breakdown → tap Food → 📌 → Save → a "Food" card appears at the bottom of the dashboard.
4. Pin one chart each from Trends, Tags × categories and Patterns.
5. Long-press a card and drag it; kill and reopen the app → the order held.
6. ⋮ → Remove → Undo → the card returns in place. ⋮ → Rename works.
7. ◀ on the dashboard → every card moves back a month; tap a card → full screen on that month; ▶ there does not move the dashboard.
8. Switch the app to Persian → cards right-to-left with Persian digits.

Then the soak: use it normally for a while before task 15, which gets its own plan (spec §8).
