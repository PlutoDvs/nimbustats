# NimbuStats — Deferred items

Things that must happen but could not be done when they were found. Numbered so
a commit or a conversation can point at one. **Nothing here is optional** — an
item leaves this file by being fixed, not by being forgotten.

Each entry records what is blocked, why, how to check whether it is still
blocked, and who can unblock it.

| # | Item | Blocks | Owner |
|---|---|---|---|
| D2 | Gradle distribution and large SDK packages need manual seeding on a fresh machine | Any new dev machine or CI | Operator (network) |
| D4 | Claude Design token sheet does not exist | Nothing hard-blocked; visual polish | Operator (design) |
| D10 | No saved-view builder: views can only be pinned from what a tab shows | "#travel by category" and other tag-scoped views cannot be pinned | Next analytics phase, or on demand |
| D12 | No global uncaught-error handler: a rethrown write failure reaches only the console | Nothing user-facing; failures are surfaced but not recorded | Phase 8 hardening, or sooner if a real failure needs a record |
| D16 | Month-change rebuilds drop frames on a 120 Hz display | Nothing under the agreed 60 fps bar; smoothness on 120 Hz screens | Next analytics phase, or on demand |
| D17 | Phase 1's haptics are silent on the A53 | The expense save's and category chips' haptic feedback on Samsung Android 15 | Phase 1 follow-up, on demand |
| D18 | Tracker haptics are too faint to feel at the lowest touch strength | Feeling a tracker tap on a phone set to the lowest touch feedback | Phase 6's Android work, or on demand |
| D13 | ~~The add-expense FAB carries no accessibility label~~ | — | **Resolved 2026-10-04** |
| D14 | ~~Pinning offers a name a card on the dashboard already uses~~ | — | **Resolved 2026-10-04** |
| D15 | ~~The starter card is named "This month by category" but follows the dashboard's month~~ | — | **Resolved 2026-10-04** |
| D11 | ~~Breakdown and cross-tab headers read "This month" for whichever month is shown~~ | — | **Resolved 2026-09-28** |
| D1 | ~~Phase 1 hardware criteria unmeasured~~ | — | **Resolved 2026-09-27** |
| D8 | ~~Payment-method tile is silently disabled when no method exists~~ | — | **Resolved 2026-09-27** |
| D9 | ~~"Saved" snackbar covers the add button~~ | — | **Resolved 2026-09-27** |
| D3 | ~~pub.dev archive access depends on the VPN exit node~~ | — | **Resolved 2026-09-05** |
| D5 | ~~Router error screen has no localized copy~~ | — | **Resolved 2026-08-24** |
| D6 | ~~Flutter-specific lints are not active~~ | — | **Resolved 2026-08-22** |
| D7 | ~~`fl_chart` unavailable — Phase 3's charts and dashboard~~ | — | **Resolved 2026-09-05** |

---

## D1 — Android build unverified: Google Maven unreachable — RESOLVED

**Status:** resolved 2026-09-27. Found 2026-08-22 during Phase 1 Task 2.

All four hardware criteria were measured on a **Samsung Galaxy A53 5G**
(SM-A536E), a mid-range phone, running a **profile** build against a
database of 5,000+ transactions seeded by the demo tile. The display
supports 60 and 120 Hz and ran at 60 Hz throughout.

| Criterion | Result | How |
|---|---|---|
| Repeat purchase in ≤ 3 taps | **3** — +, a suggested chip, Save | Operator on the device; the saved rows confirm it |
| Any expense in ≤ 5 s | **2 s** from opening the form to the saved row | `occurred_at` (form opened) vs `created_at` (row written) on the device |
| Cold start < 1 s | **558 ms** median to first frame (runs 2–6: 568, 547, 557, 567, 466 ms); run 1, first after install, 723 ms | `flutter run --profile --trace-startup`, 6 runs |
| List holds 60 fps | **0 of 5,126** frames over 16.67 ms in 3 measured passes; p99 build ≤ 3.41 ms, raster ≤ 4.06 ms; worst 8.37 ms | `app/tool/frame_timings.dart`, 20 + 20 swipes per pass |

- **Warm-up pass, reported rather than dropped:** it contained the first
  page loads after launch — 2 of 958 frames over budget, worst 25.2 ms, still
  99.8 % within budget.
- **Cold-start caveat:** measured to the first rasterized frame, as the brief
  specifies. The startup trace ends shortly after that frame. In the three
  runs that captured later frames, drawing had settled by 504–629 ms, but the
  trace does not show which frame first had rows in it.

**The device run found bugs no widget test could**, each fixed with a
failing test first:

- `782f198` a fresh install never reached onboarding, so nothing was seeded
  and every save failed its foreign key;
- `dd61c57` a dollar amount could not be typed a key at a time (`5` became
  `5.00` under the caret);
- `d440768` the keypad covered Save, so three taps took four;
- `b74636c` each new expense inherited the last one's draft, including its
  amount and timestamp;
- `df9ce7a` a new expense did not appear on the list until restart;
- and alongside them `8312e9f` (seed language), `b6a16a6` (reset erased the
  founding-user stamp), `7f0cc56` (demo data silent).

The method is in `docs/DEVELOPMENT.md`, *Measuring on a device*.

**Tagged 2026-09-27** — the operator delegated the call. `main` was
fast-forwarded to `phase/3-analytics-ui`, of which it was an ancestor, so the
fixes above arrived without a merge commit or duplicated commits, together with
Phase 3 tasks 9–12 (done and green, as the Phase 3 engine was before them).
`phase-1-complete` marks that commit: the build measured on the device, plus
this record. Cherry-picking the fixes onto the old `main` instead would have
tagged a combination no device ever ran.

The history below is kept as it was written.

**Re-checked 2026-09-26 — the build half is closed; the device half is not.**
`flutter build apk --debug` succeeded on exit `64.49.12.178`, producing
`app/build/app/outputs/flutter-apk/app-debug.apk` (165 MB: `com.nimbustats.app`
0.1.0, target SDK 36, arm64-v8a / armeabi-v7a / x86_64, debug-signed — checked
with `aapt2 dump badging` and `apksigner verify`). It took four fixes, each
found by the build failing one step further on:

1. An exit that reaches Google on *every* connection. A VPN configuration that
   rotated exits per connection failed Gradle at random — see
   `docs/DEVELOPMENT.md`.
2. `platforms;android-36`, via `sdkmanager`.
3. NDK `28.2.13676358` and `build-tools;36.0.0`, which AGP installs itself and
   the tunnel truncated. Seeded by hand and hash-verified — see **D2**.
4. The Flutter engine jars on `storage.googleapis.com`, geo-blocked (403 *"not
   available in your location"*) whenever the VPN was not routing the shell.

**What remains is the reason this item exists:** the four hardware UX
criteria below, measured on a physical device. `platform-tools` (adb 37.0.1)
is installed for that. Measure a **profile** build — a debug build's JIT makes
cold-start and frame timings meaningless.

**Re-checked 2026-08-29** at the end of the Phase 3 engine work. Still open,
and note that a bare `curl` against
`https://maven.google.com/androidx/core/core/1.13.1/core-1.13.1.pom` is **not**
a valid probe for this: it returns 404, meaning the host answered and the path
is simply wrong (that repository serves artifacts under
`dl.google.com/dl/android/maven2/...`). A 404 there is evidence of nothing.
Only a real Gradle resolution closes this item.

**Re-checked 2026-09-05** on a new exit node — the one that cleared D3 and D7.
pub.dev went to 200; Google did not move. Confirmed by the real Gradle
resolution, which failed with the identical error recorded below.

That run also produced a *sound* curl probe, which the 2026-08-29 note above
correctly said the old one was not. Ask for a Google-hosted path that
unquestionably exists and compare the response size:

```bash
curl -sL -o /dev/null -w "%{http_code} %{size_download}B\n" \
  https://dl.google.com/android/repository/repository2-1.xml
```

On 2026-09-05 this returned `404 1449B` — and so did
`dl.google.com/dl/android/maven2/androidx/core/core/1.13.1/core-1.13.1.pom` and
`maven.google.com/androidx/core/core/1.13.1/core-1.13.1.pom`. Three different
Google paths, two of which certainly exist, all answering with the same
1,449-byte generic Google error page, while `services.gradle.org` returned 200
and 2 MB from the same node. Identical sizes across paths that should differ is
interception; it is not three coincidental 404s.

`200` means the interception is gone. Still run the Gradle build to close the
item — the probe can only tell you when it is worth trying.

Gradle runs, then fails to resolve the Android Gradle Plugin:

```
Plugin [id: 'com.android.application', version: '9.1.0'] was not found
  could not resolve plugin artifact
  'com.android.application:com.android.application.gradle.plugin:9.1.0'
```

**The AGP version is correct** — Flutter 3.47.1 pins it itself
(`templateAndroidGradlePluginVersion = '9.1.0'` in
`packages/flutter_tools/lib/src/android/gradle_utils.dart`). This is not a
template bug and must not be "fixed" by pinning an older AGP.

**Root cause:** Google Maven is unreachable from the VPN exit node in use.
`androidx.core:core:1.13.1` — an artifact that unquestionably exists — returns a
1449-byte generic Google error page from both `dl.google.com` and
`maven.google.com`. That is interception, not a 404. `google()` is the only
repository that serves AGP, so nothing resolves.

Consistently, it is *Google-hosted* endpoints that fail while everything else
works: `github.com`, `repo1.maven.org`, and `services.gradle.org` all return
200 from the same node.

**Check whether it is still blocked:**

```bash
curl -sL -o /dev/null -w "%{http_code}\n" \
  https://maven.google.com/androidx/core/core/1.13.1/core-1.13.1.pom
```

`200` means fixed. `404` with a ~1449-byte body means still intercepted.

**Unblock:** an exit node that can reach Google Maven — usually a different
country or provider. Then:

```bash
cd app && flutter build apk --debug
```

**Rechecked 2026-08-24:** still 404. Phase 1's code is complete and green
(342 tests) but its gate tag is withheld on this alone.

**What stays unverifiable until then:** the four hardware UX acceptance
criteria in Phase 1 Task 16 — cold start under 1 s, 60 fps on 5,000 rows, any
expense in 5 s, and the three-tap path confirmed on a device. Phase 1 cannot be
tagged complete without them, because its own definition of done requires them
measured on hardware rather than on an emulator.

**Consequence accepted 2026-08-29 — the Phase 3 prerequisite is waived.**
Phase 3's brief requires `phase-1-complete` before starting. That tag is
withheld on this item alone, and the four criteria it is waiting for are
*hardware performance measurements*: none of them affects whether an analytics
engine compiles and passes tests against Phase 1's DAOs and value types, which
are merged on `main` and green.

Waiving it is therefore narrow and deliberate, not a shortcut:

- It covers **Phase 3's engine only** — `QuerySpec`, `PeriodBoundaries`, the
  SQL compiler, and schema v20. Phase 3's own charts are separately blocked by
  **D7**, so no UI is being built on an unverified foundation either way.
- It does **not** waive Phase 3's own gate. `phase-3-complete` is withheld
  until `phase-1-complete` exists, because a Phase 3 acceptance run measures
  chart performance on the same hardware.
- If a hardware criterion later fails and forces a Phase 1 change, the risk is
  contained: the engine depends on Phase 1's *query surface*, not its screens,
  and a frame-rate or cold-start fix does not change a DAO signature.

Anything beyond the engine still waits for the tag.

---

## D2 — Gradle distribution needs manual seeding on a fresh machine

**Status:** worked around locally on 2026-08-22. Will recur elsewhere.

The Gradle wrapper's own downloader truncated `gradle-9.3.1-all.zip` twice over
the tunnel — 89 MB, then 144 MB of 224 MB — and failed with a `ZipFile` init
error that names nothing useful.

Seeded manually, with the checksum verified against Gradle's published value:

```bash
D=~/.gradle/wrapper/dists/gradle-9.3.1-all/9ot9r568e8zfvvd4mn8rbu1j0
rm -f "$D"/*.zip "$D"/*.lck "$D"/*.ok
curl -L --retry 30 --retry-all-errors --retry-delay 5 -C - \
  -o "$D/gradle-9.3.1-all.zip" \
  https://services.gradle.org/distributions/gradle-9.3.1-all.zip
sha256sum "$D/gradle-9.3.1-all.zip"
# must equal 17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43
```

The hash directory name is derived from the `distributionUrl`; reuse whatever
directory already exists rather than inventing one.

Any new development machine or CI runner on this network hits the same wall.
Worth a note in `docs/DEVELOPMENT.md` when D1 is resolved and the Android
toolchain is proven end to end.

**Update 2026-09-26:** the toolchain is proven end to end and the note exists
— `docs/DEVELOPMENT.md`, *Installing SDK components over the tunnel*. The same
truncation hit the NDK (748 MB) and build-tools (59 MB), so this item now
covers large SDK packages as well as the Gradle distribution.

---

## D3 — pub.dev archive access depends on the VPN exit node — RESOLVED

**Status:** resolved 2026-09-05 by an operator exit-node change. Both
`https://pub.dev/api/packages/fl_chart` and
`https://pub.dev/api/archives/crypto-3.0.6.tar.gz` returned **200** with real
bodies (90,863 B and 612,122 B), where on 2026-08-29 both returned 403.

**Re-checked 2026-09-25:** it had closed again — 403 on the first probe that
day — and reopened on the next exit (`64.49.12.178`: archive 200, 612,122 B, on
8 of 8 fresh connections). Still a property of the exit, not a fix.

**The window was treated as temporary, because it has closed before.** This
item is resolved by an exit node, not by a fix, so the same node change that
opened it can close it again. Everything foreseeably needed was pulled while it
held:

- `fl_chart 1.2.0` added to `app/pubspec.yaml` — the one third-party package
  the spec names. Resolves **D7**.
- `cryptography 2.9.0`, `pointycastle 4.0.0`, `file_picker 12.2.0` and
  `share_plus 13.3.0` downloaded to the **local pub cache only**, via
  `dart pub cache add`. No pubspec references them and no stack decision has
  been made — they are Phase 7 candidates (AEAD + KDF, and the export/restore
  file flow), cached so that Phase 7's kickoff can choose between them offline
  rather than needing this node back.

If a later phase needs a package that is not already cached, expect to need a
tolerated exit node again. Check first, and pull everything in one window.

**Kept for whoever hits this again**, since the failure mode is confusing:

On a Hetzner exit (`91.107.187.87`), pub.dev's CDN rate-limited the IP:
metadata resolved fine, tarballs returned 403 after a handful of requests. The
symptom is confusing because it is partial — `path` and `logging` downloaded
while `crypto`, `equatable`, and every `go_router` at or above 16 did not.

`dart pub add` reports this as `Package not available (authorization failed)`,
which does not point at the cause.

Everything in `pubspec.lock` is cached, so **builds and tests work offline**.
Only *adding* a package needs a tolerated exit node. Phase 2 will want more
packages, so expect to revisit this.

**Check:**

```bash
curl -sL -o /dev/null -w "%{http_code}\n" \
  https://pub.dev/api/archives/crypto-3.0.6.tar.gz
```

**Note for whoever hits this:** if a mirror is ever used, pub.dev publishes the
expected hash at `https://pub.dev/api/packages/<name>/versions/<version>`
(`archive_sha256`). Verify the downloaded bytes against it. A mirror whose
tarball matches pub.dev's own published hash carries no supply-chain risk; one
that is merely trusted does.

---

## D4 — Claude Design token sheet does not exist

**Status:** open by decision, not by accident.

`packages/nimbus_design/lib/src/{tokens,colors,typography}.dart` are marked
`PROVISIONAL` and were derived from the screen contract's constraints rather
than from a design token sheet. Every screen references tokens rather than
literals, so substituting a real sheet is an edit to two files.

`packages/nimbus_design/test/theme_test.dart` asserts WCAG AA contrast for
every semantic colour against its surface, plus a luminance gap between expense
and income. **A replacement palette that fails those assertions fails the
build**, which is the safety net that makes shipping provisional colours
reasonable.

One thing a real sheet should fix: no font is bundled, so Persian renders
through the platform fallback stack named in `typography.dart`. Bundling
Vazirmatn is the obvious upgrade.

---

## D5 — Router error screen has no localized copy — RESOLVED

**Status:** resolved 2026-08-24, in Phase 1 Task 15.

`RouteNotFoundScreen` rendered an icon and nothing else, because no ARB keys
existed when the router landed and "no hardcoded UI text, ever" has no
exception for screens users are not supposed to reach.

It now uses `NimbusEmptyState` with `routeNotFoundTitle`, `routeNotFoundBody`,
and a `routeNotFoundGoHome` action that navigates to the transaction list. A
dead end with no exit is worse than the wrong screen, so the action matters as
much as the copy.

---

## D6 — Flutter-specific lints are not active — RESOLVED

**Status:** resolved 2026-08-22, before Phase 1 Task 6.

`flutter create` generated an `app/analysis_options.yaml` that would have
silently replaced the root config for the whole app package — dropping
`strict-casts`, `strict-inference`, `strict-raw-types`, and the `avoid_print` /
`empty_catches` / `unawaited_futures` severities. Deleting it was right, but it
left `flutter_lints` declared and unused, so Flutter's own lints were inert.

**Fix.** `app/` and `packages/nimbus_design/` each carry an
`analysis_options.yaml` that includes *both* rule sets. The analyzer supports a
list of includes and later entries win, so the workspace root comes last and
stays authoritative:

```yaml
include:
  - package:flutter_lints/flutter.yaml
  - ../analysis_options.yaml
```

No duplicated settings, so nothing can drift.

**A second hole was found while verifying the first.** `unawaited_futures` was
listed under `analyzer: errors:` at the root but was never *enabled* under
`linter: rules:` — and it ships in neither `lints/recommended` nor
`flutter_lints`. A severity override for a disabled rule does nothing, so the
project had believed since Phase 0 that it errored on fire-and-forget futures
and it never had. It is now requested by name at the root.

That one mattered more than the lint it was found alongside: a dropped future
in this codebase loses a database write *and* the error explaining it.

**Verified by probe, not by assumption.** A scratch file violating all four
rules was analyzed before and after. Before: `No issues found`. After: four
diagnostics — `strict-casts`, `unawaited_futures`, `avoid_print` as errors, and
`use_build_context_synchronously` as an info. The probe was deleted; if these
ever need re-checking, recreate it rather than trusting this note.

Two details worth keeping:

- `use_build_context_synchronously` reports at `info` severity, which is not a
  weakness here: the definition-of-done gate runs `dart analyze --fatal-infos`,
  so an info already fails the build.
- `unawaited_futures` only fires inside `async` bodies. A fire-and-forget call
  from a synchronous function is still invisible to it.

---

## D7 — `fl_chart` unavailable: Phase 3 cannot draw — RESOLVED

**Status:** resolved 2026-09-05, when **D3** cleared. `fl_chart 1.2.0` is now a
dependency of `app/` (it brings `equatable 2.1.0` transitively). The lockfile
change was purely additive — 17 insertions, no deletions, no existing package's
version moved — and `dart analyze --fatal-infos` stayed clean.

Found 2026-08-29 at Phase 3 kickoff: the spec's stack decision names `fl_chart`
for charts, and it was in neither `pubspec.lock` nor the local pub cache while
pub.dev returned 403 for archives *and* metadata.

**What this unblocks:** Phase 3 tasks 9–14 — the breakdown screen, trends,
period comparison, the tag × category cross-tab, patterns, the necessity ×
satisfaction matrix, saved-view UI, and the dashboard.

**Note that these are unblocked for development but not for their gate.**
Charts render and assert on the host through widget and golden tests, which
need no APK. Phase 3's *acceptance* run measures chart performance on hardware,
so `phase-3-complete` still waits on **D1** — as it already did.

**It never blocked tasks 1–8**, the whole engine, which shipped on 2026-08-29
while this was open — `QuerySpec`, `PeriodBoundaries`, the SQL compiler,
group-by dimensions, the tag double-count and rollup correctness tests,
`EXPLAIN QUERY PLAN` assertions, and schema v20 `saved_views`. None of it draws
anything.

Building that half first turned out to be right on its own merits rather than
only as a way around the network: the brief's two silent-correctness traps —
tag double-counting and nested-tag rollup — live in the engine, and the charts
now have a proven-correct thing to render.

**Note for whoever picks the UI up:** the engine returns `trueTotal` alongside
its buckets precisely so a tag chart can disclose that its slices do not sum to
the total. Wiring a pie chart without that disclosure is the bug the trap list
is warning about, not a polish item.

---

## D8 — Payment-method tile is silently disabled when no method exists — RESOLVED

**Status:** resolved 2026-09-27. Found 2026-09-26 on the first real-device run
(Galaxy A53), reported as "payment method selection not working".

**Resolution — the operator's choice of the two options below:** first run
creates Cash and Card, named in the install's language (`e29d92c`), and the
picker ends with a small "+ New payment method" until the user has a method
of their own; it creates the method and puts it on the expense being entered
(`db157c6`). The tile is never disabled any more. Verified on the A53 after
clearing the app's data: Cash and Card present from the first launch, and "+"
created a method that landed on that expense.

The original report is kept below.

The add screen's payment-method tile sets `onTap: methods.isEmpty ? null : …`
(`app/lib/features/transactions/presentation/add_transaction_screen.dart:241`).
Nothing seeds payment methods — first run seeds categories only, by design —
so on every new install the tile is inert until the user has created one under
**Settings → Payment methods**. It looks exactly like a broken control: no
hint, no route to the manager, no feedback on tap.

The same run surfaced the missing first-run gate, which made the category
pickers look broken the same way; that was fixed on `fix/onboarding-gate`.
This one was deferred instead because it does not block verification — adding
one method in settings makes the tile work — and the right fix is a UX
decision rather than a bug fix:

- keep the tile enabled when empty and offer "Add a payment method", opening
  the manager and returning with the new method selected; or
- seed a small default set (e.g. cash, card) at first run, localized like the
  category tree.

**Check:** fresh install → onboarding → add screen → "More details" →
tap the payment-method tile. Resolved when that tap does something useful.

---

## D9 — "Saved" snackbar covers the add button — RESOLVED

**Status:** resolved 2026-09-27 (`383890c`). Found the same day while writing
the test for `b74636c`, then confirmed on the A53 by the operator.

**Cause and fix:** the list's Scaffold owned the add button, but the list sits
inside the app shell's Scaffold, and snackbars are shown by the outermost one.
A Scaffold only lifts its own FAB clear of its own snackbar. The button moved
to the shell, on Home only; verified on the device, it now rises above
"Saved".

The original report is kept below.

In a widget test (an 800 × 600 view), tapping the list's + within the "Saved"
snackbar's four seconds did not reach the button — Flutter reported the tap
*"would not hit test on the specified widget"*. If the same happens on a
phone, a second expense logged right after the first costs a wait or a
missed tap. It has **not** been seen on the device: in the one back-to-back
capture there, the second add was opened after the snackbar had gone.

**Check:** on the phone, save an expense and tap + within four seconds. If the
tap does not open the add screen, the FAB and the snackbar are on different
Scaffolds (the list's and the shell's), so the FAB is not lifted above it.

---

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

## D11 — Breakdown and cross-tab headers read "This month" for any month — RESOLVED

**Status:** resolved 2026-09-28. Found 2026-09-27 while planning the
full-screen saved view; widened 2026-09-27 to cover the cross-tab body, which
has the identical bug.

`BreakdownBody` (`breakdown_body.dart:59`) and `CrossTabBody`
(`cross_tab_body.dart:61`) both label their total with `txMonthTotal` ("This
month") whatever the period. The Breakdown tab's own ◀ ▶ can show a past
month under that label directly. The Cross-tab tab has no period control of
its own — it always shows the current month — but the full-screen saved view
has one `MonthBar` shared across chart types, and inherits the label from
whichever body it draws; a cross-tab-pinned view opened full screen on a past
month is wrong the same way a breakdown-pinned one is.

**Fixed.** The caption now reads "This month" only while the range shown *is*
the month containing today, and names the period otherwise (`1405/06`, or
`1405/05 – 1405/07` for a window) — `totalCaption` in
`app/lib/features/analytics/application/period_label.dart`. A neutral "Total"
was the other candidate and was rejected: the cross-tab tab has no period
control, so its caption is the only thing on that screen saying which month
the grid covers. Both bodies now share one `TotalHeader`
(`presentation/widgets/total_header.dart`) instead of holding a copy each.

## D12 — No global uncaught-error handler

**Status:** open. Found 2026-09-27 while documenting D10 and D11.

`reportingFailure` (`app/lib/features/analytics/presentation/widgets/saved_view_write.dart`)
matches the add-expense screen's older pattern: on a failed write it shows
"Could not save the change" and rethrows, so the caller sees the failure too.
But the rethrown error reaches only the console — `app/lib/main.dart` calls
`runApp` directly, and nothing in `app/lib` installs
`PlatformDispatcher.instance.onError` or `runZonedGuarded`, so no uncaught
error anywhere in the app is ever recorded. Nothing user-facing is blocked by
this; failures are surfaced but not recorded. Fix: wrap `runApp` in
`runZonedGuarded` (or set `PlatformDispatcher.instance.onError`) and route
both to whatever Phase 8 chooses for crash reporting.

---

## D13 — The add-expense FAB carries no accessibility label — RESOLVED

**Status:** resolved 2026-10-04 (`ea1b3f3`), and confirmed on the A53 the same
day. Found 2026-09-29 during the Phase 3 device check on the A53.

`app/lib/bootstrap/app_shell.dart:53` builds the shell's FAB as
`FloatingActionButton(key: Key('tx-add-fab'), onPressed: …, child: Icon(Icons.add))`
— no `tooltip`, no `Semantics` wrapper. On the device the accessibility tree
reports it as `android.widget.Button` with `NAF="true"` and an empty
`content-desc`, so TalkBack announces the app's primary action as "Button".
Every other control read on that run does carry a name: the three nav
destinations, the month arrows ("Previous month" / "Next month"), "Pin to
dashboard", "Card options", the breadcrumb, the tag checkboxes.

Nothing is blocked and sighted use is unaffected — this is the one unnamed
control found, and it happens to be the one that starts the app's main task.

**Fix:** give the FAB a `tooltip` (a new string in both ARBs, keys kept
alphabetical). A tooltip is the idiomatic route and doubles as the long-press
hint. **Check:** a widget test asserting the label, and on device
`uiautomator dump` on Home showing a non-empty `content-desc` for the FAB.

**Not in scope:** the amount field also reports `NAF="true"`, but it *is*
labelled — `amount_field.dart:96` passes `InputDecoration(labelText: label)`,
which reaches TalkBack as the field's hint rather than a `content-desc`. The
flag is a uiautomator artifact there, not a defect.

**Fixed.** The FAB now carries `tooltip: l10n.addExpense`. That reuses the
existing "Add expense" / "افزودن هزینه" key, already the title of the screen the
button opens, rather than adding a new one. A widget test in
`app_shell_navigation_test.dart` asserts the button's semantics node carries
the name. **Checked on the device 2026-10-04**, during the performance pass. A
`uiautomator dump` on Home names the FAB "Add expense", and it is clickable,
the same way the month arrows were named on 2026-09-29.

## D14 — Pinning offers a name a card on the dashboard already uses — RESOLVED

**Status:** resolved 2026-10-04 (`ea5555e`). Found 2026-09-29 during the same device check.

Pinning the Trends tab pre-filled the name sheet with "Last 6 months", which
the starter trend card already carries, and saving produced two cards titled
identically (`saved_views.sort_order` 1 and 3, distinct ids). Nothing breaks:
each card resolves, renames and reorders on its own id. But the dashboard is a
list of questions read by their titles, and two that read the same cannot be
told apart — including in the remove-with-undo snackbar, which names the card.

**Widened 2026-10-04 by the D15 fix.** The breakdown starter is now named
"Spending by category", which is also the name pinning the Breakdown tab at its
top level suggests. So both starters can now collide with a hand-pinned card.
The operator chose this over a starter-only name, so that one fix here covers
both cards.

**Fix (decide first):** either pre-fill a distinguishing name when the default
is taken, or say in the sheet that the name is already used and let the operator
choose. Renaming after the fact already works, so this is a first-run nicety
rather than a repair. **Check:** pin the same chart twice; the second sheet does
not offer a name already on the dashboard.

**Fixed: warn, don't block** (the operator's choice over a numbered name or a
disabled Save). While the typed name matches another card's, the name sheet
shows "A card on the dashboard already has this name" under the field. Names
are compared trimmed and case-insensitively. Save stays enabled, since pinning
the same chart twice can be deliberate. The line is a live region, so TalkBack
announces it. Rename uses the same sheet and leaves out the card being renamed,
from both the dashboard menu and the full-screen view. The names are read once
from `pinnedViewsProvider` via `dashboardNames`: if the list hasn't loaded,
there is no warning, rather than a blocked pin. **The check therefore becomes:**
pinning the Breakdown tab over the starters shows the warning and still saves.
Five widget tests cover it, and mutation runs confirmed that dropping
`exceptId` and an always-on warning each fail a test. **Checked on the
device 2026-10-04**, during the performance pass. Pinning Breakdown over the
starters showed the warning under "Spending by category" with Save enabled, and
saving produced the second card. Pinning Trends did the same for "Last 6
months". The operator confirmed the Persian string ("کارتی با همین نام در
داشبورد هست") on 2026-10-04.

## D15 — The starter card's name says "this month" whatever month it shows — RESOLVED

**Status:** resolved 2026-10-04 (`f358176`). Found 2026-09-29 during the Phase 3 device check, one screen
after [D11](#d11--breakdown-and-cross-tab-headers-read-this-month-for-any-month--resolved)
was fixed.

"Add starter cards" names its breakdown card with `starterThisMonthByCategory`
— "This month by category" (`app_en.arb:184`, `app_fa.arb:149`). The dashboard's
month bar moves every card together, so with the dashboard on 2026/08 that card
is titled "This month by category" above an August total. The caption under the
title is right since `472c62c`; the title is not.

The app already has the words for it: the same question pinned by hand from the
Breakdown tab is named `pinNameSpendingByCategory` — "Spending by category",
which is true at any anchor. The starter is the only place using the dated
phrasing. The trend starter is fine, since `pinNameLastMonths(6)` ("Last 6
months") describes a window relative to whatever month is shown.

Nothing is blocked: card names are user-editable and rename works (verified on
the device). It is a first-run impression — the first ◀ a new user presses shows
them a card whose title contradicts its own subtitle.

**Fix:** name the starter with the neutral string (reuse
`pinNameSpendingByCategory`, or add a starter-specific neutral one) and drop
`starterThisMonthByCategory` if nothing else uses it. Existing installs keep the
names already stored — a rename migration is not worth it for two cards a user
can rename. **Test surface that moves with it:** `starter_views.dart`, three
assertions in `dashboard_tab_test.dart` (one of them the Persian name) and one
in `saved_view_screen_test.dart`.

**Fixed.** The breakdown starter now takes `pinNameSpendingByCategory`, and
`starterThisMonthByCategory` has been removed from both ARBs. A new test moves
the dashboard back a month and checks the card's name still reads "Spending by
category". The operator chose reuse over a starter-only string, accepting the
name clash recorded under
[D14](#d14--pinning-offers-a-name-a-card-on-the-dashboard-already-uses--resolved).
Existing installs keep their stored name.

## D16 — Month-change rebuilds drop frames on a 120 Hz display

**Status:** open. Found 2026-10-04 during the Phase 3 performance pass (task 15)
on the A53.

**What was measured.** The pass was judged against the agreed bar, which is
Phase 1's 60 fps budget of 16.67 ms per frame, and every pass met it. But the
A53 ran at **120 Hz** throughout:
- its display is in adaptive mode (`refresh_rate_mode=2`);
- `dumpsys display` reported `mActiveRenderFrameRate=120`.

At 120 Hz a frame has 8.33 ms. These measured p99 build times exceed that:
- **12.3–13.0 ms** stepping months on the dashboard;
- **13.6–14.4 ms** stepping months on Breakdown;
- **8.51 ms** in one tabs pass.

These are dropped frames on this screen during the rebuild that follows a
month change.
- **Scrolling's build** stays well inside 8.33 ms, at a p99 of 3.4–3.7 ms.
- **Raster** brushes the limit in places: one scroll pass reached a p99 of
  10.34 ms and one tabs pass 10.09 ms. Every other pass stayed at 9.8 ms or
  under.
- **Queries are not the cause.** Start delay stayed under 2 ms at p99, and the
  slowest query was 26 ms.

The cost is building the new chart and list.

**Blocks:** nothing under the agreed bar. The operator chose to pass task 15
on it and track this separately.

**Fix (investigate first):**
- Take a profile-build DevTools timeline of one month step on Breakdown to see
  which widgets rebuild, and how often, when the result arrives.
- Candidates to confirm or rule out:
  - whole-list rebuilds where only the values changed;
  - a chart rebuilding twice, once for loading and once for data;
  - layout passes that a `RepaintBoundary` or a const subtree would avoid.

**Check:** add a `--budget-ms` option to `app/tool/frame_timings.dart`. Today
its budget is fixed at 16.67 ms, which is why this doesn't show as over budget.
Then re-run `--scenario months` on the dashboard and on Breakdown with the
display at 120 Hz. The fix holds when p99 build is ≤ 8.33 ms in every pass.

## D17 — Phase 1's haptics are silent on the A53

**Status:** open. Found 2026-10-05 during the Phase 4a device check.

**What happens.** The A53 runs Android 15. On it, Android drops every Flutter
haptic except `HapticFeedback.vibrate()`, logging "performHapticFeedback;
vibration absent for constant N". Probed with `cmd vibrator_manager feedback`:

| Constant | Flutter call | Result |
|---|---|---|
| 0 `LONG_PRESS` | `vibrate` | **plays** |
| 1 `VIRTUAL_KEY` | `lightImpact` | dropped |
| 3 `KEYBOARD_TAP` | `mediumImpact` | dropped |
| 4 `CLOCK_TICK` | `selectionClick` | dropped |
| 6 `CONTEXT_CLICK` | `heavyImpact` | dropped |
| 16 `CONFIRM` | none | dropped |

Phase 4a moved tracker taps to `vibrate()`. Phase 1 still uses
`mediumImpact` when an expense is saved (`add_transaction_screen.dart`) and
`selectionClick` on the category chips (`category_chips.dart`), so those are
almost certainly silent on this phone. Their widget tests pass, because they
check the request, not what the phone does with it.

**Blocks:** haptic confirmation on capture (screen contract §1.3), on this
phone and, presumably, others like it.

**Check:** run `adb logcat -c`, save an expense, then
`adb logcat -d | grep "vibration absent"`. The fix holds when nothing prints
and `dumpsys vibrator_manager` shows a finished TOUCH effect from
`com.nimbustats.app`. The fix is to use `vibrate()`, as trackers do.

## D18 — Tracker haptics are too faint to feel at the lowest touch strength

**Status:** open. Found 2026-10-05 during the Phase 4a device check.

**What happens.** After the D17 finding, tracker taps use
`HapticFeedback.vibrate()`. Android plays each one and logs it as a finished
45 ms TOUCH effect from `com.nimbustats.app`, the same feedback other apps'
taps produce. The operator's A53 has touch feedback at its lowest step
(`VIB_FEEDBACK_MAGNITUDE=1`, shown as `TOUCH = LOW`), and its motor has no
amplitude control. At that setting the operator could not feel the taps,
whether normal or forced. A full-strength 300 ms vibration was felt clearly.
The operator tried raising the setting, but it still read 1 afterwards, and
a later tap was not felt. Perceptibility at a higher setting is unverified.

**Blocks:** a tracker tap felt on a phone set to the lowest touch feedback.
For a one-tap counter, the haptic is the main confirmation; the total and the
snackbar still change.

**Options:**
- Leave it. The app follows the user's touch-feedback preference, as every
  app does.
- A native Android vibration (`VibrationEffect`): longer, or under a usage
  the touch setting does not scale. That would override the user's
  preference, so it is a design decision, not a fix.

**Check:** set Settings → Sounds and vibration → Vibration intensity → Touch
interaction above the lowest step, confirm `adb shell settings get system
VIB_FEEDBACK_MAGNITUDE` reads above 1, then tap a tracker and ask whether it
was felt.
