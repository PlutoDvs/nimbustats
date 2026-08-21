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
| Android SDK | **not installed — blocked, see below** | intended: `C:\dev\android-sdk` |
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

The 403s carry Google's explicit body: *"We're sorry, but this service is not
available in your location."*

**`pub.dev` matters most** — every `flutter pub get` for the life of this
project goes through it. Commit `pubspec.lock` and keep the pub cache warm so a
flaky route never blocks a build.

**Never substitute a third-party Flutter or pub mirror to work around a block.**
That trades a VPN reconnect for trusting an unknown party with the toolchain and
every dependency in the app.

### The Android SDK repository is blocked separately

On the UK exit, `dl.google.com` serves normal traffic
(`/linux/linux_signing_key.pub` → 200) but **every** path under
`/android/repository/` returns an identical 1449-byte synthetic 404 — including
`repository2-3.xml`, `addon2-1.xml`, and the command-line tools zip linked from
Google's own download page. A stale filename does not explain manifest files
that certainly exist; the path is being blocked and dressed as a 404.

**Consequence:** the Android SDK cannot be installed on this route. A different
exit is required. This does **not** block most of Phase 0 — see below.

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

## `flutter doctor` state

```
[!] Flutter 3.47.1 — binary not on PATH in already-open shells (open a new terminal)
[✓] Windows Version (11 Pro 64-bit, 25H2)
[✗] Android toolchain — Unable to locate Android SDK   ← blocked, see above
[✓] Chrome
[✓] Visual Studio — Build Tools 2022 17.14.11
[✓] Connected device (3 available)
[✓] Network resources
```

The Chrome and Windows-desktop entries are irrelevant — this is an Android-only
project.
