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

- [ ] Write a transaction, export, restore into a fresh install, and confirm the
      transaction is present — **on a real device**. This is the test that
      catches the WAL mistake.
- [ ] Wrong passphrase fails cleanly and distinguishably from corruption.
- [ ] A backup with a higher schema version is refused with a clear message.
- [ ] A restore interrupted midway leaves the original database intact.
- [ ] No key material appears in any log at any level.
- [ ] Database size per 1,000 transactions measured; the 25 MB projection is
      recorded in `docs/DEVELOPMENT.md`.
- [ ] `git tag phase-7-complete`.

---

## Parallelism notes

**Pair this with Phase 3.** Analytics is the heaviest phase in the project and
backup shares no file with it, takes no schema version, and depends on nothing
Phase 3 produces.

Also safe alongside 2B and 4a.
