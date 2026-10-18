# Phase 7 — Backup

## Kickoff prompt

```
Read docs/phases/CONVENTIONS.md and docs/phases/phase-7-backup.md, then
execute Phase 7. Do not read the other phase briefs or plans.
```

**Goal:** losing the phone must not mean losing the data — without running a
server, and without encrypting the live database.

**Ships:** Android Auto Backup working correctly for a WAL-mode SQLite
database, plus a passphrase-encrypted export the user can save anywhere and
restore from.

**Schema versions:** v60–v69 reserved. Expect to use **none**.
**Branch:** `phase/7-backup` · **Gate tag:** `phase-7-complete`

---

## Why this phase is unusually independent

The export mechanism is a **whole-database operation** — it dumps and restores
the SQLite file, so it does not care which tables exist. That makes Phase 7 the
one substantial phase that can be built at almost any point after Phase 0 and
merged without coordination.

It is the best parallel partner for Phase 3 (analytics), which is the largest
and most intricate phase and benefits from a partner that shares no files with
it.

The one dependency to respect: the **restore path must refuse a backup from a
newer schema version than the running app**, so the format carries the schema
version in its header. That is a header field, not a coupling to the table set.

---

## Prerequisites — verify, do not assume

```bash
git tag --list 'phase-*-complete'   # must include phase-0-complete
dart analyze --fatal-infos
```

---

## Required reading

- Spec: "Phase 7 — Backup" in the build sequence, and the Storage / Backup /
  DB-encryption rows in the decisions table
- `packages/nimbus_data/lib/src/database/app_database.dart` — how the database
  is opened, and where the file lives
- `packages/nimbus_domain/lib/src/entitlements/` — `Feature.cloudBackup` exists
  already; Drive backup is gated behind it in Phase 8

---

## Owns

```
packages/nimbus_data/lib/src/backup/**       export, import, format, checkpointing
app/lib/features/backup/**                   backup settings UI, file picker flow
app/android/app/src/main/res/xml/            Auto Backup rules
```

Additive edits to Phase 1's settings screen for the backup section.

**Must not touch:** any feature's tables or queries.

---

## Scope

**In:**

- **Android Auto Backup**, configured correctly — which specifically means
  checkpointing the WAL before the backup runs (see traps).
- **Passphrase-encrypted export**: a single file the user can put in Drive,
  Telegram, or anywhere else.
- **Import/restore**, transactional, with a schema-version check.
- Backup settings UI: export now, restore from file, last-backup timestamp.
- A documented statement of what is and is not backed up.

**Out:**

- **Sync. Explicitly not built** — one device, and sync is a separate future
  project. Do not add "just a little" bidirectional merging.
- Live database encryption. Android full-disk encryption plus the app sandbox
  cover the realistic threat, the key would live on the same device, and with
  no PIN, physical access is already conceded. The *backup* is encrypted; the
  live database is not.
- Google Drive `appDataFolder` upload — deferred to Phase 8, where OAuth
  verification is handled alongside the store release. Design the export format
  so Drive is a destination, not a rewrite.

---

## Known traps

- **The WAL is the whole problem.** In WAL mode, recent writes live in
  `<db>-wal`, not in `<db>`. Backing up only the `.db` file silently loses the
  most recent — and most valuable — data. Force
  `PRAGMA wal_checkpoint(TRUNCATE)` before any backup or export, and verify by
  writing a transaction, exporting, and restoring into a fresh database.
- **Phase 6 turned WAL on.** `AppDatabase.openAtPath` sets
  `journal_mode=WAL` and `busy_timeout=5000` on every connection (Phase 6
  spec §3), so from Phase 6 on every device has a live
  `nimbustats.sqlite-wal`, and two engines (the app's and the widget's
  headless drain) may hold the file at once. The checkpoint above is
  therefore not hypothetical.
- **Android Auto Backup has a 25 MB app-data cap.** Exceed it and backups stop
  — silently. Measure database growth per thousand transactions, project the
  ceiling, document it, and decide what happens when it is approached.
- **Auto Backup is invisible to the user.** They cannot see it, trigger it, or
  confirm it worked. That is precisely why the manual encrypted export exists
  alongside it; do not treat either as sufficient alone.
- **Use a real KDF.** Derive the key from the passphrase with Argon2id (or
  PBKDF2 with a high, recorded iteration count), a random per-file salt, and an
  AEAD cipher (AES-GCM). A raw hash of the passphrase is not encryption.
- **Version the format header** — magic bytes, format version, schema version,
  KDF parameters, salt, nonce. Without KDF parameters in the header, you can
  never change them without breaking every old backup.
- **Refuse a backup from a newer schema version.** Restoring a v40 backup into
  a v20 app corrupts data in ways migrations cannot fix. Fail loudly with a
  clear message; never attempt a partial restore.
- **Restore is transactional and atomic.** Restore into a temporary file,
  verify it opens and its schema version is acceptable, then swap. A restore
  that fails halfway must leave the original database untouched.
- **A wrong passphrase must fail cleanly**, distinguishably from a corrupt
  file, and must never leave a half-written database.
- **Never log the passphrase, the key, or any derived material.** Not at debug
  level, not "temporarily".
- **`local_date_key` travels with the data**, so restoring on a device in a
  different timezone does not shift historical dates. Worth a test, so nobody
  later "fixes" it into recomputing keys on import.

---

## Task outline

1. WAL checkpoint helper, with a test proving a just-written transaction
   survives export.
2. Backup format: header, magic bytes, versioning, KDF parameters.
3. Key derivation and AEAD encryption, with known-answer tests.
4. Export end to end, to a caller-supplied sink.
5. Import: header validation, schema-version gate, wrong-passphrase and
   corrupt-file paths.
6. Atomic restore with a temp-file swap and rollback on failure.
7. Android Auto Backup rules plus WAL checkpointing at backup time.
8. Backup settings UI: export, restore, last-backup timestamp.
9. Size measurement and the documented ceiling.
10. Round-trip verification on a real device.

---

## Definition of done

`CONVENTIONS.md` §5, plus:

- [x] Write a transaction, export, restore into a fresh install, and confirm the
      transaction is present — **on a real device**. This is the test that
      catches the WAL mistake.
- [x] Wrong passphrase fails cleanly and distinguishably from corruption.
- [x] A backup with a higher schema version is refused with a clear message.
- [x] A restore interrupted midway leaves the original database intact.
- [x] No key material appears in any log at any level.
- [x] Database size per 1,000 transactions measured; the 25 MB projection is
      recorded in `docs/DEVELOPMENT.md`.
- [ ] `git tag phase-7-complete`.

### Gate record (2026-10-18, Galaxy A53)

Against `CONVENTIONS.md` §5 on `3d9383e` (branch `phase/7-backup`). Device:
Galaxy A53 SM-A536E (`RZCT209E3QX`), profile build. The destructive checks ran
on a separate install, `com.nimbustats.app.p7check`, because the operator's real
data is on the phone; `pm clear` stood in for a fresh install. The real app was
force-stopped, safety-copied first, and verified byte-for-byte untouched after
(listing identical, integrity ok, same row counts); the test install and its
files were removed.

- `dart analyze --fatal-infos` reports no issues.
- Test suites, all green at `3d9383e`: architecture 7; `nimbus_domain` 424;
  `nimbus_data` 413; `app` 781, run with `--no-pub --concurrency=4 --timeout
  90s`; Kotlin JUnit 33 (`ReminderTimeTest` 14, `AmountParserTest` 6,
  `PendingOverlayTest` 6, `Uuid7Test` 4, `WidgetBufferTest` 3).
- **Persian review.** The operator approved all 40 new `fa` values as written
  (2026-10-18), including `backupUndoFailed` unchanged (a rewording was offered,
  not requested). No corrections, so no `feat/fa-review` commit.

Definition of done:

- [x] **Write, export, restore into a fresh install, confirm.** An expense of
      12,345 was saved; Export (passphrase `roundtrip-7042`) saved
      `Downloads/nimbustats-20261018-1228.nimbus` (5,768 B) with "Backup saved."
      and "Last export: 2026/10/18 12:28". After `pm clear` the Home was empty.
      Restore showed "Backup from 2026/10/18 12:28" and the consequence text; the
      right passphrase went Decrypting, then restarted onto Home with 12,345
      present and the snackbar "Restored the backup from 2026/10/18 12:28." with
      Undo. `cache/backup` was empty afterwards. The host WAL test (commit
      without closing, export, restore into a fresh database) covers the WAL
      mistake.
- [x] **Wrong passphrase fails cleanly and distinguishably.** "Wrong
      passphrase." and the sheet stays. A non-backup `.txt` gave "This isn't a
      NimbuStats backup file." and its copy was deleted. Host tests keep
      `WrongPassphrase`, `CorruptBackup` and `NotABackup` apart (one exception
      below).
- [x] **A higher schema version is refused.** A v99 header gave "This backup is
      from a newer version of NimbuStats. Update the app, then restore it." with
      no sheet, and the picked copy was deleted.
- [x] **An interrupted restore leaves the original intact.** Host: injected
      failures plus a delayed writer (R1); the swap is one write transaction.
      Not reproducible on the phone by design.
- [x] **No key material in any log.** Fresh logcat over an export
      (`hygiene-7042`), a wrong-passphrase restore (`hygiene-7043`) and a
      restore: 13,311 lines; the only occurrence of either passphrase is `adbd`
      logging the harness's own `input text` command; 0 lines outside `adbd`
      contain either; 0 lines contain "passphrase"; the app logged nothing under
      the flutter or NimbuStats tags. The host hygiene test covers exceptions
      and error reports.
- [x] **Size per 1,000 transactions, and the projection.** Host:
      770,048 B vacuumed, 160,962 B gzipped. A53 with 5,002 rows and 12,453 tag
      links: `page_count` 1047 x 4096 = 4,288,512 B, freelist 0, vacuumed
      4,014,080 B (host 4,005,888 B), live file 4,251,648 B + WAL 4,165,352 B
      before the checkpoint; far below the 20 MiB warning. The projection (about
      4.4 years at 20 a day to 25 MB) is in `docs/DEVELOPMENT.md`.
- [ ] `git tag phase-7-complete` — not part of this commit; the controller asks
      the operator first.

Also verified on the device:

- **Argon2id timing** (profile/AOT, three runs, median): 64 MiB/t3 2093 / 1477 /
  1235 ms (**1,477**); 64 MiB/t2 **781**; 46 MiB/t1 **289**; 19 MiB/t2 **205**.
  The median is under 2,000 ms, so `KdfParams.standard` stays 64 MiB/t3/p1; no
  `feat/kdf-params` commit.
- **Undo is a swap.** "Undo the last restore" gave an empty Home and "Restore
  undone. Your earlier data is back." (Undo), the copy kept, `undoRedoes` true;
  the row then read "Redo the last restore" and brought 12,345 back with "The
  restored backup is back." (Undo), `undoRedoes` false.
- **R3.** After restore, undo and redo restarts, an `openRoute` intent
  (`/goals`) reached the live Dart handler and the app pushed Goals.

**Not verified on the device: Auto Backup** (the agent's
`wal_checkpoint(TRUNCATE)`, no `android_metadata`, restore-at-install). Google's
backup transport never answered from this network: `backupnow` hung at the
`@pm@` send, then at `getBackupDestinationFromTransport`, across two attempts and
a cancel/retry, also after a network change. The operator chose to defer it (D41).
The checkpoint is covered by the host review and the wiring test only. The WAL
before the checkpoint was 898,192 B beside a 4,096 B main file on the test
install (the brief's trap), and 4,165,352 B beside the seeded database.

Rulings, one line each (plan R1–R13, then the ones taken in execution):

- **R1.** The interrupted-restore test is injected failures plus a delayed
  writer; sqlite3's backup retries busy forever.
- **R2.** No dialogs and no confirm step: bottom sheets, and Undo is the safety
  net.
- **R3.** `AppRestart` takes two frames so the old scope disposes before the new
  one builds.
- **R4.** The undo copy is written as `.part` and renamed only after a committed
  swap.
- **R5.** `saveDocument` and `shareFile` take only `path`; `FileProvider` serves
  `cache/backup/out/` only.
- **R6.** The header's KDF settings are bounded; out of bounds is
  `UnsupportedFormat`.
- **R7.** The size warning ships above 20 MiB.
- **R8.** A `SqliteException` on the decrypted file is reported as unexpected,
  not as corruption.
- **R9.** "Last export" records the hand-off to Save or Share.
- **R10.** The golden fixture uses 1 MiB/t1; tests use 64 KiB/t1.
- **R11.** `VACUUM INTO` and the swap run on the main isolate. **Known limit:**
  each busy attempt blocks the main thread for up to 50 ms, and a stuck lock
  queues every later backup operation.
- **R12.** The restart notice waits for the restored settings.
- **R13.** The shared test harness gains backup fakes by default.
- **R14.** Passphrase normalisation also folds U+0649 to U+06CC (format v1).
- **Undo is a swap** (operator decision, 2026-10-17): the copy is never
  destroyed; state in `undoRedoes`.
- **Task 13b.** A process-wide single-flight lock serialises every backup
  operation.
- **Busy timeout 50 ms** (was 5 s in the spec): Dart runs on Android's main
  thread here, so a 5 s wait is an ANR; the swap stays one transaction.
- **Key-input bytes.** Damage to the header's salt, KDF settings or key-check
  value reads as WrongPassphrase (or UnsupportedFormat via R6), not
  CorruptBackup; inherent to the key-check design.
- Spec amendments are recorded in the spec's "Amendments after implementation".

**Carried forward:** D41–D45 in `DEFERRED.md`.

---

## Parallelism notes

**Pair this with Phase 3.** Analytics is the heaviest phase in the project and
backup shares no file with it, takes no schema version, and depends on nothing
Phase 3 produces.

Also safe alongside 2B and 4a.
