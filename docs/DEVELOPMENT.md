# Development Environment

Verified state of the development machine. Everything here was **observed**, not
assumed — commands and their real output, on 2026-08-21.

## Toolchain

| Component | Version | Location |
|---|---|---|
| Flutter | 3.47.1 (stable, revision `6655482ec0`, 2026-08-19) | `C:\dev\flutter` |
| Dart | 3.13.1 | bundled with Flutter |
| DevTools | 2.60.0 | bundled with Flutter |
| JDK | 17.0.2 (`17.0.2+8-LTS-86`) | `C:\Program Files\Java\jdk-17.0.2` |
| Visual Studio Build Tools | 2022, 17.14.11 | (pre-existing) |
| Android SDK | platform 36, build-tools 36.0.0, NDK 28.2.13676358, CMake 3.22.1, platform-tools 37.0.1, cmdline-tools 22.0 — installed 2026-09-26, see below | `C:\dev\android-sdk` |
| OS | Windows 11 Pro 25H2 (10.0.26200.9168) | |

### Environment variables (User scope)

```
Path     += C:\dev\flutter\bin
JAVA_HOME = C:\Program Files\Java\jdk-17.0.2
```

`JAVA_HOME` is set explicitly rather than derived from `(Get-Command java).Source`.
On this machine `java` resolves through Oracle's shim at
`C:\Program Files\Common Files\Oracle\Java\javapath`, whose parent is **not** a
JDK. A JRE 8 (`jre1.8.0_481`) is also installed, so any lookup must filter on
the presence of `bin\javac.exe`.

## Resolving SDK download URLs

**Do not hardcode SDK download URLs in scripts or docs.** Verified today:

- The Android command-line tools filename carries a build number that changes
  every release. The value in an earlier draft of the Phase 0 plan
  (`11076708`) returned a hard 404; the current one is `15859902`. Read it from
  <https://developer.android.com/studio> instead.
- The Flutter archive URL should come from
  `https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json`
  (`base_url` + the `releases[]` entry whose `hash` matches
  `current_release.stable`). Confirmed to report 3.47.1 / Dart 3.13.1.

## Network: Google endpoints are geo-sensitive

This is the single biggest environmental risk to the project and it has already
cost time twice.

Endpoint reachability depends entirely on the active VPN exit:

| Exit | `pub.dev` | Flutter archive | `developer.android.com` | `dl.google.com/android/repository/` |
|---|---|---|---|---|
| `31.171.100.118` (AZ) | 403 | 403 | 403 | 404 |
| UK exit | 200 | 200 | 200 | **404** |
| `64.49.12.178` (2026-09-26) | 200 | 200 (`download.flutter.io` engine jars) | not tested | 200 |
| `5.237.x.x` — VPN not routing this shell | not tested | 403 | not tested | 404 (1449 B) |

**Check which exit this shell is actually using** before blaming a host:
`curl -s https://api.ipify.org`. The VPN client has a system-proxy mode
(WinINET `127.0.0.1:12334`) that Git Bash `curl` and Gradle/Java ignore, so a
browser can be on the VPN while the build goes out directly. Use the client's
whole-system (TUN) mode for builds.

One VPN configuration handed each **connection** a different exit, some of
them blocked. Requests sharing a connection all succeeded or all failed
together, so Gradle — hundreds of requests, treating a 404 as "does not
exist" without retrying — failed at random. Probe with several fresh
connections and require every one to pass before starting a build.

The 403s carry Google's explicit body: *"We're sorry, but this service is not
available in your location."*

**`pub.dev` matters most** — every `flutter pub get` for the life of this
project goes through it. Commit `pubspec.lock` and keep the pub cache warm so a
flaky route never blocks a build.

**Never substitute a third-party Flutter or pub mirror to work around a block.**
That trades a VPN reconnect for trusting an unknown party with the toolchain and
every dependency in the app.

**The one exception is a mirror whose bytes are verified against the
upstream's own published hash, fetched from the upstream itself.** The mirror
is then only a faster pipe and is trusted with nothing. Size alone is not
verification. This is how the NDK and build-tools were installed — see below.

### The Android SDK repository is blocked separately

On the UK exit, `dl.google.com` serves normal traffic
(`/linux/linux_signing_key.pub` → 200) but **every** path under
`/android/repository/` returns an identical 1449-byte synthetic 404 — including
`repository2-3.xml`, `addon2-1.xml`, and the command-line tools zip linked from
Google's own download page. A stale filename does not explain manifest files
that certainly exist; the path is being blocked and dressed as a 404.

**Consequence:** the Android SDK cannot be installed on this route. A different
exit is required. This does **not** block most of Phase 0 — see below.

### Installing SDK components over the tunnel (proven 2026-09-26)

On a good exit the Gradle plugins, AndroidX and the Flutter engine jars
resolve normally, and small SDK packages (platform 36, CMake, platform-tools)
install through `sdkmanager`, which checks their checksums itself. The two
large ones did not: AGP's automatic install of the NDK (748 MB) and
build-tools (59 MB) was truncated by the tunnel and failed with *"Error
reading Zip content from a SeekableByteChannel"*. `sdkmanager` cannot resume.

What worked, for any package too large to survive the tunnel:

1. Read the Windows archive's `<size>`, `<checksum type="sha1">` and `<url>`
   for the exact package path (e.g. `ndk;28.2.13676358`) from
   `https://dl.google.com/android/repository/repository2-3.xml`.
2. Download that filename in parallel byte ranges. Google gave ~20 KiB/s per
   connection; `https://mirrors.cloud.tencent.com/AndroidSDK/<filename>` gave
   ~240 KiB/s, and 6 ranges ~500 KiB/s. Append a range only when the reply is
   `206`.
3. Accept the file only if **both** size and SHA-1 equal step 1's values.
4. Remove any half-installed `<pkg>/<version>/` the failed attempt left (it
   holds only an `.installer` marker), extract, and rename the archive's single
   top folder (`android-ndk-r28c`, `android-16`) to the version directory.
   Confirm `source.properties` shows the expected `Pkg.Revision`.

**Do not combine `curl --retry` with `-C -`.** On retry curl truncates the
file back to its size when that invocation started, so resume only works
across separate invocations — retry in a shell loop. This silently discarded
196 MB once.

Components installed this way have no `package.xml`, so `sdkmanager` does not
list them. AGP finds them by directory and `source.properties`; the APK build
confirmed it.

## What works without the Android SDK

The Android SDK is only needed to build an APK or run on a device. It is **not**
needed for:

- `dart analyze`, `dart test` — the whole `nimbus_domain` and `nimbus_data`
  layers, which are pure Dart by design
- `flutter test` — widget tests run on the host
- `dart run build_runner build` — drift code generation

Phase 0 is therefore executable to completion except for on-device
verification. Phase 1 needs the Android SDK for real-device UX measurement.

## Verified: native SQLite on the host

`sqlite3_flutter_libs` is `0.6.0+eol`. Phase 0 planning flagged as an open
question whether drift's replacement mechanism actually works here. **Resolved —
it does.**

A throwaway probe (`dart create -t package sqlite_probe`, `dart pub add drift
sqlite3 dev:test`) resolved `drift 2.34.3` and `sqlite3 3.5.2`, pulling in
`hooks 2.2.0`, `code_assets 2.0.0`, and `native_toolchain_c 0.19.4`. A test
opening `NativeDatabase.memory()`, creating a table, inserting, and selecting:

```
Running build hooks...
00:00 +1: All tests passed!
```

**`native_toolchain_c` compiles SQLite from source via build hooks**, which is
why Visual Studio Build Tools 2022 is a genuine prerequisite on this machine —
not an optional `flutter doctor` nicety. A machine without a C toolchain will
fail host tests in the data layer.

## Measuring on a device (proven 2026-09-27; analytics 2026-10-04)

The hardware criteria (Phase 1's, and Phase 3's performance pass) are
measured on a physical phone, on a
**profile** build — a debug build's JIT makes the timings meaningless — and
never on an emulator.

- **Screen on and unlocked for the whole run.** A locked phone renders no
  frames: startup tracing then waits forever, and the frame tool records
  nothing and exits with an error. Check `adb shell dumpsys power` for
  `mWakefulness=Awake` and `adb shell dumpsys window` for
  `isKeyguardShowing=false` before each run.
- `adb` is `C:\dev\android-sdk\platform-tools\adb.exe` and is not on PATH.
- **Record the refresh rate.** Run
  `adb shell dumpsys display | grep mActiveRenderFrameRate`.
  - The A53's display is adaptive (60/120 Hz).
  - Phase 1's run recorded 60 Hz. Phase 3's pass ran at 120 Hz.
  - The frame tool's budget is fixed at 16.67 ms (60 fps). At 120 Hz a frame
    has 8.33 ms; see D16.
- Build the profile APK once (`flutter build apk --profile`) and reuse it
  with `--use-application-binary`, which skips Gradle — about 10 s a run.
  Debug and profile builds share the debug signing key, so
  `adb install -r` swaps between them and keeps the app's data.
- 5,000+ rows come from **Settings → Seed 5,000 demo transactions**, which
  exists in debug builds only. The rows survive installing the profile
  build over it.
  - Since 2026-10-04 the rows are shaped like real use (`DemoDataSeeder`):
    two years of history, 2–3 tags per row, unevenly used categories,
    ratings, payment methods and a few unconfirmed captures.
  - The data is the same on every run.
  - Seeding takes about 40 s on the A53.
- **Replacing the data on the phone.** The A53 is the operator's daily
  phone, so confirm with them first. In Git Bash, prefix these with
  `MSYS_NO_PATHCONV=1`.
  1. With a debug build installed, back up:
     `adb exec-out run-as com.nimbustats.app cat app_flutter/nimbustats.sqlite > ~/nimbustats-backups/NAME.sqlite`.
  2. Check that its `sha256sum` matches
     `adb shell run-as com.nimbustats.app sha256sum app_flutter/nimbustats.sqlite`.
  3. Then reset with `adb shell pm clear com.nimbustats.app`.

  The database is a single file (no `-wal` or `-shm`). Steps 1–3 were done on
  2026-10-04. Restoring has not been exercised yet. The route would be: with
  a debug build installed, `adb push` the backup to `/data/local/tmp/`, then
  `run-as … cp` it into `app_flutter/`.

**Cold start** — six runs; report run 1 (first after install) separately
and the median of the other five:

```
flutter run --profile --trace-startup -d SERIAL \
  --use-application-binary build/app/outputs/flutter-apk/app-profile.apk
```

Each run writes `build/start_up_info.json`; the number is
`timeToFirstFrameRasterizedMicros`.

**List frame timings** — the app open on the list:

1. `flutter run --profile -d SERIAL --use-application-binary …` and leave it
   running; from a script, keep its stdin open (`sleep 3000 | flutter run …`)
   or it exits. Copy the "Dart VM service is listening on" address.
2. From `app/`:
   ```
   dart run tool/frame_timings.dart --vm-service ADDRESS --serial SERIAL \
     --adb C:/dev/android-sdk/platform-tools/adb.exe --out pass-1.json
   ```
3. One warm-up pass (`--swipes 10`, reported, not judged), then three
   measured passes of 20 + 20 swipes. The bar: p99 of build and raster
   ≤ 16.67 ms in every pass.

**Analytics timings.** This is Phase 3's performance pass. Run it in an English
UI: the tool finds the month buttons by their English names. In another
language, pass `--previous-label` and `--next-label`. Add `--scenario`:

- `scroll --swipes 10` on a dashboard of 8 cards.
- `months --swipes 10` on the dashboard, and again on Breakdown. It taps
  "Previous month" ×10, then "Next month" ×10. It finds both buttons in a
  `uiautomator dump` taken before recording starts.
- `tabs --swipes 4` from the dashboard: Dashboard to Patterns and back. It
  swipes along `--swipe-y`, which defaults to 30 % of the screen height.
  Mid-screen, the cross-tab's grid takes the swipe.

Use the same rhythm: a warm-up, then three passes. The tool also reports:
- the **start delay**: frames begun late because the UI isolate was busy;
- the app's **query timings**.

The bar is:
- p99 build, raster and start delay ≤ 16.67 ms in every pass;
- every query ≤ 100 ms.

`months` and `tabs` fail outright when no query timings arrive. That means a
release build, or the wrong screen.

The tool reads the `Flutter.Frame` event the framework posts for every frame
in debug and profile builds — the same `FrameTiming` data as DevTools — and
the `Nimbus.Query` event the app posts for every analytics query, in the same
builds.

## `flutter doctor` state

```
[✓] Flutter (stable, 3.47.1)                       ← re-run 2026-09-26
[✓] Windows Version (11 Pro 64-bit, 25H2)
[!] Android toolchain (Android SDK version 36.0.0)
    ! Some Android licenses not accepted — operator's call; not needed to build
[✓] Chrome
[✓] Visual Studio — Build Tools 2022 17.14.11
[✓] Connected device (3 available)
[✓] Network resources
```

The Chrome and Windows-desktop entries are irrelevant — this is an Android-only
project.
