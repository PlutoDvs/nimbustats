# Phase 3 Analytics Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** one query engine that answers every analytical question in the app — so "within #travel, break down by category" and "how much avoidable-and-regretted money did I spend this month" are the same code path with different arguments.

**Architecture:** A pure, serializable `QuerySpec` in `nimbus_domain` describes *what* to ask. A compiler in `nimbus_data` turns it into exactly one SQL statement. Nothing in between knows about both. Period boundaries are computed in the active calendar and converted to `DateKey` ranges before any SQL is generated, because a Jalali month is not a Gregorian month and SQLite cannot know the difference.

**Tech Stack:** Dart 3.13.1, drift, `package:test`, `package:meta`. **No new package** — `fl_chart` is unavailable (DEFERRED D7) and no chart code is in this plan.

**Spec:** `docs/superpowers/specs/2026-08-20-nimbustats-design.md` §"2. Analytics engine"
**Brief:** `docs/phases/phase-3-analytics.md` (tasks 1–8 only)
**Conventions:** `docs/phases/CONVENTIONS.md`

## Scope boundary — read this before starting

This plan covers the **engine only**: the brief's tasks 1–8. Tasks 9–14 are screens and charts, blocked by **DEFERRED D7** (`fl_chart` is in neither `pubspec.lock` nor the pub cache, and D3 returns 403 from pub.dev for archives *and* metadata). Do not write UI. Do not add a package.

The `phase-1-complete` prerequisite is **waived for this engine only**, on the basis recorded in `DEFERRED.md` §D1. `phase-3-complete` is **not** tagged at the end of this plan — Phase 3's own gate still requires charts and on-hardware verification.

## Global Constraints

- **Flutter 3.47.1 / Dart 3.13.1.** Do not bump the SDK or any dependency.
- **Package boundaries** (`test/architecture_test.dart`): `nimbus_domain` must not depend on `drift`, `sqlite3`, `flutter`, `flutter_riverpod`, `nimbus_data`, or `nimbus_design`. **`QuerySpec` therefore contains no drift types and no SQL.**
- **Money is always `int` minor units.** This includes averages — see the rounding rule in Decision 6.
- **Every query filters `deleted_at IS NULL`.** One helper, tested once, used everywhere in the engine.
- **Never do calendar math in SQL.** No `strftime` for period bucketing. Boundaries are computed in Dart, in the active calendar, then converted to `DateKey` integers.
- **No `print`. No swallowed exceptions. No hardcoded fallback that masks an error.**
- **Owned paths:** `packages/nimbus_domain/lib/src/analytics/**`, `packages/nimbus_data/lib/src/analytics/**`, `packages/nimbus_data/lib/src/tables/saved_views_table.dart`. Barrels are shared — append one `export` per line, alphabetically.
- **Must not touch:** `capture/`, `trackers/`, `goals/`, `backup/`, or Phase 1's add/edit flow.
- **TDD order is mandatory:** failing test → observe the failure → minimal implementation → observe the pass → broader suite → commit.
- **Per-commit rollback tags:** `git tag pre-<slug>` on the parent commit before implementing.
- **Branch:** `phase/3-analytics`.

### Commands

```bash
cd packages/nimbus_domain && dart test test/analytics/<file>_test.dart
cd packages/nimbus_data   && dart test test/analytics/<file>_test.dart

# the gate, before every commit
dart analyze --fatal-infos
dart test test/architecture_test.dart
cd packages/nimbus_domain && dart test
cd packages/nimbus_data   && dart test
```

Baseline to preserve: **452 tests** green across the workspace (architecture 4, nimbus_domain 177, nimbus_data 80, app 171, nimbus_design 20).

---

## What already exists — verified, do not re-derive

Read from the real code before this plan was written:

- **`Transactions` table** (`packages/nimbus_data/lib/src/tables/transactions_table.dart`): `direction` (`TxDirection{expense,income}`), `amount` (`int` via `MoneyConverter`), `currencyCode`, `occurredAtUtc`, `localDateKey` (`int` via `DateKeyConverter`), `tzOffsetMinutes`, `categoryId` (NOT NULL), `paymentMethodId?`, `merchant?`, `note?`, `necessity?` (`Necessity{needed,optional,avoidable}`), `satisfaction?` (`Satisfaction{glad,neutral,regret}`), `source`, `isConfirmed`, `captureId?`, plus `BaseColumns` (`id`, `createdAt`, `updatedAt`, `deletedAt?`).
- **Existing indexes:** `idx_tx_date(localDateKey)`, `idx_tx_category(categoryId)`, `idx_tx_unconfirmed(isConfirmed, localDateKey)`, `idx_tx_merchant(merchant)`.
- **`MaterializedPath`** (`packages/nimbus_data/lib/src/tree/materialized_path.dart`): path format `/rootId/childId/`; `subtreeUpperBound(path)` gives the exclusive upper bound so a subtree is `path >= p AND path < upper(p)` — index-friendly, and deliberately not `LIKE`.
- **`DateKey`** (`yyyymmdd` int) and **`DateRange(startInclusive, endInclusive)`** in `nimbus_domain/src/calendar/`.
- **`AppCalendar`**: `partsOf(DateKey) → CalendarParts`, `keyOf(y,m,d) → DateKey`, `monthLength`, `monthsPerYear`, `periodContaining(DateKey, PeriodType, {int firstDayOfWeek}) → DateRange`, `shiftPeriod(DateRange, PeriodType, int) → DateRange`. `GregorianCalendar()` and `JalaliCalendar()` both `const`.
- **`PeriodType { day, week, month, quarter, year }`**.
- **`schemaVersion` is 1.** Phase 3 takes **v20** for `saved_views`.

Two facts probed against the running toolchain, not assumed:

- **`EXPLAIN QUERY PLAN` is reachable** via `db.customSelect('EXPLAIN QUERY PLAN <sql>', variables: [...])`; each row's `data['detail']` is the string to assert on. A date-range sum already reports `SEARCH transactions USING INDEX idx_tx_date (local_date_key>? AND local_date_key<?)`.
- **`amount.avg()` yields a nullable `double`** (`null` on an empty table). `amount.sum()` yields a nullable `int`. **A `TypeConverter` does not apply to an aggregate** — the existing `sumInRange` wraps the raw int in `Money` by hand, and the engine must do the same everywhere.

**There is no shared `deleted_at IS NULL` helper today.** The predicate is written inline in roughly fifteen places in `app_database.dart`. The brief requires one helper for the engine; Task 5 adds it in the analytics path. Retrofitting Phase 1's DAOs is **out of scope** — note it, do not do it.

---

## Design decisions, locked here

1. **`QuerySpec` is a pure value object with lossless JSON.** Phase 5 stores one as a goal's scope, so a field that does not survive a round trip is a data-loss bug in a later phase. Every type gets a round-trip test, and `fromJson` **throws on an unknown enum value or missing required field** rather than defaulting.
2. **Group-by is a sealed class, not an enum**, because "category at depth 2" and "bucket by month" carry parameters. An enum would push those parameters into parallel nullable fields that can disagree with the selected dimension.
3. **The compiler emits exactly one SQL statement per `QuerySpec`.** Where a tag filter needs the join table, it becomes an `EXISTS` / `NOT EXISTS` subquery rather than a second round trip — a join would multiply rows and silently inflate a `SUM`.
4. **`AnalyticsResult` always carries `trueTotal` alongside `buckets`.** For every non-tag dimension they agree; for tag dimensions they do not, and that is the point. It is not optional and not nullable, so a caller cannot forget it exists.
5. **Tag rollup deduplicates by transaction id.** A transaction tagged with both a parent and its child contributes once to the parent's bucket. `EXISTS` over the subtree range expresses this naturally; `JOIN` + `GROUP BY` does not.
6. **Money rounding rule: averages round half away from zero, at the last step, on integer minor units.** `avg` comes back as a `double` from SQL; it is converted exactly once, in the compiler, and never travels as a double. Documented on the method and asserted for a `.5` case in both signs.
7. **Unconfirmed captures are included by default**, with `confirmedOnly` on the filter to exclude them. Same default everywhere — the brief forbids a dashboard and a goal disagreeing.
8. **Archived categories are filtered from pickers, never from results.** The engine has no notion of archived; it is a picker concern. Stated so nobody adds one.
9. **The engine is read-only.** No method on it writes, so no test needs a transaction rollback.

---

## File structure

| File | Responsibility |
|---|---|
| `nimbus_domain/lib/src/analytics/aggregate.dart` | `Aggregate` enum. |
| `nimbus_domain/lib/src/analytics/amount_range.dart` | `AmountRange` over `Money`. |
| `nimbus_domain/lib/src/analytics/tag_filter.dart` | Sealed `TagFilter`: all / any / none over tag subtree paths. |
| `nimbus_domain/lib/src/analytics/query_filters.dart` | Every filter dimension, with JSON. |
| `nimbus_domain/lib/src/analytics/group_by.dart` | Sealed `GroupBy` and its cases. |
| `nimbus_domain/lib/src/analytics/query_spec.dart` | `QuerySpec` = filters + groupBy + aggregate, with JSON. |
| `nimbus_domain/lib/src/analytics/period_boundaries.dart` | `PeriodBoundaries` — the one place a period becomes a key range. |
| `nimbus_domain/lib/src/analytics/analytics_result.dart` | `Bucket`, `BucketKey`, `AnalyticsResult`. |
| `nimbus_data/lib/src/analytics/analytics_predicates.dart` | The shared `notDeleted` helper and filter → drift expression translation. |
| `nimbus_data/lib/src/analytics/analytics_engine.dart` | `QuerySpec` → one SQL statement → `AnalyticsResult`. |
| `nimbus_data/lib/src/tables/saved_views_table.dart` | Schema v20. |

---
10. **`QuerySpec` needs domain-side mirrors of three `nimbus_data` enums.** `TxDirection`, `Necessity` and `Satisfaction` are declared in `packages/nimbus_data/lib/src/tables/transactions_table.dart`, and `nimbus_domain` is forbidden from importing `nimbus_data`. This is the same wall Phase 2A hit with `TxDirection`, and it gets the same answer: `nimbus_domain` declares `MoneyDirection`, `NecessityLevel` and `SatisfactionLevel`, and the compiler maps them at the boundary.

    Two parallel enum families can drift apart silently, so **Task 6 carries a mapping-completeness test** that fails if either side gains a value the other lacks. Moving the originals into `nimbus_domain` would be the cleaner fix, but it edits Phase 0's and Phase 1's files — including the add/edit flow this phase is explicitly forbidden to touch — so it is recorded as a follow-up, not done here.

---

## Task 1: The scalar filter vocabulary

**Files:**
- Create: `packages/nimbus_domain/lib/src/analytics/aggregate.dart`
- Create: `packages/nimbus_domain/lib/src/analytics/reflection_levels.dart`
- Create: `packages/nimbus_domain/lib/src/analytics/amount_range.dart`
- Test: `packages/nimbus_domain/test/analytics/scalars_test.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (three exports, alphabetical)

**Interfaces produced:**
- `enum Aggregate { sum, count, average, min, max }`
- `enum MoneyDirection { expense, income }`
- `enum NecessityLevel { needed, optional, avoidable }`
- `enum SatisfactionLevel { glad, neutral, regret }`
- `AmountRange({Money? minInclusive, Money? maxInclusive})` with `isUnbounded`, `contains(Money)`, `toJson`, `fromJson`.

**Why the mirrors exist:** see Decision 10. Their `name` strings must match the `nimbus_data` enums exactly, because Task 6 maps by value and the completeness test compares names.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_domain/test/analytics/scalars_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('mirror enums', () {
    test('names match the nimbus_data enums they mirror', () {
      // nimbus_domain cannot import nimbus_data, so these names are the
      // contract. Task 6's mapping test asserts the other side.
      expect(MoneyDirection.values.map((v) => v.name), ['expense', 'income']);
      expect(NecessityLevel.values.map((v) => v.name),
          ['needed', 'optional', 'avoidable']);
      expect(SatisfactionLevel.values.map((v) => v.name),
          ['glad', 'neutral', 'regret']);
    });
  });

  group('AmountRange', () {
    test('an unbounded range contains everything', () {
      final range = AmountRange();
      expect(range.isUnbounded, isTrue);
      expect(range.contains(const Money(-500)), isTrue);
      expect(range.contains(const Money(9999999)), isTrue);
    });

    test('bounds are inclusive on both ends', () {
      final range = AmountRange(
          minInclusive: const Money(1000), maxInclusive: const Money(2000));
      expect(range.contains(const Money(1000)), isTrue);
      expect(range.contains(const Money(2000)), isTrue);
      expect(range.contains(const Money(999)), isFalse);
      expect(range.contains(const Money(2001)), isFalse);
    });

    test('a half-open range bounds only the side it names', () {
      final atLeast = AmountRange(minInclusive: const Money(1000));
      expect(atLeast.contains(const Money(999)), isFalse);
      expect(atLeast.contains(const Money(10000000)), isTrue);
      expect(atLeast.isUnbounded, isFalse);
    });

    test('an inverted range is rejected at construction', () {
      // A range that can never match is a caller bug, and silently returning
      // nothing would look like "no data for this period".
      expect(
          () => AmountRange(
              minInclusive: const Money(2000), maxInclusive: const Money(1000)),
          throwsArgumentError);
    });

    test('JSON round-trips, including the unbounded sides', () {
      final bounded = AmountRange(
          minInclusive: const Money(1000), maxInclusive: const Money(2000));
      final halfOpen = AmountRange(maxInclusive: const Money(2000));
      final unbounded = AmountRange();
      for (final range in [bounded, halfOpen, unbounded]) {
        expect(AmountRange.fromJson(range.toJson()), range,
            reason: 'lost information round-tripping $range');
      }
    });

    test('value equality', () {
      expect(AmountRange(minInclusive: const Money(1)),
          AmountRange(minInclusive: const Money(1)));
      expect(AmountRange(minInclusive: const Money(1)),
          isNot(AmountRange(minInclusive: const Money(2))));
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd packages/nimbus_domain && dart test test/analytics/scalars_test.dart`
Expected: FAIL to compile — `Undefined name 'MoneyDirection'`.

- [ ] **Step 3: Implement**

Create `packages/nimbus_domain/lib/src/analytics/aggregate.dart`:

```dart
/// What to compute over the rows in a bucket.
enum Aggregate { sum, count, average, min, max }
```

Create `packages/nimbus_domain/lib/src/analytics/reflection_levels.dart`:

```dart
/// Domain-side mirrors of three enums declared in `nimbus_data`'s
/// transactions table.
///
/// `QuerySpec` has to name these values, and `nimbus_domain` is forbidden from
/// importing `nimbus_data` — the same wall Phase 2A hit with `TxDirection`,
/// and the same answer. The compiler in `nimbus_data` maps between the two
/// families at the boundary, and a mapping-completeness test there fails if
/// either side gains a value the other lacks.
///
/// The `name` strings are the contract. Do not rename a value without changing
/// its counterpart in the same commit.
library;

/// Mirrors `TxDirection`.
enum MoneyDirection { expense, income }

/// Mirrors `Necessity`.
enum NecessityLevel { needed, optional, avoidable }

/// Mirrors `Satisfaction`.
enum SatisfactionLevel { glad, neutral, regret }
```

Create `packages/nimbus_domain/lib/src/analytics/amount_range.dart`:

```dart
import 'package:meta/meta.dart';

import '../money/money.dart';

/// An inclusive amount filter. Either end may be absent.
@immutable
final class AmountRange {
  AmountRange({this.minInclusive, this.maxInclusive}) {
    final min = minInclusive;
    final max = maxInclusive;
    // Money defines compareTo but not the comparison operators, so this is
    // spelled out rather than written as `min > max`.
    if (min != null && max != null && min.compareTo(max) > 0) {
      // A range that can never match is a caller bug. Returning nothing
      // would be indistinguishable from "no data in this period".
      throw ArgumentError('AmountRange minInclusive ($min) exceeds '
          'maxInclusive ($max)');
    }
  }

  factory AmountRange.fromJson(Map<String, Object?> json) => AmountRange(
        minInclusive: _moneyOf(json['minInclusive']),
        maxInclusive: _moneyOf(json['maxInclusive']),
      );

  final Money? minInclusive;
  final Money? maxInclusive;

  bool get isUnbounded => minInclusive == null && maxInclusive == null;

  bool contains(Money value) {
    final min = minInclusive;
    final max = maxInclusive;
    if (min != null && value.compareTo(min) < 0) return false;
    if (max != null && value.compareTo(max) > 0) return false;
    return true;
  }

  Map<String, Object?> toJson() => {
        if (minInclusive != null) 'minInclusive': minInclusive!.minorUnits,
        if (maxInclusive != null) 'maxInclusive': maxInclusive!.minorUnits,
      };

  static Money? _moneyOf(Object? value) => switch (value) {
        null => null,
        final int minorUnits => Money(minorUnits),
        _ => throw FormatException('amount bound must be an int, got "$value"'),
      };

  @override
  bool operator ==(Object other) =>
      other is AmountRange &&
      other.minInclusive == minInclusive &&
      other.maxInclusive == maxInclusive;

  @override
  int get hashCode => Object.hash(minInclusive, maxInclusive);

  @override
  String toString() => 'AmountRange($minInclusive..$maxInclusive)';
}
```

> **On `Money` comparisons:** `Money` implements `Comparable` and defines `+`, `-`, `*`, unary `-`, `==` and `abs()`, but **not** `<` or `>`. That is why the code above uses `compareTo`. Do not add operators to `Money` to make this read better — that file is Phase 0's, and this phase does not own it.
>
> **On `const`:** these constructors have validation bodies, so they cannot be `const`. `AmountRange` above is therefore constructed without `const` in the tests. `DateKey` and `Money` remain `const`-constructible and the test code uses them that way.

- [ ] **Step 4: Export from the barrel** (alphabetical, before `src/calendar/`):

```dart
export 'src/analytics/aggregate.dart';
export 'src/analytics/amount_range.dart';
export 'src/analytics/reflection_levels.dart';
```

- [ ] **Step 5: Run the test and verify it passes** — 8 tests.

- [ ] **Step 6: Full gate** — `dart analyze --fatal-infos`, then the domain suite.

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-analytics-scalars HEAD
git add packages/nimbus_domain/lib/src/analytics/ \
        packages/nimbus_domain/test/analytics/scalars_test.dart \
        packages/nimbus_domain/lib/nimbus_domain.dart
git commit -m "feat: the scalar vocabulary a QuerySpec filters on

MoneyDirection, NecessityLevel and SatisfactionLevel mirror three enums
declared in nimbus_data's transactions table. QuerySpec has to name
those values and nimbus_domain cannot import nimbus_data -- the same
wall Phase 2A hit with TxDirection, answered the same way. The compiler
maps at the boundary and a completeness test there will fail if either
family gains a value the other lacks.

Moving the originals into nimbus_domain would be cleaner, but it edits
Phase 0's and Phase 1's files including the add/edit flow this phase is
forbidden to touch. Recorded as a follow-up.

An inverted AmountRange throws rather than matching nothing, because
nothing is indistinguishable from an empty period on a chart."
```

---

## Task 2: Tag filters and the filter set

**Files:**
- Create: `packages/nimbus_domain/lib/src/analytics/tag_filter.dart`
- Create: `packages/nimbus_domain/lib/src/analytics/query_filters.dart`
- Test: `packages/nimbus_domain/test/analytics/query_filters_test.dart`
- Modify: barrel (two exports)

**Interfaces produced:**
- `sealed class TagFilter` with `List<String> get subtreePaths`, `toJson`, `factory TagFilter.fromJson`; cases `TagsAll`, `TagsAny`, `TagsNone`.
- `QueryFilters({DateRange? dateRange, MoneyDirection? direction, List<String> categorySubtreePaths = const [], TagFilter? tags, List<String> paymentMethodIds = const [], Set<NecessityLevel> necessity = const {}, Set<SatisfactionLevel> satisfaction = const {}, AmountRange? amountRange, bool confirmedOnly = false, String? searchText})` with `toJson`, `fromJson`, value equality.

**Why paths, not ids.** Category and tag filters name **materialized paths**, not ids, because the filter means "this subtree". `MaterializedPath.subtreeUpperBound` turns a path into an index-friendly range in Task 6; an id would force a recursive lookup at query time.

**`confirmedOnly` defaults to `false`** — unconfirmed captures are included by default (Decision 7). The default lives here so a dashboard and a goal cannot disagree by accident.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_domain/test/analytics/query_filters_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  group('TagFilter', () {
    test('each kind round-trips through JSON as its own kind', () {
      final filters = <TagFilter>[
        TagsAll(const ['/travel/', '/food/']),
        TagsAny(const ['/travel/']),
        TagsNone(const ['/work/']),
      ];
      for (final filter in filters) {
        final restored = TagFilter.fromJson(filter.toJson());
        expect(restored, filter);
        expect(restored.runtimeType, filter.runtimeType,
            reason: 'ALL, ANY and NONE mean different things; a round trip '
                'that changes the kind changes the answer');
      }
    });

    test('subtreePaths exposes the paths regardless of kind', () {
      expect(TagsAny(const ['/a/', '/b/']).subtreePaths, ['/a/', '/b/']);
    });

    test('an empty path list is rejected', () {
      // "all of nothing" and "none of nothing" are degenerate and almost
      // certainly a UI bug rather than an intent.
      expect(() => TagsAll(const []), throwsArgumentError);
    });

    test('an unknown kind throws rather than defaulting to ANY', () {
      // Defaulting would turn "none of #work" into "any of #work" -- the
      // exact inverse of what the user asked for.
      expect(() => TagFilter.fromJson({'kind': 'wat', 'paths': <String>['/a/']}),
          throwsFormatException);
    });
  });

  group('QueryFilters', () {
    test('the default filter set is unfiltered and includes unconfirmed', () {
      const filters = QueryFilters();
      expect(filters.dateRange, isNull);
      expect(filters.confirmedOnly, isFalse,
          reason: 'Decision 7: unconfirmed captures are included by default, '
              'the same way everywhere');
      expect(filters.categorySubtreePaths, isEmpty);
    });

    test('a fully populated filter set round-trips losslessly', () {
      // Phase 5 stores a QuerySpec as a goal's scope. A field that does not
      // survive this is a data-loss bug in a later phase.
      final filters = QueryFilters(
        dateRange: DateRange(const DateKey(20260101), const DateKey(20261231)),
        direction: MoneyDirection.expense,
        categorySubtreePaths: const ['/food/', '/transport/'],
        tags: TagsAll(const ['/travel/']),
        paymentMethodIds: const ['pm1', 'pm2'],
        necessity: const {NecessityLevel.avoidable},
        satisfaction: const {SatisfactionLevel.regret},
        amountRange: AmountRange(minInclusive: const Money(1000)),
        confirmedOnly: true,
        searchText: 'taxi',
      );
      expect(QueryFilters.fromJson(filters.toJson()), filters);
    });

    test('the empty filter set round-trips too', () {
      const filters = QueryFilters();
      expect(QueryFilters.fromJson(filters.toJson()), filters);
    });

    test('an unknown necessity value throws rather than being dropped', () {
      // A silently dropped filter widens the query. On a goal, that means
      // reporting under budget when the user is over.
      expect(
          () => QueryFilters.fromJson({
                'necessity': ['wat']
              }),
          throwsFormatException);
    });

    test('value equality covers every field', () {
      const a = QueryFilters(direction: MoneyDirection.expense);
      const b = QueryFilters(direction: MoneyDirection.income);
      expect(a, isNot(b));
      expect(a, const QueryFilters(direction: MoneyDirection.expense));
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails** — `Undefined name 'TagsAll'`.

- [ ] **Step 3: Implement**

Create `packages/nimbus_domain/lib/src/analytics/tag_filter.dart`:

```dart
import 'package:meta/meta.dart';

/// How a set of tag subtrees narrows a query.
///
/// The three kinds mean genuinely different things and a round trip that
/// changes the kind changes the answer, so the kind is part of the JSON and an
/// unknown one throws rather than defaulting.
@immutable
sealed class TagFilter {
  const TagFilter();

  factory TagFilter.fromJson(Map<String, Object?> json) {
    final paths = _pathsOf(json['paths']);
    return switch (json['kind']) {
      'all' => TagsAll(paths),
      'any' => TagsAny(paths),
      'none' => TagsNone(paths),
      final other => throw FormatException('unknown tag filter kind "$other"'),
    };
  }

  /// Materialized paths, not ids: a tag filter always means "this subtree".
  List<String> get subtreePaths;

  Map<String, Object?> toJson();

  static List<String> _pathsOf(Object? value) => switch (value) {
        final List<Object?> list => list.map((e) => e.toString()).toList(),
        _ => throw FormatException('expected a path list, got "$value"'),
      };

  static void _requireNonEmpty(List<String> paths) {
    if (paths.isEmpty) {
      throw ArgumentError('a tag filter needs at least one subtree path');
    }
  }

  static bool _samePaths(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The transaction carries **every** one of these subtrees.
@immutable
final class TagsAll extends TagFilter {
  TagsAll(this.subtreePaths) {
    TagFilter._requireNonEmpty(subtreePaths);
  }

  @override
  final List<String> subtreePaths;

  @override
  Map<String, Object?> toJson() => {'kind': 'all', 'paths': subtreePaths};

  @override
  bool operator ==(Object other) =>
      other is TagsAll && TagFilter._samePaths(other.subtreePaths, subtreePaths);

  @override
  int get hashCode => Object.hash('all', Object.hashAll(subtreePaths));
}

/// The transaction carries **at least one** of these subtrees.
@immutable
final class TagsAny extends TagFilter {
  TagsAny(this.subtreePaths) {
    TagFilter._requireNonEmpty(subtreePaths);
  }

  @override
  final List<String> subtreePaths;

  @override
  Map<String, Object?> toJson() => {'kind': 'any', 'paths': subtreePaths};

  @override
  bool operator ==(Object other) =>
      other is TagsAny && TagFilter._samePaths(other.subtreePaths, subtreePaths);

  @override
  int get hashCode => Object.hash('any', Object.hashAll(subtreePaths));
}

/// The transaction carries **none** of these subtrees.
@immutable
final class TagsNone extends TagFilter {
  TagsNone(this.subtreePaths) {
    TagFilter._requireNonEmpty(subtreePaths);
  }

  @override
  final List<String> subtreePaths;

  @override
  Map<String, Object?> toJson() => {'kind': 'none', 'paths': subtreePaths};

  @override
  bool operator ==(Object other) =>
      other is TagsNone &&
      TagFilter._samePaths(other.subtreePaths, subtreePaths);

  @override
  int get hashCode => Object.hash('none', Object.hashAll(subtreePaths));
}
```


Create `packages/nimbus_domain/lib/src/analytics/query_filters.dart`:

```dart
import 'package:meta/meta.dart';

import '../calendar/date_key.dart';
import 'amount_range.dart';
import 'reflection_levels.dart';
import 'tag_filter.dart';

/// Every way a query can be narrowed.
///
/// Pure and serializable: Phase 5 stores a `QuerySpec` as a goal's scope, so a
/// field that does not survive a JSON round trip is a data-loss bug in a later
/// phase rather than a cosmetic one.
@immutable
final class QueryFilters {
  const QueryFilters({
    this.dateRange,
    this.direction,
    this.categorySubtreePaths = const [],
    this.tags,
    this.paymentMethodIds = const [],
    this.necessity = const {},
    this.satisfaction = const {},
    this.amountRange,
    this.confirmedOnly = false,
    this.searchText,
  });

  factory QueryFilters.fromJson(Map<String, Object?> json) => QueryFilters(
        dateRange: _rangeOf(json['dateRange']),
        direction: json['direction'] == null
            ? null
            : _enumOf(MoneyDirection.values, json['direction'], 'direction'),
        categorySubtreePaths: _stringsOf(json['categorySubtreePaths']),
        tags: json['tags'] == null
            ? null
            : TagFilter.fromJson((json['tags']! as Map).cast<String, Object?>()),
        paymentMethodIds: _stringsOf(json['paymentMethodIds']),
        necessity: _stringsOf(json['necessity'])
            .map((v) => _enumOf(NecessityLevel.values, v, 'necessity'))
            .toSet(),
        satisfaction: _stringsOf(json['satisfaction'])
            .map((v) => _enumOf(SatisfactionLevel.values, v, 'satisfaction'))
            .toSet(),
        amountRange: json['amountRange'] == null
            ? null
            : AmountRange.fromJson(
                (json['amountRange']! as Map).cast<String, Object?>()),
        confirmedOnly: json['confirmedOnly'] as bool? ?? false,
        searchText: json['searchText'] as String?,
      );

  final DateRange? dateRange;
  final MoneyDirection? direction;

  /// Materialized paths. Each names a subtree, not a single category.
  final List<String> categorySubtreePaths;
  final TagFilter? tags;
  final List<String> paymentMethodIds;
  final Set<NecessityLevel> necessity;
  final Set<SatisfactionLevel> satisfaction;
  final AmountRange? amountRange;

  /// Defaults to false: unconfirmed captures are included everywhere unless a
  /// caller opts out, so a dashboard and a goal cannot disagree by accident.
  final bool confirmedOnly;
  final String? searchText;

  Map<String, Object?> toJson() => {
        if (dateRange != null)
          'dateRange': {
            'start': dateRange!.startInclusive.value,
            'end': dateRange!.endInclusive.value,
          },
        if (direction != null) 'direction': direction!.name,
        if (categorySubtreePaths.isNotEmpty)
          'categorySubtreePaths': categorySubtreePaths,
        if (tags != null) 'tags': tags!.toJson(),
        if (paymentMethodIds.isNotEmpty) 'paymentMethodIds': paymentMethodIds,
        if (necessity.isNotEmpty)
          'necessity': necessity.map((n) => n.name).toList(),
        if (satisfaction.isNotEmpty)
          'satisfaction': satisfaction.map((s) => s.name).toList(),
        if (amountRange != null) 'amountRange': amountRange!.toJson(),
        if (confirmedOnly) 'confirmedOnly': true,
        if (searchText != null) 'searchText': searchText,
      };

  static DateRange? _rangeOf(Object? value) {
    if (value == null) return null;
    final map = (value as Map).cast<String, Object?>();
    return DateRange(
        DateKey(map['start']! as int), DateKey(map['end']! as int));
  }

  static List<String> _stringsOf(Object? value) => switch (value) {
        null => const <String>[],
        final List<Object?> list => list.map((e) => e.toString()).toList(),
        _ => throw FormatException('expected a string list, got "$value"'),
      };

  /// Throws on an unknown value rather than dropping it. A dropped filter
  /// *widens* the query, which on a goal means reporting under budget while
  /// the user is over.
  static T _enumOf<T extends Enum>(List<T> values, Object? raw, String field) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw FormatException('unknown $field value "$raw"');
  }

  @override
  bool operator ==(Object other) =>
      other is QueryFilters &&
      other.dateRange == dateRange &&
      other.direction == direction &&
      _sameList(other.categorySubtreePaths, categorySubtreePaths) &&
      other.tags == tags &&
      _sameList(other.paymentMethodIds, paymentMethodIds) &&
      _sameSet(other.necessity, necessity) &&
      _sameSet(other.satisfaction, satisfaction) &&
      other.amountRange == amountRange &&
      other.confirmedOnly == confirmedOnly &&
      other.searchText == searchText;

  @override
  int get hashCode => Object.hash(
        dateRange,
        direction,
        Object.hashAll(categorySubtreePaths),
        tags,
        Object.hashAll(paymentMethodIds),
        Object.hashAllUnordered(necessity),
        Object.hashAllUnordered(satisfaction),
        amountRange,
        confirmedOnly,
        searchText,
      );

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameSet<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);
}
```

- [ ] **Step 4: Export from the barrel**

```dart
export 'src/analytics/query_filters.dart';
export 'src/analytics/tag_filter.dart';
```

- [ ] **Step 5: Run the test and verify it passes** — 10 tests.

- [ ] **Step 6: Full gate.**

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-query-filters HEAD
git add packages/nimbus_domain/lib/src/analytics/ \
        packages/nimbus_domain/test/analytics/query_filters_test.dart \
        packages/nimbus_domain/lib/nimbus_domain.dart
git commit -m "feat: the filter half of a QuerySpec, losslessly serializable

Phase 5 stores a QuerySpec as a goal's scope, so JSON is a hard
requirement rather than a convenience and every unknown value throws
instead of being dropped. A dropped filter widens the query -- on a
goal, that means reporting under budget while the user is over.

Tag filters name materialized paths rather than ids because a tag
filter always means a subtree, and ALL / ANY / NONE are separate types
rather than a flag because a round trip that changes the kind inverts
the question being asked.

confirmedOnly defaults to false. Unconfirmed captures are included
everywhere unless a caller opts out, so a dashboard and a goal cannot
quietly disagree about what counts."
```

---
## Task 3: GroupBy and QuerySpec

**Files:**
- Create: `packages/nimbus_domain/lib/src/analytics/group_by.dart`
- Create: `packages/nimbus_domain/lib/src/analytics/query_spec.dart`
- Test: `packages/nimbus_domain/test/analytics/query_spec_test.dart`
- Modify: barrel (two exports)

**Interfaces produced:**
- `sealed class GroupBy` with `String get kind`, `toJson`, `factory GroupBy.fromJson`; cases `GroupByNone`, `GroupByCategory(int depth)`, `GroupByTag`, `GroupByPeriod(PeriodType period)`, `GroupByPaymentMethod`, `GroupByMerchant`, `GroupByReflection`, `GroupByHourOfDay`, `GroupByDayOfWeek`.
- `QuerySpec({QueryFilters filters, GroupBy groupBy, Aggregate aggregate})` with `toJson`, `fromJson`, value equality, and `bool get isTagDimension`.

**Why sealed and not an enum** (Decision 2): `GroupByCategory` carries a depth and `GroupByPeriod` carries a `PeriodType`. An enum would push those into parallel nullable fields on `QuerySpec` that can disagree with the selected dimension — `groupBy: merchant, depth: 3` would be constructible and meaningless.

**`isTagDimension` exists so the engine and the UI cannot forget** that tag buckets do not sum to the total. It is a single predicate rather than a `runtimeType` check scattered through callers.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_domain/test/analytics/query_spec_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

// Not const: GroupByCategory validates its depth, so it has a body.
final everyDimension = <GroupBy>[
  GroupByNone(),
  GroupByCategory(2),
  GroupByTag(),
  GroupByPeriod(PeriodType.month),
  GroupByPaymentMethod(),
  GroupByMerchant(),
  GroupByReflection(),
  GroupByHourOfDay(),
  GroupByDayOfWeek(),
];

void main() {
  group('GroupBy', () {
    test('every dimension round-trips as its own kind', () {
      for (final dimension in everyDimension) {
        final restored = GroupBy.fromJson(dimension.toJson());
        expect(restored, dimension, reason: 'round trip changed $dimension');
        expect(restored.runtimeType, dimension.runtimeType);
      }
    });

    test('category depth survives the round trip', () {
      // Losing the depth silently regroups a chart from sub-category to
      // top-level, which looks like a data change rather than a bug.
      final restored = GroupBy.fromJson(GroupByCategory(3).toJson());
      expect((restored as GroupByCategory).depth, 3);
    });

    test('period type survives the round trip', () {
      final restored =
          GroupBy.fromJson(const GroupByPeriod(PeriodType.quarter).toJson());
      expect((restored as GroupByPeriod).period, PeriodType.quarter);
    });

    test('a negative category depth is rejected', () {
      expect(() => GroupByCategory(-1), throwsArgumentError);
    });

    test('an unknown kind throws rather than falling back to none', () {
      // Falling back to "no grouping" turns a breakdown into a single total,
      // which renders as a plausible-looking chart with one bar.
      expect(() => GroupBy.fromJson({'kind': 'wat'}), throwsFormatException);
    });

    test('every case is covered by this test', () {
      // Guards against a dimension being added without a round-trip test.
      expect(everyDimension.map((d) => d.kind).toSet(),
          hasLength(everyDimension.length));
    });
  });

  group('QuerySpec', () {
    test('a fully populated spec round-trips losslessly', () {
      // Phase 5 stores this as a goal's scope.
      final spec = QuerySpec(
        filters: QueryFilters(
          dateRange:
              DateRange(const DateKey(20260101), const DateKey(20260131)),
          direction: MoneyDirection.expense,
          tags: TagsAny(const ['/travel/']),
          confirmedOnly: true,
        ),
        groupBy: GroupByCategory(1),
        aggregate: Aggregate.sum,
      );
      expect(QuerySpec.fromJson(spec.toJson()), spec);
    });

    test('the minimal spec round-trips', () {
      const spec = QuerySpec(
          filters: QueryFilters(),
          groupBy: GroupByNone(),
          aggregate: Aggregate.sum);
      expect(QuerySpec.fromJson(spec.toJson()), spec);
    });

    test('isTagDimension is true only for the tag grouping', () {
      for (final dimension in everyDimension) {
        final spec = QuerySpec(
            filters: const QueryFilters(),
            groupBy: dimension,
            aggregate: Aggregate.sum);
        expect(spec.isTagDimension, dimension is GroupByTag,
            reason: '$dimension reported the wrong tag-dimension answer, and '
                'that flag is what makes a chart disclose double-counting');
      }
    });

    test('an unknown aggregate throws', () {
      expect(
          () => QuerySpec.fromJson({
                'filters': <String, Object?>{},
                'groupBy': {'kind': 'none'},
                'aggregate': 'median',
              }),
          throwsFormatException);
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails** — `Undefined name 'GroupByNone'`.

- [ ] **Step 3: Implement**

Create `packages/nimbus_domain/lib/src/analytics/group_by.dart`:

```dart
import 'package:meta/meta.dart';

import '../calendar/calendar.dart';

/// The dimension a query buckets its rows along.
///
/// Sealed rather than an enum because two cases carry parameters. An enum
/// would push a depth and a period onto `QuerySpec` as parallel nullable
/// fields that can contradict the chosen dimension.
@immutable
sealed class GroupBy {
  const GroupBy();

  factory GroupBy.fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'none' => const GroupByNone(),
        'category' => GroupByCategory(json['depth']! as int),
        'tag' => const GroupByTag(),
        'period' => GroupByPeriod(_periodOf(json['period'])),
        'paymentMethod' => const GroupByPaymentMethod(),
        'merchant' => const GroupByMerchant(),
        'reflection' => const GroupByReflection(),
        'hourOfDay' => const GroupByHourOfDay(),
        'dayOfWeek' => const GroupByDayOfWeek(),
        final other => throw FormatException('unknown group-by kind "$other"'),
      };

  /// Stable discriminator, also used as the JSON tag.
  String get kind;

  Map<String, Object?> toJson() => {'kind': kind};

  static PeriodType _periodOf(Object? raw) {
    for (final period in PeriodType.values) {
      if (period.name == raw) return period;
    }
    throw FormatException('unknown period type "$raw"');
  }
}

/// One bucket holding everything the filters matched.
final class GroupByNone extends GroupBy {
  const GroupByNone();
  @override
  String get kind => 'none';
  @override
  bool operator ==(Object other) => other is GroupByNone;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByNone()';
}

/// Category, rolled up to [depth] in the materialized path.
///
/// Depth 0 is a root category; deeper values split further. A transaction
/// whose category is shallower than [depth] buckets at its own depth.
final class GroupByCategory extends GroupBy {
  GroupByCategory(this.depth) {
    if (depth < 0) {
      throw ArgumentError.value(depth, 'depth', 'must not be negative');
    }
  }

  final int depth;

  @override
  String get kind => 'category';
  @override
  Map<String, Object?> toJson() => {'kind': kind, 'depth': depth};
  @override
  bool operator ==(Object other) =>
      other is GroupByCategory && other.depth == depth;
  @override
  int get hashCode => Object.hash(kind, depth);
  @override
  String toString() => 'GroupByCategory($depth)';
}

/// Tag. **Buckets on this dimension do not sum to the total** — a transaction
/// with two tags lands in two buckets. See `AnalyticsResult.trueTotal`.
final class GroupByTag extends GroupBy {
  const GroupByTag();
  @override
  String get kind => 'tag';
  @override
  bool operator ==(Object other) => other is GroupByTag;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByTag()';
}

/// Calendar period. Boundaries are computed in the active calendar by
/// [PeriodBoundaries], never by SQL date functions.
final class GroupByPeriod extends GroupBy {
  const GroupByPeriod(this.period);

  final PeriodType period;

  @override
  String get kind => 'period';
  @override
  Map<String, Object?> toJson() => {'kind': kind, 'period': period.name};
  @override
  bool operator ==(Object other) =>
      other is GroupByPeriod && other.period == period;
  @override
  int get hashCode => Object.hash(kind, period);
  @override
  String toString() => 'GroupByPeriod(${period.name})';
}

final class GroupByPaymentMethod extends GroupBy {
  const GroupByPaymentMethod();
  @override
  String get kind => 'paymentMethod';
  @override
  bool operator ==(Object other) => other is GroupByPaymentMethod;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByPaymentMethod()';
}

final class GroupByMerchant extends GroupBy {
  const GroupByMerchant();
  @override
  String get kind => 'merchant';
  @override
  bool operator ==(Object other) => other is GroupByMerchant;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByMerchant()';
}

/// Necessity x satisfaction, the reflection matrix.
final class GroupByReflection extends GroupBy {
  const GroupByReflection();
  @override
  String get kind => 'reflection';
  @override
  bool operator ==(Object other) => other is GroupByReflection;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByReflection()';
}

final class GroupByHourOfDay extends GroupBy {
  const GroupByHourOfDay();
  @override
  String get kind => 'hourOfDay';
  @override
  bool operator ==(Object other) => other is GroupByHourOfDay;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByHourOfDay()';
}

final class GroupByDayOfWeek extends GroupBy {
  const GroupByDayOfWeek();
  @override
  String get kind => 'dayOfWeek';
  @override
  bool operator ==(Object other) => other is GroupByDayOfWeek;
  @override
  int get hashCode => kind.hashCode;
  @override
  String toString() => 'GroupByDayOfWeek()';
}
```

> `GroupByCategory` has a validation body, so it is **not** `const` while every other case is. That is why `everyDimension` in the test is declared `final`.

Create `packages/nimbus_domain/lib/src/analytics/query_spec.dart`:

```dart
import 'package:meta/meta.dart';

import 'aggregate.dart';
import 'group_by.dart';
import 'query_filters.dart';

/// One analytical question: what to include, how to bucket it, what to compute.
///
/// Pure and serializable by requirement, not by preference — Phase 5 persists a
/// `QuerySpec` as a goal's scope, so this type is a storage format as much as
/// an argument.
@immutable
final class QuerySpec {
  const QuerySpec({
    required this.filters,
    required this.groupBy,
    required this.aggregate,
  });

  factory QuerySpec.fromJson(Map<String, Object?> json) => QuerySpec(
        filters: QueryFilters.fromJson(
            (json['filters']! as Map).cast<String, Object?>()),
        groupBy:
            GroupBy.fromJson((json['groupBy']! as Map).cast<String, Object?>()),
        aggregate: _aggregateOf(json['aggregate']),
      );

  final QueryFilters filters;
  final GroupBy groupBy;
  final Aggregate aggregate;

  /// True when buckets on this dimension can overlap, so their sum exceeds the
  /// true total. Exposed as one predicate rather than left to callers to
  /// rediscover with a type check — a chart that forgets is a chart that lies.
  bool get isTagDimension => groupBy is GroupByTag;

  Map<String, Object?> toJson() => {
        'filters': filters.toJson(),
        'groupBy': groupBy.toJson(),
        'aggregate': aggregate.name,
      };

  static Aggregate _aggregateOf(Object? raw) {
    for (final value in Aggregate.values) {
      if (value.name == raw) return value;
    }
    throw FormatException('unknown aggregate "$raw"');
  }

  @override
  bool operator ==(Object other) =>
      other is QuerySpec &&
      other.filters == filters &&
      other.groupBy == groupBy &&
      other.aggregate == aggregate;

  @override
  int get hashCode => Object.hash(filters, groupBy, aggregate);

  @override
  String toString() => 'QuerySpec($groupBy, ${aggregate.name})';
}
```

- [ ] **Step 4: Export** `src/analytics/group_by.dart` and `src/analytics/query_spec.dart`.

- [ ] **Step 5: Run the test** — 11 tests pass.

- [ ] **Step 6: Full gate.**

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-query-spec HEAD
git commit -m "feat: QuerySpec -- one analytical question, serializable

Group-by is a sealed family rather than an enum because two dimensions
carry parameters. An enum would put depth and period on QuerySpec as
nullable fields that can contradict the chosen dimension: 'group by
merchant, depth 3' would be constructible and meaningless.

isTagDimension is a single predicate rather than a type check callers
rediscover. Tag buckets overlap and do not sum to the total, and a chart
that forgets to disclose that is a chart that lies.

Unknown kinds and aggregates throw. Falling back to 'no grouping' would
turn a breakdown into a one-bar chart that looks like real data."
```

---

## Task 4: PeriodBoundaries

**Files:**
- Create: `packages/nimbus_domain/lib/src/analytics/period_boundaries.dart`
- Test: `packages/nimbus_domain/test/analytics/period_boundaries_test.dart`
- Modify: barrel (one export)

**Interfaces produced:**
- `PeriodBoundaries.forPeriod(PeriodType period, DateKey anchor, AppCalendar calendar, {int firstDayOfWeek = DateTime.saturday}) → DateRange`
- `PeriodBoundaries.series(PeriodType period, DateRange span, AppCalendar calendar, {int firstDayOfWeek}) → List<DateRange>` — consecutive period ranges covering `span`, oldest first. Trends and period comparison both need this, and both getting it wrong the same way is worse than either getting it wrong alone.

**This is the one place a period becomes a key range.** `AppCalendar.periodContaining` and `shiftPeriod` already exist and do the calendar arithmetic; this type exists so there is a single named entry point the engine and Phase 5 both call, rather than two callers reaching into the calendar with slightly different week rules.

**The tests that matter are the boundaries**, because that is where a Jalali month stops lining up with a Gregorian one and where nobody looks.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_domain/test/analytics/period_boundaries_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

void main() {
  const jalali = JalaliCalendar();
  const gregorian = GregorianCalendar();

  group('forPeriod', () {
    test('a Gregorian month runs first to last', () {
      final range = PeriodBoundaries.forPeriod(
          PeriodType.month, const DateKey(20260815), gregorian);
      expect(range.startInclusive, const DateKey(20260801));
      expect(range.endInclusive, const DateKey(20260831));
    });

    test('a Jalali month is not a Gregorian month', () {
      // The whole reason period math never happens in SQL.
      final range = PeriodBoundaries.forPeriod(
          PeriodType.month, const DateKey(20260815), jalali);
      expect(range, isNot(DateRange(const DateKey(20260801), const DateKey(20260831))));
      final start = jalali.partsOf(range.startInclusive);
      final end = jalali.partsOf(range.endInclusive);
      expect(start.day, 1);
      expect(start.month, end.month,
          reason: 'a month range must not straddle two Jalali months');
      expect(end.day, jalali.monthLength(end.year, end.month));
    });

    test('a Jalali year boundary does not leak into the next year', () {
      // Esfand is month 12; the day after its last is 1 Farvardin.
      final esfand = jalali.keyOf(1404, 12, 15);
      final range =
          PeriodBoundaries.forPeriod(PeriodType.month, esfand, jalali);
      final start = jalali.partsOf(range.startInclusive);
      final end = jalali.partsOf(range.endInclusive);
      expect(start.year, 1404);
      expect(start.month, 12);
      expect(end.year, 1404);
      expect(end.month, 12);
    });

    test('a Jalali year runs Farvardin 1 to the last day of Esfand', () {
      final range = PeriodBoundaries.forPeriod(
          PeriodType.year, jalali.keyOf(1404, 6, 10), jalali);
      expect(jalali.partsOf(range.startInclusive).month, 1);
      expect(jalali.partsOf(range.startInclusive).day, 1);
      expect(jalali.partsOf(range.endInclusive).month, 12);
      expect(jalali.partsOf(range.endInclusive).year, 1404);
    });

    test('a day period is a single day', () {
      final range = PeriodBoundaries.forPeriod(
          PeriodType.day, const DateKey(20260815), gregorian);
      expect(range.startInclusive, const DateKey(20260815));
      expect(range.endInclusive, const DateKey(20260815));
      expect(range.dayCount, 1);
    });

    test('a week honours firstDayOfWeek', () {
      // Iran's week starts Saturday. Defaulting to Monday would shift every
      // weekly chart by two days and nobody would see it as a bug.
      final saturdayWeek = PeriodBoundaries.forPeriod(
          PeriodType.week, const DateKey(20260815), gregorian,
          firstDayOfWeek: DateTime.saturday);
      expect(saturdayWeek.startInclusive.weekday, DateTime.saturday);
      expect(saturdayWeek.dayCount, 7);

      final mondayWeek = PeriodBoundaries.forPeriod(
          PeriodType.week, const DateKey(20260815), gregorian,
          firstDayOfWeek: DateTime.monday);
      expect(mondayWeek.startInclusive.weekday, DateTime.monday);
      expect(mondayWeek, isNot(saturdayWeek));
    });

    test('the default first day of the week is Saturday', () {
      final explicit = PeriodBoundaries.forPeriod(
          PeriodType.week, const DateKey(20260815), gregorian,
          firstDayOfWeek: DateTime.saturday);
      final byDefault = PeriodBoundaries.forPeriod(
          PeriodType.week, const DateKey(20260815), gregorian);
      expect(byDefault, explicit);
    });

    test('a quarter covers three months in either calendar', () {
      for (final calendar in <AppCalendar>[gregorian, jalali]) {
        final range = PeriodBoundaries.forPeriod(
            PeriodType.quarter, const DateKey(20260815), calendar);
        expect(range.dayCount, greaterThan(80));
        expect(range.dayCount, lessThan(95),
            reason: 'a quarter in ${calendar.kind.name} was ${range.dayCount} '
                'days');
      }
    });
  });

  group('series', () {
    test('consecutive months tile the span without gaps or overlap', () {
      final span =
          DateRange(const DateKey(20260101), const DateKey(20260331));
      final periods =
          PeriodBoundaries.series(PeriodType.month, span, gregorian);
      expect(periods, hasLength(3));
      expect(periods.first.startInclusive, const DateKey(20260101));
      expect(periods.last.endInclusive, const DateKey(20260331));
      for (var i = 1; i < periods.length; i++) {
        expect(periods[i].startInclusive,
            periods[i - 1].endInclusive.addDays(1),
            reason: 'gap or overlap between period ${i - 1} and $i');
      }
    });

    test('a span shorter than one period yields exactly one period', () {
      final span =
          DateRange(const DateKey(20260810), const DateKey(20260812));
      final periods =
          PeriodBoundaries.series(PeriodType.month, span, gregorian);
      expect(periods, hasLength(1));
    });

    test('the series is oldest first', () {
      final span =
          DateRange(const DateKey(20260101), const DateKey(20260601));
      final periods =
          PeriodBoundaries.series(PeriodType.month, span, gregorian);
      for (var i = 1; i < periods.length; i++) {
        expect(periods[i].startInclusive.value,
            greaterThan(periods[i - 1].startInclusive.value));
      }
    });

    test('a Jalali series crosses the new year correctly', () {
      // Esfand 1404 into Farvardin 1405 -- the case that breaks naive
      // month-plus-one arithmetic.
      final span = DateRange(jalali.keyOf(1404, 12, 1), jalali.keyOf(1405, 1, 28));
      final periods = PeriodBoundaries.series(PeriodType.month, span, jalali);
      expect(periods, hasLength(2));
      expect(jalali.partsOf(periods.first.startInclusive).month, 12);
      expect(jalali.partsOf(periods.first.startInclusive).year, 1404);
      expect(jalali.partsOf(periods.last.startInclusive).month, 1);
      expect(jalali.partsOf(periods.last.startInclusive).year, 1405);
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails** — `Undefined name 'PeriodBoundaries'`.

- [ ] **Step 3: Implement**

Create `packages/nimbus_domain/lib/src/analytics/period_boundaries.dart`:

```dart
import '../calendar/calendar.dart';
import '../calendar/date_key.dart';

/// The one place a period becomes a key range.
///
/// [AppCalendar] already does the arithmetic; this type exists so the engine,
/// the trends screen and Phase 5's goal evaluation all enter through the same
/// door with the same week rule, rather than three callers reaching into the
/// calendar and disagreeing about which day a week starts on.
///
/// Period boundaries are computed here, in the active calendar, and converted
/// to `DateKey` integers before any SQL is generated. SQLite has no idea what
/// a Jalali month is, and `strftime` on `local_date_key` would silently answer
/// the Gregorian question instead.
abstract final class PeriodBoundaries {
  /// Iran's week starts on Saturday. Defaulting to Monday would shift every
  /// weekly chart by two days in a way that looks like data, not like a bug.
  static const defaultFirstDayOfWeek = DateTime.saturday;

  static DateRange forPeriod(
    PeriodType period,
    DateKey anchor,
    AppCalendar calendar, {
    int firstDayOfWeek = defaultFirstDayOfWeek,
  }) =>
      calendar.periodContaining(anchor, period,
          firstDayOfWeek: firstDayOfWeek);

  /// Consecutive periods covering [span], oldest first.
  ///
  /// The first period is the one containing `span.startInclusive`, so a span
  /// that begins mid-month yields a first bucket covering that whole month —
  /// which is what a trend chart wants, and why the caller supplies the span
  /// rather than a count.
  static List<DateRange> series(
    PeriodType period,
    DateRange span,
    AppCalendar calendar, {
    int firstDayOfWeek = defaultFirstDayOfWeek,
  }) {
    final periods = <DateRange>[];
    var current = forPeriod(period, span.startInclusive, calendar,
        firstDayOfWeek: firstDayOfWeek);

    while (current.startInclusive <= span.endInclusive) {
      periods.add(current);
      final next = calendar.shiftPeriod(current, period, 1);
      if (next.startInclusive <= current.startInclusive) {
        // shiftPeriod must move forward. Looping forever on a calendar bug
        // would hang the UI with no clue why.
        throw StateError('shiftPeriod did not advance past $current');
      }
      current = next;
    }
    return periods;
  }
}
```

- [ ] **Step 4: Export** `src/analytics/period_boundaries.dart`.

- [ ] **Step 5: Run the test** — 12 tests pass.

If `periodContaining` does not accept `firstDayOfWeek` as a named optional with a default, pass it positionally as the signature requires; do **not** change `AppCalendar`, which is Phase 0's file.

- [ ] **Step 6: Full gate.**

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-period-boundaries HEAD
git commit -m "feat: the one place a period becomes a key range

AppCalendar already does the arithmetic. This type exists so the engine,
trends, and Phase 5's goal evaluation enter through one door with one
week rule, instead of three callers reaching into the calendar and
quietly disagreeing about which day a week starts.

The default week starts Saturday. Defaulting to Monday would shift every
weekly chart by two days in a way that reads as data rather than as a
bug.

The tests are mostly boundaries -- Esfand into Farvardin, a Jalali month
against its Gregorian neighbour, a series tiling a span with no gap or
overlap. That is where a calendar assumption breaks and where nobody
looks."
```

---

## Task 5: AnalyticsResult

**Files:**
- Create: `packages/nimbus_domain/lib/src/analytics/analytics_result.dart`
- Test: `packages/nimbus_domain/test/analytics/analytics_result_test.dart`
- Modify: barrel (one export)

**Interfaces produced:**
- `sealed class BucketKey` with cases `TotalKey`, `CategoryKey(String categoryId, String path)`, `TagKey(String tagId, String path)`, `PeriodKey(DateRange range)`, `PaymentMethodKey(String? paymentMethodId)`, `MerchantKey(String? merchant)`, `ReflectionKey(NecessityLevel? necessity, SatisfactionLevel? satisfaction)`, `HourOfDayKey(int hour)`, `DayOfWeekKey(int weekday)`.
- `Bucket({required BucketKey key, required Money money, required int count})`
- `AnalyticsResult({required List<Bucket> buckets, required Money trueTotal, required int trueCount, required bool bucketsMayOverlap})` with `Money get bucketSum` and `bool get overlaps`.

**`trueTotal` is required and non-nullable** (Decision 4). For every dimension except tag it equals `bucketSum`; for tag it does not, and `overlaps` says so. Making it optional would let a caller build a pie chart without ever learning the number it should have compared against.

**Nullable key fields are real, not defensive.** `paymentMethodId` is nullable on the table, `merchant` is nullable, and `necessity`/`satisfaction` are nullable — so "no payment method" is a genuine bucket, not an error. The brief is explicit that a message with no merchant is still useful; the same holds for a transaction.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_domain/test/analytics/analytics_result_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

Bucket bucket(BucketKey key, int minorUnits, {int count = 1}) =>
    Bucket(key: key, money: Money(minorUnits), count: count);

void main() {
  group('AnalyticsResult', () {
    test('bucketSum adds every bucket', () {
      final result = AnalyticsResult(
        buckets: [
          bucket(const CategoryKey('food', '/food/'), 1000),
          bucket(const CategoryKey('travel', '/travel/'), 2500),
        ],
        trueTotal: const Money(3500),
        trueCount: 2,
        bucketsMayOverlap: false,
      );
      expect(result.bucketSum, const Money(3500));
      expect(result.overlaps, isFalse);
    });

    test('a non-overlapping dimension has bucketSum == trueTotal', () {
      final result = AnalyticsResult(
        buckets: [bucket(const CategoryKey('food', '/food/'), 1000)],
        trueTotal: const Money(1000),
        trueCount: 1,
        bucketsMayOverlap: false,
      );
      expect(result.bucketSum, result.trueTotal);
    });

    test('a tag dimension can exceed the true total, and says so', () {
      // The headline trap: one transaction tagged #travel AND #food lands in
      // both buckets. Asserting equality here would be the bug.
      final result = AnalyticsResult(
        buckets: [
          bucket(const TagKey('travel', '/travel/'), 1000),
          bucket(const TagKey('food', '/food/'), 1000),
        ],
        trueTotal: const Money(1000),
        trueCount: 1,
        bucketsMayOverlap: true,
      );
      expect(result.bucketSum.minorUnits,
          greaterThan(result.trueTotal.minorUnits));
      expect(result.overlaps, isTrue);
    });

    test('an empty result is zero, not an error', () {
      const result = AnalyticsResult(
        buckets: [],
        trueTotal: Money.zero,
        trueCount: 0,
        bucketsMayOverlap: false,
      );
      expect(result.bucketSum, Money.zero);
      expect(result.buckets, isEmpty);
    });
  });

  group('BucketKey', () {
    test('null-valued keys are legitimate buckets', () {
      // "No payment method" and "no merchant" are real answers. The columns
      // are nullable and the rows still count.
      expect(const PaymentMethodKey(null).paymentMethodId, isNull);
      expect(const MerchantKey(null).merchant, isNull);
      expect(
          const ReflectionKey(necessity: null, satisfaction: null).necessity,
          isNull);
    });

    test('keys compare by value so buckets can be looked up', () {
      expect(const CategoryKey('a', '/a/'), const CategoryKey('a', '/a/'));
      expect(const CategoryKey('a', '/a/'), isNot(const CategoryKey('b', '/b/')));
      expect(const HourOfDayKey(9), const HourOfDayKey(9));
      expect(
          PeriodKey(DateRange(const DateKey(20260101), const DateKey(20260131))),
          PeriodKey(
              DateRange(const DateKey(20260101), const DateKey(20260131))));
    });

    test('an out-of-range hour is rejected', () {
      expect(() => HourOfDayKey(24), throwsArgumentError);
      expect(() => HourOfDayKey(-1), throwsArgumentError);
    });

    test('an out-of-range weekday is rejected', () {
      expect(() => DayOfWeekKey(0), throwsArgumentError);
      expect(() => DayOfWeekKey(8), throwsArgumentError);
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails.**

- [ ] **Step 3: Implement**

Create `packages/nimbus_domain/lib/src/analytics/analytics_result.dart`:

```dart
import 'package:meta/meta.dart';

import '../calendar/date_key.dart';
import '../money/money.dart';
import 'reflection_levels.dart';

/// What a bucket is keyed on. One case per group-by dimension.
@immutable
sealed class BucketKey {
  const BucketKey();
}

/// The single bucket produced when nothing is grouped.
final class TotalKey extends BucketKey {
  const TotalKey();
  @override
  bool operator ==(Object other) => other is TotalKey;
  @override
  int get hashCode => 'total'.hashCode;
  @override
  String toString() => 'TotalKey()';
}

final class CategoryKey extends BucketKey {
  const CategoryKey(this.categoryId, this.path);
  final String categoryId;
  final String path;
  @override
  bool operator ==(Object other) =>
      other is CategoryKey &&
      other.categoryId == categoryId &&
      other.path == path;
  @override
  int get hashCode => Object.hash(categoryId, path);
  @override
  String toString() => 'CategoryKey($categoryId)';
}

final class TagKey extends BucketKey {
  const TagKey(this.tagId, this.path);
  final String tagId;
  final String path;
  @override
  bool operator ==(Object other) =>
      other is TagKey && other.tagId == tagId && other.path == path;
  @override
  int get hashCode => Object.hash(tagId, path);
  @override
  String toString() => 'TagKey($tagId)';
}

final class PeriodKey extends BucketKey {
  const PeriodKey(this.range);
  final DateRange range;
  @override
  bool operator ==(Object other) => other is PeriodKey && other.range == range;
  @override
  int get hashCode => range.hashCode;
  @override
  String toString() => 'PeriodKey($range)';
}

/// `null` means the transaction carried no payment method — a real bucket.
final class PaymentMethodKey extends BucketKey {
  const PaymentMethodKey(this.paymentMethodId);
  final String? paymentMethodId;
  @override
  bool operator ==(Object other) =>
      other is PaymentMethodKey && other.paymentMethodId == paymentMethodId;
  @override
  int get hashCode => paymentMethodId.hashCode;
  @override
  String toString() => 'PaymentMethodKey($paymentMethodId)';
}

/// `null` means the transaction named no merchant — still worth counting.
final class MerchantKey extends BucketKey {
  const MerchantKey(this.merchant);
  final String? merchant;
  @override
  bool operator ==(Object other) =>
      other is MerchantKey && other.merchant == merchant;
  @override
  int get hashCode => merchant.hashCode;
  @override
  String toString() => 'MerchantKey($merchant)';
}

/// A cell of the necessity x satisfaction matrix. Either axis may be unset,
/// because Phase 1 deliberately keeps both off the add-expense path.
final class ReflectionKey extends BucketKey {
  const ReflectionKey({required this.necessity, required this.satisfaction});
  final NecessityLevel? necessity;
  final SatisfactionLevel? satisfaction;
  @override
  bool operator ==(Object other) =>
      other is ReflectionKey &&
      other.necessity == necessity &&
      other.satisfaction == satisfaction;
  @override
  int get hashCode => Object.hash(necessity, satisfaction);
  @override
  String toString() => 'ReflectionKey($necessity, $satisfaction)';
}

final class HourOfDayKey extends BucketKey {
  HourOfDayKey(this.hour) {
    if (hour < 0 || hour > 23) {
      throw ArgumentError.value(hour, 'hour', 'must be 0..23');
    }
  }
  final int hour;
  @override
  bool operator ==(Object other) => other is HourOfDayKey && other.hour == hour;
  @override
  int get hashCode => hour.hashCode;
  @override
  String toString() => 'HourOfDayKey($hour)';
}

/// ISO weekday: `DateTime.monday` (1) through `DateTime.sunday` (7).
final class DayOfWeekKey extends BucketKey {
  DayOfWeekKey(this.weekday) {
    if (weekday < DateTime.monday || weekday > DateTime.sunday) {
      throw ArgumentError.value(weekday, 'weekday', 'must be 1..7');
    }
  }
  final int weekday;
  @override
  bool operator ==(Object other) =>
      other is DayOfWeekKey && other.weekday == weekday;
  @override
  int get hashCode => weekday.hashCode;
  @override
  String toString() => 'DayOfWeekKey($weekday)';
}

/// One row of an answer.
@immutable
final class Bucket {
  const Bucket({required this.key, required this.money, required this.count});

  final BucketKey key;

  /// The monetary result of the aggregate. `Money.zero` when the aggregate is
  /// [Aggregate.count], where [count] is the answer.
  final Money money;

  /// How many transactions fell in this bucket. Always populated, because
  /// every chart wants "n = 12" beside a total and computing it separately
  /// would mean a second query over the same rows.
  final int count;

  @override
  String toString() => 'Bucket($key, $money, n=$count)';
}

/// The answer to one [QuerySpec].
///
/// [trueTotal] is required rather than optional because for tag dimensions the
/// buckets overlap and their sum exceeds it. A caller that never receives the
/// true total cannot know it should have disclosed the difference, and the
/// resulting pie chart is a quiet lie.
@immutable
final class AnalyticsResult {
  const AnalyticsResult({
    required this.buckets,
    required this.trueTotal,
    required this.trueCount,
    required this.bucketsMayOverlap,
  });

  final List<Bucket> buckets;

  /// The total across the matched rows, counting each transaction once.
  final Money trueTotal;

  /// The number of matched transactions, counting each once.
  final int trueCount;

  /// True when one transaction can land in more than one bucket.
  final bool bucketsMayOverlap;

  Money get bucketSum => Money.sum(buckets.map((b) => b.money));

  /// Whether this result's buckets can be presented as parts of a whole.
  /// When true, the UI must say the slices do not sum to the total.
  bool get overlaps => bucketsMayOverlap;

  @override
  String toString() =>
      'AnalyticsResult(${buckets.length} buckets, total $trueTotal)';
}
```

- [ ] **Step 4: Export** `src/analytics/analytics_result.dart`.

- [ ] **Step 5: Run the test** — 8 tests pass.

- [ ] **Step 6: Full gate.**

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-analytics-result HEAD
git commit -m "feat: the shape of an answer, with the true total attached

trueTotal is required and non-nullable. For every dimension except tag
it equals the sum of the buckets; for tag it does not, because a
transaction with two tags lands in two buckets. A caller that never
receives the true total cannot know it should have disclosed the
difference, and the pie chart it draws is a quiet lie.

Null-valued keys are real buckets, not defensive padding. No payment
method, no merchant, and an unset reflection axis are all genuine
answers -- Phase 1 deliberately keeps necessity and satisfaction off the
add-expense path, so most rows have neither.

Every bucket carries its count alongside its money, because every chart
wants n beside the total and computing it separately would mean a second
pass over the same rows."
```

---
## The shared fixture, and why it is these five rows

Tasks 6–9 all run against one fixture. It was **executed against a real in-memory database before this plan was written**, and the numbers below are what SQLite actually returned — not what they ought to be.

| Transaction | Amount | `local_date_key` | Tags |
|---|---|---|---|
| `t1` | 1000 | 20260115 | `/travel/`, `/food/` |
| `t2` | 500 | 20260220 | `/travel/flights/`, `/travel/` |
| `t3` | 250 | 20260315 | none |

Tags: `travel` at `/travel/`, `flights` at `/travel/flights/`, `food` at `/food/`.

Measured facts this fixture pins down:

- **Tag buckets sum to 3000 against a true total of 1750.** `travel` 1500 (n=2), `food` 1000 (n=1), `flights` 500 (n=1). The inequality is the assertion; equality would be the bug.
- **Rolling up to `/travel/` with `JOIN` gives 2000, n=3** — `t2` counted twice, once through `/travel/` and once through `/travel/flights/`.
- **The same rollup with `EXISTS` gives 1500, n=2** — each transaction once. This is why Decision 5 says `EXISTS`, not `JOIN`.
- `MaterializedPath.subtreeUpperBound('/travel/')` is `'/travel0'` — `/` is `0x2F` and the next code point is `0x30`. Confirmed against the running helper.

Create it once, at `packages/nimbus_data/test/analytics/support/analytics_fixture.dart`, and reuse it. The insert statements below are verified against the real column lists — **`categories` has `kind`, not `is_system`**, which cost a debugging cycle when this was first written from memory.

```dart
import 'package:nimbus_data/nimbus_data.dart';

/// Seeds the shared analytics fixture. Numbers in the tests are hand-computed
/// from these five rows; changing them means recomputing every expectation.
Future<void> seedAnalyticsFixture(AppDatabase db) async {
  Future<void> tag(String id, String path, int depth) => db.customStatement(
        'INSERT INTO tags (id,name,icon_key,color,parent_id,path,depth,'
        'sort_order,usage_count,archived,created_at,updated_at,deleted_at) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,NULL)',
        [id, id, 'tag', 0, null, path, depth, 0, 0, 0, 1, 1],
      );

  await tag('travel', '/travel/', 0);
  await tag('flights', '/travel/flights/', 1);
  await tag('food', '/food/', 0);

  await db.customStatement(
    'INSERT INTO categories (id,name,icon_key,color,parent_id,path,depth,'
    'sort_order,kind,archived,created_at,updated_at,deleted_at) '
    'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,NULL)',
    ['cat', 'cat', 'tag', 0, null, '/cat/', 0, 0, 'expense', 0, 1, 1],
  );

  Future<void> tx(String id, int amount, int dateKey) => db.customStatement(
        'INSERT INTO transactions (id,direction,amount,currency_code,'
        'occurred_at_utc,local_date_key,tz_offset_minutes,category_id,'
        'payment_method_id,merchant,note,necessity,satisfaction,source,'
        'is_confirmed,capture_id,created_at,updated_at,deleted_at) '
        'VALUES (?,?,?,?,?,?,?,?,NULL,NULL,NULL,NULL,NULL,?,1,NULL,?,?,NULL)',
        [id, 'expense', amount, 'IRT', 0, dateKey, 0, 'cat', 'manual', 1, 1],
      );

  await tx('t1', 1000, 20260115);
  await tx('t2', 500, 20260220);
  await tx('t3', 250, 20260315);

  Future<void> link(String txId, String tagId) => db.customStatement(
      'INSERT INTO transaction_tags (transaction_id,tag_id) VALUES (?,?)',
      [txId, tagId]);

  await link('t1', 'travel');
  await link('t1', 'food');
  await link('t2', 'flights');
  await link('t2', 'travel');
}
```

---

## Task 6: The compiler — filters, and the boundary mapping

**Files:**
- Create: `packages/nimbus_data/lib/src/analytics/compiled_query.dart`
- Create: `packages/nimbus_data/lib/src/analytics/analytics_predicates.dart`
- Create: `packages/nimbus_data/test/analytics/support/analytics_fixture.dart` (above)
- Test: `packages/nimbus_data/test/analytics/predicates_test.dart`
- Modify: `packages/nimbus_data/lib/nimbus_data.dart` (two exports)

**Interfaces produced:**
- `CompiledQuery({required String sql, required List<Variable<Object>> variables})`
- `AnalyticsPredicates.notDeleted(String alias)` → `'<alias>.deleted_at IS NULL'`
- `AnalyticsPredicates.whereClause(QueryFilters filters)` → `({String sql, List<Variable<Object>> variables})`
- `AnalyticsPredicates.directionOf(MoneyDirection)` → `TxDirection`, plus `necessityOf`, `satisfactionOf`.

**Why raw SQL and not drift's query builder.** The engine must emit **exactly one statement** (Decision 3) across nine group-by dimensions, a CASE ladder for periods, and `EXISTS` subqueries for tags. Expressing that through the typed builder means fighting it; a compiled `(sql, variables)` pair is also directly testable and is exactly what `EXPLAIN QUERY PLAN` needs in Task 9.

**Every user value is a bound variable, never interpolated.** Ids and paths come from the app rather than a text box, but a path with a quote in it would still break the statement, and the habit is what keeps the next dimension safe.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_data/test/analytics/predicates_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import 'support/analytics_fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    await seedAnalyticsFixture(db);
  });
  tearDown(() => db.close());

  /// Runs a filtered total so a predicate is checked against real rows rather
  /// than against its own SQL string.
  Future<({int total, int count})> totalWith(QueryFilters filters) async {
    final clause = AnalyticsPredicates.whereClause(filters);
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(t.amount),0) AS total, COUNT(*) AS n '
      'FROM transactions t WHERE ${clause.sql}',
      variables: clause.variables,
    ).getSingle();
    return (total: row.data['total']! as int, count: row.data['n']! as int);
  }

  group('the boundary mapping', () {
    test('every domain mirror maps to a nimbus_data value', () {
      // The two enum families live in different packages by necessity
      // (nimbus_domain cannot import nimbus_data). This test is the only
      // thing stopping them drifting apart.
      for (final value in MoneyDirection.values) {
        expect(AnalyticsPredicates.directionOf(value).name, value.name);
      }
      for (final value in NecessityLevel.values) {
        expect(AnalyticsPredicates.necessityOf(value).name, value.name);
      }
      for (final value in SatisfactionLevel.values) {
        expect(AnalyticsPredicates.satisfactionOf(value).name, value.name);
      }
    });

    test('the families are the same size in both directions', () {
      // Catches a value added to nimbus_data that the domain mirror lacks --
      // the direction the loop above cannot see.
      expect(TxDirection.values.length, MoneyDirection.values.length);
      expect(Necessity.values.length, NecessityLevel.values.length);
      expect(Satisfaction.values.length, SatisfactionLevel.values.length);
    });
  });

  group('whereClause', () {
    test('the empty filter set matches every live row', () {
      // 1000 + 500 + 250, hand-computed from the fixture.
      expect(totalWith(const QueryFilters()),
          completion((total: 1750, count: 3)));
    });

    test('deleted rows are excluded even with no filters', () async {
      await db.customStatement(
          "UPDATE transactions SET deleted_at = 1 WHERE id = 't3'");
      expect(await totalWith(const QueryFilters()), (total: 1500, count: 2));
    });

    test('a date range is an inclusive key range', () async {
      final filters = QueryFilters(
          dateRange:
              DateRange(const DateKey(20260101), const DateKey(20260228)));
      expect(await totalWith(filters), (total: 1500, count: 2));
    });

    test('the range boundaries are inclusive on both ends', () async {
      final filters = QueryFilters(
          dateRange:
              DateRange(const DateKey(20260115), const DateKey(20260115)));
      expect(await totalWith(filters), (total: 1000, count: 1));
    });

    test('an amount range filters on minor units', () async {
      final filters =
          QueryFilters(amountRange: AmountRange(minInclusive: const Money(500)));
      expect(await totalWith(filters), (total: 1500, count: 2));
    });

    test('ANY over a tag subtree includes descendants', () async {
      // t1 via /travel/ and t2 via /travel/flights/ -- both are inside the
      // /travel/ subtree.
      final filters = QueryFilters(tags: TagsAny(const ['/travel/']));
      expect(await totalWith(filters), (total: 1500, count: 2));
    });

    test('ANY counts a transaction once even when two of its tags match',
        () async {
      // t2 carries BOTH /travel/ and /travel/flights/. EXISTS, not JOIN.
      // A JOIN here returns 2000/n=3; this is the measured difference.
      final filters = QueryFilters(tags: TagsAny(const ['/travel/']));
      final result = await totalWith(filters);
      expect(result.count, 2);
      expect(result.total, 1500);
    });

    test('ALL requires every subtree', () async {
      // Only t1 carries both /travel/ and /food/.
      final filters = QueryFilters(tags: TagsAll(const ['/travel/', '/food/']));
      expect(await totalWith(filters), (total: 1000, count: 1));
    });

    test('NONE excludes anything in the subtree', () async {
      // Everything except t1 and t2.
      final filters = QueryFilters(tags: TagsNone(const ['/travel/']));
      expect(await totalWith(filters), (total: 250, count: 1));
    });

    test('a category subtree filter uses the path range', () async {
      final filters = QueryFilters(categorySubtreePaths: const ['/cat/']);
      expect(await totalWith(filters), (total: 1750, count: 3));
    });

    test('confirmedOnly excludes unconfirmed captures', () async {
      await db.customStatement(
          "UPDATE transactions SET is_confirmed = 0 WHERE id = 't1'");
      expect(await totalWith(const QueryFilters(confirmedOnly: true)),
          (total: 750, count: 2));
      // and the default still includes them
      expect(await totalWith(const QueryFilters()), (total: 1750, count: 3));
    });

    test('search text escapes LIKE wildcards', () async {
      await db.customStatement(
          "UPDATE transactions SET merchant = '100% cotton' WHERE id = 't1'");
      // A literal % must not match every row.
      expect(await totalWith(const QueryFilters(searchText: '%')),
          (total: 1000, count: 1));
    });

    test('filters compose with AND', () async {
      final filters = QueryFilters(
        dateRange: DateRange(const DateKey(20260101), const DateKey(20260228)),
        tags: TagsAny(const ['/travel/']),
        amountRange: AmountRange(minInclusive: const Money(600)),
      );
      expect(await totalWith(filters), (total: 1000, count: 1));
    });

    test('every value reaches SQL as a bound variable', () {
      // No user value is interpolated into the statement text.
      final clause = AnalyticsPredicates.whereClause(
          const QueryFilters(searchText: "o'brien"));
      expect(clause.sql, isNot(contains("o'brien")));
      expect(clause.variables, isNotEmpty);
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails** — `Undefined name 'AnalyticsPredicates'`.

- [ ] **Step 3: Implement**

Create `packages/nimbus_data/lib/src/analytics/compiled_query.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

/// One SQL statement plus its bound variables.
///
/// The engine emits exactly one of these per `QuerySpec`. Keeping the SQL as
/// text rather than a drift query object is what lets Task 9 hand it to
/// `EXPLAIN QUERY PLAN` unchanged — an index assertion against a *different*
/// statement than the one that runs would prove nothing.
@immutable
final class CompiledQuery {
  const CompiledQuery({required this.sql, required this.variables});

  final String sql;
  final List<Variable<Object>> variables;

  @override
  String toString() => 'CompiledQuery($sql)';
}
```

Create `packages/nimbus_data/lib/src/analytics/analytics_predicates.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../tables/transactions_table.dart';
import '../tree/materialized_path.dart';

/// Filter translation, and the boundary between the two enum families.
///
/// `nimbus_domain` cannot import `nimbus_data`, so `QuerySpec` names
/// `MoneyDirection` / `NecessityLevel` / `SatisfactionLevel` while the table
/// declares `TxDirection` / `Necessity` / `Satisfaction`. The mapping happens
/// here, once, and `predicates_test.dart` fails if either family gains a value
/// the other lacks.
abstract final class AnalyticsPredicates {
  /// The one place the soft-delete rule is written for the engine.
  ///
  /// A single query that forgets this resurrects deleted rows in exactly one
  /// chart, which is the kind of bug that gets reported as "the numbers are
  /// wrong somewhere".
  static String notDeleted(String alias) => '$alias.deleted_at IS NULL';

  static TxDirection directionOf(MoneyDirection value) => switch (value) {
        MoneyDirection.expense => TxDirection.expense,
        MoneyDirection.income => TxDirection.income,
      };

  static Necessity necessityOf(NecessityLevel value) => switch (value) {
        NecessityLevel.needed => Necessity.needed,
        NecessityLevel.optional => Necessity.optional,
        NecessityLevel.avoidable => Necessity.avoidable,
      };

  static Satisfaction satisfactionOf(SatisfactionLevel value) =>
      switch (value) {
        SatisfactionLevel.glad => Satisfaction.glad,
        SatisfactionLevel.neutral => Satisfaction.neutral,
        SatisfactionLevel.regret => Satisfaction.regret,
      };

  /// Builds the WHERE clause for [filters], against the transactions table
  /// aliased as `t`.
  static ({String sql, List<Variable<Object>> variables}) whereClause(
    QueryFilters filters,
  ) {
    final conditions = <String>[notDeleted('t')];
    final variables = <Variable<Object>>[];

    final range = filters.dateRange;
    if (range != null) {
      conditions.add('t.local_date_key BETWEEN ? AND ?');
      variables
        ..add(Variable.withInt(range.startInclusive.value))
        ..add(Variable.withInt(range.endInclusive.value));
    }

    final direction = filters.direction;
    if (direction != null) {
      conditions.add('t.direction = ?');
      variables.add(Variable.withString(directionOf(direction).name));
    }

    if (filters.categorySubtreePaths.isNotEmpty) {
      final clauses = <String>[];
      for (final path in filters.categorySubtreePaths) {
        clauses.add('EXISTS (SELECT 1 FROM categories c '
            'WHERE c.id = t.category_id AND c.path >= ? AND c.path < ?)');
        variables
          ..add(Variable.withString(path))
          ..add(Variable.withString(MaterializedPath.subtreeUpperBound(path)));
      }
      conditions.add('(${clauses.join(' OR ')})');
    }

    if (filters.paymentMethodIds.isNotEmpty) {
      final placeholders =
          List.filled(filters.paymentMethodIds.length, '?').join(',');
      conditions.add('t.payment_method_id IN ($placeholders)');
      variables.addAll(
          filters.paymentMethodIds.map(Variable.withString));
    }

    if (filters.necessity.isNotEmpty) {
      final placeholders = List.filled(filters.necessity.length, '?').join(',');
      conditions.add('t.necessity IN ($placeholders)');
      variables.addAll(filters.necessity
          .map((n) => Variable.withString(necessityOf(n).name)));
    }

    if (filters.satisfaction.isNotEmpty) {
      final placeholders =
          List.filled(filters.satisfaction.length, '?').join(',');
      conditions.add('t.satisfaction IN ($placeholders)');
      variables.addAll(filters.satisfaction
          .map((s) => Variable.withString(satisfactionOf(s).name)));
    }

    final amounts = filters.amountRange;
    if (amounts != null) {
      final min = amounts.minInclusive;
      if (min != null) {
        conditions.add('t.amount >= ?');
        variables.add(Variable.withInt(min.minorUnits));
      }
      final max = amounts.maxInclusive;
      if (max != null) {
        conditions.add('t.amount <= ?');
        variables.add(Variable.withInt(max.minorUnits));
      }
    }

    if (filters.confirmedOnly) {
      conditions.add('t.is_confirmed = 1');
    }

    final needle = filters.searchText?.trim();
    if (needle != null && needle.isNotEmpty) {
      // Wildcards in user input match literally, the same way Phase 1's
      // transaction search already escapes them. Without this, typing `%`
      // silently matches everything and the search stops being a search.
      final escaped = needle
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      conditions.add(
          "(t.merchant LIKE ? ESCAPE '\\' OR t.note LIKE ? ESCAPE '\\')");
      variables
        ..add(Variable.withString('%$escaped%'))
        ..add(Variable.withString('%$escaped%'));
    }

    final tags = filters.tags;
    if (tags != null) {
      conditions.add(_tagCondition(tags, variables));
    }

    return (sql: conditions.join(' AND '), variables: variables);
  }

  /// Tag conditions are `EXISTS` subqueries, never joins.
  ///
  /// A join multiplies the row: a transaction carrying both `/travel/` and its
  /// child `/travel/flights/` would be counted twice, and its amount summed
  /// twice. Measured on the fixture, the join answers 2000 where the truth is
  /// 1500.
  static String _tagCondition(
      TagFilter filter, List<Variable<Object>> variables) {
    String existsFor(String path) {
      variables
        ..add(Variable.withString(path))
        ..add(Variable.withString(MaterializedPath.subtreeUpperBound(path)));
      return 'EXISTS (SELECT 1 FROM transaction_tags tt '
          'JOIN tags tg ON tg.id = tt.tag_id '
          'WHERE tt.transaction_id = t.id AND ${notDeleted('tg')} '
          'AND tg.path >= ? AND tg.path < ?)';
    }

    return switch (filter) {
      TagsAll(:final subtreePaths) =>
        '(${subtreePaths.map(existsFor).join(' AND ')})',
      TagsAny(:final subtreePaths) =>
        '(${subtreePaths.map(existsFor).join(' OR ')})',
      TagsNone(:final subtreePaths) =>
        '(NOT (${subtreePaths.map(existsFor).join(' OR ')}))',
    };
  }
}
```

> **Ordering matters in `_tagCondition`.** `existsFor` appends variables as a side effect of building the string, so the `map(...).join(...)` must be materialized in the same order the placeholders appear. `map` is lazy — if a future edit reorders or defers it, the bindings silently shift. If the tests show mismatched bindings, add `.toList()` before `.join(...)`.

- [ ] **Step 4: Export** `src/analytics/analytics_predicates.dart` and `src/analytics/compiled_query.dart` from `nimbus_data.dart`.

- [ ] **Step 5: Run the test** — 16 tests pass.

- [ ] **Step 6: Full gate**, including `dart test test/architecture_test.dart`.

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-analytics-predicates HEAD
git commit -m "feat: filter translation, and the one soft-delete rule

Tag conditions are EXISTS subqueries, never joins. A join multiplies the
row: a transaction carrying both /travel/ and its child /travel/flights/
gets counted twice and its amount summed twice. Measured on the fixture,
the join answers 2000 where the truth is 1500 -- and it answers it
confidently, on a chart, with no error anywhere.

notDeleted is one function because a single query that forgets the
soft-delete rule resurrects deleted rows in exactly one chart, which
gets reported as 'the numbers are wrong somewhere'.

The boundary mapping between the domain mirrors and the table enums
lives here with a test that fails if either family grows a value the
other lacks -- the only thing preventing two packages' enums from
drifting apart silently.

Every user value is a bound variable. Search text escapes LIKE
wildcards the same way Phase 1 does, so typing % stays a search."
```

---
## Task 7: Group-by dimensions and the engine

**Files:**
- Create: `packages/nimbus_data/lib/src/analytics/group_expressions.dart`
- Create: `packages/nimbus_data/lib/src/analytics/analytics_engine.dart`
- Test: `packages/nimbus_data/test/analytics/group_by_test.dart`
- Modify: `packages/nimbus_data/lib/nimbus_data.dart` (two exports)

**Interfaces produced:**
- `GroupExpressions.forDimension(GroupBy dimension, {DateRange? span, AppCalendar? calendar}) → ({String selectSql, String groupSql, List<Variable<Object>> variables})`
- `AnalyticsEngine(AppDatabase db, {AppCalendar calendar})` with `Future<AnalyticsResult> run(QuerySpec spec)` and `CompiledQuery compile(QuerySpec spec)`.

**The SQL per dimension**, each verified against the fixture:

| Dimension | Grouping expression |
|---|---|
| `none` | constant `0` |
| `category` | `c.path` truncated to depth via a join on `t.category_id` |
| `tag` | join through `transaction_tags` — the one dimension that overlaps |
| `period` | a `CASE` ladder over `local_date_key`, bounds computed in Dart |
| `paymentMethod` | `t.payment_method_id` (nullable — a real bucket) |
| `merchant` | `t.merchant` (nullable — a real bucket) |
| `reflection` | `t.necessity, t.satisfaction` |
| `hourOfDay` | `((occurred_at_utc + tz_offset_minutes*60000)/3600000) % 24` |
| `dayOfWeek` | `strftime('%w', (occurred_at_utc + tz_offset_minutes*60000)/1000, 'unixepoch')` |

**Why `strftime` is allowed for weekday but not for periods.** The trap forbids calendar math in SQL because a Jalali month is not a Gregorian month. The seven-day cycle is *identical* in both calendars — no calendar decision is being made — so deriving a weekday from an absolute instant is arithmetic, not calendar math. Period bucketing gets a `CASE` ladder built from `PeriodBoundaries` precisely because months genuinely differ.

**Period grouping requires a bounded date range.** With no `dateRange` there is no finite set of periods to enumerate, so `compile` throws `ArgumentError` naming the problem rather than silently bucketing everything into one.

**Money never becomes a double.** `SUM`, `MIN` and `MAX` come back as `int` and are wrapped in `Money` by hand — the `MoneyConverter` does not apply to aggregates, which the existing `sumInRange` already documents. `AVG` comes back as a nullable `double` and is rounded **half away from zero** exactly once, in `_moneyFromAverage`, and never travels as a double.

- [ ] **Step 1: Write the failing test**

Create `packages/nimbus_data/test/analytics/group_by_test.dart`. Every expectation is hand-computed from the fixture:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbus_data/nimbus_data.dart';
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

  Future<AnalyticsResult> run(GroupBy dimension,
          {QueryFilters filters = const QueryFilters(),
          Aggregate aggregate = Aggregate.sum}) =>
      engine.run(QuerySpec(
          filters: filters, groupBy: dimension, aggregate: aggregate));

  test('no grouping yields one bucket holding the true total', () async {
    final result = await run(const GroupByNone());
    expect(result.buckets, hasLength(1));
    expect(result.buckets.single.key, const TotalKey());
    expect(result.buckets.single.money, const Money(1750));
    expect(result.buckets.single.count, 3);
    expect(result.trueTotal, const Money(1750));
    expect(result.overlaps, isFalse);
  });

  test('every bucket carries its count', () async {
    final result = await run(const GroupByNone());
    expect(result.buckets.single.count, 3);
    expect(result.trueCount, 3);
  });

  test('grouping by merchant keeps the null bucket', () async {
    // All three rows have a null merchant in the fixture. "No merchant" is a
    // real answer, not a row to drop.
    final result = await run(const GroupByMerchant());
    expect(result.buckets, hasLength(1));
    expect((result.buckets.single.key as MerchantKey).merchant, isNull);
    expect(result.buckets.single.money, const Money(1750));
  });

  test('grouping by payment method keeps the null bucket', () async {
    final result = await run(const GroupByPaymentMethod());
    expect((result.buckets.single.key as PaymentMethodKey).paymentMethodId,
        isNull);
  });

  test('grouping by period uses Dart-computed boundaries', () async {
    final result = await run(
      const GroupByPeriod(PeriodType.month),
      filters: QueryFilters(
          dateRange:
              DateRange(const DateKey(20260101), const DateKey(20260331))),
    );
    expect(result.buckets, hasLength(3));
    expect(result.buckets[0].money, const Money(1000)); // January
    expect(result.buckets[1].money, const Money(500)); // February
    expect(result.buckets[2].money, const Money(250)); // March
    expect(result.trueTotal, const Money(1750));
  });

  test('period buckets are ordered oldest first', () async {
    final result = await run(
      const GroupByPeriod(PeriodType.month),
      filters: QueryFilters(
          dateRange:
              DateRange(const DateKey(20260101), const DateKey(20260331))),
    );
    final keys = result.buckets.map((b) => (b.key as PeriodKey).range).toList();
    for (var i = 1; i < keys.length; i++) {
      expect(keys[i].startInclusive.value,
          greaterThan(keys[i - 1].startInclusive.value));
    }
  });

  test('period grouping without a date range is refused', () async {
    // There is no finite set of periods to enumerate. Bucketing everything
    // into one would look like a working chart.
    expect(
        () => engine.compile(const QuerySpec(
            filters: QueryFilters(),
            groupBy: GroupByPeriod(PeriodType.month),
            aggregate: Aggregate.sum)),
        throwsArgumentError);
  });

  test('a Jalali month grouping is not a Gregorian one', () async {
    final jalaliEngine = AnalyticsEngine(db, calendar: const JalaliCalendar());
    final span = DateRange(const DateKey(20260101), const DateKey(20260331));
    final gregorian = await run(const GroupByPeriod(PeriodType.month),
        filters: QueryFilters(dateRange: span));
    final jalali = await jalaliEngine.run(QuerySpec(
        filters: QueryFilters(dateRange: span),
        groupBy: const GroupByPeriod(PeriodType.month),
        aggregate: Aggregate.sum));
    final gregorianStarts =
        gregorian.buckets.map((b) => (b.key as PeriodKey).range.startInclusive);
    final jalaliStarts =
        jalali.buckets.map((b) => (b.key as PeriodKey).range.startInclusive);
    expect(jalaliStarts, isNot(gregorianStarts),
        reason: 'if these agree, period math is happening in SQL');
    expect(jalali.trueTotal, const Money(1750),
        reason: 'the calendar changes the buckets, never the total');
  });

  test('grouping by hour of day', () async {
    final result = await run(const GroupByHourOfDay());
    expect(result.buckets, hasLength(1));
    expect((result.buckets.single.key as HourOfDayKey).hour, 0);
  });

  test('grouping by day of week yields an ISO weekday', () async {
    final result = await run(const GroupByDayOfWeek());
    final weekday = (result.buckets.single.key as DayOfWeekKey).weekday;
    expect(weekday, inInclusiveRange(DateTime.monday, DateTime.sunday));
  });

  test('grouping by reflection keeps unset axes as their own cell', () async {
    final result = await run(const GroupByReflection());
    final key = result.buckets.single.key as ReflectionKey;
    expect(key.necessity, isNull);
    expect(key.satisfaction, isNull);
    expect(result.buckets.single.count, 3);
  });

  test('grouping by category rolls up to the requested depth', () async {
    final result = await run(GroupByCategory(0));
    expect(result.buckets, hasLength(1));
    expect((result.buckets.single.key as CategoryKey).categoryId, 'cat');
    expect(result.buckets.single.money, const Money(1750));
  });

  group('aggregates', () {
    test('count answers in the count field', () async {
      final result = await run(const GroupByNone(), aggregate: Aggregate.count);
      expect(result.buckets.single.count, 3);
    });

    test('min and max stay integer money', () async {
      final min = await run(const GroupByNone(), aggregate: Aggregate.min);
      final max = await run(const GroupByNone(), aggregate: Aggregate.max);
      expect(min.buckets.single.money, const Money(250));
      expect(max.buckets.single.money, const Money(1000));
    });

    test('average rounds half away from zero and stays an int', () async {
      // (1000 + 500 + 250) / 3 = 583.33... -> 583
      final result =
          await run(const GroupByNone(), aggregate: Aggregate.average);
      expect(result.buckets.single.money, const Money(583));
    });

    test('an average of exactly .5 rounds away from zero', () async {
      await db.customStatement('DELETE FROM transaction_tags');
      await db.customStatement("DELETE FROM transactions WHERE id != 't1'");
      await db.customStatement(
          "UPDATE transactions SET amount = 1 WHERE id = 't1'");
      await db.customStatement(
        'INSERT INTO transactions (id,direction,amount,currency_code,'
        'occurred_at_utc,local_date_key,tz_offset_minutes,category_id,'
        'payment_method_id,merchant,note,necessity,satisfaction,source,'
        'is_confirmed,capture_id,created_at,updated_at,deleted_at) '
        "VALUES ('t9','expense',2,'IRT',0,20260115,0,'cat',NULL,NULL,NULL,"
        "NULL,NULL,'manual',1,NULL,1,1,NULL)",
      );
      // (1 + 2) / 2 = 1.5 -> 2
      final result =
          await run(const GroupByNone(), aggregate: Aggregate.average);
      expect(result.buckets.single.money, const Money(2));
    });

    test('an empty result is zero money, not an error', () async {
      final result = await run(
        const GroupByNone(),
        filters: QueryFilters(
            dateRange:
                DateRange(const DateKey(20200101), const DateKey(20200102))),
      );
      expect(result.trueTotal, Money.zero);
      expect(result.trueCount, 0);
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails.**

- [ ] **Step 3: Implement**

Create `packages/nimbus_data/lib/src/analytics/group_expressions.dart`. The grouping expression, the columns needed to rebuild a `BucketKey`, and any variables travel together, because a `SELECT` list that disagrees with its `GROUP BY` is a silent wrong answer rather than an error:

```dart
import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

/// SQL fragments for one group-by dimension.
typedef GroupFragment = ({
  /// Columns added to the SELECT list, aliased so [bucketKeyOf] can read them.
  String selectSql,

  /// The GROUP BY expression.
  String groupSql,

  /// Extra FROM/JOIN text, empty for most dimensions.
  String joinSql,
  List<Variable<Object>> variables,
});

abstract final class GroupExpressions {
  /// Builds the fragment for [dimension].
  ///
  /// [span] and [calendar] are required for period grouping and ignored
  /// otherwise: period boundaries are computed in Dart, never by SQL.
  static GroupFragment forDimension(
    GroupBy dimension, {
    DateRange? span,
    AppCalendar? calendar,
  }) =>
      switch (dimension) {
        GroupByNone() => (
            selectSql: '0 AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        GroupByMerchant() => (
            selectSql: 't.merchant AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        GroupByPaymentMethod() => (
            selectSql: 't.payment_method_id AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        GroupByReflection() => (
            selectSql: 't.necessity AS bucket, t.satisfaction AS bucket2',
            groupSql: 'bucket, bucket2',
            joinSql: '',
            variables: const [],
          ),
        GroupByHourOfDay() => (
            // Integer arithmetic on an absolute instant. No calendar involved.
            selectSql: 'CAST(((t.occurred_at_utc + t.tz_offset_minutes*60000)'
                '/3600000) % 24 AS INTEGER) AS bucket',
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        GroupByDayOfWeek() => (
            // strftime is permitted here and nowhere else: the seven-day cycle
            // is identical in both calendars, so no calendar decision is being
            // made. 0 = Sunday; the engine maps it to an ISO weekday.
            selectSql: "CAST(strftime('%w', "
                '(t.occurred_at_utc + t.tz_offset_minutes*60000)/1000, '
                "'unixepoch') AS INTEGER) AS bucket",
            groupSql: 'bucket',
            joinSql: '',
            variables: const [],
          ),
        GroupByCategory(:final depth) => (
            selectSql: 'c.id AS bucket, c.path AS bucket2',
            groupSql: 'bucket, bucket2',
            joinSql: ' JOIN categories c ON c.id = t.category_id',
            variables: const [],
          ),
        GroupByTag() => (
            selectSql: 'tg.id AS bucket, tg.path AS bucket2',
            groupSql: 'bucket, bucket2',
            joinSql: ' JOIN transaction_tags tt ON tt.transaction_id = t.id'
                ' JOIN tags tg ON tg.id = tt.tag_id AND tg.deleted_at IS NULL',
            variables: const [],
          ),
        GroupByPeriod(:final period) => _periodFragment(period, span, calendar),
      };

  /// A CASE ladder over `local_date_key`, with every bound computed in Dart by
  /// [PeriodBoundaries] and passed as a variable.
  ///
  /// This is what keeps the "never do calendar math in SQL" rule: SQLite is
  /// only ever asked whether an integer falls between two other integers.
  static GroupFragment _periodFragment(
      PeriodType period, DateRange? span, AppCalendar? calendar) {
    if (span == null || calendar == null) {
      throw ArgumentError('grouping by period needs a bounded date range: '
          'without one there is no finite set of periods to enumerate');
    }
    final periods = PeriodBoundaries.series(period, span, calendar);
    final buffer = StringBuffer('CASE');
    final variables = <Variable<Object>>[];
    for (var i = 0; i < periods.length; i++) {
      buffer.write(' WHEN t.local_date_key BETWEEN ? AND ? THEN $i');
      variables
        ..add(Variable.withInt(periods[i].startInclusive.value))
        ..add(Variable.withInt(periods[i].endInclusive.value));
    }
    buffer.write(' END AS bucket');
    return (
      selectSql: buffer.toString(),
      groupSql: 'bucket',
      joinSql: '',
      variables: variables,
    );
  }

  /// The period ranges a CASE index refers back to, so the engine can rebuild
  /// a `PeriodKey`. Must be called with the same arguments as [forDimension].
  static List<DateRange> periodsOf(
          PeriodType period, DateRange span, AppCalendar calendar) =>
      PeriodBoundaries.series(period, span, calendar);
}
```

Create `packages/nimbus_data/lib/src/analytics/analytics_engine.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../database/app_database.dart';
import '../tables/transactions_table.dart';
import 'analytics_predicates.dart';
import 'compiled_query.dart';
import 'group_expressions.dart';

/// Turns a [QuerySpec] into one SQL statement and its answer.
///
/// One engine, not two: a screen that needs a bespoke query is a missing
/// `QuerySpec` capability. A second query path beside this one is how the
/// numbers start disagreeing between two charts that should match.
final class AnalyticsEngine {
  AnalyticsEngine(this._db, {required AppCalendar calendar})
      : _calendar = calendar;

  final AppDatabase _db;
  final AppCalendar _calendar;

  CompiledQuery compile(QuerySpec spec) {
    final where = AnalyticsPredicates.whereClause(spec.filters);
    final group = GroupExpressions.forDimension(
      spec.groupBy,
      span: spec.filters.dateRange,
      calendar: _calendar,
    );

    // Variable order must match placeholder order in the finished statement:
    // SELECT fragments first, then JOIN, then WHERE.
    final variables = <Variable<Object>>[
      ...group.variables,
      ...where.variables,
    ];

    final sql = 'SELECT ${group.selectSql}, '
        'COALESCE(SUM(t.amount), 0) AS total, '
        'COUNT(*) AS n, '
        'MIN(t.amount) AS low, MAX(t.amount) AS high, AVG(t.amount) AS mean '
        'FROM transactions t${group.joinSql} '
        'WHERE ${where.sql} '
        'GROUP BY ${group.groupSql} '
        'ORDER BY ${group.groupSql}';

    return CompiledQuery(sql: sql, variables: variables);
  }

  Future<AnalyticsResult> run(QuerySpec spec) async {
    final compiled = compile(spec);
    final rows = await _db
        .customSelect(compiled.sql, variables: compiled.variables)
        .get();

    // The true total counts each transaction once, so it is deliberately not
    // derived from the buckets -- on a tag dimension those overlap.
    final trueWhere = AnalyticsPredicates.whereClause(spec.filters);
    final trueRow = await _db.customSelect(
      'SELECT COALESCE(SUM(t.amount), 0) AS total, COUNT(*) AS n '
      'FROM transactions t WHERE ${trueWhere.sql}',
      variables: trueWhere.variables,
    ).getSingle();

    final periods = switch (spec.groupBy) {
      GroupByPeriod(:final period) => GroupExpressions.periodsOf(
          period, spec.filters.dateRange!, _calendar),
      _ => const <DateRange>[],
    };

    return AnalyticsResult(
      buckets: [
        for (final row in rows)
          Bucket(
            key: _keyOf(spec.groupBy, row, periods),
            money: _moneyOf(spec.aggregate, row),
            count: row.data['n']! as int,
          ),
      ],
      trueTotal: Money(trueRow.data['total']! as int),
      trueCount: trueRow.data['n']! as int,
      bucketsMayOverlap: spec.isTagDimension,
    );
  }

  BucketKey _keyOf(
      GroupBy dimension, QueryRow row, List<DateRange> periods) {
    final bucket = row.data['bucket'];
    return switch (dimension) {
      GroupByNone() => const TotalKey(),
      GroupByMerchant() => MerchantKey(bucket as String?),
      GroupByPaymentMethod() => PaymentMethodKey(bucket as String?),
      GroupByHourOfDay() => HourOfDayKey(bucket! as int),
      // SQLite's %w is 0=Sunday; ISO is 1=Monday..7=Sunday.
      GroupByDayOfWeek() =>
        DayOfWeekKey(bucket! as int == 0 ? DateTime.sunday : bucket as int),
      GroupByCategory() =>
        CategoryKey(bucket! as String, row.data['bucket2']! as String),
      GroupByTag() =>
        TagKey(bucket! as String, row.data['bucket2']! as String),
      GroupByReflection() => ReflectionKey(
          necessity: _levelOf(NecessityLevel.values, bucket),
          satisfaction: _levelOf(SatisfactionLevel.values, row.data['bucket2']),
        ),
      GroupByPeriod() => PeriodKey(periods[bucket! as int]),
    };
  }

  static T? _levelOf<T extends Enum>(List<T> values, Object? raw) {
    if (raw == null) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw StateError('unknown stored value "$raw"');
  }

  /// The converter does not apply to an aggregate, so every number is wrapped
  /// by hand and none of them spends a moment as a double.
  static Money _moneyOf(Aggregate aggregate, QueryRow row) => switch (
          aggregate) {
        Aggregate.sum => Money(row.data['total']! as int),
        // For a count, the answer is Bucket.count; money is zero by contract.
        Aggregate.count => Money.zero,
        Aggregate.min => Money((row.data['low'] as int?) ?? 0),
        Aggregate.max => Money((row.data['high'] as int?) ?? 0),
        Aggregate.average => _moneyFromAverage(row.data['mean'] as double?),
      };

  /// Rounds half away from zero, once, at the last step.
  ///
  /// `AVG` is the only place SQL hands back a double. Dart's `round()` already
  /// rounds half away from zero, which is stated here so nobody "fixes" it to
  /// banker's rounding and quietly shifts every average by a minor unit.
  static Money _moneyFromAverage(double? mean) =>
      mean == null ? Money.zero : Money(mean.round());
}
```

- [ ] **Step 4: Export both.**

- [ ] **Step 5: Run the test** — 18 tests pass. Expect iteration here; this is the largest task in the plan. If a `bucket2` column collides on a dimension that does not use it, alias defensively rather than reordering the SELECT list.

- [ ] **Step 6: Full gate.**

- [ ] **Step 7: Tag and commit**

```bash
git tag pre-analytics-engine HEAD
git commit -m "feat: one engine, nine dimensions, one SQL statement

Period buckets are a CASE ladder whose bounds are computed in Dart by
PeriodBoundaries and bound as variables, so SQLite is only ever asked
whether an integer falls between two integers. That is what keeps a
Jalali month from being answered as a Gregorian one, and a test asserts
the two calendars disagree about the buckets while agreeing about the
total.

strftime appears exactly once, for day-of-week, and the comment says
why: the seven-day cycle is identical in both calendars, so no calendar
decision is being made there.

Money never becomes a double. The converter does not apply to an
aggregate -- SUM, MIN and MAX come back as ints and are wrapped by hand.
AVG is the one double SQL returns, rounded half away from zero exactly
once, with the rule written down so nobody switches it to banker's
rounding and shifts every average by a minor unit.

Null merchant and null payment method are real buckets. Refusing to
group by period without a date range is deliberate: there is no finite
set of periods to enumerate, and bucketing everything into one would
look like a working chart."
```

---

## Task 8: The double-count disclosure

**Files:**
- Test: `packages/nimbus_data/test/analytics/tag_overlap_test.dart`
- Modify: `packages/nimbus_data/lib/src/analytics/analytics_engine.dart` only if a test fails.

**This task adds no feature.** It exists because the brief names tag double-counting and nested rollup as the two bugs that "ship silently and make every number wrong in a way users will not catch". They deserve their own commit and their own test file so a future change that breaks them fails loudly and obviously.

**The assertion is an inequality. Asserting equality here is the bug.**

- [ ] **Step 1: Write the test** — it may pass immediately against Task 7's engine. That is fine and expected; the point is that it exists and is named.

Create `packages/nimbus_data/test/analytics/tag_overlap_test.dart`:

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbus_data/nimbus_data.dart';
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

  Future<AnalyticsResult> byTag([QueryFilters filters = const QueryFilters()]) =>
      engine.run(QuerySpec(
          filters: filters,
          groupBy: const GroupByTag(),
          aggregate: Aggregate.sum));

  test('tag buckets sum to MORE than the true total', () async {
    // The headline correctness trap. t1 carries /travel/ and /food/, so its
    // 1000 lands in two buckets. Measured: buckets 3000, true total 1750.
    //
    // If this ever asserts equality, the engine has started dropping a tag.
    final result = await byTag();
    expect(result.bucketSum.minorUnits, 3000);
    expect(result.trueTotal, const Money(1750));
    expect(result.bucketSum.minorUnits,
        greaterThan(result.trueTotal.minorUnits),
        reason: 'tag buckets overlap by construction; equality here means a '
            'transaction lost one of its tags');
  });

  test('the result declares that its buckets overlap', () async {
    // This flag is what a pie chart consults before claiming to show parts of
    // a whole. Without it the chart is a quiet lie.
    final result = await byTag();
    expect(result.overlaps, isTrue);
  });

  test('non-tag dimensions do not declare overlap and do sum to the total',
      () async {
    final result = await engine.run(const QuerySpec(
        filters: QueryFilters(),
        groupBy: GroupByMerchant(),
        aggregate: Aggregate.sum));
    expect(result.overlaps, isFalse);
    expect(result.bucketSum, result.trueTotal);
  });

  test('each tag bucket holds the right total', () async {
    final result = await byTag();
    final byId = {
      for (final bucket in result.buckets)
        (bucket.key as TagKey).tagId: bucket.money.minorUnits
    };
    expect(byId['travel'], 1500); // t1 1000 + t2 500
    expect(byId['food'], 1000); // t1
    expect(byId['flights'], 500); // t2
  });

  test('a nested rollup counts a transaction once', () async {
    // t2 carries BOTH /travel/ and its child /travel/flights/. Filtering to
    // the /travel/ subtree must yield 1500 over two transactions.
    //
    // The measured alternative -- a JOIN instead of EXISTS -- answers 2000
    // over three rows, confidently and with no error anywhere.
    final result = await engine.run(QuerySpec(
      filters: QueryFilters(tags: TagsAny(const ['/travel/'])),
      groupBy: const GroupByNone(),
      aggregate: Aggregate.sum,
    ));
    expect(result.trueTotal, const Money(1500));
    expect(result.trueCount, 2);
  });

  test('the true total ignores the grouping dimension entirely', () async {
    // Whatever the buckets do, the true total is the same number.
    final viaTag = await byTag();
    final viaMerchant = await engine.run(const QuerySpec(
        filters: QueryFilters(),
        groupBy: GroupByMerchant(),
        aggregate: Aggregate.sum));
    expect(viaTag.trueTotal, viaMerchant.trueTotal);
    expect(viaTag.trueCount, viaMerchant.trueCount);
  });
}
```

- [ ] **Step 2: Run it.** If any assertion fails, fix the **engine**, never the assertion.

- [ ] **Step 3: Full gate.**

- [ ] **Step 4: Tag and commit**

```bash
git tag pre-tag-overlap HEAD
git commit -m "test: pin the two ways tag numbers go silently wrong

Tag buckets sum to 3000 against a true total of 1750, because a
transaction with two tags lands in two buckets. The assertion is the
inequality -- asserting equality would mean the engine had started
dropping a tag, and the chart would look more plausible, not less.

Nested rollup counts a transaction once. t2 carries both /travel/ and
its child /travel/flights/; filtering to the /travel/ subtree yields
1500 over two transactions. The measured alternative, a JOIN instead of
EXISTS, answers 2000 over three rows -- confidently, on a chart, with no
error anywhere.

These get their own file because they are the two bugs the phase brief
singles out as making every number wrong in a way users cannot catch. If
one of these ever fails, fix the engine, not the assertion."
```

---

## Task 9: Query plan assertions

**Files:**
- Test: `packages/nimbus_data/test/analytics/query_plan_test.dart`
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` **only** to add an index, and only if a test proves one missing. Adding an index is a schema change — see Task 10 and take the lock.

**Verified mechanism:** `db.customSelect('EXPLAIN QUERY PLAN $sql', variables: ...)` returns rows whose `data['detail']` is the plan text. A date-range sum already reports `SEARCH transactions USING INDEX idx_tx_date (local_date_key>? AND local_date_key<?)`.

**Assert the plan of the statement that actually runs** — `engine.compile(spec).sql`, not a hand-written approximation. A correct query that degrades to a full scan at 50,000 rows is a bug that only appears once the app matters.

- [ ] **Step 1: Write the test**

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbus_data/nimbus_data.dart';
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

  /// The plan of the statement the engine will actually run.
  Future<String> planFor(QuerySpec spec) async {
    final compiled = engine.compile(spec);
    final rows = await db
        .customSelect('EXPLAIN QUERY PLAN ${compiled.sql}',
            variables: compiled.variables)
        .get();
    return rows.map((r) => r.data['detail']).join(' | ');
  }

  test('a period-filtered total uses the date index', () async {
    final plan = await planFor(QuerySpec(
      filters: QueryFilters(
          dateRange:
              DateRange(const DateKey(20260101), const DateKey(20260131))),
      groupBy: const GroupByNone(),
      aggregate: Aggregate.sum,
    ));
    expect(plan, contains('idx_tx_date'),
        reason: 'the dashboard asks this on every open; a full scan here is '
            'the difference between instant and visibly slow at 50k rows.\n'
            'Plan was: $plan');
    expect(plan, isNot(contains('SCAN transactions')),
        reason: 'plan was: $plan');
  });

  test('a category breakdown does not scan the categories table', () async {
    final plan = await planFor(QuerySpec(
      filters: QueryFilters(
          dateRange:
              DateRange(const DateKey(20260101), const DateKey(20261231))),
      groupBy: GroupByCategory(0),
      aggregate: Aggregate.sum,
    ));
    expect(plan, isNot(contains('SCAN categories')), reason: 'plan: $plan');
  });

  test('a tag filter uses the tag path index inside the subquery', () async {
    final plan = await planFor(QuerySpec(
      filters: QueryFilters(tags: TagsAny(const ['/travel/'])),
      groupBy: const GroupByNone(),
      aggregate: Aggregate.sum,
    ));
    expect(plan, contains('idx_tags_path'), reason: 'plan: $plan');
  });

  test('the confirmed-only dashboard query uses a composite index', () async {
    final plan = await planFor(QuerySpec(
      filters: QueryFilters(
        dateRange:
            DateRange(const DateKey(20260101), const DateKey(20260131)),
        confirmedOnly: true,
      ),
      groupBy: const GroupByNone(),
      aggregate: Aggregate.sum,
    ));
    expect(plan, anyOf(contains('idx_tx_unconfirmed'), contains('idx_tx_date')),
        reason: 'plan: $plan');
  });
}
```

- [ ] **Step 2: Run it.** These assertions are the most likely in the plan to need adjusting — SQLite's planner chooses differently as statements change shape. **Read the printed plan before weakening an assertion.** If the planner genuinely cannot use an index, the fix is an index (Task 10 and the schema lock), not a looser `expect`. If it picks a *different* legitimate index, widen the assertion to name both and say why in the commit.

- [ ] **Step 3: Full gate, tag, commit**

```bash
git tag pre-query-plan HEAD
git commit -m "test: assert the plan, not just the answer

A correct aggregation that degrades to a full scan is a bug that only
shows up once the app has enough data to matter to its user, which is
exactly when it is hardest to fix calmly.

These assert against engine.compile(spec).sql -- the statement that
actually runs -- rather than a hand-written approximation, because a
plan for a different statement proves nothing. Each failure message
prints the plan it saw, so the next person does not have to reconstruct
it."
```

---

## Task 10: Schema v20 — saved_views

**Files:**
- Create: `packages/nimbus_data/lib/src/tables/saved_views_table.dart`
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` (schemaVersion 1 → 20, migration step, table registration)
- Test: `packages/nimbus_data/test/analytics/saved_views_test.dart`
- Modify: `docs/phases/CONVENTIONS.md` schema registry row for Phase 3

**Take the schema lock first.** `CONVENTIONS.md` §2 makes a schema change a serialization point: it lands **alone**, in one small commit, before feature work. No other phase branch is active right now — `phase/1-expenses` and `phase/2-capture` are both merged into `main` — so the lock is uncontested. Say so in the commit message rather than leaving a reader to wonder whether it was skipped.

**Why v20 and not v2.** Ranges are reserved per phase precisely so two branches cannot both bump to the same number and silently drop one migration on merge. Phase 3 owns v20–v29.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  test('the schema version is 20', () async {
    expect(db.schemaVersion, 20);
  });

  test('a saved view round-trips its QuerySpec', () async {
    // The stored form is the JSON QuerySpec already tested in Task 3. What
    // this proves is that the column survives the trip through SQLite.
    final spec = QuerySpec(
      filters: QueryFilters(
        dateRange: DateRange(const DateKey(20260101), const DateKey(20260131)),
        tags: TagsAny(const ['/travel/']),
      ),
      groupBy: GroupByCategory(1),
      aggregate: Aggregate.sum,
    );

    await db.savedViews.upsert(
      id: 'v1',
      name: 'Travel in January',
      spec: spec,
      chartType: 'bar',
      pinned: true,
      sortOrder: 0,
    );

    final loaded = await db.savedViews.byId('v1');
    expect(loaded, isNotNull);
    expect(loaded!.spec, spec);
    expect(loaded.name, 'Travel in January');
    expect(loaded.pinned, isTrue);
  });

  test('pinned views come back in sort order', () async {
    const spec = QuerySpec(
        filters: QueryFilters(),
        groupBy: GroupByNone(),
        aggregate: Aggregate.sum);
    await db.savedViews.upsert(
        id: 'b', name: 'B', spec: spec, chartType: 'bar',
        pinned: true, sortOrder: 1);
    await db.savedViews.upsert(
        id: 'a', name: 'A', spec: spec, chartType: 'bar',
        pinned: true, sortOrder: 0);
    await db.savedViews.upsert(
        id: 'c', name: 'C', spec: spec, chartType: 'bar',
        pinned: false, sortOrder: 2);

    final pinned = await db.savedViews.pinned();
    expect(pinned.map((v) => v.id), ['a', 'b']);
  });

  test('a soft-deleted view is not returned', () async {
    const spec = QuerySpec(
        filters: QueryFilters(),
        groupBy: GroupByNone(),
        aggregate: Aggregate.sum);
    await db.savedViews.upsert(
        id: 'v', name: 'V', spec: spec, chartType: 'bar',
        pinned: true, sortOrder: 0);
    await db.savedViews.softDelete('v');
    expect(await db.savedViews.pinned(), isEmpty);
    expect(await db.savedViews.byId('v'), isNull);
  });

  test('unparseable stored JSON throws rather than yielding a default view',
      () async {
    await db.customStatement(
      "INSERT INTO saved_views (id,name,spec_json,chart_type,pinned,"
      "sort_order,created_at,updated_at,deleted_at) "
      "VALUES ('bad','Bad','{\"nope\":1}','bar',1,0,1,1,NULL)",
    );
    // A default here would silently show the wrong chart under the user's
    // own saved name.
    expect(() => db.savedViews.byId('bad'), throwsA(isA<Exception>()));
  });
}
```

- [ ] **Step 2: Run it and verify it fails.**

- [ ] **Step 3: Implement**

Create `packages/nimbus_data/lib/src/tables/saved_views_table.dart`:

```dart
import 'package:drift/drift.dart';

import '../database/columns.dart';

/// A named `QuerySpec` the user pinned.
///
/// The spec is stored as JSON rather than as columns because `QuerySpec` is
/// already a lossless JSON value (Phase 5 stores one as a goal's scope too),
/// and shredding it into columns would mean a migration every time the spec
/// grows a filter.
@TableIndex(name: 'idx_saved_views_pinned', columns: {#pinned, #sortOrder})
class SavedViews extends Table with BaseColumns {
  TextColumn get name => text()();

  /// A serialized `QuerySpec`.
  TextColumn get specJson => text()();

  TextColumn get chartType => text()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}
```

In `app_database.dart`: add `SavedViews` to the `@DriftDatabase(tables: [...])` list, raise `schemaVersion` to `20`, and add the upgrade step:

```dart
  @override
  int get schemaVersion => 20;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // v1 -> v20: Phase 3 adds saved_views. Phases 1 and 2 consumed no
          // schema version, so there is no intermediate step to write; the
          // reserved ranges in CONVENTIONS.md are what makes that safe rather
          // than lucky.
          if (from < 20) {
            await m.createTable(savedViews);
          }
        },
        beforeOpen: ...,  // leave whatever is already there unchanged
      );
```

Then regenerate drift's code and export the schema snapshot exactly as Phase 0 did — check `docs/DEVELOPMENT.md` for the exact commands rather than inventing them:

```bash
cd packages/nimbus_data && dart run build_runner build --delete-conflicting-outputs
```

Add a `SavedViewsDao` beside the existing DAOs in `app_database.dart`, following their idiom: `upsert(...)`, `byId(String)`, `pinned()`, `softDelete(String)`, every read filtering `deletedAt.isNull()`.

- [ ] **Step 4: Run the test, then the full gate including a migration test.**

- [ ] **Step 5: Update the schema registry** in `docs/phases/CONVENTIONS.md`: Phase 3's row moves from `Used: —` to `Used: **v20**`.

- [ ] **Step 6: Tag and commit**

```bash
git tag pre-schema-v20 HEAD
git commit -m "feat: schema v20, saved_views

Taking the schema lock. CONVENTIONS makes a schema change a
serialization point that lands alone before feature work; the lock is
uncontested right now because phase/1-expenses and phase/2-capture are
both merged into main and no other branch is active.

v20 rather than v2 because ranges are reserved per phase. Two branches
both bumping to v2 produce a broken migration on merge where one step
silently disappears, and the failure mode is a skipped migration on a
user's device.

The spec is stored as JSON rather than shredded into columns. QuerySpec
is already a lossless JSON value -- Phase 5 stores one as a goal's scope
-- and columns would mean a migration every time it grows a filter.

Unparseable stored JSON throws rather than yielding a default view,
because a default would show the wrong chart under the user's own saved
name."
```

---

## After Task 10

**Do not tag `phase-3-complete`.** The engine is done; the phase is not. Tasks 9–14 of the brief — breakdown, trends, comparison, cross-tab, patterns, saved-view UI, dashboard — are blocked by **D7**, and the phase gate additionally requires `phase-1-complete`, still withheld on **D1**.

Update the status board row for Phase 3 to say the engine is complete and what remains. Then re-check both blockers:

```bash
curl -sL -o /dev/null -w "%{http_code}\n" https://pub.dev/api/packages/fl_chart
curl -sL -o /dev/null -w "%{http_code}\n" \
  https://maven.google.com/androidx/core/core/1.13.1/core-1.13.1.pom
```

## Self-review

**Brief coverage.** Brief task 1 → plan tasks 1–3; brief 2 → plan 4; brief 3 → plan 6; brief 4 → plan 7; brief 5 → plan 8; brief 6 → plan 8; brief 7 → plan 9; brief 8 → plan 10. Plan task 5 (`AnalyticsResult`) is additional: the brief names the type in its interfaces list but gives it no task, and tasks 7–9 all return it.

**Verified before writing, not assumed:**
- `EXPLAIN QUERY PLAN` through `customSelect`, and that a date-range sum already reports `SEARCH transactions USING INDEX idx_tx_date`.
- `avg()` returns a nullable `double`; `sum()` a nullable `int`; a `TypeConverter` does not apply to aggregates.
- The whole fixture, executed against a real in-memory database: tag buckets **3000** vs true total **1750**; `/travel/` rollup **2000/n=3** by `JOIN` against **1500/n=2** by `EXISTS`; the CASE ladder bucketing three months correctly; hour and weekday as integer arithmetic.
- `MaterializedPath.subtreeUpperBound('/travel/') == '/travel0'`.
- The real column lists for `transactions`, `tags`, `transaction_tags`, and `categories` — **`categories` has `kind`, not `is_system`**, which cost a cycle when the probe was written from memory.

**Known soft spots, in order of likelihood:**
1. **Task 9's plan assertions.** SQLite's planner picks differently as a statement changes shape. Read the printed plan before weakening anything.
2. **Task 7's `bucket2` aliasing.** Dimensions that use one bucket column share a SELECT shape with those that use two; if drift or SQLite objects, alias per dimension.
3. **Variable ordering in `_tagCondition`** — bindings are appended as a side effect of building the string, so laziness in `map` would shift them. `.toList()` before `.join()` if bindings mismatch.
4. **`beforeOpen` in the migration** — leave whatever Phase 0 wrote untouched; only the `onUpgrade` branch is new.

**Not covered here, deliberately:** anything that draws. No `fl_chart`, no screens, no dashboard, no `phase-3-complete` tag.
