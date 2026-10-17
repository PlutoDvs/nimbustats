# Phase 7 — Backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Losing the phone must not mean losing the data. Android Auto Backup is made correct for a WAL database, and a passphrase-encrypted export file can be saved anywhere and restored from.

**Architecture:**
- **`nimbus_data/lib/src/backup/` treats the database as one file.**
  - An export is `VACUUM INTO` a temp snapshot, then gzip and AES-256-GCM, under keys from Argon2id and HKDF.
  - A restore decrypts to a temp file and migrates it through `AppDatabase.openAtPath`. It then swaps the content in with SQLite's online backup API, in one write transaction.
- **The app adds a Settings section with two bottom sheets** (export and restore), and a small Kotlin channel for Save, Share and Open.
- **A root `AppRestart` rebuilds every provider after a restore.**
- **A custom `BackupAgent` checkpoints the WAL before Auto Backup copies the files.**

**Tech Stack:**
- Flutter 3.47.1 / Dart 3.13.1, drift 2.34.3, sqlite3 3.5.2 and Riverpod 3.
- `cryptography 2.9.0`, pure Dart, the phase's one new dependency.
- Kotlin on framework APIs, plus `androidx.core`'s `FileProvider`, which is already on the compile classpath.

**Spec:** `docs/superpowers/specs/2026-10-17-backup-7-design.md`. It is the binding authority, and this plan argues from it. Where the code forced a change, the change is a numbered ruling below. Read §2 (the file format) before any `nimbus_data` task, and §5–§6 before any app task.

---

## Global Constraints

Every task's requirements include this section.

**Toolchain and dependencies**
- **Flutter 3.47.1 / Dart 3.13.1.** No SDK bump.
- **Exactly one new pub dependency:** `cryptography: ^2.9.0` in `packages/nimbus_data/pubspec.yaml` (Task 2).
  - Every package it depends on (`collection`, `crypto`, `ffi`, `meta`, `typed_data`) is already in the root `pubspec.lock`.
  - Resolve with `flutter pub get --offline` from the repo root.
  - `app` never imports `package:cryptography` directly.
- **No Gradle dependency is added.** `androidx.core:core:1.13.1` reaches `debugCompileClasspath` through the Flutter embedding (verified 2026-10-17), and it provides `FileProvider`.
- **Schema: none.** `schemaVersion` stays 40, and the registry row for v60–v69 stays "—". No table, DAO, query or migration is touched.

**The file format (spec §2): exact values**
- **Header:** 76 bytes, big-endian, laid out as follows.

  | Offset | Size | Field |
  |---|---|---|
  | 0 | 8 | magic `NIMBUSBK` (ASCII) |
  | 8 | 2 | format version `1` |
  | 10 | 4 | schema version (the payload's `user_version`) |
  | 14 | 8 | created-at, UTC epoch ms |
  | 22 | 1 | KDF id `1` = Argon2id |
  | 23 | 4 | memory, KiB |
  | 27 | 4 | iterations |
  | 31 | 1 | parallelism |
  | 32 | 16 | salt |
  | 48 | 12 | nonce |
  | 60 | 16 | key-check value |

  Then come the ciphertext and a 16-byte GCM tag. Header bytes 0–75 are the AAD.
- **Payload:** `gzip(VACUUM INTO snapshot)`.
- **Keys:**
  - `master = Argon2id(normalised UTF-8 passphrase, salt)`, 32 bytes.
  - `enc = HKDF-SHA256(master, info "nimbus-backup v1 enc")`, 32 bytes.
  - `check = HKDF-SHA256(master, info "nimbus-backup v1 check")`, 16 bytes.
- **Production KDF:** `KdfParams(memoryKiB: 65536, iterations: 3, parallelism: 1)` until the A53 measurement (Task 14).
- **File name:** `nimbustats-YYYYMMDD-HHmm.nimbus`, in ASCII digits, Gregorian, local time.

**Paths**
- The live database is `app_flutter/nimbustats.sqlite`.
- The undo copy is `app_flutter/nimbustats.pre-restore.sqlite`. It is written first as `….pre-restore.sqlite.part` (ruling R4).
- The last export's time is in `app_flutter/backup_state.json`: `{"v":1,"lastExportUtcMs":<int>}`.
- Temp files live in `<getTemporaryDirectory()>/backup/`:
  - `export-<uuid>.sqlite`
  - `import-<uuid>.sqlite`
  - `picked-<uuid>.nimbus`
- Finished exports go in `<cache>/backup/out/`. Only the latest is kept, and it is the only folder `FileProvider` serves.

**Channel:** `com.nimbustats.app/backup`. Its methods are exactly:
- `saveDocument({path})` → `bool`
- `shareFile({path})` → `null`
- `openDocument()` → `String?`

(ruling R5)

**Secrets**
- The passphrase, `master`, `enc`, `check` and anything derived from them never appear in a log, a `print`, an exception message, a `toString` or an error report, at any level.
- Test passphrases are literals in test files only.

**Strings and errors**
- **ARB:** new keys are prefixed `backup…` and inserted in alphabetical position in both `app_en.arb` and `app_fa.arb`. `app_fa.arb` carries no `@` metadata. The operator reviews every Persian value before the gate.
- **No dialogs:**
  - `app/test/ux_rules_test.dart` forbids `showDialog(`, `AlertDialog(` and `CupertinoAlertDialog(` in `app/lib`.
  - Every backup step is a modal bottom sheet (ruling R2).
  - No raw `Color(` in `app/lib`. Use theme colours.
- **No silent failures:**
  - Dart reports an unexpected error through `FlutterError.reportError` with `library: 'backup'`.
  - An expected `BackupException` is shown to the user and not reported.
  - Native code logs `Log.e(TAG, …)` with `TAG` from `OutsideChannelHandler`.
  - No `print`, and no swallowed exception.

**Tests and commits**
- **No host test is possible for the Android glue** (`NimbusBackupAgent`, `BackupDocuments`, `MainActivity`). Each such task:
  - compiles it with `flutter build apk --debug`;
  - pins the XML and manifest wiring with a text test;
  - says in its commit message "verified on device in Task 14".
- **TDD order per commit:**
  1. Write the failing test, run it and see RED.
  2. Tag the parent `pre-<slug>`.
  3. Implement, run the test and see GREEN.
  4. Run the broader suite.
  5. Commit, with a message explaining why.
  6. Fast-forward into `phase/7-backup`.
- **Commit trailer:** every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage any `bash.exe.stackdump`.

**Suite commands**

| Suite | Command |
|---|---|
| App | from `app/`: `flutter test --no-pub --concurrency=4 --timeout 90s` |
| Data | from `packages/nimbus_data/`: `dart test` |
| Domain | from `packages/nimbus_domain/`: `dart test` |
| Analysis | from the repo root: `dart analyze --fatal-infos` |
| Architecture | from the repo root: `dart test test/architecture_test.dart` |
| Kotlin | from `app/android/`: `./gradlew :app:testDebugUnitTest` |

**Widget tests**
- Never await a drift stream's `.first` inside `testWidgets`. Use one-shot DAO reads.
- `pumpAndSettle` never settles while a `LinearProgressIndicator` is showing. While work is held open, use `pump(duration)`.
- A deliberately unexpected error is consumed with `tester.takeException()`.

**Device rules**
- The A53 (`RZCT209E3QX`) is the operator's daily phone, and all NimbuStats data on it is disposable.
- Before driving it, confirm with the operator that it is free and unlocked.
- Ask before changing any device-wide setting, such as `bmgr enable`.
- `adb` is at `C:\dev\android-sdk\platform-tools\adb.exe`. Use `MSYS_NO_PATHCONV=1` for device paths in Git Bash.

## Rulings this plan makes

Each one is decided here, named in its commit, and recorded in the gate.

| # | Ruling | Why | If wrong |
|---|---|---|---|
| R1 | "Interrupted restore" is proven by injected failures plus a delayed-writer test, not by "a short busy timeout makes the step fail" (spec §7) | `sqlite3 3.5.2`'s `_backupDatabase` retries `SQLITE_BUSY`/`LOCKED` forever, 250 ms apart. With `nPage: -1` it writes nothing until it holds the lock, so a busy destination never fails. The failures that *can* happen are injected instead: a refused swap (page-size mismatch, `SqliteException(8)`, proven 2026-10-17) and an undo copy that cannot be written. The busy timeout is a constructor parameter, 5 s by default, so the delayed-writer test is quick | One more test shape. The atomicity argument is unchanged: one write transaction |
| R2 | No confirmation dialog, and no dialogs at all. Passphrase, progress and destination are steps of one bottom sheet per flow. The restore sheet states that restoring replaces all data, and its **Restore** button commits. Undo follows as a snackbar on Home and as the settings row | `ux_rules_test` forbids `showDialog(` app-wide: "undo, never confirm". Spec §5.3's confirm text becomes the sheet's statement, and the undo copy the operator chose is the safety net | Lifting the house rule is the operator's call, not this phase's |
| R3 | `AppRestart` takes two frames: an empty frame first, so the old `ProviderScope` is disposed before the new one builds | `OutsideChannel.dispose()` calls `setMethodCallHandler(null)` on the shared channel name. A key swap builds the new scope *before* finalising the old one, so the old dispose would silence every native → Dart call | One blank frame, about 16 ms, after a restore |
| R4 | The undo copy is written as `….pre-restore.sqlite.part` and renamed over the old copy only after the swap succeeds | A failed restore keeps the previous undo copy, and a half-written copy can never be offered for undo. The `.part` file is excluded from Auto Backup and swept | None |
| R5 | `saveDocument` and `shareFile` take only `path`. The file name is the path's last segment. `FileProvider` serves `cache/backup/out/` only | The spec's separate `name` would always equal the path's own name. Serving only `out/` keeps the plaintext temps unshareable | None |
| R6 | A header's KDF settings are bounded: memory 8·p … 262 144 KiB, iterations 1–16, parallelism 1–8, schema version ≥ 1. Anything else is `UnsupportedFormat` | The file is untrusted input. An unbounded header could ask Argon2id for gigabytes and crash the app before the passphrase is checked | A legitimate future file past the bounds needs a format-version bump, which it would need anyway |
| R7 | The size warning ships: above 20 MiB (`page_count × page_size`), the section warns | Measured on the host on 2026-10-17 with `DemoDataSeeder` (5,000 rows, 12,453 tag links): 770,048 B per 1,000 transactions vacuumed, 160,962 B gzipped. At 20 a day that is about 5.6 MB a year, so 25 MB in about 4.4 years. Spec §4.3's rule ("under ~10 years → warn") applies | None. Task 14 re-checks the order of magnitude on the A53 |
| R8 | A `SqliteException` while opening or migrating the decrypted file is reported as unexpected, not shown as `CorruptBackup` | The content passed GCM authentication, so it is what this app wrote. A failure there is a bug to see, not damage to blame on the file | A user sees "couldn't be restored" instead of "damaged". Both leave data unchanged |
| R9 | "Last export" is recorded when `saveDocument` returns true or the share sheet opens | Spec §5.1: it records the hand-off. Whether a share target kept the file is unknowable | None |
| R10 | The golden fixture uses Argon2id 1 MiB/t1 and the tests use 64 KiB/t1 | The header carries the settings, so the decode path is production's. Production settings would add seconds per test | None |
| R11 | `VACUUM INTO` and the swap run on the main isolate, where drift's connection lives | For a 4 MB database the swap took 44 ms in the probe. A drain write holding the lock can stall it up to the 5 s busy timeout, and the sheet shows progress meanwhile | A UI pause under a concurrent widget drain. Recorded in the gate |
| R12 | The restart notice waits for the restored settings | The snackbar then speaks the restored language and calendar, not the defaults' | None |
| R13 | `test/support/harness.dart` gains backup fakes by default | Every settings test now builds `BackupSection`. Without fakes they would hit `path_provider` and the platform channel. This is an additive edit to a shared test file, as Phase 6 did for `outsideChannelProvider` | None |

## Review Focus

Five failures that no spec-listed test reaches, most likely first. Each has a test in its owning task.

1. **The wrong file is picked.** A photo or a PDF from Downloads must say "isn't a NimbuStats backup" and leave no copy in the cache. Task 9 tests that a header error deletes the copy. Task 12 tests the message.
2. **The passphrase is typed on another keyboard.** Exported with Persian digits and restored with Latin ones, it must work. The export sheet must also accept a repeat typed in the other digit set. Task 2 covers normalisation. Task 11 tests the sheet accepting `۱۲۳۴۵۶۷۸` against `12345678`.
3. **Back, or a tap outside the sheet, mid-encryption.** The sheet must stay, and the work must finish. Task 11 tests this with a held export.
4. **The Save picker is cancelled.** That is not an error: the sheet stays on Save/Share, and no "last export" is recorded. Task 11 tests this.
5. **Native calls after a restore.** Widget taps and notification routes must still reach the live engine (R3). Task 8 tests that dispose comes before create. Task 14 checks on device that a widget tap after a restore drains in the app engine.

---

## File structure

**`packages/nimbus_data/`**

| File | Does |
|---|---|
| `lib/src/backup/backup_errors.dart` | The sealed `BackupException` family (spec §2.4) |
| `lib/src/backup/backup_format.dart` | `KdfParams`, `BackupHeader` encode/decode, `backupFileName` |
| `lib/src/backup/backup_crypto.dart` | `normalizePassphrase`, `deriveBackupKeys`, `sealBackup`, `openBackup` |
| `lib/src/backup/backup_service.dart` | `BackupService` (export, readHeader, prepare, restore, undo, sweep) and `PreparedRestore` |
| `lib/nimbus_data.dart` | Four new export lines |
| `pubspec.yaml` | `cryptography: ^2.9.0` |
| `tool/make_backup_fixture.dart` | Writes the golden v1 file, once |
| `test/fixtures/backup_v1.nimbus` | The golden file |
| `test/backup/support/backup_fixture.dart` | A file-backed database and service in a temp dir |
| `test/backup/*_test.dart` | Format, crypto, export, prepare and restore |

**`app/`**

| File | Does |
|---|---|
| `lib/features/backup/data/backup_channel.dart` | Dart half of the channel |
| `lib/features/backup/data/backup_state_store.dart` | `backup_state.json` |
| `lib/features/backup/application/restart.dart` | `RestartNotice`, `appRestartProvider`, `restartNoticeProvider` |
| `lib/features/backup/application/backup_providers.dart` | `databaseFileProvider`, `backupServiceProvider`, `backupStateStoreProvider`, `backupStatusProvider` |
| `lib/features/backup/application/backup_controller.dart` | The section's actions |
| `lib/features/backup/presentation/app_restart.dart` | The root that a restore rebuilds |
| `lib/features/backup/presentation/backup_messages.dart` | `backupErrorText`, `reportBackupFailure`, `whenLabel` |
| `lib/features/backup/presentation/backup_sheet_parts.dart` | `BackupSheetFrame`, `PassphraseField`, `BackupProgress` |
| `lib/features/backup/presentation/export_sheet.dart` | Export flow |
| `lib/features/backup/presentation/restore_sheet.dart` | Restore flow |
| `lib/features/backup/presentation/backup_section.dart` | The Settings section |
| `lib/features/backup/presentation/restart_notice_listener.dart` | The snackbar after a restart |
| `lib/main.dart` | `AppRestart` root, `databaseFileProvider` override (shared, additive) |
| `lib/bootstrap/app_shell.dart` | One line: `body: RestartNoticeListener(child: child)` (shared, additive) |
| `lib/features/settings/presentation/settings_screen.dart` | One `BackupSection` (shared, additive) |
| `lib/l10n/app_{en,fa}.arb` | `backup…` keys |
| `test/support/harness.dart` | Backup fakes by default (R13) |
| `test/features/backup/**` | The app tests and the two fakes |

**`app/android/app/src/main/`**

| File | Does |
|---|---|
| `kotlin/com/nimbustats/app/backup/NimbusBackupAgent.kt` | Checkpoint, then the XML rules |
| `kotlin/com/nimbustats/app/backup/BackupDocuments.kt` | Save, Share and Open |
| `kotlin/com/nimbustats/app/MainActivity.kt` | Registers the channel and forwards activity results |
| `res/xml/backup_rules.xml` | `fullBackupContent` (API 26–30) |
| `res/xml/data_extraction_rules.xml` | `dataExtractionRules` (API 31+) |
| `res/xml/backup_file_paths.xml` | `FileProvider` paths |
| `AndroidManifest.xml` | Backup attributes and the provider |

## Branching

`phase/7-backup` already holds the spec (920ff21) and this plan.

For each task with slug `<slug>`:

```bash
git checkout -b feat/<slug> phase/7-backup
# … write the failing test, see RED …
git tag pre-<slug> phase/7-backup
# … implement, see GREEN, run the broader suite, commit …
git checkout phase/7-backup && git merge --ff-only feat/<slug>
```

The gate (Task 15) fast-forwards `main` and tags `phase-7-complete`. Push only when the operator asks.

---

### Task 1: The backup header and its errors

Slug: `backup-format`. Spec §2.1, §2.4, ruling R6.

**Files:**
- Create: `packages/nimbus_data/lib/src/backup/backup_errors.dart`
- Create: `packages/nimbus_data/lib/src/backup/backup_format.dart`
- Modify: `packages/nimbus_data/lib/nimbus_data.dart`
- Test: `packages/nimbus_data/test/backup/backup_format_test.dart`

**Interfaces:**
- Produces:
  - `sealed class BackupException implements Exception`, with `NotABackup()`, `UnsupportedFormat(String reason)`, `NewerSchema({required int backup, required int app})`, `WrongPassphrase()` and `CorruptBackup(String reason)`.
  - `final class KdfParams({required int memoryKiB, required int iterations, required int parallelism})`, with `static const standard` and value equality.
  - `final class BackupHeader({required int schemaVersion, required DateTime createdAt, required KdfParams kdf, required Uint8List salt, required Uint8List nonce, required Uint8List keyCheck})`.
    - Constants `length = 76`, `formatVersion = 1`, `saltLength = 16`, `nonceLength = 12` and `keyCheckLength = 16`.
    - `Uint8List encode()`.
    - `static BackupHeader decode(Uint8List file)`.
  - `String backupFileName(DateTime local)`.

- [ ] **Step 1: Branch**

```bash
git checkout -b feat/backup-format phase/7-backup
```

- [ ] **Step 2: Write the failing test**

Create `packages/nimbus_data/test/backup/backup_format_test.dart`:

```dart
import 'dart:typed_data';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

void main() {
  BackupHeader sample({
    int schemaVersion = 40,
    KdfParams kdf = KdfParams.standard,
  }) =>
      BackupHeader(
        schemaVersion: schemaVersion,
        createdAt: DateTime.utc(2026, 10, 17, 9, 30),
        kdf: kdf,
        salt: Uint8List.fromList(List.generate(16, (i) => i)),
        nonce: Uint8List.fromList(List.generate(12, (i) => 100 + i)),
        keyCheck: Uint8List.fromList(List.generate(16, (i) => 200 + i)),
      );

  test('a header is 76 bytes and reads back field for field', () {
    final bytes = sample().encode();
    expect(bytes, hasLength(BackupHeader.length));
    expect(String.fromCharCodes(bytes.sublist(0, 8)), 'NIMBUSBK');

    final back = BackupHeader.decode(bytes);
    expect(back.schemaVersion, 40);
    expect(back.createdAt, DateTime.utc(2026, 10, 17, 9, 30));
    expect(back.createdAt.isUtc, isTrue);
    expect(back.kdf, KdfParams.standard);
    expect(back.salt, sample().salt);
    expect(back.nonce, sample().nonce);
    expect(back.keyCheck, sample().keyCheck);
  });

  test('the layout is big-endian at the offsets spec §2.1 fixes', () {
    final data = ByteData.sublistView(sample().encode());
    expect(data.getUint16(8), 1);
    expect(data.getUint32(10), 40);
    expect(data.getUint64(14),
        DateTime.utc(2026, 10, 17, 9, 30).millisecondsSinceEpoch);
    expect(data.getUint8(22), 1);
    expect(data.getUint32(23), KdfParams.standard.memoryKiB);
    expect(data.getUint32(27), KdfParams.standard.iterations);
    expect(data.getUint8(31), KdfParams.standard.parallelism);
    expect(data.getUint8(32), 0); // salt[0]
    expect(data.getUint8(48), 100); // nonce[0]
    expect(data.getUint8(60), 200); // key check[0]
  });

  test('decode reads only the header of a longer file', () {
    final file = Uint8List.fromList([...sample().encode(), 1, 2, 3]);
    expect(BackupHeader.decode(file).schemaVersion, 40);
  });

  group('not a backup', () {
    test('shorter than the header', () {
      expect(() => BackupHeader.decode(sample().encode().sublist(0, 75)),
          throwsA(isA<NotABackup>()));
    });
    test('an empty file', () {
      expect(() => BackupHeader.decode(Uint8List(0)),
          throwsA(isA<NotABackup>()));
    });
    test('wrong magic', () {
      expect(() => BackupHeader.decode(sample().encode()..[0] = 0x58),
          throwsA(isA<NotABackup>()));
    });
  });

  group('unsupported', () {
    test('a newer format version', () {
      final bytes = sample().encode();
      ByteData.sublistView(bytes).setUint16(8, 2);
      expect(() => BackupHeader.decode(bytes),
          throwsA(isA<UnsupportedFormat>()));
    });
    test('an unknown key derivation', () {
      expect(() => BackupHeader.decode(sample().encode()..[22] = 2),
          throwsA(isA<UnsupportedFormat>()));
    });
    test('key-derivation settings past what a phone can run (R6)', () {
      for (final kdf in const [
        KdfParams(memoryKiB: 512 * 1024, iterations: 3, parallelism: 1),
        KdfParams(memoryKiB: 65536, iterations: 0, parallelism: 1),
        KdfParams(memoryKiB: 65536, iterations: 17, parallelism: 1),
        KdfParams(memoryKiB: 65536, iterations: 3, parallelism: 0),
        KdfParams(memoryKiB: 65536, iterations: 3, parallelism: 9),
        KdfParams(memoryKiB: 15, iterations: 1, parallelism: 2),
      ]) {
        expect(() => BackupHeader.decode(sample(kdf: kdf).encode()),
            throwsA(isA<UnsupportedFormat>()),
            reason: '$kdf');
      }
    });
    test('schema version 0', () {
      expect(() => BackupHeader.decode(sample(schemaVersion: 0).encode()),
          throwsA(isA<UnsupportedFormat>()));
    });
  });

  test('the file name is local time in ASCII digits', () {
    expect(backupFileName(DateTime(2026, 3, 5, 7, 9)),
        'nimbustats-20260305-0709.nimbus');
  });

  test('an error names its kind and fixed facts, nothing else', () {
    expect(const NotABackup().toString(),
        'NotABackup: not a NimbuStats backup file');
    expect(const NewerSchema(backup: 41, app: 40).toString(),
        'NewerSchema: backup v41, app v40');
    expect(const WrongPassphrase().toString(), 'WrongPassphrase');
  });
}
```

- [ ] **Step 3: Run it and see RED**

Run from `packages/nimbus_data/`: `dart test test/backup/backup_format_test.dart`.

Expected: compile errors, because `BackupHeader`, `KdfParams`, `NotABackup` and the others are undefined.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-backup-format phase/7-backup
```

- [ ] **Step 5: Write the errors**

Create `packages/nimbus_data/lib/src/backup/backup_errors.dart`:

```dart
/// Why a backup file cannot be restored (Phase 7 spec §2.4), checked in
/// declaration order.
///
/// None carries the passphrase or anything derived from it, so `toString` is
/// safe to log or report.
sealed class BackupException implements Exception {
  const BackupException();
}

/// Shorter than the header, or not starting with the magic bytes.
final class NotABackup extends BackupException {
  const NotABackup();

  @override
  String toString() => 'NotABackup: not a NimbuStats backup file';
}

/// A format version or key-derivation setting this app cannot read.
final class UnsupportedFormat extends BackupException {
  const UnsupportedFormat(this.reason);

  final String reason;

  @override
  String toString() => 'UnsupportedFormat: $reason';
}

/// Made by an app with a newer schema. Restoring it would corrupt data in
/// ways no migration can repair, so it is refused before the passphrase is
/// asked for.
final class NewerSchema extends BackupException {
  const NewerSchema({required this.backup, required this.app});

  final int backup;
  final int app;

  @override
  String toString() => 'NewerSchema: backup v$backup, app v$app';
}

/// The passphrase derives a key-check value that differs from the file's.
final class WrongPassphrase extends BackupException {
  const WrongPassphrase();

  @override
  String toString() => 'WrongPassphrase';
}

/// The passphrase is right but the content fails a check: damaged, or
/// tampered with.
final class CorruptBackup extends BackupException {
  const CorruptBackup(this.reason);

  final String reason;

  @override
  String toString() => 'CorruptBackup: $reason';
}
```

- [ ] **Step 6: Write the format**

Create `packages/nimbus_data/lib/src/backup/backup_format.dart`:

```dart
import 'dart:typed_data';

import 'backup_errors.dart';

/// The Argon2id settings a file was sealed with (spec §2.2).
///
/// They travel in the file's header, so changing [standard] never breaks an
/// older file.
final class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// What new exports use. Fixed after the Galaxy A53 measurement (plan
  /// Task 14): the strongest setting that derives in about 2 s there.
  static const standard =
      KdfParams(memoryKiB: 65536, iterations: 3, parallelism: 1);

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      other.memoryKiB == memoryKiB &&
      other.iterations == iterations &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(memoryKiB, iterations, parallelism);

  @override
  String toString() =>
      'KdfParams(${memoryKiB}KiB, t=$iterations, p=$parallelism)';
}

/// The fixed 76-byte header of a `.nimbus` file (spec §2.1).
///
/// Integers are big-endian. The whole header is the AES-GCM associated data,
/// so changing any byte of it, such as lowering the schema version, fails
/// authentication.
final class BackupHeader {
  const BackupHeader({
    required this.schemaVersion,
    required this.createdAt,
    required this.kdf,
    required this.salt,
    required this.nonce,
    required this.keyCheck,
  });

  static const length = 76;
  static const formatVersion = 1;
  static const saltLength = 16;
  static const nonceLength = 12;
  static const keyCheckLength = 16;

  static const _magic = 'NIMBUSBK';
  static const _argon2id = 1;

  // The file is untrusted input (ruling R6). Without a ceiling, a crafted
  // header could ask Argon2id for gigabytes and crash the app before the
  // passphrase is even checked.
  static const _maxMemoryKiB = 256 * 1024;
  static const _maxIterations = 16;
  static const _maxParallelism = 8;

  /// The payload's `PRAGMA user_version`.
  final int schemaVersion;

  /// When the export was made, in UTC.
  final DateTime createdAt;
  final KdfParams kdf;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List keyCheck;

  Uint8List encode() {
    final bytes = Uint8List(length)..setAll(0, _magic.codeUnits);
    ByteData.sublistView(bytes)
      ..setUint16(8, formatVersion)
      ..setUint32(10, schemaVersion)
      ..setUint64(14, createdAt.millisecondsSinceEpoch)
      ..setUint8(22, _argon2id)
      ..setUint32(23, kdf.memoryKiB)
      ..setUint32(27, kdf.iterations)
      ..setUint8(31, kdf.parallelism);
    return bytes
      ..setAll(32, salt)
      ..setAll(48, nonce)
      ..setAll(60, keyCheck);
  }

  /// Reads the header at the start of [file].
  ///
  /// Throws [NotABackup] or [UnsupportedFormat].
  static BackupHeader decode(Uint8List file) {
    if (file.length < length) throw const NotABackup();
    for (var i = 0; i < _magic.length; i++) {
      if (file[i] != _magic.codeUnitAt(i)) throw const NotABackup();
    }
    final data = ByteData.sublistView(file, 0, length);
    final version = data.getUint16(8);
    if (version != formatVersion) {
      throw UnsupportedFormat('format version $version');
    }
    final kdfId = data.getUint8(22);
    if (kdfId != _argon2id) throw UnsupportedFormat('key derivation $kdfId');
    final kdf = KdfParams(
      memoryKiB: data.getUint32(23),
      iterations: data.getUint32(27),
      parallelism: data.getUint8(31),
    );
    if (kdf.parallelism < 1 ||
        kdf.parallelism > _maxParallelism ||
        kdf.memoryKiB < 8 * kdf.parallelism ||
        kdf.memoryKiB > _maxMemoryKiB ||
        kdf.iterations < 1 ||
        kdf.iterations > _maxIterations) {
      throw const UnsupportedFormat('key derivation settings out of range');
    }
    final schemaVersion = data.getUint32(10);
    if (schemaVersion < 1) throw const UnsupportedFormat('schema version 0');
    return BackupHeader(
      schemaVersion: schemaVersion,
      createdAt: DateTime.fromMillisecondsSinceEpoch(data.getUint64(14),
          isUtc: true),
      kdf: kdf,
      salt: Uint8List.fromList(file.sublist(32, 48)),
      nonce: Uint8List.fromList(file.sublist(48, 60)),
      keyCheck: Uint8List.fromList(file.sublist(60, 76)),
    );
  }
}

/// `nimbustats-YYYYMMDD-HHmm.nimbus`, in ASCII digits, Gregorian and the
/// device's local time (spec §2.1), so the name reads and sorts the same in
/// any language.
String backupFileName(DateTime local) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'nimbustats-${local.year.toString().padLeft(4, '0')}'
      '${two(local.month)}${two(local.day)}-'
      '${two(local.hour)}${two(local.minute)}.nimbus';
}
```

- [ ] **Step 7: Export both from the barrel**

In `packages/nimbus_data/lib/nimbus_data.dart`, after `export 'src/analytics/saved_view.dart';`, insert:

```dart
export 'src/backup/backup_errors.dart';
export 'src/backup/backup_format.dart';
```

- [ ] **Step 8: Run it and see GREEN**

Run from `packages/nimbus_data/`: `dart test test/backup/backup_format_test.dart`. Expected: all pass.

- [ ] **Step 9: Run the broader suite**

Run, from `packages/nimbus_data/`: `dart test`. From the repo root: `dart analyze --fatal-infos`. Expected: green, with no infos.

- [ ] **Step 10: Commit and merge**

```bash
git add packages/nimbus_data/lib/src/backup packages/nimbus_data/lib/nimbus_data.dart packages/nimbus_data/test/backup/backup_format_test.dart
git commit -m "$(cat <<'EOF'
feat(backup): the .nimbus header and the errors a restore can raise

The header carries everything an old file needs to be read again: the
format and schema versions, when it was made, and the Argon2id
settings with their salt. Changing the KDF later then never breaks a
file already in someone's Drive. Its KDF settings are bounded because
the file is untrusted input: an unbounded header could ask for
gigabytes of memory and crash the app before the passphrase is checked
(ruling R6). The errors are a sealed family whose toString names only
its kind and fixed facts, so any of them is safe in a log.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only feat/backup-format
```

---

### Task 2: Key derivation and AEAD, with known-answer tests

Slug: `backup-crypto`. Spec §2.2, §2.3, §7 (known answers).

**Files:**
- Modify: `packages/nimbus_data/pubspec.yaml`, and `pubspec.lock` (repo root, through `pub get`)
- Modify: `test/architecture_test.dart`
- Create: `packages/nimbus_data/lib/src/backup/backup_crypto.dart`
- Modify: `packages/nimbus_data/lib/nimbus_data.dart`
- Test: `packages/nimbus_data/test/backup/backup_crypto_test.dart`

**Interfaces:**
- Consumes: Task 1's `BackupHeader`, `KdfParams`, `WrongPassphrase`, `CorruptBackup` and `NotABackup`.
- Produces:
  - `const int minPassphraseRunes = 8`.
  - `String normalizePassphrase(String)`.
  - `final class BackupKeys`, with `SecretKey encryption` and `Uint8List check`. Its `toString` is `'BackupKeys(...)'`.
  - `Future<BackupKeys> deriveBackupKeys(String passphrase, KdfParams kdf, List<int> salt)`.
  - `Future<Uint8List> sealBackup({required List<int> payload, required String passphrase, required int schemaVersion, required DateTime createdAt, KdfParams kdf = KdfParams.standard})`.
  - `Future<Uint8List> openBackup(Uint8List file, String passphrase)`.

- [ ] **Step 1: Branch, and add the dependency so the test can import it**

```bash
git checkout -b feat/backup-crypto phase/7-backup
```

In `packages/nimbus_data/pubspec.yaml`, under `dependencies:` and after `nimbus_domain: ^0.0.0`, add:

```yaml
  # Phase 7: Argon2id, HKDF and AES-GCM for the encrypted backup file.
  # Pure Dart, so this layer stays free of Flutter.
  cryptography: ^2.9.0
```

From the repo root run `flutter pub get --offline`. Expected: `Got dependencies!`, and `git diff pubspec.lock` adds only a `cryptography` entry, version `2.9.0`. If it fails offline, stop and report: the package and its dependencies were cached on 2026-10-17.

- [ ] **Step 2: Write the failing tests**

In `test/architecture_test.dart`, inside `test('nimbus_data is pure Dart and never reaches the UI', …)`, after `expect(deps, contains('nimbus_domain'));`, add:

```dart
    // cryptography is Phase 7's one new runtime dependency: Argon2id, HKDF
    // and AES-GCM for the encrypted backup file, in pure Dart. Asserted here
    // so that the choice of a real KDF and an AEAD stays visible in the
    // boundary rules, not only in a pubspec.
    expect(deps, contains('cryptography'));
```

Create `packages/nimbus_data/test/backup/backup_crypto_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:test/test.dart';

List<int> hex(String text) => [
      for (var i = 0; i < text.length; i += 2)
        int.parse(text.substring(i, i + 2), radix: 16),
    ];

/// Cheap settings (ruling R10). The header carries them, so every other step
/// is the production path.
const fast = KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

void main() {
  group('known answers', () {
    test('Argon2id, RFC 9106 §5.3', () async {
      final tag = await Argon2id(
              memory: 32, iterations: 3, parallelism: 4, hashLength: 32)
          .deriveKey(
        secretKey: SecretKey(List.filled(32, 0x01)),
        nonce: List.filled(16, 0x02),
        optionalSecret: List.filled(8, 0x03),
        associatedData: List.filled(12, 0x04),
      );
      expect(await tag.extractBytes(),
          hex('0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659'));
    });

    test('HKDF-SHA256, RFC 5869 test case 1', () async {
      final okm = await Hkdf(hmac: Hmac.sha256(), outputLength: 42).deriveKey(
        secretKey: SecretKey(hex('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b')),
        nonce: hex('000102030405060708090a0b0c'),
        info: hex('f0f1f2f3f4f5f6f7f8f9'),
      );
      expect(
          await okm.extractBytes(),
          hex('3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
              '34007208d5b887185865'));
    });

    test('AES-256-GCM, the GCM specification test case 16', () async {
      final box = await AesGcm.with256bits().encrypt(
        hex('d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72'
            '1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39'),
        secretKey: SecretKey(hex(
            'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308')),
        nonce: hex('cafebabefacedbaddecaf888'),
        aad: hex('feedfacedeadbeeffeedfacedeadbeefabaddad2'),
      );
      expect(
          box.cipherText,
          hex('522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa'
              '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662'));
      expect(box.mac.bytes, hex('76fc6ece0f4e1768cddf8853bb2d551b'));
    });
  });

  test('the derivation is pinned: normalise, Argon2id, then both HKDF infos',
      () async {
    final keys =
        await deriveBackupKeys('correct horse battery', fast, List.filled(16, 1));
    expect(keys.check, hex('2fcd19cee5eb70a6910c4fabe0f1bfbc'));
    expect(
        await keys.encryption.extractBytes(),
        hex('a00f2658241217974d17c6d9992cd892'
            'ceba7e1c79ae369d4edb5100f67649c7'));
  });

  group('passphrase normalisation, part of format v1', () {
    for (final (typed, normalised) in [
      ('رمزي', 'رمزی'), // Arabic yeh -> Persian yeh
      ('كتاب', 'کتاب'), // Arabic kaf -> Persian keheh
      ('۱۲۳٤٥٦', '123456'), // Persian and Arabic-Indic digits -> ASCII
      (' pass word ', ' pass word '), // nothing trimmed
      ('Pass', 'Pass'), // case kept
    ]) {
      test(typed, () => expect(normalizePassphrase(typed), normalised));
    }
  });

  group('seal and open', () {
    final created = DateTime.utc(2026, 10, 17, 9, 30);

    Future<Uint8List> seal(List<int> payload,
            [String passphrase = 'correct horse']) =>
        sealBackup(
          payload: payload,
          passphrase: passphrase,
          schemaVersion: 40,
          createdAt: created,
          kdf: fast,
        );

    test('round trip, with the header describing the file', () async {
      final file = await seal(utf8.encode('payload'));
      final header = BackupHeader.decode(file);
      expect(header.schemaVersion, 40);
      expect(header.createdAt, created);
      expect(header.kdf, fast);
      expect(file, hasLength(BackupHeader.length + 'payload'.length + 16));
      expect(utf8.decode(await openBackup(file, 'correct horse')), 'payload');
    });

    test('the same passphrase from another keyboard opens it', () async {
      final file = await seal([1, 2, 3], 'رمز-پشتیبان-۱۴۰۵');
      expect(await openBackup(file, 'رمز-پشتيبان-1405'), [1, 2, 3]);
    });

    test('two seals of one payload share no salt, nonce or ciphertext',
        () async {
      final a = await seal([1, 2, 3]);
      final b = await seal([1, 2, 3]);
      expect(a.sublist(32, 60), isNot(b.sublist(32, 60)));
      expect(a.sublist(BackupHeader.length),
          isNot(b.sublist(BackupHeader.length)));
    });

    test('a wrong passphrase is WrongPassphrase', () async {
      await expectLater(openBackup(await seal([1]), 'correct horse!'),
          throwsA(isA<WrongPassphrase>()));
    });

    test('a flipped ciphertext byte is CorruptBackup, not a wrong passphrase',
        () async {
      final file = await seal([1, 2, 3, 4]);
      file[BackupHeader.length + 1] ^= 0x01;
      await expectLater(openBackup(file, 'correct horse'),
          throwsA(isA<CorruptBackup>()));
    });

    test('a flipped header byte outside the key inputs is CorruptBackup',
        () async {
      // A created-at byte: authenticated as associated data, but not an
      // input to the key. A flipped salt, KDF or check byte changes the
      // derived check instead and reads as WrongPassphrase. Those two cases
      // cannot be told apart, and neither restores anything.
      final file = await seal([1, 2, 3]);
      file[20] ^= 0x01;
      await expectLater(openBackup(file, 'correct horse'),
          throwsA(isA<CorruptBackup>()));
    });

    test('a lowered schema version fails authentication', () async {
      final file = await seal([1, 2, 3]);
      ByteData.sublistView(file).setUint32(10, 39);
      await expectLater(openBackup(file, 'correct horse'),
          throwsA(isA<CorruptBackup>()));
    });

    test('a cut tail is CorruptBackup; a cut header is NotABackup', () async {
      final file = await seal([1, 2, 3]);
      await expectLater(
          openBackup(file.sublist(0, file.length - 1), 'correct horse'),
          throwsA(isA<CorruptBackup>()));
      await expectLater(
          openBackup(file.sublist(0, BackupHeader.length + 3), 'correct horse'),
          throwsA(isA<CorruptBackup>()));
      await expectLater(openBackup(file.sublist(0, 40), 'correct horse'),
          throwsA(isA<NotABackup>()));
    });

    test('derived keys never print', () async {
      final keys = await deriveBackupKeys('correct horse', fast, List.filled(16, 2));
      expect(keys.toString(), 'BackupKeys(...)');
    });
  });
}
```

- [ ] **Step 3: Run them and see RED**

From the repo root: `dart test test/architecture_test.dart`. Expected: PASS. The dependency was added in Step 1, so this guard is green on arrival; its purpose is to keep the dependency visible.

From `packages/nimbus_data/`: `dart test test/backup/backup_crypto_test.dart`. Expected: compile errors, because `deriveBackupKeys`, `normalizePassphrase`, `sealBackup` and `openBackup` are undefined.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-backup-crypto phase/7-backup
```

- [ ] **Step 5: Write the crypto**

Create `packages/nimbus_data/lib/src/backup/backup_crypto.dart`:

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import 'backup_errors.dart';
import 'backup_format.dart';

/// The fewest runes an export's passphrase may have (spec §2.3).
const minPassphraseRunes = 8;

const _tagLength = 16;

/// Spec §2.3, part of format version 1. The same visible passphrase typed on
/// a Persian or an Arabic keyboard, in any digit set, derives the same key.
/// Nothing is trimmed: a space is part of the passphrase.
String normalizePassphrase(String passphrase) => Digits.toLatin(passphrase)
    .replaceAll('\u064A', '\u06CC') // Arabic yeh -> Persian yeh
    .replaceAll('\u0643', '\u06A9'); // Arabic kaf -> Persian keheh

/// The two keys one passphrase derives (spec §2.2).
///
/// A class rather than a record, so that printing one shows nothing.
final class BackupKeys {
  BackupKeys._(this.encryption, this.check);

  final SecretKey encryption;
  final Uint8List check;

  @override
  String toString() => 'BackupKeys(...)';
}

Future<BackupKeys> deriveBackupKeys(
    String passphrase, KdfParams kdf, List<int> salt) async {
  final master = await Argon2id(
    memory: kdf.memoryKiB,
    iterations: kdf.iterations,
    parallelism: kdf.parallelism,
    hashLength: 32,
  ).deriveKey(
    secretKey: SecretKey(utf8.encode(normalizePassphrase(passphrase))),
    nonce: salt,
  );
  final encryption = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
      .deriveKey(secretKey: master, info: utf8.encode('nimbus-backup v1 enc'));
  final check = await Hkdf(hmac: Hmac.sha256(), outputLength: 16)
      .deriveKey(secretKey: master, info: utf8.encode('nimbus-backup v1 check'));
  return BackupKeys._(encryption, Uint8List.fromList(await check.extractBytes()));
}

/// Seals [payload] into a whole `.nimbus` file: header, ciphertext, tag.
Future<Uint8List> sealBackup({
  required List<int> payload,
  required String passphrase,
  required int schemaVersion,
  required DateTime createdAt,
  KdfParams kdf = KdfParams.standard,
}) async {
  final random = Random.secure();
  Uint8List randomBytes(int count) =>
      Uint8List.fromList([for (var i = 0; i < count; i++) random.nextInt(256)]);
  final salt = randomBytes(BackupHeader.saltLength);
  final keys = await deriveBackupKeys(passphrase, kdf, salt);
  final header = BackupHeader(
    schemaVersion: schemaVersion,
    createdAt: createdAt.toUtc(),
    kdf: kdf,
    salt: salt,
    nonce: randomBytes(BackupHeader.nonceLength),
    keyCheck: keys.check,
  );
  final headerBytes = header.encode();
  final box = await AesGcm.with256bits().encrypt(
    payload,
    secretKey: keys.encryption,
    nonce: header.nonce,
    aad: headerBytes,
  );
  return (BytesBuilder(copy: false)
        ..add(headerBytes)
        ..add(box.cipherText)
        ..add(box.mac.bytes))
      .takeBytes();
}

/// Opens a whole `.nimbus` file and returns its payload.
///
/// The key-check value is what tells a wrong passphrase from damage (spec
/// §2.2). A mismatch is [WrongPassphrase]. A match whose GCM tag then fails
/// is [CorruptBackup].
Future<Uint8List> openBackup(Uint8List file, String passphrase) async {
  final header = BackupHeader.decode(file);
  final keys = await deriveBackupKeys(passphrase, header.kdf, header.salt);
  if (!_same(keys.check, header.keyCheck)) throw const WrongPassphrase();
  if (file.length < BackupHeader.length + _tagLength) {
    throw const CorruptBackup('truncated');
  }
  try {
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(
        Uint8List.sublistView(file, BackupHeader.length, file.length - _tagLength),
        nonce: header.nonce,
        mac: Mac(Uint8List.sublistView(file, file.length - _tagLength)),
      ),
      secretKey: keys.encryption,
      aad: Uint8List.sublistView(file, 0, BackupHeader.length),
    );
    return clear is Uint8List ? clear : Uint8List.fromList(clear);
  } on SecretBoxAuthenticationError {
    throw const CorruptBackup('authentication failed');
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

In `packages/nimbus_data/lib/nimbus_data.dart`, before `export 'src/backup/backup_errors.dart';`, insert:

```dart
export 'src/backup/backup_crypto.dart';
```

- [ ] **Step 6: Run it and see GREEN**

Run from `packages/nimbus_data/`: `dart test test/backup/backup_crypto_test.dart`. Expected: all pass. The known-answer constants and the pinned check value were verified against `cryptography 2.9.0` on 2026-10-17.

- [ ] **Step 7: Run the broader suite**

Run `dart test` in `packages/nimbus_data/`. From the repo root, run `dart analyze --fatal-infos` and `dart test test/architecture_test.dart`. Expected: all green.

- [ ] **Step 8: Commit and merge**

```bash
git add packages/nimbus_data/pubspec.yaml pubspec.lock test/architecture_test.dart packages/nimbus_data/lib packages/nimbus_data/test/backup/backup_crypto_test.dart
git commit -m "$(cat <<'EOF'
feat(backup): Argon2id, HKDF and AES-GCM for the backup file

A raw hash of a passphrase is not encryption. Argon2id makes guessing
expensive, the per-file salt makes each file its own attack, and
AES-GCM over the header as associated data means a lowered schema
version or a flipped byte fails authentication instead of restoring.
A separate HKDF key-check value tells a wrong passphrase from a damaged
file, which the brief requires and GCM alone cannot. Known-answer
tests pin the primitives (RFC 9106, RFC 5869, the GCM spec) and a
pinned derivation pins how they are composed, so a "harmless" refactor
cannot silently orphan every existing backup. The passphrase is
normalised so Persian and Arabic keyboards and either digit set agree.

cryptography 2.9.0 is the one new dependency. It is pure Dart and
resolved offline; the architecture test now names it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only feat/backup-crypto
```

---

### Task 3: Export, and reading a header

Slug: `backup-export`. Spec §3.1, §3.2 step 1. Brief tasks 1 and 4.

**Files:**
- Create: `packages/nimbus_data/lib/src/backup/backup_service.dart`
- Modify: `packages/nimbus_data/lib/nimbus_data.dart`
- Create: `packages/nimbus_data/test/backup/support/backup_fixture.dart`
- Test: `packages/nimbus_data/test/backup/backup_export_test.dart`

**Interfaces:**
- Consumes: Task 2's `sealBackup` and `openBackup`, and Task 1's `BackupHeader` and `NewerSchema`.
- Produces:
  - `class BackupService({required AppDatabase db, required String cacheDir, KdfParams kdf, DateTime Function() clock})`.
    - Task 5 adds `livePath`, `preRestorePath` and `busyTimeout`.
    - Not `final`: app tests implement it.
  - `String cacheDir`.
  - `Future<void> exportTo(String outPath, String passphrase)`.
  - `Future<BackupHeader> readHeader(String path)`.
  - The test-side `BackupFixture`, with `open({clock})`, `path(name)`, `cacheFiles()`, `addExpense({...})` and `close()`. It also exports the constant `fastKdf`.

- [ ] **Step 1: Branch and write the fixture**

```bash
git checkout -b feat/backup-export phase/7-backup
```

Create `packages/nimbus_data/test/backup/support/backup_fixture.dart`:

```dart
import 'dart:io';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

/// Cheap Argon2id settings (ruling R10). The header carries them, so every
/// other step is the production path.
const fastKdf = KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

/// A file-backed WAL database and its [BackupService], in a temp dir of its
/// own: what the app has, minus the platform paths.
final class BackupFixture {
  BackupFixture._(this.dir, this.db, this.service);

  factory BackupFixture.open({DateTime Function()? clock}) {
    final dir = Directory.systemTemp.createTempSync('nimbus_backup');
    String at(String name) => '${dir.path}${Platform.pathSeparator}$name';
    final db = AppDatabase.openAtPath(at('nimbustats.sqlite'));
    return BackupFixture._(
      dir,
      db,
      BackupService(
        db: db,
        cacheDir: at('cache'),
        kdf: fastKdf,
        clock: clock ?? DateTime.now,
      ),
    );
  }

  final Directory dir;
  final AppDatabase db;
  final BackupService service;

  String get livePath => path('nimbustats.sqlite');

  String path(String name) => '${dir.path}${Platform.pathSeparator}$name';

  /// The names in the service's cache directory, folders included.
  List<String> cacheFiles() {
    final cache = Directory(service.cacheDir);
    if (!cache.existsSync()) return [];
    return [
      for (final entry in cache.listSync())
        entry.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty),
    ];
  }

  /// One expense under a category of its own, committed and never
  /// checkpointed: the connection stays open, so the row lives in the WAL.
  Future<String> addExpense({
    int amount = 12345,
    DateTime? occurredAtUtc,
    DateKey? on,
  }) async {
    final id = 'tx-$amount';
    await db.categoriesDao
        .insertNode(id: 'cat-$amount', name: 'Category $amount', parentId: null);
    await db.transactionsDao.insertTransaction(
      id: id,
      direction: TxDirection.expense,
      amount: Money(amount),
      currencyCode: 'IRT',
      occurredAtUtc: (occurredAtUtc ?? DateTime.utc(2026, 10, 17, 9))
          .millisecondsSinceEpoch,
      localDateKey: on ?? DateKey.fromParts(2026, 10, 17),
      categoryId: 'cat-$amount',
      source: TxSource.manual,
      isConfirmed: true,
    );
    return id;
  }

  Future<void> close() async {
    await db.close();
    dir.deleteSync(recursive: true);
  }
}
```

- [ ] **Step 2: Write the failing test**

Create `packages/nimbus_data/test/backup/backup_export_test.dart`:

```dart
import 'dart:io';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/backup_fixture.dart';

void main() {
  late BackupFixture f;
  setUp(() => f = BackupFixture.open(clock: () => DateTime.utc(2026, 10, 17, 9, 30)));
  tearDown(() => f.close());

  /// The snapshot a decrypted [payload] holds, unzipped and opened.
  Database openPayload(List<int> payload) {
    final path = f.path('payload.sqlite');
    File(path).writeAsBytesSync(gzip.decode(payload));
    return sqlite3.open(path, mode: OpenMode.readOnly);
  }

  test('a row committed but never checkpointed is in the export (the WAL trap)',
      () async {
    final id = await f.addExpense();
    // Still connected and never closed: the row is in the -wal file.
    expect(File('${f.livePath}-wal').lengthSync(), greaterThan(0));

    await f.service.exportTo(f.path('out.nimbus'), 'correct horse');

    final payload = await openBackup(
        File(f.path('out.nimbus')).readAsBytesSync(), 'correct horse');
    final snapshot = openPayload(payload);
    addTearDown(snapshot.close);
    expect(snapshot.select('SELECT id FROM transactions').map((r) => r['id']),
        [id]);
  });

  test('the header records the snapshot schema, the time and the KDF',
      () async {
    await f.service.exportTo(f.path('out.nimbus'), 'correct horse');
    final header = await f.service.readHeader(f.path('out.nimbus'));
    expect(header.schemaVersion, f.db.schemaVersion);
    expect(header.createdAt, DateTime.utc(2026, 10, 17, 9, 30));
    expect(header.kdf, fastKdf);
  });

  test('the plaintext snapshot never outlives the export', () async {
    await f.service.exportTo(f.path('out.nimbus'), 'correct horse');
    expect(f.cacheFiles(), isEmpty);
  });

  test('a failed export leaves no plaintext either', () async {
    // The out path is a folder, so the write fails after the snapshot exists.
    Directory(f.path('out.nimbus')).createSync();
    await expectLater(f.service.exportTo(f.path('out.nimbus'), 'correct horse'),
        throwsA(isA<FileSystemException>()));
    expect(f.cacheFiles(), isEmpty);
  });

  group('readHeader', () {
    test('refuses a newer schema before any passphrase is asked for',
        () async {
      File(f.path('newer.nimbus')).writeAsBytesSync(await sealBackup(
        payload: [0],
        passphrase: 'p',
        schemaVersion: f.db.schemaVersion + 1,
        createdAt: DateTime.utc(2026),
        kdf: fastKdf,
      ));
      await expectLater(
        f.service.readHeader(f.path('newer.nimbus')),
        throwsA(isA<NewerSchema>()
            .having((e) => e.backup, 'backup', f.db.schemaVersion + 1)
            .having((e) => e.app, 'app', f.db.schemaVersion)),
      );
    });

    test('a file that is not a backup', () async {
      File(f.path('photo.jpg')).writeAsBytesSync(List.filled(500, 0xFF));
      await expectLater(f.service.readHeader(f.path('photo.jpg')),
          throwsA(isA<NotABackup>()));
    });

    test('an empty file', () async {
      File(f.path('empty.nimbus')).writeAsBytesSync(const []);
      await expectLater(f.service.readHeader(f.path('empty.nimbus')),
          throwsA(isA<NotABackup>()));
    });
  });
}
```

- [ ] **Step 3: Run it and see RED**

Run from `packages/nimbus_data/`: `dart test test/backup/backup_export_test.dart`. Expected: compile errors, because `BackupService` is undefined.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-backup-export phase/7-backup
```

- [ ] **Step 5: Write the service's export half**

Create `packages/nimbus_data/lib/src/backup/backup_service.dart`:

```dart
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'backup_crypto.dart';
import 'backup_errors.dart';
import 'backup_format.dart';

/// Export and restore of the whole database file (Phase 7 spec §3).
///
/// It treats the database as one file and never names a table, so a phase
/// that adds tables needs nothing here. The app injects every path.
class BackupService {
  BackupService({
    required AppDatabase db,
    required this.cacheDir,
    KdfParams kdf = KdfParams.standard,
    DateTime Function() clock = DateTime.now,
  })  : _db = db,
        _kdf = kdf,
        _clock = clock;

  final AppDatabase _db;
  final KdfParams _kdf;
  final DateTime Function() _clock;

  /// Where plaintext temp files live. Android leaves the cache out of Auto
  /// Backup.
  final String cacheDir;

  static const _uuid = Uuid();

  /// Writes an encrypted export of the live database to [outPath].
  Future<void> exportTo(String outPath, String passphrase) async {
    final snapshot = _temp('export');
    try {
      // A consistent single-file copy holding every committed WAL frame,
      // taken while the drain engine stays connected. It replaces the
      // brief's "checkpoint, then copy" (spec, departures).
      await _db.customStatement('VACUUM INTO ?', [snapshot]);
      await _seal(snapshot, outPath, passphrase, _clock().toUtc(), _kdf);
    } finally {
      await _delete(snapshot);
    }
  }

  /// The header of the file at [path]. A newer schema is refused here,
  /// before any passphrase is asked for (spec §2.4).
  Future<BackupHeader> readHeader(String path) async {
    final file = await File(path).open();
    final Uint8List head;
    try {
      head = await file.read(BackupHeader.length);
    } finally {
      await file.close();
    }
    final header = BackupHeader.decode(head);
    if (header.schemaVersion > _db.schemaVersion) {
      throw NewerSchema(backup: header.schemaVersion, app: _db.schemaVersion);
    }
    return header;
  }

  String _temp(String kind) {
    Directory(cacheDir).createSync(recursive: true);
    return '$cacheDir${Platform.pathSeparator}$kind-${_uuid.v4()}.sqlite';
  }

  static Future<void> _delete(String path) async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }
}

/// Reads the snapshot, gzips and seals it, and writes [outPath], in an
/// isolate so that Argon2id and AES never block the UI (spec §3.1).
///
/// A top-level function, so that the closure captures only its arguments.
Future<void> _seal(String snapshot, String outPath, String passphrase,
        DateTime createdAt, KdfParams kdf) =>
    Isolate.run(() async {
      // shortcut: whole file in memory, upgrade to chunked encryption when a database passes ~50 MB
      final plain = File(snapshot).readAsBytesSync();
      final sealed = await sealBackup(
        payload: gzip.encode(plain),
        passphrase: passphrase,
        schemaVersion: _userVersion(plain),
        createdAt: createdAt,
        kdf: kdf,
      );
      File(outPath).writeAsBytesSync(sealed, flush: true);
    });

/// `PRAGMA user_version`, read from a database file's header: offset 60,
/// big-endian.
int _userVersion(List<int> database) =>
    ByteData.sublistView(Uint8List.fromList(database.sublist(60, 64)))
        .getUint32(0);
```

In `packages/nimbus_data/lib/nimbus_data.dart`, after `export 'src/backup/backup_format.dart';`, insert:

```dart
export 'src/backup/backup_service.dart';
```

- [ ] **Step 6: Run it and see GREEN**

Run from `packages/nimbus_data/`: `dart test test/backup/backup_export_test.dart`. Expected: all pass.

- [ ] **Step 7: Run the broader suite**

Run `dart test` in `packages/nimbus_data/`. From the repo root: `dart analyze --fatal-infos`. Expected: green.

- [ ] **Step 8: Commit and merge**

```bash
git add packages/nimbus_data/lib packages/nimbus_data/test/backup
git commit -m "$(cat <<'EOF'
feat(backup): export the database as one encrypted file

The WAL is the whole problem: recent writes live in the -wal file, and
copying only the .sqlite file loses the newest, most valuable data.
VACUUM INTO writes a consistent single-file snapshot that already holds
every committed WAL frame, without touching the live file and while the
widget's drain engine stays connected, so it replaces the brief's
checkpoint-then-copy. The test writes a row, never closes the
connection, exports and finds the row. The plaintext snapshot is
deleted in finally, even when the export fails. A newer schema is
refused from the header alone, before anyone types a passphrase.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only feat/backup-export
```

---

### Task 4: Prepare a restore — decrypt, migrate, check — and the golden file

Slug: `backup-prepare`. Spec §2.4, §3.2 step 2, §7 (the golden fixture, an older schema, and wrong passphrase vs corruption). Ruling R8.

**Files:**
- Modify: `packages/nimbus_data/lib/src/backup/backup_service.dart`
- Create: `packages/nimbus_data/tool/make_backup_fixture.dart`
- Create: `packages/nimbus_data/test/fixtures/backup_v1.nimbus` (generated)
- Test: `packages/nimbus_data/test/backup/backup_prepare_test.dart`

**Interfaces:**
- Consumes: Task 3's `BackupService` and `BackupFixture`.
- Produces:
  - `final class PreparedRestore({required String path, required DateTime createdAt})`.
  - `Future<PreparedRestore> BackupService.prepare(String path, String passphrase)`.
  - `Future<void> BackupService.discard(PreparedRestore)`.

- [ ] **Step 1: Branch**

```bash
git checkout -b feat/backup-prepare phase/7-backup
```

- [ ] **Step 2: Write the failing test**

Create `packages/nimbus_data/test/backup/backup_prepare_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:drift_dev/api/migrations_native.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../generated/schema.dart';
import 'support/backup_fixture.dart';

void main() {
  late BackupFixture f;
  setUp(() => f = BackupFixture.open());
  tearDown(() => f.close());

  Future<String> exported() async {
    final out = f.path('out.nimbus');
    await f.service.exportTo(out, 'correct horse');
    return out;
  }

  /// Seals [database]'s bytes under a header claiming [schemaVersion].
  Future<String> sealAs(String database, int schemaVersion) async {
    final out = f.path('sealed.nimbus');
    File(out).writeAsBytesSync(await sealBackup(
      payload: gzip.encode(File(database).readAsBytesSync()),
      passphrase: 'correct horse',
      schemaVersion: schemaVersion,
      createdAt: DateTime.utc(2025),
      kdf: fastKdf,
    ));
    return out;
  }

  /// One value from a prepared file, read without the app's migrations.
  Object? read(PreparedRestore prepared, String sql) {
    final db = sqlite3.open(prepared.path, mode: OpenMode.readOnly);
    try {
      return db.select(sql).single.values.first;
    } finally {
      db.close();
    }
  }

  test('the golden v1 file still restores (format compatibility)', () async {
    // Never regenerated: a change that stops this file from opening has
    // broken every backup users already have.
    const fixture = 'test/fixtures/backup_v1.nimbus';
    final header = await f.service.readHeader(fixture);
    expect(header.createdAt, DateTime.utc(2026, 10, 17, 12));
    expect(header.kdf,
        const KdfParams(memoryKiB: 1024, iterations: 1, parallelism: 1));

    // Sealed as 'رمز-پشتیبان-۱۴۰۵'; typed here on an Arabic keyboard with
    // Latin digits.
    final prepared = await f.service.prepare(fixture, 'رمز-پشتيبان-1405');
    addTearDown(() => f.service.discard(prepared));
    expect(prepared.createdAt, DateTime.utc(2026, 10, 17, 12));
    expect(read(prepared, "SELECT value FROM settings WHERE key = 'fixture'"),
        'golden v1');
    expect(read(prepared, 'PRAGMA user_version'), f.db.schemaVersion);
  });

  test("an older backup migrates to today's schema (v32)", () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final v32 = await verifier.schemaAt(32);
    addTearDown(v32.close);
    v32.rawDatabase
      ..execute('PRAGMA user_version = 32')
      ..execute("INSERT INTO settings (key, value) VALUES ('from', 'v32')")
      ..execute('VACUUM INTO ?', [f.path('v32.sqlite')]);

    final prepared =
        await f.service.prepare(await sealAs(f.path('v32.sqlite'), 32), 'correct horse');
    addTearDown(() => f.service.discard(prepared));
    expect(read(prepared, 'PRAGMA user_version'), f.db.schemaVersion);
    expect(read(prepared, "SELECT value FROM settings WHERE key = 'from'"), 'v32');
  });

  test('discard deletes the prepared file', () async {
    final prepared = await f.service.prepare(await exported(), 'correct horse');
    await f.service.discard(prepared);
    expect(File(prepared.path).existsSync(), isFalse);
  });

  group('a file that must not restore leaves nothing behind', () {
    Future<void> refused(String file, Matcher error,
        [String passphrase = 'correct horse']) async {
      await expectLater(f.service.prepare(file, passphrase), throwsA(error));
      expect(f.cacheFiles(), isEmpty);
    }

    test('a wrong passphrase', () async {
      await refused(await exported(), isA<WrongPassphrase>(), 'correct horse?');
    });

    test('a flipped ciphertext byte', () async {
      final out = await exported();
      final bytes = File(out).readAsBytesSync();
      bytes[bytes.length - 40] ^= 0x01;
      File(out).writeAsBytesSync(bytes);
      await refused(out, isA<CorruptBackup>());
    });

    test('a file cut in half', () async {
      final out = await exported();
      final bytes = File(out).readAsBytesSync();
      File(out).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      await refused(out, isA<CorruptBackup>());
    });

    test('a payload that is not gzip', () async {
      final out = f.path('bad.nimbus');
      File(out).writeAsBytesSync(await sealBackup(
        payload: utf8.encode('not gzip'),
        passphrase: 'correct horse',
        schemaVersion: f.db.schemaVersion,
        createdAt: DateTime.utc(2026),
        kdf: fastKdf,
      ));
      await refused(out, isA<CorruptBackup>());
    });

    test('a payload that is not a database', () async {
      File(f.path('hello.txt')).writeAsStringSync('hello');
      await refused(await sealAs(f.path('hello.txt'), f.db.schemaVersion),
          isA<CorruptBackup>());
    });

    test('a payload whose schema differs from its header', () async {
      await f.db.customStatement('VACUUM INTO ?', [f.path('snap.sqlite')]);
      await refused(await sealAs(f.path('snap.sqlite'), f.db.schemaVersion - 1),
          isA<CorruptBackup>());
    });

    test('a database with another page size', () async {
      sqlite3.open(f.path('odd.sqlite'))
        ..execute('PRAGMA page_size = 8192')
        ..execute('CREATE TABLE t (x)')
        ..execute('PRAGMA user_version = ${f.db.schemaVersion}')
        ..close();
      await refused(await sealAs(f.path('odd.sqlite'), f.db.schemaVersion),
          isA<CorruptBackup>());
    });
  });
}
```

- [ ] **Step 3: Run it and see RED**

Run from `packages/nimbus_data/`: `dart test test/backup/backup_prepare_test.dart`. Expected: compile errors, because `prepare`, `discard` and `PreparedRestore` are undefined.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-backup-prepare phase/7-backup
```

- [ ] **Step 5: Add `prepare` and `discard`**

In `backup_service.dart`, add above `class BackupService`:

```dart
/// A decrypted, migrated and checked backup, waiting in the cache for
/// [BackupService.restore] (spec §3.2).
final class PreparedRestore {
  const PreparedRestore({required this.path, required this.createdAt});

  final String path;

  /// When the backup was made, for the restore sheet and its snackbar.
  final DateTime createdAt;
}
```

Inside `BackupService`, after `readHeader`, add:

```dart
  /// Decrypts [path] into the cache, brings it to today's schema and checks
  /// it. The live database is not touched (spec §3.2).
  ///
  /// On any failure the decrypted file is deleted before the error leaves.
  Future<PreparedRestore> prepare(String path, String passphrase) async {
    final header = await readHeader(path);
    final temp = _temp('import');
    try {
      await _unseal(path, temp, passphrase);
      await _migrateAndCheck(temp);
      return PreparedRestore(path: temp, createdAt: header.createdAt);
    } on Object {
      await _deleteDatabase(temp);
      rethrow;
    }
  }

  /// Deletes a prepared file the user decided not to restore.
  Future<void> discard(PreparedRestore prepared) =>
      _deleteDatabase(prepared.path);

  /// Opens [path] once through [AppDatabase.openAtPath], so an older backup
  /// runs the same migrations every install runs, and then checks it.
  ///
  /// A failure while opening or migrating is left as it is (ruling R8). The
  /// content passed authentication, so such a failure is a bug, not damage.
  /// In debug builds drift warns about a second AppDatabase. This one has its
  /// own file and executor, which is not the race that warning is about.
  Future<void> _migrateAndCheck(String path) async {
    final imported = AppDatabase.openAtPath(path);
    try {
      final check = await imported.customSelect('PRAGMA integrity_check').get();
      if (check.length != 1 || check.single.data.values.single != 'ok') {
        throw const CorruptBackup('integrity check failed');
      }
      // SQLite's backup cannot copy into a WAL database of another page size.
      if (await _pragma(imported, 'page_size') != await _pragma(_db, 'page_size')) {
        throw const CorruptBackup('page size differs');
      }
    } finally {
      await imported.close();
    }
  }

  static Future<int> _pragma(AppDatabase db, String name) async =>
      (await db.customSelect('PRAGMA $name').getSingle()).data.values.single
          as int;

  static Future<void> _deleteDatabase(String path) async {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      await _delete('$path$suffix');
    }
  }
```

At the end of the file, add:

```dart
/// Opens the backup at [backupPath] and writes its database to [outPath], in
/// an isolate (spec §3.2).
///
/// Throws [WrongPassphrase] or [CorruptBackup] before writing anything.
Future<void> _unseal(String backupPath, String outPath, String passphrase) =>
    Isolate.run(() async {
      // shortcut: whole file in memory, upgrade to chunked encryption when a database passes ~50 MB
      final file = File(backupPath).readAsBytesSync();
      final payload = await openBackup(file, passphrase);
      final List<int> plain;
      try {
        plain = gzip.decode(payload);
      } on FormatException {
        throw const CorruptBackup('payload is not gzip');
      }
      if (!_isSqlite(plain) ||
          _userVersion(plain) != BackupHeader.decode(file).schemaVersion) {
        throw const CorruptBackup('payload does not match its header');
      }
      File(outPath).writeAsBytesSync(plain, flush: true);
    });

bool _isSqlite(List<int> bytes) =>
    bytes.length >= 100 &&
    String.fromCharCodes(bytes.sublist(0, 16)) == 'SQLite format 3\u0000';
```

- [ ] **Step 6: Generate the golden file**

Create `packages/nimbus_data/tool/make_backup_fixture.dart`:

```dart
import 'dart:io';

import 'package:nimbus_data/nimbus_data.dart';

/// Writes `test/fixtures/backup_v1.nimbus`, the golden file every later build
/// must keep restoring (Phase 7 spec §7).
///
/// Run it once per format version, from `packages/nimbus_data`:
/// `dart run tool/make_backup_fixture.dart`. Never regenerate v1. A new
/// format version gets a new fixture beside it, and v1 keeps its test.
Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('nimbus_fixture');
  try {
    final db = AppDatabase.openAtPath('${dir.path}/live.sqlite');
    try {
      await db.settingsDao.put('fixture', 'golden v1');
      await BackupService(
        db: db,
        cacheDir: '${dir.path}/cache',
        kdf: const KdfParams(memoryKiB: 1024, iterations: 1, parallelism: 1),
        clock: () => DateTime.utc(2026, 10, 17, 12),
      ).exportTo('test/fixtures/backup_v1.nimbus', 'رمز-پشتیبان-۱۴۰۵');
    } finally {
      await db.close();
    }
  } finally {
    dir.deleteSync(recursive: true);
  }
}
```

Run from `packages/nimbus_data/`:

```bash
mkdir -p test/fixtures && dart run tool/make_backup_fixture.dart && ls -l test/fixtures/backup_v1.nimbus
```

Expected: the file exists and is a few kilobytes to a few tens of kilobytes.

- [ ] **Step 7: Run it and see GREEN**

Run from `packages/nimbus_data/`: `dart test test/backup/backup_prepare_test.dart`. Expected: all pass.

If "a database with another page size" fails with a `SqliteException` instead of `CorruptBackup`, stop and report it rather than widening a catch. Ruling R8 depends on which step fails.

- [ ] **Step 8: Run the broader suite**

Run `dart test` in `packages/nimbus_data/`. From the repo root: `dart analyze --fatal-infos`. Expected: green.

- [ ] **Step 9: Commit and merge**

```bash
git add packages/nimbus_data/lib packages/nimbus_data/tool packages/nimbus_data/test/fixtures packages/nimbus_data/test/backup/backup_prepare_test.dart
git commit -m "$(cat <<'EOF'
feat(backup): decrypt, migrate and check a backup before it touches anything

A restore must be all or nothing, so everything that can fail happens
first, on a copy in the cache. The decrypted file is opened once
through AppDatabase.openAtPath, so a v32 backup arrives at today's
schema through the same migrations every install runs. It is then
checked: integrity_check, and the page size SQLite's backup needs. A
wrong passphrase and a damaged file stay distinct errors, and none of
them leaves plaintext behind.

The golden v1 file is committed with the tool that wrote it. If it
ever stops restoring, every backup users already hold is broken, and
CI says so first. Its passphrase was typed in Persian digits and the
test types it in Latin ones, which pins normalisation too.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only feat/backup-prepare
```

---

### Task 5: The atomic swap, undo, sweep and size

Slug: `backup-restore`. Spec §3.2 steps 3–4, §3.3, §4.3, and the §7 tests (WAL round trip, interrupted restore, `local_date_key`, no key material). Rulings R1, R4, R7.

**Files:**
- Modify: `packages/nimbus_data/lib/src/backup/backup_service.dart`
- Modify: `packages/nimbus_data/test/backup/support/backup_fixture.dart`
- Test: `packages/nimbus_data/test/backup/backup_restore_test.dart`

**Interfaces:**
- Consumes: Task 4's `prepare` and `PreparedRestore`.
- Produces:
  - Three new constructor parameters: `required String livePath`, `required String preRestorePath` and `Duration busyTimeout = const Duration(seconds: 5)`.
  - `Future<void> restore(PreparedRestore)`.
  - `Future<void> undo()`.
  - `bool get canUndo`.
  - `Future<int> databaseBytes()`.
  - `Future<void> sweep()`.

- [ ] **Step 1: Branch, and give the fixture its new paths**

```bash
git checkout -b feat/backup-restore phase/7-backup
```

In `backup_fixture.dart`, replace the `BackupService(…)` construction inside `BackupFixture.open` with:

```dart
      BackupService(
        db: db,
        livePath: at('nimbustats.sqlite'),
        cacheDir: at('cache'),
        preRestorePath: at('nimbustats.pre-restore.sqlite'),
        kdf: fastKdf,
        clock: clock ?? DateTime.now,
        busyTimeout: busyTimeout,
      ),
```

Change the factory's signature to `factory BackupFixture.open({DateTime Function()? clock, Duration busyTimeout = const Duration(seconds: 5)})`. Below `livePath`, add:

```dart
  String get preRestorePath => path('nimbustats.pre-restore.sqlite');
```

- [ ] **Step 2: Write the failing test**

Create `packages/nimbus_data/test/backup/backup_restore_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/backup_fixture.dart';

void main() {
  late BackupFixture source; // the phone that exported
  late BackupFixture target; // the phone that restores
  setUp(() {
    source = BackupFixture.open();
    target = BackupFixture.open(busyTimeout: const Duration(milliseconds: 100));
  });
  tearDown(() async {
    await source.close();
    await target.close();
  });

  /// Exports [from] and prepares the file on [to].
  Future<PreparedRestore> carry(BackupFixture from, BackupFixture to) async {
    final out = from.path('out.nimbus');
    await from.service.exportTo(out, 'correct horse');
    return to.service.prepare(out, 'correct horse');
  }

  Future<Object?> pragma(AppDatabase db, String name) async =>
      (await db.customSelect('PRAGMA $name').getSingle()).data.values.single;

  test('written, exported and restored into a fresh install: the row is there '
      '(the brief DoD, on the host)', () async {
    final id = await source.addExpense(); // never checkpointed, never closed
    await target.db.settingsDao.get('open'); // a fresh install: schema only

    await target.service.restore(await carry(source, target));

    expect(await target.db.transactionsDao.byId(id), isNotNull);
    expect(await pragma(target.db, 'journal_mode'), 'wal');
    expect(await pragma(target.db, 'integrity_check'), 'ok');
  });

  test("open streams on the live database see the restored rows", () async {
    await source.db.settingsDao.put('who', 'backup');
    await target.db.settingsDao.put('who', 'original');
    final seen = expectLater(
        target.db.settingsDao.watchAll().map((all) => all['who']),
        emitsThrough('backup'));

    await target.service.restore(await carry(source, target));
    await seen;
  });

  test('local_date_key travels with the data, whatever the zone', () async {
    // Stamped two days after its UTC instant. No zone on Earth computes that,
    // so a restore that recomputed keys could not reproduce it.
    final id = await source.addExpense(
      occurredAtUtc: DateTime.utc(2026, 3, 20, 12),
      on: DateKey.fromParts(2026, 3, 22),
    );
    await target.service.restore(await carry(source, target));
    expect((await target.db.transactionsDao.byId(id))!.localDateKey,
        DateKey.fromParts(2026, 3, 22));
  });

  group('undo', () {
    test('puts back what the restore replaced, once', () async {
      await source.db.settingsDao.put('who', 'backup');
      await target.db.settingsDao.put('who', 'original');
      expect(target.service.canUndo, isFalse);

      await target.service.restore(await carry(source, target));
      expect(target.service.canUndo, isTrue);

      await target.service.undo();
      expect(await target.db.settingsDao.get('who'), 'original');
      expect(target.service.canUndo, isFalse);
    });

    test('a second restore replaces the copy: undo goes back one step',
        () async {
      await target.db.settingsDao.put('who', 'original');
      await source.db.settingsDao.put('who', 'first');
      await target.service.restore(await carry(source, target));
      await source.db.settingsDao.put('who', 'second');
      await target.service.restore(await carry(source, target));

      await target.service.undo();
      expect(await target.db.settingsDao.get('who'), 'first');
    });
  });

  group('a restore that fails midway leaves the live database as it was', () {
    setUp(() => target.db.settingsDao.put('who', 'original'));

    Future<void> expectUntouched() async {
      expect(await target.db.settingsDao.get('who'), 'original');
      expect(await pragma(target.db, 'integrity_check'), 'ok');
      expect(target.service.canUndo, isFalse);
      expect(File('${target.preRestorePath}.part').existsSync(), isFalse);
    }

    test('the swap itself fails: SQLite refuses another page size (R1)',
        () async {
      // prepare() refuses this file, so it is built by hand to reach the
      // backup step, which SQLite rejects before writing a page.
      sqlite3.open(target.path('odd.sqlite'))
        ..execute('PRAGMA page_size = 8192')
        ..execute('CREATE TABLE t (x)')
        ..close();
      final prepared = PreparedRestore(
          path: target.path('odd.sqlite'), createdAt: DateTime.utc(2026));

      await expectLater(
          target.service.restore(prepared), throwsA(isA<SqliteException>()));
      await expectUntouched();
      expect(File(prepared.path).existsSync(), isFalse);
    });

    test('the undo copy cannot be written (R4)', () async {
      Directory('${target.preRestorePath}.part').createSync();
      final prepared = await carry(source, target);

      await expectLater(
          target.service.restore(prepared), throwsA(isA<SqliteException>()));
      expect(await target.db.settingsDao.get('who'), 'original');
      expect(target.service.canUndo, isFalse);
      expect(File(prepared.path).existsSync(), isFalse);
    });

    test('a failed restore keeps the previous undo copy (R4)', () async {
      await source.db.settingsDao.put('who', 'first');
      await target.service.restore(await carry(source, target));
      sqlite3.open(target.path('odd.sqlite'))
        ..execute('PRAGMA page_size = 8192')
        ..execute('CREATE TABLE t (x)')
        ..close();

      await expectLater(
          target.service.restore(PreparedRestore(
              path: target.path('odd.sqlite'), createdAt: DateTime.utc(2026))),
          throwsA(isA<SqliteException>()));
      await target.service.undo();
      expect(await target.db.settingsDao.get('who'), 'original');
    });
  });

  test('a writer holding the lock delays the swap, which then lands whole (R1)',
      () async {
    await source.db.settingsDao.put('who', 'backup');
    await target.db.settingsDao.put('who', 'original');
    final prepared = await carry(source, target);
    // The drain engine mid-write, on its own connection.
    final writer = sqlite3.open(target.livePath)..execute('BEGIN IMMEDIATE');

    final restoring = target.service.restore(prepared);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    writer
      ..execute('COMMIT')
      ..close();
    await restoring;

    expect(await target.db.settingsDao.get('who'), 'backup');
  });

  test('databaseBytes is the file Auto Backup copies after its checkpoint',
      () async {
    await target.addExpense();
    await target.db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    expect(await target.service.databaseBytes(),
        File(target.livePath).lengthSync());
  });

  test('sweep deletes stale plaintext and picked copies, and only those',
      () async {
    final cache = Directory(target.service.cacheDir)..createSync(recursive: true);
    for (final name in const [
      'export-a.sqlite',
      'import-b.sqlite',
      'import-b.sqlite-wal',
      'picked-c.nimbus',
      'notes.txt',
    ]) {
      File('${cache.path}/$name').writeAsStringSync('x');
    }
    Directory('${cache.path}/out').createSync();
    File('${cache.path}/out/nimbustats-20261017-0930.nimbus').writeAsStringSync('x');
    File('${target.preRestorePath}.part').writeAsStringSync('x');

    await target.service.sweep();

    expect(target.cacheFiles()..sort(), ['notes.txt', 'out']);
    expect(File('${cache.path}/out/nimbustats-20261017-0930.nimbus').existsSync(),
        isTrue);
    expect(File('${target.preRestorePath}.part').existsSync(), isFalse);
  });

  test('no passphrase or derived byte reaches a print, an error or a toString',
      () async {
    const passphrase = 'hygiene-passphrase-7042';
    final printed = <String>[];
    final errors = <String>[];
    final out = source.path('out.nimbus');

    await runZoned(
      () async {
        await source.addExpense();
        await source.service.exportTo(out, passphrase);
        final damaged = source.path('damaged.nimbus');
        final bytes = File(out).readAsBytesSync();
        File(damaged).writeAsBytesSync(bytes..[bytes.length - 40] ^= 0x01);
        for (final (file, typed) in [(out, 'not-$passphrase'), (damaged, passphrase)]) {
          try {
            await target.service.prepare(file, typed);
          } on Object catch (error, stack) {
            errors
              ..add('$error')
              ..add('$stack');
          }
        }
        await target.service.restore(await target.service.prepare(out, passphrase));
      },
      zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line)),
    );

    final header = BackupHeader.decode(File(out).readAsBytesSync());
    final keys = await deriveBackupKeys(passphrase, header.kdf, header.salt);
    String hex(List<int> bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final secrets = [
      passphrase,
      normalizePassphrase(passphrase),
      for (final bytes in [keys.check, await keys.encryption.extractBytes()]) ...[
        bytes.toString(),
        hex(bytes),
        base64.encode(bytes),
      ],
    ];
    expect(errors, hasLength(4)); // both failures happened, message and stack
    for (final text in [...printed, ...errors]) {
      for (final secret in secrets) {
        expect(text, isNot(contains(secret)));
      }
    }
  });
}
```

- [ ] **Step 3: Run it and see RED**

Run from `packages/nimbus_data/`: `dart test test/backup/backup_restore_test.dart`. Expected: compile errors, because `livePath`, `preRestorePath`, `busyTimeout`, `restore`, `undo`, `canUndo`, `databaseBytes` and `sweep` are undefined.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-backup-restore phase/7-backup
```

- [ ] **Step 5: Add the swap, undo, sweep and size**

In `backup_service.dart`, add the imports:

```dart
import 'package:drift/drift.dart' show TableUpdate;
import 'package:sqlite3/sqlite3.dart';
```

Replace the constructor and fields with:

```dart
  BackupService({
    required AppDatabase db,
    required String livePath,
    required this.cacheDir,
    required String preRestorePath,
    KdfParams kdf = KdfParams.standard,
    DateTime Function() clock = DateTime.now,
    Duration busyTimeout = const Duration(seconds: 5),
  })  : _db = db,
        _livePath = livePath,
        _preRestorePath = preRestorePath,
        _kdf = kdf,
        _clock = clock,
        _busyTimeout = busyTimeout;

  final AppDatabase _db;
  final String _livePath;
  final String _preRestorePath;
  final KdfParams _kdf;
  final DateTime Function() _clock;

  /// How long the swap waits each time for a writer, such as the widget's
  /// drain engine, to release the database. Five seconds, the same as every
  /// connection `AppDatabase.openAtPath` makes.
  final Duration _busyTimeout;

  /// Where plaintext temp files live. Android leaves the cache out of Auto
  /// Backup.
  final String cacheDir;

  static const _uuid = Uuid();
  static const _tempPrefixes = ['export-', 'import-', 'picked-'];

  /// The undo copy while it is being written. It is renamed into place only
  /// after a swap succeeds (ruling R4).
  String get _partPath => '$_preRestorePath.part';

  /// Whether an undo copy exists: the last restore can be undone.
  bool get canUndo => File(_preRestorePath).existsSync();
```

After `discard`, add:

```dart
  /// Swaps [prepared]'s content into the live database (spec §3.2 step 3).
  ///
  /// First the live content is copied aside for undo. The swap is SQLite's
  /// online backup, one write transaction that commits whole or rolls back,
  /// so the drain engine's connection never sees half of it. Only a swap that
  /// happened replaces the previous undo copy.
  Future<void> restore(PreparedRestore prepared) async {
    try {
      await _delete(_partPath);
      await _db.customStatement('VACUUM INTO ?', [_partPath]);
      await _copyInto(prepared.path);
    } on Object {
      await _delete(_partPath);
      rethrow;
    } finally {
      await _deleteDatabase(prepared.path);
    }
    await File(_partPath).rename(_preRestorePath);
    _notifyAll();
  }

  /// Puts back what the last restore replaced, and spends the undo copy.
  Future<void> undo() async {
    await _copyInto(_preRestorePath);
    await File(_preRestorePath).delete();
    _notifyAll();
  }

  /// The database's size as Auto Backup will copy it, after the agent's
  /// checkpoint has emptied the WAL into the file (spec §4.3).
  Future<int> databaseBytes() async =>
      await _pragma(_db, 'page_count') * await _pragma(_db, 'page_size');

  /// Deletes plaintext a crash left behind mid-export or mid-restore (spec
  /// §3.3). Finished exports in `out/` stay: a share target may still be
  /// reading the latest.
  Future<void> sweep() async {
    final dir = Directory(cacheDir);
    if (dir.existsSync()) {
      for (final file in dir.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (_tempPrefixes.any(name.startsWith)) await file.delete();
      }
    }
    await _delete(_partPath);
  }

  /// SQLite's online backup from [source] onto the live file.
  ///
  /// `sqlite3` retries a busy lock every 250 ms until it gets it. With
  /// `nPage: -1` it writes nothing before then, so a concurrent writer delays
  /// the swap and never splits it (ruling R1).
  Future<void> _copyInto(String source) async {
    final from = sqlite3.open(source, mode: OpenMode.readOnly);
    try {
      final to = sqlite3.open(_livePath);
      try {
        to.execute('PRAGMA busy_timeout = ${_busyTimeout.inMilliseconds}');
        await from.backup(to, nPage: -1).drain<void>();
      } finally {
        to.close();
      }
    } finally {
      from.close();
    }
  }

  /// Every table changed underneath drift. Its open streams re-read, and
  /// none keeps a cached value from before the swap.
  void _notifyAll() => _db.notifyUpdates(
      {for (final table in _db.allTables) TableUpdate.onTable(table)});
```

- [ ] **Step 6: Run it and see GREEN**

Run from `packages/nimbus_data/`: `dart test test/backup/`. Expected: every backup test passes, including Tasks 3 and 4 under the new constructor.

If "the undo copy cannot be written" throws something other than `SqliteException`, report the actual type. Do not widen the matcher until the failing step is understood.

- [ ] **Step 7: Run the broader suite**

Run `dart test` in `packages/nimbus_data/`. From the repo root: `dart analyze --fatal-infos` and `dart test test/architecture_test.dart`. Expected: green.

- [ ] **Step 8: Commit and merge**

```bash
git add packages/nimbus_data/lib packages/nimbus_data/test/backup
git commit -m "$(cat <<'EOF'
feat(backup): swap a backup in atomically, with one step of undo

A file rename under the drain engine's open handle would send its
writes to an unlinked inode and lose them silently. So the swap is
SQLite's online backup, one write transaction that commits whole or
rolls back while the other connection waits on its busy timeout. The
live content is copied aside first, written as .part and renamed only
after a swap succeeds. A failed restore therefore keeps the previous
undo copy, and a half-written copy is never offered (ruling R4).

sqlite3's backup retries a busy lock forever and writes nothing until
it holds it, so the spec's "short busy timeout makes it fail" test
cannot exist (ruling R1). The failures that can happen are tested
instead: a swap SQLite refuses, an undo copy that cannot be written,
and a writer that delays the swap, which then lands whole. The brief's
WAL round trip, local_date_key travelling unchanged, and a sweep of
stale plaintext are tested too, as is a guard that no passphrase or
derived byte reaches a print, an error or a toString.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only feat/backup-restore
```

---

### Task 6: Android Auto Backup — rules, and the WAL checkpoint at backup time

Slug: `auto-backup`. Spec §4.1, §4.2. Brief task 7. Ruling R4 (the `.part` exclude).

**Files:**
- Create: `app/android/app/src/main/res/xml/backup_rules.xml`
- Create: `app/android/app/src/main/res/xml/data_extraction_rules.xml`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/backup/NimbusBackupAgent.kt`
- Modify: `app/android/app/src/main/AndroidManifest.xml` (`<application>` attributes)
- Test: `app/test/features/backup/android_wiring_test.dart`

**Interfaces:**
- Produces:
  - The excluded paths `app_flutter/nimbustats.sqlite-shm`, `app_flutter/nimbustats.pre-restore.sqlite` and `app_flutter/nimbustats.pre-restore.sqlite.part`.
  - The agent class `.backup.NimbusBackupAgent`.

- [ ] **Step 1: Branch, and write the failing test**

```bash
git checkout -b feat/auto-backup phase/7-backup
```

Create `app/test/features/backup/android_wiring_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android files no host test can run (spec §4.1), pinned as text. The
/// two rule files must never drift apart, and an `<include>` would silently
/// turn every other file off.
void main() {
  const res = 'android/app/src/main/res/xml';
  const excluded = {
    'app_flutter/nimbustats.sqlite-shm',
    'app_flutter/nimbustats.pre-restore.sqlite',
    'app_flutter/nimbustats.pre-restore.sqlite.part',
  };

  Set<String> excludes(String xml) =>
      RegExp(r'<exclude domain="root" path="([^"]+)"')
          .allMatches(xml)
          .map((match) => match[1]!)
          .toSet();

  String section(String xml, String tag) =>
      RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml)![1]!;

  test('both rule files exclude exactly the local-only files', () {
    final legacy = File('$res/backup_rules.xml').readAsStringSync();
    final modern = File('$res/data_extraction_rules.xml').readAsStringSync();

    expect(excludes(legacy), excluded);
    expect(excludes(section(modern, 'cloud-backup')), excluded);
    expect(excludes(section(modern, 'device-transfer')), excluded);
    expect('$legacy$modern', isNot(contains('<include')));
  });

  test('the manifest wires the agent and both rule files', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    for (final attribute in const [
      'android:allowBackup="true"',
      'android:fullBackupOnly="true"',
      'android:backupAgent=".backup.NimbusBackupAgent"',
      'android:fullBackupContent="@xml/backup_rules"',
      'android:dataExtractionRules="@xml/data_extraction_rules"',
    ]) {
      expect(manifest, contains(attribute));
    }
  });
}
```

- [ ] **Step 2: Run it and see RED**

Run from `app/`: `flutter test --no-pub test/features/backup/android_wiring_test.dart`. Expected: FAIL with `PathNotFoundException` for `backup_rules.xml`.

- [ ] **Step 3: Tag the parent**

```bash
git tag pre-auto-backup phase/7-backup
```

- [ ] **Step 4: Write the rules**

Create `app/android/app/src/main/res/xml/backup_rules.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- Auto Backup on Android 8–11 (Phase 7 spec §4.1). Exclude-only: everything
     else in the app's data is kept. That is the database, its WAL (emptied
     by NimbusBackupAgent first), the widget's pending buffer, the reminder
     prefs and backup_state.json. Keep in step with data_extraction_rules.xml;
     android_wiring_test checks. -->
<full-backup-content>
    <!-- Rebuilt by SQLite on open. -->
    <exclude domain="root" path="app_flutter/nimbustats.sqlite-shm" />
    <!-- The local undo copy, and the copy being written. -->
    <exclude domain="root" path="app_flutter/nimbustats.pre-restore.sqlite" />
    <exclude domain="root" path="app_flutter/nimbustats.pre-restore.sqlite.part" />
</full-backup-content>
```

Create `app/android/app/src/main/res/xml/data_extraction_rules.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- Auto Backup and device-to-device transfer on Android 12+ (Phase 7 spec
     §4.1). The same exclusions as backup_rules.xml. -->
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="root" path="app_flutter/nimbustats.sqlite-shm" />
        <exclude domain="root" path="app_flutter/nimbustats.pre-restore.sqlite" />
        <exclude domain="root" path="app_flutter/nimbustats.pre-restore.sqlite.part" />
    </cloud-backup>
    <device-transfer>
        <exclude domain="root" path="app_flutter/nimbustats.sqlite-shm" />
        <exclude domain="root" path="app_flutter/nimbustats.pre-restore.sqlite" />
        <exclude domain="root" path="app_flutter/nimbustats.pre-restore.sqlite.part" />
    </device-transfer>
</data-extraction-rules>
```

- [ ] **Step 5: Write the agent**

Create `app/android/app/src/main/kotlin/com/nimbustats/app/backup/NimbusBackupAgent.kt`:

```kotlin
package com.nimbustats.app.backup

import android.app.backup.BackupAgentHelper
import android.app.backup.FullBackupDataOutput
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import java.io.File

/**
 * Checkpoints the WAL before Auto Backup copies the app's files (Phase 7 spec §4.2).
 *
 * In WAL mode the newest writes live in `nimbustats.sqlite-wal`. A TRUNCATE checkpoint moves
 * them into the database file and empties the WAL, so the copy holds them in one place. `super`
 * then applies the XML rules. Key/value backup is off (`fullBackupOnly`), so the helper's own
 * key/value methods never run.
 */
class NimbusBackupAgent : BackupAgentHelper() {
    override fun onFullBackup(data: FullBackupDataOutput) {
        checkpoint()
        super.onFullBackup(data)
    }

    private fun checkpoint() {
        // Flutter's getApplicationDocumentsDirectory() is this app_flutter directory.
        val file = File(getDir("flutter", Context.MODE_PRIVATE), "nimbustats.sqlite")
        if (!file.exists()) return
        try {
            // NO_LOCALIZED_COLLATORS: without it, Android adds an android_metadata table to our file.
            SQLiteDatabase.openDatabase(
                file.path,
                null,
                SQLiteDatabase.OPEN_READWRITE or
                    SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING or
                    SQLiteDatabase.NO_LOCALIZED_COLLATORS,
            ).use { db ->
                // The pragma answers one row (busy, WAL frames, frames moved), so it is a query.
                db.rawQuery("PRAGMA wal_checkpoint(TRUNCATE)", null).use { row ->
                    if (row.moveToFirst() && row.getInt(0) != 0) {
                        Log.e(TAG, "WAL checkpoint before backup was blocked; the WAL is backed up with the file")
                    }
                }
            }
        } catch (error: Exception) {
            // The approved trade-off (spec §4.2): Android has stopped the app, so the file and its
            // WAL are a consistent pair that SQLite recovers on open. Skipping the backup would
            // trade a small risk for a certain loss.
            Log.e(TAG, "WAL checkpoint before backup failed; backing up as is", error)
        }
    }
}
```

- [ ] **Step 6: Wire the manifest**

In `app/android/app/src/main/AndroidManifest.xml`, replace the opening `<application …>` tag with:

```xml
    <!-- Phase 7: Auto Backup, with the WAL checkpointed first by
         NimbusBackupAgent, and the rules in res/xml (spec §4). -->
    <application
        android:label="nimbustats"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="true"
        android:fullBackupOnly="true"
        android:backupAgent=".backup.NimbusBackupAgent"
        android:fullBackupContent="@xml/backup_rules"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:supportsRtl="true">
```

- [ ] **Step 7: Run it and see GREEN, then build**

Run from `app/`:
- `flutter test --no-pub test/features/backup/android_wiring_test.dart`. Expected: PASS.
- `flutter build apk --debug`. Expected: `Built build\app\outputs\flutter-apk\app-debug.apk`.

A Kotlin compile error is fixed here, not deferred.

- [ ] **Step 8: Run the broader suite**

Run the App suite, then `dart analyze --fatal-infos` from the root. Expected: green.

- [ ] **Step 9: Commit and merge**

```bash
git add app/android/app/src/main/res/xml/backup_rules.xml app/android/app/src/main/res/xml/data_extraction_rules.xml app/android/app/src/main/kotlin/com/nimbustats/app/backup/NimbusBackupAgent.kt app/android/app/src/main/AndroidManifest.xml app/test/features/backup/android_wiring_test.dart
git commit -m "$(cat <<'EOF'
feat(backup): Auto Backup copies a checkpointed database

With no rules, Auto Backup already copied the whole data directory,
WAL included. A database and a WAL copied at different instants can
disagree. The agent checkpoints with TRUNCATE first, so the copy holds
every write in the database file. It opens with NO_LOCALIZED_COLLATORS,
or Android would add an android_metadata table to our file. If the
checkpoint fails it logs and backs up anyway: Android has stopped the
app, so the pair on disk is consistent, and skipping would be a certain
loss (the trade-off approved in spec §4.2). The shm file and the local
undo copy stay out; the rule files are pinned against drifting apart.
Verified on device in Task 14.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only feat/auto-backup
```

---

### Task 7: The backup channel — Save, Share, Open

Slug: `backup-channel`. Spec §6. Ruling R5.

**Files:**
- Create: `app/lib/features/backup/data/backup_channel.dart`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/backup/BackupDocuments.kt`
- Create: `app/android/app/src/main/res/xml/backup_file_paths.xml`
- Modify: `app/android/app/src/main/kotlin/com/nimbustats/app/MainActivity.kt`
- Modify: `app/android/app/src/main/AndroidManifest.xml` (the `<provider>`)
- Test: `app/test/features/backup/backup_channel_test.dart`
- Test: `app/test/features/backup/android_wiring_test.dart` (one more test)

**Interfaces:**
- Produces:
  - `class BackupChannel([MethodChannel?])`, with `static const name = 'com.nimbustats.app/backup'`.
  - `Future<bool> saveDocument(String path)`.
  - `Future<void> shareFile(String path)`.
  - `Future<String?> openDocument()`.
  - `final backupChannelProvider = Provider<BackupChannel>`.
  - Native writes picked files to `<cacheDir>/backup/picked-<uuid>.nimbus`.

- [ ] **Step 1: Branch, and write the failing tests**

```bash
git checkout -b feat/backup-channel phase/7-backup
```

Create `app/test/features/backup/backup_channel_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbustats/features/backup/data/backup_channel.dart';

/// The Dart half of spec §6, against a mocked platform side.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const platform = MethodChannel(BackupChannel.name);

  late List<MethodCall> calls;
  late Object? Function(MethodCall) reply;

  setUp(() {
    calls = [];
    reply = (_) => null;
    messenger.setMockMethodCallHandler(platform, (call) async {
      calls.add(call);
      return reply(call);
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(platform, null));

  test('saveDocument sends the path and answers saved or cancelled', () async {
    reply = (_) => true;
    expect(await BackupChannel().saveDocument('/c/backup/out/a.nimbus'), isTrue);
    reply = (_) => false;
    expect(await BackupChannel().saveDocument('/c/backup/out/a.nimbus'), isFalse);
    for (final call in calls) {
      expect(call.method, 'saveDocument');
      expect(call.arguments, {'path': '/c/backup/out/a.nimbus'});
    }
  });

  test('a null answer to saveDocument is a bug to see, not a cancel',
      () async {
    await expectLater(BackupChannel().saveDocument('/x'),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'null-reply')));
  });

  test('shareFile sends the path', () async {
    await BackupChannel().shareFile('/c/backup/out/a.nimbus');
    expect(calls.single.method, 'shareFile');
    expect(calls.single.arguments, {'path': '/c/backup/out/a.nimbus'});
  });

  test('openDocument answers the cache copy, or null when cancelled',
      () async {
    reply = (_) => '/c/backup/picked-1.nimbus';
    expect(await BackupChannel().openDocument(), '/c/backup/picked-1.nimbus');
    reply = (_) => null;
    expect(await BackupChannel().openDocument(), isNull);
  });

  test('a native failure arrives as a PlatformException', () async {
    messenger.setMockMethodCallHandler(platform,
        (call) async => throw PlatformException(code: 'io', message: 'IOException'));
    await expectLater(BackupChannel().openDocument(),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'io')));
  });
}
```

In `app/test/features/backup/android_wiring_test.dart`, add inside `main()`:

```dart
  test('FileProvider serves only finished exports (R5)', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:authorities="\${applicationId}.backup"'));
    expect(manifest, contains('android:resource="@xml/backup_file_paths"'));
    final paths = File('$res/backup_file_paths.xml').readAsStringSync();
    expect(RegExp(r'<(\w+-path)').allMatches(paths).map((m) => m[1]),
        ['cache-path']);
    expect(paths, contains('path="backup/out/"'));
  });
```

- [ ] **Step 2: Run them and see RED**

Run from `app/`: `flutter test --no-pub test/features/backup/`. Expected:
- `backup_channel_test` fails to compile, because `BackupChannel` is undefined.
- The FileProvider test fails, because the manifest lacks the authority.

- [ ] **Step 3: Tag the parent**

```bash
git tag pre-backup-channel phase/7-backup
```

- [ ] **Step 4: Write the Dart channel**

Create `app/lib/features/backup/data/backup_channel.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dart's half of `com.nimbustats.app/backup` (Phase 7 spec §6): Save to…,
/// Share… and opening a file, all through Android's own pickers.
///
/// Every test replaces it with `FakeBackupChannel`. An I/O failure arrives as
/// a [PlatformException], never as a quiet null.
class BackupChannel {
  BackupChannel([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel(name);

  static const name = 'com.nimbustats.app/backup';

  final MethodChannel _channel;

  /// Copies [path] into a document the user creates. False when they
  /// cancelled the picker.
  Future<bool> saveDocument(String path) async {
    final saved =
        await _channel.invokeMethod<bool>('saveDocument', {'path': path});
    if (saved == null) {
      throw PlatformException(
          code: 'null-reply', message: 'saveDocument answered null');
    }
    return saved;
  }

  /// Opens the share sheet on [path], which must be in the cache's
  /// `backup/out/` folder: the only one `FileProvider` serves.
  Future<void> shareFile(String path) =>
      _channel.invokeMethod<void>('shareFile', {'path': path});

  /// The file the user picked, copied into the cache. Null when they
  /// cancelled.
  Future<String?> openDocument() =>
      _channel.invokeMethod<String>('openDocument');
}

final backupChannelProvider = Provider<BackupChannel>((ref) => BackupChannel());
```

- [ ] **Step 5: Write the native side**

Create `app/android/app/src/main/res/xml/backup_file_paths.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- What the backup FileProvider may serve (Phase 7, ruling R5): finished,
     encrypted exports only, never the plaintext temp files beside them. -->
<paths>
    <cache-path name="backup" path="backup/out/" />
</paths>
```

Create `app/android/app/src/main/kotlin/com/nimbustats/app/backup/BackupDocuments.kt`:

```kotlin
package com.nimbustats.app.backup

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.FileProvider
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

/**
 * The native half of `com.nimbustats.app/backup` (Phase 7 spec §6).
 *
 * Save goes through the Storage Access Framework, and Share through the share sheet. Open copies
 * the picked file into the cache, where Dart reads it. The Dart flow is modal, so one picker
 * waits at a time. Every I/O failure reaches Dart as an error reply.
 */
class BackupDocuments(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private class Waiting(val request: Int, val result: MethodChannel.Result, val source: File?)

    private var waiting: Waiting? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveDocument" -> save(File(call.argument<String>("path")!!), result)
            "shareFile" -> share(File(call.argument<String>("path")!!), result)
            "openDocument" -> open(result)
            else -> result.notImplemented()
        }
    }

    private fun save(source: File, result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(MIME)
            .putExtra(Intent.EXTRA_TITLE, source.name)
        start(Waiting(REQUEST_SAVE, result, source), intent)
    }

    private fun share(file: File, result: MethodChannel.Result) {
        // backup_file_paths.xml serves cache/backup/out/ only. Any other path throws here, and
        // the channel returns that to Dart as an error.
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.backup", file)
        val send = Intent(Intent.ACTION_SEND)
            .setType(MIME)
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        // The chooser passes the read grant on only through ClipData.
        send.clipData = ClipData.newRawUri(file.name, uri)
        activity.startActivity(Intent.createChooser(send, null))
        result.success(null)
    }

    private fun open(result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
        start(Waiting(REQUEST_OPEN, result, null), intent)
    }

    private fun start(next: Waiting, intent: Intent) {
        if (waiting != null) {
            next.result.error("busy", "a backup picker is already open", null)
            return
        }
        waiting = next
        activity.startActivityForResult(intent, next.request)
    }

    /** MainActivity hands over every activity result. True when it was one of ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val done = waiting?.takeIf { it.request == requestCode } ?: return false
        waiting = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            // A cancelled picker is not an error (spec §5.2).
            done.result.success(if (requestCode == REQUEST_SAVE) false else null)
            return true
        }
        io.execute {
            try {
                val reply: Any = if (requestCode == REQUEST_SAVE) {
                    copyOut(done.source!!, uri)
                    true
                } else {
                    copyIn(uri)
                }
                main.post { done.result.success(reply) }
            } catch (error: Exception) {
                Log.e(TAG, "backup document copy failed", error)
                main.post { done.result.error("io", error.javaClass.simpleName, null) }
            }
        }
        return true
    }

    private fun copyOut(source: File, target: Uri) {
        // "wt" truncates, so saving over a longer old file leaves no tail of it.
        val out = activity.contentResolver.openOutputStream(target, "wt")
            ?: throw IOException("no output stream")
        out.use { stream -> source.inputStream().use { it.copyTo(stream) } }
    }

    private fun copyIn(source: Uri): String {
        val dir = File(activity.cacheDir, "backup").apply { mkdirs() }
        val target = File(dir, "picked-${UUID.randomUUID()}.nimbus")
        val input = activity.contentResolver.openInputStream(source)
            ?: throw IOException("no input stream")
        input.use { stream -> target.outputStream().use { stream.copyTo(it) } }
        return target.path
    }

    companion object {
        const val CHANNEL = "com.nimbustats.app/backup"
        private const val MIME = "application/octet-stream"
        private const val REQUEST_SAVE = 7_100
        private const val REQUEST_OPEN = 7_101
    }
}
```

In `MainActivity.kt`:
- Add `import com.nimbustats.app.backup.BackupDocuments`.
- Below `private val permissionResults …`, add:

```kotlin
    /** Phase 7's Save, Share and Open. Null while there is no engine. */
    private var backupDocuments: BackupDocuments? = null
```

At the end of `configureFlutterEngine`, after `OutsideChannelHandler.appChannel = channel`, add:

```kotlin
        // Phase 7: the backup channel (spec §6).
        val documents = BackupDocuments(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BackupDocuments.CHANNEL)
            .setMethodCallHandler(documents)
        backupDocuments = documents
```

In `cleanUpFlutterEngine`, before `super.cleanUpFlutterEngine(flutterEngine)`, add `backupDocuments = null`. After `onNewIntent`, add:

```kotlin
    /** A backup picker's answer goes to BackupDocuments; anything else to Flutter's plugins. */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (backupDocuments?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
```

If the compiler warns "overrides deprecated member", add `@Deprecated("Deprecated in Java")` above the override, and nothing else.

In `AndroidManifest.xml`, before the `flutterEmbedding` `<meta-data>`, add:

```xml
        <!-- Phase 7: Share… serves finished exports through this provider
             only (spec §6, ruling R5). -->
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.backup"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/backup_file_paths" />
        </provider>
```

- [ ] **Step 6: Run them and see GREEN, then build**

Run from `app/`:
- `flutter test --no-pub test/features/backup/`. Expected: PASS.
- `flutter build apk --debug`. Expected: built. An unresolved `androidx.core.content.FileProvider` means the classpath finding changed. Stop and report it; do not add a dependency.

- [ ] **Step 7: Run the broader suite**

Run the App suite and `dart analyze --fatal-infos`. Expected: green.

- [ ] **Step 8: Commit and merge**

```bash
git add app/lib/features/backup/data/backup_channel.dart app/android/app/src/main app/test/features/backup
git commit -m "$(cat <<'EOF'
feat(backup): save, share and open backup files through Android's pickers

The plugins that do this (file_picker, share_plus) do not resolve
offline, so a small channel does it with framework intents: SAF to
create a document, the share sheet through a FileProvider, and SAF to
open one, which is copied into the cache for Dart. The provider serves
cache/backup/out/ only, so the plaintext temp files beside it can never
be shared. A cancelled picker answers false or null, which is not an
error. A failed copy is logged and returned as an error reply, never
swallowed. Arguments are just the path, because the file's name is
already the path's own (ruling R5). Verified on device in Task 14.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only feat/backup-channel
```

---

### Task 8: `AppRestart` — rebuild every provider over the same database

Slug: `app-restart`. Spec §5.3, ruling R3.

**Files:**
- Create: `app/lib/features/backup/application/restart.dart`
- Create: `app/lib/features/backup/presentation/app_restart.dart`
- Modify: `app/lib/main.dart`
- Test: `app/test/features/backup/app_restart_test.dart`

**Interfaces:**
- Produces:
  - `sealed class RestartNotice`, with `BackupRestored(DateTime backupCreatedAt)` and `RestoreUndone()`.
  - `final appRestartProvider = Provider<void Function(RestartNotice notice)>`. It throws unless overridden.
  - `final restartNoticeProvider = Provider<RestartNotice?>`, null by default.
  - `class AppRestart({required List<Override> overrides, required Widget child})`.

- [ ] **Step 1: Branch, and write the failing test**

```bash
git checkout -b feat/app-restart phase/7-backup
```

Create `app/test/features/backup/app_restart_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbustats/features/backup/application/restart.dart';
import 'package:nimbustats/features/backup/presentation/app_restart.dart';

void main() {
  testWidgets(
      'a restart disposes the old scope before the new one builds (R3), '
      'and hands the new one its notice', (tester) async {
    final log = <String>[];
    var created = 0;
    final probe = Provider<int>((ref) {
      final generation = created++;
      log.add('create $generation');
      ref.onDispose(() => log.add('dispose $generation'));
      return generation;
    });
    late void Function(RestartNotice) restart;

    await tester.pumpWidget(AppRestart(
      overrides: const [],
      child: Consumer(builder: (context, ref, _) {
        restart = ref.read(appRestartProvider);
        final generation = ref.watch(probe);
        final notice = ref.watch(restartNoticeProvider);
        return Text('$generation ${notice.runtimeType}',
            textDirection: TextDirection.ltr);
      }),
    ));
    expect(find.text('0 Null'), findsOneWidget);

    restart(const RestoreUndone());
    await tester.pump();
    // The frame in between: the old scope is gone and the new one is not
    // built yet. Phase 6's channel handler is cleared before it is re-set.
    expect(log, ['create 0', 'dispose 0']);

    await tester.pump();
    expect(log, ['create 0', 'dispose 0', 'create 1']);
    expect(find.text('1 RestoreUndone'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it and see RED**

Run from `app/`: `flutter test --no-pub test/features/backup/app_restart_test.dart`. Expected: compile errors, because `AppRestart` and `RestartNotice` are undefined.

- [ ] **Step 3: Tag the parent**

```bash
git tag pre-app-restart phase/7-backup
```

- [ ] **Step 4: Write the providers**

Create `app/lib/features/backup/application/restart.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Why the app restarted, for the snackbar over Home (spec §5.3).
sealed class RestartNotice {
  const RestartNotice();
}

final class BackupRestored extends RestartNotice {
  const BackupRestored(this.backupCreatedAt);

  final DateTime backupCreatedAt;
}

final class RestoreUndone extends RestartNotice {
  const RestoreUndone();
}

/// Rebuilds every provider over the same database, whose content a restore
/// just replaced in place.
///
/// `AppRestart` provides it. Reading it without that is a wiring bug, and
/// it throws, like `appDatabaseProvider`.
final appRestartProvider = Provider<void Function(RestartNotice notice)>(
  (ref) => throw StateError(
      'appRestartProvider was read without being overridden; AppRestart '
      'provides it.'),
);

/// The notice the current scope started with. Null on an ordinary start.
final restartNoticeProvider = Provider<RestartNotice?>((ref) => null);
```

- [ ] **Step 5: Write `AppRestart`**

Create `app/lib/features/backup/presentation/app_restart.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 keeps Override out of the main barrel.
import 'package:flutter_riverpod/misc.dart';

import '../../../bootstrap/provider_retry.dart';
import '../application/restart.dart';

/// The root of the running app: one [ProviderScope] that a restore can
/// replace with a fresh one (spec §5.3).
///
/// The `AppDatabase` stays the same object, and its file's content changed
/// in place. Every provider, the router included, starts again. So does
/// whatever the shell does at start, Phase 6's reminder push and widget
/// snapshot among it.
class AppRestart extends StatefulWidget {
  const AppRestart({super.key, required this.overrides, required this.child});

  final List<Override> overrides;
  final Widget child;

  @override
  State<AppRestart> createState() => _AppRestartState();
}

class _AppRestartState extends State<AppRestart> {
  var _generation = 0;
  var _between = false;
  RestartNotice? _notice;

  void _restart(RestartNotice notice) {
    // Two frames (ruling R3): the old scope is disposed before the new one
    // builds. Phase 6's OutsideChannel clears the channel's shared handler
    // when disposed. Disposed after the new scope had set its own, it would
    // silence every native call for the rest of the run.
    setState(() {
      _between = true;
      _notice = notice;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _between = false;
        _generation++;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_between) return const SizedBox.shrink();
    return ProviderScope(
      key: ValueKey(_generation),
      retry: nimbusNoRetry,
      overrides: [
        ...widget.overrides,
        appRestartProvider.overrideWithValue(_restart),
        restartNoticeProvider.overrideWithValue(_notice),
      ],
      child: widget.child,
    );
  }
}
```

- [ ] **Step 6: Root the app on it**

In `app/lib/main.dart`:
- Remove the imports `package:flutter_riverpod/flutter_riverpod.dart` and `bootstrap/provider_retry.dart`.
- Add `import 'features/backup/presentation/app_restart.dart';`.
- Replace the `runApp(…)` call with:

```dart
  // Phase 7: the one ProviderScope lives inside AppRestart, which a restore
  // rebuilds over the same database (spec §5.3).
  runApp(AppRestart(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const NimbuStatsApp(),
  ));
```

- [ ] **Step 7: Run it and see GREEN**

Run from `app/`: `flutter test --no-pub test/features/backup/app_restart_test.dart`. Expected: PASS.

- [ ] **Step 8: Run the broader suite**

Run the App suite and `dart analyze --fatal-infos`. Expected: green, with no unused import.

- [ ] **Step 9: Commit and merge**

```bash
git add app/lib/features/backup/application/restart.dart app/lib/features/backup/presentation/app_restart.dart app/lib/main.dart app/test/features/backup/app_restart_test.dart
git commit -m "$(cat <<'EOF'
feat(backup): a root that a restore can restart

A restore replaces the database's content in place. Every provider
still holds answers from the old content, and the router and the
shell's start-up work (Phase 6's reminder push and widget snapshot)
must run again. A keyed ProviderScope rebuilds all of it over the same
AppDatabase object. It takes two frames, not one (ruling R3): Phase 6's
OutsideChannel clears the shared channel handler when disposed, and a
plain key swap disposes the old scope after the new one has set its
own, which would silence widget taps and notification routes for the
rest of the run. The test pins dispose before create.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only feat/app-restart
```

---

### Task 9: State store, providers, controller, and the test fakes

Slug: `backup-controller`. Spec §5.1, §5.2, §5.3. Rulings R9, R13.

**Files:**
- Create: `app/lib/features/backup/data/backup_state_store.dart`
- Create: `app/lib/features/backup/application/backup_providers.dart`
- Create: `app/lib/features/backup/application/backup_controller.dart`
- Modify: `app/lib/main.dart`
- Create: `app/test/features/backup/support/fake_backup_service.dart`
- Create: `app/test/features/backup/support/fake_backup_channel.dart`
- Modify: `app/test/support/harness.dart`
- Test: `app/test/features/backup/backup_state_store_test.dart`
- Test: `app/test/features/backup/backup_controller_test.dart`

**Interfaces:**
- Consumes: Task 5's `BackupService` and Task 7's `BackupChannel`/`backupChannelProvider`. From Task 8: `appRestartProvider`, `BackupRestored` and `RestoreUndone`.
- Produces:
  - `class BackupStateStore(String path)`, with `DateTime? lastExport()` and `void recordExport(DateTime at)`.
  - `databaseFileProvider` (a `Provider<String>` that throws unless overridden).
  - `backupServiceProvider` (a `FutureProvider<BackupService>`).
  - `backupStateStoreProvider`.
  - `typedef BackupStatus = ({DateTime? lastExport, bool canUndo, int databaseBytes})`.
  - `backupStatusProvider` (a `FutureProvider<BackupStatus>`).
  - `const autoBackupWarnBytes = 20 * 1024 * 1024`.
  - `typedef PickedBackup = ({String path, BackupHeader header})`.
  - `final class BackupController(Ref)`, with:
    - `sweep()`;
    - `export(String passphrase)` → path;
    - `save(String path)` → bool;
    - `share(String path)`;
    - `pick()` → `PickedBackup?`;
    - `restore(PickedBackup, String passphrase)`;
    - `void discard(String path)`, synchronous;
    - `undo()`.
  - `backupControllerProvider`.
  - The test fakes `FakeBackupService` and `FakeBackupChannel`.
  - `pumpApp` gains `BackupService? backup`, `BackupChannel? backupChannel` and `BackupStateStore? backupState`.

- [ ] **Step 1: Branch, and write the fakes**

```bash
git checkout -b feat/backup-controller phase/7-backup
```

Create `app/test/features/backup/support/fake_backup_service.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nimbus_data/nimbus_data.dart';

/// [BackupService] without files or crypto: it records each call and plays
/// the outcome a test sets.
class FakeBackupService implements BackupService {
  /// The passphrase [prepare] accepts; any other is [WrongPassphrase].
  static const goodPassphrase = 'correct horse';

  final calls = <String>[];
  String? lastPassphrase;

  Object? exportError;

  /// Holds [exportTo] open until completed, to test the working state.
  Completer<void>? exportGate;
  Object? headerError;
  Object? prepareError;
  Object? undoError;
  bool undoable = false;
  int bytes = 4 * 1024 * 1024;
  BackupHeader header = BackupHeader(
    schemaVersion: 40,
    createdAt: DateTime.utc(2026, 10, 1, 9, 30),
    kdf: KdfParams.standard,
    salt: Uint8List(16),
    nonce: Uint8List(12),
    keyCheck: Uint8List(16),
  );

  @override
  late final String cacheDir =
      Directory.systemTemp.createTempSync('nimbus_fake_backup').path;

  @override
  bool get canUndo => undoable;

  @override
  Future<int> databaseBytes() async => bytes;

  @override
  Future<void> sweep() async => calls.add('sweep');

  @override
  Future<void> exportTo(String outPath, String passphrase) async {
    calls.add('exportTo');
    lastPassphrase = passphrase;
    await exportGate?.future;
    if (exportError case final error?) throw error;
    File(outPath).writeAsBytesSync(const [1, 2, 3]);
  }

  @override
  Future<BackupHeader> readHeader(String path) async {
    calls.add('readHeader');
    if (headerError case final error?) throw error;
    return header;
  }

  @override
  Future<PreparedRestore> prepare(String path, String passphrase) async {
    calls.add('prepare');
    if (passphrase != goodPassphrase) throw const WrongPassphrase();
    if (prepareError case final error?) throw error;
    return PreparedRestore(path: path, createdAt: header.createdAt);
  }

  @override
  Future<void> restore(PreparedRestore prepared) async {
    calls.add('restore');
    undoable = true;
  }

  @override
  Future<void> undo() async {
    calls.add('undo');
    if (undoError case final error?) throw error;
    undoable = false;
  }

  @override
  Future<void> discard(PreparedRestore prepared) async => calls.add('discard');
}
```

Create `app/test/features/backup/support/fake_backup_channel.dart`:

```dart
import 'package:nimbustats/features/backup/data/backup_channel.dart';

/// [BackupChannel] without Android: records each call and answers as a test
/// sets.
class FakeBackupChannel implements BackupChannel {
  final calls = <String>[];

  /// What Save's picker answers: true saved, false cancelled.
  bool saveAnswer = true;

  /// The cache copy Open answers with. Null is a cancelled picker.
  String? picked;

  /// Thrown by the next call, then cleared.
  Object? error;

  @override
  Future<bool> saveDocument(String path) async {
    calls.add('saveDocument $path');
    _fail();
    return saveAnswer;
  }

  @override
  Future<void> shareFile(String path) async {
    calls.add('shareFile $path');
    _fail();
  }

  @override
  Future<String?> openDocument() async {
    calls.add('openDocument');
    _fail();
    return picked;
  }

  void _fail() {
    final failure = error;
    if (failure == null) return;
    error = null;
    throw failure;
  }
}
```

- [ ] **Step 2: Write the failing tests**

Create `app/test/features/backup/backup_state_store_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimbustats/features/backup/data/backup_state_store.dart';

void main() {
  late Directory dir;
  late BackupStateStore store;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('nimbus_backup_state');
    store = BackupStateStore('${dir.path}/backup_state.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('nothing recorded reads as never exported', () {
    expect(store.lastExport(), isNull);
  });

  test('a recorded export reads back to the millisecond, in UTC', () {
    final at = DateTime.utc(2026, 10, 17, 9, 30, 15, 250);
    store.recordExport(at);
    expect(store.lastExport(), at);
    expect(store.lastExport()!.isUtc, isTrue);
  });

  test('a later export replaces the earlier one', () {
    store
      ..recordExport(DateTime.utc(2026, 1, 1))
      ..recordExport(DateTime.utc(2026, 2, 1));
    expect(store.lastExport(), DateTime.utc(2026, 2, 1));
  });

  test('a file that does not parse is an error, not "never"', () {
    File('${dir.path}/backup_state.json').writeAsStringSync('{"v":1');
    expect(store.lastExport, throwsFormatException);
  });

  test('an unknown version is an error', () {
    File('${dir.path}/backup_state.json')
        .writeAsStringSync('{"v":2,"lastExportUtcMs":1}');
    expect(store.lastExport, throwsFormatException);
  });
}
```

Create `app/test/features/backup/backup_controller_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/backup/application/backup_controller.dart';
import 'package:nimbustats/features/backup/application/backup_providers.dart';
import 'package:nimbustats/features/backup/application/restart.dart';
import 'package:nimbustats/features/backup/data/backup_channel.dart';
import 'package:nimbustats/features/backup/data/backup_state_store.dart';

import 'support/fake_backup_channel.dart';
import 'support/fake_backup_service.dart';

void main() {
  late FakeBackupService service;
  late FakeBackupChannel channel;
  late Directory dir;
  late BackupStateStore store;
  late List<RestartNotice> restarts;
  late ProviderContainer container;

  setUp(() {
    service = FakeBackupService();
    channel = FakeBackupChannel();
    dir = Directory.systemTemp.createTempSync('nimbus_backup_controller');
    store = BackupStateStore('${dir.path}/backup_state.json');
    restarts = [];
    container = ProviderContainer(overrides: [
      backupServiceProvider.overrideWith((ref) async => service),
      backupChannelProvider.overrideWithValue(channel),
      backupStateStoreProvider.overrideWithValue(store),
      appRestartProvider.overrideWithValue(restarts.add),
    ]);
  });
  tearDown(() {
    container.dispose();
    dir.deleteSync(recursive: true);
  });

  BackupController controller() => container.read(backupControllerProvider);

  String pickedFile() {
    final path = '${dir.path}/picked-1.nimbus';
    File(path).writeAsBytesSync(const [1]);
    return path;
  }

  test('export writes one file, named by local time, in the cache out/ folder',
      () async {
    final first = await controller().export('correct horse');
    final second = await controller().export('correct horse');

    expect(File(second).parent.path, '${service.cacheDir}${Platform.pathSeparator}out');
    expect(File(second).uri.pathSegments.last,
        matches(RegExp(r'^nimbustats-\d{8}-\d{4}\.nimbus$')));
    // Only the latest is kept for Share.
    expect(File(second).parent.listSync(), hasLength(1));
    expect(first == second || !File(first).existsSync(), isTrue);
  });

  test('a saved export is recorded; a cancelled one is not (R9)', () async {
    channel.saveAnswer = false;
    expect(await controller().save('/x.nimbus'), isFalse);
    expect(store.lastExport(), isNull);

    channel.saveAnswer = true;
    expect(await controller().save('/x.nimbus'), isTrue);
    expect(store.lastExport(), isNotNull);
  });

  test('opening the share sheet is recorded as an export', () async {
    await controller().share('/x.nimbus');
    expect(channel.calls, ['shareFile /x.nimbus']);
    expect(store.lastExport(), isNotNull);
  });

  group('pick', () {
    test('a cancelled picker is null', () async {
      expect(await controller().pick(), isNull);
    });

    test('reads the header of the copy', () async {
      channel.picked = pickedFile();
      final picked = await controller().pick();
      expect(picked!.path, channel.picked);
      expect(picked.header.createdAt, service.header.createdAt);
    });

    test('a header error deletes the copy and rethrows', () async {
      channel.picked = pickedFile();
      service.headerError = const NotABackup();
      await expectLater(controller().pick(), throwsA(isA<NotABackup>()));
      expect(File(channel.picked!).existsSync(), isFalse);
    });
  });

  group('restore', () {
    test('a wrong passphrase keeps the copy and does not restart', () async {
      channel.picked = pickedFile();
      final picked = (await controller().pick())!;
      await expectLater(controller().restore(picked, 'wrong'),
          throwsA(isA<WrongPassphrase>()));
      expect(File(picked.path).existsSync(), isTrue);
      expect(restarts, isEmpty);
    });

    test('swaps, deletes the copy and restarts with the backup date', () async {
      channel.picked = pickedFile();
      final picked = (await controller().pick())!;
      await controller().restore(picked, FakeBackupService.goodPassphrase);

      expect(service.calls, containsAllInOrder(['prepare', 'restore']));
      expect(File(picked.path).existsSync(), isFalse);
      expect(
          restarts.single,
          isA<BackupRestored>().having(
              (n) => n.backupCreatedAt, 'createdAt', service.header.createdAt));
    });
  });

  test('undo restores and restarts saying so', () async {
    await controller().undo();
    expect(service.calls, ['undo']);
    expect(restarts.single, isA<RestoreUndone>());
  });

  test('the status combines the store and the service', () async {
    store.recordExport(DateTime.utc(2026, 10, 17));
    service
      ..undoable = true
      ..bytes = 123;
    final status = await container.read(backupStatusProvider.future);
    expect(status.lastExport, DateTime.utc(2026, 10, 17));
    expect(status.canUndo, isTrue);
    expect(status.databaseBytes, 123);
  });
}
```

- [ ] **Step 3: Run them and see RED**

Run from `app/`: `flutter test --no-pub test/features/backup/backup_state_store_test.dart test/features/backup/backup_controller_test.dart`. Expected: compile errors, because `BackupStateStore`, `backupServiceProvider` and `BackupController` are undefined.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-backup-controller phase/7-backup
```

- [ ] **Step 5: Write the store**

Create `app/lib/features/backup/data/backup_state_store.dart`:

```dart
import 'dart:convert';
import 'dart:io';

/// `backup_state.json`: when the last export was handed to Save or Share
/// (spec §5.1, ruling R9).
///
/// It lives outside the database, so restoring an old backup cannot rewind
/// it. It is synchronous: one tiny file, read when the section opens.
class BackupStateStore {
  BackupStateStore(this._path);

  final String _path;

  static const _version = 1;

  /// Null when nothing was ever exported. A file that does not read is a
  /// [FormatException], never "never".
  DateTime? lastExport() {
    final file = File(_path);
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map<String, Object?> ||
        json['v'] != _version ||
        json['lastExportUtcMs'] is! int) {
      throw FormatException('unreadable backup state', _path);
    }
    return DateTime.fromMillisecondsSinceEpoch(
        json['lastExportUtcMs']! as int,
        isUtc: true);
  }

  /// Written to a temp file and renamed over the old one, so a crash leaves
  /// the old file whole.
  void recordExport(DateTime at) {
    File('$_path.tmp')
      ..writeAsStringSync(
          jsonEncode({'v': _version, 'lastExportUtcMs': at.millisecondsSinceEpoch}),
          flush: true)
      ..renameSync(_path);
  }
}
```

- [ ] **Step 6: Write the providers**

Create `app/lib/features/backup/application/backup_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../bootstrap/database_provider.dart';
import '../data/backup_state_store.dart';

/// The live database file. `main` overrides it with the path it opened.
///
/// Reading it without the override is a bootstrap bug, so it throws, like
/// [appDatabaseProvider].
final databaseFileProvider = Provider<String>(
  (ref) => throw StateError(
      'databaseFileProvider was read without being overridden; main() '
      'overrides it with the path it opened.'),
);

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final live = ref.watch(databaseFileProvider);
  final cache = await getTemporaryDirectory();
  return BackupService(
    db: ref.watch(appDatabaseProvider),
    livePath: live,
    cacheDir: p.join(cache.path, 'backup'),
    preRestorePath: p.join(p.dirname(live), 'nimbustats.pre-restore.sqlite'),
  );
});

final backupStateStoreProvider = Provider<BackupStateStore>((ref) =>
    BackupStateStore(
        p.join(p.dirname(ref.watch(databaseFileProvider)), 'backup_state.json')));

/// What the backup section shows (spec §5.1).
typedef BackupStatus = ({
  DateTime? lastExport,
  bool canUndo,
  int databaseBytes,
});

final backupStatusProvider = FutureProvider<BackupStatus>((ref) async {
  final service = await ref.watch(backupServiceProvider.future);
  return (
    lastExport: ref.watch(backupStateStoreProvider).lastExport(),
    canUndo: service.canUndo,
    databaseBytes: await service.databaseBytes(),
  );
});

/// Above this, the section warns that Auto Backup's 25 MB cap is near
/// (spec §4.3, ruling R7; measured in docs/DEVELOPMENT.md).
const autoBackupWarnBytes = 20 * 1024 * 1024;
```

- [ ] **Step 7: Write the controller**

Create `app/lib/features/backup/application/backup_controller.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:path/path.dart' as p;

import '../data/backup_channel.dart';
import 'backup_providers.dart';
import 'restart.dart';

/// A backup the user picked for restore: copied into the cache, its header
/// read.
typedef PickedBackup = ({String path, BackupHeader header});

/// The backup section's actions (spec §5).
///
/// Each one throws what went wrong. The sheets map the error to a message.
final class BackupController {
  BackupController(this._ref);

  final Ref _ref;

  Future<BackupService> get _service => _ref.read(backupServiceProvider.future);
  BackupChannel get _channel => _ref.read(backupChannelProvider);

  /// Deletes plaintext a crash left in the cache (spec §3.3).
  Future<void> sweep() async => (await _service).sweep();

  /// A fresh export in the cache's `out/` folder, the one Share may serve.
  /// Only the latest is kept.
  Future<String> export(String passphrase) async {
    final service = await _service;
    final out = Directory(p.join(service.cacheDir, 'out'));
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);
    final path = p.join(out.path, backupFileName(DateTime.now()));
    await service.exportTo(path, passphrase);
    return path;
  }

  /// False when the user cancelled the picker, which is not an error.
  Future<bool> save(String path) async {
    final saved = await _channel.saveDocument(path);
    if (saved) _recordExport();
    return saved;
  }

  Future<void> share(String path) async {
    await _channel.shareFile(path);
    _recordExport();
  }

  /// Null when the picker was cancelled. A header error (not a backup, a
  /// newer schema…) deletes the copy and rethrows.
  Future<PickedBackup?> pick() async {
    final path = await _channel.openDocument();
    if (path == null) return null;
    try {
      return (path: path, header: await (await _service).readHeader(path));
    } on Object {
      discard(path);
      rethrow;
    }
  }

  /// Decrypts, checks and swaps in [picked], then restarts the app onto it.
  ///
  /// [WrongPassphrase] keeps the copy, so the sheet can ask again.
  Future<void> restore(PickedBackup picked, String passphrase) async {
    final service = await _service;
    final prepared = await service.prepare(picked.path, passphrase);
    await service.restore(prepared);
    discard(picked.path);
    _ref.read(appRestartProvider)(BackupRestored(picked.header.createdAt));
  }

  /// Deletes a picked copy that will not be restored.
  ///
  /// Synchronous: one small file. An async delete would also never complete
  /// inside a widget test's fake clock.
  void discard(String picked) {
    final file = File(picked);
    if (file.existsSync()) file.deleteSync();
  }

  Future<void> undo() async {
    await (await _service).undo();
    _ref.read(appRestartProvider)(const RestoreUndone());
  }

  void _recordExport() {
    _ref.read(backupStateStoreProvider).recordExport(DateTime.now().toUtc());
    _ref.invalidate(backupStatusProvider);
  }
}

final backupControllerProvider =
    Provider<BackupController>(BackupController.new);
```

- [ ] **Step 8: Wire `main` and the harness**

In `app/lib/main.dart`, replace the two lines that open the database with:

```dart
  final path = p.join(dir.path, 'nimbustats.sqlite');
  final db = AppDatabase.openAtPath(path);
```

Add `import 'features/backup/application/backup_providers.dart';`. Make `AppRestart`'s overrides:

```dart
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      databaseFileProvider.overrideWithValue(path),
    ],
```

In `app/test/support/harness.dart`, add these imports:

```dart
import 'dart:io';

import 'package:nimbustats/features/backup/application/backup_providers.dart';
import 'package:nimbustats/features/backup/data/backup_channel.dart';
import 'package:nimbustats/features/backup/data/backup_state_store.dart';

import '../features/backup/support/fake_backup_channel.dart';
import '../features/backup/support/fake_backup_service.dart';
```

Add these parameters to `pumpApp`, after `OutsideChannel? outside,`:

```dart
  BackupService? backup,
  BackupChannel? backupChannel,
  BackupStateStore? backupState,
```

In the container's overrides, after the `outsideChannelProvider` line, add:

```dart
    // No files and no Android in a widget test (Phase 7, ruling R13). Every
    // settings test builds the backup section. A test about backup passes
    // its own fakes to read what was asked.
    backupServiceProvider.overrideWith((ref) async => backup ?? FakeBackupService()),
    backupChannelProvider.overrideWithValue(backupChannel ?? FakeBackupChannel()),
    backupStateStoreProvider.overrideWithValue(backupState ?? _tempBackupState()),
```

At the end of the file, add:

```dart
/// A backup state file in a temp folder this test deletes.
BackupStateStore _tempBackupState() {
  final dir = Directory.systemTemp.createTempSync('nimbus_backup_state');
  addTearDown(() => dir.deleteSync(recursive: true));
  return BackupStateStore('${dir.path}/backup_state.json');
}
```

- [ ] **Step 9: Run them and see GREEN**

Run from `app/`: `flutter test --no-pub test/features/backup/`. Expected: all pass.

- [ ] **Step 10: Run the broader suite**

Run the App suite and `dart analyze --fatal-infos`. Expected: green.

- [ ] **Step 11: Commit and merge**

```bash
git add app/lib/features/backup app/lib/main.dart app/test/support/harness.dart app/test/features/backup
git commit -m "$(cat <<'EOF'
feat(backup): the backup section's actions and state

The controller owns each flow's order: export into the one folder
Share may serve, hand off, record; pick, read the header, prepare,
swap, restart. Each failure is left to the sheet that shows it. A
header error deletes the picked copy at once, and a wrong passphrase
keeps it, so the user can try again without picking the file twice.
The last export's time lives in backup_state.json, outside the
database, so restoring an old backup cannot rewind it. It is recorded
on hand-off, which is all the app can know (ruling R9). The widget
test harness gains backup fakes (ruling R13). Every settings test now
builds the section, and none should reach the file system or Android.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only feat/backup-controller
```

---

### Task 10: The Backup section in Settings, and its strings

Slug: `backup-section`. Spec §5.1, §5.4, ruling R7.

**Files:**
- Modify: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_fa.arb` (every `backup…` key of the phase)
- Create: `app/lib/features/backup/presentation/backup_messages.dart`
- Create: `app/lib/features/backup/presentation/backup_section.dart`
- Create: `app/lib/features/backup/presentation/export_sheet.dart` (a stub, filled in by Task 11)
- Create: `app/lib/features/backup/presentation/restore_sheet.dart` (a stub, filled in by Task 12)
- Modify: `app/lib/features/settings/presentation/settings_screen.dart`
- Create: `app/test/features/backup/support/gregorian_english.dart`
- Test: `app/test/features/backup/backup_messages_test.dart`
- Test: `app/test/features/backup/backup_section_test.dart`

**Interfaces:**
- Consumes: Task 9's `backupStatusProvider`, `backupControllerProvider`, `autoBackupWarnBytes` and `PickedBackup`.
- Produces for the later tests: `Future<void> useGregorianEnglish(AppDatabase db)` in `test/features/backup/support/gregorian_english.dart`.
- Produces:
  - `String? backupErrorText(AppLocalizations, Object error)`.
  - `void reportBackupFailure(Object error, StackTrace stack, String context)`.
  - `String whenLabel(DateTime moment, AppCalendar calendar, {required bool persianDigits})`.
  - `class BackupSection`.
  - `class ExportSheet` and `class RestoreSheet({required PickedBackup picked})`, as stubs to be completed.
  - The keys `backup-section`, `backup-loading`, `backup-error`, `backup-last-export`, `backup-size-warning`, `backup-export`, `backup-restore` and `backup-undo`.

- [ ] **Step 1: Branch, and add every string**

```bash
git checkout -b feat/backup-section phase/7-backup
```

In `app/lib/l10n/app_en.arb`, insert after `"appTitle": "NimbuStats",` and before `"breakdownAllCategories"`. Check the spot with `grep -n '"appTitle"\|"breakdownAllCategories"' app/lib/l10n/app_en.arb`.

```json
  "backupChooseDestination": "Encrypted. Where should it go?",
  "backupCorrupt": "This backup file is damaged and can't be restored.",
  "backupDecrypting": "Decrypting…",
  "backupEncrypting": "Encrypting…",
  "backupExport": "Export a backup",
  "backupExportAction": "Encrypt",
  "backupExportFailed": "The backup couldn't be made.",
  "backupForgottenPassphrase": "A forgotten passphrase can't be recovered, and without it the file can't be opened.",
  "backupIncluded": "Included: every expense, category, tag, payment method, tracker, goal, saved view and setting — the daily reminder's time too.",
  "backupLastExport": "Last export: {when}",
  "@backupLastExport": {
    "placeholders": {
      "when": {
        "type": "String"
      }
    }
  },
  "backupLoadFailed": "Couldn't read the backup status.",
  "backupNeverExported": "Never exported",
  "backupNewerSchema": "This backup is from a newer version of NimbuStats. Update the app, then restore it.",
  "backupNotABackup": "This isn't a NimbuStats backup file.",
  "backupNotIncluded": "Not in the file: entries made on the home-screen widget that the app hasn't saved yet.",
  "backupPassphrase": "Passphrase",
  "backupPassphraseHint": "At least 8 characters. Write it down: it can't be recovered.",
  "backupPassphraseMismatch": "The two passphrases differ.",
  "backupPassphraseRepeat": "Repeat the passphrase",
  "backupPassphraseTooShort": "Use at least 8 characters.",
  "backupRestore": "Restore from a file",
  "backupRestoreAction": "Restore",
  "backupRestoreFailed": "The backup couldn't be restored. Your data is unchanged.",
  "backupRestoreFrom": "Backup from {when}",
  "@backupRestoreFrom": {
    "placeholders": {
      "when": {
        "type": "String"
      }
    }
  },
  "backupRestoreReplaces": "Restoring replaces all data on this phone. You can undo it afterwards.",
  "backupRestoreUndone": "Restore undone. Your earlier data is back.",
  "backupRestored": "Restored the backup from {when}.",
  "@backupRestored": {
    "placeholders": {
      "when": {
        "type": "String"
      }
    }
  },
  "backupSave": "Save to…",
  "backupSaveFailed": "The backup couldn't be saved.",
  "backupSaved": "Backup saved.",
  "backupShare": "Share…",
  "backupShareFailed": "The share sheet couldn't open.",
  "backupSizeWarning": "Your data is nearing Android's 25 MB limit for automatic backup, which stops past it. Keep exporting to stay protected.",
  "backupTitle": "Backup",
  "backupUndoFailed": "The restore couldn't be undone.",
  "backupUndoRestore": "Undo the last restore",
  "backupUnsupported": "This backup needs a newer version of NimbuStats. Update the app, then restore it.",
  "backupWrongPassphrase": "Wrong passphrase.",
```

In `app/lib/l10n/app_fa.arb`, at the same position, after `"appTitle"`, insert the following. There is no `@` metadata in this file:

```json
  "backupChooseDestination": "رمزگذاری شد. کجا برود؟",
  "backupCorrupt": "این فایل پشتیبان آسیب دیده است و بازیابی نمی‌شود.",
  "backupDecrypting": "در حال رمزگشایی…",
  "backupEncrypting": "در حال رمزگذاری…",
  "backupExport": "تهیهٔ پشتیبان",
  "backupExportAction": "رمزگذاری",
  "backupExportFailed": "پشتیبان تهیه نشد.",
  "backupForgottenPassphrase": "عبارت عبورِ فراموش‌شده بازیابی نمی‌شود و بدون آن فایل باز نمی‌شود.",
  "backupIncluded": "شامل: همهٔ هزینه‌ها، دسته‌بندی‌ها، برچسب‌ها، روش‌های پرداخت، عادت‌ها، اهداف، نماهای ذخیره‌شده و تنظیمات — ساعت یادآور روزانه هم.",
  "backupLastExport": "آخرین پشتیبان: {when}",
  "backupLoadFailed": "وضعیت پشتیبان خوانده نشد.",
  "backupNeverExported": "هنوز پشتیبانی تهیه نشده",
  "backupNewerSchema": "این پشتیبان با نسخهٔ جدیدتری از نیمبوستتس ساخته شده است. برنامه را به‌روز کنید و سپس بازیابی کنید.",
  "backupNotABackup": "این فایل، پشتیبان نیمبوستتس نیست.",
  "backupNotIncluded": "در فایل نیست: ثبت‌هایی از ابزارک صفحهٔ اصلی که برنامه هنوز ذخیره‌شان نکرده است.",
  "backupPassphrase": "عبارت عبور",
  "backupPassphraseHint": "دست‌کم ۸ نویسه. یادداشتش کنید: بازیابی‌شدنی نیست.",
  "backupPassphraseMismatch": "دو عبارت عبور یکی نیستند.",
  "backupPassphraseRepeat": "تکرار عبارت عبور",
  "backupPassphraseTooShort": "دست‌کم ۸ نویسه وارد کنید.",
  "backupRestore": "بازیابی از فایل",
  "backupRestoreAction": "بازیابی",
  "backupRestoreFailed": "پشتیبان بازیابی نشد. داده‌هایتان تغییری نکرده است.",
  "backupRestoreFrom": "پشتیبانِ {when}",
  "backupRestoreReplaces": "بازیابی، همهٔ داده‌های این گوشی را جایگزین می‌کند. پس از آن می‌توانید برش گردانید.",
  "backupRestoreUndone": "بازیابی برگردانده شد. داده‌های قبلی‌تان بازگشت.",
  "backupRestored": "پشتیبانِ {when} بازیابی شد.",
  "backupSave": "ذخیره در…",
  "backupSaveFailed": "پشتیبان ذخیره نشد.",
  "backupSaved": "پشتیبان ذخیره شد.",
  "backupShare": "اشتراک‌گذاری…",
  "backupShareFailed": "صفحهٔ اشتراک‌گذاری باز نشد.",
  "backupSizeWarning": "داده‌هایتان به سقف ۲۵ مگابایتی پشتیبان خودکار اندروید نزدیک شده است؛ پس از آن، پشتیبان خودکار متوقف می‌شود. برای در امان ماندن، پشتیبان دستی را ادامه دهید.",
  "backupTitle": "پشتیبان‌گیری",
  "backupUndoFailed": "بازیابی برگردانده نشد.",
  "backupUndoRestore": "برگرداندن آخرین بازیابی",
  "backupUnsupported": "این پشتیبان به نسخهٔ جدیدتری از نیمبوستتس نیاز دارد. برنامه را به‌روز کنید و سپس بازیابی کنید.",
  "backupWrongPassphrase": "عبارت عبور نادرست است.",
```

Run from `app/`: `flutter gen-l10n`. Expected: it regenerates `lib/l10n/app_localizations*.dart` with no warnings.

- [ ] **Step 2: Write the failing tests**

Create `app/test/features/backup/support/gregorian_english.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';

/// Gregorian and Latin digits, so a backup test can spell out the times it
/// expects.
Future<void> useGregorianEnglish(AppDatabase db) =>
    SettingsRepository(db.settingsDao).save(AppSettings.defaults.copyWith(
        locale: const Locale('en'), calendarKind: CalendarKind.gregorian));
```

Create `app/test/features/backup/backup_messages_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/backup/presentation/backup_messages.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

void main() {
  test('a moment reads in the active calendar and digits, in local time', () {
    final moment = DateTime(2026, 10, 17, 9, 5); // local
    expect(whenLabel(moment, const GregorianCalendar(), persianDigits: false),
        '2026/10/17 09:05');
    expect(whenLabel(moment, const JalaliCalendar(), persianDigits: true),
        '۱۴۰۵/۰۷/۲۵ ۰۹:۰۵');
    expect(whenLabel(moment.toUtc(), const GregorianCalendar(), persianDigits: false),
        '2026/10/17 09:05');
  });

  test('each backup error has its own message; anything else has none',
      () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final messages = [
      for (final error in const [
        NotABackup(),
        UnsupportedFormat('x'),
        NewerSchema(backup: 41, app: 40),
        WrongPassphrase(),
        CorruptBackup('x'),
      ])
        backupErrorText(l10n, error),
    ];
    expect(messages, [
      l10n.backupNotABackup,
      l10n.backupUnsupported,
      l10n.backupNewerSchema,
      l10n.backupWrongPassphrase,
      l10n.backupCorrupt,
    ]);
    expect(backupErrorText(l10n, StateError('x')), isNull);
  });
}
```

Create `app/test/features/backup/backup_section_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/backup/application/backup_providers.dart';
import 'package:nimbustats/features/backup/application/restart.dart';
import 'package:nimbustats/features/backup/data/backup_state_store.dart';

import '../../support/harness.dart';
import 'support/fake_backup_service.dart';
import 'support/gregorian_english.dart';

void main() {
  late AppDatabase db;
  late FakeBackupService service;
  late Directory dir;
  late BackupStateStore store;
  late List<RestartNotice> restarts;

  setUp(() {
    db = AppDatabase.openInMemory();
    service = FakeBackupService();
    dir = Directory.systemTemp.createTempSync('nimbus_backup_section');
    store = BackupStateStore('${dir.path}/backup_state.json');
    restarts = [];
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  /// Opens Settings and scrolls the section's [row] into view. Loading and
  /// error states have no rows, so their tests scroll to the section itself.
  Future<void> open(WidgetTester tester,
      {Locale locale = const Locale('en'),
      String row = 'backup-restore',
      List<Override> overrides = const []}) async {
    if (locale.languageCode == 'en') await useGregorianEnglish(db);
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        initialLocation: '/settings',
        locale: locale,
        backup: service,
        backupState: store,
        overrides: [
          appRestartProvider.overrideWithValue(restarts.add),
          ...overrides,
        ]);
    await tester.scrollUntilVisible(find.byKey(Key(row)), 200);
    await tester.pumpAndSettle();
  }

  testWidgets('never exported: the empty state, and stale files are swept',
      (tester) async {
    await open(tester);
    expect(find.text('Never exported'), findsOneWidget);
    expect(service.calls, contains('sweep'));
    expect(find.byKey(const Key('backup-undo')), findsNothing);
    expect(find.byKey(const Key('backup-size-warning')), findsNothing);
  });

  testWidgets('the last export shows in the active calendar', (tester) async {
    store.recordExport(DateTime(2026, 10, 17, 9, 5).toUtc());
    await open(tester);
    expect(find.text('Last export: 2026/10/17 09:05'), findsOneWidget);
  });

  testWidgets('loading', (tester) async {
    await open(tester, row: 'backup-section', overrides: [
      backupStatusProvider.overrideWith((ref) => Completer<BackupStatus>().future),
    ]);
    expect(find.byKey(const Key('backup-loading')), findsOneWidget);
  });

  testWidgets('an unreadable state file is an error with a retry',
      (tester) async {
    await open(tester, row: 'backup-section', overrides: [
      backupStatusProvider.overrideWith(
          (ref) async => throw const FormatException('unreadable backup state')),
    ]);
    expect(find.byKey(const Key('backup-error')), findsOneWidget);
    expect(find.text("Couldn't read the backup status."), findsOneWidget);
  });

  testWidgets('past 20 MiB the section warns about the Auto Backup cap (R7)',
      (tester) async {
    service.bytes = autoBackupWarnBytes + 1;
    await open(tester);
    expect(find.byKey(const Key('backup-size-warning')), findsOneWidget);
  });

  testWidgets('Undo shows only while a copy exists, and restarts saying so',
      (tester) async {
    service.undoable = true;
    await open(tester, row: 'backup-undo');
    await tester.tap(find.byKey(const Key('backup-undo')));
    await tester.pumpAndSettle();
    expect(service.calls, contains('undo'));
    expect(restarts.single, isA<RestoreUndone>());
  });

  testWidgets('a failed undo is reported and said', (tester) async {
    service
      ..undoable = true
      ..undoError = StateError('backup step failed');
    await open(tester, row: 'backup-undo');
    await tester.tap(find.byKey(const Key('backup-undo')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    expect(find.text("The restore couldn't be undone."), findsOneWidget);
    expect(restarts, isEmpty);
  });

  testWidgets('Persian, right to left: the section renders without overflow',
      (tester) async {
    await open(tester, locale: const Locale('fa'));
    expect(find.text('هنوز پشتیبانی تهیه نشده'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 3: Run them and see RED**

Run from `app/`: `flutter test --no-pub test/features/backup/backup_messages_test.dart test/features/backup/backup_section_test.dart`. Expected:
- `backup_messages_test` fails to compile.
- The section tests fail, because no `backup-restore` key is found.

- [ ] **Step 4: Tag the parent**

```bash
git tag pre-backup-section phase/7-backup
```

- [ ] **Step 5: Write the messages**

Create `app/lib/features/backup/presentation/backup_messages.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';

/// The message for a backup error the user can act on (spec §5.4), or null
/// for one no message names. The caller reports a null case and shows its
/// generic failure text.
String? backupErrorText(AppLocalizations l10n, Object error) => switch (error) {
      NotABackup() => l10n.backupNotABackup,
      UnsupportedFormat() => l10n.backupUnsupported,
      NewerSchema() => l10n.backupNewerSchema,
      WrongPassphrase() => l10n.backupWrongPassphrase,
      CorruptBackup() => l10n.backupCorrupt,
      _ => null,
    };

/// Reports an error no message names, under `backup`. Callers pass the
/// error, never the passphrase.
void reportBackupFailure(Object error, StackTrace stack, String context) =>
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'backup',
      context: ErrorDescription(context),
    ));

/// A moment as `yyyy/MM/dd HH:mm`, in the local zone, the active calendar
/// and the user's digits: the way the transaction list writes a day.
String whenLabel(DateTime moment, AppCalendar calendar,
    {required bool persianDigits}) {
  final local = moment.toLocal();
  final parts = calendar.partsOf(DateKey.fromDateTime(local));
  String two(int value) => value.toString().padLeft(2, '0');
  final text = '${parts.year}/${two(parts.month)}/${two(parts.day)} '
      '${two(local.hour)}:${two(local.minute)}';
  return persianDigits ? Digits.toPersian(text) : text;
}
```

- [ ] **Step 6: Stub the two sheets**

Tasks 11 and 12 replace these stubs.

Create `app/lib/features/backup/presentation/export_sheet.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Export, in one sheet (spec §5.2). Completed in Task 11.
class ExportSheet extends StatelessWidget {
  const ExportSheet({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
```

Create `app/lib/features/backup/presentation/restore_sheet.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../application/backup_controller.dart';

/// Restore, in one sheet (spec §5.3). Completed in Task 12.
class RestoreSheet extends StatelessWidget {
  const RestoreSheet({super.key, required this.picked});

  final PickedBackup picked;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
```

- [ ] **Step 7: Write the section**

Create `app/lib/features/backup/presentation/backup_section.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../notifications/application/outside_errors.dart';
import '../../settings/application/settings_providers.dart';
import '../application/backup_controller.dart';
import '../application/backup_providers.dart';
import 'backup_messages.dart';
import 'export_sheet.dart';
import 'restore_sheet.dart';

/// The settings screen's "Backup" section (spec §5.1).
///
/// It shows:
/// - when the last export was handed off;
/// - Export and Restore;
/// - Undo, while an undo copy exists;
/// - the warning near Auto Backup's cap (ruling R7);
/// - what a backup holds.
///
/// States: loading, error, empty (never exported) and populated.
class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});

  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  @override
  void initState() {
    super.initState();
    // A crash mid-export or mid-restore leaves plaintext in the cache (spec
    // §3.3). Nothing is in flight here: each flow is a modal sheet that
    // blocks navigation while it works.
    unawaited(reportingFailure('backup', 'while sweeping stale backup files',
        ref.read(backupControllerProvider).sweep));
  }

  Future<void> _export() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        enableDrag: false,
        builder: (_) => const ExportSheet(),
      );

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(backupControllerProvider);
    final PickedBackup? picked;
    try {
      picked = await controller.pick();
    } on Object catch (error, stack) {
      final text = backupErrorText(l10n, error);
      if (text == null) reportBackupFailure(error, stack, 'while opening a backup file');
      messenger.showSnackBar(SnackBar(content: Text(text ?? l10n.backupRestoreFailed)));
      return;
    }
    if (picked == null) return;
    final chosen = picked;
    if (mounted) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        enableDrag: false,
        builder: (_) => RestoreSheet(picked: chosen),
      );
    }
    // Reached when the sheet closed without restoring. A restore restarts
    // the app instead, and has deleted the copy already.
    await reportingFailure('backup', 'while deleting a picked backup',
        () async => controller.discard(chosen.path));
  }

  Future<void> _undo() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(backupControllerProvider).undo();
    } on Object catch (error, stack) {
      reportBackupFailure(error, stack, 'while undoing a restore');
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupUndoFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(backupStatusProvider);

    final Widget body;
    if (status.hasError) {
      body = NimbusErrorState(
        key: const Key('backup-error'),
        title: l10n.backupLoadFailed,
        retryLabel: l10n.commonRetry,
        detail: status.error.toString(),
        onRetry: () => ref.invalidate(backupStatusProvider),
      );
    } else if (!status.hasValue) {
      body = const SizedBox(
        key: Key('backup-loading'),
        height: 3 * 72,
        child: NimbusLoadingList(rows: 3),
      );
    } else {
      body = _rows(context, l10n, status.requireValue);
    }

    return Column(
      key: const Key('backup-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              NimbusTokens.space4, NimbusTokens.space4, NimbusTokens.space4, 0),
          child: Text(l10n.backupTitle,
              style: Theme.of(context).textTheme.titleSmall),
        ),
        body,
      ],
    );
  }

  Widget _rows(BuildContext context, AppLocalizations l10n, BackupStatus status) {
    final small = Theme.of(context).textTheme.bodySmall;
    final last = status.lastExport;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const Key('backup-last-export'),
          leading: const Icon(Icons.history),
          title: Text(last == null
              ? l10n.backupNeverExported
              : l10n.backupLastExport(whenLabel(last, ref.watch(calendarProvider),
                  persianDigits: ref.watch(moneyFormatterProvider).persianDigits))),
        ),
        if (status.databaseBytes > autoBackupWarnBytes)
          ListTile(
            key: const Key('backup-size-warning'),
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(l10n.backupSizeWarning),
          ),
        ListTile(
          key: const Key('backup-export'),
          leading: const Icon(Icons.upload_file_outlined),
          title: Text(l10n.backupExport),
          onTap: () => unawaited(_export()),
        ),
        ListTile(
          key: const Key('backup-restore'),
          leading: const Icon(Icons.settings_backup_restore),
          title: Text(l10n.backupRestore),
          onTap: () => unawaited(_restore()),
        ),
        if (status.canUndo)
          ListTile(
            key: const Key('backup-undo'),
            leading: const Icon(Icons.undo),
            title: Text(l10n.backupUndoRestore),
            onTap: () => unawaited(_undo()),
          ),
        Padding(
          padding: const EdgeInsets.all(NimbusTokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: NimbusTokens.space2,
            children: [
              Text(l10n.backupIncluded, style: small),
              Text(l10n.backupNotIncluded, style: small),
              Text(l10n.backupForgottenPassphrase, style: small),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 8: Add it to Settings**

In `app/lib/features/settings/presentation/settings_screen.dart`, add `import '../../backup/presentation/backup_section.dart';`. Then replace

```dart
        const NotificationsSection(),
        const Divider(),
```

with

```dart
        const NotificationsSection(),
        // Phase 7 (additive): export, restore and the last export's time.
        const Divider(),
        const BackupSection(),
        const Divider(),
```

- [ ] **Step 9: Run them and see GREEN**

Run from `app/`: `flutter test --no-pub test/features/backup/ test/localization_test.dart test/ux_rules_test.dart test/features/settings/`. Expected: all pass. The existing settings tests still pass with the section added, because of R13's fakes.

- [ ] **Step 10: Run the broader suite**

Run the App suite and `dart analyze --fatal-infos`. Expected: green.

- [ ] **Step 11: Commit and merge**

```bash
git add app/lib/l10n app/lib/features/backup/presentation app/lib/features/settings/presentation/settings_screen.dart app/test/features/backup
git commit -m "$(cat <<'EOF'
feat(backup): a Backup section in Settings

Auto Backup is invisible, so this is where the user can see their data
is safe: when the last export was handed off, Export and Restore, Undo
while an undo copy exists, and plainly what a backup holds and that a
forgotten passphrase is unrecoverable. Past 20 MiB it warns that Auto
Backup's 25 MB cap is near. The measured growth reaches the cap in
about four years at heavy use, inside the spec's ten-year line (ruling
R7). Every backup error maps to its own message, and any other error is
reported under "backup" and said generically. All of the phase's
strings land here in both languages.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only feat/backup-section
```

---

### Task 11: The export sheet

Slug: `export-sheet`. Spec §5.2, §2.3, rulings R2 and R9, and Review Focus items 2–4.

**Files:**
- Create: `app/lib/features/backup/presentation/backup_sheet_parts.dart`
- Modify: `app/lib/features/backup/presentation/export_sheet.dart` (replace the stub)
- Test: `app/test/features/backup/export_sheet_test.dart`

**Interfaces:**
- Consumes: Task 9's `BackupController.export/save/share`, and Task 10's `reportBackupFailure`.
- Produces:
  - `BackupSheetFrame({required String title, required List<Widget> children})`.
  - `PassphraseField({required TextEditingController controller, required String label, String? helper, String? error, bool enabled = true})`.
  - `BackupProgress({required String label})`.
  - The keys `backup-passphrase`, `backup-passphrase-repeat`, `backup-encrypt`, `backup-save`, `backup-share` and `backup-sheet-error`.

- [ ] **Step 1: Branch, and write the failing test**

```bash
git checkout -b feat/export-sheet phase/7-backup
```

Create `app/test/features/backup/export_sheet_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/backup/data/backup_state_store.dart';

import '../../support/harness.dart';
import 'support/fake_backup_channel.dart';
import 'support/fake_backup_service.dart';
import 'support/gregorian_english.dart';

void main() {
  late AppDatabase db;
  late FakeBackupService service;
  late FakeBackupChannel channel;
  late Directory dir;
  late BackupStateStore store;

  setUp(() {
    db = AppDatabase.openInMemory();
    service = FakeBackupService();
    channel = FakeBackupChannel();
    dir = Directory.systemTemp.createTempSync('nimbus_export_sheet');
    store = BackupStateStore('${dir.path}/backup_state.json');
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> openSheet(WidgetTester tester) async {
    await useGregorianEnglish(db);
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        initialLocation: '/settings',
        backup: service,
        backupChannel: channel,
        backupState: store);
    await tester.scrollUntilVisible(find.byKey(const Key('backup-export')), 200);
    await tester.tap(find.byKey(const Key('backup-export')));
    await tester.pumpAndSettle();
  }

  Future<void> encrypt(WidgetTester tester, String first, String second,
      {bool settle = true}) async {
    await tester.enterText(find.byKey(const Key('backup-passphrase')), first);
    await tester.enterText(find.byKey(const Key('backup-passphrase-repeat')), second);
    await tester.tap(find.byKey(const Key('backup-encrypt')));
    settle ? await tester.pumpAndSettle() : await tester.pump();
  }

  testWidgets('under 8 characters is refused, and nothing is exported',
      (tester) async {
    await openSheet(tester);
    await encrypt(tester, 'short', 'short');
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(service.calls, isNot(contains('exportTo')));
  });

  testWidgets('two passphrases that differ are refused', (tester) async {
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct house');
    expect(find.text('The two passphrases differ.'), findsOneWidget);
    expect(service.calls, isNot(contains('exportTo')));
  });

  testWidgets('the same passphrase in Persian and Latin digits matches',
      (tester) async {
    await openSheet(tester);
    await encrypt(tester, '۱۲۳۴۵۶۷۸', '12345678');
    expect(service.calls, contains('exportTo'));
    // Passed as typed: normalising is the key derivation's job.
    expect(service.lastPassphrase, '۱۲۳۴۵۶۷۸');
  });

  testWidgets('Save hands the file over, closes, says so and records the time',
      (tester) async {
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse');
    await tester.tap(find.byKey(const Key('backup-save')));
    await tester.pumpAndSettle();

    expect(channel.calls.single,
        matches(RegExp(r'^saveDocument .*nimbustats-\d{8}-\d{4}\.nimbus$')));
    expect(find.byKey(const Key('backup-save')), findsNothing);
    expect(find.text('Backup saved.'), findsOneWidget);
    expect(store.lastExport(), isNotNull);
    expect(find.textContaining('Last export: '), findsOneWidget);
  });

  testWidgets('a cancelled Save is not an error: the choice stays, nothing '
      'is recorded', (tester) async {
    channel.saveAnswer = false;
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse');
    await tester.tap(find.byKey(const Key('backup-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backup-save')), findsOneWidget);
    expect(find.byKey(const Key('backup-sheet-error')), findsNothing);
    expect(store.lastExport(), isNull);
  });

  testWidgets('Share hands the file over and closes', (tester) async {
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse');
    await tester.tap(find.byKey(const Key('backup-share')));
    await tester.pumpAndSettle();

    expect(channel.calls.single, startsWith('shareFile '));
    expect(find.byKey(const Key('backup-share')), findsNothing);
    expect(store.lastExport(), isNotNull);
  });

  testWidgets('a failed Save is reported and said; the choice stays',
      (tester) async {
    channel.error = StateError('copy failed');
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse');
    await tester.tap(find.byKey(const Key('backup-save')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isA<StateError>());
    expect(find.text("The backup couldn't be saved."), findsOneWidget);
    expect(find.byKey(const Key('backup-share')), findsOneWidget);
  });

  testWidgets('a failed export is reported and the passphrase step returns',
      (tester) async {
    service.exportError = StateError('disk full');
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse');

    expect(tester.takeException(), isA<StateError>());
    expect(find.text("The backup couldn't be made."), findsOneWidget);
    expect(find.byKey(const Key('backup-encrypt')), findsOneWidget);
  });

  testWidgets('the sheet cannot be dismissed while encrypting', (tester) async {
    service.exportGate = Completer<void>();
    await openSheet(tester);
    await encrypt(tester, 'correct horse', 'correct horse', settle: false);
    expect(find.text('Encrypting…'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10)); // the barrier
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Encrypting…'), findsOneWidget);

    service.exportGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup-save')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it and see RED**

Run from `app/`: `flutter test --no-pub test/features/backup/export_sheet_test.dart`. Expected: FAIL, with no `backup-passphrase` widget found. The stub renders nothing.

- [ ] **Step 3: Tag the parent**

```bash
git tag pre-export-sheet phase/7-backup
```

- [ ] **Step 4: Write the shared sheet parts**

Create `app/lib/features/backup/presentation/backup_sheet_parts.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:nimbus_design/nimbus_design.dart';

/// The frame both backup sheets share: clear of the keyboard, a title, then
/// the rows.
class BackupSheetFrame extends StatelessWidget {
  const BackupSheetFrame({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        // The fields sit at the bottom of the screen, and would otherwise sit
        // under the keyboard.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(NimbusTokens.space4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: NimbusTokens.space3,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                ...children,
              ],
            ),
          ),
        ),
      );
}

/// A passphrase input. It is hidden and has no suggestions or autocorrect, so
/// the keyboard neither shows it nor learns it.
class PassphraseField extends StatelessWidget {
  const PassphraseField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.error,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          errorText: error,
          errorMaxLines: 3,
        ),
      );
}

/// Real work in progress, named once for screen readers.
class BackupProgress extends StatelessWidget {
  const BackupProgress({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: NimbusTokens.space2,
        children: [
          LinearProgressIndicator(semanticsLabel: label),
          ExcludeSemantics(child: Text(label)),
        ],
      );
}
```

- [ ] **Step 5: Write the export sheet**

Replace `app/lib/features/backup/presentation/export_sheet.dart` with:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../../l10n/app_localizations.dart';
import '../application/backup_controller.dart';
import 'backup_messages.dart';
import 'backup_sheet_parts.dart';

/// Export, in one sheet (spec §5.2): the passphrase twice, the work, then
/// where the file goes. Steps of a sheet rather than dialogs (ruling R2):
/// "undo, never confirm" keeps dialogs out of the app.
class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key});

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

enum _Step { passphrase, working, destination }

class _ExportSheetState extends ConsumerState<ExportSheet> {
  final _passphrase = TextEditingController();
  final _repeat = TextEditingController();
  var _step = _Step.passphrase;
  String? _error;
  String? _path;

  @override
  void dispose() {
    _passphrase.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _encrypt() async {
    final l10n = AppLocalizations.of(context);
    final passphrase = _passphrase.text;
    final problem = passphrase.runes.length < minPassphraseRunes
        ? l10n.backupPassphraseTooShort
        // Compared as the key derivation will see them, so the two entries
        // may use different digit sets.
        : normalizePassphrase(passphrase) != normalizePassphrase(_repeat.text)
            ? l10n.backupPassphraseMismatch
            : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _step = _Step.working;
      _error = null;
    });
    try {
      final path = await ref.read(backupControllerProvider).export(passphrase);
      if (!mounted) return;
      setState(() {
        _path = path;
        _step = _Step.destination;
      });
    } on Object catch (error, stack) {
      reportBackupFailure(error, stack, 'while exporting');
      if (!mounted) return;
      setState(() {
        _step = _Step.passphrase;
        _error = l10n.backupExportFailed;
      });
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // False: the picker was cancelled. Not an error, so the choice stays.
      if (!await ref.read(backupControllerProvider).save(_path!)) return;
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupSaved)));
    } on Object catch (error, stack) {
      reportBackupFailure(error, stack, 'while saving a backup');
      if (mounted) setState(() => _error = l10n.backupSaveFailed);
    }
  }

  Future<void> _share() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(backupControllerProvider).share(_path!);
      navigator.pop();
    } on Object catch (error, stack) {
      reportBackupFailure(error, stack, 'while sharing a backup');
      if (mounted) setState(() => _error = l10n.backupShareFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final working = _step == _Step.working;
    return PopScope(
      // Not while the file is being written: closing would orphan the work.
      canPop: !working,
      child: BackupSheetFrame(
        title: l10n.backupExport,
        children: switch (_step) {
          _Step.destination => [
              Text(l10n.backupChooseDestination),
              ListTile(
                key: const Key('backup-save'),
                leading: const Icon(Icons.save_alt),
                title: Text(l10n.backupSave),
                onTap: () => unawaited(_save()),
              ),
              ListTile(
                key: const Key('backup-share'),
                leading: const Icon(Icons.share_outlined),
                title: Text(l10n.backupShare),
                onTap: () => unawaited(_share()),
              ),
              if (_error != null)
                Text(_error!,
                    key: const Key('backup-sheet-error'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          _Step.passphrase || _Step.working => [
              PassphraseField(
                key: const Key('backup-passphrase'),
                controller: _passphrase,
                label: l10n.backupPassphrase,
                helper: l10n.backupPassphraseHint,
                enabled: !working,
              ),
              PassphraseField(
                key: const Key('backup-passphrase-repeat'),
                controller: _repeat,
                label: l10n.backupPassphraseRepeat,
                error: _error,
                enabled: !working,
              ),
              if (working) BackupProgress(label: l10n.backupEncrypting),
              FilledButton(
                key: const Key('backup-encrypt'),
                onPressed: working ? null : () => unawaited(_encrypt()),
                child: Text(l10n.backupExportAction),
              ),
            ],
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Run it and see GREEN**

Run from `app/`: `flutter test --no-pub test/features/backup/`. Expected: all pass.

- [ ] **Step 7: Run the broader suite**

Run the App suite (including `ux_rules_test`) and `dart analyze --fatal-infos`. Expected: green.

- [ ] **Step 8: Commit and merge**

```bash
git add app/lib/features/backup/presentation app/test/features/backup/export_sheet_test.dart
git commit -m "$(cat <<'EOF'
feat(backup): export in one sheet — passphrase, work, destination

Two hidden fields with no suggestions or autocorrect, so the keyboard
never learns the passphrase. At least 8 characters, and the two
entries are compared as the key derivation will see them, so Persian
and Latin digits match. The work runs in the same sheet, which cannot
be dismissed until the file is written, and then the sheet offers
Save to… or Share…. A cancelled picker is not an error: the choice
stays and no export is recorded. Steps of one sheet, not dialogs,
because "undo, never confirm" keeps dialogs out of the app (ruling R2).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only feat/export-sheet
```

---

### Task 12: The restore sheet

Slug: `restore-sheet`. Spec §5.3, §2.4, ruling R2, and Review Focus item 1.

**Files:**
- Modify: `app/lib/features/backup/presentation/restore_sheet.dart` (replace the stub)
- Test: `app/test/features/backup/restore_sheet_test.dart`

**Interfaces:**
- Consumes:
  - Task 9's `BackupController.pick/restore/discard` and `PickedBackup`.
  - Task 10's `backupErrorText`, `reportBackupFailure` and `whenLabel`.
  - Task 11's `BackupSheetFrame`, `PassphraseField` and `BackupProgress`.
- Produces: the keys `backup-restore-from`, `backup-restore-passphrase` and `backup-restore-go`.

- [ ] **Step 1: Branch, and write the failing test**

```bash
git checkout -b feat/restore-sheet phase/7-backup
```

Create `app/test/features/backup/restore_sheet_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/backup/application/restart.dart';
import 'package:nimbustats/features/backup/presentation/backup_messages.dart';

import '../../support/harness.dart';
import 'support/fake_backup_channel.dart';
import 'support/fake_backup_service.dart';
import 'support/gregorian_english.dart';

void main() {
  late AppDatabase db;
  late FakeBackupService service;
  late FakeBackupChannel channel;
  late Directory dir;
  late List<RestartNotice> restarts;

  setUp(() {
    db = AppDatabase.openInMemory();
    service = FakeBackupService();
    channel = FakeBackupChannel();
    dir = Directory.systemTemp.createTempSync('nimbus_restore_sheet');
    channel.picked = '${dir.path}/picked-1.nimbus';
    File(channel.picked!).writeAsBytesSync(const [1]);
    restarts = [];
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> tapRestore(WidgetTester tester) async {
    await useGregorianEnglish(db);
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        initialLocation: '/settings',
        backup: service,
        backupChannel: channel,
        overrides: [appRestartProvider.overrideWithValue(restarts.add)]);
    await tester.scrollUntilVisible(find.byKey(const Key('backup-restore')), 200);
    await tester.tap(find.byKey(const Key('backup-restore')));
    await tester.pumpAndSettle();
  }

  Future<void> restoreWith(WidgetTester tester, String passphrase,
      {bool settle = true}) async {
    await tester.enterText(
        find.byKey(const Key('backup-restore-passphrase')), passphrase);
    await tester.tap(find.byKey(const Key('backup-restore-go')));
    settle ? await tester.pumpAndSettle() : await tester.pump();
  }

  bool restoreEnabled(WidgetTester tester) => tester
      .widget<FilledButton>(find.byKey(const Key('backup-restore-go')))
      .enabled;

  testWidgets("the sheet names the backup's date and what restoring does",
      (tester) async {
    await tapRestore(tester);
    final when = whenLabel(service.header.createdAt, const GregorianCalendar(),
        persianDigits: false);
    expect(find.text('Backup from $when'), findsOneWidget);
    expect(find.text('Restoring replaces all data on this phone. You can undo '
        'it afterwards.'), findsOneWidget);
  });

  testWidgets('a newer schema is refused before any passphrase, saying update',
      (tester) async {
    service.headerError = const NewerSchema(backup: 41, app: 40);
    await tapRestore(tester);
    expect(find.text('This backup is from a newer version of NimbuStats. '
        'Update the app, then restore it.'), findsOneWidget);
    expect(find.byKey(const Key('backup-restore-passphrase')), findsNothing);
    expect(File(channel.picked!).existsSync(), isFalse);
    expect(service.calls, isNot(contains('prepare')));
  });

  testWidgets('a file that is not a backup says so and leaves no copy',
      (tester) async {
    service.headerError = const NotABackup();
    await tapRestore(tester);
    expect(find.text("This isn't a NimbuStats backup file."), findsOneWidget);
    expect(File(channel.picked!).existsSync(), isFalse);
  });

  testWidgets('a wrong passphrase keeps the sheet to try again; the right one '
      'restores and restarts', (tester) async {
    await tapRestore(tester);
    await restoreWith(tester, 'not it');
    expect(find.text('Wrong passphrase.'), findsOneWidget);
    expect(restoreEnabled(tester), isTrue);
    expect(restarts, isEmpty);

    // No restart happens in this harness, so the sheet stays with its
    // progress bar showing, and pumpAndSettle would never return.
    await restoreWith(tester, FakeBackupService.goodPassphrase, settle: false);
    await tester.pump();
    expect(service.calls, containsAllInOrder(['prepare', 'restore']));
    expect(
        restarts.single,
        isA<BackupRestored>().having(
            (n) => n.backupCreatedAt, 'createdAt', service.header.createdAt));
    expect(File(channel.picked!).existsSync(), isFalse);
  });

  testWidgets('a damaged file says so and leaves only closing', (tester) async {
    service.prepareError = const CorruptBackup('authentication failed');
    await tapRestore(tester);
    await restoreWith(tester, FakeBackupService.goodPassphrase);
    expect(find.text("This backup file is damaged and can't be restored."),
        findsOneWidget);
    expect(restoreEnabled(tester), isFalse);
    expect(restarts, isEmpty);
  });

  testWidgets('an unexpected failure is reported and said generically',
      (tester) async {
    service.prepareError = StateError('migration failed');
    await tapRestore(tester);
    await restoreWith(tester, FakeBackupService.goodPassphrase);
    expect(tester.takeException(), isA<StateError>());
    expect(find.text("The backup couldn't be restored. Your data is unchanged."),
        findsOneWidget);
  });

  testWidgets('closing the sheet deletes the picked copy', (tester) async {
    await tapRestore(tester);
    await tester.tapAt(const Offset(10, 10)); // the barrier
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup-restore-go')), findsNothing);
    expect(File(channel.picked!).existsSync(), isFalse);
    expect(service.calls, isNot(contains('prepare')));
  });
}
```

- [ ] **Step 2: Run it and see RED**

Run from `app/`: `flutter test --no-pub test/features/backup/restore_sheet_test.dart`. Expected: FAIL, with no `Backup from …` text and no `backup-restore-passphrase` found.

- [ ] **Step 3: Tag the parent**

```bash
git tag pre-restore-sheet phase/7-backup
```

- [ ] **Step 4: Write the restore sheet**

Replace `app/lib/features/backup/presentation/restore_sheet.dart` with:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/application/settings_providers.dart';
import '../application/backup_controller.dart';
import 'backup_messages.dart';
import 'backup_sheet_parts.dart';

/// Restore, in one sheet (spec §5.3): which backup, what restoring does, the
/// passphrase, and then the work.
///
/// Its button is the commitment. Undo follows the restore instead of a
/// confirmation preceding it ("undo, never confirm", ruling R2).
class RestoreSheet extends ConsumerStatefulWidget {
  const RestoreSheet({super.key, required this.picked});

  final PickedBackup picked;

  @override
  ConsumerState<RestoreSheet> createState() => _RestoreSheetState();
}

class _RestoreSheetState extends ConsumerState<RestoreSheet> {
  final _passphrase = TextEditingController();
  var _working = false;

  /// A wrong passphrase, under the field. The sheet stays, to try again.
  String? _wrong;

  /// Any other failure. Only closing is left.
  String? _failed;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _working = true;
      _wrong = null;
    });
    try {
      // On success the app restarts onto the restored data, and this sheet
      // goes with it.
      await ref
          .read(backupControllerProvider)
          .restore(widget.picked, _passphrase.text);
    } on WrongPassphrase {
      if (!mounted) return;
      setState(() {
        _working = false;
        _wrong = l10n.backupWrongPassphrase;
      });
    } on Object catch (error, stack) {
      final text = backupErrorText(l10n, error);
      if (text == null) reportBackupFailure(error, stack, 'while restoring a backup');
      if (!mounted) return;
      setState(() {
        _working = false;
        _failed = text ?? l10n.backupRestoreFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final when = whenLabel(widget.picked.header.createdAt, ref.watch(calendarProvider),
        persianDigits: ref.watch(moneyFormatterProvider).persianDigits);
    final open = !_working && _failed == null;
    return PopScope(
      // Not mid-swap: closing would not stop it, only hide its outcome.
      canPop: !_working,
      child: BackupSheetFrame(
        title: l10n.backupRestore,
        children: [
          Text(l10n.backupRestoreFrom(when), key: const Key('backup-restore-from')),
          Text(l10n.backupRestoreReplaces),
          PassphraseField(
            key: const Key('backup-restore-passphrase'),
            controller: _passphrase,
            label: l10n.backupPassphrase,
            error: _wrong,
            enabled: open,
          ),
          if (_working) BackupProgress(label: l10n.backupDecrypting),
          if (_failed != null)
            Text(_failed!,
                key: const Key('backup-sheet-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          FilledButton(
            key: const Key('backup-restore-go'),
            onPressed: open ? () => unawaited(_restore()) : null,
            child: Text(l10n.backupRestoreAction),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run it and see GREEN**

Run from `app/`: `flutter test --no-pub test/features/backup/`. Expected: all pass.

- [ ] **Step 6: Run the broader suite**

Run the App suite and `dart analyze --fatal-infos`. Expected: green.

- [ ] **Step 7: Commit and merge**

```bash
git add app/lib/features/backup/presentation/restore_sheet.dart app/test/features/backup/restore_sheet_test.dart
git commit -m "$(cat <<'EOF'
feat(backup): restore in one sheet, with undo instead of a confirm

The sheet names the backup by its date and says plainly that
restoring replaces all data on the phone and can be undone. Its button
is the commitment; Undo follows on Home and in Settings (ruling R2).
A file from a newer app is refused before any passphrase, saying to
update; a photo picked by mistake says it is not a backup and leaves
no copy. A wrong passphrase keeps the sheet to try again; a damaged
file leaves only closing; anything unexpected is reported and said
generically, with the reassurance that nothing changed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only feat/restore-sheet
```

---

### Task 13: After the restart — land on Home, say so, offer Undo

Slug: `restart-notice`. Spec §5.3, rulings R2, R3, R12.

**Files:**
- Create: `app/lib/features/backup/presentation/restart_notice_listener.dart`
- Modify: `app/lib/bootstrap/app_shell.dart` (one line)
- Test: `app/test/features/backup/restart_flow_test.dart`

**Interfaces:**
- Consumes: Task 8's `AppRestart`, `restartNoticeProvider`, `BackupRestored` and `RestoreUndone`; Task 9's `backupControllerProvider`; Task 10's `whenLabel` and `reportBackupFailure`.
- Produces: `class RestartNoticeListener({required Widget child})`.

- [ ] **Step 1: Branch, and write the failing test**

```bash
git checkout -b feat/restart-notice phase/7-backup
```

Create `app/test/features/backup/restart_flow_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/app.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/first_run.dart';
import 'package:nimbustats/features/backup/application/backup_providers.dart';
import 'package:nimbustats/features/backup/data/backup_channel.dart';
import 'package:nimbustats/features/backup/data/backup_state_store.dart';
import 'package:nimbustats/features/backup/presentation/app_restart.dart';
import 'package:nimbustats/features/notifications/application/notification_providers.dart';
import 'package:nimbustats/features/notifications/data/outside_channel.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

import '../notifications/support/fake_outside_channel.dart';
import 'support/fake_backup_channel.dart';
import 'support/fake_backup_service.dart';
import 'support/gregorian_english.dart';

/// The shipped root, `AppRestart` as `main` builds it, with fakes for
/// Android and files.
void main() {
  testWidgets('a restore lands on Home and says so; Undo restarts again and '
      'says that', (tester) async {
    final db = AppDatabase.openInMemory();
    addTearDown(db.close);
    await FirstRunController(db)
        .ensureSeeded(await AppLocalizations.delegate.load(const Locale('en')));
    await useGregorianEnglish(db);
    final dir = Directory.systemTemp.createTempSync('nimbus_restart_flow');
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = FakeBackupService();
    final channel = FakeBackupChannel()..picked = '${dir.path}/picked-1.nimbus';
    File(channel.picked!).writeAsBytesSync(const [1]);

    await tester.pumpWidget(AppRestart(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        outsideChannelProvider.overrideWithValue(FakeOutsideChannel()),
        isForegroundProvider.overrideWithValue(() => true),
        backupServiceProvider.overrideWith((ref) async => service),
        backupChannelProvider.overrideWithValue(channel),
        backupStateStoreProvider
            .overrideWithValue(BackupStateStore('${dir.path}/backup_state.json')),
      ],
      child: const NimbuStatsApp(overrideLocale: Locale('en')),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('backup-restore')), 200);
    await tester.tap(find.byKey(const Key('backup-restore')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('backup-restore-passphrase')),
        FakeBackupService.goodPassphrase);
    await tester.tap(find.byKey(const Key('backup-restore-go')));
    await tester.pumpAndSettle();

    expect(service.calls, containsAllInOrder(['prepare', 'restore']));
    expect(find.byKey(const Key('tx-add-fab')), findsOneWidget); // Home
    expect(find.textContaining('Restored the backup from'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'undo');
    expect(find.text('Restore undone. Your earlier data is back.'), findsOneWidget);
    expect(find.byKey(const Key('tx-add-fab')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it and see RED**

Run from `app/`: `flutter test --no-pub test/features/backup/restart_flow_test.dart`. Expected: FAIL, because no `Restored the backup from…` text is found. Nothing shows the notice yet.

- [ ] **Step 3: Tag the parent**

```bash
git tag pre-restart-notice phase/7-backup
```

- [ ] **Step 4: Write the listener**

Create `app/lib/features/backup/presentation/restart_notice_listener.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/application/settings_providers.dart';
import '../application/backup_controller.dart';
import '../application/restart.dart';
import 'backup_messages.dart';

/// Shows, once, why the app just restarted (spec §5.3): a restore with Undo,
/// or an undone restore.
///
/// It wraps the shell's body, under the shell's Scaffold, so it is up
/// whenever Home is.
class RestartNoticeListener extends ConsumerStatefulWidget {
  const RestartNoticeListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RestartNoticeListener> createState() =>
      _RestartNoticeListenerState();
}

class _RestartNoticeListenerState extends ConsumerState<RestartNoticeListener> {
  RestartNotice? _pending;

  @override
  void initState() {
    super.initState();
    _pending = ref.read(restartNoticeProvider);
    if (_pending == null) return;
    // After the restored settings load (ruling R12): the message speaks
    // their language and calendar, not the defaults'.
    ref.listenManual(settingsProvider, (_, next) {
      if (next.hasValue || next.hasError) _showOnce();
    }, fireImmediately: true);
  }

  void _showOnce() {
    final notice = _pending;
    if (notice == null) return;
    _pending = null;
    // After the frame that applies the restored locale.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final messenger = ScaffoldMessenger.of(context);
      switch (notice) {
        case BackupRestored(:final backupCreatedAt):
          messenger.showSnackBar(nimbusUndoSnackBar(
            message: l10n.backupRestored(whenLabel(
                backupCreatedAt, ref.read(calendarProvider),
                persianDigits: ref.read(moneyFormatterProvider).persianDigits)),
            undoLabel: l10n.commonUndo,
            onUndo: () => unawaited(_undo(messenger, l10n)),
          ));
        case RestoreUndone():
          messenger.showSnackBar(SnackBar(content: Text(l10n.backupRestoreUndone)));
      }
    });
  }

  Future<void> _undo(
      ScaffoldMessengerState messenger, AppLocalizations l10n) async {
    try {
      await ref.read(backupControllerProvider).undo();
    } on Object catch (error, stack) {
      reportBackupFailure(error, stack, 'while undoing a restore');
      messenger.showSnackBar(SnackBar(content: Text(l10n.backupUndoFailed)));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

- [ ] **Step 5: Mount it on the shell**

In `app/lib/bootstrap/app_shell.dart`:
- Add `import '../features/backup/presentation/restart_notice_listener.dart';`.
- Replace `body: child,` with:

```dart
            // Phase 7: why the app just restarted, over Home (spec §5.3).
            body: RestartNoticeListener(child: child),
```

- [ ] **Step 6: Run it and see GREEN**

Run from `app/`: `flutter test --no-pub test/features/backup/`. Expected: all pass.

If `find.text('Settings')` matches more than the navigation label, tap `find.byKey(const Key('nav-bar'))`'s fifth destination instead. Do not change app code for the test.

- [ ] **Step 7: Run the broader suite**

Run the App suite and `dart analyze --fatal-infos`. Expected: green. The shell's existing tests are unaffected, because the listener is inert without a notice.

- [ ] **Step 8: Commit and merge**

```bash
git add app/lib/features/backup/presentation/restart_notice_listener.dart app/lib/bootstrap/app_shell.dart app/test/features/backup/restart_flow_test.dart
git commit -m "$(cat <<'EOF'
feat(backup): after a restore, Home says so and offers Undo

A restore rebuilds the whole app, so the sheet that started it is
gone; the user needs to see what happened where they land. The shell's
body carries a listener that shows the restart's notice once: the
backup's date with Undo, or that the restore was undone. It waits for
the restored settings so the message is in their language and calendar
(ruling R12). With the settings row, this is the "undo" that replaces
a confirmation (ruling R2). The test drives the shipped root,
AppRestart, through a restore and an undo.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only feat/restart-notice
```

---

### Task 14: On-device verification on the Galaxy A53

Spec §7 ("On the Galaxy A53"). This task covers the brief's definition-of-done items that need a device, and brief task 10.

**Ask the operator first.** Confirm that the A53 is free and unlocked, and that the NimbuStats data on it may be wiped. Ask again before any device-wide change (Step 6). Record every value measured here; Task 15 pastes them into the docs.

- [ ] **Step 1: Argon2id timing, from a throwaway patch**

```bash
git checkout -b scratch/kdf-timing phase/7-backup
```

In `app/lib/main.dart`, add `import 'dart:async';` and `import 'dart:isolate';` (and `package:flutter/foundation.dart` for `debugPrint`, if it is not already reachable). Right after `installErrorHooks('nimbustats');`, add:

```dart
  unawaited(Isolate.run(() async {
    for (final kdf in const [
      KdfParams(memoryKiB: 65536, iterations: 3, parallelism: 1),
      KdfParams(memoryKiB: 65536, iterations: 2, parallelism: 1),
      KdfParams(memoryKiB: 47104, iterations: 1, parallelism: 1),
      KdfParams(memoryKiB: 19456, iterations: 2, parallelism: 1),
    ]) {
      for (var run = 0; run < 3; run++) {
        final watch = Stopwatch()..start();
        await deriveBackupKeys('timing-only', kdf, List.filled(16, 7));
        debugPrint('kdf-timing $kdf ${watch.elapsedMilliseconds} ms');
      }
    }
  }));
```

Then run:

```bash
cd app && flutter build apk --profile
ADB=/c/dev/android-sdk/platform-tools/adb.exe
$ADB -s RZCT209E3QX install -r build/app/outputs/flutter-apk/app-profile.apk
$ADB -s RZCT209E3QX logcat -c
$ADB -s RZCT209E3QX shell am start -n com.nimbustats.app/.MainActivity
sleep 60; $ADB -s RZCT209E3QX logcat -d -s flutter | grep kdf-timing
```

Throw the patch away:

```bash
git checkout -- app/lib/main.dart && git checkout phase/7-backup && git branch -D scratch/kdf-timing
```

Take the median of each setting's three runs. **Decision rule:** pick the first of 64 MiB/t3, 64 MiB/t2, 46 MiB/t1, 19 MiB/t2 whose median is ≤ 2,000 ms. If none qualifies, stop and ask the operator.

If the choice is not 64 MiB/t3, make one TDD commit on `feat/kdf-params`:
1. Change `KdfParams.standard`.
2. The layout test in `backup_format_test.dart` reads the constant, so it stays green. Add a test asserting the new values, and see it RED first.
3. The commit message records the four medians.

- [ ] **Step 2: Install the debug build of the branch**

```bash
cd app && flutter build apk --debug && $ADB -s RZCT209E3QX install -r build/app/outputs/flutter-apk/app-debug.apk
```

Drive the UI as in the `device-check-over-adb` memory:
- `uiautomator dump` exposes Flutter semantics;
- re-read coordinates after focus;
- never swipe over the keyboard.

The passphrase is ASCII, `roundtrip-7042`, because `adb shell input text` cannot type Persian.

- [ ] **Step 3: The DoD round trip**

1. Run `$ADB logcat -c`.
2. Add an expense of 12,345 with the note `phase7-roundtrip`.
3. Go to Settings → Backup → Export. Type the passphrase twice, tap Encrypt, then Save to… → Downloads → Save. Expected: the "Backup saved." snackbar, and "Last export: <now>".
4. Wipe the app's data: `$ADB shell pm clear com.nimbustats.app`. `pm clear` rather than uninstall keeps Auto Backup's restore-at-install out of this result, and Step 6 tests Auto Backup on its own.
5. Launch the app and complete first run.
6. Go to Settings → Restore → the file in Downloads. The sheet must show "Backup from <the export's time>". Type the passphrase and tap Restore.

Expected:
- the app lands on Home;
- "Restored the backup from …" shows with Undo;
- the `phase7-roundtrip` expense is listed;
- `run-as com.nimbustats.app ls -l app_flutter/` shows `nimbustats.pre-restore.sqlite`.

- [ ] **Step 4: Errors on device**

- **Wrong passphrase:** restore the same file with `roundtrip-7043`. Expected: "Wrong passphrase." under the field, the sheet stays, and the data is unchanged.
- **Newer schema:** write a header-only file from a throwaway script inside the package, which it needs in order to import `nimbus_data`. Never commit it:

```bash
cd packages/nimbus_data
cat > tool/zz_newer.dart <<'EOF'
import 'dart:io';
import 'package:nimbus_data/nimbus_data.dart';
Future<void> main() async => File('newer.nimbus').writeAsBytesSync(await sealBackup(
    payload: const [0], passphrase: 'x', schemaVersion: 99, createdAt: DateTime.now(),
    kdf: const KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1)));
EOF
dart run tool/zz_newer.dart && rm tool/zz_newer.dart
$ADB push newer.nimbus /sdcard/Download/ && rm newer.nimbus
git status --short   # expect nothing new under packages/nimbus_data
```

  Pick it in the app. Expected: "This backup is from a newer version…", and no passphrase field.
- **Not a backup:** pick any photo. Expected: "This isn't a NimbuStats backup file." Then run `run-as com.nimbustats.app ls cache/backup/` and expect no `picked-*` file.

- [ ] **Step 5: After a restore, the app still works outside itself (R3)**

- **The widget.** If no widget is placed, place one as in the device-check memory. After the Step 3 restore, tap a tracker on the widget while the app is in the foreground. Expected: the entry appears in the app within seconds, and logcat shows no headless engine start. That means the app engine's `drainNow` handler survived the restart.
- **The reminder.** Turn the reminder on, export, turn it off, then restore that export. Expected: `$ADB shell dumpsys alarm | grep -A2 com.nimbustats.app` shows the reminder's alarm armed again.

- [ ] **Step 6: Auto Backup (ask first: device-wide)**

1. Check the setup: `$ADB shell bmgr enabled` and `$ADB shell bmgr list transports`. If backup is disabled, **ask the operator** before `bmgr enable true`, which is a phone-wide setting tied to their Google account.
2. Write an expense with note `phase7-autobackup`, run `$ADB shell am force-stop com.nimbustats.app`, then `run-as com.nimbustats.app ls -l app_flutter/`. Expected: `nimbustats.sqlite-wal` larger than 0.
3. Run `$ADB shell bmgr backupnow com.nimbustats.app`. Expected: `Package com.nimbustats.app with result: Success`.
4. Run `run-as … ls -l app_flutter/` again. Expected: the WAL is 0 bytes, which shows the agent's TRUNCATE ran.
5. Run:
   ```bash
   $ADB exec-out run-as com.nimbustats.app cat app_flutter/nimbustats.sqlite > "$SCRATCH/ab.sqlite"
   python3 -c "import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute(\"select count(*) from sqlite_master where name='android_metadata'\").fetchone())" "$SCRATCH/ab.sqlite"
   ```
   Expected: `(0,)`.
6. Run `$ADB uninstall com.nimbustats.app`, then `$ADB install build/app/outputs/flutter-apk/app-debug.apk`, then launch. Expected: `phase7-autobackup` is present.
7. If the transport cannot reach Google from this network (memory `network-google-access`), record "Auto Backup restore not verified: <reason>" and add a DEFERRED item in Task 15. Steps 3–5 still count.

- [ ] **Step 7: No key material in logs**

```bash
$ADB logcat -d | grep -c 'roundtrip-7042'      # expect 0
$ADB logcat -d | grep -ci 'passphrase'          # expect 0; inspect any hit
```

- [ ] **Step 8: Size on the device (ruling R7)**

In Settings, tap the debug tile "Seed 5,000 demo transactions" and wait for it to finish. Then:

```bash
$ADB shell am force-stop com.nimbustats.app
$ADB shell run-as com.nimbustats.app ls -l app_flutter/
```

Record the sizes of `nimbustats.sqlite` and `-wal`. Expected: the same order as the host's 4.0 MB vacuumed (the live file holds free pages too). The size warning must not show.

- [ ] **Step 9: Record**

Write the measured values into a list for Task 15:
- the four Argon2id medians and the parameters chosen;
- the round-trip result;
- the logcat counts;
- the WAL sizes before and after the backup;
- `android_metadata`;
- the Auto Backup restore, or why it was not verified;
- the database sizes;
- each finding (D41 and up).

---

### Task 15: Docs, the Persian review, and the gate

Slug: `phase-7-complete`. CONVENTIONS §5.

**Files:**
- Modify: `docs/DEVELOPMENT.md` (the size measurement and projection)
- Modify: `docs/phases/CONVENTIONS.md` (the ownership row)
- Modify: `docs/phases/phase-7-backup.md` (the gate record)
- Modify: `docs/phases/README.md` (the status board)
- Modify: `docs/phases/DEFERRED.md` (Task 14 findings, if any)
- Modify: `docs/superpowers/specs/2026-10-17-backup-7-design.md` (the status line)

- [ ] **Step 1: The Persian review**

List every new `fa` value with its English key and value:

```bash
git diff main -- app/lib/l10n/app_fa.arb | grep '^+ '
```

Ask the operator to approve or correct each one, as in Phases 5 and 6. Apply corrections in one commit on `feat/fa-review` and run `localization_test` green. **Do not tag the gate before this approval.**

- [ ] **Step 2: The full definition of done**

| Where | Command |
|---|---|
| repo root | `dart analyze --fatal-infos` |
| repo root | `dart test test/architecture_test.dart` |
| `packages/nimbus_domain/` | `dart test` |
| `packages/nimbus_data/` | `dart test` |
| `app/` | `flutter test --no-pub --concurrency=4 --timeout 90s` |
| `app/android/` | `./gradlew :app:testDebugUnitTest` |

Record the test counts. Expected: all green, with the app count up by this phase's tests.

- [ ] **Step 3: The docs**

```bash
git checkout -b docs/phase-7-complete phase/7-backup
```

- **`docs/DEVELOPMENT.md`:** append a section:

```markdown
## Backup size and the Auto Backup ceiling (measured 2026-10-17)

Android Auto Backup stops silently above 25 MB of app data (Phase 7
brief). The database is all but the whole of it.

| Measure | Value |
|---|---|
| Host, `DemoDataSeeder` 5,000 rows (2.5 tags each), vacuumed | 4,005,888 B (155,648 B with no rows) |
| Per 1,000 transactions, vacuumed | 770,048 B |
| Per 1,000 transactions, gzipped (the export's payload) | 160,962 B |
| A53, after seeding 5,000 rows, live file / WAL | <Task 14 Step 8> |

Projection at a heavy 20 transactions a day (7,300 a year, about 5.6 MB a
year): 25 MB in about 4.4 years. At 10 a day, about 8.8 years. Both are
under the spec's ten-year line, so the Backup section warns once
`page_count × page_size` passes 20 MiB (ruling R7). The export file is
about a fifth of the database's size.
```

- **`docs/phases/CONVENTIONS.md`:** in §3's table, below `| \`app/android/**/notifications/**\` | Phase 6 |`, add:

```markdown
| `app/android/**/backup/**` | Phase 7 |
```

- **`docs/phases/phase-7-backup.md`:** append `### Gate record (2026-MM-DD, Galaxy A53)` under `## Definition of done`. Tick each checkbox and paste Task 14's values. Name rulings R1–R13 in one line each, with R11's known limit, and list any DEFERRED items.
- **`docs/phases/README.md`:** set the Phase 7 row to:

```markdown
| 7 — Backup | [phase-7-backup.md](phase-7-backup.md) | **Complete** (2026-MM-DD). Auto Backup with the WAL checkpointed first, and a passphrase-encrypted export (Argon2id, AES-256-GCM) saved or shared anywhere and restored in place through SQLite's backup API, with one step of undo; verified on the Galaxy A53. Carried forward: <D-items or "none"> | `phase-7-complete` |
```

- **The spec:** set the status line to `**Status:** implemented; gate passed 2026-MM-DD (see the brief's gate record). Plan rulings R1–R13 record where the build departed.`
- **`DEFERRED.md`:** add each Task 14 finding as D41 and up, in the house format: a summary-table row, then a section with *what*, *why deferred* and *what unblocks it*.

```bash
git add docs
git commit -m "$(cat <<'EOF'
docs: Phase 7 is complete

Records the A53 gate: the Argon2id timing and the parameters it fixed,
a transaction exported, wiped and restored back, a wrong passphrase
and a newer-schema file each refused with their own message, the
agent's checkpoint emptying the WAL with no android_metadata table,
nothing of the passphrase in logcat, and the database's growth with
the 25 MB projection that put the size warning in. Adds the Phase 7
native ownership row and moves the board.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/7-backup && git merge --ff-only docs/phase-7-complete
```

- [ ] **Step 4: Merge and tag. Ask first.**

Use `superpowers:finishing-a-development-branch` with base branch `main`. If the operator chooses to merge locally:

```bash
git checkout main && git merge --ff-only phase/7-backup
git tag phase-7-complete
git tag --list 'phase-*-complete'
```

Do not push unless the operator asks.

---

## Self-review notes (for the reviewer of this plan)

- **Spec coverage:**
  - §1 → the file structure, Tasks 1–13.
  - §2.1 → Task 1.
  - §2.2–2.3 → Task 2.
  - §2.4 → Tasks 1, 3, 4 and 10.
  - §3.1 → Task 3.
  - §3.2 → Tasks 4 and 5.
  - §3.3 → Task 5 (sweep), plus the deletes in Tasks 3 and 4.
  - §4.1–4.2 → Task 6.
  - §4.3 → Task 5 (`databaseBytes`), Task 10 (the warning), Tasks 14 and 15.
  - §5.1 → Tasks 9 and 10.
  - §5.2 → Task 11.
  - §5.3 → Tasks 8, 12 and 13.
  - §5.4 → Tasks 10–12.
  - §6 → Task 7.
  - §7 → the tests in each task, plus Task 14.
  - §8 → nothing out of scope is built.
- **Brief definition of done:**
  - Round trip: Task 5 on the host, Task 14 Step 3 on the device.
  - Wrong passphrase vs corruption: Tasks 2 and 4.
  - Newer schema: Tasks 3 and 12, and Task 14.
  - An interrupted restore leaves the original intact: Task 5 (R1).
  - No key material in logs: Task 5, and Task 14 Step 7.
  - The 25 MB projection: Task 15.
  - The tag: Task 15.
- **Departures from the spec, all named:** R1 (the shape of the interrupted-restore test), R2 (sheets, not dialogs, and no confirm), R3 (a two-frame restart), R4 (the `.part` undo copy and its exclude), R5 (path-only channel arguments).
- **Verified before writing, not assumed (2026-10-17):**
  - The KAT constants and the pinned check value, against `cryptography 2.9.0`.
  - `VACUUM INTO ?` with a bound path.
  - The backup API into a live WAL file under an open drift connection.
  - The busy retry.
  - The page-size refusal: `SqliteException(8)`.
  - `gzip.decode` throws `FormatException`.
  - `File.rename` replaces on Windows.
  - Jalali 2026-10-17 is 1405/07/25.
  - `androidx.core` is on the compile classpath.
  - `ux_rules_test` forbids `showDialog(`.
  - `OutsideChannel.dispose` clears the shared handler.
  - The size per 1,000 transactions.
- **Widget-test hazards designed out:**
  - `BackupStateStore`, `BackupController.export` and `BackupController.discard` use synchronous file I/O, because async I/O never completes under `testWidgets`' fake clock.
  - The fakes complete immediately unless a gate is set.
  - Tests that hold a progress bar open use `pump`, not `pumpAndSettle`.
