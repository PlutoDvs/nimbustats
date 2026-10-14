# Deferred sweep, phases 0–6 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clear every open DEFERRED item that belongs to phases 0–6 — fixed and verified, or closed with a recorded reason — so Phase 7 starts on an empty backlog.

**Architecture:** No new subsystem. Each task is one contained fix in existing code: Dart (app, `nimbus_domain`, `nimbus_data`, the root architecture test), native Kotlin (widget, notifications), and on-device checks. One commit per item on `fix/deferred-0-6`, each test-first with a `pre-<slug>` rollback tag.

**Tech Stack:** Flutter 3.47.1 / Dart 3.13.1, Riverpod 3, drift, fl_chart 1.2.0, gen-l10n (en + fa); Kotlin, JUnit4 host tests; adb against the Galaxy A53 (Android 16); an Android 11 emulator (API 30, x86_64, WHPX).

**Spec:** `docs/superpowers/specs/2026-10-14-deferred-0-6-sweep-design.md`

## Global Constraints

- Flutter 3.47.1 / Dart 3.13.1; `pubspec.lock` is committed; no new dependencies (no Robolectric).
- The app suite runs with `flutter test --concurrency=4`; the default concurrency hangs on loopback semaphore timeouts.
- JUnit host tests import no `android.*` and no `org.json`.
- Every user-visible string goes in both `app_en.arb` and `app_fa.arb`; Persian text uses Persian digits where the app's digit setting applies.
- Schema version does not change in this sweep.
- Commit messages: `type(scope): summary`, with the WHY in the body, ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Before each implementation commit: `git tag pre-<slug>` on its parent. Never force-push `main`; merge with `--ff-only`.
- The A53 is the operator's daily phone: no adb taps, installs or settings changes until the operator says it is free and unlocked; restore any setting changed for a check.
- Git Bash heredocs eat backslashes: write edit scripts with regexes to a file, never inline.
- drift stream `.first` hangs in widget tests: read streams via `tester.runAsync`; app code uses one-shot DAO reads.

## Review Focus

1. **An absurdly long amount typed anywhere money is entered** (add expense, transaction detail, goal editor): rejected as invalid, never a crash or a silently wrong value. Pinned in Task 4 (parse) and its goal-editor widget test.
2. **An uncaught async error in the background drain engine** (not only the UI engine) is reported, not lost. Pinned in Task 2 (the hook is installed in both entry points).
3. **A tag edit whose link write fails**: the transaction's amount, stamp and tags are all unchanged afterwards. Pinned in Task 5.
4. **Persian locale for every new string** (`<1 min`, the done summary, full weekday names): reads in Persian with Persian digits. Pinned by the fa variants in Tasks 11–12.
5. **The add-expense dialog with four long category names, in Persian (RTL) and in dark mode**: all four chips visible, nothing clipped. Pinned by the device check in Tasks 20–21.

---

## Execution notes

Read these before Task 1. They apply to every task.

**Order and anchors.** Run the tasks in numeric order (12a → 12b → 12c, 15a → 15b → 15c). Line numbers are as of `fd6b70f` and drift as earlier tasks land: Tasks 10, 11, 12a and 12c all edit `tracker_insights.dart` and `tracker_insights_test.dart`; Task 3 removes an import from `add_transaction_screen_test.dart`. Every edit is anchored on code text and test names — re-grep the anchor, never trust a line number blindly.

**Commit bodies start with `Dnn:`.** Task 25 finds each item's hashes and dates with `git log --grep="^Dnn:"`. The money-parse fix uses `D25:` (found in its triage). Stage exact paths: three untracked `bash.exe.stackdump` files sit in the tree and are not ignored.

**Rollback slugs are unique.** Each task names its own `pre-<slug>`; existing tags such as `pre-widget-buffer`, `pre-frame-timings`, `pre-drain-job` and `pre-expense-dialog` are taken. If `git tag` refuses, stop and report — do not reuse or move a tag.

**Kinds of RED.**
- *Compile-error RED:* Tasks 2, 9 and 10 fail first because the new symbol does not exist. Task 9's behavioural proof is its mutation step.
- *Characterization tests, green on first run by design:* Task 4's boundary test, Task 5's stamp test, Task 7's `fromJson` cases, Task 12c's Persian case, and Tasks 13, 14 and 15c. They pin code DEFERRED records as correct. Each carries a **mutation check**: break the code, see the test fail, then revert with `git checkout -- <file>` — safe only on a tree with nothing else uncommitted.
- Everything else must be RED for the stated reason before implementing. A RED for a different reason is a stop-and-report.

**When a "should pass" test fails for real** (most likely Task 15c's 2× text on the goal cards): do not adjust the test. Record it as a new DEFERRED item (Task 25 Step 3b) and report it.

**Task 15c #51:** first try deleting `muteReports` and both its calls. If both editor-state tests still pass, keep the deletion and skip the selective mute.

**Analysis gate:** `dart analyze --fatal-infos` from the repo root (CI's gate) in each task's broader step; Task 25 also runs `flutter analyze` in `app` (the spec's wording).

**Device tasks need the operator.** Tasks 21–23 run on the A53 only after the operator confirms it is free and unlocked. The operator also:
- resizes the widget by hand (D26 — adb cannot build the options Bundle);
- allows night-mode, app-language and reminder-time changes, each restored afterwards;
- allows `setprop debug.choreographer.skipwarning 1` (non-persistent) for D30;
- deletes the test expenses afterwards (1 from D17, 10 from D30);
- decides D30 keep-or-discard, D16 if 8.33 ms is not met, and D33's fix option if a row clips;
- confirms the final fast-forward of `main`.

**Out of scope, recorded instead:** two defects found while planning — the transaction detail's silent skip of an unreadable amount, and `TransactionRepository.add`'s non-atomic writes — become D37 and D38 in Task 25 Step 3b.

---


> Commands are POSIX shell (Git Bash), run from the repo root
> `C:\Users\nimae\Desktop\nimbustats`. The app suite always runs with
> `--concurrency=4` (it hangs at the default). Never `git add -A`: the tree
> carries untracked `bash.exe.stackdump` files.

### Task 1: Lock-screen wording after F1 (D35)

**Files:**
- Modify: `app/lib/features/notifications/data/notification_prefs.dart:27-28`
- Modify: `app/test/features/notifications/alert_router_test.dart:93-94`

**Interfaces:** Consumes none. Produces none (comment and test-name wording only).

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-lock-screen-wording
```

- [ ] **Step 2: Edit the wording**

`app/lib/features/notifications/data/notification_prefs.dart`, before (lines 27-28):

```dart
  /// Goal names and amounts in alert notifications. The lock screen gets the
  /// discreet text either way.
  final bool showDetails;
```

after:

```dart
  /// Goal names and amounts in alert notifications. The discreet text is the
  /// public version, which Android shows on a lock screen set to hide
  /// sensitive content; the phone's own setting decides.
  final bool showDetails;
```

`app/test/features/notifications/alert_router_test.dart`, before (lines 93-94):

```dart
  test('with details on, the text is the full alert; the lock screen still '
      'gets the discreet one', () async {
```

after:

```dart
  test('with details on, the text is the full alert; the public version, for '
      'a lock screen that hides sensitive content, stays discreet', () async {
```

- [ ] **Step 3: Run the alert router test**

```bash
(cd app && flutter test test/features/notifications/alert_router_test.dart)
```

Expected: `All tests passed!` (no assertion changed).

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/notifications/data/notification_prefs.dart app/test/features/notifications/alert_router_test.dart
git commit -m "$(cat <<'EOF'
chore(notifications): say the lock screen follows the phone's setting

D35: 9624bb1 made the lock screen follow Android's own lock-screen
setting (an app cannot set a channel's lock-screen visibility), but the
showDetails comment still said the lock screen gets the discreet text
either way, and the alert router test's name still promised it. Both now
say what is true: the discreet text is the public version, which Android
shows on a lock screen set to hide sensitive content.

Wording only; alert_router_test.dart passes unchanged.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Uncaught errors are reported (D12)

**Files:**
- Create: `app/lib/bootstrap/error_hooks.dart`
- Modify: `app/lib/main.dart:7-9` (imports), `:22-23` (body)
- Modify: `app/lib/drain_main.dart:7-8` (imports), `:21-22` (body)
- Test: `app/test/bootstrap/error_hooks_test.dart` (new)

**Interfaces:**
- Consumes: `FlutterError.reportError`, `FlutterErrorDetails`, `ErrorDescription`, `PlatformDispatcher` (all from `package:flutter/foundation.dart`; foundation re-exports `dart:ui`'s `PlatformDispatcher`).
- Produces: `void installErrorHooks(String library)` in `package:nimbustats/bootstrap/error_hooks.dart`.

Verified fact this task rests on: in `flutter_test`, `PlatformDispatcher.instance` is dart:ui's real `PlatformDispatcher` (its `onError` starts `null` in a plain `test`). Only `tester.binding.platformDispatcher` is the `TestPlatformDispatcher` wrapper, and its `onError` setter is a no-op (`C:\dev\flutter\packages\flutter_test\lib\src\window.dart:915-917` reads instead of assigning; confirmed by a probe). So the hook must set `PlatformDispatcher.instance.onError`, and the test reads it back from the same place and invokes it.

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-error-hooks
```

- [ ] **Step 2: Write the failing test**

Create `app/test/bootstrap/error_hooks_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbustats/bootstrap/error_hooks.dart';

/// D12: an error nothing caught is reported, not lost.
void main() {
  test('an uncaught error is reported under the library and marked handled',
      () {
    // dart:ui's own dispatcher. The test binding's wrapper drops an onError
    // assignment, so a hook set through it would never run here.
    final dispatcher = PlatformDispatcher.instance;
    final previousHook = dispatcher.onError;
    addTearDown(() => dispatcher.onError = previousHook);
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);

    installErrorHooks('nimbustats');
    final error = StateError('a write nobody awaited');
    final stack = StackTrace.current;

    expect(dispatcher.onError!(error, stack), isTrue);
    expect(reported, hasLength(1));
    expect(reported.single.library, 'nimbustats');
    expect(reported.single.exception, same(error));
    expect(reported.single.stack, same(stack));
  });
}
```

- [ ] **Step 3: Run it, confirm RED**

```bash
(cd app && flutter test test/bootstrap/error_hooks_test.dart)
```

Expected: compilation fails — `Error: Error when reading 'lib/bootstrap/error_hooks.dart'` and `Method not found: 'installErrorHooks'`.

- [ ] **Step 4: Implement**

Create `app/lib/bootstrap/error_hooks.dart`:

```dart
import 'package:flutter/foundation.dart';

/// Reports every error this isolate leaves uncaught through
/// [FlutterError.reportError] under [library] (D12), the channel
/// `reportingFailure` already uses. That is logcat until Phase 8 picks crash
/// reporting; nothing is persisted.
///
/// Framework errors already reach [FlutterError.onError]. This catches the
/// rest: a write rethrown from an event handler, an error in a future nothing
/// awaited. Each engine runs its own isolate, so each entry point installs
/// its own.
void installErrorHooks(String library) {
  PlatformDispatcher.instance.onError = (error, stack) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: library,
      context: ErrorDescription('and nothing caught it'),
    ));
    // Handled: reported once here, not printed again by the engine.
    return true;
  };
}
```

`app/lib/main.dart`, before (lines 7-9 and 22-23):

```dart
import 'app.dart';
import 'bootstrap/database_provider.dart';
import 'bootstrap/provider_retry.dart';
```

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
```

after:

```dart
import 'app.dart';
import 'bootstrap/database_provider.dart';
import 'bootstrap/error_hooks.dart';
import 'bootstrap/provider_retry.dart';
```

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHooks('nimbustats');

  final dir = await getApplicationDocumentsDirectory();
```

`app/lib/drain_main.dart`, before (lines 7-8 and 21-23):

```dart
import 'bootstrap/database_provider.dart';
import 'bootstrap/provider_retry.dart';
```

```dart
Future<void> drainMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final channel = OutsideChannel();
```

after:

```dart
import 'bootstrap/database_provider.dart';
import 'bootstrap/error_hooks.dart';
import 'bootstrap/provider_retry.dart';
```

```dart
Future<void> drainMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The drain job boots its own engine, so this isolate needs its own hook.
  installErrorHooks('widget drain');
  final channel = OutsideChannel();
```

- [ ] **Step 5: Run it, confirm GREEN**

```bash
(cd app && flutter test test/bootstrap/error_hooks_test.dart)
```

Expected: `All tests passed!`

- [ ] **Step 6: Broader suite**

```bash
(cd app && flutter test --concurrency=4)
dart analyze --fatal-infos
```

Expected: all app tests pass; `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/bootstrap/error_hooks.dart app/lib/main.dart app/lib/drain_main.dart app/test/bootstrap/error_hooks_test.dart
git commit -m "$(cat <<'EOF'
fix(app): an uncaught error is reported, not lost

D12: nothing installed PlatformDispatcher.instance.onError, so an error
no handler caught (a rethrown write, a future nobody awaited) reached
only the engine's default print. installErrorHooks routes it to
FlutterError.reportError under the entry point's library, the channel
reportingFailure already uses, and marks it handled. main() installs it
as 'nimbustats'; drainMain as 'widget drain', because the drain job
boots its own engine and isolate.

Logcat only until Phase 8 picks crash reporting (operator decision
2026-10-14); nothing is persisted. The hook sets dart:ui's dispatcher:
flutter_test's TestPlatformDispatcher drops an onError assignment, so a
hook set through the binding would work on a phone and vanish in tests.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Phase 1's haptics play on the A53 (D17)

**Files:**
- Modify: `app/lib/features/transactions/presentation/add_transaction_screen.dart:84-85`
- Modify: `app/lib/features/transactions/presentation/widgets/category_chips.dart:79-81`
- Test: `app/test/features/transactions/add_transaction_screen_test.dart` — line 4 (import removed), line 15 (import added), lines 215-234 (test rewritten), new test after it

**Interfaces:**
- Consumes: `List<String> captureHaptics(WidgetTester tester)` from `app/test/features/trackers/support/tracker_fixture.dart:117` (maps `HapticFeedback.vibrate()`'s null argument to `'vibrate'`); `seedRepeatPurchases` and `everything` already in the test file.
- Produces: none.

Verified today (probe): save sends `['HapticFeedbackType.mediumImpact']`, a chip tap `['HapticFeedbackType.selectionClick']`; FAB, button and chip taps send no other `HapticFeedback.vibrate` call.

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-expense-haptics
```

- [ ] **Step 2: Write the failing test**

In `app/test/features/transactions/add_transaction_screen_test.dart`:

Remove line 4 (`SystemChannels` was its only use; `TextInputType` comes through `material.dart`, which re-exports it):

```dart
import 'package:flutter/services.dart';
```

After line 15 (`import '../../support/harness.dart';`) add:

```dart
import '../trackers/support/tracker_fixture.dart' show captureHaptics;
```

Replace the test at lines 215-234 ("save fires a haptic") with these two tests (same place, inside `group('the golden path', ...)`):

```dart
    testWidgets('save fires a haptic', (tester) async {
      // D17: the A53 (Android 15) drops mediumImpact as "vibration absent";
      // vibrate() is the one haptic it plays.
      final haptics = captureHaptics(tester);

      await pumpApp(tester, seedFirstRun: true, initialLocation: '/add');
      await tester.enterText(find.byKey(const Key('tx-amount-field')), '1000');
      await tester.tap(find.byKey(const Key('tx-save')));
      await tester.pumpAndSettle();
      expect(haptics, ['vibrate']);
    });

    testWidgets('a category chip fires a haptic', (tester) async {
      // D17: selectionClick is silent on the A53 for the same reason.
      final haptics = captureHaptics(tester);
      final db = await pumpApp(tester, seedFirstRun: true);
      await seedRepeatPurchases(db, categoryId: 'seed-food-coffee');

      await tester.tap(find.byKey(const Key('tx-add-fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tx-chip-seed-food-coffee')));
      await tester.pumpAndSettle();

      expect(haptics, ['vibrate']);
      expect(await db.transactionsDao.pageAfter(range: everything, limit: 50),
          hasLength(5), reason: 'the chip alone saves nothing');
    });
```

- [ ] **Step 3: Run it, confirm RED**

```bash
(cd app && flutter test test/features/transactions/add_transaction_screen_test.dart --plain-name "haptic")
```

Expected: both fail —

```
Expected: ['vibrate']
  Actual: ['HapticFeedbackType.mediumImpact']
```

and

```
Expected: ['vibrate']
  Actual: ['HapticFeedbackType.selectionClick']
```

- [ ] **Step 4: Implement**

`app/lib/features/transactions/presentation/add_transaction_screen.dart`, before (lines 84-85):

```dart
    // Confirms the capture without the user waiting to look at the screen.
    unawaited(HapticFeedback.mediumImpact());
```

after:

```dart
    // Confirms the capture without the user waiting to look at the screen.
    // vibrate(): the one haptic a Galaxy A53 on Android 15 plays; it drops
    // the impact constants as "vibration absent" (D17).
    unawaited(HapticFeedback.vibrate());
```

`app/lib/features/transactions/presentation/widgets/category_chips.dart`, before (lines 79-81):

```dart
                // Confirms the tap without the user looking up from the
                // keypad, which is the point of a chip row at all.
                unawaited(HapticFeedback.selectionClick());
```

after:

```dart
                // Confirms the tap without the user looking up from the
                // keypad, which is the point of a chip row at all. vibrate():
                // the A53 drops selectionClick as "vibration absent" (D17).
                unawaited(HapticFeedback.vibrate());
```

- [ ] **Step 5: Run it, confirm GREEN**

```bash
(cd app && flutter test test/features/transactions/add_transaction_screen_test.dart)
```

Expected: `All tests passed!`

- [ ] **Step 6: Broader suite**

```bash
(cd app && flutter test --concurrency=4)
dart analyze --fatal-infos
```

Expected: all pass; `No issues found!` (this also proves the removed `services.dart` import is not needed).

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/transactions/presentation/add_transaction_screen.dart app/lib/features/transactions/presentation/widgets/category_chips.dart app/test/features/transactions/add_transaction_screen_test.dart
git commit -m "$(cat <<'EOF'
fix(transactions): the save and chip haptics play on the A53

D17: Samsung's Android 15 on the Galaxy A53 drops mediumImpact and
selectionClick as "vibration absent", so saving an expense and picking
a category chip were silent there. Both now call
HapticFeedback.vibrate(), the one constant the phone plays, as the
tracker taps have since Phase 4. The system touch-feedback setting
still governs it (D18, closed).

Tests: a save and a chip tap each send exactly one vibrate(). The
logcat check on the A53 follows with the device work.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: An amount too large to hold parses to null (D25 triage: money parse overflow)

**Files:**
- Modify: `packages/nimbus_domain/lib/src/money/money_format.dart:16-18` (new constant after), `:83`, `:96`
- Test: `packages/nimbus_domain/test/money/money_format_test.dart:124-127` (extend "rejects junk", add one test after it)
- Test: `app/test/features/goals/goal_editor_screen_test.dart` — new test after "a blank name says so and keeps Save disabled" (ends line 225)

**Interfaces:**
- Consumes: `Currency.minorUnitsPerMajor`.
- Produces: `Money? MoneyFormatter.parse(String input)` now returns `null` (never throws, never wraps) when the whole part is `>= 0x7FFFFFFFFFFFFFFF ~/ currency.minorUnitsPerMajor`. `formatInput` inherits this (it returns unparseable input as typed).

What happens today (verified by a probe): typing twenty 9s into a cap's target throws `FormatException: Positive input exceeds the limit of integer` twice — once "while applying input formatters" (`AmountInputFormatter` → `formatInput` → `parse`) and once "building _GoalForm" (`goalEditorErrors` → `_targetOf` → `parse`) — and the form becomes an `ErrorWidget`. A USD whole part of `99999999999999999` wraps to `Money(-8446744073709551716)`.

Callers checked for a null result:
- `AddTransactionController.validate()` (`add_transaction_controller.dart:124-129`): null → `amountError: true`, returns null. Safe today; it only ever threw via the formatter, which this fix covers.
- `transaction_detail_screen.dart:174-178`: null (or zero) skips `setAmount` and still saves the note. No throw. It is a pre-existing silent drop for any unparseable amount (see the notes); not changed here.
- `goal_editor_controller.dart:198-199`: null → `targetInvalid` → "Enter a number".

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-money-parse-overflow
```

- [ ] **Step 2: Write the failing tests**

`packages/nimbus_domain/test/money/money_format_test.dart`, replace lines 124-127:

```dart
    test('rejects junk rather than guessing', () {
      expect(toman.parse('abc'), isNull);
      expect(toman.parse(''), isNull);
    });
```

with:

```dart
    test('rejects junk rather than guessing', () {
      expect(toman.parse('abc'), isNull);
      expect(toman.parse(''), isNull);
      // Too large to hold in minor units (D25 triage). int.parse threw on
      // these, inside the goal editor's build; a 17-digit dollar amount
      // wrapped silently once scaled to cents.
      expect(toman.parse('9' * 20), isNull);
      expect(toman.parse('9223372036854775808'), isNull);
      expect(usd.parse('99999999999999999'), isNull);
    });

    test('the largest amounts that fit still parse', () {
      expect(toman.parse('9223372036854775806'),
          const Money(9223372036854775806));
      expect(usd.parse('92233720368547757.99'),
          const Money(9223372036854775799));
    });
```

`app/test/features/goals/goal_editor_screen_test.dart`, insert after line 225 (the end of "a blank name says so and keeps Save disabled"):

```dart

  testWidgets('a target too large to hold says so; the form stays up', (
    tester,
  ) async {
    // D25 triage: int.parse threw inside build, and the form became an
    // ErrorWidget.
    await openNew(tester);
    await choose(tester, GoalKind.spendingCap);
    await tester.enterText(find.byKey(const Key('tx-amount-field')), '9' * 20);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Enter a number'), findsOneWidget);
    expect(save(tester), isNull);
  });
```

- [ ] **Step 3: Run it, confirm RED**

```bash
(cd packages/nimbus_domain && dart test test/money/money_format_test.dart)
(cd app && flutter test test/features/goals/goal_editor_screen_test.dart --plain-name "too large")
```

Expected:
- "rejects junk rather than guessing" fails with `FormatException: Positive input exceeds the limit of integer`. "the largest amounts that fit still parse" PASSES already (it guards against over-rejecting; both values fit today).
- The goal editor test fails at the first expect:
  `Expected: null  Actual: 'Multiple exceptions (2) were detected during the running of the current test, and at least one was unexpected.'`, with the two `FormatException` reports above it.

- [ ] **Step 4: Implement**

`packages/nimbus_domain/lib/src/money/money_format.dart`, after line 18 (`static const _compactSuffixes = ['K', 'M', 'B'];`) add:

```dart

  /// The largest int, 2^63 - 1.
  static const _maxInt = 0x7FFFFFFFFFFFFFFF;
```

Before (line 83):

```dart
  /// Returns null for input that is not a number. Never guesses.
```

after:

```dart
  /// Returns null for input that is not a number, or an amount too large to
  /// hold in minor units. Never guesses.
```

Before (line 96):

```dart
    final major = parts[0].isEmpty ? 0 : int.parse(parts[0]);
```

after:

```dart
    final major = parts[0].isEmpty ? 0 : int.tryParse(parts[0]);
    // Below this bound whole * minorUnitsPerMajor + fraction always fits an
    // int. Above it int.parse threw (inside the goal editor's build) or the
    // product wrapped silently, so it is refused like any other non-amount.
    if (major == null || major >= _maxInt ~/ currency.minorUnitsPerMajor) {
      return null;
    }
```

(Line 106 `final total = major * currency.minorUnitsPerMajor + minor;` is unchanged; `major` is promoted to `int` by the check.)

- [ ] **Step 5: Run it, confirm GREEN**

```bash
(cd packages/nimbus_domain && dart test test/money/money_format_test.dart)
(cd app && flutter test test/features/goals/goal_editor_screen_test.dart)
```

Expected: `All tests passed!` for both.

- [ ] **Step 6: Broader suite**

```bash
(cd packages/nimbus_domain && dart test)
(cd app && flutter test --concurrency=4)
dart analyze --fatal-infos
```

Expected: all pass; `No issues found!` (the `0x7FFFFFFFFFFFFFFF` literal analyzes clean — probed).

- [ ] **Step 7: Commit**

```bash
git add packages/nimbus_domain/lib/src/money/money_format.dart packages/nimbus_domain/test/money/money_format_test.dart app/test/features/goals/goal_editor_screen_test.dart
git commit -m "$(cat <<'EOF'
fix(money): an amount too large to hold parses to null, not a throw

D25: Found in the D25 triage. MoneyFormatter.parse int.parse'd the whole
part: a Toman amount past 2^63-1 threw a FormatException -- from the
amount field's input formatter and again inside the goal editor's
build, which replaced the form with an ErrorWidget -- and a USD/EUR/TRY
whole part past ~9.2e16 wrapped silently once scaled to minor units.
parse now uses int.tryParse and returns null once the whole part
reaches maxInt ~/ minorUnitsPerMajor, below which whole * units +
fraction always fits. Every caller already treats null as "not an
amount": the goal editor says "Enter a number", the add screen shows
its amount error.

Tests: the overflow inputs parse to null and the largest that fit
still parse; twenty nines in a cap's target show the error and throw
nothing.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: A transaction edit and its tags commit together (D23)

**Files:**
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` — insert before line 1037 (`setTags`' doc comment) in `TransactionsDao`
- Modify: `app/lib/features/transactions/data/transaction_repository.dart:76-105`
- Modify: `packages/nimbus_data/lib/src/goals/goal_period_results_dao.dart:164-170` (delete)
- Test: `app/test/features/transactions/transaction_repository_test.dart` — two tests after "clearing every tag actually clears them" (ends line 145)

**Interfaces:**
- Consumes: drift `AppDatabase.transaction` (nested calls become savepoints — precedent `goal_service.dart:119-121`); `TransactionsDao.setTags` (its own `_db.transaction`).
- Produces: `Future<T> TransactionsDao.inTransaction<T>(Future<T> Function() action)`. `TransactionRepository.update(Transaction tx, {List<String>? tagIds})` signature unchanged; now atomic.

Foreign keys verified: `AppDatabase.migration.beforeOpen` runs `PRAGMA foreign_keys = ON` (`app_database.dart:182-184`), which applies to `openInMemory()` too, and `transaction_tags.tag_id` references `tags.id` (`transaction_tags_table.dart:14`). A probe on today's code: `update(tx.copyWith(amount: Money(2000)), tagIds: ['food', 'no-such-tag'])` throws `SqliteException(787): ... FOREIGN KEY constraint failed`, and afterwards the row reads `Money(2000)`, a fresh `updated_at`, tags `[travel]` — the row write committed, the tag write rolled back.

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-tag-edit-atomic
```

- [ ] **Step 2: Write the failing tests**

`app/test/features/transactions/transaction_repository_test.dart`, insert after line 145 (end of "clearing every tag actually clears them"):

```dart

  test("a tag edit moves the row's updated_at", () async {
    // The goals' money watermark has no term for tag links: it counts on a
    // tag edit stamping the row (D23).
    final tx = await repo.add(draft(tagIds: const ['travel']));
    await db.customStatement('UPDATE transactions SET updated_at = 1');

    await repo.update(tx, tagIds: const ['food']);

    expect((await db.transactionsDao.byId(tx.id))!.updatedAt, greaterThan(1));
  });

  test('an edit whose tags cannot be written changes nothing', () async {
    // An unknown tag id is a foreign-key violation: foreign_keys is on in
    // every database AppDatabase opens.
    final tx = await repo.add(
        draft(amount: const Money(1000), tagIds: const ['travel']));
    await db.customStatement('UPDATE transactions SET updated_at = 1');

    await expectLater(
      repo.update(tx.copyWith(amount: const Money(2000)),
          tagIds: const ['food', 'no-such-tag']),
      throwsA(predicate((Object e) => '$e'.contains('FOREIGN KEY'),
          'a foreign-key violation')),
    );

    final row = (await db.transactionsDao.byId(tx.id))!;
    expect(row.amount, const Money(1000));
    expect(row.updatedAt, 1);
    expect(await repo.tagsOf(tx.id), ['travel']);
  });
```

- [ ] **Step 3: Run it, confirm RED**

```bash
(cd app && flutter test test/features/transactions/transaction_repository_test.dart)
```

Expected: "a tag edit moves the row's updated_at" PASSES (it pins the D23 claim; `updateTransaction` already stamps). "an edit whose tags cannot be written changes nothing" FAILS:

```
Expected: Money:<Money(1000)>
  Actual: Money:<Money(2000)>
```

- [ ] **Step 4: Implement**

`packages/nimbus_data/lib/src/database/app_database.dart`, insert before line 1037 (`  /// Replaces the whole tag set for a transaction. ...`):

```dart
  /// Runs [action] in one transaction: its writes through this DAO commit
  /// together or not at all. A `transaction` inside it, as [setTags] opens,
  /// becomes a savepoint.
  Future<T> inTransaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

```

`app/lib/features/transactions/data/transaction_repository.dart`, before (lines 76-105):

```dart
  /// Writes an edited transaction.
  ///
  /// [tagIds] null leaves the tag set alone; a list replaces it wholesale.
  /// Replacing rather than merging is what makes removing a tag possible at
  /// all -- there is no other gesture that would express it.
  Future<void> update(Transaction tx, {List<String>? tagIds}) async {
    final local =
        DateTime.fromMillisecondsSinceEpoch(tx.occurredAtUtc, isUtc: true)
            .toLocal();
    await _dao.updateTransaction(
      tx.id,
      amount: tx.amount,
      direction: tx.direction,
      categoryId: tx.categoryId,
      occurredAtUtc: tx.occurredAtUtc,
      localDateKey: DateKey.fromDateTime(local),
      tzOffsetMinutes: local.timeZoneOffset.inMinutes,
      paymentMethodId: tx.paymentMethodId,
      merchant: tx.merchant,
      note: tx.note,
      necessity: tx.necessity,
      satisfaction: tx.satisfaction,
      isConfirmed: tx.isConfirmed,
    );
    if (tagIds != null) {
      // Usage is not re-counted on edit. The counter ranks how often a tag is
      // reached for, and re-editing one transaction ten times is not ten uses.
      await _attachTags(tx.id, tagIds, countUsage: false);
    }
  }
```

after:

```dart
  /// Writes an edited transaction.
  ///
  /// [tagIds] null leaves the tag set alone; a list replaces it wholesale.
  /// Replacing rather than merging is what makes removing a tag possible at
  /// all -- there is no other gesture that would express it.
  ///
  /// The row and its links are one transaction (D23): a tag write that fails
  /// leaves the row as it was, and the goals' money watermark never sees the
  /// row's new stamp without its new links.
  Future<void> update(Transaction tx, {List<String>? tagIds}) async {
    final local =
        DateTime.fromMillisecondsSinceEpoch(tx.occurredAtUtc, isUtc: true)
            .toLocal();
    await _dao.inTransaction(() async {
      await _dao.updateTransaction(
        tx.id,
        amount: tx.amount,
        direction: tx.direction,
        categoryId: tx.categoryId,
        occurredAtUtc: tx.occurredAtUtc,
        localDateKey: DateKey.fromDateTime(local),
        tzOffsetMinutes: local.timeZoneOffset.inMinutes,
        paymentMethodId: tx.paymentMethodId,
        merchant: tx.merchant,
        note: tx.note,
        necessity: tx.necessity,
        satisfaction: tx.satisfaction,
        isConfirmed: tx.isConfirmed,
      );
      if (tagIds != null) {
        // Usage is not re-counted on edit. The counter ranks how often a tag
        // is reached for, and re-editing one transaction ten times is not ten
        // uses.
        await _attachTags(tx.id, tagIds, countUsage: false);
      }
    });
  }
```

`packages/nimbus_data/lib/src/goals/goal_period_results_dao.dart`, before (lines 162-171):

```dart
  /// write or any goal edit heals it. Upgrade to a write counter if a user
  /// report traces back to either.
  ///
  /// shortcut: `TransactionRepository.update` stamps the row before it
  /// rewrites its tag links, in separate statements. A history load that
  /// runs between them caches the old tag membership under the new
  /// watermark, until the next money write. Upgrade to D23 (one drift
  /// transaction for the row and its links) when a tag-scoped goal shows
  /// stale history after a tag edit.
  Future<int> moneyWatermark() async {
```

after:

```dart
  /// write or any goal edit heals it. Upgrade to a write counter if a user
  /// report traces back to either.
  Future<int> moneyWatermark() async {
```

- [ ] **Step 5: Run it, confirm GREEN**

```bash
(cd app && flutter test test/features/transactions/transaction_repository_test.dart)
```

Expected: `All tests passed!`

- [ ] **Step 6: Broader suite**

```bash
(cd packages/nimbus_data && dart test)
(cd app && flutter test --concurrency=4)
dart analyze --fatal-infos
```

Expected: all pass; `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add packages/nimbus_data/lib/src/database/app_database.dart app/lib/features/transactions/data/transaction_repository.dart packages/nimbus_data/lib/src/goals/goal_period_results_dao.dart app/test/features/transactions/transaction_repository_test.dart
git commit -m "$(cat <<'EOF'
fix(transactions): a transaction edit and its tags commit together

D23: TransactionRepository.update rewrote and stamped the row, then
replaced its tag links in a separate transaction. A tag write that
failed (an unknown id is a foreign-key violation) left the row's new
amount and stamp committed beside the old links, and a goals history
load between the two writes could cache the old tag membership under
the new watermark. TransactionsDao.inTransaction runs both in one drift
transaction; setTags' own becomes a savepoint.

That makes the money watermark's claim -- tag links need no term of
their own -- hold, so its shortcut paragraph in
goal_period_results_dao.dart (Phase 5's file) goes; the DAO method is
added in Phase 0's app_database.dart.

Tests: a tag edit moves an aged updated_at; an edit with an unknown tag
throws and leaves amount, stamp and tags as they were.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: A calendar switch keeps the tracker repository (D20)

**Files:**
- Modify: `app/lib/features/trackers/application/tracker_providers.dart:14-18`
- Test: `app/test/features/trackers/tracker_providers_test.dart` — new group after `group("the tab's totals", ...)` (ends line 255), before `main`'s closing brace (line 256)

**Interfaces:**
- Consumes: `analyticsEngineProvider`, `appDatabaseProvider`, `trackerClockProvider`.
- Produces: `trackerRepositoryProvider` (type unchanged, `Provider<TrackerRepository>`) no longer rebuilds on a calendar or first-day-of-week change. It still rebuilds when the database or clock provider changes.

`TrackerRepository`'s only engine use is `totalOn` (`tracker_repository.dart:40-41`): `TrackerQueries.dayTotal(trackerId, day)` — one `DateKey`, no grouping, so the calendar never enters it. `AnalyticsEngine` holds no per-instance cache (`trackerChanges()` reads the database's own stream), so a kept engine with an old calendar answers `dayTotal` identically.

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-tracker-repo-calendar
```

- [ ] **Step 2: Write the failing test**

`app/test/features/trackers/tracker_providers_test.dart`, insert after line 255 (the `});` closing `group("the tab's totals", ...)`), before line 256 (`}`):

```dart

  group('the tracker repository', () {
    test('survives a calendar switch', () async {
      // D20: totalOn asks one day's total, which no calendar changes, so a
      // switch must not rebuild the repository under a mounted screen.
      await start();
      final kept = container.listen(trackerRepositoryProvider, (_, __) {});
      addTearDown(kept.close);
      final before = container.read(trackerRepositoryProvider);

      await SettingsRepository(db.settingsDao).save(AppSettings.defaults
          .copyWith(calendarKind: CalendarKind.gregorian));
      await until(
          () => container.read(analyticsEngineProvider).calendar
              is GregorianCalendar,
          'the engine to take the new calendar');
      await container.pump();

      expect(container.read(trackerRepositoryProvider), same(before));
    });
  });
```

(All names are already imported by this file.)

- [ ] **Step 3: Run it, confirm RED**

```bash
(cd app && flutter test test/features/trackers/tracker_providers_test.dart --plain-name "survives a calendar switch")
```

Expected (verified by a probe):

```
Expected: same instance as <Instance of 'TrackerRepository'>
  Actual: <Instance of 'TrackerRepository'>
```

- [ ] **Step 4: Implement**

`app/lib/features/trackers/application/tracker_providers.dart`, before (lines 14-18):

```dart
final trackerRepositoryProvider = Provider<TrackerRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TrackerRepository(db.trackersDao, db.trackerEntriesDao,
      ref.watch(analyticsEngineProvider), ref.watch(trackerClockProvider));
});
```

after:

```dart
final trackerRepositoryProvider = Provider<TrackerRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  // The engine is read, not watched: a calendar switch must not rebuild the
  // repository, which re-subscribes the tracker lists and resets a live
  // history (D20). Its one engine call, totalOn, asks one day's total with no
  // grouping, which no calendar changes. A method that groups by period
  // would need the watch back.
  return TrackerRepository(db.trackersDao, db.trackerEntriesDao,
      ref.read(analyticsEngineProvider), ref.watch(trackerClockProvider));
});
```

- [ ] **Step 5: Run it, confirm GREEN**

```bash
(cd app && flutter test test/features/trackers/tracker_providers_test.dart)
```

Expected: `All tests passed!` (including the existing calendar-switch reload tests: `trackerResultProvider` still watches the engine itself).

- [ ] **Step 6: Broader suite**

```bash
(cd app && flutter test --concurrency=4)
dart analyze --fatal-infos
```

Expected: all pass; `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/trackers/application/tracker_providers.dart app/test/features/trackers/tracker_providers_test.dart
git commit -m "$(cat <<'EOF'
fix(trackers): a calendar switch keeps the tracker repository

D20: trackerRepositoryProvider watched analyticsEngineProvider, so a
calendar switch rebuilt the repository, re-subscribing the tracker
lists and resetting a live history to its first page. Its one engine
call, totalOn, asks one day's total with no grouping, which no calendar
changes, so the engine is read once instead. A method that groups by
period would need the watch back; the comment says so.

Test: the repository is the same instance across a Gregorian switch.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: TrackerQuerySpec's JSON edges and its toString (D21)

**Files:**
- Modify: `packages/nimbus_domain/lib/src/trackers/tracker_query_spec.dart:116-118`
- Test: `packages/nimbus_domain/test/trackers/tracker_query_spec_test.dart` — three tests after "a half-open date range is refused" (ends line 120); one after "equal specs are equal and hash alike; ids compare in order" (ends line 142)

**Interfaces:**
- Consumes: `jsonMapOf` (`analytics/json_support.dart:16`), `DateRange.toString()` → `DateRange(DateKey(20261001)..DateKey(20261031))`.
- Produces: `TrackerQuerySpec.toString()` → `'TrackerQuerySpec($trackerIds, ${dateRange ?? 'undated'}, $groupBy, ${aggregate.name})'`. No other behaviour change.

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-query-spec-json-edges
```

- [ ] **Step 2: Write the failing tests**

`packages/nimbus_domain/test/trackers/tracker_query_spec_test.dart`, insert after line 120 (end of "a half-open date range is refused"):

```dart

    test('a missing or non-object groupBy is refused', () {
      final json = spec().toJson();
      expect(() => TrackerQuerySpec.fromJson({...json}..remove('groupBy')),
          throwsFormatException);
      expect(() => TrackerQuerySpec.fromJson({...json, 'groupBy': 'day'}),
          throwsFormatException);
    });

    test('a missing dateRange reads as undated, the form toJson stores', () {
      final json = spec().toJson()..remove('dateRange');
      expect(TrackerQuerySpec.fromJson(json).dateRange, isNull);
    });

    test('a non-object dateRange or a non-int end is refused', () {
      final json = spec().toJson();
      for (final bad in <Object>[
        '20261001..20261031',
        20261001,
        {'start': 20261001, 'end': '20261031'},
      ]) {
        expect(() => TrackerQuerySpec.fromJson({...json, 'dateRange': bad}),
            throwsFormatException,
            reason: 'accepted dateRange "$bad"');
      }
    });
```

Insert after line 142 (end of "equal specs are equal and hash alike; ids compare in order"):

```dart

    test('two specs that differ only by range print differently', () {
      // The spec keys a provider family, and Riverpod's debugging prints it.
      const november = DateRange(DateKey(20261101), DateKey(20261130));
      expect(spec().toString(), isNot(spec(range: november).toString()));
      expect(spec().toString(), contains('$october'));
    });
```

- [ ] **Step 3: Run it, confirm RED**

```bash
(cd packages/nimbus_domain && dart test test/trackers/tracker_query_spec_test.dart)
```

Expected: the three `fromJson` tests PASS on first run — D21 records the code as right and the gap as untested, so they are characterization tests pinning the storage format. "two specs that differ only by range print differently" FAILS:

```
Expected: not 'TrackerQuerySpec([cig], TrackerGroupByDay(), sum)'
  Actual: 'TrackerQuerySpec([cig], TrackerGroupByDay(), sum)'
```

- [ ] **Step 4: Implement**

`packages/nimbus_domain/lib/src/trackers/tracker_query_spec.dart`, before (lines 116-118):

```dart
  @override
  String toString() =>
      'TrackerQuerySpec($trackerIds, $groupBy, ${aggregate.name})';
```

after:

```dart
  @override
  String toString() => 'TrackerQuerySpec($trackerIds, '
      '${dateRange ?? 'undated'}, $groupBy, ${aggregate.name})';
```

- [ ] **Step 5: Run it, confirm GREEN**

```bash
(cd packages/nimbus_domain && dart test test/trackers/tracker_query_spec_test.dart)
```

Expected: `All tests passed!`

- [ ] **Step 6: Broader suite**

```bash
(cd packages/nimbus_domain && dart test)
dart analyze --fatal-infos
```

Expected: all pass; `No issues found!` (No app or data test asserts on this string — grepped `'TrackerQuerySpec(` across `packages`, `app`, `test`: only the definition.)

- [ ] **Step 7: Commit**

```bash
git add packages/nimbus_domain/lib/src/trackers/tracker_query_spec.dart packages/nimbus_domain/test/trackers/tracker_query_spec_test.dart
git commit -m "$(cat <<'EOF'
fix(trackers): TrackerQuerySpec prints its range; fromJson's edges pinned

D21: toString left out dateRange, so two family keys that differ only
by range printed alike in Riverpod's debugging. And fromJson's handling
of a missing or non-object groupBy, a missing dateRange (the stored
form of an undated spec, which toJson omits), a non-object dateRange
and a non-int end was right but untested; the tests are what pin the
format before anything stores a spec as JSON.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: The aggregate guard sees countAll, total and lowercase SQL (D21)

**Files:**
- Modify: `test/architecture_test.dart` — new top-level final after `runtimeDeps` (after line 19); new self-check test before "tracker code aggregates only through the analytics engine" (line 88); lines 92-93 removed and line 112 changed in that test

**Interfaces:**
- Consumes: none.
- Produces: top-level `final RegExp aggregatePattern` in `test/architecture_test.dart`.

How the root test runs (CI, `.github/workflows/ci.yaml`): `dart test test/architecture_test.dart` from the repo root (root `pubspec.yaml` has `test` and `yaml` as dev dependencies). Today: 6 tests, all pass.

Pattern choice, checked by a scan of `packages/nimbus_data/lib/src/trackers` and `app/lib/features/trackers` (non-comment lines, as the test reads them):
- A case-insensitive lookbehind pattern (`(?<![.\w])(sum|…|total)\s*\(`) also flags `app/lib/features/trackers/application/tracker_format.dart:39: String total(Tracker tracker, double total) => switch (tracker.type) {` — a method named `total`, a false positive. Rejected.
- The pattern below matches upper-case SQL anywhere and lower-case SQL only after a quote on the line. Its only hit is `packages/nimbus_data/lib/src/trackers/trackers_dao.dart:31: final highest = _db.trackers.sortOrder.max();`, already allowlisted. No new hits, no genuine violations.

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-aggregate-guard
```

- [ ] **Step 2: Write the failing test**

This step lifts the existing regex unchanged, so the RED shows the self-check catching the old pattern's gaps.

`test/architecture_test.dart`, insert after line 19 (the `}` closing `runtimeDeps`):

```dart

/// An aggregate written outside the analytics engine.
final aggregatePattern = RegExp(r'\b(SUM|COUNT|AVG|MIN|MAX)\s*\(|GROUP BY'
    r'|\.(sum|count|avg|min|max)\(\)|\.groupBy\(');
```

Insert before line 88 (`  test('tracker code aggregates only through the analytics engine', () {`):

```dart
  test('the aggregate pattern catches what it is for, and only that', () {
    for (final line in [
      'final n = countAll();',
      'final t = x.total();',
      "customSelect('select sum(v) from t')",
      '"... group by ..."',
      '"SELECT tracker_id, COUNT(*) FROM e "',
      'final m = e.value.max();',
      'q.groupBy([e.trackerId]);',
    ]) {
      expect(aggregatePattern.hasMatch(line), isTrue, reason: 'missed: $line');
    }
    for (final line in [
      'final top = math.max(a, b);',
      'format.total(t, 1)',
      'String total(Tracker tracker, double total) => switch (tracker.type) {',
      'TrackerGroupBy groupBy = const TrackerGroupByDay(),',
    ]) {
      expect(aggregatePattern.hasMatch(line), isFalse,
          reason: 'flagged: $line');
    }
  });

```

In "tracker code aggregates only through the analytics engine", delete lines 92-93:

```dart
    final aggregate = RegExp(r'\b(SUM|COUNT|AVG|MIN|MAX)\s*\(|GROUP BY'
        r'|\.(sum|count|avg|min|max)\(\)|\.groupBy\(');
```

and change line 112, before:

```dart
          if (aggregate.hasMatch(code) && !allowed.contains(code)) {
```

after:

```dart
          if (aggregatePattern.hasMatch(code) && !allowed.contains(code)) {
```

- [ ] **Step 3: Run it, confirm RED**

```bash
dart test test/architecture_test.dart
```

Expected: the self-check fails on its first sample —

```
Expected: true
  Actual: <false>
missed: final n = countAll();
```

— and the other 6 tests pass (the lift changed nothing else).

- [ ] **Step 4: Implement**

`test/architecture_test.dart`, replace the lifted definition:

```dart
/// An aggregate written outside the analytics engine.
final aggregatePattern = RegExp(r'\b(SUM|COUNT|AVG|MIN|MAX)\s*\(|GROUP BY'
    r'|\.(sum|count|avg|min|max)\(\)|\.groupBy\(');
```

with:

```dart
/// An aggregate written outside the analytics engine: drift's `countAll()`,
/// a column aggregate (`x.sum()`, `x.total()`, ...), `groupBy`, or SQL. SQL
/// counts in upper case anywhere, and in lower case only after a quote on
/// the line, so Dart's `max(a, b)` or a method named `total` is not SQL.
final aggregatePattern = RegExp(
    r'\b(SUM|COUNT|AVG|MIN|MAX|TOTAL)\s*\(|\bGROUP\s+BY\b'
    r'''|['"][^'"]*(\b(sum|count|avg|min|max|total)\s*\(|\bgroup\s+by\b)'''
    r'|\bcountAll\(|\.(sum|count|avg|min|max|total)\(\)|\.groupBy\(');
```

- [ ] **Step 5: Run it, confirm GREEN — and that the codebase raises no new hit**

```bash
dart test test/architecture_test.dart
```

Expected: `+7: All tests passed!` — the self-check passes, and "tracker code aggregates only through the analytics engine" still passes: the new pattern's only hit in the scanned directories is the allowlisted `trackers_dao.dart:31` line.

If it fails with an offender list instead, every line printed is a real hit: for each, either add it to `allowed` with a one-line reason in the comment above the set (as `trackers_dao.dart:31` has), or stop and report it as a genuine aggregate outside the engine. Do not loosen the pattern to make a line pass.

- [ ] **Step 6: Broader suite**

```bash
dart analyze --fatal-infos
```

Expected: `No issues found!` (the root test file is analyzed by the root config).

- [ ] **Step 7: Commit**

```bash
git add test/architecture_test.dart
git commit -m "$(cat <<'EOF'
test(architecture): the aggregate guard sees countAll, total and lowercase SQL

D21: the tracker-code aggregate pattern missed drift's countAll() and
total(), and SQL written in lower case, so a second query engine could
grow beside AnalyticsEngine unnoticed. The pattern is lifted to a
top-level final with a self-check of lines it must and must not match.
Lower-case SQL counts only after a quote on the line: matching a bare
max( flags math.max and methods named total, as a broader pattern did
with tracker_format.dart's total(). The tracker sources raise no new
hit.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: FakeClock takes a DST rule; a session keeps its start's offset (D21)

**Files:**
- Modify: `app/test/features/trackers/support/tracker_fixture.dart:14-41` (`FakeClock`)
- Test: `app/test/features/trackers/tracker_repository_test.dart` — in `group('the offset is taken at write time', ...)`, after "a timed session takes the offset at its start" (lines 350-357)
- Mutation check only (reverted): `app/lib/features/trackers/data/tracker_repository.dart:199`

**Interfaces:**
- Consumes: `TrackerClock({nowUtc, toLocal, fromLocal})`, `TrackerClock.offsetMinutesOf` (reads `toLocal`).
- Produces: `FakeClock({DateTime? nowUtc, Duration offset = FakeClock.tehran, Duration Function(DateTime utc)? rule})` and `final Duration Function(DateTime utc)? FakeClock.rule`. With `rule` null every existing caller behaves exactly as before. `toLocal(utc)` applies `rule(utc)`; `fromLocal` applies the offset in force now (`rule(nowUtc)`, or `offset`).

Why the existing test cannot tell: "a timed session takes the offset at its start" keeps one offset for the whole session, so `offsetMinutesOf(start)` and `offsetMinutesOf(now)` are the same number. Verified by a probe on today's repository with a rule clock (EDT until 2026-11-01 06:00 UTC, EST after; start 02:00 UTC, stop 8 h later): the clock reads −300 at the stop, the entry stores −240 and `localDateKey` 20261031.

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-fake-clock-dst
```

- [ ] **Step 2: Write the failing test**

`app/test/features/trackers/tracker_repository_test.dart`, insert after line 357 (end of "a timed session takes the offset at its start"):

```dart

    test('a session across a DST change keeps the offset at its start',
        () async {
      // D21: with one offset for every instant, "the offset at the start"
      // and "the offset now" were the same number. New York leaves daylight
      // time at 06:00 UTC on 1 November 2026: -4:00 before, -5:00 after.
      final fallBack = DateTime.utc(2026, 11, 1, 6);
      fake = FakeClock(
        nowUtc: DateTime.utc(2026, 11, 1, 2), // 22:00 on 31 October, EDT
        rule: (utc) => utc.isBefore(fallBack)
            ? const Duration(hours: -4)
            : const Duration(hours: -5),
      );
      repo = repositoryFor(db, fake);
      final s = await repo.create(sleep);
      await repo.startTimer(s.id);
      fake.advance(const Duration(hours: 8)); // 05:00 EST
      expect(fake.clock.offsetMinutesOf(fake.nowUtc), -300,
          reason: 'the stop is under the new offset');

      final stopped = await repo.stopTimer(s.id) as TimerStopped;

      expect(await offsetOf(stopped.entry.id), -240);
      expect(stopped.entry.localDateKey, const DateKey(20261031));
    });
```

- [ ] **Step 3: Run it, confirm RED**

```bash
(cd app && flutter test test/features/trackers/tracker_repository_test.dart --plain-name "across a DST change")
```

Expected: compilation fails — `Error: No named parameter with the name 'rule'.` (The behavioural RED is the mutation check in Step 5.)

- [ ] **Step 4: Implement**

`app/test/features/trackers/support/tracker_fixture.dart`, before (lines 14-41):

```dart
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
```

after:

```dart
/// A clock the test moves by hand.
///
/// Starts at 2026-10-05 09:00 UTC, which is 12:30 in Tehran, the default zone
/// here, so "today" is 20261005.
final class FakeClock {
  FakeClock({DateTime? nowUtc, this.offset = tehran, this.rule})
      : nowUtc = nowUtc ?? DateTime.utc(2026, 10, 5, 9);

  static const tehran = Duration(hours: 3, minutes: 30);
  static const newYork = Duration(hours: -4);

  DateTime nowUtc;

  /// The device's UTC offset. Change it to fly.
  Duration offset;

  /// The zone's offset at each instant, as a daylight-saving rule gives it.
  /// Null applies [offset] to every instant.
  final Duration Function(DateTime utc)? rule;

  void advance(Duration by) => nowUtc = nowUtc.add(by);

  /// Reads this fake's fields on every call, so moving the fake also moves a
  /// clock already handed to a repository or a provider.
  TrackerClock get clock => TrackerClock(
        nowUtc: () => nowUtc,
        toLocal: (utc) => utc.add(rule?.call(utc) ?? offset),
        // shortcut: a picked wall time maps with the offset in force now, not
        // the rule's offset at that time, so a time across a DST change lands
        // an hour off; upgrade when a test edits a time across one.
        fromLocal: (wall) => DateTime.utc(wall.year, wall.month, wall.day,
                wall.hour, wall.minute, wall.second)
            .subtract(rule?.call(nowUtc) ?? offset),
      );
}
```

- [ ] **Step 5: Run it, confirm GREEN, then prove it bites**

```bash
(cd app && flutter test test/features/trackers/tracker_repository_test.dart)
```

Expected: `All tests passed!`

Mutation check (temporary; never committed):

1. In `app/lib/features/trackers/data/tracker_repository.dart`, change line 199 from

   ```dart
        tzOffsetMinutes: _clock.offsetMinutesOf(timer.startedAtUtc),
   ```

   to

   ```dart
        tzOffsetMinutes: _clock.offsetMinutesOf(_clock.nowUtc()),
   ```

2. Run:

   ```bash
   (cd app && flutter test test/features/trackers/tracker_repository_test.dart --plain-name "offset at its start")
   ```

   Expected: "a session across a DST change keeps the offset at its start" FAILS with `Expected: <-240>  Actual: <-300>`, while the old "a timed session takes the offset at its start" still PASSES — the gap D21 named.

3. Revert and confirm the tree is clean for that file:

   ```bash
   git checkout -- app/lib/features/trackers/data/tracker_repository.dart
   git diff --exit-code app/lib/features/trackers/data/tracker_repository.dart
   ```

   Expected: no output, exit 0.

- [ ] **Step 6: Broader suite**

`FakeClock` is shared by the tracker, goal, widget and notification tests.

```bash
(cd app && flutter test --concurrency=4)
dart analyze --fatal-infos
```

Expected: all pass; `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/test/features/trackers/support/tracker_fixture.dart app/test/features/trackers/tracker_repository_test.dart
git commit -m "$(cat <<'EOF'
test(trackers): FakeClock takes a DST rule; a session keeps its start's offset

D21: FakeClock applied one offset to every instant, so "the offset at
the start" and "the offset now" were the same number and the existing
test could not tell them apart. An optional rule gives each instant its
own offset for toLocal; fromLocal keeps the offset in force now, marked
as a shortcut. A sleep session started under EDT and stopped under EST
keeps -240. With the repository changed to read the stop's offset the
new test fails and the old one still passes, which is the gap closed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Each tracker's Insights keeps its own range (D21)

**Files:**
- Modify: `app/lib/features/trackers/application/tracker_insights_controller.dart:40-44` (doc), `:79-83` (provider)
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_insights.dart:53-58`
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_range_bar.dart:10-18`
- Test: `app/test/features/trackers/tracker_insights_test.dart` — after "earlier and later move the range, never past today" (ends line 225)

**Interfaces:**
- Consumes: Riverpod 3.4.2 `NotifierProvider.autoDispose.family<NotifierT, StateT, ArgT>(NotifierT Function(ArgT arg) create)` (as `trackerHistoryProvider`, `tracker_history_controller.dart:91-93`).
- Produces:
  - `trackerInsightsProvider`: `NotifierProvider.autoDispose.family<TrackerInsightsController, TrackerInsightsView, String>` keyed by tracker id. Every reader writes `trackerInsightsProvider(tracker.id)`.
  - `TrackerRangeBar({Key? key, required String trackerId})` (no longer `const`-constructible without an id).
  - `TrackerInsightsController` itself is unchanged (it reads no tracker; the key only keeps states apart).

Any other task that edits `tracker_insights.dart` (D19, D22) must use the family form after this lands.

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-insights-family
```

- [ ] **Step 2: Write the failing test**

`app/test/features/trackers/tracker_insights_test.dart`, insert after line 225 (end of "earlier and later move the range, never past today"):

```dart

  testWidgets("one tracker's range never moves another's", (tester) async {
    // D21: the range was one notifier for the whole app, so two trackers'
    // Insights alive at once shared it.
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    final w = await repo.create(water);
    await logDaysAgo(cig, 0);
    await openInsights(tester, cig.id);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackerDetailScreen)));
    final other = container.listen(trackerInsightsProvider(w.id), (_, __) {});
    addTearDown(other.close);

    await tester.tap(find.byKey(const Key('tracker-range-previous')));
    await tester.pumpAndSettle();

    expect(textOf(tester, 'tracker-range-label'), '2026/09');
    expect(container.read(trackerInsightsProvider(w.id)).range, october);
  });
```

(All names are already imported by this file; `october` is its `const DateRange(DateKey(20261001), DateKey(20261031))`. No drift stream is read from the test body.)

- [ ] **Step 3: Run it, confirm RED**

```bash
(cd app && flutter test test/features/trackers/tracker_insights_test.dart --plain-name "never moves another")
```

Expected: compilation fails — `Error: The method 'call' isn't defined for the type 'NotifierProvider<TrackerInsightsController, TrackerInsightsView>'.` (verified wording).

- [ ] **Step 4: Implement**

`app/lib/features/trackers/application/tracker_insights_controller.dart`, before (lines 40-44):

```dart
/// The Insights tab's range.
///
/// The history chart and both patterns read this one range, because they are
/// three views of one question -- when this tracker's entries happened -- and
/// three controls would be three ways to get them out of step.
```

after:

```dart
/// One tracker's Insights range.
///
/// The history chart and both patterns read this one range, because they are
/// three views of one question -- when this tracker's entries happened -- and
/// three controls would be three ways to get them out of step.
```

Before (lines 79-83):

```dart
/// Auto-disposed: the Insights tab keeps itself alive while its screen is up,
/// so the range lasts as long as the screen does and no longer.
final trackerInsightsProvider =
    NotifierProvider.autoDispose<TrackerInsightsController, TrackerInsightsView>(
        TrackerInsightsController.new);
```

after:

```dart
/// Auto-disposed: the Insights tab keeps itself alive while its screen is up,
/// so the range lasts as long as the screen does and no longer. Keyed by
/// tracker id, so two trackers' Insights never share a range; the controller
/// itself reads no tracker.
final trackerInsightsProvider = NotifierProvider.autoDispose
    .family<TrackerInsightsController, TrackerInsightsView, String>(
        (_) => TrackerInsightsController());
```

`app/lib/features/trackers/presentation/widgets/tracker_insights.dart`, before (lines 53-58):

```dart
    final view = ref.watch(trackerInsightsProvider);
    return ListView(
      key: const Key('tracker-insights'),
      padding: const EdgeInsets.all(NimbusTokens.space4),
      children: [
        const TrackerRangeBar(),
```

after:

```dart
    final view = ref.watch(trackerInsightsProvider(tracker.id));
    return ListView(
      key: const Key('tracker-insights'),
      padding: const EdgeInsets.all(NimbusTokens.space4),
      children: [
        TrackerRangeBar(trackerId: tracker.id),
```

`app/lib/features/trackers/presentation/widgets/tracker_range_bar.dart`, before (lines 10-18):

```dart
/// Week, month or year, and which one: the Insights tab's single control.
class TrackerRangeBar extends ConsumerWidget {
  const TrackerRangeBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(trackerInsightsProvider);
    final controller = ref.read(trackerInsightsProvider.notifier);
```

after:

```dart
/// Week, month or year, and which one: the Insights tab's single control.
class TrackerRangeBar extends ConsumerWidget {
  const TrackerRangeBar({super.key, required this.trackerId});

  /// Whose range this moves.
  final String trackerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(trackerInsightsProvider(trackerId));
    final controller = ref.read(trackerInsightsProvider(trackerId).notifier);
```

- [ ] **Step 5: Run it, confirm GREEN**

```bash
(cd app && flutter test test/features/trackers/tracker_insights_test.dart)
```

Expected: `All tests passed!` (the existing range, calendar-switch and new-day tests also prove the bar and the charts read the same family member).

- [ ] **Step 6: Broader suite**

```bash
(cd app && flutter test --concurrency=4)
dart analyze --fatal-infos
```

Expected: all pass; `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/trackers/application/tracker_insights_controller.dart app/lib/features/trackers/presentation/widgets/tracker_insights.dart app/lib/features/trackers/presentation/widgets/tracker_range_bar.dart app/test/features/trackers/tracker_insights_test.dart
git commit -m "$(cat <<'EOF'
fix(trackers): each tracker's Insights keeps its own range

D21: trackerInsightsProvider was one auto-disposed notifier for the
whole app, so two trackers' Insights alive at once shared one range. It
is now a family keyed by tracker id, and TrackerRangeBar takes the id
whose range it moves.

Test: moving one tracker's range leaves another's on this month.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Tracker charts at the edges of their scale (D19)

**Files:**
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_insights.dart:91-101` (the history caption)
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_bar_chart.dart:50-61` (constants, interval maths), `:88-111` (left titles), `:110-111` (bottom titles)
- Modify: `app/lib/l10n/app_en.arb` (after the `@trackerInsightsTotalCaption` block, line 590), `app/lib/l10n/app_fa.arb` (after line 294)
- Regenerate: `app/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_fa.dart` (committed; `l10n.yaml` + `generate: true`)
- Test: `app/test/features/trackers/tracker_insights_test.dart` (new group after the `the value axis steps in whole units` group, line 182; new test after `at twice the font size Insights overflows nothing`, line 410)

Line numbers are as of `fd6b70f`. D21 (an earlier task) edits `tracker_insights.dart:53,58` only; anchor every edit below on its text.

**Interfaces:**
- Consumes: `TrackerFormat.total` / `.axis` (unchanged; goals and alerts use `duration` too), `valueAxisStep`, fl_chart 1.2.0 `TitleMeta.max`, `MediaQuery.textScalerOf`.
- Produces: ARB key `trackerInsightsUnderAMinute` (`AppLocalizations.trackerInsightsUnderAMinute`, a getter). `TrackerBarChart` gains no parameter.

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-tracker-chart-edges
```

- [ ] **Step 2: Write the failing tests**

In `app/test/features/trackers/tracker_insights_test.dart`, insert this group right after the closing `});` of `group('the value axis steps in whole units', ...)` (line 182):

```dart
  group('a duration at the edge of its scale', () {
    /// One 4-minute Sleep session, logged now (the 5th).
    Future<Tracker> fourMinutesOfSleep() async {
      final s = await repo.create(sleep);
      await repo.addDuration(s.id, const Duration(minutes: 4));
      return s;
    }

    testWidgets('an average under a minute reads <1 min, not 0:00',
        (tester) async {
      // 4 minutes over the five days of October begun so far: 48 s a day.
      // h:mm floors that to 0:00, which reads as nothing logged.
      await useGregorianEnglish();
      final s = await fourMinutesOfSleep();

      await openInsights(tester, s.id);

      expect(textOf(tester, 'tracker-history-caption'),
          '0:04 in all · <1 min a day');
    });

    testWidgets('and in Persian', (tester) async {
      // Review Focus 4. Default settings: Jalali, Persian digits. Mehr 1405
      // began on 23 September, so 13 days have begun: 18 s a day.
      final s = await fourMinutesOfSleep();

      await openInsights(tester, s.id, locale: const Locale('fa'));

      expect(textOf(tester, 'tracker-history-caption'),
          '۰:۰۴ در کل · کمتر از یک دقیقه در روز');
    });

    testWidgets('a peak under one step still labels its top', (tester) async {
      // The step is 15 minutes, above the 4-minute peak, so the top of the
      // axis is its only label above 0.
      await useGregorianEnglish();
      final s = await fourMinutesOfSleep();

      await openInsights(tester, s.id);

      expect(axisLabelsOf(tester, 'tracker-history-chart'), ['0:00', '0:04']);
    });
  });
```

Insert this test right after `testWidgets('at twice the font size Insights overflows nothing', ...)` (ends line 410):

```dart
  testWidgets("at twice the font size the axes' room doubles too",
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await useGregorianEnglish();
    final cig = await repo.create(cigarettes);
    await logDaysAgo(cig, 0);

    await openInsights(tester, cig.id);

    final titles = tester
        .widget<BarChart>(find.descendant(
            of: find.byKey(const Key('tracker-history-chart')),
            matching: find.byType(BarChart)))
        .data
        .titlesData;
    expect(titles.leftTitles.sideTitles.reservedSize, 88);
    expect(titles.bottomTitles.sideTitles.reservedSize, 56);
  });
```

No new imports: `fl_chart`, `nimbus_domain` (`Tracker`) and the fixture (`sleep`, `cigarettes`) are already imported.

- [ ] **Step 3: Run, confirm RED**

```bash
cd app && flutter test test/features/trackers/tracker_insights_test.dart
```

Expected: 4 failures, the rest pass.
- `an average under a minute ...`: `Expected: '0:04 in all · <1 min a day'  Actual: '0:04 in all · 0:00 a day'`
- `and in Persian`: `Actual: '۰:۰۴ در کل · ۰:۰۰ در روز'`
- `a peak under one step ...`: `Expected: ['0:00', '0:04']  Actual: ['0:00']`
- `... the axes' room doubles too`: `Expected: <88>  Actual: <44.0>`

The tests compile before the ARB change: none of them names the new key.

- [ ] **Step 4: Implement**

`app/lib/l10n/app_en.arb` — insert between the `@trackerInsightsTotalCaption` block's closing `},` and `"trackerInsightsWeekdaySummary"` (alphabetical: `TotalCaption` < `UnderAMinute` < `WeekdaySummary`). No placeholders, so no `@` block, as `trackerInsightsNothingLogged` has none:

```json
  "trackerInsightsUnderAMinute": "<1 min",
```

`app/lib/l10n/app_fa.arb` — insert between `"trackerInsightsTotalCaption"` (line 294) and `"trackerInsightsWeekdaySummary"` (line 295). The fa file carries no `@` metadata:

```json
  "trackerInsightsUnderAMinute": "کمتر از یک دقیقه",
```

Regenerate the committed localizations:

```bash
cd app && flutter gen-l10n
```

Expected: exits 0 and `git status` shows the three `app/lib/l10n/app_localizations*.dart` files modified.

`app/lib/features/trackers/presentation/widgets/tracker_insights.dart`, before (lines 91-101):

```dart
        final days = elapsedDays(view.range, today);
        // A boolean's per-day average would be a fraction of a "done", so it
        // says on how many days it was done instead. The day count only picks
        // "day" or "days"; it is printed through format, in the settings'
        // digits.
        final caption = tracker.type == TrackerType.boolean
            ? l10n.trackerInsightsDoneCaption(
                days, format.number(result.sum), format.digits(days))
            : l10n.trackerInsightsTotalCaption(
                format.total(tracker, result.sum),
                format.total(tracker, days == 0 ? 0 : result.sum / days));
```

After:

```dart
        final days = elapsedDays(view.range, today);
        final average = days == 0 ? 0.0 : result.sum / days;
        // A boolean's per-day average would be a fraction of a "done", so it
        // says on how many days it was done instead. The day count only picks
        // "day" or "days"; it is printed through format, in the settings'
        // digits.
        final caption = tracker.type == TrackerType.boolean
            ? l10n.trackerInsightsDoneCaption(
                days, format.number(result.sum), format.digits(days))
            : l10n.trackerInsightsTotalCaption(
                format.total(tracker, result.sum),
                // h:mm floors a duration under a minute to 0:00, which reads
                // as nothing logged. A duration's value is in seconds.
                tracker.type == TrackerType.duration &&
                        average > 0 &&
                        average < 60
                    ? l10n.trackerInsightsUnderAMinute
                    : format.total(tracker, average));
```

`app/lib/features/trackers/presentation/widgets/tracker_bar_chart.dart`, before (lines 50-61):

```dart
  /// The bottom axis's labels, under the bars.
  static const _bottomTitlesSize = 28.0;

  /// fl_chart's own measure when it picks a step: one per 40 pixels of axis.
  static const _pixelsPerStep = 40.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peak = values.fold<double>(0, math.max);
    final step = axisStepOf(
        peak, math.max((height - _bottomTitlesSize) ~/ _pixelsPerStep, 1));
```

After:

```dart
  /// The value axis's labels, beside the bars, at 1x text.
  static const _leftTitlesSize = 44.0;

  /// The bottom axis's labels, under the bars, at 1x text.
  static const _bottomTitlesSize = 28.0;

  /// fl_chart's own measure when it picks a step: one per 40 pixels of axis.
  static const _pixelsPerStep = 40.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The labels grow with the user's font size, so their room must too.
    final scaler = MediaQuery.textScalerOf(context);
    final bottomTitlesSize = scaler.scale(_bottomTitlesSize);
    final peak = values.fold<double>(0, math.max);
    final step = axisStepOf(
        peak, math.max((height - bottomTitlesSize) ~/ _pixelsPerStep, 1));
```

Before (lines 91-99):

```dart
                  reservedSize: 44,
                  interval: step,
                  getTitlesWidget: (value, meta) {
                    // fl_chart also labels the top of the axis, the highest
                    // bar, which is rarely a step: an hour and five minutes
                    // would read 1:05 above 1:00.
                    if (step != null && !_isStep(value, step)) {
                      return const SizedBox.shrink();
                    }
```

After:

```dart
                  reservedSize: scaler.scale(_leftTitlesSize),
                  interval: step,
                  getTitlesWidget: (value, meta) {
                    // fl_chart also labels the top of the axis, the highest
                    // bar, which is rarely a step: an hour and five minutes
                    // would read 1:05 above 1:00. Below one step the top is
                    // the axis's only label above 0, so it stays: a 4-minute
                    // peak reads 0:04 rather than nothing.
                    if (step != null &&
                        meta.max >= step &&
                        !_isStep(value, step)) {
                      return const SizedBox.shrink();
                    }
```

Before (line 111):

```dart
                  reservedSize: _bottomTitlesSize,
```

After:

```dart
                  reservedSize: bottomTitlesSize,
```

- [ ] **Step 5: Run, confirm GREEN**

```bash
cd app && flutter test test/features/trackers/tracker_insights_test.dart
```

Expected: `All tests passed!` (the existing axis tests, `['0', '1']`, `['0', '1', '2']`, `['0:00', '0:30', '1:00']`, still pass: each peak is at least one step).

- [ ] **Step 6: Broader suite**

```bash
cd app && flutter test --concurrency=4
cd .. && dart analyze --fatal-infos
```

Expected: `All tests passed!`; `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/trackers/presentation/widgets/tracker_insights.dart \
        app/lib/features/trackers/presentation/widgets/tracker_bar_chart.dart \
        app/lib/l10n/app_en.arb app/lib/l10n/app_fa.arb \
        app/lib/l10n/app_localizations.dart \
        app/lib/l10n/app_localizations_en.dart \
        app/lib/l10n/app_localizations_fa.dart \
        app/test/features/trackers/tracker_insights_test.dart
git commit -F- <<'EOF'
fix(trackers): charts read a sub-minute average, a small peak and large text

D19: On the A53 the Sleep header for 1405/07 read "0:04 in all, 0:00 a day":
h:mm floors an average under a minute to 0:00, which reads as nothing
logged. A duration average between 0 and 60 seconds now says "<1 min"
(trackerInsightsUnderAMinute, en and fa). TrackerFormat.duration is
unchanged, because goals and alerts read it too.

The value axis hid every label that was not a whole step, so a 4-minute
peak under a 15-minute step showed only 0:00. The top label is now hidden
only when a step fits under the max.

The axes reserved a fixed 44 and 28 points, so at 2x text their labels
wrapped or clipped. Both sizes, and the step count derived from the bottom
one, now go through the text scaler. Phase 3's identical constants are
outside D19 and stay.

D19.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 12a: A boolean's spoken history says its done caption (D22)

**Files:**
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_insights.dart:118-126` (the history `semanticsLabel`)
- Modify: `app/lib/l10n/app_en.arb` (after the `@trackerInsightsDoneCaption` block, line 538), `app/lib/l10n/app_fa.arb` (after line 287)
- Regenerate: `app/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_fa.dart`
- Test: `app/test/features/trackers/tracker_insights_test.dart` (after `the chart speaks its numbers`, line 298 before Task 11's insertions)

**Interfaces:**
- Consumes: the `caption` local Task 11 left in `_HistorySection.build`, `rangeLabel`.
- Produces: ARB key `trackerInsightsDoneSummary(String name, String period, String caption)`.

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-tracker-done-summary
```

- [ ] **Step 2: Write the failing tests**

In `app/test/features/trackers/tracker_insights_test.dart`, insert right after `testWidgets('the chart speaks its numbers', ...)`:

```dart
  testWidgets("a boolean's chart speaks its done caption, not a tied peak",
      (tester) async {
    // Every day done is a peak of 1, so a peak named the earliest of them.
    final semantics = tester.ensureSemantics();
    await useGregorianEnglish();
    final g = await repo.create(gym);
    await logDaysAgo(g, 0);
    await logDaysAgo(g, 2);

    await openInsights(tester, g.id);

    expect(find.bySemanticsLabel('Gym, 2026/10: Done on 2 of 5 days'),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets("a boolean's spoken summary in Persian", (tester) async {
    // Review Focus 4. Default settings: Jalali, Persian digits. Mehr 1405
    // began on 23 September, so 13 days have begun.
    final semantics = tester.ensureSemantics();
    final g = await repo.create(gym);
    await logDaysAgo(g, 0);
    await logDaysAgo(g, 2);

    await openInsights(tester, g.id, locale: const Locale('fa'));

    expect(
        find.bySemanticsLabel('Gym، ۱۴۰۵/۰۷: ۲ روز از ۱۳ روز انجام شد'),
        findsOneWidget);
    semantics.dispose();
  });
```

- [ ] **Step 3: Run, confirm RED**

```bash
cd app && flutter test test/features/trackers/tracker_insights_test.dart
```

Expected: the two new tests fail with `Expected: exactly one matching candidate  Actual: _SemanticsFinder:<Found 0 widgets with semantics label ...>`. Today the chart says `Gym, 2026/10: 2 in all; most on 2026/10/03, 1`.

- [ ] **Step 4: Implement**

`app/lib/l10n/app_en.arb` — insert between the `@trackerInsightsDoneCaption` block's closing `},` and `"trackerInsightsEmptyMessage"` (`DoneCaption` < `DoneSummary` < `EmptyMessage`):

```json
  "trackerInsightsDoneSummary": "{name}, {period}: {caption}",
  "@trackerInsightsDoneSummary": {
    "placeholders": {
      "name": {
        "type": "String"
      },
      "period": {
        "type": "String"
      },
      "caption": {
        "type": "String"
      }
    }
  },
```

`app/lib/l10n/app_fa.arb` — insert between `"trackerInsightsDoneCaption"` (line 287) and `"trackerInsightsEmptyMessage"` (line 288). Persian comma, as `trackerInsightsHistorySummary` writes it:

```json
  "trackerInsightsDoneSummary": "{name}، {period}: {caption}",
```

```bash
cd app && flutter gen-l10n
```

`app/lib/features/trackers/presentation/widgets/tracker_insights.dart`, before:

```dart
              semanticsLabel: l10n.trackerInsightsHistorySummary(
                tracker.name,
                rangeLabel(view, format),
                format.total(tracker, result.sum),
                year
                    ? format.month(peak.period.startInclusive)
                    : format.date(peak.period.startInclusive),
                format.total(tracker, peak.value),
              ),
```

After:

```dart
              // A boolean's every done day is a tied peak of 1, so naming one
              // says nothing; the caption is what it has to say.
              semanticsLabel: tracker.type == TrackerType.boolean
                  ? l10n.trackerInsightsDoneSummary(
                      tracker.name, rangeLabel(view, format), caption)
                  : l10n.trackerInsightsHistorySummary(
                      tracker.name,
                      rangeLabel(view, format),
                      format.total(tracker, result.sum),
                      year
                          ? format.month(peak.period.startInclusive)
                          : format.date(peak.period.startInclusive),
                      format.total(tracker, peak.value),
                    ),
```

- [ ] **Step 5: Run, confirm GREEN**

```bash
cd app && flutter test test/features/trackers/tracker_insights_test.dart
```

Expected: `All tests passed!` (`the chart speaks its numbers`, a quantity, keeps its peak sentence).

- [ ] **Step 6: Broader suite**

```bash
cd app && flutter test --concurrency=4
cd .. && dart analyze --fatal-infos
```

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/trackers/presentation/widgets/tracker_insights.dart \
        app/lib/l10n/app_en.arb app/lib/l10n/app_fa.arb \
        app/lib/l10n/app_localizations.dart \
        app/lib/l10n/app_localizations_en.dart \
        app/lib/l10n/app_localizations_fa.dart \
        app/test/features/trackers/tracker_insights_test.dart
git commit -F- <<'EOF'
fix(trackers): a boolean's history chart speaks its done caption

D22: Every day a boolean is done is a bar of exactly 1, so the spoken "most on"
named the earliest of many tied days, which tells a screen-reader user
nothing. A boolean now says what its caption says, "Gym, 2026/10: Done on
2 of 5 days" (trackerInsightsDoneSummary, en and fa). Counters,
quantities and durations keep their peak.

D22.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 12b: A stale "done" tap after midnight says nothing (D22)

**Files:**
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_logger.dart:61-71` (`toggleDone`)
- Test: `app/test/features/trackers/tracker_entry_test.dart` (inside `group('boolean', ...)`, after `a double-tap logs done once`, lines 143-154)

**Interfaces:**
- Consumes: `TrackerRepository.clearToday(String) → Future<List<String>>` (empty when nothing was live on the clock's today; `TrackerEntriesDao.softDeleteOn` returns early without writing).
- Produces: no API change.

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-tracker-stale-done
```

- [ ] **Step 2: Write the failing test**

In `app/test/features/trackers/tracker_entry_test.dart`, inside `group('boolean', ...)`, right after `testWidgets('a double-tap logs done once', ...)`:

```dart
    testWidgets('a stale "done" after midnight says nothing and keeps the day',
        (tester) async {
      await repo.logEntry(g.id);
      await openTab(tester);
      expect(textIn(tester, Key('tracker-total-${g.id}')), 'Done today');

      // Past midnight, before the tile hears of the new day (the rollover
      // timer is not pumped): it still shows yesterday's "done", so the tap
      // asks to take back a day with nothing in it.
      fake.advance(const Duration(days: 1));
      await tester.tap(action(g));
      await tester.pumpAndSettle();

      expect(find.text('Gym · not done today'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(await count(g), 1, reason: "yesterday's done is left alone");
    });
```

- [ ] **Step 3: Run, confirm RED**

```bash
cd app && flutter test test/features/trackers/tracker_entry_test.dart
```

Expected: the new test fails at the first assertion: `Expected: no matching candidates  Actual: _TextWidgetFinder:<Found 1 widget with text "Gym · not done today" ...>`.

- [ ] **Step 4: Implement**

`app/lib/features/trackers/presentation/widgets/tracker_logger.dart`, before (lines 61-71):

```dart
  Future<void> toggleDone({required bool done}) async {
    if (!done) return log();
    _haptic();
    final cleared = await _write(() => repository.clearToday(tracker.id));
    _showUndo(
```

After:

```dart
  Future<void> toggleDone({required bool done}) async {
    if (!done) return log();
    _haptic();
    final cleared = await _write(() => repository.clearToday(tracker.id));
    // A stale "done" after midnight: today held nothing to take back, and
    // "not done today" would announce a change that did not happen.
    if (cleared.isEmpty) return;
    _showUndo(
```

- [ ] **Step 5: Run, confirm GREEN**

```bash
cd app && flutter test test/features/trackers/tracker_entry_test.dart
```

Expected: `All tests passed!` (`a tap on a done gym takes it back, and undo restores it` still shows its snackbar: it clears one entry).

- [ ] **Step 6: Broader suite**

```bash
cd app && flutter test --concurrency=4
cd .. && dart analyze --fatal-infos
```

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/trackers/presentation/widgets/tracker_logger.dart \
        app/test/features/trackers/tracker_entry_test.dart
git commit -F- <<'EOF'
fix(trackers): a stale "done" tap after midnight says nothing

D22: In the moments after midnight a boolean's tile can still show yesterday's
"done". A tap then clears today, which holds nothing, and still showed
"Gym, not done today" with an Undo for nothing. The snackbar now appears
only when the clear took something back. Yesterday's entry was never
touched; the test pins that too.

D22.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 12c: English spoken weekday summaries name the whole day (D22)

**Files:**
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_insights.dart:212-217` (weekday `semanticsLabel`), `:224-237` (add `_weekdayLongName` after `_weekdayName`)
- Modify: `app/lib/l10n/app_en.arb` (between `weekdayFriday` and `weekdayMonday`, lines 817-818), `app/lib/l10n/app_fa.arb` (between lines 391 and 392)
- Regenerate: `app/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_fa.dart`
- Test: `app/test/features/trackers/tracker_insights_test.dart:510` (edit), new test after `both patterns speak their peaks` (ends line 513)

**gen-l10n check (done by reading, not running):** Flutter 3.47.1's `flutter_tools/lib/src/localizations/message_parser.dart` has `ST.selectExpr` with identifier cases (`selectPart := identifier '{' message '}' | number ... | other ...`), and `checkExtraRules` only requires an `other` case. `gen_l10n_types.dart:597-601` requires a select placeholder to be a `String`. The repo already ships selects (`goalsAlertGoalMet` and four more, `app_en.arb:83-133`). So one select key works; no seven `*Long` keys.

**Interfaces:**
- Consumes: `trackerInsightsWeekdaySummary` (unchanged), `DateTime.monday..sunday` ints.
- Produces: ARB key `weekdayLong(String day)` with cases `monday`..`saturday`, `other` = Sunday. Chart labels keep `weekdayMonday`.. (short in en).

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-tracker-weekday-long
```

- [ ] **Step 2: Write the failing tests**

In `app/test/features/trackers/tracker_insights_test.dart`, `testWidgets('both patterns speak their peaks', ...)`, before (line 510):

```dart
              'Cigarettes by day of week, 2026/10: most on Mon, 3'),
```

After:

```dart
              'Cigarettes by day of week, 2026/10: most on Monday, 3'),
```

Insert right after that test, still inside `group('patterns', ...)`:

```dart
    testWidgets('the weekday peak is spoken in full in Persian too',
        (tester) async {
      // Review Focus 4. Persian's chart labels are already full names; the
      // spoken summary now reads them through weekdayLong.
      final semantics = tester.ensureSemantics();
      final cig = await cigarettesAtNoonAndDawn();
      await openInsights(tester, cig.id, locale: const Locale('fa'));

      await scrollTo(tester, 'tracker-weekday-chart');
      expect(
          find.bySemanticsLabel(
              'Cigarettes بر اساس روز هفته، ۱۴۰۵/۰۷: بیشترین در دوشنبه، ۳'),
          findsOneWidget);
      semantics.dispose();
    });
```

- [ ] **Step 3: Run, confirm RED**

```bash
cd app && flutter test test/features/trackers/tracker_insights_test.dart
```

Expected: `patterns both patterns speak their peaks` fails: `Found 0 widgets with semantics label "Cigarettes by day of week, 2026/10: most on Monday, 3"` (today it says `Mon`). The Persian test PASSES already (fa's short keys are full names); it guards the fa mapping of the new key.

- [ ] **Step 4: Implement**

`app/lib/l10n/app_en.arb` — insert between `"weekdayFriday": "Fri",` and `"weekdayMonday": "Mon",` (`Friday` < `Long` < `Monday`):

```json
  "weekdayLong": "{day, select, monday{Monday} tuesday{Tuesday} wednesday{Wednesday} thursday{Thursday} friday{Friday} saturday{Saturday} other{Sunday}}",
  "@weekdayLong": {
    "placeholders": {
      "day": {
        "type": "String"
      }
    }
  },
```

`app/lib/l10n/app_fa.arb` — insert between `"weekdayFriday"` (line 391) and `"weekdayMonday"` (line 392). Copy each name from the existing `weekday*` value (Tuesday's carries a ZWNJ, U+200C):

```json
  "weekdayLong": "{day, select, monday{دوشنبه} tuesday{سه‌شنبه} wednesday{چهارشنبه} thursday{پنجشنبه} friday{جمعه} saturday{شنبه} other{یکشنبه}}",
```

```bash
cd app && flutter gen-l10n
```

`app/lib/features/trackers/presentation/widgets/tracker_insights.dart`, before (lines 212-217):

```dart
          semanticsLabel: l10n.trackerInsightsWeekdaySummary(
            tracker.name,
            rangeLabel(view, format),
            _weekdayName(l10n, order[peak]),
            format.total(tracker, values[peak]),
          ),
```

After:

```dart
          semanticsLabel: l10n.trackerInsightsWeekdaySummary(
            tracker.name,
            rangeLabel(view, format),
            _weekdayLongName(l10n, order[peak]),
            format.total(tracker, values[peak]),
          ),
```

Append after `_weekdayName` (after line 237):

```dart

/// A weekday's full name, for the spoken summary: a screen reader has the
/// room a chart label does not. Sunday reads through the select's `other`,
/// as [_weekdayName]'s `_` arm does.
String _weekdayLongName(AppLocalizations l10n, int isoWeekday) =>
    l10n.weekdayLong(const [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ][isoWeekday - 1]);
```

- [ ] **Step 5: Run, confirm GREEN**

```bash
cd app && flutter test test/features/trackers/tracker_insights_test.dart
```

Expected: `All tests passed!` (the chart labels `Sat` and `Mon` at lines 482 and 493 are unchanged).

- [ ] **Step 6: Broader suite**

```bash
cd app && flutter test --concurrency=4
cd .. && dart analyze --fatal-infos
```

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/trackers/presentation/widgets/tracker_insights.dart \
        app/lib/l10n/app_en.arb app/lib/l10n/app_fa.arb \
        app/lib/l10n/app_localizations.dart \
        app/lib/l10n/app_localizations_en.dart \
        app/lib/l10n/app_localizations_fa.dart \
        app/test/features/trackers/tracker_insights_test.dart
git commit -F- <<'EOF'
fix(trackers): English spoken weekday summaries name the whole day

D22: The weekday chart's spoken peak reused the chart's short labels, so
English said "most on Mon" while Persian said the full name. One select
key, weekdayLong, gives the full name for speech; fa maps it to the names
it already had. The chart's labels stay short, where the room is.

D22.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 13: Domain pins: `exceeds`, `Goal` equality, the `scaledBy` limit (D25 #5, #10, #3)

**Files:**
- Modify: `packages/nimbus_domain/lib/src/goals/goal_amount.dart:106` (one `shortcut:` comment, #3)
- Test: `packages/nimbus_domain/test/goals/goal_values_test.dart:17-38` (helper takes an `id`), after line 165 (#5), after line 380 (#10)

Claims re-checked against `fd6b70f`: no domain test calls `exceeds(` (grep); the only equality test checks `alertPercents`, `weekStart` and `active`, 3 of the 11 fields `Goal.==` reads (`goal.dart:161-173`); `scaledBy` (`goal_amount.dart:104-112`) has no `shortcut:` comment. All hold.

**Interfaces:**
- Consumes: `GoalAmount.exceeds`, `reaches`, `Goal.copyWith`, `Goal.==`.
- Produces: none (tests and a comment).

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-goal-domain-pins
```

- [ ] **Step 2: Write the tests**

`packages/nimbus_domain/test/goals/goal_values_test.dart`, the `goal` helper, before (lines 17-28):

```dart
  Goal goal({
    String name = 'Dining out',
    GoalMetric metric = GoalMetric.moneySum,
    GoalScope? scope,
    GoalDirection direction = GoalDirection.atMost,
    GoalAmount? target,
    GoalPeriod period = october,
    int weekStart = DateTime.saturday,
    List<int> alertPercents = Goal.defaultAlertPercents,
  }) =>
      Goal(
        id: 'g1',
```

After:

```dart
  Goal goal({
    String id = 'g1',
    String name = 'Dining out',
    GoalMetric metric = GoalMetric.moneySum,
    GoalScope? scope,
    GoalDirection direction = GoalDirection.atMost,
    GoalAmount? target,
    GoalPeriod period = october,
    int weekStart = DateTime.saturday,
    List<int> alertPercents = Goal.defaultAlertPercents,
  }) =>
      Goal(
        id: id,
```

Inside `group('GoalAmount', ...)`, after `a zero target is reached by anything above zero` (ends line 165):

```dart
    test('exceeds is strictly over, with the tolerance reaches uses', () {
      expect(rials(10001).exceeds(rials(10000)), isTrue);
      expect(rials(10000).exceeds(rials(10000)), isFalse,
          reason: 'exactly at a cap is within it');
      expect(rials(1).exceeds(rials(0)), isTrue);
      expect(rials(0).exceeds(rials(0)), isFalse);
      // 0.1 + 0.2 is 0.30000000000000004: on the target, so it reaches 100%
      // and is not over it. A value that reaches 100% is never also over.
      final sum = const QuantityAmount(0.1) + const QuantityAmount(0.2);
      expect(sum.reaches(const QuantityAmount(0.3), 100), isTrue);
      expect(sum.exceeds(const QuantityAmount(0.3)), isFalse);
      expect(const QuantityAmount(0.300001).exceeds(const QuantityAmount(0.3)),
          isTrue,
          reason: 'past the tolerance is over');
      expect(const QuantityAmount(1).exceeds(const QuantityAmount(0)), isTrue);
      expect(const QuantityAmount(0).exceeds(const QuantityAmount(0)), isFalse);
      expect(() => rials(1).exceeds(const QuantityAmount(1)),
          throwsArgumentError);
    });
```

Inside `group('Goal', ...)`, after `equal goals are equal and hash alike; every field counts` (ends line 380):

```dart
    test('two goals differing in any one of the eleven fields are unequal',
        () {
      // A goal keys provider families and the history cache's content
      // guard, so a field == ignored would serve one goal another's numbers.
      // The base has no direction filter, so the metric can switch alone.
      final base = goal(scope: everything);
      final variants = <String, Goal>{
        'id': goal(id: 'g2', scope: everything),
        'name': base.copyWith(name: 'Eating out'),
        'metric': base.copyWith(metric: GoalMetric.netSavings),
        'scope': base.copyWith(scope: food),
        'direction': base.copyWith(direction: GoalDirection.atLeast),
        'target': base.copyWith(target: rials(20000)),
        'period': base.copyWith(
            period: const RecurringPeriod(PeriodType.week, DateKey(20261001))),
        'calendar': base.copyWith(calendar: CalendarKind.gregorian),
        'weekStart': base.copyWith(weekStart: DateTime.monday),
        'alertPercents': base.copyWith(alertPercents: [50, 100]),
        'active': base.copyWith(active: false),
      };
      for (final MapEntry(key: field, value: variant) in variants.entries) {
        expect(variant, isNot(base), reason: field);
        expect(base, isNot(variant), reason: '$field, the other way round');
      }
    });
```

- [ ] **Step 3: Run, confirm (GREEN expected: tests for correct code)**

```bash
cd packages/nimbus_domain && dart test test/goals/goal_values_test.dart
```

Expected: `All tests passed!` (33 tests). RED is not expected: these pin code that is already right. Step 3b proves each test bites.

- [ ] **Step 3b: Mutation check — each test fails on a plausible bug, then revert**

Do these before Step 4 so `goal_amount.dart` holds no other change when it is reverted.

1. `packages/nimbus_domain/lib/src/goals/goal_amount.dart:179`, `QuantityAmount.exceeds`: change

```dart
    return value > of + of.abs() * _relativeTolerance;
```

to

```dart
    return value > of;
```

Run `cd packages/nimbus_domain && dart test test/goals/goal_values_test.dart`. Expected FAIL: `exceeds is strictly over, ...` with `Expected: false  Actual: <true>` at the `sum.exceeds` line. Revert: `git checkout -- packages/nimbus_domain/lib/src/goals/goal_amount.dart`.

2. `goal_amount.dart:101`, `MoneyAmount.exceeds`: change `compareTo(target) > 0` to `compareTo(target) >= 0`. Run the same command. Expected FAIL: `exactly at a cap is within it`. Revert with the same `git checkout --`.

3. `packages/nimbus_domain/lib/src/goals/goal.dart:170`: delete the line `      other.calendar == calendar &&`. Run the same command. Expected FAIL: `two goals differing ...` with reason `calendar`. Revert: `git checkout -- packages/nimbus_domain/lib/src/goals/goal.dart`.

Then `git diff --stat` must list only `packages/nimbus_domain/test/goals/goal_values_test.dart`.

- [ ] **Step 4: Implement (#3, the comment)**

`packages/nimbus_domain/lib/src/goals/goal_amount.dart`, before (lines 104-107):

```dart
  MoneyAmount scaledBy(int numerator, int denominator) {
    _checkPositive(denominator, 'denominator');
    final scaled = money.minorUnits * numerator;
```

After:

```dart
  MoneyAmount scaledBy(int numerator, int denominator) {
    _checkPositive(denominator, 'denominator');
    // shortcut: a plain 64-bit product, which wraps past ~2.5e16 minor units over a year-long range (~2.5e15 over a decade); move to BigInt if a goal can hold amounts that large.
    final scaled = money.minorUnits * numerator;
```

- [ ] **Step 5: Run, confirm GREEN**

```bash
cd packages/nimbus_domain && dart test test/goals/goal_values_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6: Broader suite**

```bash
cd packages/nimbus_domain && dart test
cd ../.. && dart test test/architecture_test.dart && dart analyze --fatal-infos
```

- [ ] **Step 7: Commit**

```bash
git add packages/nimbus_domain/lib/src/goals/goal_amount.dart \
        packages/nimbus_domain/test/goals/goal_values_test.dart
git commit -F- <<'EOF'
test(goals): pin exceeds' tolerance and Goal equality on every field

D25: exceeds decides "over the cap" and had no direct test: a value exactly on
a target, or within float noise of it (0.1 + 0.2 against 0.3), must not
read as over, and nothing pinned that. Goal equality was tested on 3 of
its 11 fields, though a goal keys provider families and the history
cache's content guard; a field dropped from == would serve one goal
another's numbers. Each test was seen to fail against a mutated
implementation.

scaledBy's 64-bit product gets the shortcut comment the plan's limit
(about 2.5e16 minor units over a year) was owed.

D25 #3, #5, #10.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 14: Data pins: seams, nothing to measure, TypeError, tags, early and deleted goals (D25 #14, #17, #19, #20, #22, #23)

**Files:**
- Test: `packages/nimbus_data/test/goals/engine_goal_measurer_test.dart` (after the seam test, line 151, #14; new group after line 190, #17)
- Test: `packages/nimbus_data/test/goals/goals_dao_test.dart` (the `malformed` map, after line 142, #19)
- Test: `packages/nimbus_data/test/goals/watermark_test.dart` (after line 46, #20)
- Test: `packages/nimbus_data/test/goals/goal_service_test.dart` (in `group('alert state')` after line 161, #22; in `group('history')` after line 113, #23)

Claims re-checked against `fd6b70f`, all hold:
- #14: the only seam test (`:138-151`) is `moneySum`, whose by-day map would hide a doubled window; `_net` (`engine_goal_measurer.dart:131-134`) subtracts every expense bucket it gets.
- #17: no test measures an id with no row or a range with no rows.
- #19: none of the `malformed` entries reaches a cast; `QueryFilters.fromJson` reads `json['confirmedOnly'] as bool?` (`query_filters.dart:49`), so `"confirmedOnly":"yes"` is a `TypeError`, wrapped at `goals_dao.dart:169-170`.
- #20: no test moves a tag; `TagsDao.move` stamps `updated_at` (`app_database.dart:913-918`).
- #22: `check` is tested on a range that is over (`:154-161`) and a recurring goal not yet begun (`:217-226`), never on a fixed range not yet begun.
- #23: no test deletes a goal while `history` measures.

**Interfaces:**
- Consumes: `GoalFixture` (`expense`, `income`, `measurer`, `db`), `netSavingsGoal`, `ageMoneyRows`, `_CountingMeasurer.beforeFirstDaily`, `GoalPeriodResultsDao.forGoal → CachedPeriod(period, value, watermark, lastAlerted)`.
- Produces: none (tests only).

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-goal-data-pins
```

- [ ] **Step 2: Write the tests**

`packages/nimbus_data/test/goals/engine_goal_measurer_test.dart`, inside `group('measureDaily', ...)`, right after `a span longer than one money query keeps the days at each seam` (ends line 151):

```dart
    test('net savings across the seams subtracts each expense once',
        () async {
      // The windows of the test above. 5 January ends the first and 6
      // January starts the second, both with expenses. A window overlap
      // would read a seam day twice: harmless to moneySum's by-day map, but
      // net savings subtracts every expense bucket it is given.
      expect(
          await f.measurer.measureDaily(GoalMetric.netSavings, everything,
              const DateRange(DateKey(20251206), DateKey(20260228))),
          {
            const DateKey(20260105): const MoneyAmount(Money(-1500)),
            const DateKey(20260106): const MoneyAmount(Money(-2000)),
            const DateKey(20260107): const MoneyAmount(Money(-300)),
            const DateKey(20260110): const MoneyAmount(Money(3000)),
            const DateKey(20260201): const MoneyAmount(Money(-400)),
          });
    });
```

After the closing `});` of `group('stored paths follow their nodes (Review Focus 1)', ...)` (line 190):

```dart
  group('nothing to measure', () {
    test('a stored path whose node has no row matches nothing', () async {
      // Not even a deleted row: the path stays as stored, which matches
      // nothing. Dropping it instead would widen the goal to every category.
      final gone = MoneyScope(const QueryFilters(
          direction: MoneyDirection.expense,
          categorySubtreePaths: ['/gone/']));
      final goneTag = MoneyScope(QueryFilters(
          direction: MoneyDirection.expense, tags: TagsAny(const ['/gone/'])));

      expect(await f.measurer.measure(GoalMetric.moneySum, gone, january),
          const MoneyAmount(Money.zero));
      expect(await f.measurer.measureDaily(GoalMetric.moneySum, gone, january),
          isEmpty);
      expect(await f.measurer.measure(GoalMetric.moneySum, goneTag, january),
          const MoneyAmount(Money.zero));
      expect(
          await f.measurer
              .measure(GoalMetric.trackerCount, TrackerScope('gone'), january),
          const QuantityAmount(0));
    });

    test('a range with no rows measures zero, and no days', () async {
      const march = DateRange(DateKey(20260301), DateKey(20260331));
      for (final (metric, scope, zero) in <(GoalMetric, GoalScope, GoalAmount)>[
        (GoalMetric.moneySum, food, const MoneyAmount(Money.zero)),
        (GoalMetric.txnCount, food, const QuantityAmount(0)),
        (GoalMetric.trackerSum, TrackerScope('water'), const QuantityAmount(0)),
        (GoalMetric.trackerCount, TrackerScope('cig'), const QuantityAmount(0)),
        (GoalMetric.netSavings, everything, const MoneyAmount(Money.zero)),
      ]) {
        expect(await f.measurer.measure(metric, scope, march), zero,
            reason: metric.name);
        expect(await f.measurer.measureDaily(metric, scope, march), isEmpty,
            reason: metric.name);
      }
    });
  });
```

`packages/nimbus_data/test/goals/goals_dao_test.dart`, the `malformed` map, before (lines 141-143):

```dart
    'alert percents that are not a list': {'alert_percents': '80'},
    'an unknown period': {'period': 'fortnight'},
  };
```

After:

```dart
    'alert percents that are not a list': {'alert_percents': '80'},
    'an unknown period': {'period': 'fortnight'},
    // QueryFilters reads confirmedOnly with an `as bool?` cast, so a string
    // there is a TypeError, not a FormatException: an Error, which a caller
    // catching exceptions would let take the whole list down.
    'a filter value of the wrong JSON type': {
      'scope_json': '{"type":"money","filters":{"confirmedOnly":"yes"}}',
    },
  };
```

`packages/nimbus_data/test/goals/watermark_test.dart`, right after the `moves when a category moves under another parent` test (line 46):

```dart

    test('moves when a tag moves under another parent',
        () => expectMovedBy(() => f.db.tagsDao.move('trip', 'work')));
```

`packages/nimbus_data/test/goals/goal_service_test.dart`, inside `group('history', ...)`, right after `a period that closes after the last load is measured alone` (ends line 113):

```dart

    test('a goal deleted mid-measure caches nothing', () async {
      await seed();
      await service.save(goal);
      measurer.beforeFirstDaily = () => service.delete(goal.id);

      final result = await service.history(goal);

      expect(result.outcomes, expected,
          reason: 'the caller still gets what it asked about');
      expect(
          [
            for (final row in await f.db.goalPeriodResultsDao.forGoal(goal.id))
              if (row.value != null) row.period,
          ],
          isEmpty,
          reason: 'a deleted goal has no history to cache');
    });
```

Inside `group('alert state', ...)`, right after `a fixed range that is over does not alert` (ends line 161):

```dart

    test('a fixed range not yet begun does not alert', () async {
      // Today is 10 February; the range opens on 1 March. Income dated
      // inside it already reaches the target, so only the open-period guard
      // keeps it quiet.
      const march = DateRange(DateKey(20260301), DateKey(20260331));
      final savings = netSavingsGoal(march, target: 1000);
      await service.save(savings);
      await f.income(5000, const DateKey(20260305));

      expect(await service.check(savings), isNull);
      expect((await rowFor(savings, march))?.lastAlerted, isNull);
    });
```

- [ ] **Step 3: Run, confirm (GREEN expected: tests for correct code)**

```bash
cd packages/nimbus_data && dart test test/goals/engine_goal_measurer_test.dart test/goals/goals_dao_test.dart test/goals/watermark_test.dart test/goals/goal_service_test.dart
```

Expected: `All tests passed!` RED is not expected. Step 3b proves each test bites.

- [ ] **Step 3b: Mutation check — each test fails on a plausible bug, then revert**

Each mutation goes in a `lib` file this task does not otherwise change, so `git checkout -- <file>` reverts exactly the mutation. Run the Step 3 command after each.

1. #14 — `packages/nimbus_data/lib/src/goals/engine_goal_measurer.dart:101`: `start = start.addDays(_window)` → `start = start.addDays(_window - 1)` (overlapping windows). Expected FAIL: `net savings across the seams ...` with `20260105: MoneyAmount(-3000)`; the older moneySum seam test still passes, which is the gap this test closes. Revert: `git checkout -- packages/nimbus_data/lib/src/goals/engine_goal_measurer.dart`.
2. #17 (unknown id) — `engine_goal_measurer.dart:200`: `[for (final path in stored) now[_leafId(path)] ?? path]` → `[for (final path in stored) if (now[_leafId(path)] case final moved?) moved]` (drops an unknown path). Expected FAIL: `a stored path whose node has no row ...` with `Actual: MoneyAmount(3800)`. Revert as in 1.
3. #17 (empty range) — `packages/nimbus_data/lib/src/analytics/analytics_engine.dart:64`: `'SELECT COALESCE(SUM(t.amount), 0) AS total, COUNT(*) AS n '` → `'SELECT SUM(t.amount) AS total, COUNT(*) AS n '`. Expected FAIL: `a range with no rows ...` with a `TypeError` (null check on `total`). Revert: `git checkout -- packages/nimbus_data/lib/src/analytics/analytics_engine.dart`.
4. #19 — `packages/nimbus_data/lib/src/goals/goals_dao.dart:169-170`: delete the `on TypeError catch (error) { ... }` clause. Expected FAIL: `a filter value of the wrong JSON type makes the row unreadable, not a guess` with an uncaught `TypeError: type 'String' is not a subtype of type 'bool?' in type cast`. Revert: `git checkout -- packages/nimbus_data/lib/src/goals/goals_dao.dart`.
5. #20 — `packages/nimbus_data/lib/src/goals/goal_period_results_dao.dart`, `moneyWatermark`: replace `'UNION ALL SELECT MAX(updated_at) FROM tags)'` with `')'`. Expected FAIL: `moves when a tag moves under another parent` (`Expected: a value greater than <1>  Actual: <1>`). Revert: `git checkout -- packages/nimbus_data/lib/src/goals/goal_period_results_dao.dart`.
6. #23 — `packages/nimbus_data/lib/src/goals/goal_service.dart:80`: `if (stored is! GoalReadable || stored.goal != goal) return;` → `if (stored is GoalReadable && stored.goal != goal) return;`. Expected FAIL: `a goal deleted mid-measure caches nothing` (four periods listed). Revert: `git checkout -- packages/nimbus_data/lib/src/goals/goal_service.dart`.
7. #22 — `goal_service.dart:114` and `:117`: delete both `if (!period.contains(today)) return null;` and `if (progress.status == GoalStatus.notStarted) return null;`. Each guard alone covers this case, so both go. Expected FAIL: `a fixed range not yet begun does not alert` with `Actual: GoalAlert(... percent: 100 ...)`. Revert as in 6.

Then `git diff --stat` must list only the four test files.

- [ ] **Step 4: Implement**

Nothing: every finding here is a missing test for correct code. The Step 3b mutations are reverted.

- [ ] **Step 5: Run, confirm GREEN**

```bash
cd packages/nimbus_data && dart test test/goals/
```

Expected: `All tests passed!` (83 tests: 76 before, plus 7).

- [ ] **Step 6: Broader suite**

```bash
cd packages/nimbus_data && dart test
cd ../.. && dart analyze --fatal-infos
```

- [ ] **Step 7: Commit**

```bash
git add packages/nimbus_data/test/goals/engine_goal_measurer_test.dart \
        packages/nimbus_data/test/goals/goals_dao_test.dart \
        packages/nimbus_data/test/goals/watermark_test.dart \
        packages/nimbus_data/test/goals/goal_service_test.dart
git commit -F- <<'EOF'
test(goals): pin the data layer's untested goal paths

D25: Six paths the goals data layer handles correctly, with nothing to say so:
- net savings across the 31-day windows: an overlap would subtract a
  seam day's expenses twice, and the moneySum seam test cannot see it;
- a stored path whose node has no row, and a range with no rows, measure
  zero (a dropped path would widen the goal to every category);
- a stored filter of the wrong JSON type is a TypeError, still made an
  unreadable row rather than a crash of the whole list;
- a tag move moves the money watermark, through its tags term;
- check stays quiet on a fixed range not yet begun;
- a goal deleted while history measures leaves no cached rows.

Each test was seen to fail against a mutated implementation.

D25 #14, #17, #19, #20, #22, #23.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 15a: A counter or boolean habit target must be whole (D25 #38)

**Files:**
- Modify: `app/lib/features/goals/application/goal_editor_controller.dart` (enum `GoalEditorError` :17-24, `goalEditorErrors` :130-149, `_targetOf` :194-212)
- Modify: `app/lib/features/goals/presentation/goal_editor_screen.dart:443-450` (`_targetError`)
- Modify: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_fa.arb` (new key `goalsErrorTargetWhole`, between `goalsErrorTargetInvalid` and `goalsErrorTargetZero`)
- Regenerate: `app/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_fa.dart`
- Test: `app/test/features/goals/goal_editor_screen_test.dart` (after `a habit goal refuses zero; a habit limit saves it`, ends line 260)

**Interfaces:**
- Consumes: `TrackerValues.parseAmount`, `TrackerType` (from `package:nimbus_domain/nimbus_domain.dart`, already imported).
- Produces: `GoalEditorError.targetNotWhole`; `goalEditorErrors` returns it for a fractional counter or boolean target; `goalDraft` returns null for it; inline text `goalsErrorTargetWhole` ("Enter a whole number" / "یک عدد صحیح وارد کنید").

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-habit-whole-target
```

- [ ] **Step 2: Write the failing test**

In `app/test/features/goals/goal_editor_screen_test.dart`, right after `testWidgets('a habit goal refuses zero; a habit limit saves it', ...)`:

```dart
  testWidgets('a counter or boolean habit refuses a fraction; a quantity '
      'keeps one', (tester) async {
    // 2.5 cigarettes or 2.5 gym days is no target: their entries count
    // whole times and days.
    final cig = await trackers.create(cigarettes);
    final g = await trackers.create(gym);
    final w = await trackers.create(water);
    for (final (kind, tracker) in [
      (GoalKind.habitLimit, cig),
      (GoalKind.habitGoal, g),
    ]) {
      await openNew(tester);
      await choose(tester, kind);
      await pickTracker(tester, tracker);
      await tester.enterText(find.byKey(const Key('goal-target')), '2.5');
      await tester.pump();
      expect(find.text('Enter a whole number'), findsOneWidget,
          reason: tracker.name);
      expect(find.text('Enter a number'), findsNothing, reason: tracker.name);
      expect(save(tester), isNull, reason: tracker.name);
    }

    await openNew(tester);
    await choose(tester, GoalKind.habitGoal);
    await pickTracker(tester, w);
    await tester.enterText(find.byKey(const Key('goal-target')), '2.5');
    await tester.pump();
    expect(find.text('Enter a whole number'), findsNothing, reason: 'litres');
    expect(find.text('Enter a number'), findsNothing, reason: 'litres');
    expect(save(tester), isNotNull);
  });
```

Before running, confirm the helpers this test uses exist in the file with these names and shapes: `trackers.create`, the `cigarettes`/`gym`/`water` tracker fixtures, `openNew`, `choose`, `pickTracker`, `save`. If any differs, adapt the call to the file's real helper — do not add new helpers.

- [ ] **Step 3: Run, confirm RED**

```bash
cd app && flutter test test/features/goals/goal_editor_screen_test.dart
```

Expected: the new test fails at the first loop pass: `Expected: exactly one matching candidate  Actual: _TextWidgetFinder:<Found 0 widgets with text "Enter a whole number" ...>  Cigarettes`.

- [ ] **Step 4: Implement**

4a. `app/lib/l10n/app_en.arb`, between `goalsErrorTargetInvalid` and `goalsErrorTargetZero`:

```json
  "goalsErrorTargetInvalid": "Enter a number",
  "goalsErrorTargetWhole": "Enter a whole number",
  "goalsErrorTargetZero": "The goal must be more than zero",
```

`app/lib/l10n/app_fa.arb`, same place:

```json
  "goalsErrorTargetInvalid": "یک عدد وارد کنید",
  "goalsErrorTargetWhole": "یک عدد صحیح وارد کنید",
  "goalsErrorTargetZero": "هدف باید بیشتر از صفر باشد",
```

Then:

```bash
cd app && flutter gen-l10n
```

Expected: exits 0; the three `app/lib/l10n/app_localizations*.dart` files are modified.

4b. `app/lib/features/goals/application/goal_editor_controller.dart` — the enum, before:

```dart
enum GoalEditorError {
  nameBlank,
  targetMissing,
  targetInvalid,
  targetZero,
  endBeforeStart,
  trackerMissing,
}
```

After:

```dart
enum GoalEditorError {
  nameBlank,
  targetMissing,
  targetInvalid,
  targetNotWhole,
  targetZero,
  endBeforeStart,
  trackerMissing,
}
```

4c. In `goalEditorErrors`, before:

```dart
    if (state.targetText.trim().isEmpty)
      GoalEditorError.targetMissing
    else if (target == null)
      GoalEditorError.targetInvalid
```

After:

```dart
    if (state.targetText.trim().isEmpty)
      GoalEditorError.targetMissing
    else if (_fractionOfWholeCount(state))
      GoalEditorError.targetNotWhole
    else if (target == null)
      GoalEditorError.targetInvalid
```

4d. `_targetOf`, before:

```dart
  final value = double.tryParse(Digits.toLatin(state.targetText.trim())) == 0
      ? 0.0
      : TrackerValues.parseAmount(state.targetText);
  if (value == null) return null;
  // A duration is typed in minutes and measured in seconds.
```

After:

```dart
  final value = double.tryParse(Digits.toLatin(state.targetText.trim())) == 0
      ? 0.0
      : TrackerValues.parseAmount(state.targetText);
  if (value == null || _fractionOfWholeCount(state)) return null;
  // A duration is typed in minutes and measured in seconds.
```

And directly after `_targetOf`'s closing brace, add:

```dart
/// A counter counts times and a boolean days, so a fraction is no target.
bool _fractionOfWholeCount(GoalEditorState state) {
  final type = state.tracker?.type;
  if (type != TrackerType.counter && type != TrackerType.boolean) return false;
  final value = TrackerValues.parseAmount(state.targetText);
  return value != null && value != value.roundToDouble();
}
```

4e. `app/lib/features/goals/presentation/goal_editor_screen.dart`, `_targetError`, before:

```dart
  ) => errors.contains(GoalEditorError.targetInvalid)
      ? l10n.goalsErrorTargetInvalid
      : errors.contains(GoalEditorError.targetZero)
      ? l10n.goalsErrorTargetZero
      : null;
```

After:

```dart
  ) => errors.contains(GoalEditorError.targetInvalid)
      ? l10n.goalsErrorTargetInvalid
      : errors.contains(GoalEditorError.targetNotWhole)
      ? l10n.goalsErrorTargetWhole
      : errors.contains(GoalEditorError.targetZero)
      ? l10n.goalsErrorTargetZero
      : null;
```

Then grep for any exhaustive `switch` over `GoalEditorError` that the new value breaks:

```bash
grep -rn "GoalEditorError\." app/lib app/test | grep -v "targetInvalid\|targetZero\|targetMissing\|nameBlank\|endBeforeStart\|trackerMissing\|targetNotWhole"
```

Expected: no output. `dart analyze` in Step 6 catches a non-exhaustive switch if one exists.

- [ ] **Step 5: Run, confirm GREEN**

```bash
cd app && flutter test test/features/goals/goal_editor_screen_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6: Broader suite**

```bash
cd app && flutter test --concurrency=4
cd .. && dart analyze --fatal-infos
```

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/goals/application/goal_editor_controller.dart \
        app/lib/features/goals/presentation/goal_editor_screen.dart \
        app/lib/l10n/app_en.arb app/lib/l10n/app_fa.arb \
        app/lib/l10n/app_localizations.dart \
        app/lib/l10n/app_localizations_en.dart \
        app/lib/l10n/app_localizations_fa.dart \
        app/test/features/goals/goal_editor_screen_test.dart
git commit -F- <<'EOF'
fix(goals): a counter or boolean habit target must be whole

D25: The editor accepted "2.5" as a target for cigarettes or gym days. Their
entries count whole times and days, so such a goal could never be met
exactly and its card read "3 of 2.5". A fractional target on a counter or
boolean tracker now blocks the save with "Enter a whole number" ("Enter a
number" would be wrong: 2.5 is a number). Quantities (litres) and durations
(minutes) keep their fractions.

D25 #38.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 15b: The detail's tracker loading and error states (D25 #46)

**Files:**
- Modify: `app/lib/features/goals/presentation/goal_detail_screen.dart:107-120` (`_TrackerGoalDetail.build`: two keys)
- Test: `app/test/features/goals/goal_detail_screen_test.dart` (one import; new group at the end of `main`, after line 342)

**Interfaces:**
- Consumes: `trackerByIdProvider` (`StreamProvider.autoDispose.family<Tracker?, String>`), `NimbusErrorState`, `NimbusLoadingList`.
- Produces: keys `goal-detail-tracker-loading` and `goal-detail-tracker-error`.

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-goal-detail-tracker-states
```

- [ ] **Step 2: Write the failing tests**

`app/test/features/goals/goal_detail_screen_test.dart`, add to the imports (after `package:nimbustats/features/goals/routes.dart`):

```dart
import 'package:nimbustats/features/trackers/application/tracker_providers.dart';
```

At the end of `main`, after `a failed progress load says so, and Retry runs it again` (line 342):

```dart

  group("a tracker goal's tracker", () {
    late Tracker w;

    setUp(() async {
      w = await repositoryFor(db, fake).create(water);
      await service.save(habitGoal(w,
          id: 'water',
          metric: GoalMetric.trackerSum,
          direction: GoalDirection.atLeast,
          target: 2));
    });

    testWidgets('loading shows the skeleton', (tester) async {
      final never = StreamController<Tracker?>();
      addTearDown(never.close);

      await pumpGoals(tester, db, fake,
          location: goalDetailRoute('water'),
          overrides: [
            trackerByIdProvider(w.id).overrideWith((ref) => never.stream),
          ]);

      expect(find.byKey(const Key('goal-detail-tracker-loading')),
          findsOneWidget);
      expect(find.byKey(const Key('goal-detail')), findsNothing);
    });

    testWidgets('a failed read says so, hides the raw error, and Retry '
        'reads again and shows the goal', (tester) async {
      var calls = 0;
      await pumpGoals(tester, db, fake,
          location: goalDetailRoute('water'),
          overrides: [
            trackerByIdProvider(w.id).overrideWith((ref) {
              if (++calls == 1) return Stream<Tracker?>.error(Exception('boom'));
              return Stream.value(w);
            }),
          ]);

      expect(find.byKey(const Key('goal-detail-tracker-error')),
          findsOneWidget);
      expect(find.text('Could not load your goals'), findsOneWidget);
      expect(find.text('Exception: boom'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.byKey(const Key('goal-detail')), findsOneWidget);
    });
  });
```

- [ ] **Step 3: Run, confirm RED**

```bash
cd app && flutter test test/features/goals/goal_detail_screen_test.dart
```

Expected: both new tests fail on their key: `Found 0 widgets with key [<'goal-detail-tracker-loading'>]` and `... [<'goal-detail-tracker-error'>]`.

- [ ] **Step 4: Implement**

`app/lib/features/goals/presentation/goal_detail_screen.dart`, before (lines 107-120):

```dart
    if (tracker.hasError) {
      return Scaffold(
        appBar: AppBar(),
        body: NimbusErrorState(
          title: l10n.goalsErrorTitle,
          retryLabel: l10n.commonRetry,
          detail: tracker.error.toString(),
          onRetry: () => ref.invalidate(trackerByIdProvider(trackerId)),
        ),
      );
    }
    if (!tracker.hasValue) {
      return Scaffold(appBar: AppBar(), body: const NimbusLoadingList());
    }
```

After:

```dart
    if (tracker.hasError) {
      return Scaffold(
        appBar: AppBar(),
        body: NimbusErrorState(
          key: const Key('goal-detail-tracker-error'),
          title: l10n.goalsErrorTitle,
          retryLabel: l10n.commonRetry,
          detail: tracker.error.toString(),
          onRetry: () => ref.invalidate(trackerByIdProvider(trackerId)),
        ),
      );
    }
    if (!tracker.hasValue) {
      return Scaffold(
        appBar: AppBar(),
        body: const NimbusLoadingList(key: Key('goal-detail-tracker-loading')),
      );
    }
```

- [ ] **Step 5: Run, confirm GREEN**

```bash
cd app && flutter test test/features/goals/goal_detail_screen_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 6: Broader suite**

```bash
cd app && flutter test --concurrency=4
cd .. && dart analyze --fatal-infos
```

- [ ] **Step 7: Commit**

```bash
git add app/lib/features/goals/presentation/goal_detail_screen.dart \
        app/test/features/goals/goal_detail_screen_test.dart
git commit -F- <<'EOF'
test(goals): the detail's tracker loading and error states

D25: A tracker goal's detail waits for its tracker and shows a skeleton, or an
error with Retry when the read fails. Neither branch had a key or a test,
so either could break silently. Both get keys, and tests that load, fail,
retry and land on the goal.

D25 #46.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 15c: Pin the goal screens' remaining gaps (D25 #30, #31, #44, #49, #51)

**Files:**
- Test: `app/test/features/goals/goal_watcher_test.dart` (add `import 'dart:async';`; new test after line 314, #30)
- Test: `app/test/features/goals/goals_screen_test.dart` (new test after line 322, #31)
- Test: `app/test/features/goals/goal_detail_screen_test.dart` (new test after line 252, #44)
- Test: `app/test/features/goals/goal_alert_listener_test.dart` (new test in `group('on a fake clock')` after line 157, #49)
- Test: `app/test/features/goals/goal_editor_screen_test.dart:605-694` (#51)

Claims re-checked against `fd6b70f`, all hold:
- #30: the watcher's only error test (`:298-314`) never lets the stream recover.
- #31: the 2x tests (`goals_screen_test.dart:310-322`, fa) build a cap and a savings card only.
- #44: `the bar speaks its goal's name and its percent` (`goal_detail_screen_test.dart:238-252`) is English only.
- #49: no listener test reaches `_periodOf`'s `'other'` (`goal_alert_listener.dart:84-91`).
- #51: `muteReports` (`goal_editor_screen_test.dart:607-611`) swallows every report. It is probably inert today: the edit route is a top-level route, so no shell, no `GoalAlertListener`, no watcher to report. The selective mute below keeps the spec's design and is GREEN either way.

**Interfaces:**
- Consumes: `goalsProvider`, `GoalWatcher`, `GoalProgressBar` (in `goal_card.dart`), `_Plain` problem card, `insertUnreadableGoal`, `goalServiceFor`.
- Produces: test helper `muteReportsOf(Object own)` (replaces `muteReports`).

- [ ] **Step 1: Tag the rollback target**

```bash
git tag pre-goal-app-pins
```

- [ ] **Step 2: Write the tests**

**#30** — `app/test/features/goals/goal_watcher_test.dart`. Add as the first line:

```dart
import 'dart:async';

```

After `test('a goals stream that errors is reported once, not swallowed', ...)` (ends line 314):

```dart

  test('after a goals-stream error, the next list still evaluates', () async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);

    await service.save(spendingCap()); // the baseline: nothing spent
    await spend(db, 850000, day5); // crossed while the stream was down
    final goals = StreamController<List<GoalRead>>();
    addTearDown(goals.close);
    await start(extra: [goalsProvider.overrideWith((ref) => goals.stream)]);

    goals.addError(StateError('goals stream failed'));
    await until(() => reports.isNotEmpty, 'the report');
    await settle();
    expect(alerts, isEmpty, reason: 'no list yet, nothing evaluated');

    goals.add(await service.goals());
    await until(() => alerts.length == 1, 'the evaluation after recovery');
    expect(percents(), [80]);
    expect(reports, hasLength(1));
  });
```

**#31** — `app/test/features/goals/goals_screen_test.dart`, after `at twice the font size the tab overflows nothing` (ends line 322):

```dart

  testWidgets('at twice the font size the problem, unreadable and paused '
      'cards overflow nothing', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // 800 x 2000 logical: tall enough that the list lays out every card.
    tester.view.physicalSize = const Size(2400, 6000);
    addTearDown(tester.view.resetPhysicalSize);
    final w = await trackers.create(water);
    await service.save(habitGoal(w,
        id: 'water',
        metric: GoalMetric.trackerSum,
        direction: GoalDirection.atLeast,
        target: 2));
    await db.customStatement(
        'UPDATE trackers SET deleted_at = 1 WHERE id = ?', [w.id]);
    await insertUnreadableGoal(db);
    final fuel =
        spendingCap(id: 'fuel', name: 'Fuel', paths: const [transportPath]);
    await service.save(fuel);
    await service.setActive(fuel, false);

    await pumpGoals(tester, db, fake);

    expect(find.byKey(const Key('goal-problem-water')), findsOneWidget);
    expect(find.byKey(const Key('goal-problem-bad')), findsOneWidget);
    expect(inCard('fuel', find.text('Paused')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
```

**#44** — `app/test/features/goals/goal_detail_screen_test.dart`, after `the bar speaks its goal's name and its percent` (ends line 252):

```dart

  testWidgets('in Persian the bar speaks its percent in Persian digits',
      (tester) async {
    // A progress bar's own semantics must carry a Latin number (Flutter's
    // debug check), so the bar's Persian percent lives on its container.
    final handle = tester.ensureSemantics();
    await seedHistory(); // default settings: Persian digits

    await openDetail(tester, locale: const Locale('fa'));

    final data = tester
        .getSemantics(find.byType(LinearProgressIndicator))
        .getSemanticsData();
    expect(data.label, 'Dining out');
    expect(data.value, '۳۰٪');
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
```

**#49** — `app/test/features/goals/goal_alert_listener_test.dart`, inside `group('on a fake clock', ...)`, after `View opens the goal's detail` (ends line 157):

```dart

    testWidgets('an alert for a goal no longer listed reads plainly',
        (tester) async {
      // A goal deleted between its evaluation and its snackbar: the listener
      // finds no period type, and the message's `other` case speaks. The
      // empty list stands in for the goals stream after the delete; the
      // watcher's own one-shot read still finds the goal.
      await useEnglishDigits(db);
      await service.save(spendingCap());
      await spend(db, 850000, day5);

      await pumpGoals(tester, db, fake, overrides: [
        goalsProvider
            .overrideWith((ref) => Stream<List<GoalRead>>.value(const [])),
      ]);
      await letTheWatcherRun(tester);

      expect(find.text('Dining out: 85% of the limit'), findsOneWidget);
    });
```

**#51** — `app/test/features/goals/goal_editor_screen_test.dart`, before (lines 606-611):

```dart
    /// Reports the watcher makes of a failed read are not under test here.
    void muteReports() {
      final previous = FlutterError.onError;
      FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = previous);
    }
```

After:

```dart
    /// Swallows reports of [own], the test's own failed read, which these
    /// tests do not assert on. Every other report still reaches the test
    /// binding, so an unrelated framework error fails the test.
    void muteReportsOf(Object own) {
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (identical(details.exception, own)) return;
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);
    }

    test('the mute passes every other report through', () {
      final seen = <Object>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) => seen.add(details.exception);
      addTearDown(() => FlutterError.onError = previous);
      final own = Exception('boom');
      final other = StateError('unrelated');
      muteReportsOf(own);

      FlutterError.reportError(FlutterErrorDetails(exception: own));
      FlutterError.reportError(FlutterErrorDetails(exception: other));

      expect(seen, [same(other)]);
    });
```

Before (lines 625-639):

```dart
    testWidgets('a failed goals read says so, hides the raw error, and Retry '
        'reads again and shows the form', (tester) async {
      muteReports();
      await useEnglishDigits(db);
      await service.save(spendingCap());
      var calls = 0;

      await pumpGoals(tester, db, fake, location: editGoalRoute('cap'),
          overrides: [
            goalsProvider.overrideWith((ref) {
              if (++calls == 1) {
                return Stream<List<GoalRead>>.error(Exception('boom'));
              }
              return db.goalsDao.watchAll();
            }),
          ]);
```

After:

```dart
    testWidgets('a failed goals read says so, hides the raw error, and Retry '
        'reads again and shows the form', (tester) async {
      final boom = Exception('boom');
      muteReportsOf(boom);
      await useEnglishDigits(db);
      await service.save(spendingCap());
      var calls = 0;

      await pumpGoals(tester, db, fake, location: editGoalRoute('cap'),
          overrides: [
            goalsProvider.overrideWith((ref) {
              if (++calls == 1) {
                return Stream<List<GoalRead>>.error(boom);
              }
              return db.goalsDao.watchAll();
            }),
          ]);
```

Before (lines 669-682):

```dart
    testWidgets("a failed tracker read says so, hides the raw error, and "
        'Retry reads again and shows the form', (tester) async {
      muteReports();
      final w = await trackers.create(water);
      await service.save(habitGoal(w, id: 'water'));
      var calls = 0;

      await pumpGoals(tester, db, fake,
          location: editGoalRoute('water'),
          overrides: [
            trackerByIdProvider(w.id).overrideWith((ref) {
              if (++calls == 1) return Stream<Tracker?>.error(Exception('boom'));
              return Stream.value(w);
            }),
          ]);
```

After:

```dart
    testWidgets("a failed tracker read says so, hides the raw error, and "
        'Retry reads again and shows the form', (tester) async {
      final boom = Exception('boom');
      muteReportsOf(boom);
      final w = await trackers.create(water);
      await service.save(habitGoal(w, id: 'water'));
      var calls = 0;

      await pumpGoals(tester, db, fake,
          location: editGoalRoute('water'),
          overrides: [
            trackerByIdProvider(w.id).overrideWith((ref) {
              if (++calls == 1) return Stream<Tracker?>.error(boom);
              return Stream.value(w);
            }),
          ]);
```

The two `expect(find.text('Exception: boom'), findsNothing)` lines stay as they are.

- [ ] **Step 3: Run, confirm (GREEN expected: tests for correct code)**

```bash
cd app && flutter test test/features/goals/
```

Expected: `All tests passed!` RED is not expected, with one exception: if #31 fails with `A RenderFlex overflowed`, that is a real 2x bug in a card. Stop and report it as a deferred item; do not change the test. Step 3b proves each test bites.

- [ ] **Step 3b: Mutation check — each test fails on a plausible bug, then revert**

One at a time. Run `cd app && flutter test test/features/goals/` after each.

1. #30 — `app/lib/features/goals/application/goal_watcher.dart:81`: `if (next.hasValue && !(previous?.hasValue ?? false)) {` → `if (next.hasValue && (previous?.isLoading ?? true)) {` (only a loading→data change counts as the first list). Expected FAIL: `after a goals-stream error, ...` with `timed out waiting for the evaluation after recovery`. Revert: `git checkout -- app/lib/features/goals/application/goal_watcher.dart`.
2. #31 — `app/lib/features/goals/presentation/widgets/goal_card.dart:311`: `Expanded(child: Text(message, key: messageKey)),` → `Text(message, key: messageKey),`. Expected FAIL: `... problem, unreadable and paused cards overflow nothing` (a `RenderFlex overflowed` exception: at 2x the test font's 28-point glyphs make "This goal's tracker was deleted" about 868 points in a 704-point row). Revert: `git checkout -- app/lib/features/goals/presentation/widgets/goal_card.dart`. The paused card has no layout-sensitive element; it is pinned only for being built at 2x.
3. #44 — `goal_card.dart:391`: `value: ref.watch(goalFormatProvider).percent(fraction),` → `value: '${(fraction * 100).floor()}%',`. Expected FAIL: `in Persian the bar speaks ...` with `Expected: '۳۰٪'  Actual: '30%'`. Revert as in 2.
4. #49 — `app/lib/features/goals/presentation/goal_alert_listener.dart:90`: `return 'other';` → `return 'month';`. Expected FAIL: `an alert for a goal no longer listed reads plainly` (the snackbar says `this month's limit`). Revert: `git checkout -- app/lib/features/goals/presentation/goal_alert_listener.dart`.
5. #51 — in the test file itself, `muteReportsOf`: replace `if (identical(details.exception, own)) return;` with `return;`. Expected FAIL: `the mute passes every other report through` (`Expected: [same(other)]  Actual: []`). Revert that one line by hand (`git checkout` would drop this task's test changes).

Then `git diff --stat` must list only the five test files.

- [ ] **Step 4: Implement**

Nothing in `lib`: the findings are missing or over-broad tests. The Step 3b mutations are reverted.

- [ ] **Step 5: Run, confirm GREEN**

```bash
cd app && flutter test test/features/goals/
```

Expected: `All tests passed!`

- [ ] **Step 6: Broader suite**

```bash
cd app && flutter test --concurrency=4
cd .. && dart analyze --fatal-infos
```

- [ ] **Step 7: Commit**

```bash
git add app/test/features/goals/goal_watcher_test.dart \
        app/test/features/goals/goals_screen_test.dart \
        app/test/features/goals/goal_detail_screen_test.dart \
        app/test/features/goals/goal_alert_listener_test.dart \
        app/test/features/goals/goal_editor_screen_test.dart
git commit -F- <<'EOF'
test(goals): pin the goal screens' remaining review gaps

D25: Five behaviours the goal screens get right, with nothing to say so:
- the watcher evaluates again once a failed goals stream delivers a list;
- the problem, unreadable and paused cards hold at twice the font size
  (the 2x tests built only a cap and a savings card);
- the detail's bar speaks its percent in Persian digits, without tripping
  the progress-bar semantics check;
- an alert for a goal no longer listed reads plainly, through `other`;
- the editor's state tests mute only their own failed read, so an
  unrelated framework error there now fails the test instead of vanishing.

Each test was seen to fail against a mutated implementation.

D25 #30, #31, #44, #49, #51.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 16: A torn buffer line no longer swallows the next tap (D29)

Slug `torn-append`. Commits on `fix/deferred-0-6` directly (spec, Process).

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetBuffer.kt`
- Create: `app/android/app/src/test/kotlin/com/nimbustats/app/widget/WidgetBufferTest.kt`

**Interfaces:**
- New: `internal fun WidgetBuffer.appendLine(target: File, line: String)`. It is not `@Synchronized` itself: its only production caller is the private `append`, reached from the `@Synchronized` `appendExpense` and `appendTrackerTap`, which already hold the lock.
- Unchanged: `appendExpense`, `appendTrackerTap`, `lines`, `pendingTaps`, `commit`.
- Checked against the code: `WidgetBuffer` is an `object` whose static state is three `const val`s, so loading it on the JVM runs no Android code. `appendLine` touches only `java.io`. The test needs no `Context`. AGP puts its mockable `android.jar` on the unit-test classpath, so the class's `Context`/`JSONObject` references resolve. Nothing on this path calls them. The test file imports no `android.*` and no `org.json`.

- [ ] **Step 1: Tag the rollback target**

```bash
cd /c/Users/nimae/Desktop/nimbustats
git status --short          # expect only the three untracked bash.exe.stackdump files
git tag pre-torn-append
```

- [ ] **Step 2: Write the failing test**

Create `app/android/app/src/test/kotlin/com/nimbustats/app/widget/WidgetBufferTest.kt`:

```kotlin
package com.nimbustats.app.widget

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class WidgetBufferTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val earlier = """{"v":1,"id":"a","kind":"tracker","atUtc":1,"trackerId":"t"}"""

    /** What a power loss mid-append leaves: the start of a line and no newline. */
    private val torn = """{"v":1,"id":"b","kind":"trac"""

    private val next = """{"v":1,"id":"c","kind":"tracker","atUtc":3,"trackerId":"t"}"""

    private fun buffer(content: String? = null): File =
        File(folder.root, "widget_buffer.jsonl").apply { if (content != null) writeText(content) }

    @Test
    fun aTornTailIsClosedSoTheNextTapStartsItsOwnLine() { // D29
        val file = buffer("$earlier\n$torn")

        WidgetBuffer.appendLine(file, next)

        assertEquals("$earlier\n$torn\n$next\n", file.readText())
    }

    @Test
    fun aCleanFileGetsNoBlankLine() {
        val file = buffer("$earlier\n")

        WidgetBuffer.appendLine(file, next)

        assertEquals("$earlier\n$next\n", file.readText())
    }

    @Test
    fun aMissingFileIsCreatedHoldingTheLine() {
        val file = buffer()

        WidgetBuffer.appendLine(file, next)

        assertEquals("$next\n", file.readText())
    }
}
```

- [ ] **Step 3: Run it and confirm RED**

```bash
cd /c/Users/nimae/Desktop/nimbustats/app/android
./gradlew :app:testDebugUnitTest --tests "com.nimbustats.app.widget.WidgetBufferTest"
```

Expected: `> Task :app:compileDebugUnitTestKotlin FAILED` and `BUILD FAILED`. The errors point at `WidgetBufferTest.kt` and name `appendLine`. Kotlin 2.4 reports either `Unresolved reference 'appendLine'.` or "none of the following candidates is applicable", listing the stdlib's `Appendable.appendLine`. `./gradlew` runs under Git Bash; checked on 2026-10-14, when `:app:testDebugUnitTest` passed in 30 s. If it fails there, run `gradlew.bat` from PowerShell with the same arguments.

- [ ] **Step 4: Implement**

In `WidgetBuffer.kt`, the imports. Before:

```kotlin
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import org.json.JSONObject
```

After:

```kotlin
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import org.json.JSONObject
```

The append. Before:

```kotlin
    private fun append(context: Context, json: JSONObject) {
        FileOutputStream(file(context, BUFFER), true).use { out ->
            out.write((json.toString() + "\n").toByteArray())
            out.fd.sync()
        }
    }
```

After:

```kotlin
    private fun append(context: Context, json: JSONObject) = appendLine(file(context, BUFFER), json.toString())

    /**
     * Appends [line] and syncs it to disk. Its callers hold the lock.
     *
     * A file whose last byte is not a newline ends in a line torn by a crash or power loss
     * mid-append. The new line then starts on a fresh line, so the drain rejects only the torn
     * line, never the tap that would have been glued onto it (D29).
     */
    internal fun appendLine(target: File, line: String) {
        val torn = target.length() > 0 && RandomAccessFile(target, "r").use { file ->
            file.seek(file.length() - 1)
            file.read() != '\n'.code
        }
        FileOutputStream(target, true).use { out ->
            out.write(((if (torn) "\n" else "") + line + "\n").toByteArray())
            out.fd.sync()
        }
    }
```

`File.length()` is 0 for a missing file, so a missing file skips the read. A directory in the file's place throws `FileNotFoundException`, an `IOException`, as the old `FileOutputStream` did. The callers' catches are unchanged (D26's device check relies on this).

- [ ] **Step 5: Confirm GREEN**

```bash
cd /c/Users/nimae/Desktop/nimbustats/app/android
./gradlew :app:testDebugUnitTest --tests "com.nimbustats.app.widget.WidgetBufferTest"
grep -o 'tests="[0-9]*" skipped="[0-9]*" failures="[0-9]*" errors="[0-9]*"' \
  ../build/app/test-results/testDebugUnitTest/TEST-com.nimbustats.app.widget.WidgetBufferTest.xml
```

Expected: `BUILD SUCCESSFUL`, then `tests="3" skipped="0" failures="0" errors="0"`.

- [ ] **Step 6: Broader suite and the APK**

```bash
cd /c/Users/nimae/Desktop/nimbustats/app/android
./gradlew :app:testDebugUnitTest
grep -ho 'name="[^"]*" tests="[0-9]*" skipped="[0-9]*" failures="[0-9]*" errors="[0-9]*"' \
  ../build/app/test-results/testDebugUnitTest/*.xml
cd /c/Users/nimae/Desktop/nimbustats/app && flutter build apk --debug
```

Expected:
- `BUILD SUCCESSFUL`, with five suites: `ReminderTimeTest` 14, `AmountParserTest` 6, `PendingOverlayTest` 6, `Uuid7Test` 4 and `WidgetBufferTest` 3. That is 33 tests, all with `failures="0" errors="0"`.
- `✓ Built build\app\outputs\flutter-apk\app-debug.apk`.

- [ ] **Step 7: Commit**

```bash
cd /c/Users/nimae/Desktop/nimbustats
git add app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetBuffer.kt \
        app/android/app/src/test/kotlin/com/nimbustats/app/widget/WidgetBufferTest.kt
git commit -m "$(cat <<'EOF'
fix(widget): an append after a torn line starts a fresh one

D29: a power loss inside an append leaves the buffer ending in a partial
line with no newline. The next tap was written straight after it, so the
drain read one joined line, rejected it, and lost the good tap with the
torn one.

The append now reads the file's last byte first and, when it is not a
newline, writes one before the new line: only the torn line is rejected
and reported, and the tap after it drains. The body moved into an
internal appendLine(File, String) so it runs on the JVM without a
Context (WidgetBufferTest: a torn tail, a clean file with no blank line,
a missing file). The cost is one byte read under the lock already held.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git log -1 --format='%h %s'
```

---

### Task 17: A render failure never escapes the widget's entry points (D26)

Slug `render-guard`.

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetRenderer.kt` (`build`)
- Modify: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/ExpenseWidgetProvider.kt` (`onAppWidgetOptionsChanged`)
- Modify: `app/android/app/src/main/kotlin/com/nimbustats/app/OutsideChannelHandler.kt` (`renderWidget`)
- Modify: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetActionReceiver.kt` (`render`)

**Interfaces:**
- No signature changes. Log lines in logcat tag `NimbuStats`, which the device check greps for:
  - `widget render failed; showing the loading state`: `build`'s own catch, text unchanged.
  - `widget render failed on resize`: new, in `onAppWidgetOptionsChanged`.
  - `widget render failed after the write`: the channel's catch, now catching `Exception`.
  - `widget render failed`: the receiver's catch, now catching `Exception`.
- Every caller of `WidgetRenderer.renderAll`, checked with `grep -rn "renderAll" app/android/app/src/main/kotlin`:

  | Caller | Guard before | Guard after |
  |---|---|---|
  | `ExpenseWidgetProvider.onUpdate` | `catch (Exception)` | unchanged |
  | `ExpenseWidgetProvider.onAppWidgetOptionsChanged` | none | `catch (Exception)` |
  | `OutsideChannelHandler.renderWidget` | `RuntimeException` | `Exception` |
  | `WidgetActionReceiver.render` | `RuntimeException` | `Exception` |
  | `RearmReceiver.onReceive` | `catch (Exception)` | unchanged |

- [ ] **Step 1: Tag the rollback target**

```bash
cd /c/Users/nimae/Desktop/nimbustats && git tag pre-render-guard
```

- [ ] **Step 2: No host test; the device check run in Task 21 Step 6**

`build` needs a `Context`, `AppWidgetManager` and `RemoteViews`, all `android.*`. The operator ruled out Robolectric (spec, decisions). So a device check replaces the one JUnit test DEFERRED asked for.

The check puts a **directory** where `files/widget_buffer.jsonl` should be. `WidgetBuffer.pendingTaps` then throws `FileNotFoundException … EISDIR`, an `IOException`, inside `build`. It drives three entry points:
- a `RearmReceiver` broadcast, the only render entry point the shell can send;
- a resize, by the operator's hand. `onAppWidgetOptionsChanged` has no adb path: `AppWidgetProvider` dispatches it only when the intent carries an `EXTRA_APPWIDGET_OPTIONS` **Bundle**, which `am broadcast` cannot build. Resize drags on the A53's launcher are not reliably synthesisable (memory `device-check-over-adb`);
- an app start, whose `writeSnapshot` renders through the channel.

Every block starts by setting `S` to the executing session's scratchpad in Git Bash form, then sourcing the helpers from Task 21 Step 1:

```bash
S=/c/Users/nimae/AppData/Local/Temp/claude/C--Users-nimae-Desktop-nimbustats/<this session>/scratchpad
source "$S/device/helpers.sh"
```

Here `<this session>` is the session directory the executing session's system prompt names. It is the same in every block. In each block below, those two lines are written as `source "$S/device/helpers.sh"`.

**D26-1, preconditions:**

```bash
source "$S/device/helpers.sh"; guard || exit 1
a shell dumpsys appwidget | grep -c "com.nimbustats.app.widget.ExpenseWidgetProvider"
a shell "run-as $PKG ls -la files/"
```

Expected:
- The count is at least 1, so a widget is placed.
- `widget_buffer.jsonl` is absent or 0 bytes. **If it holds bytes, taps are pending: stop.** Ask the operator to open the app once, which drains them, then re-run D26-1.

**D26-2, a directory in place of the buffer:**

```bash
source "$S/device/helpers.sh"; guard || exit 1
a shell "run-as $PKG sh -c 'if [ -f files/widget_buffer.jsonl ]; then mv files/widget_buffer.jsonl files/widget_buffer.jsonl.d26; fi; mkdir files/widget_buffer.jsonl'"
a shell "run-as $PKG ls -la files/"
```

Expected: `drwx… widget_buffer.jsonl`, plus `widget_buffer.jsonl.d26` if the file existed.

Tell the operator: until D26-5, a widget row tap or a Save in its dialog is not logged, by design.

**D26-3, a re-render from the shell:**

```bash
source "$S/device/helpers.sh"; guard || exit 1
a logcat -c
a shell am broadcast -n $PKG/.notifications.RearmReceiver -a com.nimbustats.check.D26
pause 3
a logcat -d -s NimbuStats:E AndroidRuntime:E > "$S/device/d26-rearm.log"; cat "$S/device/d26-rearm.log"
shot d26-loading
```

Expected:
- `E NimbuStats: widget render failed; showing the loading state`, then `java.io.FileNotFoundException: /data/user/0/com.nimbustats.app/files/widget_buffer.jsonl: open failed: EISDIR (Is a directory)`. That means the read now runs inside `build`'s `try`.
- **No** `widget render failed after a re-arm`. That line would mean the exception escaped `build`.
- No `FATAL EXCEPTION`.
- `d26-loading.png` shows the widget's loading state, the app icon.

The broadcast also re-arms the reminder. Inside the reminder's delivery window, that is up to an hour after its time while it is still undelivered, it posts the reminder now (`a2ece7a`). Run this outside that window: the time is recorded in Task 21 Step 1.

**D26-4, a resize (`onAppWidgetOptionsChanged`), by hand:**

```bash
source "$S/device/helpers.sh"; guard || exit 1
a shell pidof $PKG
a logcat -c
```

Ask the operator: "Please long-press the NimbuStats widget, drag its bottom handle one cell down, release, and tap the empty home screen. Then do the same back to its old size."

```bash
source "$S/device/helpers.sh"
a logcat -d -s NimbuStats:E AndroidRuntime:E > "$S/device/d26-resize.log"; cat "$S/device/d26-resize.log"
a logcat -d -b crash
a shell pidof $PKG
```

Expected:
- At least one `widget render failed; showing the loading state`, typically one per size change.
- No `widget render failed on resize`.
- No `FATAL EXCEPTION`, and the crash buffer is empty.
- The pid is the same as before.

**D26-5, an app start (`writeSnapshot` → `renderWidget`):**

```bash
source "$S/device/helpers.sh"; guard || exit 1
a logcat -c
a shell monkey -p $PKG -c android.intent.category.LAUNCHER 1
pause 8
a logcat -d -s NimbuStats:E AndroidRuntime:E > "$S/device/d26-app.log"; cat "$S/device/d26-app.log"
a shell input keyevent KEYCODE_HOME
```

Expected:
- `widget render failed; showing the loading state`.
- **No** `outside channel: writeSnapshot failed`. That line was the old symptom: the `IOException` passed `renderWidget`'s `RuntimeException` catch and the channel reported a written snapshot as failed.
- Also expected, and harmless: `outside channel: takeBuffer failed …`. The drain cannot read a directory, and Dart reports it. Both builds log it.

**D26-6, restore:**

```bash
source "$S/device/helpers.sh"; guard || exit 1
a shell "run-as $PKG sh -c 'rmdir files/widget_buffer.jsonl && if [ -f files/widget_buffer.jsonl.d26 ]; then mv files/widget_buffer.jsonl.d26 files/widget_buffer.jsonl; fi'"
a shell "run-as $PKG ls -la files/"
a logcat -c
a shell am broadcast -n $PKG/.notifications.RearmReceiver -a com.nimbustats.check.D26
pause 3
a logcat -d -s NimbuStats:E
shot d26-restored
```

Expected:
- `widget_buffer.jsonl` is a regular file again, or absent.
- No `NimbuStats` error lines.
- `d26-restored.png` shows the populated widget.

Record D26-3 to D26-6 in `$S/device/results.md`.

- [ ] **Step 3: RED**

n/a, device-verified in Task 21 Step 6.

- [ ] **Step 4: Implement**

`WidgetRenderer.kt`, `build`. Before:

```kotlin
    private fun build(context: Context): RemoteViews {
        // One lock hold for both reads (P18): a commit cannot land between them, so a tap is
        // never counted twice (new snapshot + still pending) or not at all. Views are built outside.
        val (snapshot, pending) = synchronized(WidgetBuffer) {
            WidgetSnapshot.read(context) to WidgetBuffer.pendingTaps(context)
        }
        if (snapshot == null) return loading(context)
        return try {
            val rows = rows(snapshot, pending)
```

After:

```kotlin
    private fun build(context: Context): RemoteViews {
        // The reads are inside the try too (D26): an unreadable buffer is the loading state, not
        // an exception for the receiver, the channel or a resize to handle.
        return try {
            // One lock hold for both reads (P18): a commit cannot land between them, so a tap is
            // never counted twice (new snapshot + still pending) or not at all. Views are built outside.
            val (snapshot, pending) = synchronized(WidgetBuffer) {
                WidgetSnapshot.read(context) to WidgetBuffer.pendingTaps(context)
            }
            if (snapshot == null) return loading(context)
            val rows = rows(snapshot, pending)
```

The rest of `build` is unchanged: the `if (Build.VERSION.SDK_INT >= 31) … else …` expression and the `catch (error: Exception)` that logs `widget render failed; showing the loading state`.

`ExpenseWidgetProvider.kt`. Before:

```kotlin
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        WidgetRenderer.renderAll(context)
    }
```

After:

```kotlin
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        // A resize is a system broadcast: anything escaping here would crash the app's process.
        try {
            WidgetRenderer.renderAll(context)
        } catch (error: Exception) {
            Log.e(TAG, "widget render failed on resize", error)
        }
    }
```

`OutsideChannelHandler.kt`, `renderWidget`. Before:

```kotlin
        } catch (error: RuntimeException) {
            Log.e(TAG, "widget render failed after the write", error)
        }
```

After:

```kotlin
        } catch (error: Exception) {
            Log.e(TAG, "widget render failed after the write", error)
        }
```

`WidgetActionReceiver.kt`, `render`. Before:

```kotlin
    private fun render(context: Context) {
        try {
            WidgetRenderer.renderAll(context)
        } catch (error: RuntimeException) {
            Log.e(TAG, "widget render failed", error)
        }
    }
```

After:

```kotlin
    private fun render(context: Context) {
        try {
            WidgetRenderer.renderAll(context)
        } catch (error: Exception) {
            Log.e(TAG, "widget render failed", error)
        }
    }
```

The append's two catches in `onReceive` (`IOException`, then `RuntimeException`) already cover what an append throws. They stay.

- [ ] **Step 5: GREEN (compiles; the behaviour is proven on the device)**

```bash
cd /c/Users/nimae/Desktop/nimbustats
grep -n "catch (error: RuntimeException)" \
  app/android/app/src/main/kotlin/com/nimbustats/app/OutsideChannelHandler.kt \
  app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetActionReceiver.kt
cd app && flutter build apk --debug
```

Expected:
- Exactly one grep line, the append's catch in `WidgetActionReceiver.kt`'s `onReceive`.
- `✓ Built build\app\outputs\flutter-apk\app-debug.apk`.

- [ ] **Step 6: Broader suite**

```bash
cd /c/Users/nimae/Desktop/nimbustats/app/android && ./gradlew :app:testDebugUnitTest
```

Expected: `BUILD SUCCESSFUL`, 33 tests, 0 failures. The APK was built in Step 5.

- [ ] **Step 7: Commit**

```bash
cd /c/Users/nimae/Desktop/nimbustats
git add app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetRenderer.kt \
        app/android/app/src/main/kotlin/com/nimbustats/app/widget/ExpenseWidgetProvider.kt \
        app/android/app/src/main/kotlin/com/nimbustats/app/OutsideChannelHandler.kt \
        app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetActionReceiver.kt
git commit -m "$(cat <<'EOF'
fix(widget): an unreadable buffer is the loading state, never a crash

D26: WidgetRenderer.build read the pending taps before its try, so an
IOException there escaped. From onAppWidgetOptionsChanged, which had no
guard, a resize would crash the app's process. The channel's and the
tap receiver's render guards caught RuntimeException only, so the
channel reported a written snapshot as failed.

The reads move inside build's try (loading state, logged), the resize
callback gets onUpdate's guard, and both render guards catch Exception.
Widget glue: no host test (no Robolectric, operator decision
2026-10-14); verified on the A53 in Task 21 with a directory in place of
the buffer file.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git log -1 --format='%h %s'
```

---

### Task 18: A permission ask answered at once is never stranded (D27)

Slug `permission-queue`.

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/nimbustats/app/MainActivity.kt` (`requestNotificationPermission`)

**Interfaces:**
- No signature changes. `onRequestPermissionsResult` is unchanged. It answers every queued `Result` with `grantResults.firstOrNull() == PERMISSION_GRANTED`, so empty arrays, Android's synchronous cancel, answer `false`.

- [ ] **Step 1: Tag the rollback target**

```bash
cd /c/Users/nimae/Desktop/nimbustats && git tag pre-permission-queue
```

- [ ] **Step 2: No host test, and no device path: verified by review**

There is no host test: `MainActivity` is a `FlutterActivity` (`android.*`).

There is no device path either. `Activity.requestPermissions` answers synchronously, with empty arrays, only while **another** permission request is in flight. Nothing else in the app requests a permission. The A53 already grants `POST_NOTIFICATIONS`, so the method returns at its first `if`. The spec records D27 as review-verified.

Review checklist, for the reviewer of this commit:
1. The `Result` is in `permissionResults` before `requestPermissions` runs. A synchronous `onRequestPermissionsResult` therefore finds it and answers `false`.
2. `requestPermissions` is called only when this `Result` is the first queued. A second ask while the dialog is up only queues, as before.
3. If `requestPermissions` throws, this `Result` is removed and the exception rethrown. `OutsideChannelHandler.onMethodCall`'s `catch (error: Exception)` then answers it once with `native-failure`. It is never answered twice, and never left waiting.
4. A regression check of the normal path, with the operator's consent, is Task 21 Step 9. It repeats the Phase 6 gate's double tap: one dialog, both asks answered.

- [ ] **Step 3: RED**

n/a, review-verified.

- [ ] **Step 4: Implement**

Before:

```kotlin
        // One dialog answers every ask made while it is up: a second request would be answered at
        // once with empty arrays. Added after the request, so one that throws leaves none waiting.
        if (permissionResults.isEmpty()) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        }
        permissionResults += result
    }
```

After:

```kotlin
        // One dialog answers every ask made while it is up: a second request would be answered at
        // once with empty arrays. Queued before the request, so an answer Android gives at once
        // (a cancel while another request is in flight) still reaches it, as false (D27).
        permissionResults += result
        if (permissionResults.size > 1) return
        try {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        } catch (error: Exception) {
            // Not left waiting: the channel answers it with this error instead.
            permissionResults.remove(result)
            throw error
        }
    }
```

- [ ] **Step 5: GREEN (compiles)**

```bash
cd /c/Users/nimae/Desktop/nimbustats/app && flutter build apk --debug
```

Expected: `✓ Built build\app\outputs\flutter-apk\app-debug.apk`.

- [ ] **Step 6: Broader suite**

```bash
cd /c/Users/nimae/Desktop/nimbustats/app/android && ./gradlew :app:testDebugUnitTest
```

Expected: `BUILD SUCCESSFUL`, 33 tests.

- [ ] **Step 7: Commit**

```bash
cd /c/Users/nimae/Desktop/nimbustats
git add app/android/app/src/main/kotlin/com/nimbustats/app/MainActivity.kt
git commit -m "$(cat <<'EOF'
fix(notifications): a permission ask answered at once is never stranded

D27: the Result was queued after requestPermissions. While another
request is in flight, Android answers synchronously with empty arrays,
so onRequestPermissionsResult found an empty queue, and the Result
queued just after it waited forever.

It is queued first now, and only the first ask fires the request; the
synchronous cancel answers it false. A throw removes it and rethrows,
so the channel answers it once with the error. Verified by review: no
second permission caller exists to exercise it on a device.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git log -1 --format='%h %s'
```

---

### Task 19: A recreated activity does not reopen a notification's route (D28)

Slug `route-replay`.

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/nimbustats/app/MainActivity.kt` (new `onCreate` override, import, `takeRoute` KDoc)

**Interfaces:**
- New: `override fun onCreate(savedInstanceState: Bundle?)`. It removes `Notifier.EXTRA_ROUTE` from `intent` when `savedInstanceState != null`, before `super.onCreate`.
- Verified in the code: `FlutterActivity.onCreate` → delegate `onAttach` → `configureFlutterEngine`, where `takeRoute(intent)` reads the extra. The removal must therefore come before `super`.
- Why the extra comes back: `takeRoute`'s `removeExtra` changes only the in-process `Intent`. The system keeps the launching intent in its `ActivityRecord` and hands it to the activity it recreates after process death.

- [ ] **Step 1: Tag the rollback target**

```bash
cd /c/Users/nimae/Desktop/nimbustats && git tag pre-route-replay
```

- [ ] **Step 2: No host test; the device check run in Task 21 Steps 3 and 7**

There is no host test: `MainActivity` is `android.*`. Labels come from `helpers.sh`: `HOME_LABEL`/`ADD_LABEL` are `Home`/`Amount` in English and `خانه`/`مبلغ` in Persian. The `route` helper prints `home` or `add`. `/add` is pushed over the shell, so its screen has no nav bar.

**D28-A (adb only; run on the pre-fix APK in Task 21 Step 3, then on the fixed APK in Task 21 Step 7).**

The cold start uses the intent a notification tap sends (`Notifier.routeIntent`): `MainActivity`, `EXTRA_ROUTE`, `NEW_TASK|SINGLE_TOP` = `0x30000000`. `MainActivity` is exported, so the shell can start it with the extra. The system then stores exactly that intent in the `ActivityRecord`.

A1. No `MainActivity` task may exist, or the start below would be delivered to it as `onNewIntent` instead of creating it. Ask the operator to swipe NimbuStats out of Recents. Then:

```bash
source "$S/device/helpers.sh"; guard || exit 1
a shell dumpsys activity activities | grep -c "com.nimbustats.app/.MainActivity"
a shell am kill $PKG; pause 1; a shell pidof $PKG
```

Expected: `0`, then no pid. If a pid prints, run `pause 2` and `a shell am kill $PKG` again. Never use `force-stop`: it cancels the reminder and midnight alarms.

A2. Cold start with the route:

```bash
source "$S/device/helpers.sh"; guard || exit 1
a logcat -c
a shell am start -W -n $PKG/.MainActivity -f 0x30000000 --es com.nimbustats.app.ROUTE /add
pause 8
dump && route
```

Expected: `Status: ok` and `LaunchState: COLD`, then `add`.

A3. Back to the home route:

```bash
source "$S/device/helpers.sh"; guard || exit 1
a shell input keyevent KEYCODE_BACK; pause 2; dump && route
```

If it prints `add`, the first Back only closed the keyboard: run the block once more. Stop at the first `home`. **Never press Back on `home`**: it would finish the activity and void the check.

A4. Home, then kill the process with the activity in the background:

```bash
source "$S/device/helpers.sh"; guard || exit 1
a shell input keyevent KEYCODE_HOME; pause 2
a shell am kill $PKG; pause 1; a shell pidof $PKG
a shell dumpsys activity activities | grep -c "com.nimbustats.app/.MainActivity"
```

Expected: no pid, and a count of at least 1. The record and its saved state outlive the process.

A5. Reopen from the launcher icon:

```bash
source "$S/device/helpers.sh"; guard || exit 1
a logcat -c
a shell monkey -p $PKG -c android.intent.category.LAUNCHER 1
pause 8
dump && route; shot d28-relaunch
a logcat -d -b crash
```

Expected:
- **Fixed build: `home`.**
- Pre-fix build: `add`, the replay this task removes.
- The crash buffer is empty in both.

**D28-B (fixed build only, a real notification tap, with the operator's OK; it changes their reminder time and restores it).**

B1. `source "$S/device/helpers.sh"; a shell "run-as $PKG cat shared_prefs/nimbus_reminder.xml"`. Record `enabled` and `minuteOfDay`.

B2. Ask the operator to set the reminder, under Settings → Notifications, to two minutes from now and go Home. Then ask them to swipe NimbuStats out of Recents. Then run `a shell am kill $PKG`.

B3. Wait until 30 s after that time (`pause 30`, repeated), then:

```bash
source "$S/device/helpers.sh"
a shell dumpsys notification --noredact | grep "pkg=com.nimbustats.app" | grep -c "tag=reminder"
```

If it prints `0`, nudge it. A re-arm inside the delivery window fires now (`a2ece7a`):

```bash
source "$S/device/helpers.sh"
a shell am broadcast -n $PKG/.notifications.RearmReceiver -a com.nimbustats.check.D28; pause 10
a shell dumpsys notification --noredact | grep "pkg=com.nimbustats.app" | grep -c "tag=reminder"
```

Expected: `1`.

B4. Run `a shell am kill $PKG; a shell pidof $PKG` and expect no pid. Ask the operator to pull down the shade and tap the reminder. Then run `pause 8; dump && route` and expect `add`.

B5. Run A3, A4 and A5 exactly. Expected `home`.

B6. Ask the operator to set the reminder back to the time recorded in B1. Re-read `shared_prefs/nimbus_reminder.xml`: `minuteOfDay` must equal the B1 value.

- [ ] **Step 3: RED**

n/a, device-verified. The pre-fix APK's D28-A run in Task 21 Step 3 is the discriminating "red": it must print `add` at A5. If it prints `home`, the replay does not reproduce on this device. Then record "D28 not reproduced on the A53; fixed by review".

- [ ] **Step 4: Implement**

Imports. Before:

```kotlin
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
```

After:

```kotlin
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
```

`onCreate`, inserted above `configureFlutterEngine`. Before:

```kotlin
    /** Every Dart ask waiting on the one permission dialog. */
    private val permissionResults = mutableListOf<MethodChannel.Result>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
```

After:

```kotlin
    /** Every Dart ask waiting on the one permission dialog. */
    private val permissionResults = mutableListOf<MethodChannel.Result>()

    override fun onCreate(savedInstanceState: Bundle?) {
        // Recreated after process death, the activity gets its launching intent back, route
        // included; that route was opened the first time and must not open again (D28). Before
        // super, which reads it in configureFlutterEngine.
        if (savedInstanceState != null) intent?.removeExtra(Notifier.EXTRA_ROUTE)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
```

`takeRoute`'s KDoc. Before:

```kotlin
    /**
     * The route a notification put on [intent], read once. A launch from Recents replays the
     * notification's intent, so it carries none.
     */
```

After:

```kotlin
    /**
     * The route a notification put on [intent], read once. A launch from Recents replays the
     * notification's intent, so it carries none; a recreation drops it in [onCreate].
     */
```

- [ ] **Step 5: GREEN (compiles)**

```bash
cd /c/Users/nimae/Desktop/nimbustats/app && flutter build apk --debug
```

Expected: `✓ Built build\app\outputs\flutter-apk\app-debug.apk`.

- [ ] **Step 6: Broader suite**

```bash
cd /c/Users/nimae/Desktop/nimbustats/app/android && ./gradlew :app:testDebugUnitTest
```

Expected: `BUILD SUCCESSFUL`, 33 tests.

- [ ] **Step 7: Commit**

```bash
cd /c/Users/nimae/Desktop/nimbustats
git add app/android/app/src/main/kotlin/com/nimbustats/app/MainActivity.kt
git commit -m "$(cat <<'EOF'
fix(notifications): a recreated activity does not reopen a notification's route

D28: takeRoute's removeExtra changes only this process's Intent. After
process death the system recreates MainActivity from the intent it
stored -- the notification's, route included -- with the saved state,
and the launcher icon then reopened that route.

onCreate drops the route extra from any intent that arrives with saved
state, before super.onCreate reaches configureFlutterEngine. Glue: no
host test; verified on the A53 in Task 21 (cold start with /add, back to
Home, am kill, launcher icon: Home), against the pre-fix build replaying
/add.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git log -1 --format='%h %s'
```

---

### Task 20: The widget dialog's chips, buttons and corners (D31)

Slug `dialog-polish`.

**Files:**
- Modify: `app/android/app/src/main/res/layout/activity_expense_entry.xml`
- Create: `app/android/app/src/main/res/color/entry_button_text.xml`
- Modify: `app/android/app/src/main/res/values/styles.xml`, `app/android/app/src/main/res/values-night/styles.xml` (`EntryDialogTheme`)
- Modify: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/ExpenseEntryActivity.kt` (chip container)

**Interfaces:**
- `R.id.entry_chips` keeps its id and becomes a framework `android.widget.GridLayout` with `columnCount="2"`. It still holds at most `MAX_CHIPS = 4`, so two rows of two.
- New colour state list `@color/entry_button_text`: `nimbus_widget_accent`, or `nimbus_widget_muted` when disabled. Both are defined per night mode in `values/colors.xml` and `values-night/colors.xml`.
- Contrast of the accent on its surface: light `#2E7D64` on `#F5FBF6`, dark `#6EE7B7` on `#0F1512`, both above 4.5:1. Disabled text has no contrast requirement.

- [ ] **Step 1: Tag the rollback target**

```bash
cd /c/Users/nimae/Desktop/nimbustats && git tag pre-dialog-polish
```

- [ ] **Step 2: No host test; the device check run in Task 21 Step 8**

There is no host test: it is a `View` layout in an `Activity`.

The check writes four long names into the snapshot's `chips`. The dialog reads only the snapshot, so the operator's categories in the database are never touched. It keeps the real chip ids and only ever presses **Cancel**. The app rewrites the snapshot whenever it runs in the foreground, so the app stays killed while a patched snapshot is in place.

D31-1. Write `$S/device/d31_long_chips.py` with the Write tool, not a heredoc: Git Bash heredocs mangle backslashes, and Persian text is safer in a file.

```python
"""Gives the widget snapshot four long chip names, for the D31 device check.

usage: python -I d31_long_chips.py <snapshot in> <snapshot out>
Ids stay real; a missing chip gets a check-only id, so the dialog must only
ever be cancelled while this snapshot is in place.
"""
import json
import sys

LONG = {
    "en": [
        "Groceries and household supplies",
        "Transport, fuel and parking",
        "Restaurants, cafés and takeaway",
        "Health, pharmacy and doctor visits",
    ],
    "fa": [
        "خواربار و لوازم مصرفی خانه",
        "حمل‌ونقل، سوخت و پارکینگ",
        "رستوران، کافه و غذای بیرون‌بر",
        "سلامت، داروخانه و ویزیت پزشک",
    ],
}

source, target = sys.argv[1], sys.argv[2]
with open(source, encoding="utf-8") as f:
    snapshot = json.load(f)
names = LONG["fa" if snapshot["localeTag"].startswith("fa") else "en"]
chips = snapshot["chips"]
for i, name in enumerate(names):
    if i < len(chips):
        chips[i]["name"] = name
    else:
        chips.append({"id": f"d31-check-{i}", "name": name})
with open(target, "w", encoding="utf-8") as f:
    json.dump(snapshot, f, ensure_ascii=False)
print(snapshot["localeTag"], [c["name"] for c in chips])
```

D31-2. Record and back up:

```bash
source "$S/device/helpers.sh"; guard || exit 1
a shell cmd uimode night | tee "$S/device/night-mode-before.txt"
a exec-out run-as $PKG cat files/widget_snapshot.json > "$S/device/snapshot-orig.json"
PYTHONIOENCODING=utf-8 python -I -c "import json,sys; print(json.load(open(sys.argv[1], encoding='utf-8'))['localeTag'])" "$S/device/snapshot-orig.json"
```

D31-3, patch: Home, kill, patch, write back atomically.

```bash
source "$S/device/helpers.sh"; guard || exit 1
a shell input keyevent KEYCODE_HOME; pause 1; a shell am kill $PKG; pause 1
a exec-out run-as $PKG cat files/widget_snapshot.json > "$S/device/snapshot-now.json"
PYTHONIOENCODING=utf-8 python -I "$S/device/d31_long_chips.py" "$S/device/snapshot-now.json" "$S/device/snapshot-d31.json"
a exec-in "run-as $PKG sh -c 'cat > files/widget_snapshot.json.d31 && mv files/widget_snapshot.json.d31 files/widget_snapshot.json'" < "$S/device/snapshot-d31.json"
a exec-out run-as $PKG cat files/widget_snapshot.json | PYTHONIOENCODING=utf-8 python -I -c "import json,sys; print([c['name'] for c in json.load(sys.stdin)['chips']])"
```

Expected: the last line prints the four long names. If `exec-in` is refused, use the fallback: `a push "$(cygpath -w "$S/device/snapshot-d31.json")" /data/local/tmp/snapshot-d31.json`, then `a shell "run-as $PKG cp /data/local/tmp/snapshot-d31.json files/widget_snapshot.json"`, then `a shell rm /data/local/tmp/snapshot-d31.json`.

D31-4, one capture, run per language × theme, where `$T` is `en-light`, `en-dark`, `fa-light` or `fa-dark`:

```bash
source "$S/device/helpers.sh"; guard || exit 1
T=en-light
a shell input keyevent KEYCODE_HOME; pause 1
dump || exit 1
tapon '(text|content-desc)="\+ Expense' || tapon '(text|content-desc)="\+ هزینه'
pause 2; shot "d31-$T-empty"
a shell input text 5; pause 1
dump || exit 1
xy=$(centren 'class="android.widget.ToggleButton"' 2) && a shell input tap $xy
pause 1; shot "d31-$T-filled"
dump || exit 1; tapon 'resource-id="com.nimbustats.app:id/entry_cancel"'
pause 1
a shell "run-as $PKG ls -la files/"
```

If the launcher's dump lacks the widget's subtree, which happens sometimes, take `shot home`. Read the "+ Expense" button's centre from the image and use `a shell input tap X Y`.

Expected after each Cancel: `widget_buffer.jsonl` is unchanged, absent or 0 bytes. Cancel writes nothing.

D31-5, the sequence:
- `en-light`: if `night-mode-before.txt` says `yes`, ask the operator before running `a shell cmd uimode night no`.
- Run D31-4.
- `en-dark`: ask, run `a shell cmd uimode night yes`, then D31-4.
- Ask the operator to switch the app's language to Persian (Settings → Language) and return Home. Run `pause 5`, then D31-3 again: the app rewrote the snapshot, and the patch needs re-applying.
- `fa-dark`: run D31-4.
- `fa-light`: run `a shell cmd uimode night no`, then D31-4.

D31-6, restore:
- Ask the operator to set the app's language back to the one recorded in Task 21 Step 1.
- Set night mode back to `night-mode-before.txt` with `a shell cmd uimode night <yes|no>`.
- With the app open once, the snapshot is rewritten from the database. Check: `a exec-out run-as $PKG cat files/widget_snapshot.json | PYTHONIOENCODING=utf-8 python -I -c "import json,sys; print([c['name'] for c in json.load(sys.stdin)['chips']])"` prints the real category names.
- If not, write `snapshot-orig.json` back with D31-3's `exec-in` line, using `snapshot-orig.json` as the input.

Success, per `d31-*-filled.png` and `-empty.png`, read with the Read tool:
1. The four chips sit in two rows of two, with equal widths. Each name is on one line, and long names end in "…". In Persian the ellipsis is on the left, the line's end.
2. No chip is cut at the dialog's edge.
3. Cancel and Save text is the accent: green `#2E7D64` in light, mint `#6EE7B7` in dark.
4. Save is the muted grey (`#5A5F5C`, or `#A8B0AC` in dark) in `-empty`, and the accent in `-filled`.
5. The dialog's corners are rounded (16 dp), with the home screen visible beyond them.
6. In Persian the grid starts at the right, and the buttons sit at the left.

- [ ] **Step 3: RED**

n/a, device-verified in Task 21 Step 8.

- [ ] **Step 4: Implement**

New `app/android/app/src/main/res/color/entry_button_text.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- The dialog's Cancel and Save (D31): the widget's accent, muted while disabled. -->
<selector xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:color="@color/nimbus_widget_muted" android:state_enabled="false" />
    <item android:color="@color/nimbus_widget_accent" />
</selector>
```

`activity_expense_entry.xml`, the chip row. Before:

```xml
    <HorizontalScrollView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        android:scrollbars="none">

        <LinearLayout
            android:id="@+id/entry_chips"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:orientation="horizontal" />
    </HorizontalScrollView>
```

After:

```xml
    <!-- Up to four category chips, two to a row (D31). -->
    <GridLayout
        android:id="@+id/entry_chips"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        android:columnCount="2" />
```

The buttons. Before:

```xml
        <Button
            android:id="@+id/entry_cancel"
            style="?android:attr/buttonBarButtonStyle"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:minHeight="48dp" />

        <Button
            android:id="@+id/entry_save"
            style="?android:attr/buttonBarButtonStyle"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:minHeight="48dp" />
```

After:

```xml
        <Button
            android:id="@+id/entry_cancel"
            style="?android:attr/buttonBarButtonStyle"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:minHeight="48dp"
            android:textColor="@color/entry_button_text" />

        <Button
            android:id="@+id/entry_save"
            style="?android:attr/buttonBarButtonStyle"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:minHeight="48dp"
            android:textColor="@color/entry_button_text" />
```

`values/styles.xml`. The same edit applies to `values-night/styles.xml`, whose `EntryDialogTheme` has the identical comment and item lines and differs only in its parent. Before:

```xml
    <!-- Phase 6: the widget's add-expense dialog. Translucent, so the home
         screen stays behind it; a tap outside cancels. -->
```

```xml
        <item name="android:windowBackground">@color/nimbus_widget_bg</item>
```

After:

```xml
    <!-- Phase 6: the widget's add-expense dialog. Translucent, so the home
         screen stays behind it; a tap outside cancels. Rounded like the
         widget itself (D31). -->
```

```xml
        <item name="android:windowBackground">@drawable/widget_background</item>
```

`ExpenseEntryActivity.kt`, the imports. Before:

```kotlin
import android.text.TextWatcher
import android.text.method.DigitsKeyListener
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
```

After:

```kotlin
import android.text.TextUtils
import android.text.TextWatcher
import android.text.method.DigitsKeyListener
import android.view.View
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.GridLayout
import android.widget.TextView
```

The chips. Before:

```kotlin
        val row = findViewById<LinearLayout>(R.id.entry_chips)
        for (chip in snapshot.chips.take(MAX_CHIPS)) {
            val button = ToggleButton(this).apply {
                textOn = chip.name
                textOff = chip.name
                text = chip.name
                minHeight = dp(48)
                setBackgroundResource(R.drawable.entry_chip)
```

```kotlin
            chips += button
            row.addView(
                button,
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                    .apply { marginEnd = dp(8) },
            )
        }
```

After:

```kotlin
        // Two equal columns, two rows at most (MAX_CHIPS): a long name ellipsizes in its own cell
        // instead of pushing the fourth chip past the dialog's edge (D31).
        val grid = findViewById<GridLayout>(R.id.entry_chips)
        snapshot.chips.take(MAX_CHIPS).forEachIndexed { index, chip ->
            val button = ToggleButton(this).apply {
                textOn = chip.name
                textOff = chip.name
                text = chip.name
                minHeight = dp(48)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                setBackgroundResource(R.drawable.entry_chip)
```

```kotlin
            chips += button
            grid.addView(
                button,
                GridLayout.LayoutParams(
                    GridLayout.spec(GridLayout.UNDEFINED),
                    GridLayout.spec(GridLayout.UNDEFINED, 1f),
                ).apply {
                    // Width 0 and weight 1: the columns share the width equally.
                    width = 0
                    if (index % 2 == 0) marginEnd = dp(4) else marginStart = dp(4)
                    if (index >= 2) topMargin = dp(8)
                },
            )
        }
```

The lines between the two snippets are unchanged: `setTextColor`, the single-select comment, `setOnCheckedChangeListener` and the closing `}` of `apply`. `LinearLayout` has no other use in the file, so its import goes.

- [ ] **Step 5: GREEN (compiles)**

```bash
cd /c/Users/nimae/Desktop/nimbustats
grep -n "LinearLayout" app/android/app/src/main/kotlin/com/nimbustats/app/widget/ExpenseEntryActivity.kt
cd app && flutter build apk --debug
```

Expected: the grep prints nothing, then `✓ Built build\app\outputs\flutter-apk\app-debug.apk`.

- [ ] **Step 6: Broader suite**

```bash
cd /c/Users/nimae/Desktop/nimbustats/app/android && ./gradlew :app:testDebugUnitTest
```

Expected: `BUILD SUCCESSFUL`, 33 tests.

- [ ] **Step 7: Commit**

```bash
cd /c/Users/nimae/Desktop/nimbustats
git add app/android/app/src/main/res/layout/activity_expense_entry.xml \
        app/android/app/src/main/res/color/entry_button_text.xml \
        app/android/app/src/main/res/values/styles.xml \
        app/android/app/src/main/res/values-night/styles.xml \
        app/android/app/src/main/kotlin/com/nimbustats/app/widget/ExpenseEntryActivity.kt
git commit -m "$(cat <<'EOF'
fix(widget): dialog chips in a 2x2 grid, themed buttons, rounded window

D31: the fourth category chip was cut at the dialog's edge, Cancel and
Save used the platform's button colours, and the flat window background
lost the widget's rounded corners.

The chip row is a two-column GridLayout (same id, weighted columns)
whose chips stay on one line and ellipsize, so four long names fit
(operator decision: a 2x2 grid). Both buttons take entry_button_text,
the widget accent, muted while disabled. Both EntryDialogThemes use
widget_background as the window. Verified on the A53 in Task 21, in
English and Persian, light and dark, with four long names.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git log -1 --format='%h %s'
```

---

### Task 21: Device session on the Galaxy A53 (D17, D26, D28, D31; D27 optional)

Slug: none. This task commits nothing. It writes `$S/device/results.md`, which Task 25 reads.

**Stop and ask the operator before starting.** The A53 (`RZCT209E3QX`) is their daily phone: confirm it is free and unlocked. Stop at once, without another dump, if a non-project app comes to the front. Never change a phone setting without asking first: the night mode, the app language, the reminder time, the notification permission. Restore each one at the end.

- [ ] **Step 1: Helpers and the starting state**

Write `$S/device/helpers.sh` with the Write tool, not a heredoc:

```bash
# Device-check helpers for the deferred sweep (Tasks 17-23). Set S (this session's scratchpad,
# Git Bash form) in the same block, then: source "$S/device/helpers.sh"
ADB=/c/dev/android-sdk/platform-tools/adb.exe
SERIAL=RZCT209E3QX
PKG=com.nimbustats.app
mkdir -p "$S/device"

# adb on the A53. MSYS_NO_PATHCONV only here: Python and Dart need Git Bash's path conversion.
a() { MSYS_NO_PATHCONV=1 "$ADB" -s "$SERIAL" "$@"; }

# Waits on the device, not with a local sleep.
pause() { a shell sleep "$1"; }

# Fails unless the phone is awake and unlocked; prints the focused window to check it is ours or the launcher.
guard() {
  local w
  w=$(a shell dumpsys window) || { echo "guard: adb failed; check 'adb devices'" >&2; return 1; }
  if printf '%s' "$w" | grep -qE "mDreamingLockscreen=true|isKeyguardShowing=true|mShowingLockscreen=true"; then
    echo "guard: the phone is locked; ask the operator to unlock it" >&2; return 1
  fi
  printf '%s\n' "$w" | grep -m1 -E "mCurrentFocus="
}

# Dumps the screen to $S/ui.xml. A failed dump is an error, never a stale file.
dump() {
  rm -f "$S/ui.xml"
  a shell uiautomator dump /sdcard/nimbus-ui.xml | grep -q "dumped to" || { echo "dump: failed (UI busy?); retry" >&2; return 1; }
  a exec-out cat /sdcard/nimbus-ui.xml > "$S/ui.xml"
}

# "x y": the centre of the n-th node (1-based) whose attributes match the ERE $1.
centren() {
  local hits
  hits=$(grep -oE "<node [^>]*$1[^>]*>" "$S/ui.xml" | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' | sed -n "${2}p")
  [ -n "$hits" ] || { echo "centren: no node #$2 matching $1" >&2; return 1; }
  printf '%s\n' "$hits" | tr -c '0-9\n' ' ' | awk '{print int(($1+$3)/2), int(($2+$4)/2)}'
}

# "x y" of the one node matching $1; fails loudly on none or several.
centre() {
  local n
  n=$(grep -oE "<node [^>]*$1[^>]*>" "$S/ui.xml" | grep -c bounds)
  [ "$n" -eq 1 ] || { echo "centre: want one node matching $1, found $n" >&2; return 1; }
  centren "$1" 1
}

# Taps the one node matching $1.
tapon() { local xy; xy=$(centre "$1") || return 1; a shell input tap $xy; }

# Screenshot to $S/device/<name>.png
shot() { a exec-out screencap -p > "$S/device/$1.png"; }

# The app's language, recorded in Step 1.
if [ "$(cat "$S/device/app-lang" 2>/dev/null)" = fa ]; then HOME_LABEL='خانه'; ADD_LABEL='مبلغ'; else HOME_LABEL=Home; ADD_LABEL=Amount; fi

# "home" when the shell's Home tab shows, "add" on the add screen (pushed over the shell, no nav bar).
route() {
  local home add
  home=$(grep -oE "(text|content-desc)=\"$HOME_LABEL" "$S/ui.xml" | wc -l)
  add=$(grep -o "$ADD_LABEL" "$S/ui.xml" | wc -l)
  if [ "$home" -gt 0 ] && [ "$add" -eq 0 ]; then echo home
  elif [ "$home" -eq 0 ] && [ "$add" -gt 0 ]; then echo add
  else echo "route: unclear (home=$home add=$add); read $S/ui.xml" >&2; return 1; fi
}
```

Ask: "Is the A53 free and unlocked for about 45 minutes of checks? I'll install a debug build over the current one, which keeps your data."

On a yes, record the starting state:

```bash
source "$S/device/helpers.sh"
"$ADB" devices
guard || exit 1
a shell dumpsys package $PKG | grep -E "versionName|pkgFlags" | head -3
a exec-out run-as $PKG cat files/widget_snapshot.json | python -I -c "import json,sys; print(json.load(sys.stdin)['localeTag'][:2])" | tee "$S/device/app-lang"
a shell cmd uimode night | tee "$S/device/night-mode-before.txt"
a shell "run-as $PKG cat shared_prefs/nimbus_reminder.xml" | tee "$S/device/reminder-before.txt"
a shell dumpsys display | grep -m2 -E "mActiveRenderFrameRate|refresh"
a shell dumpsys appwidget | grep -c "com.nimbustats.app.widget.ExpenseWidgetProvider"
```

Expected:
- `RZCT209E3QX device`.
- A focused window that is not someone else's app.
- `app-lang` reads `en` or `fa`.
- The reminder's `minuteOfDay`; it was 1260, that is 21:00, at the Phase 6 restore.
- A widget count of at least 1. If it is 0, ask the operator to place the widget: long-press home → Widgets → NimbuStats.

Write each result into `$S/device/results.md` as you go, as in the Phase 6 gate notes.

- [ ] **Step 2: Back up the database, and build both debug APKs**

```bash
source "$S/device/helpers.sh"
mkdir -p "$S/device/db-before"
for f in nimbustats.sqlite nimbustats.sqlite-wal nimbustats.sqlite-shm; do
  a exec-out run-as $PKG cat app_flutter/$f > "$S/device/db-before/$f" 2>/dev/null || true
done
python -I -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute('select count(*) from transactions where deleted_at is null').fetchone())" "$S/device/db-before/nimbustats.sqlite"
```

This is a precaution, run on scratch copies only. Record the count.

```bash
cd /c/Users/nimae/Desktop/nimbustats
git status --short                           # only the three stackdump files
git checkout --detach pre-route-replay       # Tasks 16-18 done, D28 not yet
(cd app && flutter build apk --debug) && cp app/build/app/outputs/flutter-apk/app-debug.apk "$S/device/app-debug-pre-d28.apk"
git checkout fix/deferred-0-6
git rev-parse --abbrev-ref HEAD              # must print fix/deferred-0-6
(cd app && flutter build apk --debug) && cp app/build/app/outputs/flutter-apk/app-debug.apk "$S/device/app-debug-tip.apk"
```

Expected: two `✓ Built` lines, and `fix/deferred-0-6`. The tip includes Tasks 1-20, among them D17's Dart change.

- [ ] **Step 3: D28 baseline on the pre-fix APK (recommended)**

```bash
source "$S/device/helpers.sh"; guard || exit 1
a install -r "$(cygpath -w "$S/device/app-debug-pre-d28.apk")"
```

Expected: `Success`. Then run **Task 19 Step 2, D28-A, A1 to A5**.

Expected at A5: `add`, the replay. Record the result. If it prints `home`, note "the pre-fix build did not replay on the A53; D28-A is not discriminating here" and carry that into Task 25's D28 entry.

- [ ] **Step 4: Install the tip**

```bash
source "$S/device/helpers.sh"; guard || exit 1
a install -r "$(cygpath -w "$S/device/app-debug-tip.apk")"
a shell monkey -p $PKG -c android.intent.category.LAUNCHER 1; pause 8
dump && route
```

Expected: `Success`, then `home`. The data is intact: same debug signing key, per `docs/DEVELOPMENT.md`.

- [ ] **Step 5: D17, the add screen's haptics**

This saves one test expense of 1, which the operator deletes in Step 10.

```bash
source "$S/device/helpers.sh"; guard || exit 1
dump && tapon 'content-desc="Add expense"'      # the shell's FAB (named since D13)
pause 2; dump && tapon 'class="android.widget.EditText"'
a shell input text 1; pause 1
dump || exit 1
```

Read `$S/ui.xml` and pick one category chip's label. It is a node below the amount field whose `text` or `content-desc` is a category name. Then:

```bash
source "$S/device/helpers.sh"; guard || exit 1
a logcat -c
tapon '(text|content-desc)="<that chip label>'
pause 1
dump && tapon '(text|content-desc)="Save'
pause 3
a logcat -d | grep -c "vibration absent"
a shell dumpsys vibrator_manager | grep -i -B2 -A6 "com.nimbustats.app" | tail -40 > "$S/device/d17-vibrator.txt"; cat "$S/device/d17-vibrator.txt"
```

Here `<that chip label>` is the label read from the dump just before.

Expected (D17 holds):
- The count is `0`.
- `d17-vibrator.txt` lists two recent vibrations from `com.nimbustats.app`, usage `TOUCH`, finished, timestamped within the last minute: the chip, then Save.

The operator's touch strength is at its lowest (D18, closed), so whether it is felt is not the check.

- [ ] **Step 6: D26**

Run **Task 17 Step 2, D26-1 to D26-6**. Capture `d26-rearm.log`, `d26-resize.log`, `d26-app.log`, `d26-loading.png` and `d26-restored.png`. Success is each block's "Expected". Record them.

- [ ] **Step 7: D28 on the fixed build**

Run **Task 19 Step 2, D28-A, A1 to A5**. Expected at A5: `home`.

Then, if the operator agrees to change the reminder time for a few minutes, run **D28-B, B1 to B6**. Expected at B5: `home`, and B6 restores the reminder.

Capture `d28-relaunch.png` and record the results.

- [ ] **Step 8: D31**

Run **Task 20 Step 2, D31-1 to D31-6**, asking before each night-mode and language change. Capture `d31-{en,fa}-{light,dark}-{empty,filled}.png`, eight screenshots. Read each with the Read tool against the six success points, and record them.

- [ ] **Step 9 (optional; only if the operator agrees): a regression check of the normal permission path after D27**

It revokes the app's notification permission and has the operator grant it again.

```bash
source "$S/device/helpers.sh"; guard || exit 1
a shell pm revoke $PKG android.permission.POST_NOTIFICATIONS
a shell dumpsys package $PKG | grep "POST_NOTIFICATIONS"
```

Expected: `granted=false`.

Ask the operator to open the app, go to Settings → Notifications, switch the reminder off, then double-tap the switch to turn it on. A single system dialog appears: tap Allow.

```bash
source "$S/device/helpers.sh"
a shell dumpsys package $PKG | grep "POST_NOTIFICATIONS"
a logcat -d -s NimbuStats:E
```

Expected:
- One dialog only.
- `granted=true`.
- No `NimbuStats` errors.
- The settings screen shows the reminder on, with no "blocked" row.

If the operator tapped Deny, restore with `a shell pm grant $PKG android.permission.POST_NOTIFICATIONS`. Ask them to check that the reminder time is the one recorded in Step 1.

- [ ] **Step 10: Restore and record**

Ask the operator to:
- delete the D17 test expense, amount 1, in the app (open it from the list → Delete);
- confirm the app language matches `app-lang`;
- confirm the reminder matches `reminder-before.txt`.

Then:

```bash
source "$S/device/helpers.sh"
a shell cmd uimode night
a shell "run-as $PKG cat shared_prefs/nimbus_reminder.xml"
a shell "run-as $PKG ls -la files/"
```

Expected:
- Night mode as recorded.
- The reminder prefs as recorded.
- No `widget_buffer.jsonl.d26` and no `widget_snapshot.json.d31`.

The debug APK stays installed for now. Task 22 installs a profile build.

Finish `$S/device/results.md`: one line per check with PASS or FAIL, the evidence file, and the time.

**A FAIL here is a bug in Tasks 16-20.** Fix it test-first in a focused commit, which needs a device re-check. Do not move on to Task 22.

---

### Task 22: The headless engine's library load waits off the main thread, if it measurably helps (D30)

Slug `async-engine-boot`. The steps below measure first and keep the change only if it beats a threshold.

**Files:**
- Modify: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/DrainJobService.kt` (`runHeadless`, new private `boot`)

**Interfaces, checked with `javap` against the cached embedding `io.flutter:flutter_embedding_profile:1.0.0-5d531788691ec3404cac0cee66ead4007b177363`:**
- `FlutterLoader.startInitialization(Context)`. It is idempotent and must be called on the main thread.
- `FlutterLoader.ensureInitializationCompleteAsync(Context, String[]?, Handler, Runnable)`:
  - It must run on the main thread, after `startInitialization`, or it throws.
  - When the loader is already initialised, it just posts the callback.
  - Otherwise, an executor waits for the init task ("FlutterLoader initTask": loading `libflutter.so` and the assets). It then runs `ensureInitializationComplete` **on the main thread** (VM creation) and posts the callback.
- So only the wait for the library load leaves the main thread. The `FlutterEngine` constructor still runs on the main thread, in the callback: it attaches the shell and registers the plugins. The spec requires exactly this split.
- The trace sections the loader writes are `FlutterLoader#startInitialization`, `FlutterLoader#ensureInitializationComplete` (both on the main thread) and `FlutterLoader initTask` (background thread).
- What stays the same: the 60 s `timeout` is posted in `onStartJob` before either path, so it still bounds the async wait. `finish` and `onStopJob` set `params = null`. The callback boots only while `params` is still the job that asked (`===`), so a job that ended, or was replaced by a new `onStartJob` on the same service, never gets an engine.

- [ ] **Step 1: Tag the rollback target**

```bash
cd /c/Users/nimae/Desktop/nimbustats && git tag pre-async-engine-boot
```

- [ ] **Step 2: The baseline measurement, on a profile build of the current tip**

There is no host test: `JobService` and `FlutterEngine` are `android.*`. The measurement is the test.

**Ask the operator first.** Each run saves one test expense of 7 through the widget's dialog, ten in all, which they delete afterwards. The runs also need the Choreographer's skipped-frame warning lowered from 30 frames to 1. By default only skips of 30 or more frames are logged, and the result may fall below that. Lowering it touches only logging, and the setting is gone at the next reboot.

The metric is the sum of `Choreographer: Skipped N frames` lines from the app's process after the Save tap. The gate measured 78 frames, about 650 ms at 120 Hz.

```bash
source "$S/device/helpers.sh"; guard || exit 1
mkdir -p "$S/d30"
cd /c/Users/nimae/Desktop/nimbustats/app && flutter build apk --profile
cp build/app/outputs/flutter-apk/app-profile.apk "$S/d30/app-profile-before.apk"
a install -r "$(cygpath -w "$S/d30/app-profile-before.apk")"
a shell setprop debug.choreographer.skipwarning 1
a shell getprop debug.choreographer.skipwarning
a shell dumpsys display | grep -m1 mActiveRenderFrameRate
a shell input keyevent KEYCODE_HOME; pause 1
dump && centre '(text|content-desc)="\+ Expense' | tee "$S/d30/plus.txt"
```

Expected:
- `Success`, then `1`.
- `mActiveRenderFrameRate=120`. If it reads 60, ask the operator for adaptive motion smoothness: the gate's 78 frames were at 120 Hz.
- An `x y` for "+ Expense". If the launcher dump lacks it, take `shot home`, read the button's centre from the image, and write it with `echo "X Y" > "$S/d30/plus.txt"`.

One run. Repeat it with `i=1` to `5`, one block per run:

```bash
source "$S/device/helpers.sh"; guard || exit 1
P=before; i=1
a shell input keyevent KEYCODE_HOME; pause 1
a shell am kill $PKG; pause 1
[ -z "$(a shell pidof $PKG | tr -d '\r')" ] || { echo "the app is still running; retry this run" >&2; exit 1; }
a logcat -c
a shell input tap $(cat "$S/d30/plus.txt"); pause 3
a shell input text 7; pause 1
dump || exit 1
xy=$(centre 'resource-id="com.nimbustats.app:id/entry_save"') || exit 1
a shell log -t NimbusD30 "$P-$i save"
a shell input tap $xy
pause 15
a logcat -d -v threadtime > "$S/d30/$P-$i.log"
a logcat -d -b crash
```

Expected: an empty crash buffer.

The app is killed before each run, so the dialog starts a fresh process, and the drain has no app engine and boots the headless one.

Summarise the batch:

```bash
P=before
for f in "$S"/d30/$P-[0-9].log; do
  pid=$(grep -oE 'Start proc [0-9]+:com\.nimbustats\.app' "$f" | tail -1 | grep -oE '[0-9]+')
  [ -n "$pid" ] || { echo "$f: no 'Start proc' line; the process was not cold" >&2; continue; }
  n=$(awk -v pid="$pid" '/NimbusD30/ {seen = 1; next} seen && $3 == pid && /Choreographer/ && /Skipped/ {for (k = 1; k <= NF; k++) if ($k == "Skipped") s += $(k + 1)} END {print s + 0}' "$f")
  echo "$(basename "$f") pid=$pid skipped_after_save=$n"
done | tee "$S/d30/$P-summary.txt"
```

Then check that every save drained, from scratch copies of the database:

```bash
source "$S/device/helpers.sh"
for f in nimbustats.sqlite nimbustats.sqlite-wal nimbustats.sqlite-shm; do a exec-out run-as $PKG cat app_flutter/$f > "$S/d30/$f" 2>/dev/null; done
python -I -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); [print(r) for r in c.execute(\"select amount, source, created_at - occurred_at_utc as drain_ms from transactions where source = 'widget' and deleted_at is null order by created_at desc limit 5\")]" "$S/d30/nimbustats.sqlite"
```

Expected: five rows, amount 7, source `widget`. Record their `drain_ms`; the gate measured 541-871.

Optional trace of the loader's sections for one run, if `atrace` works on this user build. Write `$S/d30/sections.py` with the Write tool:

```python
"""Durations of the FlutterLoader trace sections in an atrace text dump (D30).

usage: python -I sections.py <trace.txt>
"""
import re
import sys

LINE = re.compile(r"-(\d+)\s+\(\s*(\d+)\)\s.*?\s([\d.]+): tracing_mark_write: ([BE])\|\d+\|?(.*)$")
stacks = {}
with open(sys.argv[1], encoding="utf-8", errors="replace") as trace:
    for raw in trace:
        match = LINE.search(raw)
        if not match:
            continue
        tid, pid, ts, phase, name = match.groups()
        stack = stacks.setdefault(tid, [])
        if phase == "B":
            stack.append((name.strip(), float(ts)))
        elif stack:
            begun, start = stack.pop()
            if "FlutterLoader" in begun:
                where = "main" if tid == pid else f"thread {tid}"
                print(f"{begun:48} {where:14} {(float(ts) - start) * 1000:8.1f} ms")
```

To capture: before a run's `a logcat -c`, start the trace with `a shell atrace --async_start -b 16384 -a com.nimbustats.app am dalvik view gfx sched`. After its `pause 15`, stop it with `a exec-out atrace --async_stop > "$S/d30/$P-trace.txt"`, then run `python -I "$S/d30/sections.py" "$S/d30/$P-trace.txt"`.

If `atrace` reports a permission error, skip the trace: the skipped frames are the decision metric.

- [ ] **Step 3: RED (the baseline)**

The baseline is recorded:

```bash
B=$(awk -F'skipped_after_save=' '{print $2}' "$S/d30/before-summary.txt" | sort -n | sed -n 3p)
echo "BEFORE_MEDIAN=$B" | tee "$S/d30/result.env"
```

If the median is 5 or fewer, the gate's 78 frames do not reproduce. There is nothing to improve: skip to Step 7's "discard" branch with this number.

- [ ] **Step 4: Implement**

`DrainJobService.kt`. Before:

```kotlin
    private fun runHeadless() {
        // A late notImplemented/error reply after the job ended must not boot an engine nobody holds.
        if (params == null) return
        // The constructor initialises the FlutterLoader and registers the plugins (path_provider).
        val engine = FlutterEngine(applicationContext)
```

After:

```kotlin
    private fun runHeadless() {
        // A late notImplemented/error reply after the job ended must not boot an engine nobody holds.
        val job = params ?: return
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        // D30: the wait for libflutter.so and the assets runs off the main thread. Creating the VM
        // and the shell must stay on it, so the engine is built in the callback, on main.
        loader.ensureInitializationCompleteAsync(applicationContext, null, main) {
            // The job may have ended meanwhile (the 60 s timeout, onStopJob) or been replaced.
            if (params === job) boot()
        }
    }

    private fun boot() {
        // The loader is ready; the constructor registers the plugins (path_provider).
        val engine = FlutterEngine(applicationContext)
```

The rest of the old `runHeadless` body is now `boot`'s, unchanged: `this.engine = engine`, the `MethodChannel` handler, and `executeDartEntrypoint` with `FlutterInjector.instance().flutterLoader().findAppBundlePath()`.

- [ ] **Step 5: GREEN: compile, re-measure, decide**

```bash
cd /c/Users/nimae/Desktop/nimbustats/app && flutter build apk --debug
cd /c/Users/nimae/Desktop/nimbustats/app/android && ./gradlew :app:testDebugUnitTest
cd /c/Users/nimae/Desktop/nimbustats/app && flutter build apk --profile
cp build/app/outputs/flutter-apk/app-profile.apk "$S/d30/app-profile-after.apk"
```

Expected: `✓ Built` twice, and `BUILD SUCCESSFUL` with 33 tests.

Then:
1. `a install -r "$(cygpath -w "$S/d30/app-profile-after.apk")"`, sourcing the helpers first.
2. Check `a shell getprop debug.choreographer.skipwarning` still reads `1`.
3. Run Step 2's run block with `P=after; i=1` to `5`.
4. Run the summary and the database check with `P=after`.
5. Grep all five `after` logs for errors: `grep -hE " E (NimbuStats|flutter|AndroidRuntime)" "$S"/d30/after-[0-9].log`.

The decision. **Keep only if both hold:**
- the median skipped frames after Save fall by at least 30 %, that is after ≤ 0.7 × before;
- all five `after` rows drained, with no new error lines and an empty crash buffer.

```bash
B=$(awk -F'skipped_after_save=' '{print $2}' "$S/d30/before-summary.txt" | sort -n | sed -n 3p)
A=$(awk -F'skipped_after_save=' '{print $2}' "$S/d30/after-summary.txt" | sort -n | sed -n 3p)
K=$(awk -v b="$B" -v a="$A" 'BEGIN {print (b > 5 && a <= 0.7 * b) ? "yes" : "no"}')
echo "BEFORE_MEDIAN=$B AFTER_MEDIAN=$A KEEP=$K" | tee "$S/d30/result.env"
```

Show the operator both summaries and the decision before Step 7.

- [ ] **Step 6: Broader suite**

Done in Step 5: the Kotlin suite and both APK builds.

Restore the phone:
- `a shell setprop debug.choreographer.skipwarning 30`, the default. A reboot clears it anyway.
- Ask the operator to delete the ten test expenses of 7, source widget, in the app.
- Leave the profile build installed. If the change is discarded, reinstall `app-profile-before.apk`.

- [ ] **Step 7: Commit, or discard**

If `KEEP=yes`:

```bash
cd /c/Users/nimae/Desktop/nimbustats
source "$S/d30/result.env"
git add app/android/app/src/main/kotlin/com/nimbustats/app/widget/DrainJobService.kt
git commit -m "$(cat <<EOF
fix(widget): the drain engine's library load waits off the main thread

D30: a widget save with the app killed boots the headless FlutterEngine
on the app process's main thread, and the gate counted 78 skipped frames
(about 650 ms at 120 Hz) after the dialog's Save.

The job now starts the loader and waits for libflutter.so and the assets
with ensureInitializationCompleteAsync. VM and shell creation stay on the
main thread, as Flutter requires, in the callback, which boots the engine
only if the same job still holds it (timeout and onStopJob unchanged).
Measured on the A53, five saves each, app killed: median skipped frames
after Save ${BEFORE_MEDIAN} before, ${AFTER_MEDIAN} after; every save drained.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git log -1 --format='%h %s'
```

If `KEEP=no`: ask the operator to confirm the discard, then:

```bash
cd /c/Users/nimae/Desktop/nimbustats
git restore app/android/app/src/main/kotlin/com/nimbustats/app/widget/DrainJobService.kt
git status --short             # only the stackdumps
git rev-parse HEAD; git rev-parse pre-async-engine-boot   # equal: nothing was committed
```

Then reinstall `app-profile-before.apk`. Task 25 records D30 as closed with its measurement, using `result.env`.

---

### Task 23: Month steps at 120 Hz (D16)

Slugs:
- `frame-budget`: the tool;
- `keep-shown-answer`: fix A, if chosen;
- `static-pies`: fix C, if chosen.

This is an investigation: it measures, profiles, and fixes what the profile shows. **Done when** p99 build ≤ 8.33 ms in every measured pass, three on the dashboard and three on Breakdown. If that is not met, the numbers are recorded and the operator decides.

**Files:**
- (a) `app/tool/src/frame_stats.dart`, `app/tool/frame_timings.dart`, `app/test/tool/frame_stats_test.dart` and `docs/DEVELOPMENT.md`.
- (d) Only those the timeline points at:
  - `app/lib/features/analytics/presentation/analytics_screen.dart` (`_BreakdownTab`);
  - `app/lib/features/analytics/presentation/widgets/saved_view_card.dart` (`_Readable`);
  - `app/lib/features/analytics/presentation/widgets/breakdown_body.dart` (`PieChart`);
  - `app/lib/features/analytics/presentation/widgets/card_previews.dart` (`_BreakdownPreview`'s `PieChart`);
  - their tests: `app/test/features/analytics/breakdown_screen_test.dart`, `dashboard_tab_test.dart` and `card_previews_test.dart`.

**Interfaces:**
- `FrameStats.of(List<FrameSample> samples, {int budgetMicros = sixtyFpsBudgetMicros})`. The static `budgetMicros` is renamed `sixtyFpsBudgetMicros`, with the same value, 16667. A new instance field `budgetMicros` holds the budget a run was judged against.
- `static int FrameStats.budgetMicrosFromMs(String text)`: milliseconds as typed, to whole µs. It throws `FormatException` outside (0, 1000] ms.
- `frame_timings.dart` gains `--budget-ms <ms>`. Without it the tool behaves exactly as now: 16.667 ms, reported as "(60 fps)".

#### (a) `--budget-ms`

- [ ] **Step 1: Tag the rollback target**

```bash
cd /c/Users/nimae/Desktop/nimbustats && git tag pre-frame-budget
```

- [ ] **Step 2: Write the failing tests**

In `app/test/tool/frame_stats_test.dart`. Before:

```dart
  test('a frame of exactly one sixtieth of a second is on budget', () {
    expect(FrameStats.budgetMicros, 16667);
    final stats = FrameStats.of([frame(16667, 16667), frame(16668, 1000)]);
    expect(stats.build.overBudget, 1);
    expect(stats.raster.overBudget, 0);
  });
```

After:

```dart
  test('a frame of exactly one sixtieth of a second is on budget', () {
    expect(FrameStats.sixtyFpsBudgetMicros, 16667);
    final stats = FrameStats.of([frame(16667, 16667), frame(16668, 1000)]);
    expect(stats.budgetMicros, 16667);
    expect(stats.build.overBudget, 1);
    expect(stats.raster.overBudget, 0);
  });

  test('a run can be judged against a 120 Hz budget', () {
    // D16: at 120 Hz a frame has 8.33 ms, so a 12 ms build drops a frame
    // there while it is on budget at 60 fps.
    final samples = [frame(12000, 4000), frame(8330, 8331)];
    final at60 = FrameStats.of(samples);
    final at120 = FrameStats.of(samples, budgetMicros: 8330);

    expect(at60.budgetMicros, 16667);
    expect(at60.overBudgetEither, 0);
    expect(at120.budgetMicros, 8330);
    expect(at120.build.overBudget, 1);
    expect(at120.raster.overBudget, 1);
    expect(at120.overBudgetEither, 2);
    expect(at120.toJson()['budgetMicros'], 8330);
  });

  test('--budget-ms reads milliseconds as typed', () {
    expect(FrameStats.budgetMicrosFromMs('8.33'), 8330);
    expect(FrameStats.budgetMicrosFromMs('16.67'), 16670);
    for (final bad in ['', 'fast', '0', '-8', 'NaN', 'Infinity', '0.0001', '1001']) {
      expect(() => FrameStats.budgetMicrosFromMs(bad), throwsFormatException,
          reason: bad);
    }
  });
```

- [ ] **Step 3: Confirm RED**

```bash
cd /c/Users/nimae/Desktop/nimbustats/app && flutter test --no-pub test/tool/frame_stats_test.dart
```

Expected: the file fails to compile, with errors on `sixtyFpsBudgetMicros`, the named parameter `budgetMicros`, `budgetMicrosFromMs` and the getter `budgetMicros`. The run ends `Some tests failed.`

- [ ] **Step 4: Implement**

`app/tool/src/frame_stats.dart`. Before:

```dart
/// A run's frames against the 60 fps budget.
final class FrameStats {
  FrameStats._(List<FrameSample> samples)
      : count = samples.length,
```

After:

```dart
/// A run's frames against a frame budget: 60 fps unless the caller sets one.
final class FrameStats {
  FrameStats._(List<FrameSample> samples, this.budgetMicros)
      : count = samples.length,
```

The initializer list's `budgetMicros` references now resolve to the parameter, so its body is unchanged.

Before:

```dart
  factory FrameStats.of(List<FrameSample> samples) {
    if (samples.isEmpty) {
      throw ArgumentError.value(samples, 'samples',
          'no frames were recorded -- screen off, wrong screen, or no stream');
    }
    return FrameStats._(samples);
  }

  /// One sixtieth of a second, rounded up to whole microseconds, so a frame of
  /// exactly 16.667 ms is on budget.
  static const budgetMicros = 16667;
```

After:

```dart
  factory FrameStats.of(List<FrameSample> samples,
      {int budgetMicros = sixtyFpsBudgetMicros}) {
    if (samples.isEmpty) {
      throw ArgumentError.value(samples, 'samples',
          'no frames were recorded -- screen off, wrong screen, or no stream');
    }
    if (budgetMicros < 1) {
      throw ArgumentError.value(
          budgetMicros, 'budgetMicros', 'must be at least one microsecond');
    }
    return FrameStats._(samples, budgetMicros);
  }

  /// One sixtieth of a second, rounded up to whole microseconds, so a frame of
  /// exactly 16.667 ms is on budget. The budget when none is given.
  static const sixtyFpsBudgetMicros = 16667;

  /// `--budget-ms`, as typed, in whole microseconds: `8.33` is 8,330 µs, the
  /// 120 Hz bar D16 is judged on.
  static int budgetMicrosFromMs(String text) {
    final ms = double.tryParse(text);
    // Up to a second: anything longer is a typo, not a frame budget.
    final micros =
        ms != null && ms > 0 && ms <= 1000 ? (ms * 1000).round() : 0;
    if (micros < 1) {
      throw FormatException(
          '--budget-ms must be between 0.001 and 1000 milliseconds', text);
    }
    return micros;
  }

  /// What every phase of this run was judged against.
  final int budgetMicros;
```

`toJson`'s `'budgetMicros': budgetMicros` now reads the field, and the text is unchanged.

`app/tool/frame_timings.dart`, the doc comment. Before:

```dart
/// 2. From `app/`:
///    `dart run tool/frame_timings.dart --vm-service ADDRESS --serial SERIAL`
```

After:

```dart
/// 2. From `app/`:
///    `dart run tool/frame_timings.dart --vm-service ADDRESS --serial SERIAL`
///    Frames are judged against 16.67 ms (60 fps); on a 120 Hz display pass
///    `--budget-ms 8.33` (D16).
```

In `_measure`. Before:

```dart
    frameStats = FrameStats.of(frames);
```

After:

```dart
    frameStats = FrameStats.of(frames, budgetMicros: options.budgetMicros);
```

In `_report`. Before:

```dart
        'budget ${ms(FrameStats.budgetMicros)} ms (60 fps)')
```

After:

```dart
        'budget ${ms(stats.budgetMicros)} ms '
        '(${(1e6 / stats.budgetMicros).round()} fps)')
```

`_Options`, the constructor. Before:

```dart
    required this.swipeY,
    required this.out,
  });
```

After:

```dart
    required this.swipeY,
    required this.budgetMicros,
    required this.out,
  });
```

The usage text. Before:

```dart
      '[--swipe-y PX] [--out results.json]';
```

After:

```dart
      '[--swipe-y PX] [--budget-ms 16.67] [--out results.json]';
```

The fields. Before:

```dart
  final int? swipeY;
  final String? out;
```

After:

```dart
  final int? swipeY;

  /// What build, raster and start delay are judged against: one sixtieth of
  /// a second unless `--budget-ms` says otherwise.
  final int budgetMicros;
  final String? out;
```

The known options. Before:

```dart
      'swipe-y',
      'out',
    };
```

After:

```dart
      'swipe-y',
      'budget-ms',
      'out',
    };
```

The parse. Before:

```dart
    final scenarioName = values['scenario'] ?? _Scenario.scroll.name;
```

After:

```dart
    final budgetText = values['budget-ms'];
    final budgetMicros = budgetText == null
        ? FrameStats.sixtyFpsBudgetMicros
        : FrameStats.budgetMicrosFromMs(budgetText);
    final scenarioName = values['scenario'] ?? _Scenario.scroll.name;
```

The return. Before:

```dart
      swipeY: swipeY,
      out: values['out'],
    );
```

After:

```dart
      swipeY: swipeY,
      budgetMicros: budgetMicros,
      out: values['out'],
    );
```

`docs/DEVELOPMENT.md`, *Measuring on a device*. Before:

```markdown
  - The frame tool's budget is fixed at 16.67 ms (60 fps). At 120 Hz a frame
    has 8.33 ms; see D16.
```

After:

```markdown
  - The frame tool judges against 16.67 ms (60 fps) unless given
    `--budget-ms`. At 120 Hz a frame has 8.33 ms: pass `--budget-ms 8.33`
    (D16).
```

- [ ] **Step 5: GREEN**

```bash
cd /c/Users/nimae/Desktop/nimbustats/app
flutter test --no-pub test/tool/frame_stats_test.dart
dart run tool/frame_timings.dart --vm-service http://127.0.0.1:1/x=/ --serial none --budget-ms fast; echo "exit=$?"
```

Expected:
- `+17: All tests passed!`
- `--budget-ms must be between 0.001 and 1000 milliseconds`, then the usage line, then `exit=64`. The flag reaches the parser, which rejects it before any adb or VM-service call.

- [ ] **Step 6: Broader suite**

```bash
cd /c/Users/nimae/Desktop/nimbustats/app && flutter test --no-pub --concurrency=4 --timeout 90s 2>&1 | tail -3
cd /c/Users/nimae/Desktop/nimbustats && dart analyze --fatal-infos
```

Expected: `All tests passed!` and `No issues found!`. Run tests in the foreground, one process at a time. If a file fails to load with a semaphore timeout on 127.0.0.1, kill the stray `dart`/`flutter_tester` processes and re-run (memory `app-suite-concurrency-cap`).

- [ ] **Step 7: Commit**

```bash
cd /c/Users/nimae/Desktop/nimbustats
git add app/tool/src/frame_stats.dart app/tool/frame_timings.dart app/test/tool/frame_stats_test.dart docs/DEVELOPMENT.md
git commit -m "$(cat <<'EOF'
feat: the frame tool judges against a chosen frame budget

D16: the A53's display runs at 120 Hz, where a frame has 8.33 ms, but
the tool's budget was a fixed 16.67 ms, so month steps that drop frames
there counted as on budget.

--budget-ms sets the budget for build, raster and start delay, reported
with its frame rate. Without it nothing changes: 16.667 ms, "(60 fps)".
Milliseconds parse as typed (8.33 is 8,330 us); anything outside
(0, 1000] ms is a usage error.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git log -1 --format='%h %s'
```

#### (b) The baseline at 120 Hz

- [ ] **Step 8: Measure the dashboard and Breakdown**

**Ask the operator first**: the phone is needed for about 30 minutes. The app's UI must be in **English**, because the tool finds the "Previous month" and "Next month" buttons by their English names. If it is in Persian, pass `--previous-label "ماه قبل" --next-label "ماه بعد"`, after checking the exact strings with a dump.

```bash
source "$S/device/helpers.sh"; guard || exit 1
mkdir -p "$S/d16"
a shell dumpsys display | grep -m1 mActiveRenderFrameRate
cd /c/Users/nimae/Desktop/nimbustats/app && flutter build apk --profile
```

Expected: `mActiveRenderFrameRate=120`. If it reads 60, ask the operator: the bar is judged at 120 Hz. Then `✓ Built … app-profile.apk`.

Start the app with its VM service. This is a long-running command, so start it with the Bash tool's `run_in_background`:

```bash
cd /c/Users/nimae/Desktop/nimbustats/app
sleep 3000 | flutter run --profile -d RZCT209E3QX --use-application-binary build/app/outputs/flutter-apk/app-profile.apk > "$S/d16/run.log" 2>&1
```

Poll until the address appears (the Monitor tool, or this block repeated):

```bash
grep -oE 'http://127\.0\.0\.1:[0-9]+/[A-Za-z0-9_-]+=/' "$S/d16/run.log" | head -1 | tee "$S/d16/vm.txt"
```

Expected: one `http://127.0.0.1:PORT/TOKEN=/` line.

Then open the dashboard: `source "$S/device/helpers.sh"; dump && tapon 'content-desc="Analytics'`. Count the visible cards with `grep -o 'content-desc="Card options"' "$S/ui.xml" | wc -l`. Phase 3 measured a dashboard of 8 cards. Record the count, and if it is not 8, tell the operator; do not re-pin cards without their OK.

A pass:

```bash
cd /c/Users/nimae/Desktop/nimbustats/app
NAME=dash-1
dart run tool/frame_timings.dart --vm-service "$(cat "$S/d16/vm.txt")" --serial RZCT209E3QX \
  --adb C:/dev/android-sdk/platform-tools/adb.exe --scenario months --swipes 10 \
  --budget-ms 8.33 --out "$S/d16/$NAME.json"
```

Run, in order:
- `dash-warmup`, which is reported and not judged;
- `dash-1`, `dash-2`, `dash-3`;
- then open Breakdown (`source "$S/device/helpers.sh"; dump && tapon 'content-desc="Breakdown'`);
- `brk-warmup`, `brk-1`, `brk-2`, `brk-3`.

Expected each time: a table with `budget 8.33 ms (120 fps)` and a `written to …` line.

The summary:

```bash
for f in "$S"/d16/{dash,brk}-[0-9].json; do
  python -I -c "import json,sys; d=json.load(open(sys.argv[1])); print(sys.argv[1].rsplit('/',1)[-1], 'frames', d['count'], 'p99 build', d['build']['p99Micros']/1000, 'p99 raster', d['raster']['p99Micros']/1000, 'over', d['overBudgetEither'])" "$f"
done | tee "$S/d16/baseline.txt"
```

Expected: the worst p99 build is near Phase 3's figures, 12.3-13.0 ms on the dashboard and 13.6-14.4 ms on Breakdown. Record the table.

#### (c) A timeline of one Breakdown month step

- [ ] **Step 9: Profile one step, per widget**

The executing agent cannot drive DevTools' UI, so a scratch script reads the same timeline over the VM service. It is not committed. Write `$S/d16/timeline.dart` with the Write tool:

```dart
// One month step, timed per widget, for D16. A scratch tool for the
// investigation, run against a profile build; not part of the app.
//
// dart --packages=.dart_tool/package_config.json <this file> \
//   <vm-service http address> <adb> <serial> <tap x> <tap y> <out.json>
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _profiling = [
  'ext.flutter.profileWidgetBuilds',
  'ext.flutter.profileRenderObjectLayouts',
  'ext.flutter.profileRenderObjectPaints',
];

final _phase = RegExp(
    r'^(BUILD|LAYOUT|PAINT|UPDATING COMPOSITING BITS|COMPOSITING|SEMANTICS|FINALIZE TREE)');

Future<void> main(List<String> args) async {
  if (args.length != 6) {
    stderr.writeln('usage: timeline.dart <vm-service> <adb> <serial> <x> <y> <out.json>');
    exitCode = 64;
    return;
  }
  final [address, adb, serial, x, y, out] = args;
  final http = Uri.parse(address);
  final path = http.path.endsWith('/') ? http.path : '${http.path}/';
  final service = await vmServiceConnectUri(
      http.replace(scheme: 'ws', path: '${path}ws').toString());
  try {
    final isolateId = await _flutterIsolate(service);
    Future<void> profile(bool on) async {
      for (final name in _profiling) {
        await service.callServiceExtension(name,
            isolateId: isolateId, args: {'enabled': '$on'});
      }
    }

    await profile(true);
    await service.setVMTimelineFlags(['Dart', 'Embedder', 'GC']);
    await service.clearVMTimeline();
    final tap = await Process.run(adb, ['-s', serial, 'shell', 'input', 'tap', x, y]);
    if (tap.exitCode != 0) throw StateError('adb tap failed: ${tap.stderr}');
    await Future<void>.delayed(const Duration(seconds: 2));
    final timeline = await service.getVMTimeline();
    await profile(false);
    final events = [
      for (final e in timeline.traceEvents ?? const <TimelineEvent>[]) e.json!,
    ];
    if (events.isEmpty) {
      throw StateError('the timeline is empty: is this a profile build?');
    }
    File(out).writeAsStringSync(jsonEncode({'traceEvents': events}));
    _summarise(events);
  } finally {
    await service.dispose();
  }
}

Future<String> _flutterIsolate(VmService service) async {
  for (final ref in (await service.getVM()).isolates ?? const <IsolateRef>[]) {
    final isolate = await service.getIsolate(ref.id!);
    if (isolate.extensionRPCs?.contains(_profiling.first) ?? false) return ref.id!;
  }
  throw StateError('no isolate offers ${_profiling.first}');
}

/// Each frame phase in time order, then the 40 costliest names (inclusive).
void _summarise(List<Map<String, dynamic>> events) {
  final open = <Object?, List<Map<String, dynamic>>>{};
  final total = <String, int>{};
  final count = <String, int>{};
  final phases = <String>[];
  void record(String name, int ts, int micros) {
    total[name] = (total[name] ?? 0) + micros;
    count[name] = (count[name] ?? 0) + 1;
    if (_phase.hasMatch(name)) {
      phases.add('${(ts / 1000).toStringAsFixed(1).padLeft(12)} ms  '
          '${name.padRight(28)} ${(micros / 1000).toStringAsFixed(2)} ms');
    }
  }

  final sorted = [...events]
    ..sort((a, b) => ((a['ts'] ?? 0) as num).compareTo((b['ts'] ?? 0) as num));
  for (final e in sorted) {
    final name = e['name'] as String? ?? '?';
    final ts = (e['ts'] as num?)?.toInt() ?? 0;
    switch (e['ph']) {
      case 'X':
        record(name, ts, (e['dur'] as num?)?.toInt() ?? 0);
      case 'B':
        (open[e['tid']] ??= []).add(e);
      case 'E':
        final stack = open[e['tid']];
        if (stack == null || stack.isEmpty) break;
        final begin = stack.removeLast();
        final start = (begin['ts'] as num).toInt();
        record(begin['name'] as String? ?? '?', start, ts - start);
    }
  }
  stdout.writeln('Frame phases, in time order:');
  phases.forEach(stdout.writeln);
  stdout.writeln('\nTop 40 by total time (name, count, total ms):');
  final names = total.keys.toList()
    ..sort((a, b) => total[b]!.compareTo(total[a]!));
  for (final name in names.take(40)) {
    stdout.writeln('${name.padRight(52)} ${count[name].toString().padLeft(5)} '
        '${(total[name]! / 1000).toStringAsFixed(2).padLeft(9)}');
  }
}
```

With the app on Breakdown at the current month:

```bash
source "$S/device/helpers.sh"; guard || exit 1
dump && centre 'content-desc="Previous month"' | tee "$S/d16/prev.txt"
cd /c/Users/nimae/Desktop/nimbustats
dart --packages=.dart_tool/package_config.json "$S/d16/timeline.dart" "$(cat "$S/d16/vm.txt")" \
  /c/dev/android-sdk/platform-tools/adb.exe RZCT209E3QX $(cat "$S/d16/prev.txt") "$S/d16/breakdown-step.json" \
  | tee "$S/d16/breakdown-step.txt"
```

Expected:
- a list of BUILD, LAYOUT and PAINT phases with their durations;
- the top-40 table;
- `breakdown-step.json`, a Chrome-trace file. It opens offline in Chrome's `chrome://tracing`, or in ui.perfetto.dev if the exit allows it.

If the timeline comes back empty, fall back to DevTools:
1. Ask the operator to open the "Flutter DevTools debugger and profiler" address from `run.log` in a browser. DevTools is served locally by the Flutter tool.
2. Performance → enable "Track widget builds", "Track layouts" and "Track paints".
3. Record, tap "Previous month" once, stop.
4. Export to `$S/d16`.

Repeat on the dashboard, with `dash-step` as the file names. The tracking adds overhead: these timelines attribute cost, the passes in (b) and (e) time it.

#### (d) Candidates, read off the timeline

- [ ] **Step 10: Decide what the timeline shows**

Read `breakdown-step.txt` and `dash-step.txt` against this table. Record each verdict, with the lines that support it, in `$S/d16/findings.md`.

| # | Candidate (from DEFERRED D16) | How it shows in the timeline | What it implies |
|---|---|---|---|
| A | A whole rebuild where only the values changed, and the chart built twice, once for loading and once for data | Right after the tap, a BUILD containing `NimbusLoadingList` on Breakdown, or a card's skeleton on the dashboard. Then a later heavy BUILD that inflates the body from scratch: `BreakdownBody`, `ListTile`/`_BreakdownRow` × the visible rows, `PieChart`, `TotalHeader`; on the dashboard `CardPreview` per card. Nothing is reused, because the loading state replaced the body. The code confirms the mechanism: a month step asks a new `analyticsResultProvider(spec)` family member, which starts with no value. `_BreakdownTab` then shows `NimbusLoadingList`, and `_Readable` shows `_CardSkeleton`. | **Fix A** below: keep the shown answer until the next arrives, so the step is one update of a live tree instead of a teardown and a rebuild. |
| B | A list that builds every row | Each `_BreakdownRow` built far more often than there are rows on screen | Not expected: `BreakdownBody`'s `ListView(children:)` already inflates only visible children, and wraps each in a `RepaintBoundary` (`addRepaintBoundaries` defaults to true). If it shows anyway, record it and ask the operator. |
| C | The chart's swap animation | `PieChart` (and its `PieChartLeaf` layout and paint) in about 18 consecutive frames after the data frame: fl_chart 1.2.0's default `duration` is 150 ms (`pie_chart.dart:17`), which is 18 frames at 120 Hz | **Fix C** below: `duration: Duration.zero` on the PieCharts the timeline names. |
| D | Layout or paint passes a `RepaintBoundary` or a const subtree would avoid | LAYOUT or PAINT phases as long as BUILD in the worst frames, dominated by one subtree outside a list item (the month bar, the tab bar) | Each list item is already a repaint boundary. Record the subtree and its numbers and ask the operator before changing it. |

Apply the fixes in the order A, then C. Only apply what the timeline shows, each as its own commit with its test. Re-measure (e) after each. If none of A to D explains the worst BUILD, record the top-40 table and **stop for the operator**.

- [ ] **Step 11 (only if A shows): Fix A, a month step keeps the shown answer**

Tag:

```bash
cd /c/Users/nimae/Desktop/nimbustats && git tag pre-keep-shown-answer
```

Tests first. In `app/test/features/analytics/breakdown_screen_test.dart`, add after the test `'the period can be moved and the total follows'`:

```dart
  testWidgets('a month step keeps the shown breakdown until the next arrives',
      (tester) async {
    // D16: a skeleton frame, then a from-scratch rebuild of the pie and the
    // rows, cost two heavy frames per step on a 120 Hz screen.
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    await seedLastMonth(db);
    await openBreakdown(tester, db);

    await tester.tap(find.byKey(const Key('breakdown-period-previous')));
    await tester.pump();

    expect(find.byType(NimbusLoadingList), findsNothing);
    expect(find.byType(PieChart), findsOneWidget);

    await tester.pumpAndSettle();
    expect(textOf(tester, 'breakdown-amount-seed-transport'), '۳۰۰');
  });
```

In `app/test/features/analytics/dashboard_tab_test.dart`, add after `'the month bar moves every card together'`:

```dart
  testWidgets("a month step keeps each card's answer until the next arrives",
      (tester) async {
    // D16: a skeleton then a from-scratch preview, per card, per step.
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final (breakdown, _) = await pinStarters(db);
    await openAnalytics(tester, db);

    await tester.tap(find.byKey(const Key('dashboard-period-previous')));
    await tester.pump();

    expect(find.byKey(const Key('card-loading')), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byKey(Key('card-empty-$breakdown')), findsOneWidget);
  });
```

RED:

```bash
cd /c/Users/nimae/Desktop/nimbustats/app
flutter test --no-pub test/features/analytics/breakdown_screen_test.dart --plain-name "keeps the shown breakdown"
flutter test --no-pub test/features/analytics/dashboard_tab_test.dart --plain-name "keeps each card's answer"
```

Expected: both fail. The first finds one `NimbusLoadingList`; the second finds two `card-loading` widgets, one per starter card. On the first frame after the tap, the new spec's provider has no value yet.

Implement. In `app/lib/features/analytics/presentation/analytics_screen.dart`, before:

```dart
class _BreakdownTab extends ConsumerWidget {
  const _BreakdownTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(breakdownControllerProvider);
    final controller = ref.read(breakdownControllerProvider.notifier);
    final result = ref.watch(analyticsResultProvider(view.spec));
    final nodes = ref.watch(categoryNodesByIdProvider);
```

After:

```dart
class _BreakdownTab extends ConsumerStatefulWidget {
  const _BreakdownTab();

  @override
  ConsumerState<_BreakdownTab> createState() => _BreakdownTabState();
}

class _BreakdownTabState extends ConsumerState<_BreakdownTab> {
  /// The answer last drawn and the period it covers. A month step asks a new
  /// question whose provider starts with no value; drawing this until it
  /// answers spares a skeleton frame and a from-scratch rebuild of the pie
  /// and the rows on every step (D16).
  (AnalyticsResult, DateRange)? _shown;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(breakdownControllerProvider);
    final controller = ref.read(breakdownControllerProvider.notifier);
    final result = ref.watch(analyticsResultProvider(view.spec));
    final nodes = ref.watch(categoryNodesByIdProvider);
    if (result case AsyncData(value: final data)) _shown = (data, view.period);
```

And the body's switch. Before:

```dart
          child: switch ((result, nodes)) {
            (AsyncError(:final error), _) || (_, AsyncError(:final error)) =>
              NimbusErrorState(
                title: AppLocalizations.of(context).analyticsErrorTitle,
                detail: error.toString(),
                retryLabel: AppLocalizations.of(context).commonRetry,
                onRetry: () =>
                    ref.invalidate(analyticsResultProvider(view.spec)),
              ),
            (AsyncData(value: final data), AsyncData(value: final byId)) =>
              BreakdownBody(
                result: data,
                period: view.period,
                nodesById: byId,
                formatter: ref.watch(moneyFormatterProvider),
                onDrill: controller.drillInto,
              ),
            _ => const NimbusLoadingList(),
          },
```

After:

```dart
          // Between two answers, the last one stays on screen (D16).
          child: switch ((result, nodes, _shown)) {
            (AsyncError(:final error), _, _) ||
            (_, AsyncError(:final error), _) =>
              NimbusErrorState(
                title: AppLocalizations.of(context).analyticsErrorTitle,
                detail: error.toString(),
                retryLabel: AppLocalizations.of(context).commonRetry,
                onRetry: () =>
                    ref.invalidate(analyticsResultProvider(view.spec)),
              ),
            (_, AsyncData(value: final byId), (final data, final period)?) =>
              BreakdownBody(
                result: data,
                period: period,
                nodesById: byId,
                formatter: ref.watch(moneyFormatterProvider),
                onDrill: controller.drillInto,
              ),
            _ => const NimbusLoadingList(),
          },
```

In `app/lib/features/analytics/presentation/widgets/saved_view_card.dart`, before:

```dart
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
```

After:

```dart
class _Readable extends ConsumerStatefulWidget {
  const _Readable({required this.view, required this.anchor});

  final SavedView view;
  final DateKey anchor;

  @override
  ConsumerState<_Readable> createState() => _ReadableState();
}

class _ReadableState extends ConsumerState<_Readable> {
  /// The question this card last answered, and its answer. A month step asks
  /// a new question whose provider starts with no value; showing this until
  /// it answers spares a skeleton and a from-scratch preview per card per step
  /// (D16). The period label follows the shown question, so a card never
  /// pairs one month's label with another month's total.
  (QuerySpec, AnalyticsResult)? _shown;

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final calendar = ref.watch(calendarProvider);
    final formatter = ref.watch(moneyFormatterProvider);
    final asked = resolvedSpec(view, widget.anchor, calendar,
        firstDayOfWeek: ref.watch(firstDayOfWeekProvider));
    final result = ref.watch(analyticsResultProvider(asked));

    // hasError/hasValue rather than a switch over the AsyncValue subtypes:
    // while an answer re-runs after a write it is a loading value that still
    // holds the old answer, and the card should keep showing it.
    final fresh = result.hasError ? null : result.value;
    if (fresh != null) _shown = (asked, fresh);
    final shown = result.hasError ? null : _shown;
    final spec = shown?.$1 ?? asked;
    final data = shown?.$2;
```

The rest of `build` is unchanged. It reads `view`, `spec`, `data`, `result`, `formatter`, `theme`, `l10n` and `calendar`, and on an error `spec` is the asked one, so Retry invalidates the right provider.

GREEN, then the two analytics test files whole:

```bash
cd /c/Users/nimae/Desktop/nimbustats/app
flutter test --no-pub test/features/analytics/breakdown_screen_test.dart test/features/analytics/dashboard_tab_test.dart test/features/analytics/card_previews_test.dart test/features/analytics/saved_view_screen_test.dart
```

Expected: `All tests passed!`.

Broader: `flutter test --no-pub --concurrency=4 --timeout 90s` in `app/`, then `dart analyze --fatal-infos` from the root. Both green.

Commit:

```bash
cd /c/Users/nimae/Desktop/nimbustats
git add app/lib/features/analytics/presentation/analytics_screen.dart \
        app/lib/features/analytics/presentation/widgets/saved_view_card.dart \
        app/test/features/analytics/breakdown_screen_test.dart \
        app/test/features/analytics/dashboard_tab_test.dart
git commit -m "$(cat <<'EOF'
fix(analytics): a month step keeps the shown answer until the next arrives

D16: a month step asks a new analyticsResultProvider question, which
starts with no value, so Breakdown drew its loading list and every
dashboard card its skeleton for a frame, then rebuilt the pie, rows and
previews from scratch. The profile timeline of one Breakdown step on the
A53 showed that teardown and rebuild in the frames over 8.33 ms.

Breakdown and each card now keep the answer they last drew (with its
period or question, so labels never mix months) until the new one
arrives, and the step updates a live tree. An error still shows at once.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git log -1 --format='%h %s'
```

- [ ] **Step 12 (only if C shows): Fix C, the pies draw at once**

Tag:

```bash
cd /c/Users/nimae/Desktop/nimbustats && git tag pre-static-pies
```

Tests first. In `breakdown_screen_test.dart`, after `'a category breakdown draws a pie'`:

```dart
  testWidgets('the pie is drawn at once, not animated in', (tester) async {
    // D16: fl_chart's default 150 ms swap animation rebuilds and repaints the
    // pie on every frame of a month step.
    final db = await seededDb();
    addTearDown(db.close);
    await seedSpending(db);
    await openBreakdown(tester, db);

    expect(tester.widget<PieChart>(find.byType(PieChart)).duration,
        Duration.zero);
  });
```

In `card_previews_test.dart`, after `'a breakdown card lists its top categories beside a pie'`:

```dart
  testWidgets('a breakdown card draws its pie at once, not animated in',
      (tester) async {
    final db = await categorisedDb();
    addTearDown(db.close);
    await seedSpending(db);
    final id = await _pin(
        db, BreakdownView(period: _month).spec, SavedViewChart.breakdown);
    await openAnalytics(tester, db);

    expect(tester.widget<PieChart>(_inCard(id, find.byType(PieChart))).duration,
        Duration.zero);
  });
```

RED:

```bash
cd /c/Users/nimae/Desktop/nimbustats/app
flutter test --no-pub test/features/analytics/breakdown_screen_test.dart --plain-name "drawn at once"
flutter test --no-pub test/features/analytics/card_previews_test.dart --plain-name "draws its pie at once"
```

Expected: both fail with `Expected: Duration:<0:00:00.000000> Actual: Duration:<0:00:00.150000>`.

Implement. In `breakdown_body.dart`, before:

```dart
                      showTitle: false,
                      radius: 40,
                    ),
              ],
            ),
          ),
```

After:

```dart
                      showTitle: false,
                      radius: 40,
                    ),
              ],
            ),
            // Drawn at once: the default 150 ms swap animation rebuilds and
            // repaints the pie on every frame of a month step (D16).
            duration: Duration.zero,
          ),
```

In `card_previews.dart` (`_BreakdownPreview`), before:

```dart
                    showTitle: false,
                    radius: 28,
                  ),
              ],
            ),
          ),
```

After:

```dart
                    showTitle: false,
                    radius: 28,
                  ),
              ],
            ),
            // Drawn at once, as on Breakdown (D16).
            duration: Duration.zero,
          ),
```

If the timeline shows another fl_chart chart animating (`BarChart` or `LineChart` in `card_previews.dart` or `trends_body.dart`), give it the same `duration: Duration.zero` in this commit, with a test of the same shape for each.

GREEN: re-run both RED commands and expect both to pass. Broader: the app suite with `--concurrency=4` and `dart analyze --fatal-infos`.

Commit:

```bash
cd /c/Users/nimae/Desktop/nimbustats
git add app/lib/features/analytics/presentation/widgets/breakdown_body.dart \
        app/lib/features/analytics/presentation/widgets/card_previews.dart \
        app/test/features/analytics/breakdown_screen_test.dart \
        app/test/features/analytics/card_previews_test.dart
git commit -m "$(cat <<'EOF'
fix(analytics): the breakdown pies draw at once on a month step

D16: fl_chart animates a PieChart for 150 ms by default when its data
changes: on the A53's 120 Hz screen that is 18 frames of rebuilding,
relaying out and repainting the pie after every month step, which the
profile timeline showed among the frames over 8.33 ms.

Breakdown's pie and the dashboard card's pie take duration zero. The
slices simply show the new month.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git log -1 --format='%h %s'
```

#### (e) Re-measure and record

- [ ] **Step 13: Re-run (b) on a fresh profile build, then decide**

1. Stop the background `flutter run`.
2. Rebuild with `flutter build apk --profile`.
3. Restart it as in Step 8 and read the new `vm.txt`.
4. Run Step 8's passes again, writing to `dash-after-{warmup,1,2,3}` and `brk-after-{warmup,1,2,3}`.
5. Summarise them into `$S/d16/after.txt` with the same loop over `"$S"/d16/{dash,brk}-after-[0-9].json`.

**Done when** each of the six measured passes has p99 build ≤ 8.33 ms; raster is reported, not judged.

If not met:
1. Run (c) again on the new build, to see whether another candidate now leads.
2. Apply it if it is A or C.
3. Otherwise **stop**: show the operator `baseline.txt`, `after.txt` and `findings.md`, and record their decision verbatim in `$S/d16/decision.md` for Task 25.

Stop the background `flutter run` when done. The profile APK stays installed.

---

### Task 24: Below Android 12, on an Android 11 emulator (D33)

Slug `widget-rows-pre12`, only if a clip is confirmed.

**Files:**
- No change if nothing clips.
- If it clips, after the operator picks an option:
  - `app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetRenderer.kt`;
  - new `app/android/app/src/test/kotlin/com/nimbustats/app/widget/WidgetRendererTest.kt`;
  - `app/android/app/src/main/res/xml/expense_widget_info.xml` and `app/android/app/src/main/res/xml-v31/expense_widget_info.xml` (comments).

**Interfaces, if fixed:** `internal fun WidgetRenderer.rowCapacity(heightDp: Int): Int`. `build(context, capacity: Int = 2)` is used below API 31 only.

**What is installed, checked 2026-10-14:**
- `sdkmanager --list_installed` lists `system-images;android-30;default;x86_64` at **revision 10**: its `source.properties` says `Pkg.Revision=10`, while the spec says r11. It has no `package.xml`, but the SDK manager reads it from `source.properties`.
- `emulator 37.1.11`, which reports `WHPX(10.0.26300) is installed and usable.`
- `avdmanager list device` offers `pixel_4`.
- `%USERPROFILE%\.android\avd` exists and is empty.
- `ANDROID_HOME=C:\dev\android-sdk`.

- [ ] **Step 1: Create the AVD (PowerShell)**

```powershell
echo no | & "C:\dev\android-sdk\cmdline-tools\latest\bin\avdmanager.bat" create avd -n nimbus_api30 -k "system-images;android-30;default;x86_64" -d pixel_4
Get-Content "$env:USERPROFILE\.android\avd\nimbus_api30.avd\config.ini" | Select-String "image.sysdir|abi.type|hw.lcd"
```

Expected: no error, ignoring the "sdkmanager is deprecated" warning, and `image.sysdir.1=system-images\android-30\default\x86_64\`.

**Fallback if `avdmanager` refuses the hand-extracted image.** Write these two files with the Write tool.

`C:\Users\nimae\.android\avd\nimbus_api30.ini`:

```ini
avd.ini.encoding=UTF-8
path=C:\Users\nimae\.android\avd\nimbus_api30.avd
path.rel=avd\nimbus_api30.avd
target=android-30
```

`C:\Users\nimae\.android\avd\nimbus_api30.avd\config.ini`:

```ini
AvdId=nimbus_api30
PlayStore.enabled=false
abi.type=x86_64
avd.ini.displayname=nimbus_api30
avd.ini.encoding=UTF-8
disk.dataPartition.size=6G
hw.accelerometer=yes
hw.audioInput=no
hw.battery=yes
hw.camera.back=none
hw.camera.front=none
hw.cpu.arch=x86_64
hw.cpu.ncore=4
hw.dPad=no
hw.device.manufacturer=Google
hw.device.name=pixel_4
hw.gps=no
hw.gpu.enabled=yes
hw.gpu.mode=auto
hw.keyboard=yes
hw.lcd.density=440
hw.lcd.height=2280
hw.lcd.width=1080
hw.mainKeys=no
hw.ramSize=2048
hw.sdCard=no
hw.sensors.orientation=yes
hw.sensors.proximity=no
hw.trackBall=no
image.sysdir.1=system-images\android-30\default\x86_64\
tag.display=Default Android System Image
tag.id=default
vm.heapSize=256
```

Then `& "C:\dev\android-sdk\emulator\emulator.exe" -list-avds` must print `nimbus_api30`.

- [ ] **Step 2: Boot it with WHPX, and install the debug APK**

Start it in PowerShell with `run_in_background`. The emulator's window stays open for the operator:

```powershell
& "C:\dev\android-sdk\emulator\emulator.exe" -avd nimbus_api30 -accel on -no-snapshot -no-boot-anim
```

Then in Git Bash. The A53 may also be attached, so every command names the emulator:

```bash
E() { MSYS_NO_PATHCONV=1 /c/dev/android-sdk/platform-tools/adb.exe -s emulator-5554 "$@"; }
mkdir -p "$S/d33"
E wait-for-device
for i in $(seq 1 60); do [ "$(E shell getprop sys.boot_completed | tr -d '\r')" = 1 ] && break; E shell sleep 5; done
E shell getprop ro.build.version.sdk
cd /c/Users/nimae/Desktop/nimbustats/app && flutter build apk --debug
E install -r "$(cygpath -w build/app/outputs/flutter-apk/app-debug.apk)"
```

Expected: `30`, then `Success`. The debug APK carries `x86_64`, per the D1 record, and minSdk is 26.

- [ ] **Step 3: A snapshot with three trackers, without opening the app**

The widget renders from `files/widget_snapshot.json`. Never open the app on the emulator during this task: it would ask for onboarding and later rewrite the snapshot. Write `$S/d33/snapshot.json` with the Write tool. Its strings are the English ARB values (`widget*` in `app_en.arb`), and it passes `WidgetSnapshot.parse`: `v` 1, every required string, `decimalDigits` 0-3.

```json
{
  "v": 1,
  "dayKey": 0,
  "localeTag": "en",
  "rtl": false,
  "currency": {"code": "IRT", "decimalDigits": 0, "label": "Toman"},
  "trackers": [
    {"id": "d33-water", "name": "Water", "color": 4280391411, "type": "counter", "perTap": 1.0, "unit": null, "todayTotal": 3.0},
    {"id": "d33-coffee", "name": "Coffee", "color": 4294940672, "type": "counter", "perTap": 1.0, "unit": null, "todayTotal": 1.0},
    {"id": "d33-gym", "name": "Gym", "color": 4283215696, "type": "boolean", "perTap": 1.0, "unit": null, "todayTotal": 0.0}
  ],
  "chips": [],
  "strings": {
    "addExpense": "+ Expense",
    "emptyTrackers": "Add a tracker in the app to log it from here",
    "entryTitle": "Add expense",
    "save": "Save",
    "cancel": "Cancel",
    "saved": "Saved",
    "trackerAdd": "{name}, today {total}. Add one",
    "trackerDone": "{name}, done today"
  }
}
```

```bash
E() { MSYS_NO_PATHCONV=1 /c/dev/android-sdk/platform-tools/adb.exe -s emulator-5554 "$@"; }
sed -i "s/\"dayKey\": 0/\"dayKey\": $(E shell date +%Y%m%d | tr -d '\r')/" "$S/d33/snapshot.json"
E exec-in "run-as com.nimbustats.app sh -c 'mkdir -p files && cat > files/widget_snapshot.json'" < "$S/d33/snapshot.json"
E exec-out run-as com.nimbustats.app cat files/widget_snapshot.json | head -c 120; echo
```

Expected: the file's first bytes, with today's `dayKey`.

- [ ] **Step 4: Place the widget at its default size, and screenshot it**

On the AOSP launcher of API 30, a widget is placed by long-press and drag.

1. Go home, then long-press empty space: `E shell input keyevent KEYCODE_HOME`, then `E shell input swipe 540 1400 540 1400 1200`. The menu offers "Widgets".
2. Dump with `E shell uiautomator dump /sdcard/ui.xml && E exec-out cat /sdcard/ui.xml > "$S/d33/ui.xml"`. Tap "Widgets" at its bounds' centre.
3. Find the NimbuStats entry in the tray, under the app "nimbustats". Scroll with `E shell input swipe 540 1800 540 800 300` until a dump shows it.
4. Drag it to the home screen with `E shell input draganddrop <x> <y> 540 1100 1500`, using the entry's centre for `<x> <y>`.
5. If `input` prints its usage, meaning there is no `draganddrop` on this image, or nothing is placed, **ask the operator to drag it in the emulator window with the mouse.**
6. Tap empty space to drop the resize frame.

```bash
E() { MSYS_NO_PATHCONV=1 /c/dev/android-sdk/platform-tools/adb.exe -s emulator-5554 "$@"; }
E exec-out screencap -p > "$S/d33/widget-default.png"
E shell wm density
E shell dumpsys appwidget | grep -B2 -A14 "com.nimbustats.app.widget.ExpenseWidgetProvider" | grep -iE "id=|options|Height|Width" | tee "$S/d33/options.txt"
```

Read `widget-default.png`:
- Record the default span, from the cells it covers.
- Record its height in dp: pixels ÷ (density ÷ 160); at 440 that is ÷ 2.75.
- Record any `appWidgetMinHeight`/`appWidgetMaxHeight` from `options.txt`.

Two fixed rows need 168 dp: 24 of padding, the 48 dp "+ Expense" and two 48 dp rows.

If the default span is not 4 × 2, also ask the operator to resize it to 4 × 2 with the handles, then take `widget-4x2.png` and re-read `options.txt`.

**Criterion:** at the default size and at 4 × 2, "+ Expense", **both** tracker rows (Water and Coffee, each with its [+]) and the 12 dp bottom padding show uncut, inside the rounded background.

- [ ] **Step 5: Decide**

**Nothing clips:** record it in `$S/d33/results.md` with the span, the height in dp and the screenshots, and go to Step 7. Task 25 closes D33 with no code change.

**A row clips:** show the operator the screenshot and the numbers, and ask which fix:
- **(i) Rows by the reported height.** Below Android 12, each widget gets `rowCapacity(OPTION_APPWIDGET_MIN_HEIGHT)` rows, 0 to 4, and keeps 2 when the launcher reports no height. It never clips, but at a 110-130 dp default it shows 0-1 rows.
- **(ii) A taller default.** Below Android 12, `minHeight` becomes 180 dp: three cells by the pre-12 rule of 70 n − 30, which holds two rows. This changes the spec's §6.4 default from 4 × 2 to 4 × 3 on Android 11 and older only. A resize still allows 120 dp, and without (i) a resize below 168 dp clips again.
- **(iii) Both. Recommended:** two rows at the default, and no clip at any size.

- [ ] **Step 6 (only if a row clips): TDD the chosen fix**

Tag:

```bash
cd /c/Users/nimae/Desktop/nimbustats && git tag pre-widget-rows-pre12
```

**(i), the test first.** Create `app/android/app/src/test/kotlin/com/nimbustats/app/widget/WidgetRendererTest.kt`:

```kotlin
package com.nimbustats.app.widget

import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetRendererTest {
    @Test
    fun theRowsAreThoseTheReportedHeightHolds() { // D33
        assertEquals(0, WidgetRenderer.rowCapacity(110))
        assertEquals(1, WidgetRenderer.rowCapacity(120))
        assertEquals(1, WidgetRenderer.rowCapacity(167))
        assertEquals(2, WidgetRenderer.rowCapacity(168))
        assertEquals(4, WidgetRenderer.rowCapacity(264))
    }

    @Test
    fun neverMoreThanFourOrFewerThanNone() {
        assertEquals(4, WidgetRenderer.rowCapacity(1_000))
        assertEquals(0, WidgetRenderer.rowCapacity(0))
    }
}
```

RED:

```bash
cd /c/Users/nimae/Desktop/nimbustats/app/android
./gradlew :app:testDebugUnitTest --tests "com.nimbustats.app.widget.WidgetRendererTest"
```

Expected: `compileDebugUnitTestKotlin FAILED` on `Unresolved reference 'rowCapacity'`. `WidgetRenderer` is an `object` with no static Android calls, so the JVM loads it as it does `WidgetBuffer`.

**(i), the implementation.** In `WidgetRenderer.kt`, `renderAll`. Before:

```kotlin
        if (ids.isEmpty()) return
        val views = build(context)
        for (id in ids) manager.updateAppWidget(id, views)
    }
```

After:

```kotlin
        if (ids.isEmpty()) return
        if (Build.VERSION.SDK_INT >= 31) {
            val views = build(context)
            for (id in ids) manager.updateAppWidget(id, views)
            return
        }
        // Below Android 12 there are no size buckets: each widget gets the rows its own height holds
        // (D33). The smaller reported height, so no orientation clips a row; a launcher that
        // reports none keeps the old two rows.
        for (id in ids) {
            val heightDp = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            manager.updateAppWidget(id, build(context, if (heightDp > 0) rowCapacity(heightDp) else 2))
        }
    }

    /** Rows that fit [heightDp]: 24 dp of padding and the 48 dp button, then 48 dp a row; 0 to 4. */
    internal fun rowCapacity(heightDp: Int): Int = ((heightDp - 24 - 48) / 48).coerceIn(0, 4)
```

`build`'s signature and its pre-12 branch. Before:

```kotlin
    private fun build(context: Context): RemoteViews {
```

```kotlin
            } else {
                layout(context, snapshot, rows, 2)
            }
```

After:

```kotlin
    /** [capacity]: the rows below Android 12, where there are no size buckets. */
    private fun build(context: Context, capacity: Int = 2): RemoteViews {
```

```kotlin
            } else {
                layout(context, snapshot, rows, capacity)
            }
```

The class KDoc. Before:

```kotlin
 * padding, the 48 dp button and 48 dp per row); below 12 there are 2 rows.
```

After:

```kotlin
 * padding, the 48 dp button and 48 dp per row); below 12, as many as the widget's reported height
 * holds, or 2 when the launcher reports none (D33).
```

**(ii), only if chosen.** In `res/xml/expense_widget_info.xml`, before:

```xml
<!-- One resizable widget, 4x2 by default (spec §6.4). No polling:
     updatePeriodMillis is 0, and the widget re-renders on snapshot writes,
     taps and the midnight alarm. -->
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:initialLayout="@layout/widget_loading"
    android:minHeight="110dp"
```

After:

```xml
<!-- One resizable widget, 4x2 by default on Android 12+ (xml-v31, spec §6.4).
     Below 12, 180dp: three cells by the old 70n - 30 rule, the height two
     rows need (D33, operator decision). No polling: updatePeriodMillis is 0,
     and the widget re-renders on snapshot writes, taps and the midnight
     alarm. -->
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:initialLayout="@layout/widget_loading"
    android:minHeight="180dp"
```

In `res/xml-v31/expense_widget_info.xml`, before:

```xml
     minHeight, so below 120dp the 48dp [+] would clip. Pre-12 keeps 110dp. -->
```

After:

```xml
     minHeight, so below 120dp the 48dp [+] would clip. Pre-12 asks 180dp (D33). -->
```

GREEN:
1. Run the RED command again: `BUILD SUCCESSFUL`, `tests="2" … failures="0"`.
2. Broader: `./gradlew :app:testDebugUnitTest`, 35 tests, then `flutter build apk --debug`.
3. Re-check on the emulator:
   - `E install -r …app-debug.apk`;
   - remove the widget (long-press → Remove, or the operator by hand);
   - place it again at its default size and take `widget-default-after.png`;
   - the operator resizes it to its smallest, then take `widget-smallest-after.png`.

   Expected: no clipped row in either. With (ii), two rows at the default.

Commit:

```bash
cd /c/Users/nimae/Desktop/nimbustats
git add app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetRenderer.kt \
        app/android/app/src/test/kotlin/com/nimbustats/app/widget/WidgetRendererTest.kt \
        app/android/app/src/main/res/xml/expense_widget_info.xml \
        app/android/app/src/main/res/xml-v31/expense_widget_info.xml
git commit -m "$(cat <<'EOF'
fix(widget): below Android 12 the rows follow the widget's height

D33: Android 11 has no size buckets, and the widget always drew two
fixed rows (168 dp). On an Android 11 emulator (AOSP launcher) the
default placement was shorter than that and the second row was cut.

Below 12 each widget now gets the rows its reported height holds, 0 to
4 (two when the launcher reports none), and the pre-12 minHeight asks
180 dp, three cells by the old rule, so the default shows both rows
(operator decision). Android 12+ keeps its responsive buckets.
rowCapacity is covered by JUnit; the layout was re-checked on the
emulator at the default and smallest sizes.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

If only (i) or only (ii) was chosen, stage only its files, and in the body drop the sentence about the part not chosen.

- [ ] **Step 7: Shut the emulator down**

```bash
MSYS_NO_PATHCONV=1 /c/dev/android-sdk/platform-tools/adb.exe -s emulator-5554 emu kill
```

The AVD stays for later checks. Record everything in `$S/d33/results.md`.

---

### Task 25: Docs closure and the merge

Slug `docs-deferred-sweep`.

**Files:**
- Modify: `docs/phases/DEFERRED.md`
- Modify: `docs/phases/README.md`
- Modify: `docs/phases/phase-3-analytics.md`, only if D16 is resolved: its link at line 302.

**Inputs:**
- `$S/device/results.md` (Task 21);
- `$S/d30/result.env` (Task 22);
- `$S/d16/{baseline,after}.txt`, `findings.md` and `decision.md` (Task 23);
- `$S/d33/results.md` (Task 24).

**How each item's commit is found.** Every sweep commit's body starts with `Dnn:`, as the commits in Tasks 16-24 do. Tasks 1-15 must follow the same rule: see the Notes. Two token kinds stand in for values a script fills from git:
- `{{hash:Dnn}}` becomes the item's commit hashes, in backticks, comma-separated;
- `{{date:Dnn}}` becomes the item's last commit date.

`{{today}}` is the docs commit's date. `{{measured:…}}` tokens are numbers from the records above, typed in by hand. The guard in Step 4 refuses to continue while any `{{` remains.

The existing format is mirrored from D24: the heading gains ` — RESOLVED` (or ` — CLOSED`), and the `**Status:**` line becomes a short "resolved/closed … by `<hash>` …; the original finding follows." paragraph. The original text below it stays.

- [ ] **Step 1: Tag the rollback target**

```bash
cd /c/Users/nimae/Desktop/nimbustats && git tag pre-docs-deferred-sweep
```

- [ ] **Step 2: The top table**

In `DEFERRED.md`, replace the rows `| D12 |` to `| D36 |` (lines 15-35) with the rows below, in this order. They go above `| D24 | ~~Goal screens…`. Rows `D2`, `D4` and `D10` stay as they are.

```markdown
| D12 | ~~No global uncaught-error handler: a rethrown write failure reaches only the console~~ | — | **Resolved {{date:D12}}** |
| D16 | ~~Month-change rebuilds drop frames on a 120 Hz display~~ | — | **Resolved {{date:D16}}** |
| D17 | ~~Phase 1's haptics are silent on the A53~~ | — | **Resolved {{date:D17}}** |
| D18 | ~~Tracker haptics are too faint to feel at the lowest touch strength~~ | — | **Closed 2026-10-14** (operator decision) |
| D19 | ~~Tracker charts misread at the edges of their scale: a sub-minute duration average, a small duration peak's axis, large text on the axes~~ | — | **Resolved {{date:D19}}** |
| D20 | ~~A calendar switch rebuilds the tracker repository~~ | — | **Resolved {{date:D20}}** |
| D21 | ~~4b's test and guard gaps~~ | — | **Resolved {{date:D21}}** |
| D22 | ~~Tracker copy edge cases: tied boolean peaks, a stale "done" tap after midnight, English weekday names~~ | — | **Resolved {{date:D22}}** |
| D23 | ~~No app-level test that a tag edit stamps `transactions.updated_at`~~ | — | **Resolved {{date:D23}}** |
| D25 | ~~Phase 5's deferred review findings~~ | — | **Resolved {{date:D25}}** |
| D26 | ~~WidgetRenderer.build reads the pending taps outside its try~~ | — | **Resolved {{date:D26}}** |
| D27 | ~~A foreign in-flight requestPermissions would strand a queued Result~~ | — | **Resolved {{date:D27}}** |
| D28 | ~~Process-death recreation can replay a notification route~~ | — | **Resolved {{date:D28}}** |
| D29 | ~~A torn buffer append glues the next tap onto a partial line~~ | — | **Resolved {{date:D29}}** |
| D30 | ~~The headless FlutterEngine boots on the main thread~~ | — | **Resolved {{date:D30}}** |
| D31 | ~~Dialog polish~~ | — | **Resolved {{date:D31}}** |
| D32 | ~~Persian digits cannot be typed in the dialog on the A53~~ | — | **Closed 2026-10-14** (operator decision) |
| D33 | ~~Below Android 12 the fixed two rows may clip~~ | — | **Resolved {{today}}** |
| D34 | ~~A reminder time change while that day's reminder is due can double it~~ | — | **Closed 2026-10-14** (operator decision) |
| D35 | ~~Stale wording after F1~~ | — | **Resolved {{date:D35}}** |
| D36 | ~~The widget's midnight reset was not observed~~ | — | **Closed 2026-10-14** (operator decision) |
```

Variants, by outcome:
- **D16 not met:** keep the original open D16 row, `| D16 | Month-change rebuilds drop frames on a 120 Hz display | Nothing under the agreed 60 fps bar; smoothness on 120 Hz screens | Next analytics phase, or on demand |`, directly under `D10`, and drop the struck D16 row above.
- **D30 discarded:** `| D30 | ~~The headless FlutterEngine boots on the main thread~~ | — | **Closed {{today}}** (measured: no gain) |`.
- **D33 fixed by a commit:** `**Resolved {{date:D33}}**`.

- [ ] **Step 3: Each section**

For each item, apply the heading and status edit with the Edit tool.

**D12.** Before:

```markdown
## D12 — No global uncaught-error handler

**Status:** open. Found 2026-09-27 while documenting D10 and D11.
```

After:

```markdown
## D12 — No global uncaught-error handler — RESOLVED

**Status:** resolved {{date:D12}} by {{hash:D12}}. `installErrorHooks`
(`app/lib/bootstrap/error_hooks.dart`) sets `PlatformDispatcher.instance.onError`
to report into `FlutterError.reportError`, so an uncaught error reaches logcat
under its library: `nimbustats` from `main()`, `widget drain` from `drainMain`.
Nothing is persisted; crash reporting stays Phase 8's choice (operator decision
2026-10-14). Found 2026-09-27 while documenting D10 and D11; the original
finding follows.
```

**D16, if met.** Before:

```markdown
## D16 — Month-change rebuilds drop frames on a 120 Hz display

**Status:** open. Found 2026-10-04 during the Phase 3 performance pass (task 15)
on the A53.
```

After:

```markdown
## D16 — Month-change rebuilds drop frames on a 120 Hz display — RESOLVED

**Status:** resolved {{date:D16}} by {{hash:D16}}. `frame_timings.dart` takes
`--budget-ms`. A profile timeline of one Breakdown month step showed
{{measured:the cause, from findings.md}}, fixed by {{measured:the fixes applied}}.
Re-measured on the A53 at 120 Hz (`--budget-ms 8.33`, a warm-up and three
passes each): worst p99 build {{measured:dashboard worst p99 build}} ms on the
dashboard and {{measured:Breakdown worst p99 build}} ms on Breakdown, against
12.98 and 14.37 ms before. Found 2026-10-04 during the Phase 3 performance pass
(task 15) on the A53; the original finding follows.
```

**D16, if not met.** Keep the heading and replace the status:

```markdown
**Status:** open, re-measured {{today}} after {{hash:D16}}. At 120 Hz
(`--budget-ms 8.33`) the worst p99 build was {{measured:dashboard worst p99 build}} ms
on the dashboard and {{measured:Breakdown worst p99 build}} ms on Breakdown, over
the 8.33 ms bar. Operator decision {{today}}: {{measured:decision.md, verbatim}}.
Found 2026-10-04 during the Phase 3 performance pass (task 15) on the A53.
```

**D17.** Before:

```markdown
## D17 — Phase 1's haptics are silent on the A53

**Status:** open. Found 2026-10-05 during the Phase 4a device check.
```

After:

```markdown
## D17 — Phase 1's haptics are silent on the A53 — RESOLVED

**Status:** resolved {{date:D17}} by {{hash:D17}}: the expense save and the
category chips call `HapticFeedback.vibrate()`, as tracker taps do. Checked on
the A53: no "vibration absent" in logcat after a chip tap and a save, and
`dumpsys vibrator_manager` lists both as finished TOUCH vibrations from
`com.nimbustats.app`. Found 2026-10-05 during the Phase 4a device check; the
original finding follows.
```

**D18.** Before:

```markdown
## D18 — Tracker haptics are too faint to feel at the lowest touch strength

**Status:** open. Found 2026-10-05 during the Phase 4a device check.
```

After:

```markdown
## D18 — Tracker haptics are too faint to feel at the lowest touch strength — CLOSED

**Status:** closed 2026-10-14 by operator decision: the app follows the user's
touch-feedback setting, as every app does. Found 2026-10-05 during the Phase 4a
device check; the original finding follows.
```

**D19.** Before:

```markdown
## D19 — Tracker charts at the edges of their scale

**Status:** open. Found 2026-10-09 in Phase 4b, on the A53 and in the final
review.
```

After:

```markdown
## D19 — Tracker charts at the edges of their scale — RESOLVED

**Status:** resolved {{date:D19}} by {{hash:D19}}: a duration average under a
minute reads "<1 min" (`trackerInsightsUnderAMinute`), the value axis keeps its
top label when a step fits under the peak, and the axes' reserved sizes follow
the text scale. Found 2026-10-09 in Phase 4b, on the A53 and in the final
review; the original finding follows.
```

**D20.** Before:

```markdown
## D20 — A calendar switch rebuilds the tracker repository

**Status:** open. Found 2026-10-09 by the Phase 4b final review.
```

After:

```markdown
## D20 — A calendar switch rebuilds the tracker repository — RESOLVED

**Status:** resolved {{date:D20}} by {{hash:D20}}: `trackerRepositoryProvider`
reads the analytics engine instead of watching it, so a calendar switch keeps
the same repository (`totalOn` asks a calendar-free question). Found 2026-10-09
by the Phase 4b final review; the original finding follows.
```

**D21.** Before:

```markdown
## D21 — 4b's test and guard gaps

**Status:** open. Found 2026-10-09 by the Phase 4b final review. Re-scoped
```

After:

```markdown
## D21 — 4b's test and guard gaps — RESOLVED

**Status:** resolved {{date:D21}} by {{hash:D21}}: `TrackerQuerySpec.fromJson`
cases and a `toString` that includes `dateRange`; the architecture test's
aggregate pattern is a self-checked top-level regex; `FakeClock` takes an offset
rule; `trackerInsightsProvider` is a family keyed by tracker id. The original
status follows.

**Was:** open. Found 2026-10-09 by the Phase 4b final review. Re-scoped
```

**D22.** Before:

```markdown
## D22 — Tracker copy edge cases

**Status:** open. Found 2026-10-09 in Phase 4b.
```

After:

```markdown
## D22 — Tracker copy edge cases — RESOLVED

**Status:** resolved {{date:D22}} by {{hash:D22}}: a boolean's spoken summary
speaks its done caption, a stale "done" after midnight shows no snackbar, and
English spoken weekday summaries use full names (`weekdayLong`). Found
2026-10-09 in Phase 4b; the original finding follows.
```

**D23.** Before:

```markdown
## D23 — A tag edit's `updated_at` stamp is not pinned by a test

**Status:** open. Found 2026-10-11 in Phase 5 Task 8.
```

After:

```markdown
## D23 — A tag edit's `updated_at` stamp is not pinned by a test — RESOLVED

**Status:** resolved {{date:D23}} by {{hash:D23}}: `TransactionRepository.update`
writes the row and its tag links in one transaction
(`TransactionsDao.inTransaction`), pinned by a test that a tag edit moves
`updated_at` and one that a failing link write leaves amount, stamp and tags
unchanged. The `shortcut:` paragraph in `goal_period_results_dao.dart` is gone,
its guarantee now true. Found 2026-10-11 in Phase 5 Task 8; the original finding
follows.
```

**D25.** Before:

```markdown
## D25 — Phase 5's deferred review findings

**Status:** open. Collected 2026-10-12 from the Phase 5 task reviews and the
final review. None was judged worth fixing before the merge.
```

After:

```markdown
## D25 — Phase 5's deferred review findings — RESOLVED

**Status:** resolved {{date:D25}} by {{hash:D25}}, after the operator's triage
(2026-10-14): every bug fixed, every missing test added, and each style or scale
note closed with its reason (the table at the end of this entry). Fixed: #38, a
fractional habit target for a counter or boolean is invalid. Tests added: #5,
#10, #14, #17, #19, #20, #22, #23, #30, #31, #44, #46, #49, #51. Found in the
same triage and fixed: `MoneyFormatter.parse` returns null for a whole part too
large for minor units, instead of throwing inside the goal editor's `build`
(Toman) or wrapping silently (USD, EUR, TRY). Collected 2026-10-12 from the
Phase 5 task reviews and the final review; the original findings follow.
```

Then append the closures table at the end of D25's section. Write `$S/d25_closures.py` with the Write tool:

```python
"""Appends the D25 triage closures from the sweep spec to DEFERRED.md's D25 entry.

Run from the repo root: python -I <this file>
"""
import pathlib

deferred = pathlib.Path("docs/phases/DEFERRED.md")
spec = pathlib.Path("docs/superpowers/specs/2026-10-14-deferred-0-6-sweep-design.md")
table = spec.read_text(encoding="utf-8").splitlines()[196:234]
assert table[0].startswith("| # | Finding | Why closed |"), table[0]
assert table[-1].startswith("| 52 |"), table[-1]
anchor = "**Unblocked by:** on demand; each line names the file to start from.\n"
text = deferred.read_text(encoding="utf-8")
assert text.count(anchor) == 1, "D25's last line moved; find it by hand"
block = (
    anchor
    + "\n**Closed in the triage (operator, 2026-10-14).** The numbers follow the"
    + " triage's enumeration of the findings above; STALE means the finding was"
    + " already fixed or false.\n\n"
    + "\n".join(table)
    + "\n"
)
deferred.write_text(text.replace(anchor, block), encoding="utf-8", newline="\n")
print(f"appended {len(table) - 2} closures")
```

```bash
cd /c/Users/nimae/Desktop/nimbustats && python -I "$S/d25_closures.py"
```

Expected: `appended 36 closures`. The table runs from row 1 to row 52, skipping the fixed ones.

**D26.** Before:

```markdown
## D26 — WidgetRenderer.build reads the pending taps outside its try

**Status:** open. Found at the Phase 6 gate, 2026-10-13.
```

After:

```markdown
## D26 — WidgetRenderer.build reads the pending taps outside its try — RESOLVED

**Status:** resolved {{date:D26}} by {{hash:D26}}: the read is inside `build`'s
`try`, `onAppWidgetOptionsChanged` is guarded like `onUpdate`, and the channel's
and the receiver's render guards catch `Exception`. Checked on the A53 with a
directory in place of the buffer file: a re-render, a resize and an app start
each logged "widget render failed; showing the loading state", with no crash. A
device check replaced the JUnit test asked for below: `build` is Android glue,
and Robolectric was ruled out (operator decision 2026-10-14). Found at the
Phase 6 gate, 2026-10-13; the original finding follows.
```

**D27.** Before:

```markdown
## D27 — A foreign in-flight requestPermissions would strand a queued Result

**Status:** open. Found at the Phase 6 gate, 2026-10-13.
```

After:

```markdown
## D27 — A foreign in-flight requestPermissions would strand a queued Result — RESOLVED

**Status:** resolved {{date:D27}} by {{hash:D27}}: `MainActivity` queues the
`Result` before `requestPermissions` and asks only for the first, so a cancel
Android answers at once still reaches it, as false; a throw takes it back out
and reaches Dart as the channel's error. Verified by review: no second
permission caller exists to exercise it on a device. Found at the Phase 6 gate,
2026-10-13; the original finding follows.
```

**D28.** Before:

```markdown
## D28 — Process-death recreation can replay a notification route

**Status:** open. Found at the Phase 6 gate, 2026-10-13.
```

After, if the pre-fix APK replayed in Task 21 Step 3:

```markdown
## D28 — Process-death recreation can replay a notification route — RESOLVED

**Status:** resolved {{date:D28}} by {{hash:D28}}: `MainActivity.onCreate` drops
the route extra from an intent that comes with saved state, before
`configureFlutterEngine` reads it. Checked on the A53: a cold start on `/add`,
back to Home, `am kill`, then the launcher icon opened Home, where the build
before the fix reopened `/add`. Found at the Phase 6 gate, 2026-10-13; the
original finding follows.
```

If the pre-fix APK did not replay, the third sentence instead reads: "On the A53 the build before the fix did not replay either, so the fix is verified by review; the fixed build opened Home."

**D29.** Before:

```markdown
## D29 — A torn buffer append glues the next tap onto a partial line

**Status:** open. Found at the Phase 6 gate, 2026-10-13.
```

After:

```markdown
## D29 — A torn buffer append glues the next tap onto a partial line — RESOLVED

**Status:** resolved {{date:D29}} by {{hash:D29}}: an append to a file that does
not end in a newline writes one first, so only the torn line is rejected
(`WidgetBufferTest`). Found at the Phase 6 gate, 2026-10-13; the original
finding follows.
```

**D30, if kept.** Before:

```markdown
## D30 — The headless FlutterEngine boots on the main thread

**Status:** open. Found at the Phase 6 gate, 2026-10-13.
```

After:

```markdown
## D30 — The headless FlutterEngine boots on the main thread — RESOLVED

**Status:** resolved {{date:D30}} by {{hash:D30}}: the drain job waits for
Flutter's library load off the main thread (`ensureInitializationCompleteAsync`)
and builds the engine in its callback; VM and shell creation stay on the main
thread, as Flutter requires. Measured on the A53, five widget saves each with
the app killed: median skipped frames after Save {{measured:BEFORE_MEDIAN}}
before, {{measured:AFTER_MEDIAN}} after. Found at the Phase 6 gate, 2026-10-13;
the original finding follows.
```

**D30, if discarded.** The same before. After:

```markdown
## D30 — The headless FlutterEngine boots on the main thread — CLOSED

**Status:** closed {{today}} with its measurement. Moving the library-load wait
off the main thread (`ensureInitializationCompleteAsync`, the only part Flutter
lets leave it) was measured on the A53, five widget saves each with the app
killed: median skipped frames after Save {{measured:BEFORE_MEDIAN}} before and
{{measured:AFTER_MEDIAN}} after, short of the 30 % cut set to keep it, so the
change was not committed. Nothing of ours is on screen during the boot. Found at
the Phase 6 gate, 2026-10-13; the original finding follows.
```

**D31.** Before:

```markdown
## D31 — Dialog polish

**Status:** open. Found at the Phase 6 gate, 2026-10-13.
```

After:

```markdown
## D31 — Dialog polish — RESOLVED

**Status:** resolved {{date:D31}} by {{hash:D31}}: the chips sit in a
two-column grid with single-line, ellipsized names; Cancel and Save use the
accent, muted when disabled; the window background is the widget's rounded
shape. Checked on the A53 in English and Persian, light and dark, with four long
category names. Found at the Phase 6 gate, 2026-10-13; the original finding
follows.
```

**D32.** Before:

```markdown
## D32 — Persian digits cannot be typed in the dialog on the A53

**Status:** open. Found at the Phase 6 gate, 2026-10-13.
```

After:

```markdown
## D32 — Persian digits cannot be typed in the dialog on the A53 — CLOSED

**Status:** closed 2026-10-14 by operator decision: disregarded.
`AmountParserTest` and the dialog's key listener cover the Persian-digit path.
Found at the Phase 6 gate, 2026-10-13; the original finding follows.
```

**D33.** Before:

```markdown
## D33 — Below Android 12 the fixed two rows may clip

**Status:** open. Found at the Phase 6 gate, 2026-10-13.
```

After, if nothing clipped:

```markdown
## D33 — Below Android 12 the fixed two rows may clip — RESOLVED

**Status:** resolved {{today}}, with no code change. On an Android 11 emulator
(`system-images;android-30;default;x86_64`, AOSP launcher), the widget placed
at its default size ({{measured:span and height in dp}}) and at 4 × 2 showed
"+ Expense" and both rows uncut. Found at the Phase 6 gate, 2026-10-13; the
original finding follows.
```

After, if fixed:

```markdown
## D33 — Below Android 12 the fixed two rows may clip — RESOLVED

**Status:** resolved {{date:D33}} by {{hash:D33}}. On an Android 11 emulator
(AOSP launcher) the default placement ({{measured:span and height in dp}})
clipped the second row. Below Android 12 the rows now follow the widget's
reported height{{measured:", and the default asks 180 dp", if option (ii) was taken}};
re-checked at the default and smallest sizes. Found at the Phase 6 gate,
2026-10-13; the original finding follows.
```

**D34.** Before:

```markdown
## D34 — A reminder time change while that day's reminder is due can double it

**Status:** open. Found at the Phase 6 gate, 2026-10-13.
```

After:

```markdown
## D34 — A reminder time change while that day's reminder is due can double it — CLOSED

**Status:** closed 2026-10-14 by operator decision: the accepted cost of
`a2ece7a`, which stops a re-arm inside the delivery window from skipping the
day. Found at the Phase 6 gate, 2026-10-13; the original finding follows.
```

**D35.** Before:

```markdown
## D35 — Stale wording after F1

**Status:** open. Found at the Phase 6 gate, 2026-10-13.
```

After:

```markdown
## D35 — Stale wording after F1 — RESOLVED

**Status:** resolved {{date:D35}} by {{hash:D35}}: the comment in
`notification_prefs.dart` and the test name in `alert_router_test.dart` say the
lock screen follows the phone's setting. Found at the Phase 6 gate, 2026-10-13;
the original finding follows.
```

**D36.** Before:

```markdown
## D36 — The widget's midnight reset was not observed

**Status:** open. Found at the Phase 6 gate, 2026-10-13.
```

After:

```markdown
## D36 — The widget's midnight reset was not observed — CLOSED

**Status:** closed 2026-10-14 by operator decision: disregarded. The
`widget.MIDNIGHT` alarm is armed and re-armed (Phase 6 gate record); the reset
itself was not observed. Found at the Phase 6 gate, 2026-10-13; the original
finding follows.
```

Type each `{{measured:…}}` value in from the named record. Then fill the hashes and dates:

```bash
cd /c/Users/nimae/Desktop/nimbustats
missing=0
for d in D12 D16 D17 D19 D20 D21 D22 D23 D25 D26 D27 D28 D29 D30 D31 D33 D35; do
  grep -qE "\{\{(hash|date):$d\}\}" docs/phases/DEFERRED.md || continue
  hashes=$(git log --reverse --format='`%h`' --grep="^$d:" 4c23ed0..fix/deferred-0-6 | paste -sd, - | sed 's/,/, /g')
  day=$(git log -1 --format=%ad --date=short --grep="^$d:" 4c23ed0..fix/deferred-0-6)
  if [ -z "$hashes" ]; then echo "no commit body starts with $d:" >&2; missing=1; continue; fi
  sed -i "s/{{hash:$d}}/$hashes/g; s/{{date:$d}}/$day/g" docs/phases/DEFERRED.md
done
sed -i "s/{{today}}/$(date +%F)/g" docs/phases/DEFERRED.md
echo "missing=$missing"
```

For a `missing` item, find its commit with `git log --format='%h %ad %s' --date=short 4c23ed0..fix/deferred-0-6` and replace its tokens by hand.

- [ ] **Step 3b: Record the sweep's new findings**

Two defects were found while planning the sweep and are out of its scope (CLAUDE.md: bugs surfaced mid-rollout are deferred, not piled in). Add both to the top table, after D36's row:

```markdown
| D37 | The transaction detail's Save skips an unreadable amount without a word | Nothing hard-blocked; a typo in an edited amount is silently dropped | On demand |
| D38 | Adding a transaction writes its row, tag links and usage counts separately | Nothing today; a failed tag write leaves an untagged row | On demand, or whoever next touches `TransactionRepository` |
```

And add both sections after D36's section:

```markdown
## D37 — The transaction detail's Save skips an unreadable amount without a word

**Status:** open. Found 2026-10-14 while planning the deferred sweep.

**What:** `transaction_detail_screen.dart:174-184`: Save with an amount that
does not parse (or is zero) skips `setAmount`, still saves the note, and leaves
the typed text in the field. Nothing tells the user the amount was not saved.

**Why deferred:** Found while checking the money-parse fix's callers; out of the
sweep's scope. It never throws and loses no stored data.

**Unblocked by:** Validate the amount as the add screen does (`validate()` with
an inline error) and keep Save from closing on a bad amount; one widget test.

## D38 — Adding a transaction writes its row, tag links and usage counts separately

**Status:** open. Found 2026-10-14 while planning the D23 fix.

**What:** D23 made `TransactionRepository.update` write the row and its tag
links in one drift transaction. `add` still writes the row, then the links,
then the tag usage counts as separate statements, so a failing link write
leaves an untagged row behind.

**Why deferred:** The spec scoped D23 to `update`; `add`'s failure needs a tag
id that no picker offers.

**Unblocked by:** Run `add`'s writes inside `TransactionsDao.inTransaction`, as
`update` does; an atomicity test with an unknown tag id.
```

If the sweep itself surfaced another defect (for example Task 15c's 2× test coming up RED for a real overflow), record it the same way as D39 onward, with the task that found it.


- [ ] **Step 4: The status board and the links**

`docs/phases/README.md`, phase 4 row. Before:

```markdown
Carried forward: [D17](DEFERRED.md#d17--phase-1s-haptics-are-silent-on-the-a53), [D18](DEFERRED.md#d18--tracker-haptics-are-too-faint-to-feel-at-the-lowest-touch-strength), D19, D20, D21, D22 (see DEFERRED.md)
```

After:

```markdown
Its carried-forward items, D17–D22, were fixed in the 2026-10-14 deferred sweep, or closed by operator decision (D18); see [DEFERRED.md](DEFERRED.md)
```

Phase 5 row. Before:

```markdown
Carried forward: [D23](DEFERRED.md#d23--a-tag-edits-updated_at-stamp-is-not-pinned-by-a-test), [D25](DEFERRED.md#d25--phase-5s-deferred-review-findings)
```

After:

```markdown
Its carried-forward items, D23 and D25, were cleared in the 2026-10-14 deferred sweep; see [DEFERRED.md](DEFERRED.md)
```

Phase 6 row. Before:

```markdown
Carried forward: [D26](DEFERRED.md#d26--widgetrendererbuild-reads-the-pending-taps-outside-its-try)–[D36](DEFERRED.md#d36--the-widgets-midnight-reset-was-not-observed)
```

After:

```markdown
Its carried-forward items, D26–D36, were fixed in the 2026-10-14 deferred sweep, or closed by operator decision (D32, D34, D36); see [DEFERRED.md](DEFERRED.md)
```

If D30 was discarded, the parenthesis reads `(D32, D34, D36), or closed with its measurement (D30)`.

Phase 3 row, **only if D16 is resolved.** Before:

```markdown
Carried forward: [D10](DEFERRED.md#d10--no-saved-view-builder) (no view builder) and [D16](DEFERRED.md#d16--month-change-rebuilds-drop-frames-on-a-120-hz-display) (120 Hz frame drops on month changes)
```

After:

```markdown
Carried forward: [D10](DEFERRED.md#d10--no-saved-view-builder) (no view builder). [D16](DEFERRED.md#d16--month-change-rebuilds-drop-frames-on-a-120-hz-display--resolved) (120 Hz frame drops on month changes) was fixed in the 2026-10-14 deferred sweep
```

`docs/phases/phase-3-analytics.md` line 302, **only if D16 is resolved**: replace `DEFERRED.md#d16--month-change-rebuilds-drop-frames-on-a-120-hz-display)` with `DEFERRED.md#d16--month-change-rebuilds-drop-frames-on-a-120-hz-display--resolved)`.

Guards:

```bash
cd /c/Users/nimae/Desktop/nimbustats
grep -n '{{' docs/phases/DEFERRED.md
grep -rnoE "DEFERRED\.md#d(1[2-9]|2[0-9]|3[0-6])[a-z0-9_-]*" --include=*.md docs/phases
grep -cE "^## D(1[2-9]|2[0-9]|3[0-6]) .* — (RESOLVED|CLOSED)$" docs/phases/DEFERRED.md
```

Expected:
- The first grep prints nothing.
- The second prints at most `phase-3-analytics.md:302` and `README.md:46`, each with `--resolved`, or with the unchanged D16 anchor if D16 is still open.
- The count is 22, or 21 if D16 is still open: D12 and D16-D36 is 22 headings. D24 already ended in `— RESOLVED`, so it counts too.

- [ ] **Step 5: The full suites**

Run each in the foreground, one at a time. Check the last lines, not just the exit code.

| Where | Command | Expected |
|---|---|---|
| repo root | `flutter analyze` | `No issues found!` |
| repo root | `dart analyze --fatal-infos` | `No issues found!` |
| repo root | `dart test test/architecture_test.dart` | `All tests passed!` |
| `packages/nimbus_domain/` | `dart test` | `All tests passed!` |
| `packages/nimbus_data/` | `dart test` | `All tests passed!` |
| `packages/nimbus_design/` | `flutter test --no-pub` | `All tests passed!` |
| `app/` | `flutter test --no-pub --concurrency=4 --timeout 90s` | `All tests passed!` |
| `app/android/` | `./gradlew :app:testDebugUnitTest` | `BUILD SUCCESSFUL`, 33, or 35 with D33's test |

`nimbus_design` is a Flutter package, so it runs under `flutter test`, not `dart test`. Record the counts; the Phase 6 gate's were architecture 6, domain 417, data 337, app 681 and Kotlin 30.

- [ ] **Step 6: Commit the docs**

```bash
cd /c/Users/nimae/Desktop/nimbustats
git add docs/phases/DEFERRED.md docs/phases/README.md docs/phases/phase-3-analytics.md
git commit -m "$(cat <<'EOF'
docs: the phase 0-6 deferred backlog is cleared

Phase 7 starts on an empty backlog: every phase 0-6 item now leaves
DEFERRED.md fixed and verified, or closed by a recorded decision. D18,
D32, D34 and D36 close by operator decision (2026-10-14); D25's style
and scale notes close with the triage's reasons; the device-checked
items (D17, D26, D28, D31 on the A53, D33 on an Android 11 emulator)
carry what was seen, and D16 and D30 carry their measurements. The
status board's carried-forward lists shrink to what is still open (D10,
plus the operator-owned D2 and D4).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git log --oneline 4c23ed0..HEAD
```

If `phase-3-analytics.md` was not changed, drop it from `git add`. If D16 is still open, the last sentence of the body names D16 too.

- [ ] **Step 7: Fast-forward `main`, only after the operator confirms**

Show the operator:
- `git log --oneline main..fix/deferred-0-6`;
- the suite counts from Step 5;
- the device results.

Ask: "Fast-forward `main` to `fix/deferred-0-6`?" On a yes:

```bash
cd /c/Users/nimae/Desktop/nimbustats
git checkout main
git merge --ff-only fix/deferred-0-6
git log -1 --format='%h %s'
git status --short          # only the three stackdump files
```

Expected: `Fast-forward`, and `main` at the docs commit. Never force-push. If `--ff-only` refuses, `main` has moved: stop and ask the operator.

---
