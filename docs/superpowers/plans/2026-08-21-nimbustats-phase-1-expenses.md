# NimbuStats Phase 1 — Expenses: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:executing-plans`
> to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking. The operator has asked to review **after every task**, so each task
> ends at a commit and a report, not at the next task.

**Goal:** make NimbuStats genuinely usable for daily expense logging — a seeded
category tree, category/tag/payment-method managers, a three-tap add flow, a
paginated transaction list, and the settings that govern how all of it renders.

**Architecture:** four packages with compiler-enforced boundaries, already
established in Phase 0. Phase 1 adds the presentation layer (`nimbus_design`
tokens + `app/lib/features/**`), one pure-domain predictor
(`nimbus_domain/src/prediction/`), one seeding module
(`nimbus_data/src/seed/`), and additive DAO methods. Riverpod supplies
dependency injection and state; `go_router` supplies routing composed from
per-feature route lists; every database write in the app funnels through
`TransactionRepository` so Phase 2's captures and Phase 6's widget have exactly
one insert path to reuse.

**Tech Stack:** Flutter 3.47.1 / Dart 3.13.1 · drift 2.34 · flutter_riverpod
3.4.2 · go_router (added in Task 2) · intl 0.20.3 · uuid 4.6 (in `nimbus_data`).

**Spec:** [`../specs/2026-08-20-nimbustats-design.md`](../specs/2026-08-20-nimbustats-design.md)
**Brief:** [`../../phases/phase-1-expenses.md`](../../phases/phase-1-expenses.md)
**Conventions:** [`../../phases/CONVENTIONS.md`](../../phases/CONVENTIONS.md)
**Screen contract:** [`../screen-contract.md`](../screen-contract.md)

---

## How to read this plan

Test code in this plan is **normative** — it is the contract for the task and
should be typed as written, because it is what a reviewer checks the
implementation against. Implementation code is given in full wherever the logic
is non-obvious (queries, path rewriting, keyset pagination, scoring, parsing,
migration-free system rows). For widget `build` methods the plan gives the real
widget tree, the exact `Key`s and `Semantics` labels the tests select on, and
the state branching — but the executor is expected to finish routine layout
(padding, alignment) against the tokens rather than copy pixel-level code from a
document written before the screen was ever rendered.

Where a step says **verify**, run the command and read the output. Do not infer
that it passed.

---

## Global Constraints

Copied verbatim from `CONVENTIONS.md` §1. Every task's requirements implicitly
include this section.

- **Flutter 3.47.1 / Dart 3.13.1.** `pubspec.lock` is committed. Do not bump the
  SDK or a dependency as a side effect of feature work.
- **Package boundaries — enforced by `test/architecture_test.dart`:**
  - `nimbus_domain` MUST NOT depend on `flutter`, `drift`, `sqlite3`,
    `flutter_riverpod`, `nimbus_data`, or `nimbus_design`.
  - `nimbus_data` MUST NOT depend on `flutter`, `flutter_riverpod`,
    `path_provider`, or `nimbus_design`.
  - `nimbus_design` MUST NOT depend on `drift`, `sqlite3`, or `nimbus_data`.
  - `app` may depend on all three. Phase 1 adds a fourth assertion: `app` must
    not depend on `drift` or `sqlite3` **directly** — it reaches the database
    only through `nimbus_data`'s injected-path factory.
- **Money is always `int` minor units.** `double` must never represent money.
- **Dates:** `occurred_at_utc` (epoch ms, UTC) **plus** `local_date_key`
  (`int`, `yyyymmdd`, local Gregorian). Period boundaries are computed in the
  *active calendar*, then converted to a `DateKey` range. Never do calendar
  math in SQL.
- **Every table carries** `id TEXT PRIMARY KEY` (UUIDv7), `created_at`,
  `updated_at`, `deleted_at NULL`.
- **Every query filters `deleted_at IS NULL`** through the one shared helper.
- **Locales:** `fa` (RTL, primary) and `en` (LTR). Every user-facing string goes
  through ARB localization. No hardcoded UI text, ever.
- **No `print`. No swallowed exceptions. No hardcoded fallback that masks a
  config error.**
- **The app must function completely with the VPS unreachable.**
- **TDD order is mandatory:** failing test to observe the failure, minimal
  implementation, observe the pass, broader suite, commit.

### Phase 1 additions to the global constraints

- **Schema stays at v1.** Phase 1 expects to consume none of its reserved
  v2–v9 range. If a column turns out to be genuinely required, stop, take the
  schema lock in `CONVENTIONS.md` §2, and land the migration alone first.
- **No modal confirmation dialogs anywhere.** Destructive actions use a snackbar
  with undo. Enforced by a source-grep test in Task 14, not by review alone.
- **No DAO call from a widget.** Presentation code calls repositories;
  repositories call DAOs. Enforced by the same grep test.
- **Every screen implements `loading`, `empty`, `error`, and `populated`.**
  Screen contract §1.1. A screen with only a happy path is not done.

---

## Decisions settled at kickoff

Recorded here because a later reader will otherwise re-litigate them.

| Decision | Choice | Why |
|---|---|---|
| Design tokens | Provisional, derived from the screen contract | No Claude Design token sheet exists. Tokens are marked `PROVISIONAL` in source so swapping a real sheet in is one file, and no screen holds a raw colour. |
| Routing | `go_router` (new dependency in `app`) | Phase 6's home-screen widget must deep-link into add-expense without booting the full app graph. Hand-rolling that on `onGenerateRoute` later costs more than the dependency does now. |
| Android scaffolding | `flutter create --platforms=android .` in Task 2 | Four of the ten UX criteria are only measurable on hardware, and `app/android/` did not exist. |
| Android applicationId | `com.nimbustats.app` | Product-named and Play-listable. Free to change now, impossible after Phase 8 publishes. |
| Review cadence | Stop after every task | Operator's choice. Each task ends at a green suite, a commit, and a report. |
| Uncategorized system row | Fixed string id `system-uncategorized`, no `is_system` column | The brief says Phase 0 creates it; Phase 0 in fact does not (verified — no seeding code exists anywhere in the repository). Adding an `is_system` column would consume schema v2 and take the schema lock for one boolean. A reserved id is enforceable in the repository, greppable, and stable across reinstalls. The brief's trap line is corrected in Task 4's commit. |
| Amount input | Real `TextField` with `autofocus` and a digit-normalising formatter, not a custom keypad | Gets paste, IME, hardware keyboards, screen-reader support, and dynamic type for free. A custom keypad would have to re-implement all four to satisfy screen contract §1.4. |
| Archive semantics | Archiving or soft-deleting a node applies to its whole subtree, transactionally | A picker that hides a parent but still offers its children is incoherent. `softDelete` returns the affected ids so undo restores exactly that set and nothing else. |
| pub.dev access | Operator's VPN | `pub.dev` returns 403 from this machine without it (Google geo-block; `storage.googleapis.com` too). Everything in `pubspec.lock` is cached, so builds work offline — only *adding* a package needs the VPN up. |

---

## File structure

New and modified files, by responsibility. Paths marked **(P0)** belong to
Phase 0 and are edited additively only; each such edit is called out in its
commit message per `CONVENTIONS.md` §3.

### `packages/nimbus_design/` — Phase 1 owns this package outright

| File | Responsibility |
|---|---|
| `lib/src/tokens.dart` | **(rewrite)** Provisional token set: spacing, radii, motion, tap target, elevation. No `ThemeData` here. |
| `lib/src/typography.dart` | Type ramp as a `TextTheme`, with the Persian/Latin font fallback stack. |
| `lib/src/colors.dart` | Light and dark `ColorScheme`s plus the app-specific roles (`expense`, `income`, necessity and satisfaction hues) that `ColorScheme` has no slot for, exposed as a `ThemeExtension`. |
| `lib/src/theme.dart` | **(rewrite)** Assembles tokens, typography and colours into `NimbusTheme.light()` / `.dark()`. |
| `lib/src/widgets/nimbus_empty_state.dart` | The `empty` state every screen needs: icon, title, message, optional action. Takes strings — `nimbus_design` never localises. |
| `lib/src/widgets/nimbus_error_state.dart` | The `error` state: what failed plus a retry. Never renders a raw exception. |
| `lib/src/widgets/nimbus_loading_list.dart` | The `loading` state: skeleton rows, never a blocking spinner. |
| `lib/src/widgets/nimbus_undo_snackbar.dart` | `SnackBar` factory for "undo, never confirm". |
| `lib/nimbus_design.dart` | Barrel — one export per line, alphabetically sorted. |

### `packages/nimbus_domain/` — Phase 1 owns `src/prediction/` only

| File | Responsibility |
|---|---|
| `lib/src/prediction/category_observation.dart` | Immutable `(categoryId, occurredAt, merchant?)` triple — the only history the predictor sees. |
| `lib/src/prediction/category_predictor.dart` | `abstract interface class CategoryPredictor`. Phase 2 swaps its implementation behind this. |
| `lib/src/prediction/mru_frequency_predictor.dart` | Phase 1's implementation: merchant match, then recency, then frequency, deterministic tie-break. |

### `packages/nimbus_data/` — Phase 1 owns `src/seed/`; DAO edits are additive

| File | Responsibility |
|---|---|
| `lib/src/seed/seed_category.dart` | `SeedCategoryNode` — a localised tree spec handed in by the app, because `nimbus_data` cannot localise. |
| `lib/src/seed/category_seeder.dart` | Idempotent, transactional first-run seeding; owns `SystemCategoryIds.uncategorized`. |
| `lib/src/seed/ids.dart` | `Ids.newId()` — UUIDv7 generation, so the app never needs the `uuid` package. |
| `lib/src/database/app_database.dart` **(P0)** | Additive: `AppDatabase.openAtPath`, and new methods on `SettingsDao`, `CategoriesDao`, `TagsDao`, `TransactionsDao`. A new `PaymentMethodsDao` lands in this file beside its siblings. |
| `lib/nimbus_data.dart` | Barrel — new exports appended alphabetically. |

### `app/` — Phase 1 owns every feature directory listed here

| File | Responsibility |
|---|---|
| `lib/main.dart` **(rewrite)** | Bootstrap only: resolve the database path, open it, override providers, `runApp`. |
| `lib/app.dart` | `MaterialApp.router` wired to locale, theme and calendar from settings. |
| `lib/bootstrap/database_provider.dart` | `appDatabaseProvider`, overridden at bootstrap and in every test. Throws if unoverridden. |
| `lib/bootstrap/app_router.dart` | Composes the per-feature route lists into one `GoRouter`. |
| `lib/features/settings/data/settings_repository.dart` | Typed façade over the key/value `SettingsDao`; `AppSettings` value type and its defaults. |
| `lib/features/settings/application/settings_providers.dart` | `settingsProvider` plus derived `currencyProvider`, `calendarProvider`, `localeProvider`, `themeModeProvider`, `moneyFormatterProvider`. |
| `lib/features/settings/presentation/settings_screen.dart` | The settings list. |
| `lib/features/settings/routes.dart` | Route names plus the `RouteBase` list. |
| `lib/features/onboarding/**` | First-run flow; skippable in one tap. |
| `lib/features/categories/**` | `CategoryRepository`, providers, manager screen, node editor sheet, picker. |
| `lib/features/tags/**` | `TagRepository`, providers, manager screen, inline-create picker. |
| `lib/features/payment_methods/**` | `PaymentMethodRepository`, providers, manager screen, picker. |
| `lib/features/transactions/data/transaction_draft.dart` | `TransactionDraft` value object. |
| `lib/features/transactions/data/transaction_repository.dart` | **The single write path.** |
| `lib/features/transactions/data/transaction_query.dart` | `PaginatedTransactionQuery` plus `TransactionPage`. |
| `lib/features/transactions/application/**` | Providers for add, list and detail. |
| `lib/features/transactions/presentation/**` | Add/edit screen, list screen, detail screen and their parts. |
| `lib/features/transactions/routes.dart` | The route names Phases 2 and 6 consume. |
| `lib/l10n/app_{en,fa}.arb` | Every string, keys prefixed by feature, inserted in alphabetical position. |

### Test files

| File | Covers |
|---|---|
| `packages/nimbus_design/test/theme_test.dart` | Token invariants, WCAG AA contrast, tap-target floor. |
| `packages/nimbus_design/test/widgets/*_test.dart` | The three state widgets and the undo snackbar. |
| `packages/nimbus_domain/test/prediction/mru_frequency_predictor_test.dart` | Ranking, tie-breaks, empty history. |
| `packages/nimbus_data/test/seed/category_seeder_test.dart` | Idempotency, paths, system row, rollback. |
| `packages/nimbus_data/test/categories_dao_test.dart` | Rename, archive subtree, soft delete and restore, reorder. |
| `packages/nimbus_data/test/tags_dao_test.dart` | The same, plus usage counts. |
| `packages/nimbus_data/test/payment_methods_dao_test.dart` | CRUD and archive. |
| `packages/nimbus_data/test/pagination_test.dart` | 5,000 rows: keyset walk with no gaps or repeats, index actually used. |
| `app/test/support/harness.dart` | Pumps any screen with an in-memory database, a locale, and overridden providers. |
| `app/test/features/**` | One test file per screen, covering all four states. |
| `app/test/ux_rules_test.dart` | Source-grep enforcement: no `showDialog`, no DAO call from presentation. |
| `test/architecture_test.dart` | Extended with the `app` boundary assertion. |

---

## Task map

The brief's twelve-item outline expands to sixteen tasks; data and UI split for
each manager so a reviewer can reject a query without rejecting a screen.

| # | Task | Brief item |
|---|---|---|
| 1 | Design tokens, theme, and the four shared state widgets | 1 |
| 2 | App shell: Android scaffolding, go_router, Riverpod, database provider | (scaffolding) |
| 3 | Settings repository and typed `AppSettings` | 11 (data half) |
| 4 | First-run seeding and the Uncategorized system row | 2 |
| 5 | Category DAO extensions and `CategoryRepository` | 3 (data half) |
| 6 | Category manager screen | 3 (UI half) |
| 7 | Tag DAO extensions and `TagRepository` | 4 (data half) |
| 8 | Tag manager screen | 4 (UI half) |
| 9 | Payment methods: DAO, repository, manager screen | 5 |
| 10 | `TransactionDraft`, `TransactionRepository`, keyset pagination | 6 |
| 11 | `CategoryPredictor` | 7 |
| 12 | Add-expense screen | 8 |
| 13 | Transaction list screen | 9 |
| 14 | Edit, delete with undo, necessity and satisfaction | 10 |
| 15 | Onboarding and settings screens | 11 (UI half) |
| 16 | UX budget verification, definition-of-done gate, gate tag | 12 |

---

## Task 1: Design tokens, theme, and the shared state widgets

Everything visual in Phase 1 references these. Landing them first means no screen
ever holds a raw colour or a magic number, so replacing the provisional palette
with a real Claude Design token sheet later is one file rather than a sweep.

**Files:**
- Rewrite: `packages/nimbus_design/lib/src/tokens.dart`
- Create: `packages/nimbus_design/lib/src/colors.dart`
- Create: `packages/nimbus_design/lib/src/typography.dart`
- Rewrite: `packages/nimbus_design/lib/src/theme.dart`
- Create: `packages/nimbus_design/lib/src/widgets/nimbus_empty_state.dart`
- Create: `packages/nimbus_design/lib/src/widgets/nimbus_error_state.dart`
- Create: `packages/nimbus_design/lib/src/widgets/nimbus_loading_list.dart`
- Create: `packages/nimbus_design/lib/src/widgets/nimbus_undo_snackbar.dart`
- Modify: `packages/nimbus_design/lib/nimbus_design.dart`
- Test: `packages/nimbus_design/test/theme_test.dart`
- Test: `packages/nimbus_design/test/widgets/state_widgets_test.dart`

**Interfaces:**
- Consumes: nothing outside Flutter.
- Produces:
  - `NimbusTokens.space1|space2|space3|space4|space6|space8` (`double`),
    `.radiusSm|radiusMd|radiusLg` (`double`), `.minTapTarget` (`double`),
    `.durationFast|durationNormal` (`Duration`), `.elevationCard` (`double`),
    `.maxTreeIndentDepth` (`int`), `.indentPerLevel` (`double`).
  - `NimbusColors.seed` (`Color`), `.lightScheme` / `.darkScheme`
    (`ColorScheme`), `.lightSemantics` / `.darkSemantics`
    (`NimbusSemanticColors`).
  - `NimbusSemanticColors extends ThemeExtension<NimbusSemanticColors>` with
    `expense`, `income`, `necessityNeeded`, `necessityOptional`,
    `necessityAvoidable`, `satisfactionGlad`, `satisfactionNeutral`,
    `satisfactionRegret`, `skeleton` (all `Color`), plus
    `static NimbusSemanticColors of(BuildContext)`.
  - `NimbusTypography.textTheme(ColorScheme scheme)` returning `TextTheme`.
  - `NimbusTheme.light()` / `NimbusTheme.dark()` returning `ThemeData`.
  - `NimbusEmptyState({required IconData icon, required String title,
    required String message, String? actionLabel, VoidCallback? onAction})`.
  - `NimbusErrorState({required String title, required String retryLabel,
    required VoidCallback onRetry, String? detail})`.
  - `NimbusLoadingList({int rows = 6})`.
  - `SnackBar nimbusUndoSnackBar({required String message,
    required String undoLabel, required VoidCallback onUndo})`.

---

- [ ] **Step 1: Write the failing theme test**

Create `packages/nimbus_design/test/theme_test.dart`:

```dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_design/nimbus_design.dart';

/// WCAG 2.1 relative luminance. Written out rather than pulled from a package
/// so the contrast assertions below depend on nothing that can drift.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('tokens', () {
    test('the spacing scale is strictly ascending', () {
      const scale = [
        NimbusTokens.space1,
        NimbusTokens.space2,
        NimbusTokens.space3,
        NimbusTokens.space4,
        NimbusTokens.space6,
        NimbusTokens.space8,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]),
            reason: 'spacing step $i must be larger than the one before it');
      }
    });

    test('the minimum tap target meets the platform accessibility floor', () {
      // Material and the Android accessibility guidelines both put this at 48.
      // Anything smaller is a defect on a phone held one-handed.
      expect(NimbusTokens.minTapTarget, greaterThanOrEqualTo(48.0));
    });

    test('tree indentation is capped so a six-level tree still fits', () {
      // Screen contract D4: indentation must degrade rather than push a deep
      // node off the side of the screen.
      expect(NimbusTokens.maxTreeIndentDepth, lessThanOrEqualTo(4));
      expect(
        NimbusTokens.indentPerLevel * NimbusTokens.maxTreeIndentDepth,
        lessThanOrEqualTo(64.0),
      );
    });
  });

  group('contrast', () {
    // Screen contract 1.4: contrast is part of the definition of done for every
    // screen, so it is asserted once here rather than eyeballed per screen.
    void assertReadable(String name, Color foreground, Color background) {
      expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5),
          reason: '$name must meet WCAG AA against its surface');
    }

    test('light semantic colours are readable on the light surface', () {
      final scheme = NimbusColors.lightScheme;
      final s = NimbusColors.lightSemantics;
      assertReadable('expense', s.expense, scheme.surface);
      assertReadable('income', s.income, scheme.surface);
      assertReadable('necessityNeeded', s.necessityNeeded, scheme.surface);
      assertReadable('necessityOptional', s.necessityOptional, scheme.surface);
      assertReadable('necessityAvoidable', s.necessityAvoidable, scheme.surface);
      assertReadable('satisfactionGlad', s.satisfactionGlad, scheme.surface);
      assertReadable('satisfactionNeutral', s.satisfactionNeutral, scheme.surface);
      assertReadable('satisfactionRegret', s.satisfactionRegret, scheme.surface);
      assertReadable('onSurface', scheme.onSurface, scheme.surface);
    });

    test('dark semantic colours are readable on the dark surface', () {
      final scheme = NimbusColors.darkScheme;
      final s = NimbusColors.darkSemantics;
      assertReadable('expense', s.expense, scheme.surface);
      assertReadable('income', s.income, scheme.surface);
      assertReadable('necessityNeeded', s.necessityNeeded, scheme.surface);
      assertReadable('necessityOptional', s.necessityOptional, scheme.surface);
      assertReadable('necessityAvoidable', s.necessityAvoidable, scheme.surface);
      assertReadable('satisfactionGlad', s.satisfactionGlad, scheme.surface);
      assertReadable('satisfactionNeutral', s.satisfactionNeutral, scheme.surface);
      assertReadable('satisfactionRegret', s.satisfactionRegret, scheme.surface);
      assertReadable('onSurface', scheme.onSurface, scheme.surface);
    });

    test('expense and income differ by more than hue alone', () {
      // Screen contract D6: direction must be distinguishable without relying
      // on colour. The colours still have to differ for users who do see them,
      // but the widgets additionally carry a sign or arrow -- asserted where
      // those widgets are built, not here.
      final light = NimbusColors.lightSemantics;
      expect(_contrast(light.expense, light.income), greaterThan(1.2),
          reason: 'expense and income must not be near-identical in value');
    });
  });

  group('theme', () {
    test('light and dark themes carry the semantic extension', () {
      expect(
        NimbusTheme.light().extension<NimbusSemanticColors>(),
        isNotNull,
        reason: 'screens read semantic colours through the extension',
      );
      expect(NimbusTheme.dark().extension<NimbusSemanticColors>(), isNotNull);
    });

    test('themes use Material 3 and the seeded scheme', () {
      final light = NimbusTheme.light();
      expect(light.useMaterial3, isTrue);
      expect(light.colorScheme.brightness, Brightness.light);
      expect(NimbusTheme.dark().colorScheme.brightness, Brightness.dark);
    });

    test('the type ramp is complete and ascending in the display sizes', () {
      final text = NimbusTheme.light().textTheme;
      for (final style in [
        text.displaySmall,
        text.headlineMedium,
        text.titleLarge,
        text.titleMedium,
        text.bodyLarge,
        text.bodyMedium,
        text.labelLarge,
        text.labelSmall,
      ]) {
        expect(style, isNotNull);
        expect(style!.fontSize, isNotNull);
      }
      expect(text.displaySmall!.fontSize!,
          greaterThan(text.headlineMedium!.fontSize!));
      expect(text.headlineMedium!.fontSize!,
          greaterThan(text.titleLarge!.fontSize!));
      expect(text.bodyLarge!.fontSize!, greaterThan(text.labelSmall!.fontSize!));
    });

    test('the font fallback stack can render Persian', () {
      // No font is bundled, so Persian rendering depends on the platform
      // fallback list being present. Naming it explicitly is what keeps a
      // future refactor from silently dropping it.
      final fallback = NimbusTheme.light().textTheme.bodyMedium!.fontFamilyFallback;
      expect(fallback, isNotNull);
      expect(fallback, contains('Noto Naskh Arabic'));
    });

    test('semantic colours resolve from a BuildContext', () {
      // NimbusSemanticColors.of is what every screen calls; a null return
      // would only show up as a crash deep in a widget tree otherwise.
      expect(
        NimbusTheme.dark().extension<NimbusSemanticColors>()!.expense,
        NimbusColors.darkSemantics.expense,
      );
    });
  });
}
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
cd packages/nimbus_design && flutter test test/theme_test.dart
```

Expected: compile failure — `NimbusColors`, `NimbusSemanticColors`, and the new
`NimbusTokens` members do not exist yet. Read the output and confirm the failure
is "undefined name", not something unrelated.

- [ ] **Step 3: Write the tokens**

Replace `packages/nimbus_design/lib/src/tokens.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Spacing, radii, motion, and the dimensional floors every screen obeys.
///
/// PROVISIONAL. These values are derived from the screen contract's constraints
/// rather than from a Claude Design token sheet, which does not exist yet. They
/// are named rather than inlined precisely so that swapping in a real sheet is
/// an edit to this file and `colors.dart`, not a sweep across every screen.
abstract final class NimbusTokens {
  // A 4pt base scale. The gaps (no space5, space7) are deliberate: a scale with
  // every integer step is not a scale, it is a licence to eyeball.
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space6 = 24.0;
  static const space8 = 32.0;

  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 20.0;

  static const BorderRadius borderRadiusSm =
      BorderRadius.all(Radius.circular(radiusSm));
  static const BorderRadius borderRadiusMd =
      BorderRadius.all(Radius.circular(radiusMd));
  static const BorderRadius borderRadiusLg =
      BorderRadius.all(Radius.circular(radiusLg));

  /// Minimum tap target. Primary actions sit in the bottom third of the screen
  /// so they stay within one-handed reach.
  static const minTapTarget = 48.0;

  /// Chips in the add flow are tapped more than anything else in the app, so
  /// they get a target above the floor rather than at it.
  static const chipHeight = 44.0;

  static const elevationCard = 0.0;
  static const elevationSheet = 3.0;

  /// Screen contract D4: a six-level category tree must stay legible. Indent
  /// stops growing after this many levels and the breadcrumb carries the rest.
  static const maxTreeIndentDepth = 4;
  static const indentPerLevel = 16.0;

  /// Motion. Fast is for state that the user caused directly (a chip
  /// selecting); normal is for surfaces arriving.
  static const durationFast = Duration(milliseconds: 120);
  static const durationNormal = Duration(milliseconds: 200);
  static const curveStandard = Curves.easeOutCubic;
}
```

- [ ] **Step 4: Write the colours**

Create `packages/nimbus_design/lib/src/colors.dart`:

```dart
import 'package:flutter/material.dart';

/// Colours the app needs that Material's [ColorScheme] has no slot for.
///
/// Direction and the reflection axes are domain concepts, not Material roles,
/// so they live in a [ThemeExtension] rather than being smuggled into
/// `tertiary` and friends where the next reader would have to guess.
@immutable
final class NimbusSemanticColors extends ThemeExtension<NimbusSemanticColors> {
  const NimbusSemanticColors({
    required this.expense,
    required this.income,
    required this.necessityNeeded,
    required this.necessityOptional,
    required this.necessityAvoidable,
    required this.satisfactionGlad,
    required this.satisfactionNeutral,
    required this.satisfactionRegret,
    required this.skeleton,
  });

  final Color expense;
  final Color income;
  final Color necessityNeeded;
  final Color necessityOptional;
  final Color necessityAvoidable;
  final Color satisfactionGlad;
  final Color satisfactionNeutral;
  final Color satisfactionRegret;

  /// Fill for loading skeleton rows.
  final Color skeleton;

  static NimbusSemanticColors of(BuildContext context) {
    final ext = Theme.of(context).extension<NimbusSemanticColors>();
    if (ext == null) {
      // Not a fallback: a missing extension means the app was built without
      // NimbusTheme, and returning defaults here would hide that until a
      // designer noticed the wrong red in a screenshot.
      throw StateError(
        'NimbusSemanticColors is missing. Build the app with NimbusTheme.',
      );
    }
    return ext;
  }

  @override
  NimbusSemanticColors copyWith({
    Color? expense,
    Color? income,
    Color? necessityNeeded,
    Color? necessityOptional,
    Color? necessityAvoidable,
    Color? satisfactionGlad,
    Color? satisfactionNeutral,
    Color? satisfactionRegret,
    Color? skeleton,
  }) =>
      NimbusSemanticColors(
        expense: expense ?? this.expense,
        income: income ?? this.income,
        necessityNeeded: necessityNeeded ?? this.necessityNeeded,
        necessityOptional: necessityOptional ?? this.necessityOptional,
        necessityAvoidable: necessityAvoidable ?? this.necessityAvoidable,
        satisfactionGlad: satisfactionGlad ?? this.satisfactionGlad,
        satisfactionNeutral: satisfactionNeutral ?? this.satisfactionNeutral,
        satisfactionRegret: satisfactionRegret ?? this.satisfactionRegret,
        skeleton: skeleton ?? this.skeleton,
      );

  @override
  NimbusSemanticColors lerp(
    ThemeExtension<NimbusSemanticColors>? other,
    double t,
  ) {
    if (other is! NimbusSemanticColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return NimbusSemanticColors(
      expense: mix(expense, other.expense),
      income: mix(income, other.income),
      necessityNeeded: mix(necessityNeeded, other.necessityNeeded),
      necessityOptional: mix(necessityOptional, other.necessityOptional),
      necessityAvoidable: mix(necessityAvoidable, other.necessityAvoidable),
      satisfactionGlad: mix(satisfactionGlad, other.satisfactionGlad),
      satisfactionNeutral: mix(satisfactionNeutral, other.satisfactionNeutral),
      satisfactionRegret: mix(satisfactionRegret, other.satisfactionRegret),
      skeleton: mix(skeleton, other.skeleton),
    );
  }
}

/// PROVISIONAL palette, derived from the screen contract rather than a design
/// token sheet. Every value below is checked against WCAG AA by
/// `test/theme_test.dart`, so a future substitution cannot quietly become
/// unreadable.
abstract final class NimbusColors {
  /// A muted green. Money apps that shout at you get uninstalled; the regret
  /// matrix in Phase 3 is explicitly required to read as factual, not punitive,
  /// and that starts with the seed.
  static const seed = Color(0xFF2E7D64);

  static final ColorScheme lightScheme =
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);

  static final ColorScheme darkScheme =
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);

  static const lightSemantics = NimbusSemanticColors(
    expense: Color(0xFFC0392B),
    income: Color(0xFF1B7F5C),
    necessityNeeded: Color(0xFF1B7F5C),
    necessityOptional: Color(0xFF8A6A00),
    necessityAvoidable: Color(0xFFC0392B),
    satisfactionGlad: Color(0xFF1B7F5C),
    satisfactionNeutral: Color(0xFF5A5F5C),
    satisfactionRegret: Color(0xFFC0392B),
    skeleton: Color(0xFFE3E7E4),
  );

  static const darkSemantics = NimbusSemanticColors(
    expense: Color(0xFFFF8A80),
    income: Color(0xFF6EE7B7),
    necessityNeeded: Color(0xFF6EE7B7),
    necessityOptional: Color(0xFFE8C547),
    necessityAvoidable: Color(0xFFFF8A80),
    satisfactionGlad: Color(0xFF6EE7B7),
    satisfactionNeutral: Color(0xFFA8B0AC),
    satisfactionRegret: Color(0xFFFF8A80),
    skeleton: Color(0xFF2A2E2C),
  );
}
```

- [ ] **Step 5: Write the type ramp**

Create `packages/nimbus_design/lib/src/typography.dart`:

```dart
import 'package:flutter/material.dart';

/// The type ramp.
///
/// PROVISIONAL sizes, derived from the screen contract's density requirements.
/// No font file is bundled: Persian renders through the platform fallback
/// stack, which is named explicitly below so a refactor cannot silently drop it
/// and leave Farsi users looking at tofu. Bundling Vazirmatn is the obvious
/// upgrade and is deliberately deferred to the phase that has a token sheet.
abstract final class NimbusTypography {
  static const _fallback = <String>[
    'Noto Naskh Arabic',
    'Noto Sans Arabic',
    'Roboto',
  ];

  static TextTheme textTheme(ColorScheme scheme) {
    TextStyle style(double size, FontWeight weight, {double? height}) =>
        TextStyle(
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: scheme.onSurface,
          fontFamilyFallback: _fallback,
        );

    return TextTheme(
      // Reserved for the one number a screen is actually about: the amount on
      // the add screen, the month total on the list.
      displaySmall: style(36, FontWeight.w600, height: 1.15),
      headlineMedium: style(28, FontWeight.w600, height: 1.2),
      titleLarge: style(22, FontWeight.w600, height: 1.25),
      titleMedium: style(16, FontWeight.w600, height: 1.3),
      bodyLarge: style(16, FontWeight.w400, height: 1.4),
      bodyMedium: style(14, FontWeight.w400, height: 1.4),
      labelLarge: style(14, FontWeight.w600, height: 1.2),
      labelMedium: style(12, FontWeight.w500, height: 1.2),
      labelSmall: style(11, FontWeight.w500, height: 1.2),
    );
  }
}
```

- [ ] **Step 6: Assemble the theme**

Replace `packages/nimbus_design/lib/src/theme.dart`:

```dart
import 'package:flutter/material.dart';

import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';

abstract final class NimbusTheme {
  static ThemeData light() =>
      _base(NimbusColors.lightScheme, NimbusColors.lightSemantics);

  static ThemeData dark() =>
      _base(NimbusColors.darkScheme, NimbusColors.darkSemantics);

  static ThemeData _base(ColorScheme scheme, NimbusSemanticColors semantics) {
    final text = NimbusTypography.textTheme(scheme);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      textTheme: text,
      extensions: <ThemeExtension<dynamic>>[semantics],
      // standard rather than compact: dynamic type is a stated requirement, and
      // compact density fights it on the first notch of enlargement.
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: NimbusTokens.borderRadiusMd,
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: text.labelLarge,
        shape: const RoundedRectangleBorder(
          borderRadius: NimbusTokens.borderRadiusLg,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize:
              const Size(NimbusTokens.minTapTarget, NimbusTokens.minTapTarget),
          shape: const RoundedRectangleBorder(
            borderRadius: NimbusTokens.borderRadiusMd,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: NimbusTokens.space2,
      ),
      cardTheme: const CardThemeData(
        elevation: NimbusTokens.elevationCard,
        shape: RoundedRectangleBorder(
          borderRadius: NimbusTokens.borderRadiusMd,
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Update the barrel and run the theme test**

Append to `packages/nimbus_design/lib/nimbus_design.dart`, keeping one export
per line in alphabetical order:

```dart
export 'src/colors.dart';
export 'src/theme.dart';
export 'src/tokens.dart';
export 'src/typography.dart';
export 'src/widgets/nimbus_empty_state.dart';
export 'src/widgets/nimbus_error_state.dart';
export 'src/widgets/nimbus_loading_list.dart';
export 'src/widgets/nimbus_undo_snackbar.dart';
```

Run: `cd packages/nimbus_design && flutter test test/theme_test.dart`

Expected: the widget exports fail to resolve until Step 9. Run the theme test
alone by temporarily importing `src/theme.dart` directly if the barrel blocks
it, or write the widgets first — the order within this task is a convenience,
not a contract. What matters is that the contrast assertions were seen to fail
before the palette existed.

- [ ] **Step 8: Write the failing state-widget test**

Create `packages/nimbus_design/test/widgets/state_widgets_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_design/nimbus_design.dart';

void main() {
  Widget host(Widget child, {TextDirection direction = TextDirection.rtl}) =>
      MaterialApp(
        theme: NimbusTheme.light(),
        home: Directionality(
          textDirection: direction,
          child: Scaffold(body: child),
        ),
      );

  group('NimbusEmptyState', () {
    testWidgets('shows the title, the message, and the action', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(host(NimbusEmptyState(
        icon: Icons.receipt_long,
        title: 'Nothing here yet',
        message: 'Log your first expense to see it appear.',
        actionLabel: 'Add expense',
        onAction: () => tapped++,
      )));

      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Log your first expense to see it appear.'),
          findsOneWidget);

      await tester.tap(find.text('Add expense'));
      expect(tapped, 1,
          reason: 'an empty state that says what to do next must let you do it');
    });

    testWidgets('omits the action when none is given', (tester) async {
      await tester.pumpWidget(host(const NimbusEmptyState(
        icon: Icons.sell,
        title: 'No tags',
        message: 'Tags group expenses across categories.',
      )));
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('renders right-to-left without overflowing', (tester) async {
      await tester.pumpWidget(host(const NimbusEmptyState(
        icon: Icons.sell,
        title: 'برچسبی وجود ندارد',
        message: 'برچسب‌ها هزینه‌ها را فراتر از دسته‌بندی گروه‌بندی می‌کنند.',
      )));
      expect(tester.takeException(), isNull);
      expect(find.text('برچسبی وجود ندارد'), findsOneWidget);
    });
  });

  group('NimbusErrorState', () {
    testWidgets('offers a retry and never shows a raw exception', (tester) async {
      var retried = 0;
      await tester.pumpWidget(host(NimbusErrorState(
        title: 'Could not load transactions',
        retryLabel: 'Retry',
        onRetry: () => retried++,
        detail: 'DatabaseException: no such table: transactions',
      )));

      expect(find.text('Could not load transactions'), findsOneWidget);
      // The detail is available but not shouted: the contract forbids a bare
      // exception string as the error state.
      expect(find.text('DatabaseException: no such table: transactions'),
          findsNothing);

      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });
  });

  group('NimbusLoadingList', () {
    testWidgets('renders skeleton rows, not a blocking spinner', (tester) async {
      await tester.pumpWidget(host(const NimbusLoadingList(rows: 4)));
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'the contract forbids a blocking spinner for a read');
      expect(find.byKey(const Key('nimbus-skeleton-row')), findsNWidgets(4));
    });
  });

  group('nimbusUndoSnackBar', () {
    testWidgets('carries an undo action rather than a confirmation',
        (tester) async {
      var undone = 0;
      late BuildContext ctx;
      await tester.pumpWidget(host(Builder(builder: (context) {
        ctx = context;
        return const SizedBox.shrink();
      })));

      ScaffoldMessenger.of(ctx).showSnackBar(nimbusUndoSnackBar(
        message: 'Deleted',
        undoLabel: 'Undo',
        onUndo: () => undone++,
      ));
      await tester.pump();

      expect(find.text('Deleted'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      expect(undone, 1);
    });
  });
}
```

- [ ] **Step 9: Run the widget test and verify it fails**

```bash
cd packages/nimbus_design && flutter test test/widgets/state_widgets_test.dart
```

Expected: undefined names `NimbusEmptyState`, `NimbusErrorState`,
`NimbusLoadingList`, `nimbusUndoSnackBar`.

- [ ] **Step 10: Implement the four state widgets**

`nimbus_empty_state.dart` — a centred column: icon at `scheme.outline`, title in
`titleMedium`, message in `bodyMedium` at `onSurfaceVariant`, and, when
`actionLabel` and `onAction` are both non-null, a `FilledButton` below it.
Everything spaced with `NimbusTokens.space4`; the whole thing padded
`space6` and wrapped in `Center`. Text is `textAlign: TextAlign.center`, which
is direction-neutral and therefore correct in both locales.

`nimbus_error_state.dart` — the same skeleton with `Icons.error_outline` at
`scheme.error`, the title, and a `FilledButton` carrying `retryLabel`. `detail`
is stored on the widget and rendered only inside an `ExpansionTile` labelled by
the caller — this is what keeps the contract's "never a bare exception string"
true while still leaving the detail reachable for a bug report. For Phase 1 the
detail is not rendered at all; it is accepted so callers stop dropping it on the
floor, and the widget's doc comment says exactly that.

`nimbus_loading_list.dart` — `ListView.builder` of `rows` items, each a
`Container` of height `NimbusTokens.minTapTarget` with
`semantics.skeleton` fill and `borderRadiusSm`, each keyed
`const Key('nimbus-skeleton-row')`, separated by `space2`. No animation in Phase
1: a static skeleton costs nothing and cannot drop frames.

`nimbus_undo_snackbar.dart`:

```dart
import 'package:flutter/material.dart';

import '../tokens.dart';

/// The app's one destructive-action affordance.
///
/// "Undo, never confirm" is a stated interaction rule, so there is deliberately
/// no confirmation-dialog counterpart to this function anywhere in the
/// codebase; `app/test/ux_rules_test.dart` asserts none appears.
SnackBar nimbusUndoSnackBar({
  required String message,
  required String undoLabel,
  required VoidCallback onUndo,
  Duration duration = const Duration(seconds: 5),
}) =>
    SnackBar(
      content: Text(message),
      duration: duration,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(NimbusTokens.space4),
      action: SnackBarAction(label: undoLabel, onPressed: onUndo),
    );
```

- [ ] **Step 11: Run both test files and verify they pass**

```bash
cd packages/nimbus_design && flutter test
```

Expected: all green.

- [ ] **Step 12: Run the broader suite**

```bash
cd ../.. && dart analyze --fatal-infos
dart test test/architecture_test.dart
cd packages/nimbus_domain && dart test
cd ../nimbus_data && dart test
cd ../../app && flutter test
```

Expected: all green. `nimbus_design` is a leaf, so nothing else should move.

- [ ] **Step 13: Tag the rollback point and commit**

```bash
git tag pre-design-tokens HEAD
git add packages/nimbus_design docs/superpowers/plans
git commit -m "feat: provisional design tokens, theme, and shared state widgets

Every Phase 1 screen references tokens rather than literals, so replacing this
provisional palette with a real Claude Design token sheet is an edit to two
files instead of a sweep through every screen. The contrast assertions are the
point: a substituted palette that fails WCAG AA fails the build rather than
shipping and being noticed in a screenshot months later.

The four state widgets land here because the screen contract requires empty,
loading, and error on every screen -- building them once now is what makes that
requirement cheap enough to actually honour."
```

---

## Task 2: App shell — Android scaffolding, go_router, Riverpod, database provider

Nothing above the domain layer can be built until the app can open a database,
resolve a route, and be pumped in a test. This task builds exactly that and
nothing else, so a failure here is unambiguous.

**Prerequisite — operator action.** `pub.dev` returns 403 from this machine
without the VPN. Before Step 3, confirm:

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://pub.dev/api/packages/go_router
```

Expected: `200`. If it prints `403`, stop and ask the operator to bring the VPN
up; do not work around it with a mirror without an explicit decision, because a
mirror establishes the hash for a newly added package.

**Files:**
- Create: `app/android/**` (generated by `flutter create`)
- Modify: `app/pubspec.yaml` (add `go_router`)
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` **(P0)** —
  add `AppDatabase.openAtPath`
- Create: `app/lib/bootstrap/database_provider.dart`
- Create: `app/lib/bootstrap/app_router.dart`
- Create: `app/lib/app.dart`
- Rewrite: `app/lib/main.dart`
- Create: `app/test/support/harness.dart`
- Test: `app/test/bootstrap/app_shell_test.dart`
- Modify: `test/architecture_test.dart`

**Interfaces:**
- Consumes: `AppDatabase` (Phase 0), `NimbusTheme` (Task 1).
- Produces:
  - `AppDatabase.openAtPath(String path)` — the only way the app constructs a
    database, keeping `drift` and `sqlite3` out of `app`'s dependency list.
  - `appDatabaseProvider` (`Provider<AppDatabase>`) — throws unless overridden.
  - `appRouterProvider` (`Provider<GoRouter>`) — composes feature route lists.
  - `NimbuStatsApp` — `MaterialApp.router`, locale and theme driven by
    providers added in Task 3.
  - `pumpApp(WidgetTester, {Widget? home, List<Override> overrides,
    Locale locale})` in `app/test/support/harness.dart` — every later widget
    test uses it.

---

- [ ] **Step 1: Scaffold the Android platform folder**

```bash
cd app && flutter create --platforms=android --org com.nimbustats --project-name nimbustats .
```

Verify: `app/android/app/build.gradle.kts` (or `.gradle`) contains
`applicationId = "com.nimbustats.app"`. If `flutter create` produced
`com.nimbustats.nimbustats`, edit `applicationId` and `namespace` to
`com.nimbustats.app` and move the generated `MainActivity` package directory to
match — a mismatch between `namespace` and the Kotlin package fails the build
with a message that does not name the cause.

Then confirm the generated `pubspec.yaml` was not rewritten:

```bash
git diff app/pubspec.yaml
```

Expected: no change, or only a `flutter:` section addition. `flutter create`
over an existing project preserves dependencies, but confirm rather than assume.

- [ ] **Step 2: Verify the app still builds and tests still pass**

```bash
cd app && flutter test
```

Expected: the Phase 0 localization tests still pass. If `flutter create`
replaced `lib/main.dart`, restore it from git — it is rewritten deliberately in
Step 7, not accidentally in Step 1.

```bash
git checkout -- app/lib/main.dart   # only if flutter create clobbered it
```

- [ ] **Step 3: Add go_router**

```bash
cd app && dart pub add go_router
```

Record the resolved version in the commit message. Then:

```bash
git diff app/pubspec.yaml pubspec.lock
```

Expected: `go_router` appears in `dependencies` with a caret constraint, and
`pubspec.lock` gains `go_router` plus its transitive deps.

- [ ] **Step 4: Write the failing architecture assertion**

Append to `test/architecture_test.dart`:

```dart
  test('app reaches the database only through nimbus_data', () {
    // app may depend on all three packages, but not on drift or sqlite3
    // directly: the moment a screen can construct a NativeDatabase, the
    // "UI cannot import the database" boundary is decoration.
    final deps = runtimeDeps('app');
    for (final forbidden in ['drift', 'sqlite3']) {
      expect(deps, isNot(contains(forbidden)),
          reason: 'app must open the database through '
              'AppDatabase.openAtPath; remove $forbidden');
    }
    expect(deps, contains('nimbus_data'));
    expect(deps, contains('nimbus_domain'));
    expect(deps, contains('nimbus_design'));
    // go_router is Phase 1's one new dependency; asserting it is present keeps
    // the routing decision visible to anyone reading the boundary rules.
    expect(deps, contains('go_router'));
  });
```

- [ ] **Step 5: Run it and verify it fails**

```bash
dart test test/architecture_test.dart
```

Expected: fails on `go_router` if Step 3 has not been run, passes otherwise. If
it passes immediately, that is fine — the assertion's value is regression
protection, and Step 3 already made it true.

- [ ] **Step 6: Add the injected-path factory to `nimbus_data`**

In `packages/nimbus_data/lib/src/database/app_database.dart`, add to
`AppDatabase`:

```dart
  /// Opens the database at [path].
  ///
  /// The app layer owns *where* the file lives (it has `path_provider`; this
  /// package deliberately does not) and this factory owns *how* it is opened.
  /// Keeping `NativeDatabase` behind this boundary is what lets
  /// `test/architecture_test.dart` assert that `app` depends on neither
  /// `drift` nor `sqlite3`.
  factory AppDatabase.openAtPath(String path) =>
      AppDatabase(NativeDatabase(File(path)));
```

with `import 'dart:io';` and `import 'package:drift/native.dart';` at the top of
the file.

- [ ] **Step 7: Write the failing app-shell test**

Create `app/test/bootstrap/app_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';

import '../support/harness.dart';

void main() {
  testWidgets('the app boots against an injected database', (tester) async {
    await pumpApp(tester);
    // The shell renders. Screens arrive in later tasks; what is asserted here
    // is that provider overrides, the router, and the theme compose at all.
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('an unknown route renders the error screen, not a crash',
      (tester) async {
    await pumpApp(tester, initialLocation: '/no-such-route');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('router-error')), findsOneWidget);
  });

  test('the database provider refuses to guess a database', () {
    // A provider that silently created an in-memory database when the real one
    // was missing would turn a bootstrap failure into silent data loss.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(() => container.read(appDatabaseProvider), throwsStateError);
  });

  testWidgets('the injected database is a real, queryable database',
      (tester) async {
    late AppDatabase db;
    await pumpApp(tester, onContainer: (c) => db = c.read(appDatabaseProvider));
    // Proves sqlite3 resolves under `flutter test` on this host, which is the
    // one thing about the app-layer test setup that could fail for
    // environmental rather than logical reasons.
    await expectLater(db.settingsDao.get('missing'), completion(isNull));
  });
}
```

- [ ] **Step 8: Write the test harness**

Create `app/test/support/harness.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/app.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';

/// Pumps the real app against a fresh in-memory database.
///
/// Every widget test in this package goes through here, so the wiring under
/// test is the wiring that ships -- a hand-rolled MaterialApp per test would
/// pass while the real shell was broken.
Future<AppDatabase> pumpApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
  String? initialLocation,
  Locale locale = const Locale('en'),
  void Function(ProviderContainer container)? onContainer,
}) async {
  final db = AppDatabase.openInMemory();
  addTearDown(db.close);

  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  onContainer?.call(container);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: NimbuStatsApp(
        initialLocation: initialLocation,
        overrideLocale: locale,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}
```

This requires one more addition to `nimbus_data`'s `AppDatabase`, beside
`openAtPath` (same commit, same reasoning):

```dart
  /// An in-memory database. Used by tests in every package; kept here rather
  /// than in a test helper so `app` still needs no `drift` dependency to make
  /// one.
  factory AppDatabase.openInMemory() => AppDatabase(NativeDatabase.memory());
```

- [ ] **Step 9: Run the test and verify it fails**

```bash
cd app && flutter test test/bootstrap/app_shell_test.dart
```

Expected: undefined `appDatabaseProvider`, `NimbuStatsApp` named parameters,
`AppDatabase.openInMemory`.

- [ ] **Step 10: Implement the database provider**

Create `app/lib/bootstrap/database_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

/// The application database.
///
/// Deliberately unimplemented at declaration: `main` overrides it with a
/// database opened at the real path, and every test overrides it with an
/// in-memory one. A default here would be a hardcoded fallback that masks a
/// bootstrap failure -- the app would run, write to the wrong place, and look
/// fine until the user's data was not there.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw StateError(
    'appDatabaseProvider was read without being overridden. '
    'main() overrides it after opening the database; tests override it with '
    'AppDatabase.openInMemory().',
  );
});
```

- [ ] **Step 11: Implement the router**

Create `app/lib/bootstrap/app_router.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Composes the per-feature route lists into the app's router.
///
/// There is deliberately no central switch statement: each feature owns a
/// `routes.dart` exporting its own `List<RouteBase>`, and adding a feature adds
/// one line here. Two phases adding different features therefore append
/// different lines and merge cleanly (CONVENTIONS.md 3).
final appRouterProvider =
    Provider.family<GoRouter, String?>((ref, initialLocation) {
  return GoRouter(
    initialLocation: initialLocation ?? '/',
    routes: <RouteBase>[
      // Feature route lists are appended here, one per line, as each feature
      // lands: transactionRoutes (Task 12), categoryRoutes (Task 6),
      // tagRoutes (Task 8), paymentMethodRoutes (Task 9),
      // settingsRoutes and onboardingRoutes (Task 15).
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const _ShellPlaceholder(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      key: const Key('router-error'),
      body: Center(child: Text(state.uri.toString())),
    ),
  );
});

/// Replaced by the transaction list in Task 13. It exists so the shell has
/// something to render before any feature does.
class _ShellPlaceholder extends StatelessWidget {
  const _ShellPlaceholder();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('NimbuStats')));
}
```

Note on the error screen: the `Key('router-error')` is on the `Scaffold`, and
the body shows the unresolved location. Task 15 replaces the bare URI with a
localized message — it is left raw here only because no ARB key exists yet, and
that is called out rather than left to be discovered.

- [ ] **Step 12: Implement the app widget**

Create `app/lib/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import 'bootstrap/app_router.dart';
import 'l10n/app_localizations.dart';

class NimbuStatsApp extends ConsumerWidget {
  const NimbuStatsApp({
    super.key,
    this.initialLocation,
    this.overrideLocale,
  });

  /// Set by tests and by the Phase 6 widget deep link. Null means "start at
  /// the router's default".
  final String? initialLocation;

  /// Set by tests only. The running app takes its locale from settings
  /// (wired in Task 15).
  final Locale? overrideLocale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider(initialLocation));
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: NimbusTheme.light(),
      darkTheme: NimbusTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Persian by default so right-to-left is the path exercised every day,
      // rather than a mode that breaks the first time someone switches to it.
      locale: overrideLocale ?? const Locale('fa'),
      routerConfig: router,
    );
  }
}
```

- [ ] **Step 13: Rewrite `main.dart` as bootstrap only**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'bootstrap/database_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The app layer owns the path because it is the only layer allowed to know
  // about the platform's directory conventions; nimbus_data receives it.
  final dir = await getApplicationDocumentsDirectory();
  final db = AppDatabase.openAtPath(p.join(dir.path, 'nimbustats.sqlite'));

  runApp(ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const NimbuStatsApp(),
  ));
}
```

If `package:path` is not already a transitive dependency exposed to `app`, add
it with `dart pub add path` in the same VPN window as Step 3 rather than
building the path with string concatenation.

- [ ] **Step 14: Run the shell test and verify it passes**

```bash
cd app && flutter test test/bootstrap/app_shell_test.dart
```

Expected: all four tests green. The fourth is the environmental one — if
`sqlite3` cannot be loaded under `flutter test`, it fails here with a library
load error rather than surfacing three tasks later inside a screen test.

- [ ] **Step 15: Run the broader suite**

```bash
cd .. && dart analyze --fatal-infos
dart test test/architecture_test.dart
cd packages/nimbus_domain && dart test
cd ../nimbus_data && dart test
cd ../../app && flutter test
```

- [ ] **Step 16: Commit**

```bash
git tag pre-app-shell HEAD
git add app packages/nimbus_data test/architecture_test.dart pubspec.lock
git commit -m "feat: app shell with router, provider scope, and injected database

Adds go_router <version> and the Android platform folder, neither of which
existed. The interesting part is what did not change: app still does not depend
on drift or sqlite3. AppDatabase.openAtPath and .openInMemory keep database
construction behind nimbus_data, so the architecture test can assert the
boundary rather than trusting that no screen ever imports drift.

appDatabaseProvider throws when unoverridden on purpose. A default in-memory
database would let a bootstrap failure run to completion and lose the user's
data quietly, which is the worst available outcome.

Touches packages/nimbus_data/lib/src/database/app_database.dart, a Phase 0 file,
additively: two factories, no signature changes."
```

---

## Task 3: Settings repository and typed `AppSettings`

Currency, calendar, locale, first day of week, and theme decide how every other
screen renders, so they are needed before any screen is built. The settings
*screen* is Task 15; this task is the typed layer under it.

**Files:**
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` **(P0)** —
  add `SettingsDao.watchAll` and `SettingsDao.getAll`
- Create: `app/lib/features/settings/data/settings_keys.dart`
- Create: `app/lib/features/settings/data/app_settings.dart`
- Create: `app/lib/features/settings/data/settings_repository.dart`
- Create: `app/lib/features/settings/application/settings_providers.dart`
- Test: `app/test/features/settings/settings_repository_test.dart`

**Interfaces:**
- Consumes: `SettingsDao` (Phase 0), `Currency`, `CalendarKind`, `AppCalendar`,
  `MoneyFormatter` (Phase 0 domain), `appDatabaseProvider` (Task 2).
- Produces:
  - `SettingsKeys.{currencyCode, calendarKind, localeCode, firstDayOfWeek,
    themeMode, onboardingCompleted, foundingUser, installedAt, seedVersion}`
    (`String` constants).
  - `AppSettings` with fields `currency` (`Currency`), `calendarKind`
    (`CalendarKind`), `locale` (`Locale`), `firstDayOfWeek` (`int`, ISO 1–7),
    `themeMode` (`ThemeMode`), `onboardingCompleted` (`bool`); getters
    `calendar` (`AppCalendar`), `persianDigits` (`bool`), `moneyFormatter`
    (`MoneyFormatter`); `AppSettings.defaults`; `copyWith`.
  - `SettingsFormatException` — thrown when a *stored* value cannot be parsed.
  - `SettingsRepository(SettingsDao)` with `Future<AppSettings> load()`,
    `Stream<AppSettings> watch()`, `Future<void> save(AppSettings)`,
    `Future<void> resetToDefaults()`.
  - `settingsRepositoryProvider`, `settingsProvider`
    (`AsyncNotifierProvider<SettingsNotifier, AppSettings>`), and the derived
    `currencyProvider`, `calendarProvider`, `localeProvider`,
    `themeModeProvider`, `moneyFormatterProvider`.

---

- [ ] **Step 1: Write the failing repository test**

Create `app/test/features/settings/settings_repository_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_keys.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase.openInMemory();
    repo = SettingsRepository(db.settingsDao);
  });

  tearDown(() => db.close());

  test('an empty database yields the documented defaults', () async {
    final settings = await repo.load();
    // First run is a normal state, not an error: absent keys take defaults.
    expect(settings, AppSettings.defaults);
    expect(settings.currency, Currency.toman);
    expect(settings.calendarKind, CalendarKind.jalali);
    expect(settings.locale, const Locale('fa'));
    expect(settings.firstDayOfWeek, DateTime.saturday);
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.onboardingCompleted, isFalse);
  });

  test('every field round-trips through the database', () async {
    const written = AppSettings(
      currency: Currency.usd,
      calendarKind: CalendarKind.gregorian,
      locale: Locale('en'),
      firstDayOfWeek: DateTime.monday,
      themeMode: ThemeMode.dark,
      onboardingCompleted: true,
    );
    await repo.save(written);
    expect(await repo.load(), written);
  });

  test('a stored value that cannot be parsed throws rather than defaulting',
      () async {
    // Absent means "first run". Present-but-invalid means the database is
    // wrong, and silently substituting a default there would hide corruption
    // behind an app that merely renders the wrong calendar.
    await db.settingsDao.put(SettingsKeys.calendarKind, 'martian');
    await expectLater(
      repo.load(),
      throwsA(isA<SettingsFormatException>()
          .having((e) => e.key, 'key', SettingsKeys.calendarKind)
          .having((e) => e.value, 'value', 'martian')),
    );
  });

  test('an unknown currency code throws and names the key', () async {
    await db.settingsDao.put(SettingsKeys.currencyCode, 'XYZ');
    await expectLater(
      repo.load(),
      throwsA(isA<SettingsFormatException>()
          .having((e) => e.key, 'key', SettingsKeys.currencyCode)),
    );
  });

  test('a first day of week outside ISO 1-7 throws', () async {
    await db.settingsDao.put(SettingsKeys.firstDayOfWeek, '9');
    await expectLater(repo.load(), throwsA(isA<SettingsFormatException>()));
  });

  test('resetToDefaults recovers from a corrupt value', () async {
    await db.settingsDao.put(SettingsKeys.themeMode, 'chartreuse');
    await expectLater(repo.load(), throwsA(isA<SettingsFormatException>()));
    await repo.resetToDefaults();
    expect(await repo.load(), AppSettings.defaults);
  });

  test('watch emits the current settings and then every change', () async {
    final seen = <AppSettings>[];
    final sub = repo.watch().listen(seen.add);
    addTearDown(sub.cancel);

    await pumpEventQueue();
    await repo.save(AppSettings.defaults.copyWith(themeMode: ThemeMode.light));
    await pumpEventQueue();

    expect(seen.first, AppSettings.defaults);
    expect(seen.last.themeMode, ThemeMode.light);
  });

  group('derived values', () {
    test('the Jalali setting produces a Jalali calendar', () {
      expect(AppSettings.defaults.calendar, isA<JalaliCalendar>());
      expect(
        AppSettings.defaults.copyWith(calendarKind: CalendarKind.gregorian)
            .calendar,
        isA<GregorianCalendar>(),
      );
    });

    test('Persian digits follow the locale, not the calendar', () {
      // Screen contract 8: a user may read `en` and keep the Jalali calendar.
      const enJalali = AppSettings(
        currency: Currency.toman,
        calendarKind: CalendarKind.jalali,
        locale: Locale('en'),
        firstDayOfWeek: DateTime.saturday,
        themeMode: ThemeMode.system,
        onboardingCompleted: true,
      );
      expect(enJalali.persianDigits, isFalse);
      expect(enJalali.calendar, isA<JalaliCalendar>());
      expect(AppSettings.defaults.persianDigits, isTrue);
    });

    test('the money formatter matches currency and digit style', () {
      final formatter = AppSettings.defaults.moneyFormatter;
      expect(formatter.currency, Currency.toman);
      expect(formatter.format(const Money(1234567)), '۱٬۲۳۴٬۵۶۷');
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

```bash
cd app && flutter test test/features/settings/settings_repository_test.dart
```

Expected: undefined `SettingsRepository`, `AppSettings`, `SettingsKeys`,
`SettingsFormatException`.

- [ ] **Step 3: Add the two DAO reads**

In `packages/nimbus_data/lib/src/database/app_database.dart`, add to
`SettingsDao`:

```dart
  Future<Map<String, String>> getAll() async {
    final rows = await _db.select(_db.settings).get();
    return {for (final row in rows) row.key: row.value};
  }

  /// Emits the whole settings map on every change. Settings are a handful of
  /// rows, so re-reading all of them is cheaper than tracking which key moved.
  Stream<Map<String, String>> watchAll() => _db.select(_db.settings).watch().map(
        (rows) => {for (final row in rows) row.key: row.value},
      );

  Future<void> clear() => _db.delete(_db.settings).go();
```

- [ ] **Step 4: Write the keys and the value type**

`app/lib/features/settings/data/settings_keys.dart`:

```dart
/// The `settings` table's key namespace.
///
/// String literals live here and nowhere else: a typo in a key is otherwise a
/// silent no-op that reads back as "not configured yet".
abstract final class SettingsKeys {
  static const currencyCode = 'currency_code';
  static const calendarKind = 'calendar_kind';
  static const localeCode = 'locale';
  static const firstDayOfWeek = 'first_day_of_week';
  static const themeMode = 'theme_mode';
  static const onboardingCompleted = 'onboarding_completed';
  static const foundingUser = 'founding_user';
  static const installedAt = 'installed_at';

  /// Bumped when the seeded default tree changes, so a future phase can decide
  /// whether to re-seed. Phase 1 writes it and never reads it back.
  static const seedVersion = 'seed_version';
}
```

`app/lib/features/settings/data/app_settings.dart` — the value type. Key
implementation notes, all of which the tests above pin:

- `defaults` is `Currency.toman`, `CalendarKind.jalali`, `Locale('fa')`,
  `DateTime.saturday`, `ThemeMode.system`, `onboardingCompleted: false`. Farsi
  and Jalali are the primary experience, so they are the defaults rather than a
  fallback.
- `firstDayOfWeek` is ISO (`DateTime.monday == 1` … `DateTime.sunday == 7`),
  matching `DateKey.weekday` and both `AppCalendar` implementations. Saturday is
  `DateTime.saturday == 6`.
- `calendar` returns `const JalaliCalendar()` or `const GregorianCalendar()`.
- `persianDigits` is `locale.languageCode == 'fa'`.
- `moneyFormatter` is
  `MoneyFormatter(currency: currency, persianDigits: persianDigits)`.
- `==` and `hashCode` cover all six fields; the round-trip test compares whole
  values.

`app/lib/features/settings/data/settings_repository.dart`:

```dart
/// Raised when a value *present* in the database cannot be parsed.
///
/// Distinct from an absent key, which is the ordinary first-run state and
/// yields a documented default. Substituting a default for an unparseable
/// stored value would turn database corruption into an app that quietly
/// renders the wrong calendar.
final class SettingsFormatException implements Exception {
  const SettingsFormatException(this.key, this.value);

  final String key;
  final String value;

  @override
  String toString() =>
      'SettingsFormatException: setting "$key" holds unparseable value '
      '"$value". Reset settings to defaults to recover.';
}
```

The repository parses the map returned by `getAll()` / `watchAll()`:

```dart
  T _parse<T>(Map<String, String> raw, String key, T fallback,
      T? Function(String) parser) {
    final value = raw[key];
    if (value == null) return fallback;      // absent: first run
    final parsed = parser(value);
    if (parsed == null) throw SettingsFormatException(key, value);
    return parsed;
  }
```

- currency: `Currency.byCode` wrapped so its `ArgumentError` becomes a null and
  therefore a `SettingsFormatException` naming the key.
- calendar: `CalendarKind.values.firstWhereOrNull(...)` by `name`.
- locale: accepted values are exactly `fa` and `en`; anything else throws,
  because a locale the app has no ARB bundle for would silently fall back to
  English.
- firstDayOfWeek: `int.tryParse`, then a range check of 1–7.
- themeMode: by `ThemeMode.values` `name`.
- booleans: `'true'` / `'false'` only.

`save` writes every field through `SettingsDao.put`; `resetToDefaults` calls
`SettingsDao.clear()` — which is why `load()` on an empty table must return
defaults and not throw.

- [ ] **Step 5: Run the test and verify it passes**

```bash
cd app && flutter test test/features/settings/settings_repository_test.dart
```

- [ ] **Step 6: Add the providers**

`app/lib/features/settings/application/settings_providers.dart`:

```dart
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider).settingsDao),
);

/// The single source of truth for how the app renders.
///
/// A stream rather than a one-shot read, so changing the calendar or locale in
/// settings re-renders the app without a restart -- required by screen contract
/// 3.6.
final settingsProvider = StreamProvider<AppSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).watch(),
);

/// Derived views. Screens watch the narrowest one they need so a theme change
/// does not rebuild a list that only cares about the currency.
final currencyProvider = Provider<Currency>(
  (ref) => ref.watch(settingsProvider).valueOrNull?.currency ??
      AppSettings.defaults.currency,
);
```

Note on the `??` above: this is not a fallback masking an error. While the
stream has not produced its first value the app must still render, and the
defaults are the same values a first run would write. Where the *error* matters
— a `SettingsFormatException` — `settingsProvider` is in the `AsyncError` state
and the settings screen (Task 15) shows the error state with a reset action;
the derived providers deliberately keep the app usable in the meantime.

Add `calendarProvider`, `localeProvider`, `themeModeProvider`, and
`moneyFormatterProvider` on the same pattern.

- [ ] **Step 7: Run the broader suite and commit**

```bash
cd .. && dart analyze --fatal-infos && dart test test/architecture_test.dart
cd packages/nimbus_data && dart test
cd ../../app && flutter test
```

```bash
git tag pre-settings-repository HEAD
git add app packages/nimbus_data
git commit -m "feat: typed settings over the key/value settings table

Absent key and unparseable value are deliberately different: the first is first
run and takes a documented default, the second is database corruption and
throws with the offending key named. Collapsing the two -- the obvious
shortcut -- produces an app that renders the wrong calendar and never says why.

Settings arrive as a stream so changing calendar or locale re-renders without a
restart, which screen contract 3.6 requires.

Touches app_database.dart (Phase 0) additively: three read methods on
SettingsDao, no signature changes."
```

---

## Task 4: First-run seeding and the Uncategorized system row

**Correction to the brief, landed in this commit.** `phase-1-expenses.md` says
"The Uncategorized system row. Phase 0 creates it". Phase 0 does not — there is
no seeding code anywhere in the repository, verified by grep. Phase 1 creates
it here, and the brief's trap line is edited in this commit to say so.

**Files:**
- Create: `packages/nimbus_data/lib/src/seed/ids.dart`
- Create: `packages/nimbus_data/lib/src/seed/seed_category.dart`
- Create: `packages/nimbus_data/lib/src/seed/category_seeder.dart`
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` **(P0)** —
  `insertNode` gains optional `sortOrder` and `kind`
- Modify: `packages/nimbus_data/lib/nimbus_data.dart` (barrel)
- Create: `app/lib/features/categories/data/default_category_tree.dart`
- Create: `app/lib/bootstrap/first_run.dart`
- Modify: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_fa.arb`
- Test: `packages/nimbus_data/test/seed/category_seeder_test.dart`
- Test: `app/test/bootstrap/first_run_test.dart`
- Modify: `docs/phases/phase-1-expenses.md` (the trap correction)

**Interfaces:**
- Consumes: `AppDatabase`, `CategoriesDao`, `MaterializedPath`.
- Produces:
  - `Ids.newId()` — UUIDv7 string.
  - `SeedCategoryNode({required String id, required String name,
    String iconKey, int color, String kind, List<SeedCategoryNode> children})`.
  - `SystemCategoryIds.uncategorized` (`'system-uncategorized'`) and
    `SystemCategoryIds.isSystem(String id)`.
  - `CategorySeeder(AppDatabase)` with
    `Future<bool> seedIfEmpty({required List<SeedCategoryNode> roots,
    required String uncategorizedName})`.
  - `defaultCategoryTree(AppLocalizations l10n)` in the app layer.
  - `firstRunProvider` (`FutureProvider<void>`) — seeds and stamps
    `installedAt` / `seedVersion` exactly once.

---

- [ ] **Step 1: Write the failing seeder test**

Create `packages/nimbus_data/test/seed/category_seeder_test.dart`:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';

const _tree = <SeedCategoryNode>[
  SeedCategoryNode(
    id: 'seed-food',
    name: 'Food',
    iconKey: 'restaurant',
    color: 0xFFEF6C00,
    children: [
      SeedCategoryNode(id: 'seed-food-groceries', name: 'Groceries'),
      SeedCategoryNode(id: 'seed-food-dining', name: 'Dining out'),
    ],
  ),
  SeedCategoryNode(id: 'seed-transport', name: 'Transport'),
  SeedCategoryNode(
      id: 'seed-salary', name: 'Salary', kind: 'income'),
];

void main() {
  late AppDatabase db;
  late CategorySeeder seeder;

  setUp(() {
    db = openTestDatabase();
    seeder = CategorySeeder(db);
  });

  tearDown(() => db.close());

  test('seeds the tree and reports that it did', () async {
    final seeded =
        await seeder.seedIfEmpty(roots: _tree, uncategorizedName: 'Uncategorized');
    expect(seeded, isTrue);

    final all = await db.categoriesDao.allLive();
    // three roots, two children, plus the system row
    expect(all.length, 6);
  });

  test('creates the system Uncategorized row at the root', () async {
    await seeder.seedIfEmpty(roots: _tree, uncategorizedName: 'Uncategorized');

    final row = await db.categoriesDao.byId(SystemCategoryIds.uncategorized);
    expect(row, isNotNull);
    expect(row!.name, 'Uncategorized');
    expect(row.parentId, isNull);
    expect(row.path, '/${SystemCategoryIds.uncategorized}/');
    expect(row.depth, 0);
    expect(SystemCategoryIds.isSystem(row.id), isTrue);
  });

  test('builds correct materialized paths and depths for children', () async {
    await seeder.seedIfEmpty(roots: _tree, uncategorizedName: 'Uncategorized');

    final groceries = await db.categoriesDao.byId('seed-food-groceries');
    expect(groceries!.path, '/seed-food/seed-food-groceries/');
    expect(groceries.depth, 1);
    expect(groceries.parentId, 'seed-food');

    final food = await db.categoriesDao.byId('seed-food');
    expect(food!.path, '/seed-food/');
    expect(food.depth, 0);
  });

  test('preserves the declared order as sortOrder', () async {
    await seeder.seedIfEmpty(roots: _tree, uncategorizedName: 'Uncategorized');
    final food = await db.categoriesDao.byId('seed-food');
    final transport = await db.categoriesDao.byId('seed-transport');
    expect(food!.sortOrder, lessThan(transport!.sortOrder));

    final groceries = await db.categoriesDao.byId('seed-food-groceries');
    final dining = await db.categoriesDao.byId('seed-food-dining');
    expect(groceries!.sortOrder, lessThan(dining!.sortOrder));
  });

  test('carries the declared kind', () async {
    await seeder.seedIfEmpty(roots: _tree, uncategorizedName: 'Uncategorized');
    expect((await db.categoriesDao.byId('seed-salary'))!.kind, 'income');
    expect((await db.categoriesDao.byId('seed-food'))!.kind, 'expense');
  });

  test('is idempotent: a second run changes nothing', () async {
    await seeder.seedIfEmpty(roots: _tree, uncategorizedName: 'Uncategorized');
    final before = await db.categoriesDao.allLive();

    final seededAgain =
        await seeder.seedIfEmpty(roots: _tree, uncategorizedName: 'Different');
    expect(seededAgain, isFalse);

    final after = await db.categoriesDao.allLive();
    expect(after.length, before.length);
    // The name must not be rewritten either: a user who renamed a seeded
    // category would otherwise lose that on the next launch.
    expect((await db.categoriesDao.byId(SystemCategoryIds.uncategorized))!.name,
        'Uncategorized');
  });

  test('a soft-deleted tree still counts as seeded', () async {
    await seeder.seedIfEmpty(roots: _tree, uncategorizedName: 'Uncategorized');
    await db.categoriesDao.softDeleteSubtree('seed-transport');

    final seededAgain =
        await seeder.seedIfEmpty(roots: _tree, uncategorizedName: 'Uncategorized');
    expect(seededAgain, isFalse,
        reason: 'a user who deleted a default category must not get it back '
            'on the next launch');
  });

  test('a failure part-way through leaves no rows behind', () async {
    // Two nodes sharing an id violates the primary key on the second insert.
    const broken = <SeedCategoryNode>[
      SeedCategoryNode(id: 'dup', name: 'First'),
      SeedCategoryNode(id: 'dup', name: 'Second'),
    ];
    await expectLater(
      seeder.seedIfEmpty(roots: broken, uncategorizedName: 'Uncategorized'),
      throwsA(anything),
    );
    final all = await db.categoriesDao.allLive();
    expect(all, isEmpty,
        reason: 'seeding is transactional; a half-seeded tree is worse than '
            'none, because the next launch would consider it already seeded');
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

```bash
cd packages/nimbus_data && dart test test/seed/category_seeder_test.dart
```

Expected: undefined `SeedCategoryNode`, `CategorySeeder`, `SystemCategoryIds`,
and also `allLive` / `softDeleteSubtree`, which Task 5 formalises. Add those two
DAO methods here (they are needed by this test) and let Task 5 add the rest.

- [ ] **Step 3: Implement ids and the seed node**

`packages/nimbus_data/lib/src/seed/ids.dart`:

```dart
import 'package:uuid/uuid.dart';

/// Identifier generation for every row the app creates.
///
/// UUIDv7 rather than v4: the leading 48 bits are a millisecond timestamp, so
/// ids sort chronologically. That makes them index-friendly as a primary key
/// and gives keyset pagination a stable tiebreaker within a single day.
abstract final class Ids {
  static const _uuid = Uuid();

  static String newId() => _uuid.v7();
}
```

Verify `uuid` 4.6 exposes `v7()` before relying on it:

```bash
cd packages/nimbus_data && grep -rn "String v7" ~/AppData/Local/Pub/Cache/hosted/pub.dev/uuid-*/lib/uuid.dart
```

If it does not, use `v4()` and record the change in the commit body — keyset
pagination in Task 10 orders by `(local_date_key, id)` and only needs `id` to be
*unique and stable*, not time-ordered, so the fallback is correct but loses the
index locality.

`packages/nimbus_data/lib/src/seed/seed_category.dart`:

```dart
import 'package:meta/meta.dart';

/// A node in the first-run category tree.
///
/// Names arrive already localized: this package has no access to ARB bundles
/// and must not gain one, so the app hands in a fully-resolved tree.
///
/// Ids are declared rather than generated. A stable `seed-food` id means a
/// merchant rule written in Phase 2 keeps pointing at the same category after
/// a reinstall, and makes this seeding idempotent by construction.
@immutable
final class SeedCategoryNode {
  const SeedCategoryNode({
    required this.id,
    required this.name,
    this.iconKey = 'tag',
    this.color = 0xFF9E9E9E,
    this.kind = 'expense',
    this.children = const <SeedCategoryNode>[],
  });

  final String id;
  final String name;
  final String iconKey;
  final int color;
  final String kind;
  final List<SeedCategoryNode> children;
}
```

Note: `meta` is not currently a dependency of `nimbus_data`. Either add it (it
is a pure annotation package and does not cross any boundary) or drop
`@immutable`. Adding it requires the VPN and a line in the commit message.

`packages/nimbus_data/lib/src/seed/category_seeder.dart`:

```dart
import '../database/app_database.dart';

/// Ids the app itself owns, as opposed to ids a user created.
abstract final class SystemCategoryIds {
  /// Every transaction requires a category, so captures awaiting review and
  /// expenses logged before the user picks anything land here. This id is a
  /// fixed string rather than a generated UUID so that it is greppable, stable
  /// across reinstalls, and enforceable without an `is_system` column -- which
  /// would have cost a schema version and the schema lock for one boolean.
  static const uncategorized = 'system-uncategorized';

  static bool isSystem(String id) => id == uncategorized;
}

/// First-run seeding of the default category tree.
final class CategorySeeder {
  const CategorySeeder(this._db);

  final AppDatabase _db;

  /// Seeds [roots] plus the system Uncategorized row, and returns whether it
  /// did any work.
  ///
  /// "Empty" means the `categories` table holds no rows at all, including
  /// soft-deleted ones: a user who deleted every default category has made a
  /// decision, and re-seeding on the next launch would silently undo it.
  ///
  /// The whole thing runs in one transaction. A half-seeded tree is worse than
  /// no tree, because the emptiness check would then consider seeding done.
  Future<bool> seedIfEmpty({
    required List<SeedCategoryNode> roots,
    required String uncategorizedName,
  }) async {
    return _db.transaction(() async {
      final existing = await _db.select(_db.categories).get();
      if (existing.isNotEmpty) return false;

      await _db.categoriesDao.insertNode(
        id: SystemCategoryIds.uncategorized,
        name: uncategorizedName,
        parentId: null,
        iconKey: 'help_outline',
        sortOrder: -1, // sorts above everything the user can reorder
      );

      var order = 0;
      Future<void> insertAll(
          List<SeedCategoryNode> nodes, String? parentId) async {
        for (final node in nodes) {
          await _db.categoriesDao.insertNode(
            id: node.id,
            name: node.name,
            parentId: parentId,
            iconKey: node.iconKey,
            color: node.color,
            kind: node.kind,
            sortOrder: order++,
          );
          await insertAll(node.children, node.id);
        }
      }

      await insertAll(roots, null);
      return true;
    });
  }
}
```

- [ ] **Step 4: Extend `insertNode` additively**

In `CategoriesDao.insertNode` (and `TagsDao.insertNode`, for symmetry), add two
optional named parameters with defaults that preserve current behaviour:

```dart
    int sortOrder = 0,
    String kind = 'expense',
```

and pass them into the companion (`sortOrder: Value(sortOrder)`,
`kind: Value(kind)`). `TagsDao` has no `kind` column, so it takes `sortOrder`
only. Optional parameters with defaults keep every existing call site compiling,
which is what "additive, no signature changes" means in practice.

- [ ] **Step 5: Add `allLive` and `softDeleteSubtree` to `CategoriesDao`**

```dart
  Future<List<Category>> allLive({bool includeArchived = true}) {
    final query = _db.select(_db.categories)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.name),
      ]);
    if (!includeArchived) query.where((t) => t.archived.equals(false));
    return query.get();
  }

  /// Soft-deletes [id] and every descendant, returning exactly the ids it
  /// touched so an undo can restore that set and nothing else.
  ///
  /// Rows already soft-deleted are left out of the returned list: restoring
  /// them would resurrect something the user deleted separately and earlier.
  Future<List<String>> softDeleteSubtree(String id) async {
    final node = await byId(id);
    if (node == null) return const [];
    return _db.transaction(() async {
      final affected = await subtreeQuery(node.path).get();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in affected) {
        await (_db.update(_db.categories)..where((t) => t.id.equals(row.id)))
            .write(CategoriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ));
      }
      return affected.map((r) => r.id).toList();
    });
  }
```

`subtreeQuery` already filters `deletedAt.isNull()`, which is exactly the
"leave already-deleted rows alone" behaviour described above.

- [ ] **Step 6: Run the seeder test and verify it passes**

```bash
cd packages/nimbus_data && dart test test/seed/category_seeder_test.dart
```

- [ ] **Step 7: Write the failing first-run test**

Create `app/test/bootstrap/first_run_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/settings/data/settings_keys.dart';

import '../support/harness.dart';

void main() {
  testWidgets('first launch seeds a localized category tree', (tester) async {
    final db = await pumpApp(tester, seedFirstRun: true);

    final categories = await db.categoriesDao.allLive();
    expect(categories, isNotEmpty);
    expect(
      categories.any((c) => c.id == SystemCategoryIds.uncategorized),
      isTrue,
    );
    // English harness locale, so the seeded names are English.
    expect(categories.map((c) => c.name), contains('Food & drink'));
  });

  testWidgets('the Persian tree is seeded in Persian', (tester) async {
    final db =
        await pumpApp(tester, seedFirstRun: true, locale: const Locale('fa'));
    final categories = await db.categoriesDao.allLive();
    expect(categories.map((c) => c.name), contains('خوراک و نوشیدنی'));
  });

  testWidgets('a second launch does not re-seed', (tester) async {
    final db = await pumpApp(tester, seedFirstRun: true);
    final first = (await db.categoriesDao.allLive()).length;

    await db.categoriesDao.rename(SystemCategoryIds.uncategorized, 'Renamed');
    await pumpApp(tester, seedFirstRun: true, database: db);

    expect((await db.categoriesDao.allLive()).length, first);
    expect((await db.categoriesDao.byId(SystemCategoryIds.uncategorized))!.name,
        'Renamed');
  });

  testWidgets('first run stamps installedAt and the seed version',
      (tester) async {
    final db = await pumpApp(tester, seedFirstRun: true);
    expect(await db.settingsDao.get(SettingsKeys.installedAt), isNotNull);
    expect(await db.settingsDao.get(SettingsKeys.seedVersion), '1');
  });
}
```

This adds two parameters to the harness — `seedFirstRun` (default `false`, so
existing tests are unaffected) and `database` (to reuse one across two pumps).
Extend `app/test/support/harness.dart` accordingly.

- [ ] **Step 8: Implement the localized tree and the first-run provider**

`app/lib/features/categories/data/default_category_tree.dart` returns the tree
below. Ids are stable strings; names come from `AppLocalizations`.

| id | en | fa | icon | kind |
|---|---|---|---|---|
| `seed-food` | Food & drink | خوراک و نوشیدنی | `restaurant` | expense |
| `seed-food-groceries` | Groceries | خواربار | `shopping_basket` | expense |
| `seed-food-dining` | Dining out | رستوران | `restaurant_menu` | expense |
| `seed-food-coffee` | Coffee | کافه | `local_cafe` | expense |
| `seed-transport` | Transport | حمل و نقل | `directions_bus` | expense |
| `seed-transport-fuel` | Fuel | سوخت | `local_gas_station` | expense |
| `seed-transport-taxi` | Taxi | تاکسی | `local_taxi` | expense |
| `seed-transport-public` | Public transport | حمل و نقل عمومی | `train` | expense |
| `seed-home` | Home | خانه | `home` | expense |
| `seed-home-rent` | Rent | اجاره | `key` | expense |
| `seed-home-utilities` | Utilities | قبض‌ها | `bolt` | expense |
| `seed-home-internet` | Internet & phone | اینترنت و تلفن | `wifi` | expense |
| `seed-health` | Health | سلامت | `favorite` | expense |
| `seed-health-pharmacy` | Pharmacy | داروخانه | `medication` | expense |
| `seed-health-doctor` | Doctor | پزشک | `stethoscope` | expense |
| `seed-shopping` | Shopping | خرید | `shopping_bag` | expense |
| `seed-shopping-clothing` | Clothing | پوشاک | `checkroom` | expense |
| `seed-shopping-electronics` | Electronics | لوازم الکترونیکی | `devices` | expense |
| `seed-entertainment` | Entertainment | سرگرمی | `movie` | expense |
| `seed-education` | Education | آموزش | `school` | expense |
| `seed-gifts` | Gifts & charity | هدیه و کمک | `card_giftcard` | expense |
| `seed-other` | Other | سایر | `more_horiz` | expense |
| `seed-salary` | Salary | حقوق | `payments` | income |
| `seed-freelance` | Freelance | آزاد | `work` | income |
| `seed-other-income` | Other income | سایر درآمدها | `savings` | income |

ARB keys are the id with `seedCategory` prefix and camel case:
`seedCategoryFood`, `seedCategoryFoodGroceries`, …, `seedCategoryOtherIncome`.
Insert each in alphabetical position in both ARB files.

`app/lib/bootstrap/first_run.dart`:

```dart
/// Runs exactly once per install, before the first screen needs a category.
///
/// Kept out of `main` so tests can run it deterministically, and expressed as a
/// FutureProvider so the onboarding screen can show its seeding state
/// (screen contract 3.1) rather than the app blocking on a splash.
final firstRunProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final l10n = ref.watch(appLocalizationsProvider);
  final seeded = await CategorySeeder(db).seedIfEmpty(
    roots: defaultCategoryTree(l10n),
    uncategorizedName: l10n.uncategorized,
  );
  if (!seeded) return;
  final settings = db.settingsDao;
  await settings.put(
      SettingsKeys.installedAt, DateTime.now().toUtc().millisecondsSinceEpoch.toString());
  await settings.put(SettingsKeys.seedVersion, '1');
  await settings.put(SettingsKeys.foundingUser, 'true');
});
```

`appLocalizationsProvider` is a `Provider<AppLocalizations>` overridden at the
top of the widget tree from `AppLocalizations.of(context)`; it exists so
`firstRunProvider` can localize without a `BuildContext`. Declare it in
`app/lib/bootstrap/localization_provider.dart` throwing when unoverridden, on
the same reasoning as `appDatabaseProvider`.

- [ ] **Step 9: Run the first-run test, then the broader suite**

```bash
cd app && flutter test test/bootstrap/first_run_test.dart
cd .. && dart analyze --fatal-infos && dart test test/architecture_test.dart
cd packages/nimbus_data && dart test
cd ../../app && flutter test
```

- [ ] **Step 10: Correct the brief, then commit**

In `docs/phases/phase-1-expenses.md`, replace the trap line

> **The "Uncategorized" system row.** Phase 0 creates it; Phase 1 must make it
> undeletable and unrenameable

with

> **The "Uncategorized" system row.** Phase 1 creates it (Phase 0 shipped the
> `categories` table but no seeding), and must make it undeletable and
> unrenameable

```bash
git tag pre-first-run-seeding HEAD
git add packages/nimbus_data app docs/phases/phase-1-expenses.md
git commit -m "feat: first-run seeding with a localized default category tree

Zero-config first run is a stated requirement: nobody should build a taxonomy
before logging their first expense. Seeding is transactional and keyed on the
table being completely empty -- including soft-deleted rows -- so a user who
deletes the defaults does not get them back on the next launch.

Seeded ids are fixed strings, not UUIDs, so a Phase 2 merchant rule keeps
pointing at the same category across a reinstall.

The Uncategorized row uses the reserved id system-uncategorized rather than an
is_system column, which would have consumed schema v2 and the schema lock for
one boolean. The brief claimed Phase 0 created this row; it did not, and the
brief is corrected in this commit.

Touches app_database.dart (Phase 0) additively: optional sortOrder/kind on
insertNode, plus allLive and softDeleteSubtree."
```

---

## Task 5: Category DAO extensions and `CategoryRepository`

The tree operations the manager screen needs, tested without a widget tree.
Phase 0 shipped `insertNode`, `move`, `subtreeOf`, and the recursive-CTE oracle;
this task adds rename, appearance, archive, soft delete with undo, reorder, and
the system-row guards.

**Files:**
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` **(P0)**
- Create: `app/lib/features/categories/data/category_repository.dart`
- Create: `app/lib/features/categories/data/category_tree.dart`
- Create: `app/lib/features/categories/application/category_providers.dart`
- Test: `packages/nimbus_data/test/categories_dao_test.dart`
- Test: `app/test/features/categories/category_repository_test.dart`

**Interfaces:**
- Consumes: `CategoriesDao`, `MaterializedPath`, `SystemCategoryIds` (Task 4),
  `Ids.newId()` (Task 4), `appDatabaseProvider` (Task 2).
- Produces:
  - `CategoriesDao`: `watchAll({bool includeArchived})`,
    `rename(String id, String name)`,
    `updateAppearance(String id, {String? iconKey, int? color})`,
    `setArchivedSubtree(String id, bool archived)` returning `List<String>`,
    `restoreAll(List<String> ids)`,
    `reorderSiblings(String? parentId, List<String> orderedIds)`,
    `childCounts()` returning `Map<String, int>`.
  - `SystemCategoryError` — thrown on any attempt to rename, move, archive, or
    delete the Uncategorized row.
  - `CategoryRepository` with `watchTree()`, `create(...)`, `rename`,
    `updateAppearance`, `move`, `archive`, `unarchive`, `delete`, `restore`,
    `reorder`.
  - `CategoryNode({Category category, List<CategoryNode> children, int depth})`
    and `CategoryTree.build(List<Category>)`.
  - `categoryRepositoryProvider`, `categoryTreeProvider`
    (`StreamProvider<List<CategoryNode>>`).

---

- [ ] **Step 1: Write the failing DAO test**

Create `packages/nimbus_data/test/categories_dao_test.dart`. The cases, each of
which must be written as a real assertion, not a smoke test:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

void main() {
  late AppDatabase db;
  late CategoriesDao dao;

  setUp(() async {
    db = openTestDatabase();
    dao = db.categoriesDao;
    // /food/ -> /food/dining/ -> /food/dining/fast/ ; /transport/
    await dao.insertNode(id: 'food', name: 'Food', parentId: null, sortOrder: 0);
    await dao.insertNode(
        id: 'dining', name: 'Dining', parentId: 'food', sortOrder: 0);
    await dao.insertNode(
        id: 'fast', name: 'Fast food', parentId: 'dining', sortOrder: 0);
    await dao.insertNode(
        id: 'transport', name: 'Transport', parentId: null, sortOrder: 1);
  });

  tearDown(() => db.close());

  test('rename changes the name and bumps updatedAt', () async {
    final before = (await dao.byId('food'))!;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await dao.rename('food', 'Food & drink');
    final after = (await dao.byId('food'))!;
    expect(after.name, 'Food & drink');
    expect(after.updatedAt, greaterThan(before.updatedAt));
    // Renaming must not disturb the tree: paths are built from ids, not names.
    expect(after.path, before.path);
  });

  test('updateAppearance changes only what it is given', () async {
    await dao.updateAppearance('food', iconKey: 'restaurant');
    var row = (await dao.byId('food'))!;
    expect(row.iconKey, 'restaurant');
    final colorBefore = row.color;

    await dao.updateAppearance('food', color: 0xFFEF6C00);
    row = (await dao.byId('food'))!;
    expect(row.color, 0xFFEF6C00);
    expect(row.iconKey, 'restaurant');
    expect(colorBefore, isNot(0xFFEF6C00));
  });

  test('archiving a node archives its whole subtree', () async {
    // A picker that hides Food but still offers Dining is incoherent.
    final affected = await dao.setArchivedSubtree('food', true);
    expect(affected, containsAll(<String>['food', 'dining', 'fast']));
    expect(affected, isNot(contains('transport')));

    for (final id in ['food', 'dining', 'fast']) {
      expect((await dao.byId(id))!.archived, isTrue);
    }
    expect((await dao.byId('transport'))!.archived, isFalse);
  });

  test('archived categories still resolve for historical transactions',
      () async {
    await dao.setArchivedSubtree('food', true);
    // byId is the lookup a transaction row uses; archiving must not hide it,
    // or every old chart loses its labels.
    expect(await dao.byId('food'), isNotNull);
    expect(await dao.allLive(includeArchived: true), hasLength(4));
    expect(await dao.allLive(includeArchived: false), hasLength(1));
  });

  test('soft delete removes the subtree from live queries and undo restores it',
      () async {
    final deleted = await dao.softDeleteSubtree('food');
    expect(deleted, containsAll(<String>['food', 'dining', 'fast']));
    expect(await dao.allLive(), hasLength(1));

    await dao.restoreAll(deleted);
    expect(await dao.allLive(), hasLength(4));
    expect((await dao.byId('fast'))!.deletedAt, isNull);
  });

  test('undo restores exactly the set that was deleted', () async {
    // 'fast' was deleted separately and earlier; undoing the deletion of
    // 'food' must not resurrect it.
    await dao.softDeleteSubtree('fast');
    final deleted = await dao.softDeleteSubtree('food');
    expect(deleted, isNot(contains('fast')));

    await dao.restoreAll(deleted);
    expect((await dao.byId('fast'))!.deletedAt, isNotNull);
    expect((await dao.byId('dining'))!.deletedAt, isNull);
  });

  test('reorderSiblings writes a dense ascending order', () async {
    await dao.reorderSiblings(null, ['transport', 'food']);
    expect((await dao.byId('transport'))!.sortOrder, 0);
    expect((await dao.byId('food'))!.sortOrder, 1);
  });

  test('childCounts counts live children per parent', () async {
    final counts = await dao.childCounts();
    expect(counts['food'], 1);
    expect(counts['dining'], 1);
    expect(counts['transport'], isNull);

    await dao.softDeleteSubtree('fast');
    expect((await dao.childCounts())['dining'], isNull);
  });

  test('watchAll emits on every write', () async {
    final seen = <int>[];
    final sub = dao.watchAll().listen((rows) => seen.add(rows.length));
    addTearDown(sub.cancel);

    await pumpEventQueue();
    await dao.insertNode(id: 'health', name: 'Health', parentId: null);
    await pumpEventQueue();

    expect(seen.first, 4);
    expect(seen.last, 5);
  });

  test('moving a subtree rewrites descendant paths', () async {
    // Phase 0 built and tested this; re-asserted here because Task 6 drives it
    // through the UI and a regression would be attributed to the screen.
    await dao.move('dining', 'transport');
    expect((await dao.byId('dining'))!.path, '/transport/dining/');
    expect((await dao.byId('fast'))!.path, '/transport/dining/fast/');
    expect((await dao.byId('fast'))!.depth, 2);
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

```bash
cd packages/nimbus_data && dart test test/categories_dao_test.dart
```

Expected: undefined `rename`, `updateAppearance`, `setArchivedSubtree`,
`restoreAll`, `reorderSiblings`, `childCounts`, `watchAll`.

- [ ] **Step 3: Implement the DAO methods**

Add to `CategoriesDao`. Every one of them stamps `updatedAt`, because a row
that changed without its timestamp moving is invisible to the sync-ready
baseline the schema exists to support.

```dart
  Stream<List<Category>> watchAll({bool includeArchived = true}) {
    final query = _db.select(_db.categories)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.name),
      ]);
    if (!includeArchived) query.where((t) => t.archived.equals(false));
    return query.watch();
  }

  Future<void> rename(String id, String name) =>
      (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
        CategoriesCompanion(
          name: Value(name),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<void> updateAppearance(String id, {String? iconKey, int? color}) =>
      (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
        CategoriesCompanion(
          iconKey: iconKey == null ? const Value.absent() : Value(iconKey),
          color: color == null ? const Value.absent() : Value(color),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  /// Archives or unarchives [id] and every live descendant, returning the ids
  /// it touched so the caller can undo exactly that set.
  Future<List<String>> setArchivedSubtree(String id, bool archived) async {
    final node = await byId(id);
    if (node == null) return const [];
    return _db.transaction(() async {
      final affected = await subtreeQuery(node.path).get();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final row in affected) {
        await (_db.update(_db.categories)..where((t) => t.id.equals(row.id)))
            .write(CategoriesCompanion(
          archived: Value(archived),
          updatedAt: Value(now),
        ));
      }
      return affected.map((r) => r.id).toList();
    });
  }

  Future<void> restoreAll(List<String> ids) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await (_db.update(_db.categories)..where((t) => t.id.isIn(ids))).write(
        CategoriesCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// Writes a dense 0..n-1 order over [orderedIds].
  ///
  /// Dense rather than sparse (10, 20, 30) on purpose: a category sibling list
  /// is short, reordering is rare, and a dense sequence has no renumbering
  /// edge case to get wrong later.
  Future<void> reorderSiblings(String? parentId, List<String> orderedIds) =>
      _db.transaction(() async {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (var i = 0; i < orderedIds.length; i++) {
          await (_db.update(_db.categories)
                ..where((t) => t.id.equals(orderedIds[i])))
              .write(CategoriesCompanion(
            sortOrder: Value(i),
            updatedAt: Value(now),
          ));
        }
      });

  /// Live child count per parent id. One grouped query rather than N counts,
  /// because the manager screen needs every number at once.
  Future<Map<String, int>> childCounts() async {
    final parent = _db.categories.parentId;
    final count = _db.categories.id.count();
    final query = _db.selectOnly(_db.categories)
      ..addColumns([parent, count])
      ..where(_db.categories.deletedAt.isNull() & parent.isNotNull())
      ..groupBy([parent]);
    final rows = await query.get();
    return {
      for (final row in rows) row.read(parent)!: row.read(count)!,
    };
  }
```

- [ ] **Step 4: Run the DAO test and verify it passes**

```bash
cd packages/nimbus_data && dart test test/categories_dao_test.dart
```

- [ ] **Step 5: Write the failing repository test**

Create `app/test/features/categories/category_repository_test.dart`. The
repository is where the system-row rules live, so that is what the test is
about:

```dart
void main() {
  late AppDatabase db;
  late CategoryRepository repo;

  setUp(() async {
    db = AppDatabase.openInMemory();
    repo = CategoryRepository(db.categoriesDao);
    await CategorySeeder(db).seedIfEmpty(
      roots: const [
        SeedCategoryNode(id: 'food', name: 'Food', children: [
          SeedCategoryNode(id: 'dining', name: 'Dining'),
        ]),
      ],
      uncategorizedName: 'Uncategorized',
    );
  });

  tearDown(() => db.close());

  group('the Uncategorized system row', () {
    // Every chart depends on category_id being non-null, so this row has to
    // survive anything the user does in the manager.
    test('cannot be renamed', () {
      expect(
        () => repo.rename(SystemCategoryIds.uncategorized, 'Misc'),
        throwsA(isA<SystemCategoryError>()),
      );
    });

    test('cannot be deleted', () {
      expect(() => repo.delete(SystemCategoryIds.uncategorized),
          throwsA(isA<SystemCategoryError>()));
    });

    test('cannot be archived', () {
      expect(() => repo.archive(SystemCategoryIds.uncategorized),
          throwsA(isA<SystemCategoryError>()));
    });

    test('cannot be moved under another category', () {
      expect(() => repo.move(SystemCategoryIds.uncategorized, 'food'),
          throwsA(isA<SystemCategoryError>()));
    });

    test('cannot become a parent, so it never grows a subtree', () {
      expect(() => repo.move('food', SystemCategoryIds.uncategorized),
          throwsA(isA<SystemCategoryError>()));
    });

    test('is excluded from the picker but present in the manager', () async {
      final pickable = await repo.pickableCategories();
      expect(pickable.map((c) => c.id),
          isNot(contains(SystemCategoryIds.uncategorized)));

      final tree = await repo.watchTree().first;
      expect(tree.map((n) => n.category.id),
          contains(SystemCategoryIds.uncategorized));
    });
  });

  test('create returns a usable id and places the node in the tree', () async {
    final id = await repo.create(name: 'Coffee', parentId: 'food');
    final row = await db.categoriesDao.byId(id);
    expect(row!.name, 'Coffee');
    expect(row.path, '/food/$id/');
    expect(row.depth, 1);
  });

  test('a move under its own descendant is rejected before it is attempted',
      () {
    // Screen contract 3.4: rejecting the drop after the fact via an error toast
    // is explicitly not acceptable, so the check is a pure predicate the UI can
    // call while the drag is still in flight.
    expect(repo.canMove(id: 'food', newParentId: 'dining'), isFalse);
    expect(repo.canMove(id: 'dining', newParentId: null), isTrue);
    expect(repo.canMove(id: 'food', newParentId: 'food'), isFalse);
  });

  test('delete then restore round-trips the whole subtree', () async {
    final deleted = await repo.delete('food');
    expect(deleted, containsAll(<String>['food', 'dining']));
    expect((await repo.watchTree().first).map((n) => n.category.id),
        isNot(contains('food')));

    await repo.restore(deleted);
    expect((await repo.watchTree().first).map((n) => n.category.id),
        contains('food'));
  });

  test('watchTree nests children under parents and caps reported depth',
      () async {
    final roots = await repo.watchTree().first;
    final food = roots.firstWhere((n) => n.category.id == 'food');
    expect(food.children.map((n) => n.category.id), ['dining']);
    expect(food.depth, 0);
    expect(food.children.single.depth, 1);
  });
}
```

`canMove` is a synchronous predicate over the already-loaded tree, which is what
lets the screen refuse a drop rather than undo one. It answers false when
`newParentId == id`, when `newParentId` is a descendant of `id`, and when either
side is the system row.

- [ ] **Step 6: Implement the repository and the tree builder**

`SystemCategoryError` is an `Error`, not an `Exception`: reaching it means the
UI offered an action it should have disabled, which is a programming mistake,
and `only_throw_errors` is on in the analyzer options.

`CategoryTree.build` groups the flat list by `parentId`, sorts each sibling
group by `(sortOrder, name)`, and walks from the roots. Reported `depth` is the
real depth; the *visual* indent cap from `NimbusTokens.maxTreeIndentDepth` is
applied in the widget, not here, so the data stays truthful.

- [ ] **Step 7: Run the tests, then the broader suite**

```bash
cd app && flutter test test/features/categories/category_repository_test.dart
cd .. && dart analyze --fatal-infos && dart test test/architecture_test.dart
cd packages/nimbus_data && dart test
cd ../../app && flutter test
```

- [ ] **Step 8: Commit**

```bash
git tag pre-category-repository HEAD
git add packages/nimbus_data app
git commit -m "feat: category tree operations and the system-row guards

Archive and soft delete both apply to the whole subtree, transactionally, and
both return the ids they touched. Returning the set is what makes undo exact:
restoring a subtree must not resurrect a child the user had deleted separately
and earlier, and there is a test for precisely that.

canMove is a synchronous predicate rather than a failed write, because the
screen contract forbids surfacing an invalid drop as an error after the fact.

Touches app_database.dart (Phase 0) additively: seven read/write methods on
CategoriesDao, no signature changes."
```

---

## Task 6: Category manager screen

**Files:**
- Create: `app/lib/features/categories/presentation/category_manager_screen.dart`
- Create: `app/lib/features/categories/presentation/widgets/category_row.dart`
- Create: `app/lib/features/categories/presentation/widgets/category_editor_sheet.dart`
- Create: `app/lib/features/categories/presentation/widgets/move_target_sheet.dart`
- Create: `app/lib/features/categories/presentation/widgets/icon_picker.dart`
- Create: `app/lib/features/categories/routes.dart`
- Modify: `app/lib/bootstrap/app_router.dart` (one line)
- Modify: both ARB files
- Test: `app/test/features/categories/category_manager_screen_test.dart`

**Interfaces:**
- Consumes: `categoryTreeProvider`, `categoryRepositoryProvider` (Task 5),
  `NimbusEmptyState` / `NimbusErrorState` / `NimbusLoadingList` /
  `nimbusUndoSnackBar` (Task 1).
- Produces: `categoryRoutes` (`List<RouteBase>`), `categoryManagerRoute`
  (`'/categories'`), `CategoryManagerScreen`.

**States, all four required:**

| State | Trigger | Rendering |
|---|---|---|
| `loading` | `categoryTreeProvider` is `AsyncLoading` | `NimbusLoadingList(rows: 6)` |
| `empty` | tree is empty | `NimbusEmptyState` with the "create your first category" action. Unreachable in practice because seeding runs first, but required — a user can delete everything. |
| `error` | provider is `AsyncError` | `NimbusErrorState` with retry that invalidates the provider |
| `populated` | otherwise | the tree |

- [ ] **Step 1: Write the failing screen test**

Create `app/test/features/categories/category_manager_screen_test.dart`
covering, as separate `testWidgets` cases:

1. **loading** — pump with the provider overridden to a stream that has not
   emitted; expect `find.byType(NimbusLoadingList)` and
   `find.byType(CircularProgressIndicator)` to be `findsNothing`.
2. **empty** — override with `Stream.value(const [])`; expect the empty title
   and that tapping its action opens the editor sheet.
3. **error** — override with `Stream.error(Exception('boom'))`; expect
   `NimbusErrorState`, expect `find.text('Exception: boom')` to be
   `findsNothing`, and expect a retry control.
4. **populated** — seeded tree; expect a row per node and the child count on
   `Food`.
5. **indent is capped at six levels** — build a six-deep chain; assert the
   deepest row's leading indent equals
   `NimbusTokens.indentPerLevel * NimbusTokens.maxTreeIndentDepth` and that the
   row still lays out without overflow in a 320-logical-pixel-wide surface
   (`tester.view.physicalSize`), in RTL.
6. **rename** — tap a row's overflow, tap rename, type, save, expect the DAO
   value changed and the row re-rendered.
7. **move rejects an invalid target before the drop** — open "Move to…" on
   `Food`; assert `Dining` is rendered disabled (`find.byWidgetPredicate` on the
   `ListTile` with `enabled: false`), and that tapping it does nothing.
8. **archive** — archive `Food`; expect its subtree to disappear from the
   pickable list but the rows to remain in the manager with an archived badge.
9. **delete shows undo and no confirmation dialog** — delete `Transport`;
   expect a `SnackBar` with the undo label, expect `find.byType(Dialog)` and
   `find.byType(AlertDialog)` to be `findsNothing`, tap undo, expect the row
   back.
10. **the system row is not deletable from the UI** — expect the Uncategorized
    row's overflow menu to contain no delete or rename entry.
11. **accessibility** — every interactive element has a semantics label:
    `expect(tester.getSemantics(find.byKey(const Key('category-row-food'))),
    matchesSemantics(label: ..., isButton: true))` for a representative row.

- [ ] **Step 2: Run and verify failure** — undefined `CategoryManagerScreen`.

- [ ] **Step 3: Implement the screen**

Structure:

```
Scaffold
  appBar: AppBar(title: l10n.categoryManagerTitle)
  body: switch (ref.watch(categoryTreeProvider))
    AsyncLoading -> NimbusLoadingList(rows: 6)
    AsyncError   -> NimbusErrorState(title: l10n.categoryErrorTitle,
                      retryLabel: l10n.commonRetry,
                      onRetry: () => ref.invalidate(categoryTreeProvider))
    AsyncData(value: final roots) when roots.isEmpty
                 -> NimbusEmptyState(...)
    AsyncData(value: final roots)
                 -> ReorderableListView over the flattened tree
  floatingActionButton: FloatingActionButton.extended(   // bottom third
      key: Key('category-add'), onPressed: _openEditor)
```

Flattening: the tree is rendered as a flat list of `CategoryRow`s carrying their
own depth, because `ReorderableListView` needs a flat child list and a nested
one would make drag-to-reorder ambiguous across levels. Reorder is therefore
**within a sibling group only** — a drag that would cross groups is rejected in
`onReorder` by comparing `parentId`, and re-parenting is done through "Move
to…", which is also what makes the operation reachable without a drag for
accessibility.

`CategoryRow`:
- leading: `Icon` from the icon key, tinted `Color(category.color)`, wrapped in
  `Semantics(label: l10n.categoryIconLabel)`.
- indent: `SizedBox(width: min(depth, maxTreeIndentDepth) * indentPerLevel)`
  placed at the row's *start*, so RTL indents from the right for free — never
  `EdgeInsets.only(left:)`.
- title: name; subtitle: child count when non-zero, plus an archived badge.
- trailing: `PopupMenuButton` with rename, change icon/colour, move to…,
  archive/unarchive, delete. For `SystemCategoryIds.isSystem(id)` the menu holds
  only "change icon/colour" — the guard is in the repository, but a menu that
  offers an action that always throws is a bug in its own right.
- `key: Key('category-row-${category.id}')`, and the whole row is a
  `Semantics(button: true, label: name)`.

Delete handler — the pattern every destructive action in this app follows:

```dart
Future<void> _delete(WidgetRef ref, BuildContext context, Category c) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(categoryRepositoryProvider);
  final restored = await repo.delete(c.id);
  messenger.showSnackBar(nimbusUndoSnackBar(
    message: l10n.categoryDeleted(c.name),
    undoLabel: l10n.commonUndo,
    onUndo: () => repo.restore(restored),
  ));
}
```

No dialog, no await on user confirmation, and the delete happens first so the
list updates immediately — the stream from `watchAll` drives the rebuild.

`MoveTargetSheet` lists every category as a flat, indented list plus a "Move to
root" entry, with `enabled: repo.canMove(id: moving, newParentId: target)`.
Disabled targets are rendered dimmed with a semantics hint, which is how the
invalid drop is refused before it happens rather than after.

`IconPicker` offers a fixed set of about 24 Material icons, mapped from string
keys in one `Map<String, IconData>` in
`app/lib/features/categories/presentation/widgets/icon_picker.dart`. The map is
the single place a key becomes an icon, so a key that arrives from seeding, from
a Phase 2 merchant rule, or from a backup restore resolves identically —
and an unknown key resolves to `Icons.label_outline` with no exception, because
an icon is cosmetic and a missing one must not take a screen down.

**ARB keys added by this task** (both files, alphabetical position):

| key | en | fa |
|---|---|---|
| `commonRetry` | Retry | تلاش دوباره |
| `commonUndo` | Undo | بازگردانی |
| `commonRename` | Rename | تغییر نام |
| `commonDelete` | Delete | حذف |
| `commonArchive` | Archive | بایگانی |
| `commonUnarchive` | Unarchive | خروج از بایگانی |
| `commonMoveTo` | Move to… | انتقال به… |
| `commonSave` | Save | ذخیره |
| `commonCancel` | Cancel | انصراف |
| `categoryManagerTitle` | Categories | دسته‌بندی‌ها |
| `categoryEmptyTitle` | No categories | دسته‌بندی‌ای وجود ندارد |
| `categoryEmptyMessage` | Categories group your spending. Create your first one. | دسته‌بندی‌ها هزینه‌های شما را گروه‌بندی می‌کنند. اولین مورد را بسازید. |
| `categoryEmptyAction` | New category | دسته‌بندی جدید |
| `categoryErrorTitle` | Could not load categories | بارگذاری دسته‌بندی‌ها ممکن نشد |
| `categoryNewTitle` | New category | دسته‌بندی جدید |
| `categoryEditTitle` | Edit category | ویرایش دسته‌بندی |
| `categoryNameLabel` | Name | نام |
| `categoryIconLabel` | Icon | نماد |
| `categoryColorLabel` | Colour | رنگ |
| `categoryMoveToRoot` | Move to top level | انتقال به سطح اول |
| `categoryMoveInvalid` | A category cannot move inside itself | یک دسته‌بندی نمی‌تواند درون خودش قرار گیرد |
| `categoryArchivedBadge` | Archived | بایگانی‌شده |
| `categoryDeleted` | Deleted {name} | {name} حذف شد |
| `categoryChildCount` | {count, plural, =1{1 subcategory} other{{count} subcategories}} | {count, plural, other{{count} زیر‌دسته}} |

- [ ] **Step 4: Register the route**

`app/lib/features/categories/routes.dart`:

```dart
const categoryManagerRoute = '/categories';

final categoryRoutes = <RouteBase>[
  GoRoute(
    path: categoryManagerRoute,
    name: 'categories',
    builder: (context, state) => const CategoryManagerScreen(),
  ),
];
```

and one line added to `app_router.dart`'s route list: `...categoryRoutes,`.

- [ ] **Step 5: Run the screen test, then the broader suite, then commit**

```bash
cd app && flutter test test/features/categories/
cd .. && dart analyze --fatal-infos && dart test test/architecture_test.dart
cd app && flutter test
```

```bash
git tag pre-category-manager HEAD
git add app && git commit -m "feat: category manager screen with all four states

Reordering is deliberately restricted to a sibling group and re-parenting goes
through Move to..., which is both unambiguous for a flat ReorderableListView and
reachable without a drag for anyone using a screen reader.

Invalid move targets are rendered disabled rather than rejected on drop: the
screen contract calls surfacing that as an after-the-fact error toast
unacceptable, and the repository already exposes canMove as a pure predicate.

Delete is a soft delete plus an undo snackbar. There is no confirmation dialog
anywhere in this screen, which Task 14 turns into an enforced grep."
```

---

## Task 7: Tag DAO extensions and `TagRepository`

Structurally the same as Task 5 with three differences that matter: tags are not
seeded (so `empty` is the real first-run state), they carry `usageCount` for
suggestion ranking, and they must be creatable inline from the add screen.

**Files:**
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` **(P0)**
- Create: `app/lib/features/tags/data/tag_repository.dart`
- Create: `app/lib/features/tags/application/tag_providers.dart`
- Test: `packages/nimbus_data/test/tags_dao_test.dart`
- Test: `app/test/features/tags/tag_repository_test.dart`

**Interfaces:**
- Produces: on `TagsDao` — `watchAll`, `rename`, `updateAppearance`,
  `setArchivedSubtree`, `softDeleteSubtree`, `restoreAll`, `reorderSiblings`,
  `allLive`, `childCounts`, plus `incrementUsage(String id)` and
  `recomputeUsageCounts()`; `TagRepository` with the same surface as
  `CategoryRepository` plus
  `Future<Tag> findOrCreate(String name, {String? parentId})`;
  `tagRepositoryProvider`, `tagTreeProvider`, `tagSuggestionsProvider`.

- [ ] **Step 1: Write the failing DAO test** — mirror
  `categories_dao_test.dart` (rename, archive subtree, soft delete and exact
  undo, reorder, watch), and add:

```dart
  test('usage count rises when a tag is attached', () async {
    await dao.insertNode(id: 'travel', name: 'travel', parentId: null);
    expect((await dao.byId('travel'))!.usageCount, 0);
    await dao.incrementUsage('travel');
    await dao.incrementUsage('travel');
    expect((await dao.byId('travel'))!.usageCount, 2);
  });

  test('recomputeUsageCounts rebuilds from the join table', () async {
    // usage_count is a cache. Anything that can drift needs a way back to the
    // truth, or it becomes a number nobody trusts and everybody ignores.
    await dao.insertNode(id: 'travel', name: 'travel', parentId: null);
    await dao.incrementUsage('travel');   // count says 1
    await dao.incrementUsage('travel');   // count says 2, join table says 0
    await dao.recomputeUsageCounts();
    expect((await dao.byId('travel'))!.usageCount, 0);
  });

  test('nested tags roll up through the materialized path', () async {
    await dao.insertNode(id: 'travel', name: 'travel', parentId: null);
    await dao.insertNode(id: 'turkey', name: 'turkey-2026', parentId: 'travel');
    final subtree = await dao.subtreeOf('travel');
    expect(subtree.map((t) => t.id), containsAll(<String>['travel', 'turkey']));
  });
```

- [ ] **Step 2: Run and verify failure.**

- [ ] **Step 3: Implement.** `incrementUsage` is a single
  `UPDATE tags SET usage_count = usage_count + 1` expressed through drift's
  `customUpdate` so it is atomic rather than read-modify-write.
  `recomputeUsageCounts` sets each tag's count from
  `SELECT tag_id, COUNT(*) FROM transaction_tags GROUP BY tag_id`, defaulting
  absent tags to zero.

- [ ] **Step 4: Write the failing repository test**, whose distinctive cases are:

```dart
  test('findOrCreate returns the existing tag, case-insensitively', () async {
    final first = await repo.findOrCreate('Travel');
    final second = await repo.findOrCreate('travel');
    expect(second.id, first.id,
        reason: 'a user typing a different case means the same tag; two rows '
            'here would silently split their history in two');
  });

  test('findOrCreate trims and rejects an empty name', () async {
    final tag = await repo.findOrCreate('  travel  ');
    expect(tag.name, 'travel');
    expect(() => repo.findOrCreate('   '), throwsArgumentError);
  });

  test('findOrCreate nests under a parent when given one', () async {
    final parent = await repo.findOrCreate('travel');
    final child = await repo.findOrCreate('turkey-2026', parentId: parent.id);
    expect(child.path, '/${parent.id}/${child.id}/');
  });

  test('suggestions rank by usage then recency', () async {
    // The add screen shows a bounded list; ordering is the whole value of it.
    ...
    expect(suggestions.map((t) => t.name).take(3), ['food', 'travel', 'work']);
  });
```

- [ ] **Step 5: Implement `TagRepository`.** `findOrCreate` normalises with
  `name.trim()` and compares case-insensitively against live tags in the same
  parent scope; a name that is empty after trimming throws `ArgumentError`
  rather than creating a blank tag.

- [ ] **Step 6: Run everything, commit.**

```bash
git tag pre-tag-repository HEAD
git add packages/nimbus_data app
git commit -m "feat: tag tree operations, inline creation, and usage ranking

findOrCreate is case-insensitive and trims, because two rows for Travel and
travel would split one tag's history in half and nothing in the UI would show
why the numbers looked wrong.

usage_count is a cache with a recompute path. A denormalised counter without one
becomes a number nobody trusts, and there is a test that proves the rebuild
disagrees with a drifted counter and wins.

Touches app_database.dart (Phase 0) additively: nine methods on TagsDao."
```

---

## Task 8: Tag manager screen

Same shape as Task 6. What differs, and what the test must therefore assert:

- **`empty` is the real first-run state.** Tags are not seeded. The empty state
  must explain what a tag *is* — "Tags group expenses across categories, like
  #travel or #gift" — not merely say there is no data. Screen contract 3.5.
- **Inline creation from the picker.** `TagPickerSheet` has a text field whose
  submit action calls `findOrCreate` and immediately selects the result. The
  test types a novel name, submits, and asserts both that the tag now exists and
  that it is selected — without the tag manager ever being opened.
- **D3, twenty tags on one expense.** `TagChipRow` renders at most four chips
  plus a `+N` affordance; the test attaches twenty tags and asserts exactly five
  children and no overflow at 320 logical pixels.
- **Usage count is shown** on each manager row and drives picker ordering.

**Files:** `app/lib/features/tags/presentation/{tag_manager_screen,
widgets/tag_picker_sheet, widgets/tag_chip_row}.dart`,
`app/lib/features/tags/routes.dart`, both ARB files, and
`app/test/features/tags/tag_manager_screen_test.dart`.

**ARB keys:** `tagManagerTitle` (Tags / برچسب‌ها), `tagEmptyTitle` (No tags yet /
هنوز برچسبی ندارید), `tagEmptyMessage` (Tags group expenses across categories,
like travel or gift. / برچسب‌ها هزینه‌ها را فراتر از دسته‌بندی گروه‌بندی می‌کنند،
مثل سفر یا هدیه.), `tagEmptyAction` (New tag / برچسب جدید), `tagErrorTitle`
(Could not load tags / بارگذاری برچسب‌ها ممکن نشد), `tagNewTitle`, `tagNameLabel`
(Name / نام), `tagCreateInline` (Create "{name}" / ساخت «{name}»),
`tagUsageCount` (`{count, plural, other{{count} uses}}` /
`{count, plural, other{{count} بار استفاده}}`), `tagPickerTitle` (Tags /
برچسب‌ها), `tagPickerSearchHint` (Search or create / جست‌وجو یا ساخت),
`tagMoreCount` (+{count} / +{count}), `tagDeleted` (Deleted {name} / {name} حذف
شد).

Commit message body should say why the empty state carries an explanation
rather than a bare "no data": tags are the one Phase 1 concept a first-time user
has never configured, and an empty list that does not teach is a dead end.

---

## Task 9: Payment methods — DAO, repository, and manager screen

Small enough to land data and UI together: one flat table, no tree, no
materialized paths.

**Files:**
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` **(P0)** —
  add `PaymentMethodsDao` and `AppDatabase.paymentMethodsDao`
- Create: `app/lib/features/payment_methods/data/payment_method_repository.dart`
- Create: `app/lib/features/payment_methods/application/payment_method_providers.dart`
- Create: `app/lib/features/payment_methods/presentation/payment_method_manager_screen.dart`
- Create: `app/lib/features/payment_methods/presentation/widgets/payment_method_picker.dart`
- Create: `app/lib/features/payment_methods/routes.dart`
- Modify: `app/lib/bootstrap/app_router.dart`, both ARB files
- Test: `packages/nimbus_data/test/payment_methods_dao_test.dart`
- Test: `app/test/features/payment_methods/payment_method_manager_screen_test.dart`

**Interfaces produced:** `PaymentMethodsDao` with `watchAll`, `allLive`,
`byId`, `insertMethod({required String id, required String name,
required PaymentMethodKind kind, String? last4, int color, String iconKey})`,
`update`, `setArchived`, `softDelete`, `restoreAll`;
`PaymentMethodRepository`; `paymentMethodsProvider`;
`paymentMethodRoutes` and `paymentMethodManagerRoute` (`'/payment-methods'`).

Distinctive test cases:

```dart
  test('last4 must be exactly four digits or absent', () async {
    // The column is withLength(min: 4, max: 4) and nullable, so the database
    // enforces the length. The repository enforces digit-ness, and normalises
    // Persian digits first -- a user typing ۱۲۳۴ means 1234.
    expect(() => repo.create(name: 'Card', kind: PaymentMethodKind.card,
        last4: '12'), throwsArgumentError);
    final method = await repo.create(
        name: 'Card', kind: PaymentMethodKind.card, last4: '۱۲۳۴');
    expect(method.last4, '1234');
  });

  test('the app never stores more than four digits', () async {
    expect(() => repo.create(name: 'Card', kind: PaymentMethodKind.card,
        last4: '1234567890123456'), throwsArgumentError,
        reason: 'this app has no reason to hold a full card number');
  });

  test('archived methods disappear from the picker but resolve historically',
      () async {
    final method = await repo.create(name: 'Old card', kind: PaymentMethodKind.card);
    await repo.archive(method.id);
    expect((await repo.pickable()).map((m) => m.id), isNot(contains(method.id)));
    expect(await repo.byId(method.id), isNotNull);
  });
```

Plus the four screen states, the undo-on-delete snackbar, and no confirmation
dialog — identical in shape to Task 6, and worth asserting again because these
are the properties that silently regress.

**ARB keys:** `payManagerTitle` (Payment methods / روش‌های پرداخت),
`payEmptyTitle` (No payment methods / روش پرداختی ثبت نشده),
`payEmptyMessage` (Add cash, a card, or a bank account to see where your money
goes out from. / نقدی، کارت یا حساب بانکی اضافه کنید تا ببینید پول از کجا خارج
می‌شود.), `payEmptyAction`, `payErrorTitle`, `payNewTitle`, `payNameLabel`,
`payKindLabel` (Type / نوع), `payKindCash` (Cash / نقدی), `payKindCard` (Card /
کارت), `payKindBank` (Bank / بانک), `payKindOther` (Other / سایر),
`payLast4Label` (Last 4 digits / چهار رقم آخر), `payLast4Invalid` (Enter exactly
four digits / دقیقاً چهار رقم وارد کنید), `payNone` (None / هیچ‌کدام),
`payDeleted` (Deleted {name} / {name} حذف شد).

```bash
git tag pre-payment-methods HEAD
git add packages/nimbus_data app && git commit -m "feat: payment methods as an analytics dimension

No balances and no reconciliation, by design -- a payment method here answers
'where did this go out from', nothing more, so nothing ever needs to be made to
add up.

last4 is validated as exactly four digits after Persian-to-Latin normalisation,
and anything longer is rejected outright: this app has no reason to hold a full
card number and the easiest way to guarantee that is to make it impossible."
```

---

## Task 10: `TransactionDraft`, `TransactionRepository`, and keyset pagination

The single write path, and the read path that has to survive five years of daily
use. Phases 2, 3, 5, and 6 all consume what this task produces, so the names are
fixed by the brief and must be typed exactly as written.

**Files:**
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` **(P0)**
- Create: `app/lib/features/transactions/data/transaction_draft.dart`
- Create: `app/lib/features/transactions/data/transaction_query.dart`
- Create: `app/lib/features/transactions/data/transaction_repository.dart`
- Create: `app/lib/features/transactions/application/transaction_providers.dart`
- Test: `packages/nimbus_data/test/pagination_test.dart`
- Test: `app/test/features/transactions/transaction_repository_test.dart`

**Interfaces:**
- Consumes: `TransactionsDao`, `Money`, `DateKey`, `DateRange`, `TxDirection`,
  `TxSource`, `Necessity`, `Satisfaction`, `Ids.newId()`, `currencyProvider`.
- Produces:
  - `TransactionDraft` — `Money amount`, `TxDirection direction`,
    `String categoryId`, `DateTime occurredAtUtc`, and optional
    `paymentMethodId`, `merchant`, `note`, `tagIds`, `necessity`,
    `satisfaction`, `source` (default `TxSource.manual`), `isConfirmed`
    (default `true`), `captureId`.
  - `TransactionRepository` with
    `Future<Transaction> add(TransactionDraft draft)`,
    `Future<void> update(Transaction tx, {List<String>? tagIds})`,
    `Future<void> softDelete(String id)`, `Future<void> restore(String id)`,
    `Future<TransactionPage> page(PaginatedTransactionQuery query)`,
    `Future<Money> total(DateRange range, {TxDirection? direction})`.
  - `PaginatedTransactionQuery`, `TransactionCursor`, `TransactionPage`.
  - `TransactionsDao`: `pageAfter(...)`, `sumInRange(...)`,
    `updateTransaction(...)`, `softDelete(id)`, `restore(id)`,
    `recentCategoryUsage({int limit})`.
  - `transactionRepositoryProvider`.

---

- [ ] **Step 1: Write the failing pagination test**

Create `packages/nimbus_data/test/pagination_test.dart`. This is the test that
justifies the whole keyset design, so it uses a realistic volume:

```dart
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

import 'support/test_database.dart';

/// 5,000 transactions across roughly three years, which is what the brief
/// requires the list performance check to run against.
Future<void> seedLargeDatabase(AppDatabase db, {int count = 5000}) async {
  await db.categoriesDao
      .insertNode(id: 'cat', name: 'Cat', parentId: null);
  await db.batch((batch) {
    final now = DateTime.utc(2026, 8, 21);
    for (var i = 0; i < count; i++) {
      final at = now.subtract(Duration(hours: i * 5));
      batch.insert(
        db.transactions,
        TransactionsCompanion.insert(
          id: 'tx-${i.toString().padLeft(6, '0')}',
          direction: i % 7 == 0 ? TxDirection.income : TxDirection.expense,
          amount: Money(1000 + i),
          currencyCode: 'IRT',
          occurredAtUtc: at.millisecondsSinceEpoch,
          localDateKey: DateKey.fromDateTime(at),
          categoryId: 'cat',
          source: TxSource.manual,
          merchant: Value(i % 3 == 0 ? 'Cafe $i' : null),
          createdAt: at.millisecondsSinceEpoch,
          updatedAt: at.millisecondsSinceEpoch,
        ),
      );
    }
  });
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    await seedLargeDatabase(db);
  });

  tearDown(() => db.close());

  test('a keyset walk visits every row exactly once', () async {
    // The property that matters. LIMIT/OFFSET would also pass a naive count
    // test while quietly repeating or skipping rows whenever a write lands
    // between pages -- which is the normal case for an app being used.
    final range = DateRange(const DateKey(20000101), const DateKey(20991231));
    final seen = <String>[];
    TransactionCursorRow? cursor;

    while (true) {
      final page = await db.transactionsDao.pageAfter(
        range: range,
        after: cursor,
        limit: 100,
      );
      if (page.isEmpty) break;
      seen.addAll(page.map((t) => t.id));
      final last = page.last;
      cursor = (dateKey: last.localDateKey, id: last.id);
    }

    expect(seen, hasLength(5000));
    expect(seen.toSet(), hasLength(5000), reason: 'no row may repeat');
  });

  test('pages come back newest first, and pages do not overlap', () async {
    final range = DateRange(const DateKey(20000101), const DateKey(20991231));
    final first = await db.transactionsDao.pageAfter(range: range, limit: 40);
    final last = first.last;
    final second = await db.transactionsDao.pageAfter(
      range: range,
      after: (dateKey: last.localDateKey, id: last.id),
      limit: 40,
    );

    expect(first, hasLength(40));
    expect(second, hasLength(40));
    expect(first.first.localDateKey.value,
        greaterThanOrEqualTo(first.last.localDateKey.value));
    expect(first.map((t) => t.id).toSet().intersection(
        second.map((t) => t.id).toSet()), isEmpty);
  });

  test('the page query uses the date index rather than scanning', () async {
    // Same technique Phase 0 used for the materialized path: assert the plan,
    // not the wall clock, so the guarantee survives a fast machine.
    final rows = await db.customSelect(
      'EXPLAIN QUERY PLAN SELECT * FROM transactions '
      'WHERE deleted_at IS NULL AND local_date_key BETWEEN ? AND ? '
      'ORDER BY local_date_key DESC, id DESC LIMIT 40',
      variables: [Variable<int>(20240101), Variable<int>(20991231)],
    ).get();
    final plan = rows.map((r) => r.data.values.join(' ')).join('\n');
    expect(plan.toLowerCase(), contains('idx_tx_date'),
        reason: 'pagination must not degrade into a table scan:\n$plan');
  });

  test('a period total is one SUM, not five thousand rows on the wire',
      () async {
    final range = DateRange(const DateKey(20260801), const DateKey(20260831));
    final total = await db.transactionsDao.sumInRange(range,
        direction: TxDirection.expense);
    final rows = await db.transactionsDao
        .inRange(range)
        .then((all) => all.where((t) => t.direction == TxDirection.expense));
    expect(total, Money.sum(rows.map((t) => t.amount)));
  });

  test('soft-deleted rows leave the page and come back on restore', () async {
    final range = DateRange(const DateKey(20000101), const DateKey(20991231));
    final before = await db.transactionsDao.pageAfter(range: range, limit: 5);
    await db.transactionsDao.softDelete(before.first.id);

    final after = await db.transactionsDao.pageAfter(range: range, limit: 5);
    expect(after.map((t) => t.id), isNot(contains(before.first.id)));

    await db.transactionsDao.restore(before.first.id);
    final restored = await db.transactionsDao.pageAfter(range: range, limit: 5);
    expect(restored.map((t) => t.id), contains(before.first.id));
  });

  test('search matches merchant and note without treating input as SQL',
      () async {
    // A search box is untrusted input. LIKE wildcards inside it must match
    // literally, or a user typing % gets every row and a user typing _ gets
    // nonsense.
    final range = DateRange(const DateKey(20000101), const DateKey(20991231));
    final hits = await db.transactionsDao
        .pageAfter(range: range, searchText: 'Cafe 3', limit: 100);
    expect(hits, isNotEmpty);
    expect(hits.every((t) => t.merchant!.contains('Cafe 3')), isTrue);

    final wildcards = await db.transactionsDao
        .pageAfter(range: range, searchText: '%', limit: 100);
    expect(wildcards, isEmpty,
        reason: 'a literal percent sign matches no merchant in this data');
  });
}
```

`TransactionCursorRow` is the record type `({DateKey dateKey, String id})`,
declared as a typedef in `nimbus_data` so both layers name it the same way.

- [ ] **Step 2: Run it and verify it fails**

```bash
cd packages/nimbus_data && dart test test/pagination_test.dart
```

Expected: undefined `pageAfter`, `sumInRange`, `softDelete`, `restore`.

- [ ] **Step 3: Implement the DAO methods**

```dart
typedef TransactionCursorRow = ({DateKey dateKey, String id});

  /// Keyset pagination over `(local_date_key DESC, id DESC)`.
  ///
  /// Not LIMIT/OFFSET. Offset re-counts every skipped row on each page, so it
  /// degrades exactly when the user has enough history for the app to be worth
  /// using -- and it repeats or drops rows whenever a write lands between two
  /// page fetches, which for this app is the normal case rather than the edge.
  ///
  /// UUIDv7 ids are time-ordered, so `id` is a meaningful tiebreaker within a
  /// day rather than an arbitrary one.
  Future<List<Transaction>> pageAfter({
    required DateRange range,
    TransactionCursorRow? after,
    int limit = 40,
    TxDirection? direction,
    String? categoryId,
    String? searchText,
    bool confirmedOnly = false,
  }) {
    final query = _db.select(_db.transactions)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.localDateKey.isBetweenValues(
            range.startInclusive.value,
            range.endInclusive.value,
          ))
      ..orderBy([
        (t) => OrderingTerm.desc(t.localDateKey),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);

    if (after != null) {
      query.where((t) =>
          t.localDateKey.isSmallerThanValue(after.dateKey.value) |
          (t.localDateKey.equals(after.dateKey.value) &
              t.id.isSmallerThanValue(after.id)));
    }
    if (direction != null) query.where((t) => t.direction.equalsValue(direction));
    if (categoryId != null) query.where((t) => t.categoryId.equals(categoryId));
    if (confirmedOnly) query.where((t) => t.isConfirmed.equals(true));

    final needle = searchText?.trim();
    if (needle != null && needle.isNotEmpty) {
      // Wildcards in user input match literally. `\` escapes `%`, `_`, and
      // itself; SQLite needs the ESCAPE clause spelled out for that to hold.
      final escaped = needle
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      final pattern = '%$escaped%';
      query.where((t) =>
          t.merchant.like(pattern, escape: r'\') |
          t.note.like(pattern, escape: r'\'));
    }
    return query.get();
  }
```

Verify against the installed drift version whether `like` accepts an `escape`
argument; if it does not, express the predicate with
`customExpression` carrying `merchant LIKE ?1 ESCAPE '\'` rather than dropping
the escaping. Do not fall back to unescaped `LIKE` — that is the silent
correctness bug this comment exists to prevent.

```dart
  /// A period total as one SUM. `totalInRange` (Phase 0) pulls every row across
  /// the boundary and adds them in Dart, which was fine at Phase 0 volumes and
  /// is not fine at five thousand.
  Future<Money> sumInRange(
    DateRange range, {
    TxDirection? direction,
    bool confirmedOnly = false,
  }) async {
    final amount = _db.transactions.amount;
    final total = amount.sum();
    final query = _db.selectOnly(_db.transactions)..addColumns([total]);
    var predicate = _db.transactions.deletedAt.isNull() &
        _db.transactions.localDateKey.isBetweenValues(
          range.startInclusive.value,
          range.endInclusive.value,
        );
    if (direction != null) {
      predicate = predicate & _db.transactions.direction.equalsValue(direction);
    }
    if (confirmedOnly) {
      predicate = predicate & _db.transactions.isConfirmed.equals(true);
    }
    query.where(predicate);
    final row = await query.getSingle();
    // An empty range sums to NULL in SQL, which is zero money, not an error.
    return Money(row.read(total) ?? 0);
  }

  Future<void> softDelete(String id) =>
      (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          deletedAt: Value(DateTime.now().millisecondsSinceEpoch),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<void> restore(String id) =>
      (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
```

`sum()` is applied to the raw column; confirm whether drift's converter-aware
column exposes `.sum()` directly. If it does not, take the sum over
`_db.transactions.amount.dartCast<int>()` and wrap the result in `Money` — the
important property is that the addition happens in SQLite and that the result
becomes `Money` before it leaves this method, never a `double`.

`updateTransaction` writes every mutable field plus `updatedAt`.
`recentCategoryUsage({int limit})` returns
`List<({String categoryId, String? merchant, DateTime occurredAt})>` ordered by
`local_date_key DESC, id DESC`, limited — the raw material for Task 11.

- [ ] **Step 4: Run the pagination test and verify it passes**

- [ ] **Step 5: Write the failing repository test**

`app/test/features/transactions/transaction_repository_test.dart`:

```dart
  test('add fills in id, timestamps, currency, and the local date key',
      () async {
    final at = DateTime.utc(2026, 8, 21, 18, 30);
    final tx = await repo.add(TransactionDraft(
      amount: const Money(125000),
      direction: TxDirection.expense,
      categoryId: 'cat',
      occurredAtUtc: at,
    ));

    expect(tx.id, isNotEmpty);
    expect(tx.amount, const Money(125000));
    expect(tx.currencyCode, 'IRT', reason: 'taken from the active currency');
    expect(tx.localDateKey, DateKey.fromDateTime(at.toLocal()));
    expect(tx.source, TxSource.manual);
    expect(tx.isConfirmed, isTrue);
    expect(tx.createdAt, greaterThan(0));
  });

  test('the local date key follows local time, not UTC', () async {
    // A purchase at 01:00 local on the 22nd is the 22nd, even though it is
    // still the 21st in UTC. Getting this wrong puts spending in the wrong day
    // bucket for everyone east of Greenwich, which is the entire target market.
    final at = DateTime(2026, 8, 22, 1, 0).toUtc();
    final tx = await repo.add(TransactionDraft(
      amount: const Money(1),
      direction: TxDirection.expense,
      categoryId: 'cat',
      occurredAtUtc: at,
    ));
    expect(tx.localDateKey, const DateKey(20260822));
    expect(tx.tzOffsetMinutes, DateTime(2026, 8, 22).timeZoneOffset.inMinutes);
  });

  test('tags are written and read back through the join table', () async {
    final tx = await repo.add(TransactionDraft(
      amount: const Money(1),
      direction: TxDirection.expense,
      categoryId: 'cat',
      occurredAtUtc: DateTime.utc(2026, 8, 21),
      tagIds: const ['travel', 'food'],
    ));
    expect((await db.transactionsDao.tagsOf(tx.id)).toSet(),
        {'travel', 'food'});
  });

  test('attaching a tag raises its usage count', () async {
    await repo.add(TransactionDraft(
      amount: const Money(1),
      direction: TxDirection.expense,
      categoryId: 'cat',
      occurredAtUtc: DateTime.utc(2026, 8, 21),
      tagIds: const ['travel'],
    ));
    expect((await db.tagsDao.byId('travel'))!.usageCount, 1);
  });

  test('a draft without a category lands in Uncategorized, never null',
      () async {
    // Every chart depends on category_id being non-null. The draft type makes
    // categoryId required; this asserts the app-level default that feeds it.
    final draft = TransactionDraft.uncategorized(
      amount: const Money(5000),
      direction: TxDirection.expense,
      occurredAtUtc: DateTime.utc(2026, 8, 21),
    );
    expect(draft.categoryId, SystemCategoryIds.uncategorized);
  });

  test('soft delete then restore round-trips', () async {
    final tx = await repo.add(/* ... */);
    await repo.softDelete(tx.id);
    expect((await db.transactionsDao.byId(tx.id))!.deletedAt, isNotNull);
    await repo.restore(tx.id);
    expect((await db.transactionsDao.byId(tx.id))!.deletedAt, isNull);
  });

  test('update replaces the tag set rather than appending to it', () async {
    final tx = await repo.add(/* ... tagIds: ['a', 'b'] */);
    await repo.update(tx, tagIds: const ['b', 'c']);
    expect((await db.transactionsDao.tagsOf(tx.id)).toSet(), {'b', 'c'});
  });

  test('a page carries a cursor only while more rows remain', () async {
    // ... seed 45 rows, limit 40
    final first = await repo.page(query);
    expect(first.items, hasLength(40));
    expect(first.hasMore, isTrue);
    final second = await repo.page(query.next(first.cursor!));
    expect(second.items, hasLength(5));
    expect(second.hasMore, isFalse);
    expect(second.cursor, isNull);
  });
```

- [ ] **Step 6: Implement the draft, the query, and the repository**

`TransactionDraft` is immutable with a `const` constructor, a named
`TransactionDraft.uncategorized` that fills `categoryId` with
`SystemCategoryIds.uncategorized`, and a `copyWith`. It holds `Money`, never a
`double`, and `DateTime occurredAtUtc` which it asserts `isUtc`.

`TransactionRepository.add`:

```dart
  Future<Transaction> add(TransactionDraft draft) async {
    final id = Ids.newId();
    final local = draft.occurredAtUtc.toLocal();
    await _dao.insertTransaction(
      id: id,
      direction: draft.direction,
      amount: draft.amount,
      currencyCode: _currency.code,
      occurredAtUtc: draft.occurredAtUtc.millisecondsSinceEpoch,
      localDateKey: DateKey.fromDateTime(local),
      categoryId: draft.categoryId,
      source: draft.source,
      isConfirmed: draft.isConfirmed,
      paymentMethodId: draft.paymentMethodId,
      merchant: draft.merchant,
      note: draft.note,
    );
    if (draft.tagIds.isNotEmpty) {
      await _dao.setTags(id, draft.tagIds);
      for (final tagId in draft.tagIds.toSet()) {
        await _tagsDao.incrementUsage(tagId);
      }
    }
    final row = await _dao.byId(id);
    if (row == null) {
      // Not defensive noise: a row that vanishes between insert and read means
      // the write did not commit, and returning a fabricated object would let
      // the UI show an expense that does not exist.
      throw StateError('Transaction $id was not persisted');
    }
    return row;
  }
```

`insertTransaction` does not currently accept `tzOffsetMinutes`, `necessity`, or
`satisfaction`. Add all three as optional named parameters with defaults, in the
same additive style as Task 4.

- [ ] **Step 7: Run everything and commit**

```bash
git tag pre-transaction-repository HEAD
git add packages/nimbus_data app
git commit -m "feat: the single transaction write path and keyset pagination

TransactionRepository is the only insert path in the app. Phase 2's captures and
Phase 6's widget reuse it rather than adding a second one, which is what keeps
tag usage counts, the Uncategorized default, and the local-date-key computation
from having to be re-implemented correctly three times.

Pagination is keyset on (local_date_key, id), not LIMIT/OFFSET. Offset degrades
precisely when the user has enough history for the app to matter, and repeats or
drops rows whenever a write lands between two pages -- normal here, not an edge
case. There is a 5,000-row test that walks the whole set and asserts no row is
seen twice, plus an EXPLAIN QUERY PLAN assertion that the walk stays on
idx_tx_date.

Search input is escaped for LIKE wildcards, so a user typing a percent sign
searches for a percent sign.

Touches app_database.dart (Phase 0) additively: six methods on TransactionsDao
plus three optional parameters on insertTransaction."
```

---

## Task 11: `CategoryPredictor`

Pure domain, no database, no Flutter. The interface exists so Phase 2 can swap
merchant-rule-backed prediction in behind it without touching the add screen.

**Files:**
- Create: `packages/nimbus_domain/lib/src/prediction/category_observation.dart`
- Create: `packages/nimbus_domain/lib/src/prediction/category_predictor.dart`
- Create: `packages/nimbus_domain/lib/src/prediction/mru_frequency_predictor.dart`
- Modify: `packages/nimbus_domain/lib/nimbus_domain.dart` (barrel)
- Create: `app/lib/features/transactions/application/prediction_providers.dart`
- Test: `packages/nimbus_domain/test/prediction/mru_frequency_predictor_test.dart`

**Interfaces produced:**

```dart
abstract interface class CategoryPredictor {
  /// Returns up to [limit] category ids, best first.
  ///
  /// Never throws and never returns null: the add screen shows these as chips
  /// and an empty list simply means no chips, which is a normal first-run
  /// state rather than an error.
  List<String> predict({String? merchant, DateTime? at, int limit = 4});
}
```

- [ ] **Step 1: Write the failing predictor test**

```dart
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:test/test.dart';

CategoryObservation obs(String category, String daysAgo, {String? merchant}) =>
    CategoryObservation(
      categoryId: category,
      occurredAt: DateTime.utc(2026, 8, 21).subtract(Duration(days: int.parse(daysAgo))),
      merchant: merchant,
    );

void main() {
  final now = DateTime.utc(2026, 8, 21, 12);

  test('empty history predicts nothing rather than throwing', () {
    final predictor = MruFrequencyCategoryPredictor(const []);
    expect(predictor.predict(at: now), isEmpty);
  });

  test('a merchant seen before wins outright', () {
    // This is the whole point: the second coffee at the same cafe should not
    // require thinking about categories at all.
    final predictor = MruFrequencyCategoryPredictor([
      obs('groceries', '0'),
      obs('groceries', '1'),
      obs('groceries', '2'),
      obs('coffee', '30', merchant: 'Cafe Naderi'),
    ]);
    expect(predictor.predict(merchant: 'Cafe Naderi', at: now).first, 'coffee');
  });

  test('merchant matching ignores case and surrounding whitespace', () {
    final predictor = MruFrequencyCategoryPredictor([
      obs('coffee', '5', merchant: 'Cafe Naderi'),
    ]);
    expect(predictor.predict(merchant: '  cafe naderi ', at: now).first,
        'coffee');
  });

  test('recent beats frequent when there is no merchant', () {
    // Twelve old groceries against two recent transport entries: what someone
    // did yesterday is a better guess for today than what they did in spring.
    final predictor = MruFrequencyCategoryPredictor([
      for (var i = 0; i < 12; i++) obs('groceries', '${120 + i}'),
      obs('transport', '0'),
      obs('transport', '1'),
    ]);
    expect(predictor.predict(at: now).first, 'transport');
  });

  test('frequency breaks a recency tie', () {
    final predictor = MruFrequencyCategoryPredictor([
      obs('a', '1'),
      obs('b', '1'),
      obs('b', '2'),
    ]);
    expect(predictor.predict(at: now).first, 'b');
  });

  test('ranking is deterministic when scores are identical', () {
    // Chips that reshuffle between rebuilds are worse than chips in a boring
    // order: muscle memory is the feature.
    final predictor = MruFrequencyCategoryPredictor([
      obs('zebra', '1'),
      obs('apple', '1'),
    ]);
    expect(predictor.predict(at: now), ['apple', 'zebra']);
    expect(predictor.predict(at: now), ['apple', 'zebra']);
  });

  test('respects the limit and never repeats a category', () {
    final predictor = MruFrequencyCategoryPredictor([
      for (var i = 0; i < 20; i++) obs('c${i % 6}', '$i'),
    ]);
    final result = predictor.predict(at: now, limit: 4);
    expect(result, hasLength(4));
    expect(result.toSet(), hasLength(4));
  });

  test('time of day nudges but does not dominate', () {
    // Coffee at 9am on eight mornings against one grocery run last night.
    final predictor = MruFrequencyCategoryPredictor([
      for (var i = 1; i <= 8; i++)
        CategoryObservation(
          categoryId: 'coffee',
          occurredAt: DateTime.utc(2026, 8, 21 - i, 9),
        ),
      CategoryObservation(
        categoryId: 'groceries',
        occurredAt: DateTime.utc(2026, 8, 20, 21),
      ),
    ]);
    expect(
      predictor.predict(at: DateTime.utc(2026, 8, 21, 9)).first,
      'coffee',
    );
  });
}
```

- [ ] **Step 2: Run and verify failure.**

- [ ] **Step 3: Implement the scoring**

```dart
/// Most-recently-used plus most-frequent, with a merchant short-circuit.
///
/// Phase 2 replaces this with merchant-rule-backed prediction behind the same
/// interface, which is why [CategoryPredictor] is an interface at all rather
/// than a helper function.
final class MruFrequencyCategoryPredictor implements CategoryPredictor {
  MruFrequencyCategoryPredictor(this._history);

  final List<CategoryObservation> _history;

  // Weights are deliberately far apart rather than tuned. A merchant match is
  // near-certain knowledge; recency is a good guess; frequency is a weak prior;
  // hour-of-day is a nudge. Tuning them against real usage is Phase 2's job,
  // once there is real usage to tune against.
  static const _merchantWeight = 100.0;
  static const _recencyWeight = 10.0;
  static const _frequencyWeight = 1.0;
  static const _hourWeight = 2.0;

  @override
  List<String> predict({String? merchant, DateTime? at, int limit = 4}) {
    if (_history.isEmpty || limit <= 0) return const [];
    final now = at ?? DateTime.now();
    final needle = _normalize(merchant);
    final scores = <String, double>{};

    for (final o in _history) {
      var score = _frequencyWeight;

      final days = now.difference(o.occurredAt).inDays.abs();
      // Hyperbolic rather than exponential: yesterday and last week should
      // still be comparable, while last spring should not be.
      score += _recencyWeight / (1 + days);

      if (needle != null && _normalize(o.merchant) == needle) {
        score += _merchantWeight;
      }

      final hourGap = (o.occurredAt.hour - now.hour).abs();
      if (hourGap <= 2) score += _hourWeight * (3 - hourGap) / 3;

      scores.update(o.categoryId, (v) => v + score, ifAbsent: () => score);
    }

    final ranked = scores.keys.toList()
      ..sort((a, b) {
        final byScore = scores[b]!.compareTo(scores[a]!);
        // Alphabetical tiebreak so chip order never reshuffles between
        // rebuilds. Muscle memory is the feature.
        return byScore != 0 ? byScore : a.compareTo(b);
      });
    return ranked.take(limit).toList();
  }

  static String? _normalize(String? value) {
    final trimmed = value?.trim().toLowerCase();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
```

- [ ] **Step 4: Wire the app-side provider**

`categoryPredictorProvider` is a `FutureProvider<CategoryPredictor>` that reads
`recentCategoryUsage(limit: 300)` and constructs the predictor. Three hundred is
enough history for the ranking to be stable and small enough to load on every
open of the add screen without being noticed; the number is named as a constant
with that reasoning attached.

- [ ] **Step 5: Run everything and commit**

```bash
git tag pre-category-predictor HEAD
git add packages/nimbus_domain app
git commit -m "feat: MRU-plus-frequency category prediction behind an interface

The interface is the deliverable. Phase 2 swaps in merchant-rule-backed
prediction without the add screen changing, which is only possible if the seam
exists before there is a second implementation to justify it.

Weights are spread far apart rather than tuned: a merchant match is near
certain, recency is a good guess, frequency is a weak prior, hour-of-day is a
nudge. Tuning happens in Phase 2 against real usage rather than now against
imagined usage.

Ranking breaks ties alphabetically so chip order is stable between rebuilds.
Chips that reshuffle defeat the muscle memory that makes three taps possible."
```

---

## Task 12: Add-expense screen

The screen the whole app is judged on. Five of the ten UX acceptance criteria
are verified here.

**Files:**
- Create: `app/lib/features/transactions/presentation/add_transaction_screen.dart`
- Create: `app/lib/features/transactions/presentation/widgets/amount_field.dart`
- Create: `app/lib/features/transactions/presentation/widgets/category_chips.dart`
- Create: `app/lib/features/transactions/presentation/widgets/direction_toggle.dart`
- Create: `app/lib/features/transactions/presentation/widgets/date_field.dart`
- Create: `app/lib/features/transactions/application/add_transaction_controller.dart`
- Create: `app/lib/features/transactions/routes.dart`
- Modify: `app/lib/bootstrap/app_router.dart`, both ARB files
- Test: `app/test/features/transactions/add_transaction_screen_test.dart`

**Interfaces produced:** `addTransactionRoute` (`'/add'`),
`transactionDetailRoute` (`'/tx/:id'`), `transactionRoutes` — **Phases 2 and 6
consume these names**; `AddTransactionScreen`;
`AddTransactionController` (a `Notifier<AddTransactionState>`) with
`setAmountText`, `selectCategory`, `toggleTag`, `setPaymentMethod`,
`setMerchant`, `setNote`, `setDate`, `setDirection`, `save`.

### The tap-count definition

The brief requires a repeat purchase in **three taps**, verified by a widget
test counting taps on the golden path. Digit entry is data, not navigation, so
the count is of **non-digit taps** and the golden path is stated explicitly in
the test so nobody can quietly re-define it later:

1. tap the FAB on the transaction list → the add screen opens with the amount
   field already focused;
2. type the amount (not counted);
3. tap a predicted category chip;
4. tap save.

Three taps. If a future change adds a required field, this test fails, which is
the entire point of writing it down this way.

- [ ] **Step 1: Write the failing screen test**

```dart
void main() {
  group('the golden path', () {
    testWidgets('a repeat purchase takes three taps', (tester) async {
      final db = await pumpApp(tester, seedFirstRun: true);
      // History so the predictor has something to offer.
      await seedRepeatPurchases(db, categoryId: 'seed-food-coffee', count: 5);

      var taps = 0;
      Future<void> tap(Finder f) async {
        taps++;
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await tap(find.byKey(const Key('tx-add-fab')));               // 1
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '45000');
      await tester.pumpAndSettle();
      await tap(find.byKey(const Key('tx-chip-seed-food-coffee')));  // 2
      await tap(find.byKey(const Key('tx-save')));                   // 3

      expect(taps, 3);
      final saved = await db.transactionsDao
          .pageAfter(range: everything, limit: 1);
      expect(saved.single.amount, const Money(45000));
      expect(saved.single.categoryId, 'seed-food-coffee');
    });

    testWidgets('the keypad opens focused on the amount', (tester) async {
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      final field = tester.widget<TextField>(
          find.byKey(const Key('tx-amount-field')));
      expect(field.autofocus, isTrue);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.keyboardType, TextInputType.number);
    });

    testWidgets('amount is the only required field', (tester) async {
      final db = await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '1000');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();

      final saved = await db.transactionsDao.pageAfter(range: everything, limit: 1);
      expect(saved, hasLength(1));
      expect(saved.single.categoryId, SystemCategoryIds.uncategorized,
          reason: 'no category chosen must still produce a real row, because '
              'every chart depends on category_id being non-null');
      expect(saved.single.note, isNull);
      expect(saved.single.paymentMethodId, isNull);
    });

    testWidgets('save shows no spinner', (tester) async {
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '1000');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pump();   // one frame, mid-save
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('save fires a haptic', (tester) async {
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

      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '1000');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();
      expect(haptics, isNotEmpty);
    });
  });

  group('the amount field', () {
    testWidgets('accepts Persian digits', (tester) async {
      // A user typing ۱۲۳۴۵ must not produce a parse error.
      final db = await pumpApp(tester, seedFirstRun: true,
          initialLocation: '/add', locale: const Locale('fa'));
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '۱۲۳۴۵');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();
      final saved = await db.transactionsDao.pageAfter(range: everything, limit: 1);
      expect(saved.single.amount, const Money(12345));
    });

    testWidgets('renders grouped digits in the active locale', (tester) async {
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add',
          locale: const Locale('fa'));
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '1234567');
      await tester.pump();
      expect(find.text('۱٬۲۳۴٬۵۶۷'), findsOneWidget);
    });

    testWidgets('a nine-digit Toman amount does not overflow', (tester) async {
      // Degenerate case D1.
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add',
          locale: const Locale('fa'));
      await tester.enterText(
          find.byKey(const Key('tx-amount-field')), '999999999');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('refuses to save a malformed amount and says so', (tester) async {
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '1.2.3');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tx-amount-error')), findsOneWidget);
    });

    testWidgets('an empty amount cannot be saved', (tester) async {
      final db = await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();
      expect(await db.transactionsDao.pageAfter(range: everything, limit: 1),
          isEmpty);
    });
  });

  group('layout and reachability', () {
    testWidgets('save sits in the bottom third of the screen', (tester) async {
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      final saveCentre = tester.getCenter(find.byKey(const Key('tx-save')));
      final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(saveCentre.dy, greaterThan(height * 2 / 3),
          reason: 'primary actions must stay within one-handed reach');
    });

    testWidgets('category chips arriving late do not move the amount field',
        (tester) async {
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      final before = tester.getRect(find.byKey(const Key('tx-amount-field')));
      await tester.pumpAndSettle();   // predictions resolve
      final after = tester.getRect(find.byKey(const Key('tx-amount-field')));
      expect(after, before,
          reason: 'the chip row reserves its height so the keypad target does '
              'not jump under the user thumb');
    });

    testWidgets('necessity and satisfaction are absent from the add screen',
        (tester) async {
      // Deliberately absent: extra taps in the add path are what kill daily
      // tracking. They belong on the edit screen only (Task 14).
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      expect(find.byKey(const Key('tx-necessity')), findsNothing);
      expect(find.byKey(const Key('tx-satisfaction')), findsNothing);
    });

    testWidgets('renders right-to-left with the amount reading correctly',
        (tester) async {
      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add',
          locale: const Locale('fa'));
      expect(tester.takeException(), isNull);
      final direction = Directionality.of(
          tester.element(find.byKey(const Key('tx-amount-field'))));
      expect(direction, TextDirection.rtl);
    });
  });
}
```

- [ ] **Step 2: Run and verify failure.**

- [ ] **Step 3: Implement `AmountField`**

A `TextField` with `autofocus: true`, `keyboardType: TextInputType.number`,
`textAlign: TextAlign.center`, `style: textTheme.displaySmall`, and a single
`TextInputFormatter` that:

1. runs the raw value through `Digits.toLatin`, so Persian and Arabic-Indic
   input normalises before anything else looks at it;
2. strips group separators and any character that is not a digit, `.`, or a
   leading `-`;
3. re-groups for display through `MoneyFormatter.format` when the value parses,
   preserving the caret at the end (the field is right-aligned in LTR and the
   caret sits after the last typed digit in both directions);
4. leaves the raw text alone when it does not parse, so the user can keep
   typing through an intermediate state such as `1.` — validation happens on
   save, not on every keystroke.

The controller holds the *text*; parsing to `Money` happens once, in `save`,
through `MoneyFormatter.parse`. There is no `double` anywhere in this path.

- [ ] **Step 4: Implement `CategoryChips`**

Watches `categoryPredictorProvider`, renders up to four chips plus a "more…"
chip that opens the full category picker. The row has a fixed height of
`NimbusTokens.chipHeight + NimbusTokens.space4` reserved even while predictions
are loading, which is what the "chips arriving late do not move the amount
field" test pins. Each chip is
`key: Key('tx-chip-$categoryId')`, is a `Semantics(button: true, selected: ...)`,
and fires `HapticFeedback.selectionClick()` on selection. Archived and system
categories never appear.

- [ ] **Step 5: Implement the screen and the controller**

Layout, top to bottom: direction toggle (expense/income segmented control,
expense preselected), the amount field, the chip row, then a collapsed
"more details" section holding tags, payment method, merchant, note, and date.
The save `FilledButton` is pinned to the bottom via `bottomNavigationBar` so it
stays in the bottom third regardless of keyboard state.

`save`:

```dart
Future<void> save() async {
  final amount = _formatter.parse(state.amountText);
  if (amount == null || amount.isZero) {
    state = state.copyWith(amountError: true);
    return;
  }
  unawaited(HapticFeedback.mediumImpact());
  // Optimistic: pop first, persist behind. A SQLite insert is sub-millisecond,
  // so a spinner would be a lie about how long this takes -- and the contract
  // forbids one outright.
  _onSaved();
  await _repository.add(state.toDraft());
}
```

`_onSaved` pops the route and shows the saved snackbar. If `add` throws, the
error surfaces through the controller's state and the list shows a retry — the
write is local, so the only realistic failure is disk exhaustion, and pretending
otherwise by swallowing the exception is not acceptable.

- [ ] **Step 6: Register routes and the FAB**

```dart
const addTransactionRoute = '/add';
const transactionDetailRoute = '/tx';   // + '/:id'

final transactionRoutes = <RouteBase>[
  GoRoute(path: addTransactionRoute, name: 'tx-add',
      builder: (context, state) => AddTransactionScreen(
            initialAmount: state.uri.queryParameters['amount'],
          )),
  GoRoute(path: '$transactionDetailRoute/:id', name: 'tx-detail',
      builder: (context, state) =>
          TransactionDetailScreen(id: state.pathParameters['id']!)),
];
```

The `amount` query parameter exists for Phase 6's widget deep link. It is
accepted and parsed here so the deep link works the day the widget ships,
rather than requiring this screen to change then.

**ARB keys:** `txAddTitle` (Add expense / افزودن هزینه — reuse the existing
`addExpense` key rather than duplicating it), `txAmountLabel` (Amount / مبلغ —
reuse `amount`), `txAmountInvalid` (Enter a valid amount / مبلغ معتبر وارد کنید),
`txDirectionExpense` (Expense / هزینه), `txDirectionIncome` (Income / درآمد),
`txMoreDetails` (More details / جزئیات بیشتر), `txMerchantLabel` (Merchant /
فروشنده), `txNoteLabel` (Note / یادداشت), `txDateLabel` (Date / تاریخ),
`txPaymentMethodLabel` (Payment method / روش پرداخت), `txCategoryMore` (More… /
بیشتر…), `txSaved` (Saved / ذخیره شد), `txSaveFailed` (Could not save / ذخیره
نشد).

- [ ] **Step 7: Run everything and commit**

```bash
git tag pre-add-transaction HEAD
git add app && git commit -m "feat: add-expense screen, three taps on the golden path

The tap count is defined in the test rather than left to interpretation: FAB,
predicted chip, save, with digit entry excluded as data rather than navigation.
A future change that adds a required field fails that test, which is the reason
to write it down this way.

Amount is the only required field and an unset category resolves to the
Uncategorized system row, so no chart ever has a hole in it.

Save is optimistic and pops before the insert completes. A SQLite insert is
sub-millisecond, so a spinner would misrepresent it -- and the interaction rules
forbid one for a save outright.

Necessity and satisfaction are deliberately absent here. Extra taps in the add
path are what kill daily tracking; they live on the edit screen."
```

---

## Task 13: Transaction list screen

**Files:**
- Create: `app/lib/features/transactions/presentation/transaction_list_screen.dart`
- Create: `app/lib/features/transactions/presentation/widgets/{transaction_row,day_header,period_header,filter_sheet}.dart`
- Create: `app/lib/features/transactions/application/transaction_list_controller.dart`
- Modify: `app/lib/bootstrap/app_router.dart` (the list becomes `/`), both ARB files
- Test: `app/test/features/transactions/transaction_list_screen_test.dart`

**Interfaces produced:** `TransactionListScreen`,
`TransactionListController` (an `AsyncNotifier<TransactionListState>`) with
`loadMore`, `setPeriod`, `setSearch`, `setFilters`, `refresh`.

Cases the test must cover, beyond the four states:

```dart
  testWidgets('rows are grouped by day with a subtotal per day', (tester) async {
    // Three expenses on the 21st, one on the 20th.
    ...
    expect(find.byKey(const Key('day-header-20260821')), findsOneWidget);
    expect(find.byKey(const Key('day-subtotal-20260821')), findsOneWidget);
    expect(find.text('۱۵۰٬۰۰۰'), findsOneWidget);   // the day subtotal
  });

  testWidgets('the header shows a running month total in the active calendar',
      (tester) async {
    // A Jalali month is not a Gregorian one. With the Jalali calendar active,
    // the total covers Mordad, not August, and a transaction dated 22 August
    // (31 Mordad) is inside it while 23 August (1 Shahrivar) is not.
    ...
    expect(find.byKey(const Key('tx-month-total')), findsOneWidget);
  });

  testWidgets('loading more appends without repeating a row', (tester) async {
    // 45 rows, page size 40.
    ...
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pumpAndSettle();
    final keys = tester.widgetList<TransactionRow>(find.byType(TransactionRow))
        .map((w) => w.transaction.id).toList();
    expect(keys.toSet(), hasLength(keys.length));
    expect(keys, hasLength(45));
  });

  testWidgets('income and expense are distinguishable without colour',
      (tester) async {
    // Degenerate case D6. The sign, not the hue, carries the meaning.
    ...
    expect(find.byKey(const Key('tx-direction-icon-income')), findsOneWidget);
    expect(find.textContaining('+'), findsWidgets);
  });

  testWidgets('a forty-character merchant ellipsises on one line',
      (tester) async {
    // Degenerate case D2: never reflow the row height.
    ...
    final text = tester.widget<Text>(find.byKey(const Key('tx-merchant-$id')));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('search filters the list and survives Persian digits',
      (tester) async {
    ...
  });

  testWidgets('the empty state points at the add action rather than reading '
      'as a failure', (tester) async {
    await pumpApp(tester, seedFirstRun: true);
    expect(find.byType(NimbusEmptyState), findsOneWidget);
    await tester.tap(find.byKey(const Key('tx-empty-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tx-amount-field')), findsOneWidget);
  });
```

**Implementation notes that matter:**

- The list is a `CustomScrollView` of `SliverList`s: one `SliverPersistentHeader`
  for the period and month total, then per-day `SliverStickyHeader`-style groups
  built from the flattened page data. Grouping is computed once per page in the
  controller, not per build.
- `loadMore` fires from a `ScrollController` listener at 80% scroll extent, is
  guarded by `state.isLoadingMore` so a fling cannot issue three overlapping
  page requests, and appends into an immutable list.
- The period header uses `AppCalendar.periodContaining(today, PeriodType.month)`
  and `shiftPeriod` for the previous/next affordances, so switching to Gregorian
  in settings changes the boundaries without any other code moving.
- Day subtotals sum the *loaded* rows for that day, and the month total comes
  from `sumInRange` — a SQL aggregate over the whole month rather than over what
  happens to be loaded. Mixing those two up is how a running total silently
  becomes "the total of the first forty rows".
- Amounts in rows use `formatCompact` only when the row is width-constrained;
  the day subtotal and month total use full `format`. Never both inside one
  visual grouping.

**ARB keys:** `txListTitle` (Transactions / تراکنش‌ها), `txListEmptyTitle`
(No transactions yet / هنوز تراکنشی ثبت نشده), `txListEmptyMessage` (Log your
first expense and it will appear here. / اولین هزینه‌تان را ثبت کنید تا اینجا
نمایش داده شود.), `txListEmptyAction` (Add expense / افزودن هزینه — reuse
`addExpense`), `txListErrorTitle` (Could not load transactions / بارگذاری
تراکنش‌ها ممکن نشد), `txMonthTotal` (This month / این ماه), `txDaySubtotal`
(Day total / مجموع روز), `txSearchHint` (Search merchant or note / جست‌وجوی
فروشنده یا یادداشت), `txFilterTitle` (Filters / فیلترها),
`txFilterDirection` (Direction / نوع), `txFilterCategory` (Category /
دسته‌بندی — reuse `category`), `txFilterAll` (All / همه),
`txLoadMore` (Load more / بارگذاری بیشتر).

```bash
git tag pre-transaction-list HEAD
git add app && git commit -m "feat: paginated transaction list with day grouping and month total

The month total is a SQL SUM over the whole period, not a sum of the loaded
page. Those two are easy to confuse and the second one is wrong in a way that
looks right until someone scrolls.

Period boundaries come from the active AppCalendar, so a Jalali month is Mordad
rather than August without any other code knowing about it.

loadMore is guarded against overlapping requests, because a fling issues scroll
callbacks faster than a page can resolve."
```

---

## Task 14: Edit, delete with undo, and the reflection axes

**Files:**
- Create: `app/lib/features/transactions/presentation/transaction_detail_screen.dart`
- Create: `app/lib/features/transactions/presentation/widgets/{necessity_selector,satisfaction_selector}.dart`
- Modify: `app/lib/features/transactions/application/transaction_providers.dart`
- Modify: both ARB files
- Test: `app/test/features/transactions/transaction_detail_screen_test.dart`
- Test: `app/test/ux_rules_test.dart` — the source-level enforcement

Cases:

```dart
  testWidgets('editing an amount writes through the repository', (tester) async {
    ...
  });

  testWidgets('necessity and satisfaction are settable here', (tester) async {
    await tester.tap(find.byKey(const Key('tx-necessity-avoidable')));
    await tester.tap(find.byKey(const Key('tx-satisfaction-regret')));
    await tester.pumpAndSettle();
    final row = await db.transactionsDao.byId(id);
    expect(row!.necessity, Necessity.avoidable);
    expect(row.satisfaction, Satisfaction.regret);
  });

  testWidgets('both axes are optional and can be cleared', (tester) async {
    // Phase 3's regret matrix shows unlabelled totals separately rather than
    // dropping them, so "no answer" has to remain expressible.
    ...
    expect(row.necessity, isNull);
  });

  testWidgets('delete is soft, offers undo, and never confirms', (tester) async {
    await tester.tap(find.byKey(const Key('tx-delete')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect((await db.transactionsDao.byId(id))!.deletedAt, isNotNull);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await db.transactionsDao.byId(id))!.deletedAt, isNull);
  });

  testWidgets('twenty tags collapse to a bounded row', (tester) async {
    // Degenerate case D3.
    ...
    expect(find.byType(TagChip), findsNWidgets(4));
    expect(find.byKey(const Key('tx-tags-more')), findsOneWidget);
  });

  testWidgets('a negative amount renders its sign on the correct side in RTL',
      (tester) async {
    // Degenerate case D7.
    ...
  });
```

And the enforcement test, which is what makes the two structural rules real
rather than aspirational:

```dart
// app/test/ux_rules_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dartSources(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.endsWith('.g.dart'));

void main() {
  test('no confirmation dialog exists anywhere in the app', () {
    // "Undo, never confirm" is an interaction rule, and rules that are only
    // enforced by review come back the first time someone is in a hurry.
    final offenders = <String>[];
    for (final file in _dartSources('lib')) {
      final source = file.readAsStringSync();
      for (final pattern in ['showDialog(', 'AlertDialog(', 'CupertinoAlertDialog(']) {
        if (source.contains(pattern)) offenders.add('${file.path}: $pattern');
      }
    }
    expect(offenders, isEmpty,
        reason: 'destructive actions use nimbusUndoSnackBar:\n'
            '${offenders.join('\n')}');
  });

  test('presentation code never calls a DAO directly', () {
    // The single-write-path guarantee. A screen that reaches past the
    // repository would bypass tag usage counts and the Uncategorized default,
    // and nothing would fail until a number looked wrong months later.
    final offenders = <String>[];
    for (final file in _dartSources('lib')) {
      if (!file.path.contains('presentation')) continue;
      final source = file.readAsStringSync();
      for (final pattern in [
        'Dao.', 'categoriesDao', 'tagsDao', 'transactionsDao',
        'paymentMethodsDao', 'settingsDao',
      ]) {
        if (source.contains(pattern)) offenders.add('${file.path}: $pattern');
      }
    }
    expect(offenders, isEmpty,
        reason: 'presentation talks to repositories, not DAOs:\n'
            '${offenders.join('\n')}');
  });

  test('no raw Color literal outside nimbus_design', () {
    final offenders = <String>[];
    final literal = RegExp(r'Color\(0x');
    for (final file in _dartSources('lib')) {
      if (literal.hasMatch(file.readAsStringSync())) offenders.add(file.path);
    }
    expect(offenders, isEmpty,
        reason: 'colours come from tokens so a token-sheet swap is one file:\n'
            '${offenders.join('\n')}');
  });
}
```

Note: the colour-literal rule has one legitimate exception — the seeded category
tree carries `color` values as `int`s in the *data* layer. Those live in
`features/categories/data/default_category_tree.dart` as named references into
`NimbusTokens`/`NimbusColors`, not as hex literals, so the rule holds without an
exemption list. If that turns out to be impractical, add the file to an
explicit, commented allow-list rather than weakening the regex.

**ARB keys:** `txDetailTitle` (Transaction / تراکنش), `txEditTitle` (Edit /
ویرایش), `txDeleted` (Deleted / حذف شد), `txNecessityLabel` (Was it needed? /
لازم بود؟), `txNecessityNeeded` (Needed / لازم), `txNecessityOptional`
(Optional / اختیاری), `txNecessityAvoidable` (Avoidable / قابل اجتناب),
`txSatisfactionLabel` (How do you feel about it? / چه حسی درباره‌اش دارید؟),
`txSatisfactionGlad` (Glad / راضی), `txSatisfactionNeutral` (Neutral / خنثی),
`txSatisfactionRegret` (Regret / پشیمان), `txTagsLabel` (Tags / برچسب‌ها).

```bash
git tag pre-transaction-detail HEAD
git add app && git commit -m "feat: transaction detail with undo delete and the reflection axes

Necessity and satisfaction live here and only here. Phase 3's regret matrix
needs them and the add path cannot afford them.

Both axes stay clearable, because the regret matrix reports unlabelled totals
separately rather than dropping them, and that requires 'no answer' to be a
real state rather than an absence nobody can produce.

Adds app/test/ux_rules_test.dart, which greps the source for confirmation
dialogs, direct DAO calls from presentation, and raw colour literals. Rules
enforced only by review come back the first time someone is in a hurry."
```

---

## Task 15: Onboarding and settings screens

**Files:**
- Create: `app/lib/features/onboarding/presentation/onboarding_screen.dart`
- Create: `app/lib/features/onboarding/routes.dart`
- Create: `app/lib/features/settings/presentation/settings_screen.dart`
- Create: `app/lib/features/settings/presentation/widgets/{currency_picker,calendar_picker,locale_picker,first_day_picker,theme_picker}.dart`
- Modify: `app/lib/app.dart` — locale and theme now come from `settingsProvider`
- Modify: `app/lib/bootstrap/app_router.dart`, both ARB files
- Test: `app/test/features/onboarding/onboarding_screen_test.dart`
- Test: `app/test/features/settings/settings_screen_test.dart`

Cases:

```dart
  testWidgets('onboarding is skippable in one tap and still leaves a usable app',
      (tester) async {
    final db = await pumpApp(tester, initialLocation: '/onboarding');
    await tester.tap(find.byKey(const Key('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tx-add-fab')), findsOneWidget);
    // Defaults were already valid before the first question was answered.
    final settings = await SettingsRepository(db.settingsDao).load();
    expect(settings, AppSettings.defaults.copyWith(onboardingCompleted: true));
    expect(await db.categoriesDao.allLive(), isNotEmpty);
  });

  testWidgets('seeding failure offers a retry and leaves no half-seeded tree',
      (tester) async {
    // The only place a progress indicator is acceptable, because it is
    // genuinely doing work.
    ...
    expect(find.byType(NimbusErrorState), findsOneWidget);
    expect(await db.categoriesDao.allLive(), isEmpty);
  });

  testWidgets('changing the calendar re-renders without a restart',
      (tester) async {
    await pumpApp(tester, seedFirstRun: true, initialLocation: '/settings');
    await tester.tap(find.byKey(const Key('settings-calendar')));
    await tester.tap(find.byKey(const Key('calendar-gregorian')));
    await tester.pumpAndSettle();
    // The list header now shows a Gregorian month without the app restarting.
    ...
  });

  testWidgets('changing the locale switches direction live', (tester) async {
    await pumpApp(tester, seedFirstRun: true, initialLocation: '/settings');
    expect(Directionality.of(tester.element(find.byType(Scaffold))),
        TextDirection.rtl);
    await tester.tap(find.byKey(const Key('settings-locale')));
    await tester.tap(find.byKey(const Key('locale-en')));
    await tester.pumpAndSettle();
    expect(Directionality.of(tester.element(find.byType(Scaffold))),
        TextDirection.ltr);
  });

  testWidgets('a failed write reverts the control rather than lying',
      (tester) async {
    // Screen contract 3.6: the UI must not show a value the database does not
    // hold.
    ...
    expect(find.text('Jalali'), findsOneWidget);
  });

  testWidgets('a corrupt setting surfaces with a reset action', (tester) async {
    await db.settingsDao.put(SettingsKeys.themeMode, 'chartreuse');
    ...
    expect(find.byType(NimbusErrorState), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-reset')));
    await tester.pumpAndSettle();
    expect(find.byType(NimbusErrorState), findsNothing);
  });

  testWidgets('entitlement labels read as a gift, not a countdown',
      (tester) async {
    expect(find.text('Pro — free during early access'), findsOneWidget);
  });
```

Settings also carries, gated behind `kDebugMode` and never present in a release
build, a **"Seed 5,000 demo transactions"** action. Task 16 needs a device with
that data to measure the 60 fps criterion, and building it as a debug-only
settings entry is the difference between measuring it and writing "not
measured" in the definition of done.

**ARB keys:** `onboardingWelcomeTitle` (Welcome to NimbuStats / به نیمبوستتس خوش
آمدید), `onboardingWelcomeBody` (A few quick choices — or skip and start
logging. / چند انتخاب کوتاه — یا رد کنید و شروع کنید.), `onboardingCurrencyTitle`
(Currency / واحد پول), `onboardingCalendarTitle` (Calendar / تقویم),
`onboardingLocaleTitle` (Language / زبان), `onboardingSeeding` (Setting up… /
در حال آماده‌سازی…), `onboardingSeedFailed` (Setup did not finish / آماده‌سازی
کامل نشد), `onboardingFinish` (Start / شروع), `onboardingSkip` (Skip / رد کردن),
`settingsTitle` (Settings / تنظیمات), `settingsCurrency` (Currency / واحد پول),
`settingsCalendar` (Calendar / تقویم), `settingsCalendarJalali` (Jalali /
شمسی), `settingsCalendarGregorian` (Gregorian / میلادی), `settingsLocale`
(Language / زبان), `settingsFirstDayOfWeek` (First day of week / اولین روز
هفته), `settingsTheme` (Theme / پوسته), `settingsThemeSystem` (System /
سیستم), `settingsThemeLight` (Light / روشن), `settingsThemeDark` (Dark /
تیره), `settingsCategories` (Categories / دسته‌بندی‌ها — reuse
`categoryManagerTitle`), `settingsProBadge` (Pro — free during early access /
حرفه‌ای — رایگان در دسترسی زودهنگام), `settingsResetFailed` (Could not save that
change / این تغییر ذخیره نشد), `settingsReset` (Reset settings / بازنشانی
تنظیمات), `settingsDebugSeed` (Seed 5,000 demo transactions / ساخت ۵۰۰۰ تراکنش
نمونه).

```bash
git tag pre-onboarding-settings HEAD
git add app && git commit -m "feat: onboarding and settings, with live locale and calendar switching

Onboarding is skippable in one tap and the defaults are already valid before the
first question is answered, so nothing here can block reaching the add screen.
That is the whole design: a first-run flow that can be skipped is a first-run
flow people actually complete.

A failed settings write reverts its control rather than leaving the UI showing
a value the database does not hold, and a setting the database holds but cannot
parse surfaces as an error with a reset action instead of being papered over
with a default.

Adds a debug-only action that seeds 5,000 demo transactions, which is what makes
the 60 fps criterion in Task 16 measurable rather than aspirational."
```

---

## Task 16: UX budget verification, definition-of-done gate, and the phase tag

No new features. This task proves the phase met its own criteria and leaves the
evidence where the next phase can find it.

- [ ] **Step 1: Run the full definition-of-done gate**

```bash
dart analyze --fatal-infos
dart test test/architecture_test.dart
cd packages/nimbus_domain && dart test
cd ../nimbus_data && dart test
cd ../nimbus_design && flutter test
cd ../../app && flutter test
```

Every one must be green. Record the test counts in the report.

- [ ] **Step 2: Verify ARB parity and localization coverage**

The existing `both ARB files define the same keys` test covers parity. Add one
more assertion to `app/test/localization_test.dart`:

```dart
  test('no ARB value is left as its English text in the Persian bundle', () {
    // gen_l10n does not fail on an untranslated string, so a key copied across
    // and forgotten looks fine until a Farsi user sees English.
    final en = valuesOf('lib/l10n/app_en.arb');
    final fa = valuesOf('lib/l10n/app_fa.arb');
    final untranslated = <String>[];
    for (final key in en.keys) {
      // Brand names and format-only strings legitimately match.
      const allowed = {'appTitle', 'tagMoreCount'};
      if (allowed.contains(key)) continue;
      if (en[key] == fa[key]) untranslated.add(key);
    }
    expect(untranslated, isEmpty,
        reason: 'these keys are still English in the fa bundle: $untranslated');
  });
```

- [ ] **Step 3: Verify the structural claims the brief makes**

```bash
# TransactionRepository is the only insert path.
grep -rn "insertTransaction" app/lib | grep -v "data/transaction_repository.dart"
# Expected: no output.

# No DAO reached from a widget.
cd app && flutter test test/ux_rules_test.dart
```

- [ ] **Step 4: Build the release-mode APK and hand the operator the runbook**

```bash
cd app && flutter build apk --profile
```

Then give the operator this runbook verbatim. These four criteria cannot be
measured on this machine, and the phase is not done until the numbers are
recorded here.

> **1. Install the profile build**
> ```bash
> adb devices                      # confirm exactly one device
> adb install -r build/app/outputs/flutter-apk/app-profile.apk
> ```
>
> **2. Cold start to a usable list (target: < 1 s)**
> ```bash
> adb shell am force-stop com.nimbustats.app
> adb shell am start-activity -W -n com.nimbustats.app/.MainActivity
> ```
> Read `TotalTime` from the output. Run it five times and report all five —
> the first run after install is not representative.
>
> **3. Seed the performance data**
> Open Settings → "Seed 5,000 demo transactions", wait for the snackbar.
>
> **4. 60 fps on the seeded list (target: no frame over 16.7 ms)**
> ```bash
> flutter run --profile -d <device-id>
> ```
> Scroll the transaction list hard for ten seconds, then in the DevTools
> performance view read the worst frame time and the count of janky frames.
> Report both numbers.
>
> **5. Any expense in ≤ 5 seconds**
> Stopwatch, from tapping the FAB to seeing the row in the list. Three
> attempts, report all three.
>
> **6. Repeat purchase in ≤ 3 taps**
> Already asserted by a widget test, but confirm it feels true on hardware —
> if the predicted chip you want is not among the four, the test passes and
> the criterion does not.

- [ ] **Step 5: Record the measurements in this plan**

Fill this table in with the operator's numbers before tagging. An empty cell
means the phase is not done.

| Criterion | Target | Measured | Verified by |
|---|---|---|---|
| Repeat purchase | ≤ 3 taps | **3 taps** (software) | `add_transaction_screen_test.dart` — "a repeat purchase takes three taps" |
| Any expense | ≤ 5 s | **not measured — blocked by D1** | device stopwatch |
| Cold start to usable list | < 1 s | **not measured — blocked by D1** | `am start -W` ×5 |
| List frame times | 60 fps at 5,000 rows | **not measured — blocked by D1** | DevTools |
| Amount is the only required field | pass | **pass** | `add_transaction_screen_test.dart` |
| Keypad opens focused on amount | pass | **pass** | `add_transaction_screen_test.dart` |
| No spinner on save | pass | **pass** | `add_transaction_screen_test.dart` |
| Undo, never confirm | pass | **pass** | `ux_rules_test.dart` — source-level, whole `lib/` |
| Primary actions in bottom third | pass | **pass** | `add_transaction_screen_test.dart` |
| Haptic on capture | pass | **pass** | `add_transaction_screen_test.dart` |

**Six of ten measured. The remaining four need hardware and are blocked by
deferred item D1** — Google Maven is unreachable from this network, so the
Android toolchain has never resolved AGP and no APK has ever been built. Those
four are the reason `phase-1-complete` is not tagged: the phase's own definition
of done requires them measured on a device rather than on an emulator, and
writing "probably fine" in this table would defeat the purpose of the table.

Rechecked 2026-08-24: `maven.google.com/androidx/core/core/1.13.1/core-1.13.1.pom`
still returns 404 with the ~1449-byte interception body. The moment that returns
200, the runbook in Step 4 is what closes this out.

### Definition-of-done gate, run 2026-08-24

| Suite | Result |
|---|---|
| `dart analyze --fatal-infos` (workspace) | clean |
| `flutter analyze` (`app`, `nimbus_design`) | clean |
| `test/architecture_test.dart` | 4 passed |
| `nimbus_domain` | 67 passed |
| `nimbus_data` | 80 passed |
| `nimbus_design` | 20 passed |
| `app` | 171 passed |
| **Total** | **342 passed** |

Structural claims re-verified by grep and by test, not by review:

- `insertTransaction` appears nowhere in `app/lib` outside
  `data/transaction_repository.dart` — the single-write-path guarantee holds.
- `ux_rules_test.dart` proves no confirmation dialog, no DAO reference from a
  presentation file, no raw `Color(0x…)` literal outside `nimbus_design`, and
  no `drift`/`sqlite3` import anywhere in the app package.
- Schema stayed at **v1**. Phase 0 created every table Phase 1 needed, exactly
  as the brief predicted; no version was consumed from the v2–v9 reservation.

- [ ] **Step 6: Reconcile the screen contract**

Read `docs/superpowers/screen-contract.md` §3.1–3.6 against what actually
shipped, and edit any entry where reality diverged — the contract is a working
document and a stale one misleads Phase 3. Note each edit in the commit body.

- [ ] **Step 7: Update the status board and the schema registry**

In `docs/phases/README.md`, set Phase 1 to **Complete** with today's date, and
move Phases 2, 3, 4 from "Blocked on 1" to "Ready".

In `docs/phases/CONVENTIONS.md` §2, leave Phase 1's "Used" column as `—` if no
schema version was consumed — which is the expected outcome — or record the
version and the migration if one was.

- [ ] **Step 8: Tag the phase**

```bash
git add docs app
git commit -m "docs: record Phase 1 UX measurements and mark the phase complete

All ten acceptance criteria measured, with the four hardware ones taken on a
real device rather than an emulator. Numbers are in the plan rather than in a
commit message so the next phase can compare against them.

Schema stayed at v1: Phase 0 created every table Phase 1 needed, exactly as the
brief predicted."

git tag phase-1-complete
git checkout main && git merge --ff-only phase/1-expenses
```

- [ ] **Step 9: Report**

Phase 1 unblocks Phases 2B, 3, 4, and 7 — the widest fan-out in the project.
Say so in the final report, along with anything discovered that makes a later
brief wrong.

---

## Self-review against the brief

Checked after writing, per the writing-plans skill.

**Scope coverage.** Every "In" item from the brief maps to a task: category
manager (5, 6), tag manager (7, 8), payment methods (9), add flow (12), edit and
delete with undo (14), transaction list with pagination, grouping, subtotals,
month total, search and filters (13), income entry (12, via the direction
toggle), necessity × satisfaction on edit only (14), first-run seeding and
settings bootstrap (3, 4, 15), settings (15). The five named "Interfaces
produced" are Tasks 10, 10, 11, 10, and 12 respectively.

**Known traps.** Pagination from day one — Task 10, with a 5,000-row test.
The Uncategorized system row — Task 4 creates it, Task 5 guards it, Task 12
defaults to it. Subtree move rebuilding paths — Task 5 re-asserts it at the DAO
level, Task 6 drives it through the UI. Persian and Latin digits in the amount
field — Task 12. Money parsing never touching `double` — Task 10 and Task 12.
Archive is not delete — Tasks 5, 7, 9 each assert that archived rows still
resolve for historical transactions. Tag create-on-the-fly — Tasks 7 and 8.
No chart — nothing in this plan draws one; the month total is a number.

**Gaps I am aware of and have chosen to leave.**
1. The `error` state on the add screen covers a rejected parse and a failed
   write; it does not cover a category that was deleted in another tab between
   opening the screen and saving. Single-device app, no tabs, so the window does
   not exist in Phase 1.
2. Reorder is sibling-scoped. Cross-level reordering by drag is not built;
   "Move to…" covers it and is more accessible. If the operator wants drag
   re-parenting, it is a follow-on, not a gap in this plan.
3. Frame-time verification is a device measurement, not an automated test.
   There is no honest way to assert 60 fps in a widget test, and asserting a
   wall-clock budget in CI would be a flaky test pretending to be a guarantee.
