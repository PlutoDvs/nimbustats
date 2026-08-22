# NimbuStats — Deferred items

Things that must happen but could not be done when they were found. Numbered so
a commit or a conversation can point at one. **Nothing here is optional** — an
item leaves this file by being fixed, not by being forgotten.

Each entry records what is blocked, why, how to check whether it is still
blocked, and who can unblock it.

| # | Item | Blocks | Owner |
|---|---|---|---|
| D1 | Android build unverified — Google Maven unreachable | Phase 1 Task 16, every APK build | Operator (network) |
| D2 | Gradle distribution needs manual seeding on a fresh machine | Any new dev machine or CI | Operator (network) |
| D3 | pub.dev archive access depends on the VPN exit node | Adding any new package, Phase 2 onward | Operator (network) |
| D4 | Claude Design token sheet does not exist | Nothing hard-blocked; visual polish | Operator (design) |
| D5 | Router error screen has no localized copy | Nothing; tidy-up | Phase 1 Task 15 |
| D6 | Flutter-specific lints are not active | Widget code quality from Task 6 on | Phase 1, before Task 6 |

---

## D1 — Android build unverified: Google Maven unreachable

**Status:** open. Found 2026-08-22 during Phase 1 Task 2.

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

**What stays unverifiable until then:** the four hardware UX acceptance
criteria in Phase 1 Task 16 — cold start under 1 s, 60 fps on 5,000 rows, any
expense in 5 s, and the three-tap path confirmed on a device. Phase 1 cannot be
tagged complete without them, because its own definition of done requires them
measured on hardware rather than on an emulator.

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

---

## D3 — pub.dev archive access depends on the VPN exit node

**Status:** open, currently working.

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

## D5 — Router error screen has no localized copy

**Status:** open, scheduled.

`app/lib/bootstrap/app_router.dart`'s `RouteNotFoundScreen` renders an icon and
nothing else. "No hardcoded UI text, ever" has no exception for screens users
are not supposed to reach, and no ARB keys existed when the router landed.

Phase 1 Task 15 adds the settings and onboarding strings; give this screen a
title and a "go home" action in the same commit.

---

## D6 — Flutter-specific lints are not active

**Status:** open. Should be resolved **before Phase 1 Task 6**, which is where
widget code starts in volume.

`flutter create` generated an `app/analysis_options.yaml` that would have
silently replaced the root config for the whole app package — dropping
`strict-casts`, `strict-inference`, `strict-raw-types`, and the `avoid_print` /
`empty_catches` / `unawaited_futures` **errors**. It was deleted so the root
config governs, which was the right call.

The side effect: `flutter_lints` is a declared dev dependency of `app` and
`nimbus_design` but nothing includes it, so Flutter-specific lints are inert.
The one that matters is **`use_build_context_synchronously`**, which catches
using a `BuildContext` across an `await` — a real crash source, and Tasks 6
through 15 are almost entirely async handlers that touch `context` afterwards.

Two ways out, and the choice should be deliberate:

1. Add the Flutter lint rules to the **root** `analysis_options.yaml`, keeping
   one config for the workspace. Root would then depend on `flutter_lints`
   resolving for non-Flutter packages, which needs checking.
2. Give `app/` and `packages/nimbus_design/` an `analysis_options.yaml` that
   includes `package:flutter_lints/flutter.yaml` **and** restates the root's
   strict analyzer settings. Costs duplication that can drift.

Whichever is chosen, the acceptance test is the same: a file using `context`
after an `await` must produce an analyzer error.
