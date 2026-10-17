# Phase 7 — Backup — design

**Status:** approved in conversation 2026-10-17; awaiting written-spec review.
**Brief:** `docs/phases/phase-7-backup.md`.
**Prerequisites:** `phase-0-complete` exists (all of 0–6 do).
**Schema:** none · **Branch:** `phase/7-backup` · **Gate:** `phase-7-complete`

## Context

Losing the phone must not mean losing the data — without a server, and without
encrypting the live database. Two mechanisms ship, because neither is enough
alone: Android Auto Backup (invisible, capped at 25 MB) and a
passphrase-encrypted export file the user keeps anywhere and restores from.

### What the code showed before the design

1. **The database is `app_flutter/nimbustats.sqlite`** — `main()` and
   `drainMain()` both open `getApplicationDocumentsDirectory()/nimbustats.sqlite`
   through `AppDatabase.openAtPath`, which sets `journal_mode = WAL` and
   `busy_timeout = 5000` on every connection. Two engines (the app's and the
   widget's headless drain) can hold the file at once. Schema is v40.
2. **The manifest declares no backup rules.** Auto Backup therefore already
   copies the whole data directory by default: the database, its `-wal`, its
   `-shm`, the widget buffer and the reminder prefs.
3. **The app holds one `AppDatabase`** as a `ProviderScope` override in
   `main.dart`; providers read it through `appDatabaseProvider`.
4. **Offline package state** (pub.dev reachability depends on the exit node,
   D3): `cryptography 2.9.0` and `pointycastle 4.0.0` resolve offline;
   `file_picker 12.2.0` and `share_plus 13.3.0` do **not** (missing
   `windows_file_picker`, `win32`). `androidx.core:core 1.13.1` is in the Gradle
   cache through Flutter's embedding, so `FileProvider` needs no download.
5. **`sqlite3 3.5.2` exposes the online backup API**
   (`Database.backup(toDatabase, nPage: -1)`), and `drift 2.34.3` has
   `NativeDatabase.opened`.
6. **Pure-Dart crypto is fast enough.** Measured AOT on the dev PC (x64):
   Argon2id 64 MiB / t=3 / p=1 in 513 ms; PBKDF2-SHA256 600k in 4,808 ms;
   AES-256-GCM 8 MiB in ~500 ms each way. The A53 is expected 3–5× slower;
   re-measured on device before parameters are fixed (§7).

### Decisions taken with the operator (2026-10-17)

| Question | Decision |
|---|---|
| Where an export goes | **Both** "Save to…" (Storage Access Framework) and "Share…" (share sheet), through one small Kotlin channel — no new plugin |
| Protection against restoring the wrong file | **Keep one pre-restore copy**; "Undo last restore" until the next restore replaces it |
| Passphrase policy | **At least 8 characters, typed twice** on export; no strength meter |
| Restore mechanism | **In place through SQLite's online backup API**, single step |
| Checkpoint failure inside the Auto Backup agent | Log and still back up (§4.2) |

### Where this design departs from the brief

- **Task 1's "checkpoint before export" becomes `VACUUM INTO`.** It writes a
  consistent single-file snapshot that already contains every committed WAL
  frame, without touching the live file and while the drain engine stays
  connected. The brief's test is kept unchanged: commit without closing,
  export, restore into a fresh database, the row is present. The explicit
  `wal_checkpoint(TRUNCATE)` moves to where it is the only option — the Auto
  Backup agent (§4).
- **"Restore into a temp file, then swap" is kept in spirit, not as a file
  rename.** A rename under the drain engine's open handle would send its writes
  to an unlinked inode and lose them silently. The swap is SQLite's backup API,
  which commits the whole database as one write transaction or rolls back.
- **The undo option dropped "or until the next export".** The option the
  operator chose said the undo lasts "until the next restore or export"; an
  export does not make the pre-restore data safe, so tying the copy's lifetime
  to it is arbitrary. The copy lives until the next restore replaces it, or an
  undo consumes it.

## 1. Architecture

```
packages/nimbus_data/lib/src/backup/        pure Dart — Phase 7 owns
  backup_format.dart     header encode/decode, constants
  backup_crypto.dart     passphrase normalisation, Argon2id, HKDF, AES-GCM
  backup_errors.dart     sealed BackupException family
  backup_service.dart    export, readHeader, prepare, restore, undo

app/lib/features/backup/                    Phase 7 owns
  application/           providers, controller, backup_state.json store
  data/                  backup channel (Dart side)
  presentation/          BackupSection, dialogs, sheets

app/android/app/src/main/kotlin/com/nimbustats/app/backup/   Phase 7 (new dir)
  NimbusBackupAgent.kt   checkpoint, then the XML rules
  BackupDocuments.kt     save / share / open through the backup channel
app/android/app/src/main/res/xml/
  backup_rules.xml               fullBackupContent (API 26–30)
  data_extraction_rules.xml      dataExtractionRules (API 31+)
  backup_file_paths.xml          FileProvider paths
```

**Shared files touched, each named in its commit:**
`AndroidManifest.xml` (agent, rules, FileProvider), `MainActivity.kt`
(register the backup channel and its activity results), `settings_screen.dart`
(one `BackupSection` line), `main.dart` (keyed restart wrapper),
`packages/nimbus_data/pubspec.yaml` + `test/architecture_test.dart`
(`cryptography`), the `nimbus_data` barrel (one export line), and both ARB
files (`backup`-prefixed keys).

**Not touched:** any table, DAO, query or migration. `backup_service.dart`
treats the database as a whole file.

## 2. The file format

### 2.1 Header

Big-endian integers. The whole header (bytes 0–75) is the AES-GCM associated
data, so changing any header byte — for instance lowering the schema version —
fails authentication.

| Offset | Size | Field |
|---|---|---|
| 0 | 8 | magic `NIMBUSBK` (ASCII) |
| 8 | 2 | format version = `1` |
| 10 | 4 | schema version — the payload's `PRAGMA user_version` |
| 14 | 8 | created at, UTC epoch ms |
| 22 | 1 | KDF id: `1` = Argon2id |
| 23 | 4 | Argon2id memory, KiB |
| 27 | 4 | Argon2id iterations |
| 31 | 1 | Argon2id parallelism |
| 32 | 16 | salt — random per file |
| 48 | 12 | nonce — random per file |
| 60 | 16 | key-check value |
| 76 | … | ciphertext ‖ 16-byte GCM tag |

**Payload** = `gzip(snapshot bytes)` (`dart:io` `gzip`), then encrypted.

File name: `nimbustats-YYYYMMDD-HHmm.nimbus`, ASCII digits, Gregorian, local
time. MIME `application/octet-stream`.

### 2.2 Keys

1. Normalise the passphrase (§2.3) and encode it as UTF-8.
2. `master = Argon2id(passphrase, salt, memory, iterations, parallelism)`,
   32 bytes. Starting parameters 64 MiB / 3 / 1; fixed after the A53
   measurement (§7). They live in the header, so changing them never breaks an
   old file.
3. `encKey = HKDF-SHA256(master, info: "nimbus-backup v1 enc")`, 32 bytes →
   AES-256-GCM.
4. `check = HKDF-SHA256(master, info: "nimbus-backup v1 check")`, 16 bytes →
   the header's key-check value.

All primitives come from `cryptography 2.9.0`, added to `nimbus_data`; the
architecture test is updated in the same commit.

The key-check value is what tells a wrong passphrase from a damaged file:
check mismatch → wrong passphrase; check matches but the GCM tag fails →
corrupt. It gives an attacker nothing the GCM tag does not already give, and
Argon2id's cost dominates either way.

### 2.3 Passphrase

- At least 8 characters counted as runes; typed twice on export, once on
  restore.
- Normalised before derivation so the same visible passphrase works across
  keyboards: Arabic `ي` (U+064A) → Persian `ی` (U+06CC), Arabic `ك` (U+0643) →
  Persian `ک` (U+06A9), Persian and Arabic-Indic digits → ASCII. Nothing is
  trimmed. The rule is part of format version 1.
- Never stored. The passphrase, `master`, `encKey`, `check` and anything
  derived from them never appear in a log, an error message, an exception's
  `toString`, or an error report — at any level.

### 2.4 Import errors

A sealed `BackupException` family, checked in this order:

| Error | Raised when | Checked |
|---|---|---|
| `NotABackup` | shorter than the header, or wrong magic | header |
| `UnsupportedFormat` | format version > 1, or unknown KDF id | header |
| `NewerSchema(backup, app)` | header schema version > `AppDatabase.schemaVersion` | header — **before the passphrase is asked for** |
| `WrongPassphrase` | key-check mismatch | after derivation |
| `CorruptBackup` | GCM tag fails, gunzip fails, payload `user_version` ≠ header, `integrity_check` ≠ `ok`, or page size ≠ live | after decryption |

A failure anywhere leaves the live database untouched (§3.3).

## 3. The pipeline — `BackupService`

The app injects every path: the live database file, a cache directory for
temp files, and the pre-restore copy's location
(`app_flutter/nimbustats.pre-restore.sqlite`).

### 3.1 Export — `exportTo(outPath, passphrase)`

1. `VACUUM INTO '<cache>/export-<uuid>.sqlite'` on the live connection.
2. `Isolate.run`: read the snapshot, gzip, derive, encrypt, write `outPath`.
3. `finally`: delete the snapshot.

`shortcut: whole file in memory, upgrade to chunked encryption when a database
passes ~50 MB` — a code comment at the read.

### 3.2 Restore — two calls, so the user confirms between them

1. **`readHeader(path)`** → `BackupHeader` or a header-level error.
   `NewerSchema` is refused here.
2. **`prepare(path, passphrase)`** → `PreparedRestore`:
   1. `Isolate.run`: derive, check, decrypt, gunzip to
      `<cache>/import-<uuid>.sqlite`.
   2. Open that file once with `AppDatabase.openAtPath`, so an older backup
      (e.g. v32) migrates to v40 through the same migrations every install
      runs; check `PRAGMA integrity_check` and the page size; close it.
   3. Return the header's created-at for the confirm dialog.
3. **`restore(prepared)`**:
   1. `VACUUM INTO` the pre-restore copy (replacing any previous one).
   2. Open a raw `sqlite3` connection to the live file with
      `busy_timeout = 5000` and run
      `tempDb.backup(liveRaw, nPage: -1)` — one write transaction.
   3. `finally`: close both raw connections, delete the temp file.
   4. `notifyUpdates` for every table of the live `AppDatabase`.
4. **`undo()`**: the same backup step from the pre-restore copy, then delete it.

`discard(prepared)` deletes the temp file when the user cancels at the
confirm dialog.

### 3.3 Atomicity and leftovers

- `backup(nPage: -1)` holds the destination's write lock and commits once; an
  error rolls it back. The drain engine's connection waits on its busy timeout
  and then reads the new content.
- Temp files live in the cache directory (excluded from Auto Backup by
  default) and are deleted in `finally`. Because a crash mid-export would leave
  a plaintext copy behind, the backup screen also deletes every stale
  `export-*` / `import-*` file when it opens.

## 4. Android Auto Backup

### 4.1 Rules

Manifest: `android:allowBackup="true"`, `android:fullBackupOnly="true"`,
`android:backupAgent=".backup.NimbusBackupAgent"`,
`android:fullBackupContent="@xml/backup_rules"`,
`android:dataExtractionRules="@xml/data_extraction_rules"` (both
`<cloud-backup>` and `<device-transfer>`).

Exclude-only rules, identical in both files:

- exclude `root` `app_flutter/nimbustats.sqlite-shm` — rebuilt on open;
- exclude `root` `app_flutter/nimbustats.pre-restore.sqlite` — local undo only.

Kept by default: the database, its (emptied) WAL, the widget's pending buffer
(entries not yet drained exist only there), the widget snapshot, the reminder
prefs, and `backup_state.json`. Cache is excluded by Android.

### 4.2 The agent — `NimbusBackupAgent`

`onFullBackup(data)`:

1. Open the database with the framework `SQLiteDatabase.openDatabase` and the
   flags `OPEN_READWRITE | ENABLE_WRITE_AHEAD_LOGGING | NO_LOCALIZED_COLLATORS`.
   The last flag is required: without it Android creates an
   `android_metadata` table in our file.
2. `PRAGMA wal_checkpoint(TRUNCATE)`; close.
3. `super.onFullBackup(data)`, which applies the XML rules.

**Trade-off, approved:** if steps 1–2 throw, the agent logs with `Log.e` (no
data in the message) and still calls `super`. Android shuts the app process
down for Auto Backup, so the database and WAL on disk are a consistent pair
and SQLite recovers the WAL on open. Skipping the backup would trade a small
risk for a certain loss.

### 4.3 The 25 MB ceiling

Measure bytes per 1,000 transactions on a vacuumed, seeded database (with
tags, as real use has), project when 25 MB is reached at a heavy-use rate, and
record both in `docs/DEVELOPMENT.md`. If the projection is under ~10 years, the
backup section shows a size warning once the database passes 20 MB; otherwise
it is documented only.

## 5. The app

### 5.1 `BackupSection` (in Settings)

- "Last export: \<date and time in the active calendar\>" — or "Never exported"
  (empty state).
- **Export** and **Restore** buttons.
- **Undo last restore** — only while the pre-restore copy exists.
- "What's backed up": everything in the app — expenses, categories, tags,
  payment methods, trackers, goals, saved views and settings (the daily
  reminder's time included — it is a `settings` key). Not included in the
  export file: widget entries still waiting in the widget's buffer. Plus the
  warning that a forgotten passphrase cannot be recovered.

`backup_state.json` (`app_flutter/`) holds the last export time. It is kept out
of the database so that restoring an old backup cannot rewind it. It records
the hand-off to Save or Share; whether a share target kept the file is outside
the app's knowledge.

### 5.2 Export flow

Passphrase dialog (two obscured fields, ≥ 8, must match) → progress →
sheet with **Save to…** / **Share…** → snackbar with the result. Cancelling the
system picker is not an error.

### 5.3 Restore flow

Pick a file → `readHeader` (a newer schema is refused here, with "update the
app") → passphrase → `prepare` with progress → confirm: "Replace all data on
this phone with the backup from \<date\>? You can undo this." → `restore` →
the app restarts its `ProviderScope` and lands on Home with a snackbar.

The restart is a keyed wrapper around the root in `main.dart`: a new key
rebuilds every provider while the `AppDatabase` object stays the same (its file
content changed in place). Whatever Phase 6 runs at app start — re-arming the
reminder, refreshing the widget snapshot — must run again through that
rebuild; the plan verifies it rather than assuming it.

### 5.4 States, strings, accessibility

Every view has empty, loading, error and populated states. Each
`BackupException` maps to its own message. All strings exist in `app_en.arb`
and `app_fa.arb` with the `backup` prefix. RTL and LTR, Persian and Latin
numerals, dynamic type, screen-reader labels on every control.

## 6. The native channel — `com.nimbustats.app/backup`

A new channel, separate from Phase 6's `outside` channel, registered in
`MainActivity`.

| Method | Does | Returns |
|---|---|---|
| `saveDocument(path, name)` | `ACTION_CREATE_DOCUMENT`, then copies the file into the chosen URI | `true` saved, `false` cancelled |
| `shareFile(path, name)` | `FileProvider` URI (cache path only) + `ACTION_SEND` chooser | `null` when the chooser opened |
| `openDocument()` | `ACTION_OPEN_DOCUMENT` (`*/*`), copies into the cache | the cache path, or `null` cancelled |

I/O failures are returned as `PlatformException` with a code, never swallowed.

## 7. Testing

TDD per commit. `nimbus_data` tests use file-backed databases in a temp dir
where WAL matters.

**`nimbus_data`**

- Header encode/decode round trip; each header error (`NotABackup`,
  `UnsupportedFormat`, `NewerSchema`).
- Known-answer tests: Argon2id (RFC 9106 §5.3 vector), AES-256-GCM (a NIST
  vector), HKDF-SHA256 (RFC 5869 case 1).
- Passphrase normalisation table.
- **Golden fixture:** a small backup file committed under `test/fixtures/` with
  a known passphrase. It must keep decrypting; any change that breaks old files
  fails CI.
- Wrong passphrase → `WrongPassphrase`; a flipped ciphertext byte, a flipped
  header byte and a truncated file → `CorruptBackup` (or `NotABackup` for a
  truncated header); never confused with each other.
- **WAL:** write a transaction on a file-backed WAL database without closing
  it, export, restore into a fresh database — the row is present.
- **Interrupted restore:** a second connection holds a write transaction with
  the restorer's busy timeout set short; the backup step fails; the live file's
  content is unchanged.
- **Older schema:** a v32 database (built with the existing migration-test
  schema snapshots) exported and restored into v40 migrates.
- **`local_date_key` travels:** restoring under a different `TZ` leaves every
  stored `local_date_key` unchanged.
- **No key material in logs:** capture `Logger`/zone prints and error reports
  through export, a wrong-passphrase import and a corrupt import; assert
  neither the passphrase nor any derived byte string appears, and that
  exceptions' `toString` carry neither.

**app**

- `BackupSection` states; passphrase validation; error → message mapping;
  restart after restore lands on Home with fresh providers.

**On the Galaxy A53** (all its data is disposable)

- Argon2id timing → fix the parameters (target ≤ ~2 s per derivation).
- **The definition-of-done round trip:** add a transaction, export, uninstall,
  reinstall, restore — the transaction is present.
- Wrong passphrase and a newer-schema file on device.
- Auto Backup: `adb shell bmgr backupnow com.nimbustats.app`, uninstall,
  reinstall (restore at install) — data present, no `android_metadata` table.
- `adb logcat` grep for the passphrase through every flow: nothing.
- Size per 1,000 transactions and the 25 MB projection (§4.3).

## 8. Out of scope

Sync of any kind; Google Drive upload (Phase 8 sends the same file to a new
destination); showing when Auto Backup last ran; a passphrase strength meter;
streaming / chunked encryption; live-database encryption.
