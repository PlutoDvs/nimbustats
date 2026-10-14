# Deferred sweep, phases 0–6 — design

**Date:** 2026-10-14 · **Branch:** `fix/deferred-0-6` · **Source:** `docs/phases/DEFERRED.md`

## Goal

Clear every open DEFERRED item that belongs to phases 0–6, so Phase 7 starts on
an empty backlog. An item leaves DEFERRED.md by being fixed or by a recorded
operator decision — never by being forgotten.

## Out of scope

- **Phase 2B** (bank SMS): later, when the operator has the samples.
- **D2** (machine seeding) and **D4** (design token sheet): operator-owned.
- **D10** (saved-view builder): a feature. It follows this sweep as its own
  brainstorm → spec → plan cycle.

## Operator decisions (2026-10-14)

| Item | Decision |
|---|---|
| D18 | Close: the app follows the user's touch-feedback setting, as every app does. |
| D32 | Close: disregarded. |
| D34 | Close: the accepted cost of `a2ece7a`. |
| D36 | Close: disregarded. |
| D12 | Uncaught errors go to `FlutterError.reportError` (logcat) until Phase 8 picks crash reporting. Nothing persisted. |
| D25 | Triage: fix every bug, add every missing test, close style and scale notes with a recorded reason. |
| D16, D30 | Measured on the A53. |
| D33 | Checked on an Android 11 emulator (`system-images;android-30;default;x86_64` r11, SHA-1 verified, installed under `C:\dev\android-sdk`). |
| Kotlin verification | Device checks; no Robolectric (it would put `android.*` into JUnit and add a dependency). |
| D31 chips | A 2×2 grid. |

## Dart fixes

Each is one test-first commit.

**D12 — uncaught errors.** New `app/lib/bootstrap/error_hooks.dart`:
`installErrorHooks(String library)` sets `PlatformDispatcher.instance.onError` to
forward into `FlutterError.reportError` (the house channel, as
`outside_errors.dart`) and return `true`. Called after `ensureInitialized()` in
`main()` (`'nimbustats'`) and in `drainMain` (`'widget drain'`) — the drain job
boots its own engine, so its isolate needs its own hook. Test
`app/test/bootstrap/error_hooks_test.dart`: save and restore `onError` with
`addTearDown`, invoke the installed handler, expect `true` and one report with
the library and the same exception (capture as in `drain_service_test.dart:51-54`).

**D17 — Phase 1 haptics.** `add_transaction_screen.dart:85` `mediumImpact` and
`category_chips.dart:81` `selectionClick` become `HapticFeedback.vibrate()`. Test
first: `add_transaction_screen_test.dart` "save fires a haptic" maps a null
argument to `'vibrate'` and expects `['vibrate']` (fails today); a new chip test
taps a seeded chip without saving and expects `['vibrate']`.

**D19 — tracker charts at the edges.**
- Header (`tracker_insights.dart:96-101`): a duration average with
  `0 < average < 60 s` reads a new ARB key `trackerInsightsUnderAMinute`
  (en `<1 min`, fa `کمتر از یک دقیقه`). `TrackerFormat.duration` is unchanged —
  goals and alerts use it too.
- Axis (`tracker_bar_chart.dart:93-99`): the top label is suppressed only when a
  step fits under the max (`meta.max >= step`).
- Scale: `reservedSize` 44 and `_bottomTitlesSize` 28 go through
  `MediaQuery.textScalerOf(context).scale(...)`, including the interval maths at
  `:61`. Phase 3's identical constants (`patterns_body.dart`, `trends_body.dart`)
  are not in D19 and stay.
- Tests in `tracker_insights_test.dart`: a 4-minute Sleep month reads
  `0:04 in all · <1 min a day`; its axis labels are `['0:00', '0:04']`; at 2×
  text the reserved sizes are 88 and 56.

**D20 — calendar switch rebuilds the tracker repository.**
`tracker_providers.dart:14-18` reads `analyticsEngineProvider` instead of
watching it. `totalOn` is its only use and asks a calendar-free question (one
`DateKey`, no grouping); the comment says a period-grouping method would need
the watch back. Test in `tracker_providers_test.dart`: the repository is
`identical` across a Gregorian switch (fails today).

**D21 — 4b's test and guard gaps.**
- `TrackerQuerySpec.fromJson` cases (`nimbus_domain/test/trackers/tracker_query_spec_test.dart`):
  missing and non-object `groupBy` throw; missing `dateRange` reads as undated
  (the stored form — `toJson` omits it); non-object `dateRange` and a non-int end
  throw.
- `toString` includes `dateRange`; a test pins two specs differing only by range
  printing differently.
- Root `test/architecture_test.dart`: the aggregate regex is lifted to a
  top-level final with a self-check. It must match `countAll()`, `x.total()`,
  `'select sum(v) from t'`, `"... group by ..."`, and must not match
  `math.max(a, b)` or `format.total(t, 1)`.
- `FakeClock` (`tracker_fixture.dart`) gains an optional `rule` from UTC instant
  to offset for `toLocal`; `fromLocal` stays on the current offset with a
  `shortcut:` comment. A test in `tracker_repository_test.dart` starts a timer
  under one offset and stops it under another, and expects the start's offset.
- `trackerInsightsProvider` becomes `.autoDispose.family<…, String>` keyed by
  tracker id; `TrackerRangeBar` takes `trackerId`. A test pins two trackers'
  ranges as independent.

**D22 — tracker copy.**
- A boolean's spoken history summary speaks the done caption instead of a tied
  peak: new key `trackerInsightsDoneSummary` (`{name}, {period}: {caption}`).
- `tracker_logger.dart:61-71`: no snackbar when `clearToday` cleared nothing.
- English spoken weekday summaries use full names via one ICU `select` key
  `weekdayLong` (fa maps to its existing full names). Chart labels keep the
  short keys.
- Tests: the boolean summary label; a stale "done" after a day's rollover shows
  no "not done" snackbar and leaves the count; `most on Monday` replaces
  `most on Mon` at `tracker_insights_test.dart:510`.

**D23 — tag edit atomicity.** `TransactionsDao.inTransaction<T>(action)` wraps
`_db.transaction`; `TransactionRepository.update` runs the row write and
`_attachTags` inside it (`setTags`' own transaction becomes a savepoint). The
`shortcut:` paragraph at `goal_period_results_dao.dart:165-170` is deleted, as
its guarantee becomes true. Tests in `transaction_repository_test.dart`: a tag
edit moves an aged `updated_at`; an update with an unknown tag id (a
foreign-key violation) throws and leaves amount, stamp and tags unchanged
(fails today).

**Money parse overflow (found in the D25 triage).** `MoneyFormatter.parse`
(`money_format.dart:96`) `int.parse`s the whole part: a Toman amount above
`9223372036854775807` throws — inside the goal editor's `build`, which replaces
the form with an ErrorWidget — and a USD/EUR/TRY whole part above ~9.2e16 wraps
silently. Fix once there: `int.tryParse`, and return null when the major part
reaches `maxInt ~/ minorUnitsPerMajor`. Tests in `money_format_test.dart`
"rejects junk": `'9' * 20` and `'9223372036854775808'` for Toman and a 17-digit
USD amount parse to null.

**D25 — fixes and tests** (numbers refer to the triage table below).
- #38: a counter or boolean habit target with a fraction is `targetInvalid`
  (`goal_editor_controller.dart:203-206`); test in `goal_editor_screen_test.dart`.
- Tests: #5 `exceeds` and its tolerance; #10 `Goal` equality across all fields;
  #14 net savings across the 31-day seam with an expense next to it; #17 an
  unknown stored id and an empty range measure zero; #19 the TypeError →
  FormatException wrap; #20 the watermark's `tags` term; #22 `check` before a
  fixed range begins; #23 a goal deleted mid-measure; #30 the watcher recovering
  after a goals-stream error; #31 2× text on the problem, unreadable and paused
  cards; #44 a Persian detail semantics label; #46 keys plus loading and error
  tests for the detail's tracker branches; #49 the deleted-goal period fallback;
  #51 `muteReports` mutes only the test's own error.

**D35 — wording.** `notification_prefs.dart:27-28` and the test name at
`alert_router_test.dart:93-94` say the lock screen follows the phone's setting.

## Kotlin fixes

**D29 — torn append.** `WidgetBuffer.append`'s body moves to
`internal fun appendLine(target: File, line: String)`, which prefixes a newline
when a non-empty file does not end in one (`RandomAccessFile`, last byte). New
`WidgetBufferTest.kt` (JUnit4 + `TemporaryFolder`, no `android.*`): a torn tail,
a clean file and a missing file.

**D26 — unguarded render.** `WidgetRenderer.build`'s `try` moves above the
`synchronized` read; `onAppWidgetOptionsChanged` gets `onUpdate`'s guard; the
P22 catches in `OutsideChannelHandler.renderWidget` and
`WidgetActionReceiver` widen to `Exception`. Device check: a directory named
`files/widget_buffer.jsonl` (debug build, `run-as`), resize the widget, expect
"widget render failed" in logcat and no FATAL; remove the directory.

**D27 — stranded permission Result.** `MainActivity` adds the Result to the
queue before `requestPermissions`, and fires the request only when it is the
first; a throw removes it and rethrows. A synchronous cancel (another request
in flight) then answers it `false`. Verified by review; no second permission
caller exists to exercise it.

**D28 — route replay after process death.** `MainActivity.onCreate` removes
`EXTRA_ROUTE` from the intent when `savedInstanceState != null`, before
`super.onCreate` (where `configureFlutterEngine` reads it). Device check:
cold-start from a notification, Home, `am kill`, reopen from the launcher icon —
the route must not replay.

**D30 — engine boot on main.** `DrainJobService` starts the loader and builds
the engine in `ensureInitializationCompleteAsync`'s callback, guarding a job
that ended meanwhile. Only the library-load wait leaves the main thread; shell
and VM creation must stay there. Measured on the A53 before and after (skipped
frames after the dialog's Save, the loader's trace sections); kept only if it
measurably helps.

**D31 — dialog polish.** The chip row becomes a two-column `GridLayout`
(same id, weighted columns, single-line ellipsized chips). Cancel and Save take
`@color/entry_button_text` (accent, muted when disabled). Both `EntryDialogTheme`s
use `@drawable/widget_background` as the window background. Device check:
screenshots in en and fa, light and dark, with four long category names.

## Device work

On the A53, only when the operator says it is free:
- **D16:** add `--budget-ms` to `app/tool/frame_timings.dart`; take a profile
  timeline of one month step on Breakdown; fix what it shows; re-run
  `--scenario months` on the dashboard and Breakdown at 120 Hz. It holds when
  p99 build ≤ 8.33 ms in every pass.
- D17 (logcat shows no "vibration absent"), D26, D28, D30, D31 as above.

On the Android 11 emulator:
- **D33:** install the debug APK, place the widget in a default 4×2 cell, and
  screenshot it. If the fixed two rows clip, fix the layout and re-check.

## D25 triage — closures

Recorded in DEFERRED.md with these reasons. STALE means the finding is already
fixed or false.

| # | Finding | Why closed |
|---|---|---|
| 1 | `QuantityAmount` accepts NaN/∞ | Unreachable: the editor parses with `TrackerValues.parseAmount`, which rejects non-finite values. |
| 2 | `==`/`compareTo` disagree on -0.0 | Unreachable: no path produces -0.0. |
| 3 | `scaledBy` overflow lacks a `shortcut:` comment | Limit ~2.5e16 minor units over a year-long range; the comment is added. |
| 4 | `foldDaily` walks every day | Linear in the goal's age; a 10-year range is 3,650 steps. |
| 6 | Negative numerator untested | No caller passes one; the negative branch is covered via `rials(-10)`. |
| 7 | Crossing with a stale `lastAlerted` | Unreachable: every save drops the rows before re-baselining. |
| 8 | `reachedPercent` for negative net savings | Covered through `reaches`, pinned at `goal_values_test.dart:140`. |
| 9 | `engine.today()` untested | STALE: covered by `goal_engine_test.dart:57-68`. |
| 11 | Zero-target branch repeated | Style. |
| 12 | `.first` relies on sorted percents | STALE: enforced at `goal.dart:107-110` and documented. |
| 13 | Kind-free grep flags trailing comments | Fails safe, at authoring time only. |
| 15 | Net savings resolves paths twice | Two indexed lookups per call. |
| 16 | `_leafId` outside `MaterializedPath` | Style. |
| 18 | `GoalsDao` writes act on soft-deleted goals | No UI path holds a deleted goal; `restore` needs the unfiltered write. |
| 21 | `deleteForGoal`'s hard delete unpinned | STALE: pinned by `goal_service_test.dart:174-191`. |
| 24 | Stale `history(old)` after an edit | Only autoDispose providers keyed by the old goal, replaced on the next emission; nothing stale is written. |
| 25 | DAO comment reads as a guarantee | Folded into D23. |
| 26 | v32 migration defaults unasserted | STALE: `migrateAndValidate` checks column defaults. |
| 27 | Watcher keeps old subscriptions? | The code cancels; a kept one would only add a debounced duplicate trigger. |
| 28 | Evaluation at `stop()` still emits | Intended; the crossing write is idempotent. |
| 29 | Failed one-shot read drops flags | Delayed to the next trigger, not lost. |
| 32 | Card's `excludeSemantics` hides the bar's label | The card's sentence carries name, amounts and status. |
| 33 | `error_outline` on two states | Excluded from semantics; the words differ. |
| 34 | Pickers say "none yet" while loading | The lists are loaded before the form builds; only a failed local read shows it. |
| 35 | Tag picker has no error handling | A failed local read reaches the zone handler, now recorded (D12). |
| 37 | Editing an unreadable goal says "gone" | No UI path: the unreadable card cannot edit. |
| 39 | Unknown tag id is a zone error | An invariant guard: every id comes from the same reads. |
| 40 | Amount written twice; errors computed thrice | Trivial cost. |
| 41 | Editor test hygiene | Test style; swap for an `until` poll if one flakes. |
| 42 | "Gone" can flash during a delete | At most one frame; pop follows. |
| 43 | Deleting from the problem card leaves the gone screen | That screen explains and offers Undo and the way back. |
| 45 | "0 periods met in a row" | Accurate. |
| 47 | Fourth skeleton/Retry copy | Style. |
| 48 | Queued alert reads its period late | STALE: the text is built when the alert is raised. |
| 50 | `dart format` not in the gate | 166 of 249 lib files would change; a repo-wide reformat is its own decision. |
| 52 | Tap-target tests dispose inline | Leaks only in an already-failing test. |

## Process

- Branch `fix/deferred-0-6` from `main` (`4c23ed0`). One commit per item; tag
  `pre-<slug>` on the parent before each; red → green → broader suite.
- Suites: `flutter test --concurrency=4` in `app`; `dart test` in each package;
  the root architecture test; `gradlew testDebugUnitTest`.
- Fast-forward `main` after the device checks. A final docs commit moves each
  item to RESOLVED or CLOSED in DEFERRED.md and updates the status board.

## Done when

- Every item above is fixed and verified, or closed with its reason in
  DEFERRED.md.
- All suites green; `flutter analyze` clean.
- D16's 120 Hz bar is met, or its measured result is recorded with the
  operator's decision.
