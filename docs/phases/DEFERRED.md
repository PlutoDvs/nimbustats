# NimbuStats — Deferred items

Things that must happen but could not be done when they were found. Numbered so
a commit or a conversation can point at one. **Nothing here is optional** — an
item leaves this file by being fixed, not by being forgotten.

Each entry records what is blocked, why, how to check whether it is still
blocked, and who can unblock it.

| # | Item | Blocks | Owner |
|---|---|---|---|
| D1 | Phase 1 hardware criteria unmeasured — APK builds since 2026-09-26 | Phase 1 Task 16 gate, `phase-3-complete` | Operator (device) |
| D2 | Gradle distribution and large SDK packages need manual seeding on a fresh machine | Any new dev machine or CI | Operator (network) |
| D4 | Claude Design token sheet does not exist | Nothing hard-blocked; visual polish | Operator (design) |
| D8 | Payment-method tile is silently disabled when no method exists | Nothing hard-blocked; add-screen UX | Next phase touching the add screen |
| D3 | ~~pub.dev archive access depends on the VPN exit node~~ | — | **Resolved 2026-09-05** |
| D5 | ~~Router error screen has no localized copy~~ | — | **Resolved 2026-08-24** |
| D6 | ~~Flutter-specific lints are not active~~ | — | **Resolved 2026-08-22** |
| D7 | ~~`fl_chart` unavailable — Phase 3's charts and dashboard~~ | — | **Resolved 2026-09-05** |

---

## D1 — Android build unverified: Google Maven unreachable

**Status:** open. Found 2026-08-22 during Phase 1 Task 2.

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

## D8 — Payment-method tile is silently disabled when no method exists

**Status:** open. Found 2026-09-26 on the first real-device run (Galaxy A53),
reported as "payment method selection not working".

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
