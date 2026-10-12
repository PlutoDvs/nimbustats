# Phase 6 — Outside the App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reach the user without the app being opened. A home-screen widget logs an expense or a tracker tap in under a second. A goal crossing becomes a notification within seconds. One optional daily reminder can be switched on.

**Architecture:**
- **Taps never start Flutter.** A widget tap is native end to end: one line appended to a buffer file.
- **A background job drains the buffer.** It hands the work to the app's live engine if there is one, and otherwise boots a headless Dart engine at `drainMain`.
- **The drain writes through the existing repositories.** Each buffer line carries its own id, which becomes the row id, so every tap is written exactly once.
- **The drain then runs Phase 5's goal check.** An `AlertRouter` shows each alert as a snackbar in the foreground, or posts a notification otherwise.
- **The two sides talk over one MethodChannel.** Native code only displays text; Dart sends every string, already in the app's language.

**Tech Stack:**
- Flutter 3.47.1 / Dart 3.13.1, drift 2.34.3 and Riverpod 3.
- Kotlin on Android framework APIs only: `AppWidgetProvider`, `RemoteViews`, `JobScheduler`, `AlarmManager`, `Notification`, `java.time` and ICU.
- JUnit 4.13.2, test-only.

**Spec:** `docs/superpowers/specs/2026-10-12-outside-6-design.md`. It is the binding authority, and this plan argues from it. Read §1.1, the channel contract, before any native or channel task.

---

## Global Constraints

Every task's requirements include this section.

**Toolchain and dependencies**
- **Flutter 3.47.1 / Dart 3.13.1.** No SDK bump and no pub dependency added. `pubspec.lock` is unchanged by this phase.
- **Android:** `minSdk = 26` (the operator's decision on 2026-10-12, so `java.time` is native), `compileSdk`/`targetSdk` = Flutter's 36. AGP 9.1.0, Kotlin 2.4.0, Gradle 9.3.1, `android.builtInKotlin=false`. No runtime Gradle dependency. The one addition is `testImplementation("junit:junit:4.13.2")`.
- **Network:** before any Gradle run that resolves a new artifact, check the exit and probe the host:
  - Run `curl -s https://api.ipify.org`, then `curl -sI https://repo.maven.apache.org/maven2/junit/junit/4.13.2/junit-4.13.2.pom` four times.
  - `5.237.x` or `5.215.x` means the direct path, which is blocked.
  - If Maven Central does not answer 200 four times out of four, stop and ask the operator to switch the VPN to whole-system mode. Never probe through the system proxy, and never drop JUnit.

**Schema and manifest**
- **Schema:** no version is used. `schemaVersion` stays 40, and the registry row for v50–v59 stays "—".
- **Manifest permissions:** add exactly `POST_NOTIFICATIONS` and `RECEIVE_BOOT_COMPLETED`. Never add `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM` or `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.

**Channel and files**
- **Channel name:** `com.nimbustats.app/outside`. The methods, arguments and returns are exactly spec §1.1.
- **Files under `context.filesDir`:**
  - `widget_buffer.jsonl`
  - `widget_buffer.rejected.jsonl`
  - `widget_snapshot.json`
- **Buffer line:** `{"v":1,"id":"<uuidv7>","kind":"expense"|"tracker","atUtc":<epoch ms>, …}`. An expense adds `amountMinor` (an int in 1..999 999 999 999 999) and `categoryId` (a string or null). A tracker tap adds `trackerId`.
- **Snapshot:** `v` = 1. Its fields are exactly spec §6.1.

**Settings keys**
- `reminder_enabled` (default `false`), `reminder_minute_of_day` (default `1260`) and `notification_detail` (default `false`).
- None of them is in `SettingsKeys.appSettings`.
- A present-but-unparseable value is reported through `FlutterError.reportError` and reads as its default.

**Strings and errors**
- **ARB:** new keys are prefixed `notifications…` or `widget…`, inserted in alphabetical position in both `app_en.arb` and `app_fa.arb`. `app_fa.arb` carries no `@` metadata (house style). The operator reviews every Persian value before the gate.
- **No silent failures:**
  - Dart reports through `FlutterError.reportError` with `library` set to exactly `widget drain`, `alert router` or `reminder`.
  - Native logs `Log.e("NimbuStats", …)`.
  - No `print`, and no swallowed exception.

**Tests and commits**
- **No host test is possible for Android glue.** That covers receivers, the job service, `RemoteViews`, the dialog activity and `MainActivity`. Each such task compiles it with `flutter build apk --debug`, its commit message says "verified on device in Task 17", and Task 17 proves it on the A53.
- **Pure Kotlin logic gets JUnit tests:** `ReminderTime`, `AmountParser`, `PendingOverlay` and `Uuid7`. They import no `android.*` and no `org.json`.
- **TDD order per commit:**
  1. Write the failing test, then run it and see RED.
  2. Tag the parent `pre-<slug>`.
  3. Implement, then run the test and see GREEN.
  4. Run the broader suite.
  5. Commit, with a message explaining why.
  6. Fast-forward into `phase/6-outside-the-app`.
- **Commit trailer:** every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never stage `bash.exe.stackdump`.

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
- Tests never await a drift `watch()` stream's `.first` inside `testWidgets`. Read streams through `firstOf(tester, stream)` and use one-shot DAO reads in app code. See the `drift-stream-first-hangs-widget-tests` memory.

**Device rules**
- The A53 (`RZCT209E3QX`) is the operator's daily phone.
- Before driving it, confirm it is free and unlocked.
- Ask before the reboot and before the time-zone change, and restore afterwards.
- `adb` is at `C:\dev\android-sdk\platform-tools\adb.exe`. Use `MSYS_NO_PATHCONV=1` for device paths in Git Bash.

## Rulings this plan makes

The spec leaves these open, or the code contradicts it. Each is decided here and named in its commit.

| # | Ruling | Why | If wrong |
|---|---|---|---|
| R1 | `minSdk = 26` | The operator's decision (2026-10-12). `java.time` (spec §5) is API 26+ and desugaring was rejected | Android 7 phones can't install the app. Reverting means replacing `java.time` |
| R2 | The WAL and busy-timeout pragmas are set in `NativeDatabase(setup:)`, not in `beforeOpen` | `setup` runs on each connection before drift's own version check. A second engine opening at the same moment would contend on that check before `beforeOpen` ever ran | None. Same pragmas, set earlier |
| R3 | "Exactly once" is decided by the primary key, not by a read before the write | A read then a write lets two drains race, as the once-per-day index comment in `TrackerEntriesDao` already argues. The new `LogResult` variant `AlreadyLogged` says "this id was written before" | One extra sealed-class case in `tracker_logger.dart` |
| R4 | One native handler, `OutsideChannelHandler`, serves both engines | MainActivity's engine and the headless one answer the same Dart → native methods. A `notImplemented` reply to `drainNow` is what sends the job to the headless engine | None |
| R5 | `main.dart` exports `drain_main.dart` | An AOT build compiles only libraries reachable from `main`. `@pragma('vm:entry-point')` keeps a function alive, but not a library nothing imports | None |
| R6 | The two Dart bridges (`WidgetSync`, `NotificationsBridge`) mount in `AppShell` | A drain before first run would fail the category foreign key, and route handling needs the router. The shell exists exactly when both hold. This is an additive edit to a bootstrap file | None |
| R7 | `NotificationPermission` is folded into `OutsideChannel` | Its three methods are pass-throughs of channel methods. A wrapper class would add a file and nothing else | None |
| R8 | The dialog rejects negative amounts | `MoneyFormatter.parse` accepts `-`, and the add screen flips the sign. A widget dialog records spending only, so `-` disables Save | Users never type `-` there |
| R9 | Tracker taps and the midnight refresh go to a **non-exported** `WidgetActionReceiver`, not to the exported `ExpenseWidgetProvider` | The provider must be exported for the system's update broadcast. Any app could then send it a "tap" | None |
| R10 | `drainFinished(ok)`: `ok` is true only when every line was acked or rejected | Then a job that finds new lines left after a clean drain can reschedule itself, while a failing line never loops (spec §2.4) | None |
| R11 | A row the headless engine writes while the app engine is alive does not refresh the app's open lists until their next write | Drift's change notifications are per connection. The window is the few seconds of a headless drain with the app opened during it, and the job hands a live engine the work instead | A list stale for seconds. Recorded in the gate record |

## Review Focus

Five failures that no spec-listed test reaches, most likely first. Each has a test in its owning task.

1. **A tap at 23:59 that drains after midnight.** The entry must land on the tap's day. The widget's overlay must not count it toward the new day. Task 13 tests that the tap time is kept across midnight. Task 12 tests, through `PendingOverlay`, that only today's pending taps count.
2. **Persian digits with the Persian group separator.** `۱۲٬۵۰۰` typed in the dialog must save 12 500. Task 12 has an `AmountParser` case for it.
3. **The app opened while a headless drain runs.** Two engines drain the same lines at once against one database file, and each item must be written once. Task 13 tests this on a temp-file database with two connections.
4. **Notifications blocked for good.** Switching the reminder on must leave it off, never call `setReminder(enabled: true)`, and show the blocked row. Task 10 tests this.
5. **The language switched while a reminder is armed.** The reminder text must be re-pushed in the new language, and the channels renamed. Task 9 tests this.

---

## File structure

**Native**, under `app/android/app/src/main/kotlin/com/nimbustats/app/`:

| File | Does |
|---|---|
| `MainActivity.kt` | Registers the channel. Keeps the launch route. Asks for the permission. Forwards notification taps |
| `OutsideChannelHandler.kt` | Dart → native methods for both engines (R4), plus the live app channel holder |
| `widget/WidgetBuffer.kt` | The buffer and snapshot files, under one lock |
| `widget/WidgetSnapshot.kt` | Parses and version-checks the snapshot |
| `widget/Uuid7.kt` | Pure. The UUIDv7 for each line |
| `widget/AmountParser.kt` | Pure. The dialog's amount to minor units |
| `widget/PendingOverlay.kt` | Pure. Today's value with pending taps |
| `widget/DrainScheduler.kt` | Enqueues the one drain job |
| `widget/DrainJobService.kt` | Hands off to the live engine, or runs `drainMain` headless |
| `widget/ExpenseWidgetProvider.kt` | The `AppWidgetProvider` |
| `widget/WidgetRenderer.kt` | Builds the `RemoteViews` |
| `widget/WidgetActionReceiver.kt` | Tracker taps and the midnight refresh (R9) |
| `widget/ExpenseEntryActivity.kt` | The add-expense dialog |
| `notifications/Notifier.kt` | Channels, alert and reminder posting, the route intent |
| `notifications/ReminderTime.kt` | Pure. The next trigger and the next midnight |
| `notifications/ReminderScheduler.kt` | Arms and cancels the reminder and the midnight refresh |
| `notifications/ReminderReceiver.kt` | Fires the reminder |
| `notifications/RearmReceiver.kt` | Re-arms after boot, time-zone, time-set, locale and package-replaced broadcasts |

**Native resources**, under `app/android/app/src/main/res/`:
- `layout/widget_expense.xml`, `layout/widget_tracker_row.xml`, `layout/widget_loading.xml` and `layout/activity_expense_entry.xml`.
- `xml/expense_widget_info.xml`.
- Drawables: `drawable/ic_stat_nimbus.xml`, `drawable/widget_background.xml`, `drawable/widget_button.xml`, `drawable/widget_dot.xml`, `drawable/ic_widget_add.xml`, `drawable/ic_widget_done.xml` and `drawable/entry_chip.xml`.
- `color/entry_chip_text.xml`.
- `values/colors.xml`, `values-night/colors.xml`, and additions to `values/styles.xml` and `values-night/styles.xml`.

**Native tests**, under `app/android/app/src/test/kotlin/com/nimbustats/app/`:
- `notifications/ReminderTimeTest.kt`
- `widget/AmountParserTest.kt`
- `widget/PendingOverlayTest.kt`
- `widget/Uuid7Test.kt`

**Dart**, under `app/lib/`:

| File | Does |
|---|---|
| `drain_main.dart` | The headless entrypoint |
| `features/notifications/data/outside_channel.dart` | The one platform boundary, and `outsideChannelProvider` |
| `features/notifications/data/notification_prefs.dart` | The three keys: parse, report, load, watch, save |
| `features/notifications/application/notification_providers.dart` | Providers for prefs and the foreground check |
| `features/notifications/application/alert_router.dart` | The only subscriber to the watcher's alerts |
| `features/notifications/application/reminder_controller.dart` | Turns the reminder on, off and to a new time, and pushes it |
| `features/notifications/application/permission_request.dart` | Asks for the permission and reports a channel failure |
| `features/notifications/application/outside_errors.dart` | `reportingFailure`: reports a failed fire-and-forget channel call |
| `features/notifications/presentation/notifications_bridge.dart` | Channels, reminder re-push, launch and tap routes |
| `features/notifications/presentation/notifications_section.dart` | The settings section |
| `features/widget/application/snapshot_writer.dart` | Builds the snapshot JSON |
| `features/widget/application/widget_drain.dart` | Parses lines and writes them through the repositories |
| `features/widget/application/drain_service.dart` | One drain run: take, write, commit, report, check goals |
| `features/widget/presentation/widget_sync.dart` | The app engine's drain and snapshot triggers |

**Edits outside Phase 6's directories.** Each is additive and named in its commit:

| File | Change |
|---|---|
| `packages/nimbus_data/lib/src/database/app_database.dart` | WAL pragmas (R2), the `onlyIfAbsent` insert |
| `packages/nimbus_data/lib/src/database/sqlite_errors.dart` | New: `isPrimaryKeyViolation` |
| `packages/nimbus_data/lib/src/trackers/tracker_entries_dao.dart` | `onlyIfAbsent` |
| `packages/nimbus_data/lib/src/trackers/trackers_dao.dart` | One-shot `allLive` |
| `packages/nimbus_domain/lib/src/trackers/tracker_results.dart` | `AlreadyLogged` |
| `app/lib/features/transactions/data/transaction_repository.dart` | `add(id:)` |
| `app/lib/features/transactions/application/prediction_providers.dart` | `loadCategoryPredictor` extracted |
| `app/lib/features/trackers/data/tracker_repository.dart` | `logEntry(id:)` |
| `app/lib/features/trackers/presentation/widgets/tracker_logger.dart` | The new case |
| `app/lib/features/goals/application/goal_watcher.dart` | `checkNow` |
| `app/lib/features/goals/presentation/goal_alert_listener.dart` | The foreground stream |
| `app/lib/features/goals/presentation/goal_editor_screen.dart` | The first-goal permission ask |
| `app/lib/features/settings/data/settings_keys.dart` | Three keys |
| `app/lib/features/settings/presentation/settings_screen.dart` | One section line |
| `app/lib/bootstrap/app_shell.dart` | The two bridges (R6) |
| `app/lib/main.dart` | The export (R5) |
| `app/lib/l10n/app_{en,fa}.arb` | New keys |
| `app/test/support/harness.dart` | The fake channel by default |
| `app/android/app/build.gradle.kts` | `minSdk 26`, JUnit |
| `app/android/app/src/main/AndroidManifest.xml` | Permissions and components |

**Dart tests**, under `app/test/features/`:
- `notifications/outside_channel_test.dart`
- `notifications/notification_prefs_test.dart`
- `notifications/alert_router_test.dart`
- `notifications/reminder_controller_test.dart`
- `notifications/notifications_bridge_test.dart`
- `notifications/notifications_section_test.dart`
- `notifications/support/fake_outside_channel.dart`
- `widget/snapshot_writer_test.dart`
- `widget/support/buffer_lines.dart`
- `widget/widget_drain_test.dart`
- `widget/drain_service_test.dart`
- `widget/widget_sync_test.dart`

Existing test files gain cases:
- `goals/goal_watcher_test.dart` and `goals/goal_editor_screen_test.dart`
- `transactions/transaction_repository_test.dart`
- `trackers/tracker_repository_test.dart`
- the data package's `open_database_test.dart`, `transactions_test.dart` and `trackers/tracker_entries_dao_test.dart`

## Branching

`docs/outside-6-spec` holds the spec and this plan.

1. Create the dev branch at the plan commit: `git branch phase/6-outside-the-app docs/outside-6-spec`.
2. For each task with slug `<slug>`:

   ```bash
   git checkout -b feat/<slug> phase/6-outside-the-app
   # … write the failing test, see RED …
   git tag pre-<slug> phase/6-outside-the-app
   # … implement, see GREEN, run the broader suite, commit …
   git checkout phase/6-outside-the-app && git merge --ff-only feat/<slug>
   ```

3. The gate (Task 18) fast-forwards `main` to `phase/6-outside-the-app` and tags `phase-6-complete`.
4. Push only when the operator asks.

---
### Task 1: The database file shares itself with a second engine (WAL + busy timeout)

Slug: `wal-busy-timeout`. Spec §3, ruling R2.

**Files:**
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` (`openAtPath`, around line 67)
- Test: `packages/nimbus_data/test/open_database_test.dart`
- Modify: `docs/phases/phase-7-backup.md` (one bullet under "Known traps")

**Interfaces:**
- Consumes: nothing new.
- Produces: every file-backed `AppDatabase` runs `journal_mode=WAL` with `busy_timeout=5000`. Later tasks open the same file from two engines.

- [ ] **Step 1: Create the dev branch and the task branch**

```bash
git branch phase/6-outside-the-app docs/outside-6-spec
git checkout -b feat/wal-busy-timeout phase/6-outside-the-app
```

- [ ] **Step 2: Write the failing tests**

Append to `packages/nimbus_data/test/open_database_test.dart`. Add `import 'dart:isolate';` at the top. Put the two helpers below `main`, top level, so the second isolate can run them:

```dart
  group('a file-backed database shared with a second engine (Phase 6)', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('nimbus_wal_test');
      path = '${dir.path}${Platform.pathSeparator}nimbustats.sqlite';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Object?> pragma(AppDatabase db, String name) async =>
        (await db.customSelect('PRAGMA $name').get()).single.data.values.first;

    test('runs in WAL mode with a five-second busy timeout', () async {
      final db = AppDatabase.openAtPath(path);
      addTearDown(db.close);
      await db.settingsDao.put('k', 'v');

      expect(await pragma(db, 'journal_mode'), 'wal');
      expect(await pragma(db, 'busy_timeout'), 5000);
      // The file Phase 7's backup must checkpoint, and device checks copy.
      expect(File('$path-wal').existsSync(), isTrue);
    });

    test('a second engine writing at the same time waits rather than fails',
        () async {
      // The app engine opens (and migrates) first, as it does at start.
      final app = AppDatabase.openAtPath(path);
      addTearDown(app.close);
      await app.settingsDao.get('warm');

      // A real second isolate, like the headless drain engine: each opens its
      // own SQLite connection, so the two write transactions truly overlap.
      final drain = Isolate.run(() => _writeSettings(path, 'drain', 200));
      await _writeSettingsOn(app, 'app', 200);
      await drain;

      final keys = (await app.settingsDao.getAll()).keys;
      expect(keys.where((k) => k.startsWith('app-')), hasLength(200));
      expect(keys.where((k) => k.startsWith('drain-')), hasLength(200));
    });
  });
```

```dart
/// Opens its own connection to [path] and writes [count] settings, one
/// transaction each: what the headless drain engine does to the same file.
Future<void> _writeSettings(String path, String prefix, int count) async {
  final db = AppDatabase.openAtPath(path);
  try {
    await _writeSettingsOn(db, prefix, count);
  } finally {
    await db.close();
  }
}

Future<void> _writeSettingsOn(AppDatabase db, String prefix, int count) async {
  for (var i = 0; i < count; i++) {
    await db.transaction(() => db.settingsDao.put('$prefix-$i', '$i'));
  }
}
```

- [ ] **Step 3: Run the tests and confirm RED**

Run from `packages/nimbus_data/`: `dart test test/open_database_test.dart`

Expected:
- The first test fails with `Expected: 'wal' Actual: 'delete'`.
- The second fails with `SqliteException(5): database is locked`. The collision is overwhelmingly likely at 200 transactions each, but not guaranteed. If it happens to pass, the first test's RED is the gate.

- [ ] **Step 4: Tag the rollback target**

```bash
git tag pre-wal-busy-timeout phase/6-outside-the-app
```

- [ ] **Step 5: Implement**

In `packages/nimbus_data/lib/src/database/app_database.dart`, replace the `openAtPath` factory and its doc comment's last paragraph with:

```dart
  /// Opens the database stored at [path].
  ///
  /// The app layer owns *where* the file lives -- it is the only layer allowed
  /// to know the platform's directory conventions, and it has `path_provider`
  /// for the purpose. This factory owns *how* it is opened. Keeping
  /// [NativeDatabase] behind this boundary is what lets
  /// `test/architecture_test.dart` assert that `app` depends on neither
  /// `drift` nor `sqlite3`: a screen that could construct a database would
  /// make the "UI cannot import the database" rule decoration.
  ///
  /// Two engines open this file: the app's, and Phase 6's headless drain.
  /// WAL lets a read run beside a write, and the busy timeout makes a second
  /// writer wait up to five seconds instead of failing with "database is
  /// locked". Both are set in `setup`, which runs on each connection before
  /// drift's own version check, so even two engines opening at the same
  /// moment never contend unprotected. The `-wal` file this creates is what
  /// Phase 7's backup must checkpoint first.
  factory AppDatabase.openAtPath(String path) => AppDatabase(NativeDatabase(
        File(path),
        setup: (database) => database
          ..execute('PRAGMA journal_mode = WAL')
          ..execute('PRAGMA busy_timeout = 5000'),
      ));
```

`openInMemory` is unchanged. An in-memory database has no second connection to share with.

- [ ] **Step 6: Run the tests and confirm GREEN**

Run: `dart test test/open_database_test.dart`. Expected: all pass.

- [ ] **Step 7: Run the broader suites**

Run, from `packages/nimbus_data/`: `dart test`. From the repo root: `dart analyze --fatal-infos`. From `app/`: `flutter test --no-pub --concurrency=4 --timeout 90s`.

Expected: all green. The app suite uses in-memory databases, so it proves only that nothing else broke.

- [ ] **Step 8: Note the WAL in the Phase 7 brief**

In `docs/phases/phase-7-backup.md`, under `## Known traps`, insert this bullet directly after the bullet that starts `- **The WAL is the whole problem.**`:

```markdown
- **Phase 6 turned WAL on.** `AppDatabase.openAtPath` sets
  `journal_mode=WAL` and `busy_timeout=5000` on every connection (Phase 6
  spec §3), so from Phase 6 on every device has a live
  `nimbustats.sqlite-wal`, and two engines (the app's and the widget's
  headless drain) may hold the file at once. The checkpoint above is
  therefore not hypothetical.
```

- [ ] **Step 9: Commit and fast-forward**

```bash
git add packages/nimbus_data/lib/src/database/app_database.dart packages/nimbus_data/test/open_database_test.dart docs/phases/phase-7-backup.md
git commit -m "$(cat <<'EOF'
feat(data): WAL journal and a 5 s busy timeout on the database file

Phase 6's widget drain runs in a second Flutter engine with its own
SQLite connection to the same file. In rollback-journal mode with no
busy timeout, the second writer failed at once with "database is
locked"; WAL lets reads run beside a write and the timeout makes a
second writer wait. Set in NativeDatabase's setup so the pragmas apply
before drift's own version check on every connection.

Edits Phase 0's app_database.dart (openAtPath only) and adds the WAL
note to the Phase 7 brief, whose backup must now checkpoint a real
-wal file.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/wal-busy-timeout
```

---

### Task 2: Exactly-once writes — the caller's id is the row id

Slug: `once-by-id`. Spec §2.2, ruling R3.

**Files:**
- Create: `packages/nimbus_data/lib/src/database/sqlite_errors.dart`
- Modify: `packages/nimbus_data/lib/src/database/app_database.dart` (`TransactionsDao.insertTransaction`, around line 926)
- Modify: `packages/nimbus_data/lib/src/trackers/tracker_entries_dao.dart` (`insertEntry`, line 35)
- Modify: `packages/nimbus_domain/lib/src/trackers/tracker_results.dart` (new `AlreadyLogged`)
- Modify: `app/lib/features/transactions/data/transaction_repository.dart` (`add`)
- Modify: `app/lib/features/trackers/data/tracker_repository.dart` (`logEntry`)
- Modify: `app/lib/features/trackers/presentation/widgets/tracker_logger.dart` (line 52)
- Test: `packages/nimbus_data/test/transactions_test.dart`, `packages/nimbus_data/test/trackers/tracker_entries_dao_test.dart`, `app/test/features/transactions/transaction_repository_test.dart`, `app/test/features/trackers/tracker_repository_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces, for Task 13:
  - `Future<bool> TransactionsDao.insertTransaction({…, bool onlyIfAbsent = false})` returns true when it wrote the row.
  - `Future<LogResult> TrackerEntriesDao.insertEntry(NewTrackerEntry entry, {bool onlyIfAbsent = false})`.
  - `final class AlreadyLogged extends LogResult`.
  - `Future<Transaction> TransactionRepository.add(TransactionDraft draft, {String? id})` returns the row with that id, whether new or already there.
  - `Future<LogResult> TrackerRepository.logEntry(String trackerId, {double? value, DateTime? at, String? note, String? id})`.

- [ ] **Step 1: Branch**

```bash
git checkout -b feat/once-by-id phase/6-outside-the-app
```

- [ ] **Step 2: Write the failing data tests**

Append inside `main()` of `packages/nimbus_data/test/transactions_test.dart`:

```dart
  group('insert only if absent (Phase 6 widget drain)', () {
    const day = DateKey(20261012);

    Future<bool> insertOnce(String id, {int amount = 1000}) =>
        db.transactionsDao.insertTransaction(
          id: id,
          direction: TxDirection.expense,
          amount: Money(amount),
          currencyCode: 'IRT',
          occurredAtUtc: day.toDateTime().millisecondsSinceEpoch,
          localDateKey: day,
          categoryId: 'food',
          source: TxSource.widget,
          onlyIfAbsent: true,
        );

    test('a second insert with the same id writes nothing', () async {
      expect(await insertOnce('w1', amount: 1000), isTrue);
      expect(await insertOnce('w1', amount: 9999), isFalse);
      expect((await db.transactionsDao.byId('w1'))!.amount, const Money(1000));
    });

    test('a soft-deleted row still holds its id: no resurrection', () async {
      await insertOnce('w2');
      await db.transactionsDao.softDelete('w2');
      expect(await insertOnce('w2'), isFalse);
      expect((await db.transactionsDao.byId('w2'))!.deletedAt, isNotNull);
    });

    test('two inserts racing on one id write it once', () async {
      final written = await Future.wait([insertOnce('w3'), insertOnce('w3')]);
      expect(written.where((w) => w), hasLength(1));
    });

    test('without it, a duplicate id is still an error', () async {
      final id = await addExpense(amount: 5, on: day);
      expect(
        () => db.transactionsDao.insertTransaction(
          id: id,
          direction: TxDirection.expense,
          amount: const Money(5),
          currencyCode: 'IRT',
          occurredAtUtc: day.toDateTime().millisecondsSinceEpoch,
          localDateKey: day,
          categoryId: 'food',
          source: TxSource.manual,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
```

Append inside `main()` of `packages/nimbus_data/test/trackers/tracker_entries_dao_test.dart`:

```dart
  group('insert only if absent (Phase 6 widget drain)', () {
    test('a second insert with the same id writes nothing', () async {
      expect(await dao.insertEntry(newEntry('w1', 'cig'), onlyIfAbsent: true),
          isA<EntryLogged>());
      expect(
          await dao.insertEntry(newEntry('w1', 'cig', value: 3),
              onlyIfAbsent: true),
          isA<AlreadyLogged>());
      expect(await liveEntries(db, 'cig'), 1);
    });

    test('a soft-deleted entry still holds its id: no resurrection', () async {
      await dao.insertEntry(newEntry('w2', 'cig'), onlyIfAbsent: true);
      await dao.softDelete('w2');
      expect(await dao.insertEntry(newEntry('w2', 'cig'), onlyIfAbsent: true),
          isA<AlreadyLogged>());
      expect(await liveEntries(db, 'cig'), 0);
    });

    test('two inserts racing on one id write it once', () async {
      final results = await Future.wait([
        dao.insertEntry(newEntry('w3', 'cig'), onlyIfAbsent: true),
        dao.insertEntry(newEntry('w3', 'cig'), onlyIfAbsent: true),
      ]);
      expect(results.whereType<EntryLogged>(), hasLength(1));
      expect(results.whereType<AlreadyLogged>(), hasLength(1));
    });

    test('a boolean already done that day is still AlreadyDoneToday', () async {
      await dao.insertEntry(newEntry('a', 'gym', oncePerDay: true));
      expect(
          await dao.insertEntry(newEntry('w4', 'gym', oncePerDay: true),
              onlyIfAbsent: true),
          isA<AlreadyDoneToday>());
    });

    test('without it, a duplicate id is still an error', () async {
      await dao.insertEntry(newEntry('w5', 'cig'));
      expect(() => dao.insertEntry(newEntry('w5', 'cig')),
          throwsA(isA<Exception>()));
    });
  });
```

- [ ] **Step 3: Write the failing repository tests**

Append inside `main()` of `app/test/features/transactions/transaction_repository_test.dart`:

```dart
  group('add with a caller-supplied id (Phase 6 widget drain)', () {
    test('a repeat returns the first row and writes nothing', () async {
      final first = await repo.add(draft(amount: const Money(1000)), id: 'w1');
      final again = await repo.add(draft(amount: const Money(9999)), id: 'w1');

      expect(first.id, 'w1');
      expect(again.id, 'w1');
      expect(again.amount, const Money(1000));
      expect(await repo.total(wholeEra), const Money(1000));
    });

    test("a repeat leaves the row's tags and their usage alone", () async {
      await repo.add(draft(tagIds: ['travel']), id: 'w2');
      // An empty tag list would clear the first write's tags if it reached
      // _attachTags.
      await repo.add(draft(), id: 'w2');

      expect(await repo.tagsOf('w2'), ['travel']);
      expect((await db.tagsDao.byId('travel'))!.usageCount, 1);
    });

    test('a row deleted after it was written is not resurrected', () async {
      await repo.add(draft(amount: const Money(700)), id: 'w3');
      await repo.softDelete('w3');
      await repo.add(draft(amount: const Money(700)), id: 'w3');

      expect(await repo.total(wholeEra), Money.zero);
    });
  });
```

Append inside `main()` of `app/test/features/trackers/tracker_repository_test.dart`:

```dart
  group('logEntry with a caller-supplied id (Phase 6 widget drain)', () {
    test('a repeat writes nothing and the tap time decides the day', () async {
      final tracker = await repo.create(cigarettes);
      // 23:59 in Tehran on the 4th, drained at 12:30 on the 5th (the fake's
      // now): the entry belongs to the 4th.
      final at = DateTime.utc(2026, 10, 4, 20, 29);

      expect(await repo.logEntry(tracker.id, at: at, id: 'w1'),
          isA<EntryLogged>());
      expect(await repo.logEntry(tracker.id, at: at, id: 'w1'),
          isA<AlreadyLogged>());

      final entries = await entriesOf(tracker.id);
      expect(entries.single.id, 'w1');
      expect(entries.single.localDateKey, const DateKey(20261004));
    });

    test('without an id, two taps are two entries', () async {
      final tracker = await repo.create(cigarettes);
      await repo.logEntry(tracker.id);
      await repo.logEntry(tracker.id);
      expect(await entriesOf(tracker.id), hasLength(2));
    });
  });
```

`Tag.usageCount` is the generated field for `tags.usage_count`. Check it with `grep -n "usageCount" packages/nimbus_data/lib/src/database/app_database.g.dart | head -3` before running.

- [ ] **Step 4: Run and confirm RED**

Run from `packages/nimbus_data/`: `dart test test/transactions_test.dart test/trackers/tracker_entries_dao_test.dart`. Expected: compile errors. There is no named parameter `onlyIfAbsent`, and `AlreadyLogged` is undefined.

Run from `app/`: `flutter test --no-pub test/features/transactions/transaction_repository_test.dart test/features/trackers/tracker_repository_test.dart`. Expected: compile errors. There is no named parameter `id`, and `AlreadyLogged` is undefined.

- [ ] **Step 5: Tag the rollback target**

```bash
git tag pre-once-by-id phase/6-outside-the-app
```

- [ ] **Step 6: The domain result**

In `packages/nimbus_domain/lib/src/trackers/tracker_results.dart`, after `AlreadyDoneToday`, add:

```dart
/// An entry with the caller's own id was written before, and may have been
/// deleted since. Nothing was written.
///
/// Only a caller that supplies the id can get this: Phase 6's widget drain,
/// whose buffer line id is the entry id so a repeated drain writes each tap
/// once and never brings a deleted one back.
final class AlreadyLogged extends LogResult {
  const AlreadyLogged();

  @override
  String toString() => 'AlreadyLogged()';
}
```

- [ ] **Step 7: The shared primary-key check**

Create `packages/nimbus_data/lib/src/database/sqlite_errors.dart`:

```dart
import 'package:sqlite3/common.dart' show SqlExtendedError, SqliteException;

/// SQLite refusing a row because its primary key is already taken -- by a
/// live row or a soft-deleted one.
///
/// Like `_isOncePerDayViolation` in tracker_entries_dao.dart, this matches the
/// [SqliteException] that `AppDatabase.openAtPath` and `openInMemory` throw,
/// because both run SQLite on the calling isolate. A database moved to a
/// background isolate throws drift's remote wrapper instead, and this must
/// then unwrap it.
bool isPrimaryKeyViolation(Object error) => switch (error) {
      SqliteException(:final extendedResultCode) =>
        extendedResultCode == SqlExtendedError.SQLITE_CONSTRAINT_PRIMARYKEY,
      _ => false,
    };
```

This file is not exported from the barrel. It is internal to `nimbus_data`.

- [ ] **Step 8: `TransactionsDao.insertTransaction` gains `onlyIfAbsent`**

In `app_database.dart`:
1. Add `import 'sqlite_errors.dart';` next to `import 'converters.dart';`.
2. Change `insertTransaction`'s signature and body. All the existing named parameters stay. Add `bool onlyIfAbsent = false,` as the last one, and make it return `Future<bool>`:

```dart
  /// Writes one transaction and returns true.
  ///
  /// With [onlyIfAbsent], an [id] already in the table -- live or
  /// soft-deleted -- writes nothing and returns false. The primary key
  /// decides, not a read first, so two drains racing on one id still write it
  /// once, and an expense deleted after it was drained is never brought back
  /// (Phase 6 spec §2.2). Without it a duplicate id is a bug and throws.
  Future<bool> insertTransaction({
    required String id,
    required TxDirection direction,
    required Money amount,
    required String currencyCode,
    required int occurredAtUtc,
    required DateKey localDateKey,
    required String categoryId,
    required TxSource source,
    bool isConfirmed = true,
    String? paymentMethodId,
    String? merchant,
    String? note,
    int tzOffsetMinutes = 0,
    Necessity? necessity,
    Satisfaction? satisfaction,
    String? captureId,
    bool onlyIfAbsent = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await _db.into(_db.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              direction: direction,
              amount: amount,
              currencyCode: currencyCode,
              occurredAtUtc: occurredAtUtc,
              localDateKey: localDateKey,
              tzOffsetMinutes: Value(tzOffsetMinutes),
              categoryId: categoryId,
              source: source,
              isConfirmed: Value(isConfirmed),
              paymentMethodId: Value(paymentMethodId),
              merchant: Value(merchant),
              note: Value(note),
              necessity: Value(necessity),
              satisfaction: Value(satisfaction),
              captureId: Value(captureId),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return true;
    } on Object catch (error) {
      if (onlyIfAbsent && isPrimaryKeyViolation(error)) return false;
      rethrow;
    }
  }
```

- [ ] **Step 9: `TrackerEntriesDao.insertEntry` gains `onlyIfAbsent`**

In `tracker_entries_dao.dart`:
1. Add `import '../database/sqlite_errors.dart';`.
2. Change the signature to `Future<LogResult> insertEntry(NewTrackerEntry entry, {bool onlyIfAbsent = false}) async {`.
3. Replace the `catch` block with:

```dart
    } on Object catch (error) {
      // An id the caller supplied was written before (Phase 6's widget
      // drain): the primary key, not a read first, decides.
      if (onlyIfAbsent && isPrimaryKeyViolation(error)) {
        return const AlreadyLogged();
      }
      if (_isOncePerDayViolation(error)) return const AlreadyDoneToday();
      rethrow;
    }
```

4. Extend the doc comment's first line to: `/// Inserts [entry], or reports that its day already holds a live "done", or -- with [onlyIfAbsent] -- that its id was written before.`

- [ ] **Step 10: The repositories take the id**

In `app/lib/features/transactions/data/transaction_repository.dart`, replace `add` with:

```dart
  /// Writes [draft] as a new transaction and returns it.
  ///
  /// [id] is for a caller that must write each item exactly once: Phase 6's
  /// widget drain, whose buffer line id becomes the row id. With it, an id
  /// already in the table -- live or deleted -- writes nothing, and the row
  /// as it stands is returned with its tags untouched (re-attaching the
  /// draft's would clear any the user has added since). Without it, every
  /// call is a new row.
  Future<Transaction> add(TransactionDraft draft, {String? id}) async {
    final rowId = id ?? Ids.newId();
    final local = draft.occurredAtUtc.toLocal();
    final written = await _dao.insertTransaction(
      id: rowId,
      direction: draft.direction,
      amount: draft.amount,
      currencyCode: _currency.code,
      occurredAtUtc: draft.occurredAtUtc.millisecondsSinceEpoch,
      // Derived from local time, not UTC. A purchase at 01:00 local on the
      // 22nd belongs to the 22nd even though it is still the 21st in UTC;
      // getting this wrong files spending under the wrong day for everyone
      // east of Greenwich, which is the entire target market.
      localDateKey: DateKey.fromDateTime(local),
      tzOffsetMinutes: local.timeZoneOffset.inMinutes,
      categoryId: draft.categoryId,
      source: draft.source,
      isConfirmed: draft.isConfirmed,
      paymentMethodId: draft.paymentMethodId,
      merchant: draft.merchant,
      note: draft.note,
      necessity: draft.necessity,
      satisfaction: draft.satisfaction,
      captureId: draft.captureId,
      onlyIfAbsent: id != null,
    );
    if (written) await _attachTags(rowId, draft.tagIds, countUsage: true);

    final row = await _dao.byId(rowId);
    if (row == null) {
      // Not defensive noise: a row that vanishes between insert and read means
      // the write did not commit, and returning a fabricated object would let
      // the UI show an expense that does not exist.
      throw StateError('Transaction $rowId was not persisted');
    }
    return row;
  }
```

In `app/lib/features/trackers/data/tracker_repository.dart`:
1. Add `String? id,` to `logEntry`'s named parameters, after `String? note,`.
2. In its `insertEntry` call, change `id: Ids.newId(),` to `id: id ?? Ids.newId(),`.
3. Add `, onlyIfAbsent: id != null` as the second argument of `_entries.insertEntry((…), …)`.
4. Append to the doc comment:

```dart
  ///
  /// [id] is for a caller that must log each tap exactly once (Phase 6's
  /// widget drain): an id written before -- even one deleted since -- returns
  /// [AlreadyLogged] and writes nothing.
```

- [ ] **Step 11: The tab's exhaustive switch**

In `app/lib/features/trackers/presentation/widgets/tracker_logger.dart`, replace the `case AlreadyDoneToday():` arm, and its comment, with:

```dart
      case AlreadyDoneToday() || AlreadyLogged():
        // A double-tap on "done": the first tap's entry already holds the
        // day, and the tile shows it. AlreadyLogged needs a caller-supplied
        // id, which the tab never passes.
        break;
```

- [ ] **Step 12: Run and confirm GREEN**

Run from `packages/nimbus_data/`: `dart test test/transactions_test.dart test/trackers/tracker_entries_dao_test.dart`.

Run from `app/`: `flutter test --no-pub test/features/transactions/transaction_repository_test.dart test/features/trackers/tracker_repository_test.dart`.

Expected: all pass.

- [ ] **Step 13: Broader suites**

Run, from `packages/nimbus_domain/`: `dart test`. From `packages/nimbus_data/`: `dart test`. From the repo root: `dart analyze --fatal-infos`. From `app/`: `flutter test --no-pub --concurrency=4 --timeout 90s`. Expected: all green.

- [ ] **Step 14: Commit and fast-forward**

```bash
git add packages/nimbus_data/lib/src/database/sqlite_errors.dart packages/nimbus_data/lib/src/database/app_database.dart packages/nimbus_data/lib/src/trackers/tracker_entries_dao.dart packages/nimbus_domain/lib/src/trackers/tracker_results.dart app/lib/features/transactions/data/transaction_repository.dart app/lib/features/trackers/data/tracker_repository.dart app/lib/features/trackers/presentation/widgets/tracker_logger.dart packages/nimbus_data/test/transactions_test.dart packages/nimbus_data/test/trackers/tracker_entries_dao_test.dart app/test/features/transactions/transaction_repository_test.dart app/test/features/trackers/tracker_repository_test.dart
git commit -m "$(cat <<'EOF'
feat(data): a caller-supplied id makes a write happen exactly once

The widget drain may run twice over one buffer line: after a crash, or
in the app engine and the headless engine at once. Each line's id
becomes the row id, and with onlyIfAbsent the primary key refuses a
second write, live or soft-deleted, so a repeat writes nothing and a
deleted expense is never resurrected. The key decides rather than a
read first, as the once-per-day index already does for "done".

A repeated TransactionRepository.add returns the existing row without
re-attaching tags, which would otherwise clear any added since.
logEntry reports AlreadyLogged, a new LogResult case the tab's switch
now names. Without an id both behave exactly as before.

Edits Phase 0's TransactionsDao, Phase 1's TransactionRepository and
Phase 4's TrackerEntriesDao, TrackerRepository, LogResult and
tracker_logger, all additively.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/once-by-id
```

---

### Task 3: `GoalWatcher.checkNow()`

Slug: `goal-check-now`. Spec §2.5.

**Files:**
- Modify: `app/lib/features/goals/application/goal_watcher.dart`
- Test: `app/test/features/goals/goal_watcher_test.dart`

**Interfaces:**
- Consumes: `GoalWatcher` as it stands.
- Produces: `Future<void> GoalWatcher.checkNow()`. It evaluates every active goal's current period now, emits any alert on `alerts`, and completes when the evaluation has. Task 13 calls it after every drain.

- [ ] **Step 1: Branch**

```bash
git checkout -b feat/goal-check-now phase/6-outside-the-app
```

- [ ] **Step 2: Write the failing test**

Append inside `main()` of `app/test/features/goals/goal_watcher_test.dart`, after the last test:

```dart
  group('checkNow (Phase 6: the drain engines)', () {
    /// The providers as the headless drain engine builds them: no shell, so
    /// the watcher is never started.
    GoalWatcher unstarted() {
      final c = ProviderContainer(retry: nimbusNoRetry, overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ...trackerOverrides(fake),
      ]);
      started = c;
      final watcher = c.read(goalWatcherProvider);
      final subscription = watcher.alerts.listen(alerts.add);
      addTearDown(subscription.cancel);
      return watcher;
    }

    test('emits a due alert once; a second call emits none', () async {
      await service.save(spendingCap()); // the baseline: nothing spent
      await spend(db, 850000, day5); // a widget expense, drained
      final watcher = unstarted();

      await watcher.checkNow();
      // The broadcast stream delivers in a microtask.
      await Future<void>.delayed(Duration.zero);
      expect(percents(), [80]);

      await watcher.checkNow();
      await Future<void>.delayed(Duration.zero);
      expect(percents(), [80],
          reason: 'the crossing is recorded: a second check recomputes');
    });

    test('checks tracker goals too, without waiting for a debounce',
        () async {
      final trackers = repositoryFor(db, fake);
      final cig = await trackers.create(cigarettes);
      await service.save(habitGoal(cig)); // at most 5 a day
      for (var i = 0; i < 4; i++) {
        await trackers.logEntry(cig.id);
      }
      final watcher = unstarted();

      await watcher.checkNow();
      await Future<void>.delayed(Duration.zero);
      expect(percents(), [80]);
    });
  });
```

- [ ] **Step 3: Run and confirm RED**

Run from `app/`: `flutter test --no-pub test/features/goals/goal_watcher_test.dart`. Expected: compile error, `The method 'checkNow' isn't defined for the type 'GoalWatcher'`.

- [ ] **Step 4: Tag**

```bash
git tag pre-goal-check-now phase/6-outside-the-app
```

- [ ] **Step 5: Implement**

In `goal_watcher.dart`, after `stop()` and before `_teardown()`, add:

```dart
  /// Evaluates every active goal's current period now, and completes when
  /// that evaluation has. Any alert is on [alerts] by then (spec §2.5).
  ///
  /// For Phase 6's drain. The headless engine never [start]s the watcher, and
  /// a drain in the app engine should not wait out the debounce. A debounced
  /// evaluation already pending is folded into this one: it would evaluate a
  /// subset of the same goals. Two checks of one crossing still alert once,
  /// because `GoalService.check` records it in one transaction.
  Future<void> checkNow() {
    _pending?.cancel();
    _pending = null;
    _moneyDue = true;
    _trackersDue = true;
    return _evaluate();
  }
```

In the class doc comment, extend the first bullet list with a last item:

```dart
/// - on [checkNow], after Phase 6's widget drain.
```

Change the sentence `[alerts] is the stream Phase 6 subscribes to. Until then, the shell shows each alert as a snackbar.` to:

```dart
/// [alerts] is the stream Phase 6's `AlertRouter` subscribes to.
```

- [ ] **Step 6: GREEN**

Run: `flutter test --no-pub test/features/goals/goal_watcher_test.dart`. Expected: all pass.

- [ ] **Step 7: Broader suite**

Run, from the repo root: `dart analyze --fatal-infos`. From `app/`: `flutter test --no-pub --concurrency=4 --timeout 90s`. Expected: green.

- [ ] **Step 8: Commit and fast-forward**

```bash
git add app/lib/features/goals/application/goal_watcher.dart app/test/features/goals/goal_watcher_test.dart
git commit -m "$(cat <<'EOF'
feat(goals): GoalWatcher.checkNow evaluates every goal on demand

A widget expense drained while the app is closed runs in a headless
engine whose watcher is never started, so nothing would evaluate the
crossing until the next app launch. checkNow evaluates every active
goal's current period immediately and completes when done, so the
drain can deliver the alert within seconds. It adds no firing logic:
GoalService.check still records each crossing once.

A Phase 5 addition, named in the Phase 6 spec (§2.5).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/goal-check-now
```

---
### Task 4: `OutsideChannel` — the one platform boundary, faked in every test

Slug: `outside-channel`. Spec §1.1, ruling R7.

**Files:**
- Create: `app/lib/features/notifications/data/outside_channel.dart`
- Create: `app/lib/features/notifications/application/outside_errors.dart`
- Create: `app/test/features/notifications/support/fake_outside_channel.dart`
- Modify: `app/test/support/harness.dart` (fake by default)
- Test: `app/test/features/notifications/outside_channel_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces, used by every later Dart task:
  - `typedef RejectedLine = ({String line, String reason});`
  - `typedef ChannelTexts = ({String alertsName, String alertsDescription, String reminderName, String reminderDescription});`
  - `class OutsideChannel`:
    - `static const name = 'com.nimbustats.app/outside'`
    - `Future<bool> Function()? onDrainNow`
    - `Stream<String> get routes`
    - `Future<bool> notificationsEnabled()`
    - `Future<bool> requestNotificationPermission()`
    - `Future<void> openNotificationSettings()`
    - `Future<void> registerChannels(ChannelTexts texts)`
    - `Future<void> postAlert({required String tag, required String text, required String publicText, required String route})`
    - `Future<void> setReminder({required bool enabled, required int minuteOfDay, required String text, required String route})`
    - `Future<void> writeSnapshot(String json)`
    - `Future<List<String>> takeBuffer()`
    - `Future<void> commitDrain({required String snapshot, required List<String> ackIds, required List<RejectedLine> rejected})`
    - `Future<void> drainFinished(bool ok)`
    - `Future<String?> takeLaunchRoute()`
    - `void dispose()`
  - `final outsideChannelProvider = Provider<OutsideChannel>(…)`
  - `Future<T?> reportingFailure<T>(String library, String context, Future<T> Function() action)`
  - The test-side `FakeOutsideChannel`.
  - `pumpApp(…, OutsideChannel? outside)`.

- [ ] **Step 1: Branch**

```bash
git checkout -b feat/outside-channel phase/6-outside-the-app
```

- [ ] **Step 2: Write the failing test**

Create `app/test/features/notifications/outside_channel_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbustats/features/notifications/data/outside_channel.dart';

/// The Dart half of spec §1.1, against a mocked platform side.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const platform = MethodChannel(OutsideChannel.name);
  const codec = StandardMethodCodec();

  late List<MethodCall> calls;
  late Object? Function(MethodCall) reply;
  late OutsideChannel outside;

  setUp(() {
    calls = [];
    reply = (_) => null;
    messenger.setMockMethodCallHandler(platform, (call) async {
      calls.add(call);
      return reply(call);
    });
    outside = OutsideChannel();
  });
  tearDown(() {
    outside.dispose();
    messenger.setMockMethodCallHandler(platform, null);
  });

  /// A call made by native code, as the app engine receives it.
  Future<ByteData?> fromNative(String method, [Object? arguments]) {
    final answered = Completer<ByteData?>();
    messenger.handlePlatformMessage(OutsideChannel.name,
        codec.encodeMethodCall(MethodCall(method, arguments)),
        answered.complete);
    return answered.future;
  }

  test('commitDrain sends the snapshot, the acks and the rejects', () async {
    await outside.commitDrain(
      snapshot: '{"v":1}',
      ackIds: const ['a', 'b'],
      rejected: const [(line: 'x', reason: 'malformed line')],
    );
    expect(calls.single.method, 'commitDrain');
    expect(calls.single.arguments, {
      'snapshot': '{"v":1}',
      'ackIds': ['a', 'b'],
      'rejected': [
        {'line': 'x', 'reason': 'malformed line'},
      ],
    });
  });

  test('postAlert and setReminder carry exactly the spec arguments', () async {
    await outside.postAlert(
        tag: 'goal:g1', text: 'full', publicText: 'discreet', route: '/goals/g1');
    await outside.setReminder(
        enabled: true, minuteOfDay: 1260, text: 'Log?', route: '/add');
    expect(calls[0].arguments, {
      'tag': 'goal:g1',
      'text': 'full',
      'publicText': 'discreet',
      'route': '/goals/g1',
    });
    expect(calls[1].arguments, {
      'enabled': true,
      'minuteOfDay': 1260,
      'text': 'Log?',
      'route': '/add',
    });
  });

  test('takeBuffer returns the raw lines', () async {
    reply = (_) => ['{"v":1}', 'garbage'];
    expect(await outside.takeBuffer(), ['{"v":1}', 'garbage']);
  });

  test('a null reply where a value is required is an error, not a default',
      () async {
    reply = (_) => null;
    expect(outside.notificationsEnabled(), throwsA(isA<PlatformException>()));
    expect(outside.takeBuffer(), throwsA(isA<PlatformException>()));
  });

  test('drainNow with no drain registered answers not-implemented, so '
      'native drains in a headless engine', () async {
    expect(await fromNative('drainNow'), isNull);
  });

  test('drainNow runs the registered drain and replies with its result',
      () async {
    outside.onDrainNow = () async => true;
    final answer = await fromNative('drainNow');
    expect(codec.decodeEnvelope(answer!), isTrue);
  });

  test('openRoute arrives on routes', () async {
    final routes = <String>[];
    final subscription = outside.routes.listen(routes.add);
    addTearDown(subscription.cancel);
    await fromNative('openRoute', '/goals/g1');
    await Future<void>.delayed(Duration.zero);
    expect(routes, ['/goals/g1']);
  });
}
```

- [ ] **Step 3: RED**

Run from `app/`: `flutter test --no-pub test/features/notifications/outside_channel_test.dart`. Expected: compile error, `Target of URI doesn't exist: 'package:nimbustats/features/notifications/data/outside_channel.dart'`.

- [ ] **Step 4: Tag**

```bash
git tag pre-outside-channel phase/6-outside-the-app
```

- [ ] **Step 5: Implement the channel**

Create `app/lib/features/notifications/data/outside_channel.dart`:

```dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A buffer line the drain refused, and why (spec §2.3).
typedef RejectedLine = ({String line, String reason});

/// What Android shows for the two notification channels, in the app's
/// language (spec §4.1).
typedef ChannelTexts = ({
  String alertsName,
  String alertsDescription,
  String reminderName,
  String reminderDescription,
});

/// The one boundary between Dart and Phase 6's Android code: the
/// `com.nimbustats.app/outside` channel, exactly as spec §1.1 lists it.
///
/// Every test replaces it with a fake (`FakeOutsideChannel`). A method that
/// must return a value and gets null throws: a missing answer from native is
/// a bug to see, not a default to assume.
class OutsideChannel {
  OutsideChannel([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel(name) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const name = 'com.nimbustats.app/outside';

  final MethodChannel _channel;
  final _routes = StreamController<String>.broadcast();

  /// Runs a drain when native asks the app engine for one (`drainNow`), and
  /// says whether every line was settled.
  ///
  /// Null until `WidgetSync` mounts. Native then hears "not implemented" and
  /// drains in a headless engine instead (spec §2.4).
  Future<bool> Function()? onDrainNow;

  /// Routes of notifications tapped while the app runs (`openRoute`).
  Stream<String> get routes => _routes.stream;

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'drainNow':
        final drain = onDrainNow;
        if (drain == null) {
          throw MissingPluginException('no drain handler is registered yet');
        }
        return drain();
      case 'openRoute':
        _routes.add(call.arguments as String);
        return null;
      default:
        throw MissingPluginException('${call.method} is not a native call');
    }
  }

  Future<bool> notificationsEnabled() => _require<bool>('notificationsEnabled');

  /// Asks for Android 13's POST_NOTIFICATIONS in context. Below 13 it answers
  /// whether notifications are enabled, with no dialog.
  Future<bool> requestNotificationPermission() =>
      _require<bool>('requestNotificationPermission');

  Future<void> openNotificationSettings() =>
      _channel.invokeMethod<void>('openNotificationSettings');

  Future<void> registerChannels(ChannelTexts texts) =>
      _channel.invokeMethod<void>('registerChannels', {
        'alertsName': texts.alertsName,
        'alertsDescription': texts.alertsDescription,
        'reminderName': texts.reminderName,
        'reminderDescription': texts.reminderDescription,
      });

  Future<void> postAlert({
    required String tag,
    required String text,
    required String publicText,
    required String route,
  }) =>
      _channel.invokeMethod<void>('postAlert', {
        'tag': tag,
        'text': text,
        'publicText': publicText,
        'route': route,
      });

  /// Arms the daily reminder at [minuteOfDay] local time, or cancels it.
  Future<void> setReminder({
    required bool enabled,
    required int minuteOfDay,
    required String text,
    required String route,
  }) =>
      _channel.invokeMethod<void>('setReminder', {
        'enabled': enabled,
        'minuteOfDay': minuteOfDay,
        'text': text,
        'route': route,
      });

  /// Stores [json] as the widget snapshot and re-renders every widget.
  Future<void> writeSnapshot(String json) =>
      _channel.invokeMethod<void>('writeSnapshot', {'snapshot': json});

  /// Every pending buffer line, raw. Nothing is removed.
  Future<List<String>> takeBuffer() async =>
      (await _require<List<Object?>>('takeBuffer')).cast<String>();

  /// Under the buffer lock, in one call: writes [snapshot], drops the acked
  /// and rejected lines, and keeps the rejected ones with their reasons
  /// (spec §2.3 step 4).
  Future<void> commitDrain({
    required String snapshot,
    required List<String> ackIds,
    required List<RejectedLine> rejected,
  }) =>
      _channel.invokeMethod<void>('commitDrain', {
        'snapshot': snapshot,
        'ackIds': ackIds,
        'rejected': [
          for (final r in rejected) {'line': r.line, 'reason': r.reason},
        ],
      });

  /// The headless engine's last word: native then destroys it.
  Future<void> drainFinished(bool ok) =>
      _channel.invokeMethod<void>('drainFinished', {'ok': ok});

  /// The route a notification tap launched the app with, once.
  Future<String?> takeLaunchRoute() =>
      _channel.invokeMethod<String>('takeLaunchRoute');

  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_routes.close());
  }

  Future<T> _require<T>(String method) async {
    final value = await _channel.invokeMethod<T>(method);
    if (value == null) {
      throw PlatformException(
          code: 'null-reply', message: '$method answered null');
    }
    return value;
  }
}

/// The app's one channel. The headless drain engine overrides it with the
/// channel it built, so both engines read the same provider.
final outsideChannelProvider = Provider<OutsideChannel>((ref) {
  final channel = OutsideChannel();
  ref.onDispose(channel.dispose);
  return channel;
});
```

Create `app/lib/features/notifications/application/outside_errors.dart`:

```dart
import 'package:flutter/foundation.dart';

/// Runs [action]. A failure is reported through [FlutterError.reportError]
/// under [library] (spec §9), and null is returned.
///
/// For the fire-and-forget calls that cross the platform channel: a
/// rethrown error there would surface as an unhandled async error with no
/// context, and an ignored one would be a silent failure.
Future<T?> reportingFailure<T>(
  String library,
  String context,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } on Object catch (error, stack) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: library,
      context: ErrorDescription(context),
    ));
    return null;
  }
}
```

- [ ] **Step 6: The fake, and the harness uses it by default**

Create `app/test/features/notifications/support/fake_outside_channel.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:nimbustats/features/notifications/data/outside_channel.dart';

/// [OutsideChannel] without Android. It records every call and plays the
/// native side's part: the buffer, the permission, the launch route.
class FakeOutsideChannel implements OutsideChannel {
  /// Method names, in call order.
  final calls = <String>[];

  bool enabled = true;

  /// What the permission dialog answers. Granting also enables.
  bool grant = true;
  int permissionRequests = 0;
  int settingsOpened = 0;

  /// The native buffer's lines.
  List<String> buffer = [];
  String? launchRoute;

  final channelTexts = <ChannelTexts>[];
  final posted =
      <({String tag, String text, String publicText, String route})>[];
  final reminders =
      <({bool enabled, int minuteOfDay, String text, String route})>[];
  final snapshots = <String>[];
  final commits = <({
    String snapshot,
    List<String> ackIds,
    List<RejectedLine> rejected,
  })>[];
  final finished = <bool>[];

  final _routes = StreamController<String>.broadcast();

  /// A notification tapped while the app runs, as native sends it.
  void tapRoute(String route) => _routes.add(route);

  @override
  Future<bool> Function()? onDrainNow;

  @override
  Stream<String> get routes => _routes.stream;

  @override
  Future<bool> notificationsEnabled() async {
    calls.add('notificationsEnabled');
    return enabled;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    calls.add('requestNotificationPermission');
    permissionRequests++;
    if (grant) enabled = true;
    return grant;
  }

  @override
  Future<void> openNotificationSettings() async {
    calls.add('openNotificationSettings');
    settingsOpened++;
  }

  @override
  Future<void> registerChannels(ChannelTexts texts) async {
    calls.add('registerChannels');
    channelTexts.add(texts);
  }

  @override
  Future<void> postAlert({
    required String tag,
    required String text,
    required String publicText,
    required String route,
  }) async {
    calls.add('postAlert');
    posted.add((tag: tag, text: text, publicText: publicText, route: route));
  }

  @override
  Future<void> setReminder({
    required bool enabled,
    required int minuteOfDay,
    required String text,
    required String route,
  }) async {
    calls.add('setReminder');
    reminders.add((
      enabled: enabled,
      minuteOfDay: minuteOfDay,
      text: text,
      route: route,
    ));
  }

  @override
  Future<void> writeSnapshot(String json) async {
    calls.add('writeSnapshot');
    snapshots.add(json);
  }

  @override
  Future<List<String>> takeBuffer() async {
    calls.add('takeBuffer');
    return List.of(buffer);
  }

  /// Drops what native would: acked ids and rejected lines.
  @override
  Future<void> commitDrain({
    required String snapshot,
    required List<String> ackIds,
    required List<RejectedLine> rejected,
  }) async {
    calls.add('commitDrain');
    commits.add((snapshot: snapshot, ackIds: ackIds, rejected: rejected));
    snapshots.add(snapshot);
    final acked = ackIds.toSet();
    final refused = {for (final r in rejected) r.line};
    buffer.removeWhere(
        (line) => refused.contains(line) || acked.contains(_idOf(line)));
  }

  @override
  Future<void> drainFinished(bool ok) async {
    calls.add('drainFinished');
    finished.add(ok);
  }

  @override
  Future<String?> takeLaunchRoute() async {
    calls.add('takeLaunchRoute');
    final route = launchRoute;
    launchRoute = null;
    return route;
  }

  @override
  void dispose() => unawaited(_routes.close());

  static String? _idOf(String line) {
    try {
      return (jsonDecode(line) as Map<String, Object?>)['id'] as String?;
    } on Object {
      return null;
    }
  }
}
```

In `app/test/support/harness.dart`:
1. Add the imports:

```dart
import 'package:nimbustats/features/notifications/data/outside_channel.dart';

import '../features/notifications/support/fake_outside_channel.dart';
```

2. Add the parameter `OutsideChannel? outside,` after `List<Override> overrides = const [],`.
3. Add this override after the `firstRunCompleteProvider` one, before `...overrides`:

```dart
    // No Android in a widget test. A test about the channel passes its own
    // fake to read what was sent.
    outsideChannelProvider.overrideWithValue(outside ?? FakeOutsideChannel()),
```

- [ ] **Step 7: GREEN**

Run from `app/`: `flutter test --no-pub test/features/notifications/outside_channel_test.dart`. Expected: all pass.

- [ ] **Step 8: Broader suite**

Run, from the repo root: `dart analyze --fatal-infos`. From `app/`: `flutter test --no-pub --concurrency=4 --timeout 90s`. Expected: green. Nothing reads the provider yet, so the harness change is inert.

- [ ] **Step 9: Commit and fast-forward**

```bash
git add app/lib/features/notifications app/test/features/notifications app/test/support/harness.dart
git commit -m "$(cat <<'EOF'
feat(notifications): OutsideChannel, the one platform boundary

Every Phase 6 call between Dart and Android -- notifications, the
reminder, the widget snapshot and buffer, the drain hand-off and
notification-tap routes -- goes through this one class on the
com.nimbustats.app/outside channel, exactly as spec §1.1 lists it. A
null where a value is owed throws instead of defaulting. drainNow with
no drain registered answers not-implemented, which is what sends the
native job to a headless engine.

The test harness now overrides it with a fake by default, so no widget
test touches a real platform channel.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/outside-channel
```

---

### Task 5: Android groundwork — minSdk 26, the channel handler, notification channels, the permission ask

Slug: `android-outside-channel`. Spec §1.1, §4.1, §4.2, rulings R1 and R4.

This task has no host test (Global Constraints). It is verified by a build here, and on the device in Task 17.

**Files:**
- Modify: `app/android/app/build.gradle.kts`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Modify: `app/android/app/src/main/kotlin/com/nimbustats/app/MainActivity.kt`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/OutsideChannelHandler.kt`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/notifications/Notifier.kt`
- Create: `app/android/app/src/main/res/drawable/ic_stat_nimbus.xml`

**Interfaces:**
- Consumes: the channel contract of Task 4.
- Produces:
  - `OutsideChannelHandler(context, takeLaunchRoute, requestPermission, onDrainFinished)`.
  - `OutsideChannelHandler.CHANNEL`, `OutsideChannelHandler.TAG = "NimbuStats"` and `@Volatile var OutsideChannelHandler.appChannel: MethodChannel?`.
  - `MethodCall.string(key)`.
  - `Notifier.ALERTS`, `Notifier.REMINDER` and `Notifier.EXTRA_ROUTE`.
  - `Notifier.enabled(context)`, `Notifier.registerChannels(…)` and `Notifier.settingsIntent(context)`.
  - Later tasks add `when` arms to the handler, and functions to `Notifier`.

- [ ] **Step 1: Branch and check the exit**

```bash
git checkout -b feat/android-outside-channel phase/6-outside-the-app
curl -s https://api.ipify.org; echo
```

This build adds no artifact, so any exit works. Record the IP in the task report anyway.

- [ ] **Step 2: Confirm the build is green before the change**

Run from `app/`: `flutter build apk --debug`. Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 3: Tag**

```bash
git tag pre-android-outside-channel phase/6-outside-the-app
```

- [ ] **Step 4: minSdk 26**

In `app/android/app/build.gradle.kts`, replace `minSdk = flutter.minSdkVersion` with:

```kotlin
        // 26, not Flutter's 24: Phase 6's reminder and widget compute local
        // times with java.time, which is API 26+ without desugaring (operator
        // decision, 2026-10-12; spec §5).
        minSdk = 26
```

- [ ] **Step 5: The notifier**

Create `app/android/app/src/main/kotlin/com/nimbustats/app/notifications/Notifier.kt`:

```kotlin
package com.nimbustats.app.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.provider.Settings

/**
 * The app's two notification channels (spec §4.1) and the posts made on them.
 *
 * Every text it shows arrives from Dart in the app's language; nothing here composes one.
 */
object Notifier {
    const val ALERTS = "alerts"
    const val REMINDER = "reminder"

    /** The route a notification tap opens, carried to [com.nimbustats.app.MainActivity]. */
    const val EXTRA_ROUTE = "com.nimbustats.app.ROUTE"

    fun enabled(context: Context): Boolean =
        context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    /**
     * Creates both channels, or renames them: creating an existing id again updates its name
     * and description, which is how a language switch reaches Android's settings.
     */
    fun registerChannels(
        context: Context,
        alertsName: String,
        alertsDescription: String,
        reminderName: String,
        reminderDescription: String,
    ) {
        context.getSystemService(NotificationManager::class.java).createNotificationChannels(
            listOf(
                NotificationChannel(ALERTS, alertsName, NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { description = alertsDescription },
                NotificationChannel(REMINDER, reminderName, NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { description = reminderDescription },
            ),
        )
    }

    fun settingsIntent(context: Context): Intent =
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}
```

- [ ] **Step 6: The handler**

Create `app/android/app/src/main/kotlin/com/nimbustats/app/OutsideChannelHandler.kt`:

```kotlin
package com.nimbustats.app

import android.content.Context
import android.util.Log
import com.nimbustats.app.notifications.Notifier
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Answers Dart on the `com.nimbustats.app/outside` channel (spec §1.1) for both engines.
 *
 * - The app's engine registers it in [MainActivity], with the launch route and the permission
 *   dialog.
 * - The widget drain's headless engine registers it in `DrainJobService`, with
 *   [onDrainFinished].
 *
 * Native code stores and displays; every string arrives from Dart.
 */
class OutsideChannelHandler(
    private val context: Context,
    private val takeLaunchRoute: () -> String? = { null },
    private val requestPermission: ((MethodChannel.Result) -> Unit)? = null,
    private val onDrainFinished: ((Boolean) -> Unit)? = null,
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "notificationsEnabled" -> result.success(Notifier.enabled(context))
                "requestNotificationPermission" -> {
                    val request = requestPermission
                    if (request == null) {
                        result.error("no-activity", "the permission dialog needs the app's activity", null)
                    } else {
                        request(result)
                    }
                }
                "openNotificationSettings" -> {
                    context.startActivity(Notifier.settingsIntent(context))
                    result.success(null)
                }
                "registerChannels" -> {
                    Notifier.registerChannels(
                        context,
                        call.string("alertsName"),
                        call.string("alertsDescription"),
                        call.string("reminderName"),
                        call.string("reminderDescription"),
                    )
                    result.success(null)
                }
                "takeLaunchRoute" -> result.success(takeLaunchRoute())
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            // Reaches Dart as a PlatformException, which Dart reports (spec §9).
            Log.e(TAG, "outside channel: ${call.method} failed", error)
            result.error("native-failure", error.message, null)
        }
    }

    companion object {
        const val CHANNEL = "com.nimbustats.app/outside"
        const val TAG = "NimbuStats"

        /**
         * The app engine's channel while its activity lives. The drain job hands the app engine
         * the work through it (spec §2.4).
         */
        @Volatile
        var appChannel: MethodChannel? = null
    }
}

/** A required string argument. A missing one is Dart's bug, so it fails loudly. */
internal fun MethodCall.string(key: String): String =
    argument<String>(key) ?: throw IllegalArgumentException("missing argument $key")
```

- [ ] **Step 7: MainActivity**

Replace `app/android/app/src/main/kotlin/com/nimbustats/app/MainActivity.kt` with:

```kotlin
package com.nimbustats.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.nimbustats.app.notifications.Notifier
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /** The route a notification tap launched the app with, until Dart takes it. */
    private var launchRoute: String? = null
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchRoute = intent?.getStringExtra(Notifier.EXTRA_ROUTE)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OutsideChannelHandler.CHANNEL)
        channel.setMethodCallHandler(
            OutsideChannelHandler(
                applicationContext,
                takeLaunchRoute = { launchRoute.also { launchRoute = null } },
                requestPermission = ::requestNotificationPermission,
            ),
        )
        OutsideChannelHandler.appChannel = channel
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        OutsideChannelHandler.appChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** A notification tapped while the app runs (`singleTop`): Dart navigates. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val route = intent.getStringExtra(Notifier.EXTRA_ROUTE) ?: return
        OutsideChannelHandler.appChannel?.invokeMethod("openRoute", route)
    }

    /**
     * Spec §4.2. Below Android 13, or when already granted, it answers at once with no dialog.
     * After two denials Android shows nothing and answers false. No "already asked" state is kept.
     */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(Notifier.enabled(this))
            return
        }
        // A second ask while the dialog is up answers the first, so no Dart future waits forever.
        permissionResult?.success(false)
        permissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATIONS) return
        permissionResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        permissionResult = null
    }

    private companion object {
        const val REQUEST_NOTIFICATIONS = 6_100
    }
}
```

- [ ] **Step 8: The manifest permission and the status-bar icon**

In `app/android/app/src/main/AndroidManifest.xml`, insert directly after the opening `<manifest …>` line:

```xml
    <!-- Phase 6: alerts and the reminder (Android 13+ runtime permission,
         asked in context, never at first launch). -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Create `app/android/app/src/main/res/drawable/ic_stat_nimbus.xml`. It is a monochrome bar chart, as Android requires for a status-bar icon:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M5,19h3v-7H5V19zM10.5,19h3V5h-3V19zM16,19h3v-10h-3V19z" />
</vector>
```

- [ ] **Step 9: Build**

Run from `app/`: `flutter build apk --debug`. Expected: `✓ Built …app-debug.apk`. A Kotlin compile error here is fixed in this task.

- [ ] **Step 10: Broader suite**

Run, from the repo root: `dart analyze --fatal-infos`. From `app/`: `flutter test --no-pub --concurrency=4 --timeout 90s`. Expected: green.

- [ ] **Step 11: Commit and fast-forward**

```bash
git add app/android/app/build.gradle.kts app/android/app/src/main/AndroidManifest.xml app/android/app/src/main/kotlin app/android/app/src/main/res/drawable/ic_stat_nimbus.xml
git commit -m "$(cat <<'EOF'
feat(android): the outside channel, notification channels, permission ask

The native half of spec §1.1's first methods: notification state, the
Android 13 permission asked in context, channel registration with
Dart's strings, the app-settings shortcut, and the launch route a
notification tap carries. One handler class serves both the app engine
and (from Task 14) the headless drain engine; MainActivity publishes
its channel so the drain job can hand the app engine the work.

minSdk rises from Flutter's 24 to 26: the reminder and the widget
compute local times with java.time, API 26+ without desugaring
(operator decision, 2026-10-12). No host test exists for Android glue;
built here, verified on device in Task 17.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/android-outside-channel
```

---

### Task 6: `NotificationsBridge` — channels in the app's language, and notification taps open their route

Slug: `notifications-bridge`. Spec §4.1 and §1.1 (`takeLaunchRoute`, `openRoute`), ruling R6.

**Files:**
- Create: `app/lib/features/notifications/presentation/notifications_bridge.dart`
- Modify: `app/lib/bootstrap/app_shell.dart` (wrap in the bridge)
- Modify: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_fa.arb`
- Test: `app/test/features/notifications/notifications_bridge_test.dart`

**Interfaces:**
- Consumes: `outsideChannelProvider`, `ChannelTexts`, `reportingFailure` (Task 4).
- Produces: `class NotificationsBridge extends ConsumerStatefulWidget { const NotificationsBridge({super.key, required this.child}); }`. Task 9 extends its state with the reminder re-push.

- [ ] **Step 1: Branch**

```bash
git checkout -b feat/notifications-bridge phase/6-outside-the-app
```

- [ ] **Step 2: Write the failing test**

Create `app/test/features/notifications/notifications_bridge_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../support/harness.dart';
import 'support/fake_outside_channel.dart';

void main() {
  late AppDatabase db;
  late FakeOutsideChannel outside;

  setUp(() {
    db = AppDatabase.openInMemory();
    outside = FakeOutsideChannel();
  });
  tearDown(() => db.close());

  testWidgets('channels are named in the app language, and renamed after a '
      'language switch', (tester) async {
    // No locale override: the language comes from settings (fa by default).
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        outside: outside,
        initialLocation: '/settings',
        locale: null);

    expect(outside.channelTexts.last.alertsName, 'هشدارهای هدف');
    expect(outside.channelTexts.last.reminderName, 'یادآور روزانه');

    await tester.tap(find.byKey(const Key('settings-locale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('locale-en')));
    await tester.pumpAndSettle();

    expect(outside.channelTexts.last, (
      alertsName: 'Goal alerts',
      alertsDescription: 'Budget and limit warnings',
      reminderName: 'Daily reminder',
      reminderDescription: 'Your daily reminder to log',
    ));
  });

  testWidgets('the route a notification launched the app with opens after '
      'the first frame', (tester) async {
    outside.launchRoute = '/add';
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);

    expect(find.widgetWithText(AppBar, 'Add expense'), findsOneWidget);
    expect(outside.launchRoute, isNull, reason: 'taken once');
  });

  testWidgets('a notification tapped while the app runs opens its route',
      (tester) async {
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);
    expect(find.widgetWithText(AppBar, 'Add expense'), findsNothing);

    outside.tapRoute('/add');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Add expense'), findsOneWidget);
  });
}
```

- [ ] **Step 3: RED**

Run from `app/`: `flutter test --no-pub test/features/notifications/notifications_bridge_test.dart`. Expected: the first test fails with `Bad state: No element` on `channelTexts.last`, and the other two fail to find `Add expense`.

- [ ] **Step 4: Tag**

```bash
git tag pre-notifications-bridge phase/6-outside-the-app
```

- [ ] **Step 5: The strings**

In `app/lib/l10n/app_en.arb`, insert in alphabetical position. That is after the last `nav…` key and before the first `onboarding…` key. Check with `grep -n '"nav\|"onboarding' app/lib/l10n/app_en.arb`.

```json
  "notificationsAlertsChannelDescription": "Budget and limit warnings",
  "notificationsAlertsChannelName": "Goal alerts",
  "notificationsReminderChannelDescription": "Your daily reminder to log",
  "notificationsReminderChannelName": "Daily reminder",
```

In `app/lib/l10n/app_fa.arb`, insert at the same alphabetical position:

```json
  "notificationsAlertsChannelDescription": "هشدارهای بودجه و سقف",
  "notificationsAlertsChannelName": "هشدارهای هدف",
  "notificationsReminderChannelDescription": "یادآور روزانه برای ثبت",
  "notificationsReminderChannelName": "یادآور روزانه",
```

Run from `app/`: `flutter gen-l10n`. Expected: it regenerates `lib/l10n/app_localizations*.dart` with no warnings.

- [ ] **Step 6: The bridge**

Create `app/lib/features/notifications/presentation/notifications_bridge.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../application/outside_errors.dart';
import '../data/outside_channel.dart';

/// Keeps Android's side of notifications in step with the app (spec §4.1,
/// §1.1):
/// - names the two channels in the app's language, at start and again
///   after a language switch;
/// - opens the route of a notification that launched the app, once, after
///   the first frame;
/// - opens the route of a notification tapped while the app runs.
///
/// It sits on the shell (ruling R6): the routes need the router, and
/// nothing posts before the app has run once, so the channels exist
/// whenever they are needed.
class NotificationsBridge extends ConsumerStatefulWidget {
  const NotificationsBridge({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationsBridge> createState() =>
      _NotificationsBridgeState();
}

class _NotificationsBridgeState extends ConsumerState<NotificationsBridge> {
  late final OutsideChannel _channel;
  late final StreamSubscription<String> _routes;

  /// The locale the channels were last named in.
  Locale? _namedIn;

  @override
  void initState() {
    super.initState();
    _channel = ref.read(outsideChannelProvider);
    _routes = _channel.routes.listen(_open);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final route = await reportingFailure('alert router',
          'while reading the launch route', _channel.takeLaunchRoute);
      if (route != null) _open(route);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (locale == _namedIn) return;
    _namedIn = locale;
    final l10n = AppLocalizations.of(context);
    unawaited(reportingFailure(
      'alert router',
      'while naming the notification channels',
      () => _channel.registerChannels((
        alertsName: l10n.notificationsAlertsChannelName,
        alertsDescription: l10n.notificationsAlertsChannelDescription,
        reminderName: l10n.notificationsReminderChannelName,
        reminderDescription: l10n.notificationsReminderChannelDescription,
      )),
    ));
  }

  void _open(String route) {
    if (!mounted) return;
    unawaited(GoRouter.of(context).push(route));
  }

  @override
  void dispose() {
    unawaited(_routes.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

`GoRouter.push` returns `Future<T?>` in go_router 17.5.0 (`router.dart:448`). `unawaited_futures` is an error in `analysis_options.yaml`, which is why the `unawaited(…)` is there.

- [ ] **Step 7: Mount it on the shell**

In `app/lib/bootstrap/app_shell.dart`:
1. Add the import `import '../features/notifications/presentation/notifications_bridge.dart';`.
2. Wrap the returned `GoalAlertListener(…)` so `build` returns `NotificationsBridge(child: GoalAlertListener(…))`.
3. Above it, add the comment:

```dart
    // Phase 6: Android's notification channels follow the app's language,
    // and a notification tap opens its route (ruling R6).
```

- [ ] **Step 8: GREEN**

Run: `flutter test --no-pub test/features/notifications/notifications_bridge_test.dart`. Expected: all pass.

- [ ] **Step 9: Broader suite**

Run, from the repo root: `dart analyze --fatal-infos`. From `app/`: `flutter test --no-pub --concurrency=4 --timeout 90s`. Expected: green. `localization_test.dart` confirms both bundles have the keys, and that no Persian value is left in English.

- [ ] **Step 10: Commit and fast-forward**

```bash
git add app/lib/features/notifications/presentation app/lib/bootstrap/app_shell.dart app/lib/l10n app/test/features/notifications/notifications_bridge_test.dart
git commit -m "$(cat <<'EOF'
feat(notifications): channels in the app's language; taps open routes

Android shows the alert and reminder channels in its settings, so they
are named from the ARB strings at start-up and renamed after a language
switch (re-creating a channel id renames it). A notification that
launched the app opens its route after the first frame, and one tapped
while the app runs opens it at once.

Mounted on AppShell (Phase 0/1 file, one wrapper line): the routes need
the router, and the shell exists exactly when first run is done.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/notifications-bridge
```

---
### Task 7: `AlertRouter` — snackbar in the foreground, a discreet notification otherwise

Slug: `alert-router`. Spec §4.3, §8 (`notification_detail`), §9.

**Files:**
- Modify: `app/lib/features/settings/data/settings_keys.dart` (three keys)
- Create: `app/lib/features/notifications/data/notification_prefs.dart`
- Create: `app/lib/features/notifications/application/notification_providers.dart`
- Create: `app/lib/features/notifications/application/alert_router.dart`
- Modify: `app/lib/features/goals/presentation/goal_alert_listener.dart`
- Modify: `app/test/support/harness.dart` (`isForeground`)
- Modify: `app/test/features/notifications/support/fake_outside_channel.dart` (`postError`)
- Modify: `app/lib/l10n/app_en.arb`, `app/lib/l10n/app_fa.arb`
- Modify: `app/android/app/src/main/kotlin/com/nimbustats/app/notifications/Notifier.kt` (`postAlert`, `routeIntent`)
- Modify: `app/android/app/src/main/kotlin/com/nimbustats/app/OutsideChannelHandler.kt` (`postAlert` arm)
- Test: `app/test/features/notifications/notification_prefs_test.dart`, `app/test/features/notifications/alert_router_test.dart`

**Interfaces:**
- Consumes:
  - `GoalWatcher.alerts` and `checkNow()` (Task 3).
  - `outsideChannelProvider` and `reportingFailure` (Task 4).
  - `GoalFormat.alertMessage(l10n, alert, period)` (Phase 5).
  - `SettingsRepository.load()`, `goalServiceProvider` and `goalDetailRoute`.
- Produces:
  - Setting keys `SettingsKeys.reminderEnabled`, `SettingsKeys.reminderMinuteOfDay` and `SettingsKeys.notificationDetail`.
  - `final class NotificationPrefs`, with `reminderEnabled`, `reminderMinuteOfDay`, `showDetails`, and `static const defaults`.
  - `final class NotificationPrefsRepository(SettingsDao)`, with `load()`, `watch()`, `setReminder({required bool enabled, required int minuteOfDay})`, `setShowDetails(bool)`, and `static NotificationPrefs parse(Map<String, String>)`.
  - `notificationPrefsRepositoryProvider`, `notificationPrefsProvider` (a `StreamProvider<NotificationPrefs>`), and `isForegroundProvider` (a `Provider<bool Function()>`).
  - `final class AlertRouter`, with `Stream<GoalAlert> get foregroundAlerts` and `Future<void> idle()`, and `alertRouterProvider`.
  - On the harness, `pumpApp(…, bool Function()? isForeground)`, which defaults to `() => true`.

- [ ] **Step 1: Branch**

```bash
git checkout -b feat/alert-router phase/6-outside-the-app
```

- [ ] **Step 2: Write the failing tests**

Create `app/test/features/notifications/notification_prefs_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/notifications/data/notification_prefs.dart';
import 'package:nimbustats/features/settings/data/settings_keys.dart';

void main() {
  late AppDatabase db;
  late NotificationPrefsRepository prefs;
  late List<FlutterErrorDetails> reported;
  FlutterExceptionHandler? previous;

  setUp(() {
    db = AppDatabase.openInMemory();
    prefs = NotificationPrefsRepository(db.settingsDao);
    reported = [];
    previous = FlutterError.onError;
    FlutterError.onError = reported.add;
  });
  tearDown(() async {
    FlutterError.onError = previous;
    await db.close();
  });

  test('absent keys read as off, 21:00, discreet', () async {
    expect(await prefs.load(), NotificationPrefs.defaults);
    expect(NotificationPrefs.defaults.reminderMinuteOfDay, 1260);
    expect(reported, isEmpty);
  });

  test('saved values read back', () async {
    await prefs.setReminder(enabled: true, minuteOfDay: 450);
    await prefs.setShowDetails(true);
    expect(
      await prefs.load(),
      const NotificationPrefs(
          reminderEnabled: true, reminderMinuteOfDay: 450, showDetails: true),
    );
  });

  test('a value that does not parse is reported and reads as its default; '
      'saving repairs it', () async {
    await db.settingsDao.put(SettingsKeys.reminderMinuteOfDay, '25:00');
    await db.settingsDao.put(SettingsKeys.notificationDetail, 'yes');

    final read = await prefs.load();
    expect(read.reminderMinuteOfDay, 1260);
    expect(read.showDetails, isFalse);
    expect(reported.map((e) => e.library), ['reminder', 'reminder']);

    await prefs.setReminder(enabled: false, minuteOfDay: 600);
    expect((await prefs.load()).reminderMinuteOfDay, 600);
  });

  test('a reset leaves these keys alone (spec §8)', () {
    expect(SettingsKeys.appSettings, isNot(contains(SettingsKeys.reminderEnabled)));
    expect(SettingsKeys.appSettings,
        isNot(contains(SettingsKeys.reminderMinuteOfDay)));
    expect(SettingsKeys.appSettings,
        isNot(contains(SettingsKeys.notificationDetail)));
  });

  test('a minute outside the day is refused before it is written', () {
    expect(() => prefs.setReminder(enabled: true, minuteOfDay: 1440),
        throwsArgumentError);
  });
}
```

Create `app/test/features/notifications/alert_router_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/provider_retry.dart';
import 'package:nimbustats/features/goals/application/goal_watcher.dart';
import 'package:nimbustats/features/notifications/application/alert_router.dart';
import 'package:nimbustats/features/notifications/application/notification_providers.dart';
import 'package:nimbustats/features/notifications/data/notification_prefs.dart';
import 'package:nimbustats/features/notifications/data/outside_channel.dart';

import '../goals/support/goal_test_app.dart';
import '../trackers/support/tracker_fixture.dart';
import 'support/fake_outside_channel.dart';

/// The router as both engines run it: real providers over a test database,
/// with the channel faked and the lifecycle injected.
void main() {
  late FakeClock fake;
  late AppDatabase db;
  late GoalService service;
  late FakeOutsideChannel outside;
  late bool foreground;

  const day5 = DateKey(20261005);

  setUp(() async {
    fake = FakeClock();
    db = AppDatabase.openInMemory();
    service = goalServiceFor(db, fake.clock.today);
    outside = FakeOutsideChannel();
    foreground = false;
    await seedCategories(db);
    await useEnglishDigits(db); // English settings: English notification text
    await service.save(spendingCap()); // 'Dining out', 1,000,000 a month
    await spend(db, 850000, day5); // 85%: crosses 80
  });
  tearDown(() => db.close());

  late List<GoalAlert> snackbars;

  Future<(AlertRouter, GoalWatcher)> start() async {
    final c = ProviderContainer(retry: nimbusNoRetry, overrides: [
      appDatabaseProvider.overrideWithValue(db),
      ...trackerOverrides(fake),
      outsideChannelProvider.overrideWithValue(outside),
      isForegroundProvider.overrideWithValue(() => foreground),
    ]);
    addTearDown(c.dispose);
    final router = c.read(alertRouterProvider);
    snackbars = [];
    final subscription = router.foregroundAlerts.listen(snackbars.add);
    addTearDown(subscription.cancel);
    return (router, c.read(goalWatcherProvider));
  }

  Future<void> cross(AlertRouter router, GoalWatcher watcher) async {
    await watcher.checkNow();
    await Future<void>.delayed(Duration.zero); // the broadcast delivery
    await router.idle();
  }

  test('in the foreground an alert goes to the snackbar stream only',
      () async {
    foreground = true;
    final (router, watcher) = await start();
    await cross(router, watcher);

    expect(snackbars.single.percent, 80);
    expect(outside.posted, isEmpty);
  });

  test('otherwise it posts one discreet notification, tagged per goal, that '
      'opens the goal', () async {
    final (router, watcher) = await start();
    await cross(router, watcher);

    expect(snackbars, isEmpty);
    expect(outside.posted, [
      (
        tag: 'goal:cap',
        text: 'A goal needs a look',
        publicText: 'A goal needs a look',
        route: '/goals/cap',
      ),
    ]);
  });

  test('with details on, the text is the full alert; the lock screen still '
      'gets the discreet one', () async {
    await NotificationPrefsRepository(db.settingsDao).setShowDetails(true);
    final (router, watcher) = await start();
    await cross(router, watcher);

    expect(outside.posted.single.text, "Dining out: 85% of this month's limit");
    expect(outside.posted.single.publicText, 'A goal needs a look');
  });

  test('recomputation posts nothing more', () async {
    final (router, watcher) = await start();
    await cross(router, watcher);
    await cross(router, watcher);
    expect(outside.posted, hasLength(1));
  });

  test('a failed post is reported under "alert router", not retried',
      () async {
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
    outside.postError = PlatformException(code: 'boom');

    final (router, watcher) = await start();
    await cross(router, watcher);

    expect(reported.single.library, 'alert router');
    expect(outside.calls.where((c) => c == 'postAlert'), hasLength(1));
  });
}
```

- [ ] **Step 3: RED**

Run from `app/`: `flutter test --no-pub test/features/notifications/notification_prefs_test.dart test/features/notifications/alert_router_test.dart`. Expected: compile errors. `notification_prefs.dart` and `alert_router.dart` do not exist, and `postError` is undefined.

- [ ] **Step 4: Tag**

```bash
git tag pre-alert-router phase/6-outside-the-app
```

- [ ] **Step 5: The keys and the prefs**

In `app/lib/features/settings/data/settings_keys.dart`, after `seedVersion`, add:

```dart

  /// Phase 6's notification settings. Outside [appSettings] on purpose: a
  /// settings reset must not leave a reminder armed in Android's alarm
  /// manager while the database says it is off (Phase 6 spec §8). Read by
  /// `NotificationPrefsRepository`, which reports a bad value and reads its
  /// default rather than failing.
  static const reminderEnabled = 'reminder_enabled';
  static const reminderMinuteOfDay = 'reminder_minute_of_day';
  static const notificationDetail = 'notification_detail';
```

Create `app/lib/features/notifications/data/notification_prefs.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../settings/data/settings_keys.dart';

/// The reminder and the notification detail level (spec §5, §8).
@immutable
final class NotificationPrefs {
  const NotificationPrefs({
    required this.reminderEnabled,
    required this.reminderMinuteOfDay,
    required this.showDetails,
  });

  /// Off; 21:00; discreet.
  static const defaults = NotificationPrefs(
    reminderEnabled: false,
    reminderMinuteOfDay: 1260,
    showDetails: false,
  );

  final bool reminderEnabled;

  /// Minutes after local midnight, 0..1439.
  final int reminderMinuteOfDay;

  /// Goal names and amounts in alert notifications. The lock screen gets the
  /// discreet text either way.
  final bool showDetails;

  @override
  bool operator ==(Object other) =>
      other is NotificationPrefs &&
      other.reminderEnabled == reminderEnabled &&
      other.reminderMinuteOfDay == reminderMinuteOfDay &&
      other.showDetails == showDetails;

  @override
  int get hashCode =>
      Object.hash(reminderEnabled, reminderMinuteOfDay, showDetails);

  @override
  String toString() => 'NotificationPrefs(reminder: $reminderEnabled at '
      '$reminderMinuteOfDay, details: $showDetails)';
}

/// Typed access to the three notification keys.
///
/// Unlike `SettingsRepository`, a value that does not parse does not fail
/// the read. It is reported, and reads as its default: a broken reminder
/// setting must not take the settings screen down, and saving a new value
/// repairs it (spec §8).
final class NotificationPrefsRepository {
  const NotificationPrefsRepository(this._dao);

  final SettingsDao _dao;

  Future<NotificationPrefs> load() async => parse(await _dao.getAll());

  Stream<NotificationPrefs> watch() => _dao.watchAll().map(parse);

  Future<void> setReminder({
    required bool enabled,
    required int minuteOfDay,
  }) async {
    if (minuteOfDay < 0 || minuteOfDay >= 1440) {
      throw ArgumentError.value(
          minuteOfDay, 'minuteOfDay', 'minutes after midnight, 0..1439');
    }
    await _dao.put(SettingsKeys.reminderEnabled, '$enabled');
    await _dao.put(SettingsKeys.reminderMinuteOfDay, '$minuteOfDay');
  }

  Future<void> setShowDetails(bool value) =>
      _dao.put(SettingsKeys.notificationDetail, '$value');

  static NotificationPrefs parse(Map<String, String> raw) => NotificationPrefs(
        reminderEnabled: _read(raw, SettingsKeys.reminderEnabled,
            NotificationPrefs.defaults.reminderEnabled, _bool),
        reminderMinuteOfDay: _read(raw, SettingsKeys.reminderMinuteOfDay,
            NotificationPrefs.defaults.reminderMinuteOfDay, _minute),
        showDetails: _read(raw, SettingsKeys.notificationDetail,
            NotificationPrefs.defaults.showDetails, _bool),
      );

  static T _read<T>(
    Map<String, String> raw,
    String key,
    T fallback,
    T? Function(String) parse,
  ) {
    final value = raw[key];
    if (value == null) return fallback;
    final parsed = parse(value);
    if (parsed != null) return parsed;
    FlutterError.reportError(FlutterErrorDetails(
      exception: FormatException('setting "$key" does not parse', value),
      library: 'reminder',
      context: ErrorDescription('while reading the notification settings; '
          'it reads as its default until a new value is saved'),
    ));
    return fallback;
  }

  static bool? _bool(String value) => switch (value) {
        'true' => true,
        'false' => false,
        _ => null,
      };

  static int? _minute(String value) {
    final parsed = int.tryParse(value);
    return parsed != null && parsed >= 0 && parsed < 1440 ? parsed : null;
  }
}
```

Create `app/lib/features/notifications/application/notification_providers.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bootstrap/database_provider.dart';
import '../data/notification_prefs.dart';

final notificationPrefsRepositoryProvider =
    Provider<NotificationPrefsRepository>((ref) =>
        NotificationPrefsRepository(ref.watch(appDatabaseProvider).settingsDao));

/// The reminder and detail settings, live: the settings section watches it.
final notificationPrefsProvider = StreamProvider<NotificationPrefs>(
    (ref) => ref.watch(notificationPrefsRepositoryProvider).watch());

/// Whether the app is on screen (spec §4.3). The headless drain engine has
/// no lifecycle, so it reads false there, and every alert becomes a
/// notification. Overridden in tests.
final isForegroundProvider = Provider<bool Function()>((ref) => () =>
    WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
```

- [ ] **Step 6: The router**

Create `app/lib/features/notifications/application/alert_router.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../goals/application/goal_format.dart';
import '../../goals/application/goal_providers.dart';
import '../../goals/application/goal_watcher.dart';
import '../../goals/routes.dart';
import '../../settings/application/settings_providers.dart';
import '../../trackers/application/tracker_format.dart';
import '../data/outside_channel.dart';
import 'notification_providers.dart';
import 'outside_errors.dart';

/// Decides *where* each goal alert is shown, never *whether* (spec §4.3).
/// Phase 5 decided that.
///
/// It is the only subscriber to the watcher's alerts. That gives one
/// decision point, so no alert is shown twice or missed at a lifecycle
/// boundary:
/// - In the foreground, the alert goes to [foregroundAlerts], which the
///   shell's `GoalAlertListener` shows as Phase 5's snackbar.
/// - Otherwise, including the headless drain engine, it is posted as a
///   notification. The tag is `goal:<id>`, so a 100% replaces that goal's
///   80%. The text is discreet unless the user turned details on. The lock
///   screen always gets the discreet text, and a tap opens the goal.
///
/// A failed post is reported, not retried. Phase 5 has already recorded the
/// crossing, by design (spec §9).
final class AlertRouter {
  AlertRouter(this._ref) {
    _subscription = _ref.read(goalWatcherProvider).alerts.listen(_route);
  }

  final Ref _ref;
  late final StreamSubscription<GoalAlert> _subscription;
  final _foreground = StreamController<GoalAlert>.broadcast();
  final _posting = <Future<void>>{};

  Stream<GoalAlert> get foregroundAlerts => _foreground.stream;

  /// Completes once every notification already being posted has been. The
  /// headless drain waits on this before its engine is destroyed.
  Future<void> idle() => Future.wait(List.of(_posting));

  void _route(GoalAlert alert) {
    if (_ref.read(isForegroundProvider)()) {
      _foreground.add(alert);
      return;
    }
    final post = reportingFailure('alert router',
        'while posting the alert for goal ${alert.goalId}', () => _post(alert));
    _posting.add(post);
    unawaited(post.whenComplete(() => _posting.remove(post)));
  }

  /// Reads the settings once, here, rather than through the settings stream.
  /// The headless engine posts before that stream has emitted, and would
  /// otherwise word the alert in the default language.
  Future<void> _post(GoalAlert alert) async {
    final settings = await _ref.read(settingsRepositoryProvider).load();
    final prefs = await _ref.read(notificationPrefsRepositoryProvider).load();
    final l10n = lookupAppLocalizations(settings.locale);
    final discreet = l10n.notificationsAlertDiscreet;
    final text = prefs.showDetails
        ? GoalFormat(
            money: settings.moneyFormatter,
            trackers: TrackerFormat(
              localeTag: settings.locale.languageCode,
              persianDigits: settings.persianDigits,
              calendar: settings.calendar,
            ),
          ).alertMessage(l10n, alert, await _periodOf(alert.goalId))
        : discreet;
    await _ref.read(outsideChannelProvider).postAlert(
          tag: 'goal:${alert.goalId}',
          text: text,
          publicText: discreet,
          route: goalDetailRoute(alert.goalId),
        );
  }

  /// The goal's period type, for the wording, as `GoalAlertListener` finds
  /// it. A goal deleted since reads plainly, through the message's `other`
  /// case.
  Future<String> _periodOf(String goalId) async {
    for (final read in await _ref.read(goalServiceProvider).goals()) {
      if (read case GoalReadable(:final goal) when goal.id == goalId) {
        return goal.period.storedName;
      }
    }
    return 'other';
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _foreground.close();
  }
}

/// Created once per engine, before the watcher starts or checks, so no alert
/// is emitted with no one routing it.
final alertRouterProvider = Provider<AlertRouter>((ref) {
  final router = AlertRouter(ref);
  ref.onDispose(() => unawaited(router.dispose()));
  return router;
});
```

`AppSettings.persianDigits`, `.calendar`, `.moneyFormatter` and `.locale` exist (`app_settings.dart:41–61`). `GoalFormat`'s named parameters are `money:` and `trackers:` (`goal_format.dart:127`).

- [ ] **Step 7: The shell shows only foreground alerts**

In `app/lib/features/goals/presentation/goal_alert_listener.dart`:
1. Add `import '../../notifications/application/alert_router.dart';`.
2. In `initState`, replace `_alerts = _watcher.alerts.listen(_show);` with:

```dart
    // Phase 6: the router decides where each alert goes. This shows the
    // ones it keeps on screen. Read before start(), so the router is
    // subscribed before the watcher's first evaluation.
    _alerts = ref.read(alertRouterProvider).foregroundAlerts.listen(_show);
```

3. Replace the class doc comment's first sentence, `Shows each goal alert as a snackbar, until Phase 6 makes them notifications (spec §4.2).`, with `Shows each goal alert the app gets while on screen as a snackbar (Phase 5 spec §4.2). Phase 6's \`AlertRouter\` posts the rest as notifications.`

- [ ] **Step 8: The harness keeps a pumped app on screen**

The test binding reports no lifecycle state until a test sets one. `flutter_test`'s `initialLifecycleState` is `''`. Without this override every widget test's alert would become a notification. In `app/test/support/harness.dart`:
1. Add `import 'package:nimbustats/features/notifications/application/notification_providers.dart';`.
2. Add the parameter `bool Function()? isForeground,`.
3. Add this override after the `outsideChannelProvider` one:

```dart
    // A pumped app is on screen. The test binding reports no lifecycle
    // state until a test sets one, which would read as "in the background".
    isForegroundProvider.overrideWithValue(isForeground ?? () => true),
```

In `app/test/features/notifications/support/fake_outside_channel.dart`, add the field below `int settingsOpened = 0;`:

```dart
  /// Thrown by the next [postAlert], to test a failed post.
  Object? postError;
```

As the first two lines of `postAlert`'s body, after `calls.add('postAlert');`, add:

```dart
    final error = postError;
    if (error != null) throw error;
```

- [ ] **Step 9: The string**

In both ARB files, insert in alphabetical position, before `notificationsAlertsChannelDescription`:
- `app_en.arb`: `"notificationsAlertDiscreet": "A goal needs a look",`
- `app_fa.arb`: `"notificationsAlertDiscreet": "یک هدف نیاز به بررسی دارد",`

Then run from `app/`: `flutter gen-l10n`.

- [ ] **Step 10: The native post**

In `Notifier.kt`:
1. Add the imports:

```kotlin
import android.app.Notification
import android.app.PendingIntent
import android.util.Log
import com.nimbustats.app.MainActivity
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import com.nimbustats.app.R
```

2. Add inside the object:

```kotlin
    /**
     * A goal alert (spec §4.3). Tag `goal:<id>` and id 1, so a 100% crossing replaces that goal's
     * 80% one. The lock screen shows [publicText], never a name or an amount.
     *
     * A post Android would drop is logged instead: the crossing is already recorded, so it is
     * not retried (spec §9).
     */
    fun postAlert(context: Context, tag: String, text: String, publicText: String, route: String) {
        if (!canPost(context, ALERTS, "goal alert $tag")) return
        val public = Notification.Builder(context, ALERTS)
            .setSmallIcon(R.drawable.ic_stat_nimbus)
            .setContentText(publicText)
            .build()
        val notification = Notification.Builder(context, ALERTS)
            .setSmallIcon(R.drawable.ic_stat_nimbus)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(public)
            .setContentIntent(routeIntent(context, route, tag))
            .setAutoCancel(true)
            .build()
        context.getSystemService(NotificationManager::class.java).notify(tag, 1, notification)
    }

    /** Opens [route] in the app: `MainActivity` passes it to Dart (launch or `openRoute`). */
    internal fun routeIntent(context: Context, route: String, key: String): PendingIntent =
        PendingIntent.getActivity(
            context,
            key.hashCode(),
            Intent(context, MainActivity::class.java)
                .putExtra(EXTRA_ROUTE, route)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    /** Whether a post on [channel] would be shown; if not, says why in logcat. */
    internal fun canPost(context: Context, channel: String, what: String): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        val reason = when {
            !manager.areNotificationsEnabled() -> "notifications are disabled"
            manager.getNotificationChannel(channel) == null -> "channel $channel is not registered yet"
            manager.getNotificationChannel(channel).importance == NotificationManager.IMPORTANCE_NONE ->
                "channel $channel is blocked"
            else -> return true
        }
        Log.e(TAG, "$what not shown: $reason")
        return false
    }
```

In `OutsideChannelHandler.kt`, add this arm before `"takeLaunchRoute"`:

```kotlin
                "postAlert" -> {
                    Notifier.postAlert(
                        context,
                        call.string("tag"),
                        call.string("text"),
                        call.string("publicText"),
                        call.string("route"),
                    )
                    result.success(null)
                }
```

- [ ] **Step 11: GREEN**

Run from `app/`: `flutter test --no-pub test/features/notifications/ test/features/goals/goal_alert_listener_test.dart`. Expected: all pass. The listener tests still see their snackbars, through the router.

- [ ] **Step 12: Build and the broader suite**

Run, from `app/`: `flutter build apk --debug`, then `flutter test --no-pub --concurrency=4 --timeout 90s`. From the repo root: `dart analyze --fatal-infos`. Expected: green.

- [ ] **Step 13: Commit and fast-forward**

```bash
git add app/lib app/test app/android/app/src/main/kotlin
git commit -m "$(cat <<'EOF'
feat(notifications): goal alerts become notifications when off screen

AlertRouter is the one subscriber to Phase 5's alerts and decides only
where each is shown: Phase 5's snackbar while the app is resumed, a
notification otherwise -- including in the headless drain engine,
which has no lifecycle. Notifications are tagged goal:<id> so 100%
replaces 80%, discreet by default ("A goal needs a look"), full text
only with the new notification_detail setting, discreet on the lock
screen always, and open the goal on tap. A failed post is reported,
not retried: the crossing is already recorded.

GoalAlertListener (Phase 5) now listens to the router's foreground
stream; settings_keys.dart (Phase 1) gains the three Phase 6 keys,
outside appSettings so a reset cannot desync the native alarm.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/alert-router
```

---

### Task 8: The first goal's save asks for the notification permission

Slug: `goal-permission-ask`. Spec §4.2.

**Files:**
- Create: `app/lib/features/notifications/application/permission_request.dart`
- Modify: `app/lib/features/goals/presentation/goal_editor_screen.dart` (`_save`, line 151)
- Modify: `app/test/features/goals/support/goal_test_app.dart` (`pumpGoals` forwards `outside`)
- Test: `app/test/features/goals/goal_editor_screen_test.dart`

**Interfaces:**
- Consumes: `outsideChannelProvider` and `reportingFailure` (Task 4).
- Produces: `Future<bool> askForNotifications(OutsideChannel channel, {required String library})`. Task 10 uses it.

- [ ] **Step 1: Branch**

```bash
git checkout -b feat/goal-permission-ask phase/6-outside-the-app
```

- [ ] **Step 2: Write the failing tests**

In `app/test/features/goals/support/goal_test_app.dart`:
1. Add the parameter `OutsideChannel? outside,` to `pumpGoals`.
2. Pass `outside: outside,` through to `pumpApp`.
3. Add `import 'package:nimbustats/features/notifications/data/outside_channel.dart';`.

Append inside `main()` of `app/test/features/goals/goal_editor_screen_test.dart`, and add `import '../notifications/support/fake_outside_channel.dart';`:

```dart
  group('the notification permission (Phase 6, spec §4.2)', () {
    Future<void> saveACap(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('goals-new')));
      await tester.pumpAndSettle();
      await choose(tester, GoalKind.spendingCap);
      await tester.enterText(
          find.byKey(const Key('tx-amount-field')), '2000000');
      await tester.pump();
      await tester.tap(find.byKey(const Key('goal-save')));
      await tester.pumpAndSettle();
    }

    testWidgets("the first goal's save asks, once", (tester) async {
      final outside = FakeOutsideChannel();
      await pumpGoals(tester, db, fake, outside: outside);
      await saveACap(tester);

      expect(outside.permissionRequests, 1);
      expect(find.byKey(const Key('goals-list')), findsOneWidget,
          reason: 'the save still closes the editor');
    });

    testWidgets("a later goal's save does not ask", (tester) async {
      await service.save(spendingCap());
      final outside = FakeOutsideChannel();
      await pumpGoals(tester, db, fake, outside: outside);
      await saveACap(tester);

      expect(outside.permissionRequests, 0);
    });
  });
```

- [ ] **Step 3: RED**

Run from `app/`: `flutter test --no-pub test/features/goals/goal_editor_screen_test.dart`. Expected: `"the first goal's save asks, once"` fails with `Expected: <1> Actual: <0>`.

- [ ] **Step 4: Tag**

```bash
git tag pre-goal-permission-ask phase/6-outside-the-app
```

- [ ] **Step 5: Implement**

Create `app/lib/features/notifications/application/permission_request.dart`:

```dart
import '../data/outside_channel.dart';
import 'outside_errors.dart';

/// Asks for the notification permission in context (spec §4.2): after the
/// first goal is saved, and when the reminder is switched on. Never at first
/// launch.
///
/// Android does the rest. A granted permission answers at once with no
/// dialog, and after two denials it shows nothing, so no "already asked"
/// state is kept here. A channel failure is reported under [library] and
/// reads as not granted.
Future<bool> askForNotifications(
  OutsideChannel channel, {
  required String library,
}) async =>
    await reportingFailure(library,
        'while asking for the notification permission',
        channel.requestNotificationPermission) ??
    false;
```

In `app/lib/features/goals/presentation/goal_editor_screen.dart`:
1. Add the imports:

```dart
import '../../notifications/application/permission_request.dart';
import '../../notifications/data/outside_channel.dart';
```

2. In `_save()`, after `final service = ref.read(goalServiceProvider);`, add:

```dart
    final outside = ref.read(outsideChannelProvider);
    // The first goal is when notifications start to matter (Phase 6 spec
    // §4.2). Counted before the write, so this goal does not count itself.
    final firstGoal =
        widget.seed.goal == null && (await service.goals()).isEmpty;
```

3. After the `await reportingGoalFailure(…);` statement, add:

```dart
    // Not awaited: Android's dialog shows over the list the editor returns
    // to, and the save is already done.
    if (firstGoal) {
      unawaited(askForNotifications(outside, library: 'alert router'));
    }
```

- [ ] **Step 6: GREEN**

Run: `flutter test --no-pub test/features/goals/goal_editor_screen_test.dart`. Expected: all pass.

- [ ] **Step 7: Broader suite**

Run, from the repo root: `dart analyze --fatal-infos`. From `app/`: `flutter test --no-pub --concurrency=4 --timeout 90s`. Expected: green.

- [ ] **Step 8: Commit and fast-forward**

```bash
git add app/lib/features/notifications/application/permission_request.dart app/lib/features/goals/presentation/goal_editor_screen.dart app/test/features/goals
git commit -m "$(cat <<'EOF'
feat(goals): saving the first goal asks for the notification permission

Spec §4.2 asks in context, never at first launch: the first goal is
when a notification first has something to say. The ask happens only
when no goal existed before the save, and Android itself suppresses
the dialog once granted or twice denied, so no extra state is kept.

An additive edit to Phase 5's goal editor save path.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/goal-permission-ask
```

---

### Task 9: The daily reminder — native alarm, re-arm receivers, and the Dart controller

Slug: `daily-reminder`. Spec §5. This task adds JUnit: run the Maven Central probe first.

**Files:**
- Modify: `app/android/app/build.gradle.kts` (JUnit)
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/notifications/ReminderTime.kt`
- Create: `app/android/app/src/test/kotlin/com/nimbustats/app/notifications/ReminderTimeTest.kt`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/notifications/ReminderScheduler.kt`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/notifications/ReminderReceiver.kt`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/notifications/RearmReceiver.kt`
- Modify: `Notifier.kt` (`postReminder`), `OutsideChannelHandler.kt` (`setReminder` arm), `AndroidManifest.xml`
- Create: `app/lib/features/notifications/application/reminder_controller.dart`
- Modify: `app/lib/features/notifications/presentation/notifications_bridge.dart` (re-push)
- Modify: ARB files (`notificationsReminderText`)
- Test: `app/test/features/notifications/reminder_controller_test.dart`, `app/test/features/notifications/notifications_bridge_test.dart`

**Interfaces:**
- Consumes:
  - `NotificationPrefsRepository` and `notificationPrefsRepositoryProvider` (Task 7).
  - `askForNotifications` (Task 8).
  - `OutsideChannel.setReminder` (Task 4).
  - `addTransactionRoute`.
- Produces:
  - `ReminderTime.nextTrigger(now: ZonedDateTime, minuteOfDay: Int): ZonedDateTime` and `ReminderTime.nextMidnight(now: ZonedDateTime): ZonedDateTime`. Task 16 uses the second.
  - `ReminderScheduler.configure(context, enabled, minuteOfDay, text, route)` and `ReminderScheduler.rearm(context)`. Task 16 adds the midnight refresh to `rearm`.
  - `final class ReminderController`:
    - `Future<bool> enable(AppLocalizations l10n)`
    - `Future<void> disable(AppLocalizations l10n)`
    - `Future<void> setTime(AppLocalizations l10n, int minuteOfDay)`
    - `Future<void> push(AppLocalizations l10n)`
  - `reminderControllerProvider`.

- [ ] **Step 1: Branch and probe Maven Central**

```bash
git checkout -b feat/daily-reminder phase/6-outside-the-app
curl -s https://api.ipify.org; echo
for i in 1 2 3 4; do curl -s -o /dev/null -w '%{http_code}\n' https://repo.maven.apache.org/maven2/junit/junit/4.13.2/junit-4.13.2.pom; done
for i in 1 2 3 4; do curl -s -o /dev/null -w '%{http_code}\n' https://repo.maven.apache.org/maven2/org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.pom; done
```

Expected: eight `200`s. If any probe fails, **stop**. Ask the operator to switch the VPN to whole-system (TUN) mode, then re-probe. Do not drop JUnit, and do not probe through the system proxy (Global Constraints).

- [ ] **Step 2: Add JUnit, test-only**

At the end of `app/android/app/build.gradle.kts`, append:

```kotlin
dependencies {
    // Host-only tests for Phase 6's pure Kotlin logic: ReminderTime,
    // AmountParser, PendingOverlay, Uuid7. Test scope: never in the APK
    // (Phase 6 spec §10). From Maven Central.
    testImplementation("junit:junit:4.13.2")
}
```

- [ ] **Step 3: Write the failing JUnit test**

Create `app/android/app/src/test/kotlin/com/nimbustats/app/notifications/ReminderTimeTest.kt`:

```kotlin
package com.nimbustats.app.notifications

import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class ReminderTimeTest {
    private val tehran = ZoneId.of("Asia/Tehran")
    private val newYork = ZoneId.of("America/New_York")
    private val nine = 21 * 60

    private fun at(zone: ZoneId, y: Int, mo: Int, d: Int, h: Int, mi: Int) =
        ZonedDateTime.of(y, mo, d, h, mi, 0, 0, zone)

    @Test
    fun laterTodayWhenTheTimeIsStillAhead() {
        assertEquals(
            at(tehran, 2026, 10, 12, 21, 0),
            ReminderTime.nextTrigger(at(tehran, 2026, 10, 12, 9, 30), nine),
        )
    }

    @Test
    fun tomorrowWhenTheTimeHasPassedOrIsNow() {
        assertEquals(
            at(tehran, 2026, 10, 13, 21, 0),
            ReminderTime.nextTrigger(at(tehran, 2026, 10, 12, 21, 30), nine),
        )
        // Strictly after now: a reminder firing at 21:00 arms tomorrow's.
        assertEquals(
            at(tehran, 2026, 10, 13, 21, 0),
            ReminderTime.nextTrigger(at(tehran, 2026, 10, 12, 21, 0), nine),
        )
    }

    @Test
    fun aTimeInTheSpringGapMovesLaterByTheGap() {
        // 2026-03-08 02:30 does not exist in New York: clocks jump 02:00 -> 03:00.
        val trigger = ReminderTime.nextTrigger(at(newYork, 2026, 3, 8, 0, 0), 2 * 60 + 30)
        assertEquals(3, trigger.hour)
        assertEquals(30, trigger.minute)
        assertEquals(ZoneOffset.ofHours(-4), trigger.offset)
    }

    @Test
    fun aTimeInTheAutumnOverlapTakesTheEarlierInstant() {
        // 2026-11-01 01:30 happens twice in New York; java.time keeps the earlier offset.
        val trigger = ReminderTime.nextTrigger(at(newYork, 2026, 11, 1, 0, 0), 90)
        assertEquals(ZoneOffset.ofHours(-4), trigger.offset)
        assertEquals(1, trigger.hour)
        assertEquals(30, trigger.minute)
    }

    @Test
    fun aTimeZoneChangeMovesTheInstantToTheNewLocalTime() {
        val instant = at(tehran, 2026, 10, 12, 9, 0).toInstant()
        val inTehran = ReminderTime.nextTrigger(instant.atZone(tehran), nine)
        val inNewYork = ReminderTime.nextTrigger(instant.atZone(newYork), nine)
        assertEquals(21, inNewYork.hour)
        assertEquals(newYork, inNewYork.zone)
        // Same wall time, different instants: the alarm must be re-armed on a zone change.
        assertNotEquals(inTehran.toInstant(), inNewYork.toInstant())
    }

    @Test
    fun nextMidnightIsTheStartOfTomorrowLocally() {
        assertEquals(
            at(tehran, 2026, 10, 13, 0, 0),
            ReminderTime.nextMidnight(at(tehran, 2026, 10, 12, 23, 59)),
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun aMinuteOutsideTheDayIsRefused() {
        ReminderTime.nextTrigger(at(tehran, 2026, 10, 12, 9, 0), 1440)
    }
}
```

- [ ] **Step 4: RED (Kotlin)**

Run from `app/android/`: `./gradlew :app:testDebugUnitTest --tests "com.nimbustats.app.notifications.ReminderTimeTest"`. Expected: a compilation failure, `Unresolved reference: ReminderTime`.

On Windows, if `./gradlew` fails under Git Bash, run `./gradlew.bat` from PowerShell with the same arguments.

- [ ] **Step 5: Write the failing Dart tests**

Create `app/test/features/notifications/reminder_controller_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/provider_retry.dart';
import 'package:nimbustats/features/notifications/application/reminder_controller.dart';
import 'package:nimbustats/features/notifications/data/notification_prefs.dart';
import 'package:nimbustats/features/notifications/data/outside_channel.dart';
import 'package:nimbustats/l10n/app_localizations.dart';

import 'support/fake_outside_channel.dart';

void main() {
  late AppDatabase db;
  late FakeOutsideChannel outside;
  late ReminderController reminder;
  late NotificationPrefsRepository prefs;
  final en = lookupAppLocalizations(const Locale('en'));

  setUp(() {
    db = AppDatabase.openInMemory();
    outside = FakeOutsideChannel();
    prefs = NotificationPrefsRepository(db.settingsDao);
    final c = ProviderContainer(retry: nimbusNoRetry, overrides: [
      appDatabaseProvider.overrideWithValue(db),
      outsideChannelProvider.overrideWithValue(outside),
    ]);
    addTearDown(c.dispose);
    reminder = c.read(reminderControllerProvider);
  });
  tearDown(() => db.close());

  test('switching on asks, then saves and arms at 21:00 with the text and '
      'the add route', () async {
    expect(await reminder.enable(en), isTrue);

    expect(outside.permissionRequests, 1);
    expect((await prefs.load()).reminderEnabled, isTrue);
    expect(outside.reminders.single, (
      enabled: true,
      minuteOfDay: 1260,
      text: 'Anything to log today?',
      route: '/add',
    ));
  });

  test('a denied permission leaves it off and arms nothing', () async {
    outside
      ..grant = false
      ..enabled = false;
    expect(await reminder.enable(en), isFalse);

    expect((await prefs.load()).reminderEnabled, isFalse);
    expect(outside.reminders.where((r) => r.enabled), isEmpty);
  });

  test('a new time is saved, and re-armed only while the reminder is on',
      () async {
    await reminder.setTime(en, 450);
    expect((await prefs.load()).reminderMinuteOfDay, 450);
    expect(outside.reminders, isEmpty, reason: 'off: nothing to arm');

    await reminder.enable(en);
    await reminder.setTime(en, 480);
    expect(outside.reminders.last.minuteOfDay, 480);
    expect(outside.reminders.last.enabled, isTrue);
  });

  test('switching off saves it and cancels the alarm', () async {
    await reminder.enable(en);
    await reminder.disable(en);

    expect((await prefs.load()).reminderEnabled, isFalse);
    expect(outside.reminders.last.enabled, isFalse);
  });

  test('push hands native the stored config, worded in the given language',
      () async {
    await prefs.setReminder(enabled: true, minuteOfDay: 1200);
    await reminder.push(lookupAppLocalizations(const Locale('fa')));

    expect(outside.reminders.single.minuteOfDay, 1200);
    expect(outside.reminders.single.text, 'امروز چیزی برای ثبت دارید؟');
  });
}
```

Append inside `main()` of `app/test/features/notifications/notifications_bridge_test.dart`, and add `import 'package:nimbustats/features/notifications/data/notification_prefs.dart';`:

```dart
  testWidgets('an armed reminder is re-pushed in the new language after a '
      'switch (Review Focus 5)', (tester) async {
    await NotificationPrefsRepository(db.settingsDao)
        .setReminder(enabled: true, minuteOfDay: 1260);
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        outside: outside,
        initialLocation: '/settings',
        locale: null);
    expect(outside.reminders.last.text, 'امروز چیزی برای ثبت دارید؟');

    await tester.tap(find.byKey(const Key('settings-locale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('locale-en')));
    await tester.pumpAndSettle();

    expect(outside.reminders.last, (
      enabled: true,
      minuteOfDay: 1260,
      text: 'Anything to log today?',
      route: '/add',
    ));
  });
```

- [ ] **Step 6: RED (Dart)**

Run from `app/`: `flutter test --no-pub test/features/notifications/reminder_controller_test.dart test/features/notifications/notifications_bridge_test.dart`. Expected: compile errors, because `reminder_controller.dart` does not exist.

- [ ] **Step 7: Tag**

```bash
git tag pre-daily-reminder phase/6-outside-the-app
```

- [ ] **Step 8: `ReminderTime`**

Create `app/android/app/src/main/kotlin/com/nimbustats/app/notifications/ReminderTime.kt`:

```kotlin
package com.nimbustats.app.notifications

import java.time.LocalTime
import java.time.ZonedDateTime

/**
 * When the daily reminder and the widget's midnight refresh fire next (spec §5, §6.3).
 *
 * Computed from the local wall clock every time, never as a fixed 24 hours, so daylight saving
 * and time-zone changes stay correct where `setInexactRepeating` drifts. A wall time inside a
 * DST gap or overlap resolves the way `java.time` resolves it: later by the gap, or the earlier
 * offset. Pure: no Android, so JUnit covers it on the host.
 */
object ReminderTime {
    /** The next local occurrence of [minuteOfDay] strictly after [now], in [now]'s zone. */
    fun nextTrigger(now: ZonedDateTime, minuteOfDay: Int): ZonedDateTime {
        require(minuteOfDay in 0 until 24 * 60) { "minuteOfDay $minuteOfDay is outside the day" }
        val time = LocalTime.of(minuteOfDay / 60, minuteOfDay % 60)
        val today = ZonedDateTime.of(now.toLocalDate(), time, now.zone)
        return if (today.isAfter(now)) today else ZonedDateTime.of(now.toLocalDate().plusDays(1), time, now.zone)
    }

    /** The start of tomorrow, locally. */
    fun nextMidnight(now: ZonedDateTime): ZonedDateTime = now.toLocalDate().plusDays(1).atStartOfDay(now.zone)
}
```

Run: `./gradlew :app:testDebugUnitTest --tests "com.nimbustats.app.notifications.ReminderTimeTest"`. Expected: `BUILD SUCCESSFUL`. Seven tests pass. The first run downloads JUnit and Hamcrest.

- [ ] **Step 9: Scheduler, receivers, notifier, manifest, handler**

Create `app/android/app/src/main/kotlin/com/nimbustats/app/notifications/ReminderScheduler.kt`:

```kotlin
package com.nimbustats.app.notifications

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.time.ZonedDateTime

/**
 * Arms the daily reminder (spec §5).
 *
 * It keeps Dart's last config in SharedPreferences, so [RearmReceiver] can re-arm after a reboot
 * or a zone change without starting Flutter. The alarm is `setAndAllowWhileIdle(RTC_WAKEUP)`:
 * inexact, delivered in Doze, needing no exact-alarm permission. It is one-shot, and each firing
 * arms the next.
 */
object ReminderScheduler {
    private const val PREFS = "nimbus_reminder"
    private const val ENABLED = "enabled"
    private const val MINUTE = "minuteOfDay"
    private const val TEXT = "text"
    private const val ROUTE = "route"

    fun configure(context: Context, enabled: Boolean, minuteOfDay: Int, text: String, route: String) {
        require(minuteOfDay in 0 until 24 * 60) { "minuteOfDay $minuteOfDay is outside the day" }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(ENABLED, enabled)
            .putInt(MINUTE, minuteOfDay)
            .putString(TEXT, text)
            .putString(ROUTE, route)
            .apply()
        armReminder(context)
    }

    /** Everything this app keeps armed, re-armed from the local clock now. */
    fun rearm(context: Context) {
        armReminder(context)
    }

    fun armReminder(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val intent = reminderIntent(context)
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(ENABLED, false)) {
            alarms.cancel(intent)
            return
        }
        val at = ReminderTime.nextTrigger(ZonedDateTime.now(), prefs.getInt(MINUTE, 21 * 60))
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.toInstant().toEpochMilli(), intent)
    }

    /** The stored text and route, or null when Dart never configured the reminder. */
    fun content(context: Context): Pair<String, String>? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val text = prefs.getString(TEXT, null) ?: return null
        val route = prefs.getString(ROUTE, null) ?: return null
        return text to route
    }

    private fun reminderIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, ReminderReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}
```

Create `app/android/app/src/main/kotlin/com/nimbustats/app/notifications/ReminderReceiver.kt`:

```kotlin
package com.nimbustats.app.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG

/** The reminder's alarm: posts it, then arms tomorrow's from the local clock (spec §5). */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val content = ReminderScheduler.content(context)
        if (content == null) {
            Log.e(TAG, "reminder fired with no text stored; nothing posted")
        } else {
            Notifier.postReminder(context, content.first, content.second)
        }
        ReminderScheduler.armReminder(context)
    }
}
```

Create `app/android/app/src/main/kotlin/com/nimbustats/app/notifications/RearmReceiver.kt`:

```kotlin
package com.nimbustats.app.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-arms after the events that silently clear or move an alarm: a reboot, a time-zone change, a
 * clock change, a locale change and an app update (spec §5). Each is a protected broadcast only
 * the system sends, and each is on Android's implicit-broadcast exemption list.
 */
class RearmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReminderScheduler.rearm(context)
    }
}
```

In `Notifier.kt`, add:

```kotlin
    /** The daily reminder (spec §5). A tap opens [route]: the add-expense screen. */
    fun postReminder(context: Context, text: String, route: String) {
        if (!canPost(context, REMINDER, "reminder")) return
        val notification = Notification.Builder(context, REMINDER)
            .setSmallIcon(R.drawable.ic_stat_nimbus)
            .setContentText(text)
            .setContentIntent(routeIntent(context, route, "reminder"))
            .setAutoCancel(true)
            .build()
        context.getSystemService(NotificationManager::class.java).notify("reminder", 1, notification)
    }
```

In `OutsideChannelHandler.kt`, add this arm before `"takeLaunchRoute"`. Also add the import `com.nimbustats.app.notifications.ReminderScheduler`:

```kotlin
                "setReminder" -> {
                    ReminderScheduler.configure(
                        context,
                        call.argument<Boolean>("enabled") ?: throw IllegalArgumentException("missing enabled"),
                        call.argument<Int>("minuteOfDay") ?: throw IllegalArgumentException("missing minuteOfDay"),
                        call.string("text"),
                        call.string("route"),
                    )
                    result.success(null)
                }
```

In `AndroidManifest.xml`:
1. Under the `POST_NOTIFICATIONS` line, add:

```xml
    <!-- Re-arms the reminder (and, from Task 16, the widget's midnight
         refresh) after a reboot. No exact-alarm permission: the reminder is
         inexact on purpose. -->
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

2. Inside `<application>`, after the `</activity>` of `MainActivity`, add:

```xml
        <receiver
            android:name=".notifications.ReminderReceiver"
            android:exported="false" />
        <!-- Exported only to hear these system broadcasts, which other apps
             cannot send. -->
        <receiver
            android:name=".notifications.RearmReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.TIMEZONE_CHANGED" />
                <action android:name="android.intent.action.TIME_SET" />
                <action android:name="android.intent.action.LOCALE_CHANGED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            </intent-filter>
        </receiver>
```

- [ ] **Step 10: The string, the controller, the bridge's re-push**

In both ARB files, insert in alphabetical position, after `notificationsReminderChannelName`:
- `app_en.arb`: `"notificationsReminderText": "Anything to log today?",`
- `app_fa.arb`: `"notificationsReminderText": "امروز چیزی برای ثبت دارید؟",`

Then run from `app/`: `flutter gen-l10n`.

Create `app/lib/features/notifications/application/reminder_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../transactions/routes.dart';
import '../data/notification_prefs.dart';
import '../data/outside_channel.dart';
import 'notification_providers.dart';
import 'permission_request.dart';

/// The daily reminder's switch and time (spec §5, §8).
///
/// The database is the source of truth, and native keeps a copy so its
/// receivers can re-arm without Dart. Every change saves first, then pushes
/// that copy. [push] re-sends it at start and after a language switch, so
/// the text is always in the app's language.
final class ReminderController {
  ReminderController(this._ref);

  final Ref _ref;

  NotificationPrefsRepository get _prefs =>
      _ref.read(notificationPrefsRepositoryProvider);

  /// Asks for the permission in context. If granted, it saves the reminder
  /// as on and arms it. If denied, it leaves it off. Returns whether it is
  /// on.
  Future<bool> enable(AppLocalizations l10n) async {
    final granted = await askForNotifications(
        _ref.read(outsideChannelProvider),
        library: 'reminder');
    if (!granted) return false;
    final minute = (await _prefs.load()).reminderMinuteOfDay;
    await _prefs.setReminder(enabled: true, minuteOfDay: minute);
    await _send(l10n, enabled: true, minuteOfDay: minute);
    return true;
  }

  Future<void> disable(AppLocalizations l10n) async {
    final minute = (await _prefs.load()).reminderMinuteOfDay;
    await _prefs.setReminder(enabled: false, minuteOfDay: minute);
    await _send(l10n, enabled: false, minuteOfDay: minute);
  }

  Future<void> setTime(AppLocalizations l10n, int minuteOfDay) async {
    final enabled = (await _prefs.load()).reminderEnabled;
    await _prefs.setReminder(enabled: enabled, minuteOfDay: minuteOfDay);
    if (enabled) await _send(l10n, enabled: true, minuteOfDay: minuteOfDay);
  }

  Future<void> push(AppLocalizations l10n) async {
    final prefs = await _prefs.load();
    await _send(l10n,
        enabled: prefs.reminderEnabled,
        minuteOfDay: prefs.reminderMinuteOfDay);
  }

  Future<void> _send(
    AppLocalizations l10n, {
    required bool enabled,
    required int minuteOfDay,
  }) =>
      _ref.read(outsideChannelProvider).setReminder(
            enabled: enabled,
            minuteOfDay: minuteOfDay,
            text: l10n.notificationsReminderText,
            route: addTransactionRoute,
          );
}

final reminderControllerProvider =
    Provider<ReminderController>(ReminderController.new);
```

In `notifications_bridge.dart`:
1. Add `import '../application/reminder_controller.dart';`.
2. In `didChangeDependencies`, after the `registerChannels` call, add:

```dart
    // The reminder's text is in the app's language, and native keeps a
    // copy: re-send it at start and after a switch.
    unawaited(reportingFailure('reminder', 'while pushing the reminder',
        () => ref.read(reminderControllerProvider).push(l10n)));
```

3. Extend the class doc comment's list with `/// - re-sends the reminder's config, worded in the app's language.`

- [ ] **Step 11: GREEN**

Run from `app/android/`: `./gradlew :app:testDebugUnitTest`. Expected: `BUILD SUCCESSFUL`.

Run from `app/`: `flutter test --no-pub test/features/notifications/`. Expected: all pass.

- [ ] **Step 12: Build and the broader suite**

Run, from `app/`: `flutter build apk --debug`, then `flutter test --no-pub --concurrency=4 --timeout 90s`. From the repo root: `dart analyze --fatal-infos`. Expected: green.

- [ ] **Step 13: Commit and fast-forward**

```bash
git add app/android app/lib app/test
git commit -m "$(cat <<'EOF'
feat(notifications): the daily reminder, re-armed after reboot and zone change

An inexact setAndAllowWhileIdle alarm, one-shot and re-armed from the
local wall clock on every firing, so DST and zone changes land on the
new local time where a repeating alarm would drift. RearmReceiver
re-arms after boot, time-zone and time changes, locale change and app
update; the config lives in SharedPreferences so no Flutter engine is
needed for that. No exact-alarm permission is requested.

ReminderController asks for the permission when the reminder is
switched on, saves, then pushes the config; the shell re-pushes it at
start and after a language switch so the text follows the app.

Adds JUnit 4.13.2 as a test-only Gradle dependency (spec §10); Maven
Central probed before adding. ReminderTime is JUnit-tested; the
receivers are built here and verified on device in Task 17.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/daily-reminder
```

---

### Task 10: The settings section — reminder, time, details, the blocked row

Slug: `notifications-settings`. Spec §8, Review Focus 4.

**Files:**
- Create: `app/lib/features/notifications/presentation/notifications_section.dart`
- Modify: `app/lib/features/settings/presentation/settings_screen.dart` (one line plus an import)
- Modify: ARB files
- Test: `app/test/features/notifications/notifications_section_test.dart`

**Interfaces:**
- Consumes:
  - `notificationPrefsProvider`, `notificationPrefsRepositoryProvider` (Task 7) and `reminderControllerProvider` (Task 9).
  - `outsideChannelProvider` and `reportingFailure` (Task 4).
  - `moneyFormatterProvider`, for the digit style.
- Produces: `class NotificationsSection extends ConsumerStatefulWidget`, with the keys:
  - `notifications-section`, `notifications-reminder`, `notifications-reminder-time`, `notifications-details`, `notifications-blocked`, `notifications-open-settings`
  - `notifications-loading` and `notifications-error`

- [ ] **Step 1: Branch**

```bash
git checkout -b feat/notifications-settings phase/6-outside-the-app
```

- [ ] **Step 2: Write the failing tests**

Create `app/test/features/notifications/notifications_section_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbustats/features/notifications/application/notification_providers.dart';
import 'package:nimbustats/features/notifications/data/notification_prefs.dart';
import 'package:nimbustats/features/settings/data/settings_keys.dart';

import '../../support/harness.dart';
import 'support/fake_outside_channel.dart';

void main() {
  late AppDatabase db;
  late FakeOutsideChannel outside;

  setUp(() {
    db = AppDatabase.openInMemory();
    outside = FakeOutsideChannel();
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester,
      {Locale locale = const Locale('en'), List<Override> overrides = const []}) async {
    // Digits follow the *settings* locale (AppSettings.persianDigits), whose
    // default is fa. An English test saves English so its times read 21:00.
    if (locale.languageCode == 'en') await useEnglishDigits(db);
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        outside: outside,
        initialLocation: '/settings',
        locale: locale,
        overrides: overrides);
    await tester.scrollUntilVisible(
        find.byKey(const Key('notifications-section')), 200);
    await tester.pumpAndSettle();
  }

  bool switchOn(WidgetTester tester, String key) =>
      tester.widget<SwitchListTile>(find.byKey(Key(key))).value;

  testWidgets('switching the reminder on asks, saves and arms; the time shows',
      (tester) async {
    await open(tester);
    expect(find.byKey(const Key('notifications-reminder-time')), findsNothing);

    await tester.tap(find.byKey(const Key('notifications-reminder')));
    await tester.pumpAndSettle();

    expect(outside.permissionRequests, 1);
    expect(await db.settingsDao.get(SettingsKeys.reminderEnabled), 'true');
    expect(outside.reminders.last.enabled, isTrue);
    expect(switchOn(tester, 'notifications-reminder'), isTrue);
    expect(find.text('21:00'), findsOneWidget);
  });

  testWidgets('a denied permission leaves it off and shows the blocked row; '
      '"Open settings" opens Android\'s', (tester) async {
    outside
      ..grant = false
      ..enabled = false;
    await open(tester);

    await tester.tap(find.byKey(const Key('notifications-reminder')));
    await tester.pumpAndSettle();

    expect(switchOn(tester, 'notifications-reminder'), isFalse);
    expect(outside.reminders.where((r) => r.enabled), isEmpty);
    expect(find.byKey(const Key('notifications-blocked')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notifications-open-settings')));
    await tester.pumpAndSettle();
    expect(outside.settingsOpened, 1);
  });

  testWidgets('a reminder left on while notifications are blocked shows the '
      'row', (tester) async {
    await NotificationPrefsRepository(db.settingsDao)
        .setReminder(enabled: true, minuteOfDay: 1260);
    outside.enabled = false;
    await open(tester);

    expect(find.byKey(const Key('notifications-blocked')), findsOneWidget);
  });

  testWidgets('a new time is saved and re-armed', (tester) async {
    await NotificationPrefsRepository(db.settingsDao)
        .setReminder(enabled: true, minuteOfDay: 1260);
    await open(tester);

    await tester.tap(find.byKey(const Key('notifications-reminder-time')));
    await tester.pumpAndSettle();
    // The picker's text-input mode: two fields, hour then minute.
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '07');
    await tester.enterText(find.byType(TextField).at(1), '30');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(await db.settingsDao.get(SettingsKeys.reminderMinuteOfDay), '450');
    expect(outside.reminders.last.minuteOfDay, 450);
    expect(find.text('07:30'), findsOneWidget);
  });

  testWidgets('the details switch persists', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('notifications-details')));
    await tester.pumpAndSettle();

    expect(await db.settingsDao.get(SettingsKeys.notificationDetail), 'true');
    expect(switchOn(tester, 'notifications-details'), isTrue);
  });

  testWidgets('loading, then error with a retry', (tester) async {
    final never = StreamController<NotificationPrefs>();
    addTearDown(never.close);
    await open(tester, overrides: [
      notificationPrefsProvider.overrideWith((ref) => never.stream),
    ]);
    expect(find.byKey(const Key('notifications-loading')), findsOneWidget);

    never.addError(StateError('disk'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notifications-error')), findsOneWidget);
    expect(find.byType(NimbusErrorState), findsOneWidget);
  });

  testWidgets('Persian: the section reads in Persian with Persian digits',
      (tester) async {
    await NotificationPrefsRepository(db.settingsDao)
        .setReminder(enabled: true, minuteOfDay: 1260);
    await open(tester, locale: const Locale('fa'));

    expect(find.text('اعلان‌ها'), findsOneWidget);
    expect(find.text('۲۱:۰۰'), findsOneWidget);
  });

  testWidgets('every control is a 48 dp target', (tester) async {
    await NotificationPrefsRepository(db.settingsDao)
        .setReminder(enabled: true, minuteOfDay: 1260);
    outside.enabled = false;
    await open(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });
}
```

Add two imports:
- `import 'package:flutter_riverpod/misc.dart';`, where Riverpod 3 keeps `Override`.
- `import '../trackers/support/tracker_fixture.dart';`, for `useEnglishDigits`.

`AppSettings.persianDigits` is `locale.languageCode == 'fa'` (`app_settings.dart:59`), and the settings default is `fa`. So the Persian test needs no save to read `۲۱:۰۰`, while `open` saves English for the English tests.

- [ ] **Step 3: RED**

Run from `app/`: `flutter test --no-pub test/features/notifications/notifications_section_test.dart`. Expected: `notifications-section` is never found, so `scrollUntilVisible` fails.

- [ ] **Step 4: Tag**

```bash
git tag pre-notifications-settings phase/6-outside-the-app
```

- [ ] **Step 5: The strings**

In `app_en.arb`, insert in alphabetical position among the `notifications…` keys:

```json
  "notificationsBlocked": "Notifications are blocked",
  "notificationsLoadFailed": "Notification settings could not be read",
  "notificationsOpenSettings": "Open settings",
  "notificationsSettingsDetails": "Show details in notifications",
  "notificationsSettingsDetailsHint": "Goal names and amounts. The lock screen stays discreet.",
  "notificationsSettingsReminder": "Daily reminder",
  "notificationsSettingsReminderTime": "Reminder time",
  "notificationsSettingsTitle": "Notifications",
```

In `app_fa.arb`, at the same positions:

```json
  "notificationsBlocked": "اعلان‌ها مسدود است",
  "notificationsLoadFailed": "تنظیمات اعلان خوانده نشد",
  "notificationsOpenSettings": "باز کردن تنظیمات",
  "notificationsSettingsDetails": "نمایش جزئیات در اعلان‌ها",
  "notificationsSettingsDetailsHint": "نام و مبلغ هدف‌ها. صفحهٔ قفل بدون جزئیات می‌ماند.",
  "notificationsSettingsReminder": "یادآور روزانه",
  "notificationsSettingsReminderTime": "ساعت یادآور",
  "notificationsSettingsTitle": "اعلان‌ها",
```

`notificationsSettingsReminder` and `notificationsReminderChannelName` share a value in both languages. That is allowed: `localization_test` compares en with fa per key, not keys with each other.

Run from `app/`: `flutter gen-l10n`.

- [ ] **Step 6: The section**

Create `app/lib/features/notifications/presentation/notifications_section.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_design/nimbus_design.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/application/settings_providers.dart';
import '../application/notification_providers.dart';
import '../application/outside_errors.dart';
import '../application/reminder_controller.dart';
import '../data/notification_prefs.dart';
import '../data/outside_channel.dart';

/// The settings screen's "Notifications" section (spec §8): the daily
/// reminder and its time, the detail switch, and a row that says when
/// Android is blocking notifications.
///
/// States: loading (the keys not read yet), error (the read failed),
/// populated. There is no empty state.
class NotificationsSection extends ConsumerStatefulWidget {
  const NotificationsSection({super.key});

  @override
  ConsumerState<NotificationsSection> createState() =>
      _NotificationsSectionState();
}

class _NotificationsSectionState extends ConsumerState<NotificationsSection> {
  late final OutsideChannel _channel;
  late final AppLifecycleListener _lifecycle;

  /// Whether Android lets the app post; null until first asked.
  bool? _enabled;

  /// A denial just now: the row shows even though the reminder stayed off.
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _channel = ref.read(outsideChannelProvider);
    // Re-checked on resume: the user may have just come back from Android's
    // notification settings.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_recheck()));
    unawaited(_recheck());
  }

  Future<void> _recheck() async {
    final enabled = await reportingFailure('reminder',
        'while checking whether notifications are enabled',
        _channel.notificationsEnabled);
    if (!mounted || enabled == null) return;
    setState(() {
      _enabled = enabled;
      if (enabled) _denied = false;
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Runs one change. A failure is reported under `reminder` and the user is
  /// told, as the rest of the settings screen does. Returns null on failure.
  Future<T?> _change<T>(String what, Future<T> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).settingsSaveFailed;
    try {
      return await action();
    } on Object catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'reminder',
        context: ErrorDescription(what),
      ));
      messenger.showSnackBar(SnackBar(content: Text(failed)));
      return null;
    }
  }

  Future<void> _toggleReminder(bool on) async {
    final l10n = AppLocalizations.of(context);
    final reminder = ref.read(reminderControllerProvider);
    if (!on) {
      await _change('while switching the reminder off',
          () => reminder.disable(l10n));
      if (mounted) setState(() => _denied = false);
      return;
    }
    final enabled = await _change(
        'while switching the reminder on', () => reminder.enable(l10n));
    if (!mounted) return;
    setState(() => _denied = enabled == false);
    await _recheck();
  }

  Future<void> _pickTime(int minuteOfDay) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    await _change(
      'while setting the reminder time',
      () => ref
          .read(reminderControllerProvider)
          .setTime(l10n, picked.hour * 60 + picked.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final prefs = ref.watch(notificationPrefsProvider);

    final Widget body;
    if (prefs.hasError) {
      body = NimbusErrorState(
        key: const Key('notifications-error'),
        title: l10n.notificationsLoadFailed,
        retryLabel: l10n.commonRetry,
        detail: prefs.error.toString(),
        onRetry: () => ref.invalidate(notificationPrefsProvider),
      );
    } else if (!prefs.hasValue) {
      body = const SizedBox(
        key: Key('notifications-loading'),
        height: 3 * 72,
        child: NimbusLoadingList(rows: 3),
      );
    } else {
      body = _rows(context, l10n, prefs.requireValue);
    }

    return Column(
      key: const Key('notifications-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              NimbusTokens.space4, NimbusTokens.space4, NimbusTokens.space4, 0),
          child: Text(l10n.notificationsSettingsTitle,
              style: theme.textTheme.titleSmall),
        ),
        body,
      ],
    );
  }

  Widget _rows(
      BuildContext context, AppLocalizations l10n, NotificationPrefs prefs) {
    final persian = ref.watch(moneyFormatterProvider).persianDigits;
    final time = _time(prefs.reminderMinuteOfDay, persian: persian);
    final blocked =
        _denied || (prefs.reminderEnabled && _enabled == false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('notifications-reminder'),
          title: Text(l10n.notificationsSettingsReminder),
          value: prefs.reminderEnabled,
          onChanged: (on) => unawaited(_toggleReminder(on)),
        ),
        if (prefs.reminderEnabled)
          ListTile(
            key: const Key('notifications-reminder-time'),
            title: Text(l10n.notificationsSettingsReminderTime),
            trailing: Text(time),
            onTap: () => unawaited(_pickTime(prefs.reminderMinuteOfDay)),
          ),
        SwitchListTile(
          key: const Key('notifications-details'),
          title: Text(l10n.notificationsSettingsDetails),
          subtitle: Text(l10n.notificationsSettingsDetailsHint),
          value: prefs.showDetails,
          onChanged: (on) => unawaited(_change(
              'while saving the detail setting',
              () => ref
                  .read(notificationPrefsRepositoryProvider)
                  .setShowDetails(on))),
        ),
        if (blocked)
          ListTile(
            key: const Key('notifications-blocked'),
            leading: const Icon(Icons.notifications_off_outlined),
            title: Text(l10n.notificationsBlocked),
            trailing: TextButton(
              key: const Key('notifications-open-settings'),
              onPressed: () => unawaited(reportingFailure('reminder',
                  'while opening notification settings',
                  _channel.openNotificationSettings)),
              child: Text(l10n.notificationsOpenSettings),
            ),
          ),
      ],
    );
  }

  /// 24-hour, in the settings' digits (spec §8).
  static String _time(int minuteOfDay, {required bool persian}) {
    String two(int v) => v.toString().padLeft(2, '0');
    final latin = '${two(minuteOfDay ~/ 60)}:${two(minuteOfDay % 60)}';
    return persian ? Digits.toPersian(latin) : latin;
  }
}
```

In `app/lib/features/settings/presentation/settings_screen.dart`:
1. Add `import '../../notifications/presentation/notifications_section.dart';`.
2. In `_Body.build`'s `ListView` children, directly after the theme `_ChoiceTile<ThemeMode>(…)`, insert:

```dart
        // Phase 6 (additive): the reminder, its time and notification detail.
        const Divider(),
        const NotificationsSection(),
```

- [ ] **Step 7: GREEN**

Run: `flutter test --no-pub test/features/notifications/notifications_section_test.dart test/features/settings/`. Expected: all pass. If the time picker's input-mode icon differs in Flutter 3.47.1, find it with `find.byTooltip('Switch to text input mode')` instead. Do not drop the test.

- [ ] **Step 8: Broader suite**

Run, from the repo root: `dart analyze --fatal-infos`. From `app/`: `flutter test --no-pub --concurrency=4 --timeout 90s`. `ux_rules_test` checks that presentation calls no DAO directly, and that there is no `showDialog`. `showTimePicker` is allowed. Expected: green.

- [ ] **Step 9: Commit and fast-forward**

```bash
git add app/lib app/test/features/notifications/notifications_section_test.dart
git commit -m "$(cat <<'EOF'
feat(settings): a Notifications section for the reminder and details

The reminder switch asks for the permission in context and stays off
on a denial, showing a "Notifications are blocked · Open settings" row
that is re-checked on resume; the time is a 24-hour picker in the
settings' digits; "Show details in notifications" turns goal names and
amounts on (the lock screen stays discreet). Loading, error and
populated states; fa and en.

An additive line in Phase 1's settings screen.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/notifications-settings
```

---
### Task 11: The widget snapshot — built in Dart, pushed on every relevant change

Slug: `widget-snapshot`. Spec §6.1.

**Files:**
- Modify: `packages/nimbus_data/lib/src/trackers/trackers_dao.dart` (one-shot `allLive`)
- Modify: `app/lib/features/transactions/application/prediction_providers.dart` (extract `loadCategoryPredictor`)
- Create: `app/lib/features/widget/application/snapshot_writer.dart`
- Create: `app/lib/features/widget/presentation/widget_sync.dart`
- Modify: `app/lib/bootstrap/app_shell.dart` (wrap in `WidgetSync`)
- Modify: ARB files (`widget…` keys)
- Test: `app/test/features/widget/snapshot_writer_test.dart`, `app/test/features/widget/widget_sync_test.dart`

**Interfaces:**
- Consumes:
  - `outsideChannelProvider` and `reportingFailure` (Task 4).
  - `trackerClockProvider`, `trackersProvider`, `analyticsEngineProvider` and `settingsProvider`.
- Produces:
  - `Future<List<Tracker>> TrackersDao.allLive({required bool archived})`.
  - `Future<CategoryPredictor> loadCategoryPredictor(AppDatabase db)`.
  - `final class SnapshotWriter`, with `const SnapshotWriter(AppDatabase db, TrackerClock clock)`, `Future<String> build()`, and the constants `version = 1`, `maxTrackers = 4` and `maxChips = 4`.
  - `snapshotWriterProvider`.
  - `class WidgetSync extends ConsumerStatefulWidget`. Task 13 adds the drain triggers.

- [ ] **Step 1: Branch**

```bash
git checkout -b feat/widget-snapshot phase/6-outside-the-app
```

- [ ] **Step 2: Write the failing tests**

Create `app/test/features/widget/snapshot_writer_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_draft.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/widget/application/snapshot_writer.dart';

import '../goals/support/goal_test_app.dart';
import '../trackers/support/tracker_fixture.dart';

void main() {
  late AppDatabase db;
  late FakeClock fake;
  late TrackerRepository trackers;

  const day5 = DateKey(20261005);

  setUp(() async {
    db = AppDatabase.openInMemory();
    fake = FakeClock(); // 2026-10-05, 12:30 in Tehran
    trackers = repositoryFor(db, fake);
    await seedCategories(db);
  });
  tearDown(() => db.close());

  Future<Map<String, Object?>> snapshot() async =>
      jsonDecode(await SnapshotWriter(db, fake.clock).build())
          as Map<String, Object?>;

  List<Map<String, Object?>> rows(Map<String, Object?> s, String key) =>
      (s[key]! as List<Object?>).cast<Map<String, Object?>>();

  test('trackers: tab order, no duration, none archived, at most four, with '
      "today's totals", () async {
    final cig = await trackers.create(cigarettes);
    final gymTracker = await trackers.create(gym);
    final waterTracker = await trackers.create(water);
    await trackers.create(sleep); // duration: a timer cannot run from a widget
    final old = await trackers.create(const TrackerDraft(
        name: 'Old', iconKey: 'tag', color: 1, type: TrackerType.counter));
    await trackers.archive(old.id);
    final coffee = await trackers.create(const TrackerDraft(
        name: 'Coffee', iconKey: 'tag', color: 2, type: TrackerType.counter));
    await trackers.create(const TrackerDraft(
        name: 'Tea', iconKey: 'tag', color: 3, type: TrackerType.counter));

    for (var i = 0; i < 3; i++) {
      await trackers.logEntry(cig.id);
    }
    await trackers.logEntry(cig.id,
        at: DateTime.utc(2026, 10, 4, 12)); // yesterday: not today's
    await trackers.logEntry(gymTracker.id);
    await trackers.logEntry(waterTracker.id);
    await trackers.logEntry(waterTracker.id);

    final s = await snapshot();
    expect([for (final t in rows(s, 'trackers')) t['name']],
        ['Cigarettes', 'Gym', 'Water', 'Coffee']);
    final byName = {for (final t in rows(s, 'trackers')) t['name']: t};
    expect(byName['Cigarettes'], {
      'id': cig.id,
      'name': 'Cigarettes',
      'color': 0xFF546E7A,
      'type': 'counter',
      'perTap': 1.0,
      'unit': null,
      'todayTotal': 3.0,
    });
    expect(byName['Gym']!['todayTotal'], 1.0);
    expect(byName['Water']!['perTap'], 0.25);
    expect(byName['Water']!['unit'], 'L');
    expect(byName['Water']!['todayTotal'], 0.5);
    expect(byName['Coffee']!['id'], coffee.id);
    expect(byName['Coffee']!['todayTotal'], 0.0);
  });

  test('chips: up to four predicted categories, never Uncategorized',
      () async {
    await spend(db, 1000, day5); // Dining
    await spend(db, 1000, day5, category: 'seed-transport');

    final chips = rows(await snapshot(), 'chips');
    expect(chips.length, lessThanOrEqualTo(4));
    expect(chips, contains({'id': 'seed-dining', 'name': 'Dining'}));
    expect(chips.map((c) => c['id']),
        isNot(contains(SystemCategoryIds.uncategorized)));
  });

  test('the day, the language, the direction and the currency', () async {
    final s = await snapshot();
    expect(s['v'], 1);
    expect(s['dayKey'], 20261005);
    expect(s['localeTag'], 'fa'); // the settings default
    expect(s['rtl'], isTrue);
    expect(s['currency'], {
      'code': 'IRT',
      'decimalDigits': 0,
      'label': 'تومان',
    });
    expect(rows(s, 'trackers'), isEmpty);

    await useEnglishDigits(db); // settings locale: en
    final en = await snapshot();
    expect(en['localeTag'], 'en');
    expect(en['rtl'], isFalse);
    expect((en['currency']! as Map)['label'], 'Toman');
  });

  test('strings are in the app language, templates keep their slots',
      () async {
    final fa = (await snapshot())['strings']! as Map<String, Object?>;
    expect(fa['trackerAdd'], '{name}، امروز {total}. افزودن یکی');
    expect(fa['trackerDone'], '{name}، امروز انجام شد');

    await useEnglishDigits(db);
    final en = (await snapshot())['strings']! as Map<String, Object?>;
    expect(en, {
      'addExpense': '+ Expense',
      'emptyTrackers': 'Add a tracker in the app to log it from here',
      'entryTitle': 'Add expense',
      'save': 'Save',
      'cancel': 'Cancel',
      'saved': 'Saved',
      'trackerAdd': '{name}, today {total}. Add one',
      'trackerDone': '{name}, done today',
    });
  });

  test('a corrupt setting builds with the defaults, as every screen does',
      () async {
    await db.settingsDao.put(SettingsKeys.themeMode, 'chartreuse');
    final s = await snapshot();
    expect(s['localeTag'], 'fa');
    expect((s['currency']! as Map)['code'], 'IRT');
  });
}
```

Add `import 'package:nimbustats/features/settings/data/settings_keys.dart';` to this test.

Create `app/test/features/widget/widget_sync_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbustats/features/trackers/routes.dart';

import '../../support/harness.dart';
import '../notifications/support/fake_outside_channel.dart';
import '../trackers/support/tracker_fixture.dart';

void main() {
  late AppDatabase db;
  late FakeOutsideChannel outside;
  late FakeClock fake;

  setUp(() {
    db = AppDatabase.openInMemory();
    outside = FakeOutsideChannel();
    fake = FakeClock();
  });
  tearDown(() => db.close());

  Map<String, Object?> last() =>
      jsonDecode(outside.snapshots.last) as Map<String, Object?>;

  /// Longer than the 300 ms debounce, and lets the write finish.
  Future<void> settleSnapshot(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  testWidgets('a snapshot is written after start-up', (tester) async {
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);
    await settleSnapshot(tester);

    expect(outside.snapshots, isNotEmpty);
    expect(last()['v'], 1);
  });

  testWidgets("a tracker tap in the app rewrites it with today's new total",
      (tester) async {
    final cig = await repositoryFor(db, fake).create(cigarettes);
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        outside: outside,
        initialLocation: trackersRoute,
        overrides: trackerOverrides(fake));
    await settleSnapshot(tester);

    await tester.tap(find.byKey(Key('tracker-action-${cig.id}')));
    await tester.pumpAndSettle();
    await settleSnapshot(tester);

    final row = (last()['trackers']! as List<Object?>).single as Map;
    expect(row['todayTotal'], 1.0);
  });

  testWidgets('a language switch rewrites it in the new language',
      (tester) async {
    await pumpApp(tester,
        database: db,
        seedFirstRun: true,
        outside: outside,
        initialLocation: '/settings',
        locale: null);
    await settleSnapshot(tester);
    expect(last()['localeTag'], 'fa');

    await tester.tap(find.byKey(const Key('settings-locale')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('locale-en')));
    await tester.pumpAndSettle();
    await settleSnapshot(tester);

    expect(last()['localeTag'], 'en');
    expect(last()['rtl'], isFalse);
  });
}
```

- [ ] **Step 3: RED**

Run from `app/`: `flutter test --no-pub test/features/widget/`. Expected: compile errors. `snapshot_writer.dart` does not exist.

- [ ] **Step 4: Tag**

```bash
git tag pre-widget-snapshot phase/6-outside-the-app
```

- [ ] **Step 5: The one-shot reads**

In `packages/nimbus_data/lib/src/trackers/trackers_dao.dart`, after `watchLive`, add:

```dart
  /// [watchLive] read once, for code that runs where no stream has emitted
  /// yet: Phase 6's widget snapshot, built in a headless engine too.
  Future<List<Tracker>> allLive({required bool archived}) async =>
      (await liveQuery(archived: archived).get()).map(_toTracker).toList();
```

In `app/lib/features/transactions/application/prediction_providers.dart`, replace the provider body with a call to a new top-level function. Keep the doc comments:

```dart
/// The predictor built from [db]'s recent history, read once. Shared by the
/// add screen's provider and Phase 6's widget snapshot, so both rank the
/// same chips.
Future<CategoryPredictor> loadCategoryPredictor(AppDatabase db) async {
  final usage = await db.transactionsDao
      .recentCategoryUsage(limit: predictionHistoryLimit);
  return MruFrequencyCategoryPredictor([
    for (final row in usage)
      CategoryObservation(
        categoryId: row.categoryId,
        occurredAt: row.occurredAt.toLocal(),
        merchant: row.merchant,
      ),
  ]);
}

final categoryPredictorProvider = FutureProvider<CategoryPredictor>(
    (ref) => loadCategoryPredictor(ref.watch(appDatabaseProvider)));
```

Add `import 'package:nimbus_data/nimbus_data.dart';` for `AppDatabase`.

- [ ] **Step 6: The strings**

`app_en.arb`. Append these keys in alphabetical position. They sort after every other key, so they go at the end of the file. The current last key is `weekday…`; check with `tail -5 app/lib/l10n/app_en.arb`. Keep the closing `}` and fix the comma on the line before:

```json
  "widgetAddExpense": "+ Expense",
  "widgetCancel": "Cancel",
  "widgetEmptyTrackers": "Add a tracker in the app to log it from here",
  "widgetEntryTitle": "Add expense",
  "widgetSave": "Save",
  "widgetSaved": "Saved",
  "widgetTrackerAdd": "{name}, today {total}. Add one",
  "@widgetTrackerAdd": {
    "placeholders": {
      "name": {
        "type": "String"
      },
      "total": {
        "type": "String"
      }
    }
  },
  "widgetTrackerDone": "{name}, done today",
  "@widgetTrackerDone": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  }
```

`app_fa.arb`, at the same position:

```json
  "widgetAddExpense": "+ هزینه",
  "widgetCancel": "انصراف",
  "widgetEmptyTrackers": "در برنامه یک عادت بسازید تا از اینجا ثبتش کنید",
  "widgetEntryTitle": "افزودن هزینه",
  "widgetSave": "ذخیره",
  "widgetSaved": "ذخیره شد",
  "widgetTrackerAdd": "{name}، امروز {total}. افزودن یکی",
  "widgetTrackerDone": "{name}، امروز انجام شد"
```

Run from `app/`: `flutter gen-l10n`.

- [ ] **Step 7: The writer**

Create `app/lib/features/widget/application/snapshot_writer.dart`:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show Bidi;
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../../bootstrap/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/data/app_settings.dart';
import '../../settings/data/settings_repository.dart';
import '../../trackers/application/tracker_providers.dart';
import '../../trackers/data/tracker_clock.dart';
import '../../transactions/application/prediction_providers.dart';

/// Builds `widget_snapshot.json` (spec §6.1): everything the home-screen
/// widget and its dialog show, in the app's language. Native displays it
/// and never composes text.
///
/// One-shot reads only, settings included. The same code runs in the app
/// engine and in the headless drain engine, where no stream has emitted yet.
final class SnapshotWriter {
  const SnapshotWriter(this._db, this._clock);

  final AppDatabase _db;
  final TrackerClock _clock;

  static const version = 1;

  /// The largest layout's rows (spec §6.4).
  static const maxTrackers = 4;
  static const maxChips = 4;

  Future<String> build() async {
    final AppSettings settings;
    try {
      settings = await SettingsRepository(_db.settingsDao).load();
    } on SettingsFormatException {
      // As every screen does while a stored setting is corrupt: the
      // defaults, while the settings screen surfaces the error and its
      // reset (settings_providers.dart). The drain, which stamps a
      // currency, stays strict instead.
      settings = AppSettings.defaults;
    }
    final l10n = lookupAppLocalizations(settings.locale);
    final today = _clock.today();
    final trackers = [
      for (final tracker in await _db.trackersDao.allLive(archived: false))
        // A timer cannot run from a widget (spec §6.1).
        if (tracker.type != TrackerType.duration) tracker,
    ].take(maxTrackers).toList();
    final totals = await _totals(trackers, today, settings.calendar);
    final language = settings.locale.languageCode;

    return jsonEncode({
      'v': version,
      // Gregorian, like every local_date_key: nothing here depends on the
      // calendar.
      'dayKey': today.value,
      'localeTag': language,
      'rtl': Bidi.isRtlLanguage(language),
      'currency': {
        'code': settings.currency.code,
        'decimalDigits': settings.currency.decimalDigits,
        'label': _currencyLabel(l10n, settings.currency),
      },
      'trackers': [
        for (final tracker in trackers)
          {
            'id': tracker.id,
            'name': tracker.name,
            'color': tracker.color,
            'type': tracker.type.name,
            'perTap': TrackerValues.perTap(tracker.type,
                perTapValue: tracker.perTapValue),
            'unit': tracker.unit,
            'todayTotal': totals[tracker.id] ?? 0.0,
          },
      ],
      'chips': [
        for (final category in await _chips())
          {'id': category.id, 'name': category.name},
      ],
      'strings': {
        'addExpense': l10n.widgetAddExpense,
        'emptyTrackers': l10n.widgetEmptyTrackers,
        'entryTitle': l10n.widgetEntryTitle,
        'save': l10n.widgetSave,
        'cancel': l10n.widgetCancel,
        'saved': l10n.widgetSaved,
        // Templates: native fills the slots with values it formats itself
        // (spec §6.2), so a tap shows before the drain.
        'trackerAdd': l10n.widgetTrackerAdd('{name}', '{total}'),
        'trackerDone': l10n.widgetTrackerDone('{name}'),
      },
    });
  }

  Future<Map<String, double>> _totals(
      List<Tracker> trackers, DateKey today, AppCalendar calendar) async {
    if (trackers.isEmpty) return const {};
    final result = await AnalyticsEngine(_db, calendar: calendar).runTracker(
        TrackerQueries.dayTotals([for (final t in trackers) t.id], today));
    return {
      for (final bucket in result.buckets)
        if (bucket.key case TrackerKey(:final trackerId)) trackerId: bucket.value,
    };
  }

  /// The add screen's ranking, filtered as its chips are: live, unarchived,
  /// not a system row.
  Future<List<Category>> _chips() async {
    final predictor = await loadCategoryPredictor(_db);
    final offerable = {
      for (final category
          in await _db.categoriesDao.allLive(includeArchived: false))
        if (!SystemCategoryIds.isSystem(category.id)) category.id: category,
    };
    return [
      for (final id in predictor.predict(
          at: _clock.toLocal(_clock.nowUtc()), limit: maxChips))
        if (offerable[id] case final category?) category,
    ];
  }

  static String _currencyLabel(AppLocalizations l10n, Currency currency) =>
      switch (currency.code) {
        'IRT' => l10n.currency_toman,
        'USD' => l10n.currency_usd,
        'EUR' => l10n.currency_eur,
        _ => l10n.currency_try,
      };
}

final snapshotWriterProvider = Provider<SnapshotWriter>((ref) => SnapshotWriter(
    ref.watch(appDatabaseProvider), ref.watch(trackerClockProvider)));
```

- [ ] **Step 8: The sync**

Create `app/lib/features/widget/presentation/widget_sync.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../analytics/application/analytics_providers.dart';
import '../../notifications/application/outside_errors.dart';
import '../../notifications/data/outside_channel.dart';
import '../../settings/application/settings_providers.dart';
import '../../trackers/application/tracker_providers.dart';
import '../application/snapshot_writer.dart';

/// Keeps the home-screen widget's snapshot current while the app runs
/// (spec §6.1). It rewrites the snapshot 300 ms after the last of these:
/// - start-up (after the first frame, never on the cold-start path);
/// - resume;
/// - a transaction, category or tag write (the chips);
/// - a tracker entry write (today's totals);
/// - a change to the tab's trackers;
/// - a settings change (language, currency).
///
/// It sits on the shell (ruling R6): the widget is empty until first run is
/// done, and so is the database it reads.
class WidgetSync extends ConsumerStatefulWidget {
  const WidgetSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WidgetSync> createState() => _WidgetSyncState();
}

class _WidgetSyncState extends ConsumerState<WidgetSync> {
  static const _debounce = Duration(milliseconds: 300);

  late final AppLifecycleListener _lifecycle;
  final _writes = <StreamSubscription<void>>[];
  Timer? _pending;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _changed);
    ref.listenManual<AnalyticsEngine>(
        analyticsEngineProvider, (_, engine) => _follow(engine),
        fireImmediately: true);
    ref.listenManual(trackersProvider, (_, __) => _changed());
    ref.listenManual(settingsProvider, (_, __) => _changed());
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  void _follow(AnalyticsEngine engine) {
    for (final subscription in _writes) {
      unawaited(subscription.cancel());
    }
    _writes
      ..clear()
      ..add(engine.changes().listen((_) => _changed()))
      ..add(engine.trackerChanges().listen((_) => _changed()));
    _changed();
  }

  void _changed() {
    _pending?.cancel();
    _pending = Timer(_debounce, () => unawaited(_write()));
  }

  Future<void> _write() {
    // Read now: the write may finish after this widget is gone.
    final writer = ref.read(snapshotWriterProvider);
    final channel = ref.read(outsideChannelProvider);
    return reportingFailure('widget drain', 'while writing the widget snapshot',
        () async => channel.writeSnapshot(await writer.build()));
  }

  @override
  void dispose() {
    _pending?.cancel();
    for (final subscription in _writes) {
      unawaited(subscription.cancel());
    }
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

In `app/lib/bootstrap/app_shell.dart`:
1. Import `../features/widget/presentation/widget_sync.dart`.
2. Wrap so that `build` returns `NotificationsBridge(child: WidgetSync(child: GoalAlertListener(…)))`.
3. Extend the comment above it with `// The home-screen widget's snapshot follows the data (Phase 6).`

- [ ] **Step 9: GREEN**

Run from `app/`: `flutter test --no-pub test/features/widget/`. Expected: all pass.

Run from `packages/nimbus_data/`: `dart test test/trackers/`. Expected: pass.

- [ ] **Step 10: Broader suite**

Run, from the repo root: `dart analyze --fatal-infos`. From `app/`: `flutter test --no-pub --concurrency=4 --timeout 90s`. Expected: green.

If an existing widget test now ends with `A Timer is still pending`, the shell was disposed without cancelling the debounce. `dispose` above cancels it, so look for a second `WidgetSync`. Fix the cause. Do not pump extra time to hide it.

- [ ] **Step 11: Commit and fast-forward**

```bash
git add packages/nimbus_data/lib/src/trackers/trackers_dao.dart app/lib app/test/features/widget
git commit -m "$(cat <<'EOF'
feat(widget): the widget snapshot, rebuilt as the data changes

The home-screen widget renders natively from widget_snapshot.json:
the first four live non-duration trackers in tab order with today's
totals, the add screen's top four category chips, the currency, the
day, the direction, and every label already in the app's language,
with {name}/{total} slots native fills itself. Built from one-shot
reads so the headless drain engine can build it too; rewritten 300 ms
after start-up, resume, any money or tracker write, a tracker list
change or a settings change.

Additive edits: TrackersDao.allLive (Phase 4), loadCategoryPredictor
extracted from Phase 1's provider so both rank the same chips, and
WidgetSync on AppShell.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/widget-snapshot
```

---

### Task 12: The native buffer and its pure helpers (`Uuid7`, `AmountParser`, `PendingOverlay`)

Slug: `widget-buffer`. Spec §2.1, §6.3, §7. Review Focus 1 and 2.

**Files:**
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/Uuid7.kt`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/AmountParser.kt`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/PendingOverlay.kt`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetBuffer.kt`
- Modify: `OutsideChannelHandler.kt` (`takeBuffer`, `writeSnapshot`, `commitDrain` arms)
- Test: `app/android/app/src/test/kotlin/com/nimbustats/app/widget/{Uuid7Test,AmountParserTest,PendingOverlayTest}.kt`

**Interfaces:**
- Consumes: JUnit (Task 9), and the handler (Task 5).
- Produces, for Tasks 14–16:
  - `Uuid7.shared.next(): String`.
  - `AmountParser.parse(input: String, decimalDigits: Int): Long?` and `AmountParser.MAX_MINOR`.
  - `data class PendingTap(trackerId: String, atUtc: Long)`.
  - `PendingOverlay.todayValue(…)`, `PendingOverlay.isDone(type, value)` and `PendingOverlay.dayKey(instant, zone)`.
  - `WidgetBuffer`:
    - `appendExpense(context, atUtc, amountMinor, categoryId)` and `appendTrackerTap(context, atUtc, trackerId)`
    - `lines(context)` and `pendingTaps(context)`
    - `writeSnapshot(context, json)` and `readSnapshot(context): String?`
    - `commit(context, snapshot, ackIds, rejected)`

- [ ] **Step 1: Branch**

```bash
git checkout -b feat/widget-buffer phase/6-outside-the-app
```

- [ ] **Step 2: Write the failing JUnit tests**

Create `app/android/app/src/test/kotlin/com/nimbustats/app/widget/Uuid7Test.kt`:

```kotlin
package com.nimbustats.app.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class Uuid7Test {
    private val shape = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")

    @Test
    fun versionSevenAndVariantTen() {
        val generator = Uuid7()
        repeat(200) { assertTrue(shape.matches(generator.next())) }
    }

    @Test
    fun theFirst48BitsAreTheMillisecond() {
        val id = Uuid7(clock = { 0x01933F2A1B2CL }).next()
        assertEquals("01933f2a-1b2c", id.substring(0, 13))
    }

    @Test
    fun idsMadeInOneMillisecondKeepIncreasing() {
        // More than the 12-bit counter holds, so the borrow path runs too.
        val generator = Uuid7(clock = { 1_760_270_000_000L })
        val ids = List(5_000) { generator.next() }
        assertEquals(ids.sorted(), ids)
        assertEquals(ids.size, ids.toSet().size)
    }

    @Test
    fun aClockGoingBackDoesNotGoBack() {
        var now = 2_000_000L
        val generator = Uuid7(clock = { now })
        val first = generator.next()
        now = 1_000_000L
        assertTrue(generator.next() > first)
    }
}
```

Create `app/android/app/src/test/kotlin/com/nimbustats/app/widget/AmountParserTest.kt`:

```kotlin
package com.nimbustats.app.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AmountParserTest {
    @Test
    fun latinPersianAndArabicIndicDigitsReadTheSame() {
        assertEquals(12_500L, AmountParser.parse("12500", 0))
        assertEquals(12_500L, AmountParser.parse("۱۲۵۰۰", 0))
        assertEquals(12_500L, AmountParser.parse("١٢٥٠٠", 0))
    }

    @Test
    fun bothGroupSeparatorsAndSpacesAreIgnored() {
        assertEquals(12_500L, AmountParser.parse("12,500", 0))
        assertEquals(12_500L, AmountParser.parse("۱۲٬۵۰۰", 0)) // Review Focus 2
        assertEquals(12_500L, AmountParser.parse(" 12 500 ", 0))
        assertEquals(12_500L, AmountParser.parse("12 500", 0))
    }

    @Test
    fun fractionsFollowTheCurrency() {
        assertEquals(1_250L, AmountParser.parse("12.5", 2))
        assertEquals(1_205L, AmountParser.parse("12.05", 2))
        assertEquals(1_200L, AmountParser.parse("12.", 2))
        assertEquals(50L, AmountParser.parse(".5", 2))
        assertNull(AmountParser.parse("12.345", 2))
        assertNull(AmountParser.parse("12.5", 0)) // Toman has no fraction
        assertEquals(12L, AmountParser.parse("12.", 0))
    }

    @Test
    fun zeroAndNegativeCannotBeSaved() {
        assertNull(AmountParser.parse("0", 0))
        assertNull(AmountParser.parse("0.00", 2))
        assertNull(AmountParser.parse("-5", 0)) // ruling R8
    }

    @Test
    fun theBoundIsFifteenNinesOfMinorUnits() {
        assertEquals(999_999_999_999_999L, AmountParser.parse("999999999999999", 0))
        assertNull(AmountParser.parse("1000000000000000", 0))
        assertEquals(999_999_999_999_999L, AmountParser.parse("9999999999999.99", 2))
        assertNull(AmountParser.parse("10000000000000.00", 2))
        assertNull(AmountParser.parse("99999999999999999999999", 0)) // no overflow
    }

    @Test
    fun garbageIsNull() {
        for (input in listOf("", " ", ".", "1.2.3", "12a", "۱۲x", "--5", "+5", "1e5", "12٫5")) {
            assertNull(input, AmountParser.parse(input, 2))
        }
    }
}
```

Create `app/android/app/src/test/kotlin/com/nimbustats/app/widget/PendingOverlayTest.kt`:

```kotlin
package com.nimbustats.app.widget

import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingOverlayTest {
    private val tehran = ZoneId.of("Asia/Tehran")
    private val noon = Instant.parse("2026-10-12T08:30:00Z") // 12:00 on the 12th in Tehran
    private fun tap(id: String, at: Instant = noon) = PendingTap(id, at.toEpochMilli())

    private fun value(dayKey: Int, total: Double, perTap: Double, pending: List<PendingTap>) =
        PendingOverlay.todayValue(dayKey, total, perTap, "cig", pending, tehran, noon)

    @Test
    fun todaysSnapshotPlusTodaysTapsForThisTracker() {
        assertEquals(5.0, value(20261012, 3.0, 1.0, listOf(tap("cig"), tap("cig"), tap("tea"))), 0.0)
    }

    @Test
    fun aSnapshotFromAnotherDayCountsAsNothing() {
        assertEquals(1.0, value(20261011, 7.0, 1.0, listOf(tap("cig"))), 0.0)
    }

    @Test
    fun aTapFromBeforeMidnightDoesNotCountToday() { // Review Focus 1
        val lateLastNight = Instant.parse("2026-10-11T20:29:00Z") // 23:59 on the 11th in Tehran
        assertEquals(0.0, value(20261012, 0.0, 1.0, listOf(tap("cig", lateLastNight))), 0.0)
    }

    @Test
    fun aQuantityTapAddsItsPerTapAmount() {
        assertEquals(1.0, value(20261012, 0.5, 0.25, listOf(tap("cig"), tap("cig"))), 1e-9)
    }

    @Test
    fun aBooleanIsDoneOnceTodayHoldsAnything() {
        assertTrue(PendingOverlay.isDone("boolean", 1.0))
        assertFalse(PendingOverlay.isDone("boolean", 0.0))
        assertFalse(PendingOverlay.isDone("counter", 3.0))
    }

    @Test
    fun theDayKeyIsTheLocalGregorianDate() {
        assertEquals(20261011, PendingOverlay.dayKey(Instant.parse("2026-10-11T20:29:00Z"), tehran))
        assertEquals(20261012, PendingOverlay.dayKey(Instant.parse("2026-10-11T20:31:00Z"), tehran))
    }
}
```

- [ ] **Step 3: RED**

Run from `app/android/`: `./gradlew :app:testDebugUnitTest`. Expected: compilation fails. `Uuid7`, `AmountParser`, `PendingOverlay` and `PendingTap` are unresolved.

- [ ] **Step 4: Tag**

```bash
git tag pre-widget-buffer phase/6-outside-the-app
```

- [ ] **Step 5: The pure helpers**

Create `app/android/app/src/main/kotlin/com/nimbustats/app/widget/Uuid7.kt`:

```kotlin
package com.nimbustats.app.widget

import java.security.SecureRandom
import java.util.Locale
import java.util.Random

/**
 * UUIDv7 ids for buffer lines (spec §2.1). A line's id becomes its row's id, and the app's own ids
 * are v7 too, so widget rows sort by time like every other row.
 *
 * Layout: 48 bits of Unix milliseconds, version 7, a 12-bit counter that keeps ids made in one
 * millisecond increasing, variant `10`, then 62 random bits. Pure: JUnit covers it.
 */
class Uuid7(
    private val clock: () -> Long = System::currentTimeMillis,
    private val random: Random = SecureRandom(),
) {
    private var lastMs = -1L
    private var counter = 0

    @Synchronized
    fun next(): String {
        var ms = clock()
        if (ms <= lastMs) {
            // The same millisecond, or a clock that stepped back: keep counting.
            ms = lastMs
            if (++counter > 0xFFF) {
                ms++ // borrow the next millisecond rather than repeat
                counter = random.nextInt(0x800)
            }
        } else {
            // Random, but in the lower half, so there is room to count up.
            counter = random.nextInt(0x800)
        }
        lastMs = ms
        val high = (ms shl 16) or (0x7L shl 12) or counter.toLong()
        val low = (random.nextLong() and 0x3FFF_FFFF_FFFF_FFFFL) or Long.MIN_VALUE
        val hex = String.format(Locale.ROOT, "%016x%016x", high, low)
        return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-" +
            "${hex.substring(16, 20)}-${hex.substring(20)}"
    }

    companion object {
        /** The process-wide generator every buffer append uses. */
        val shared = Uuid7()
    }
}
```

Create `app/android/app/src/main/kotlin/com/nimbustats/app/widget/AmountParser.kt`:

```kotlin
package com.nimbustats.app.widget

/**
 * The dialog's amount as minor units for a currency with [decimalDigits] fraction digits, or null
 * (spec §7). Pure: JUnit covers it.
 *
 * It mirrors Dart's `MoneyFormatter.parse`, so the dialog accepts what the add screen accepts:
 * - Latin, Persian and Arabic-Indic digits;
 * - `,`, U+066C, a space and a no-break space are dropped;
 * - one `.`;
 * - at most [decimalDigits] fraction digits, and none for a zero-decimal currency.
 *
 * Unlike it, the dialog refuses `-` (ruling R8: it records spending) and zero (nothing to save),
 * and anything above [MAX_MINOR].
 */
object AmountParser {
    /** Fifteen nines of minor units: far above any real expense, inside a Long and a JSON number. */
    const val MAX_MINOR = 999_999_999_999_999L

    fun parse(input: String, decimalDigits: Int): Long? {
        require(decimalDigits in 0..3) { "decimalDigits $decimalDigits" }
        val text = toLatin(input).trim()
            .replace(",", "").replace("٬", "").replace(" ", "").replace(" ", "")
        if (text.isEmpty() || text.startsWith("-")) return null
        val parts = text.split('.')
        if (parts.size > 2 || parts.any { part -> part.any { it !in '0'..'9' } }) return null
        val whole = parts[0]
        val fraction = parts.getOrNull(1)
        if (whole.isEmpty() && fraction.isNullOrEmpty()) return null
        val major = whole.trimStart('0').ifEmpty { "0" }
        if (major.length > 15) return null
        val minor = when {
            fraction.isNullOrEmpty() -> 0L
            decimalDigits == 0 || fraction.length > decimalDigits -> return null
            else -> fraction.padEnd(decimalDigits, '0').toLong()
        }
        var scale = 1L
        repeat(decimalDigits) { scale *= 10 }
        val total = major.toLong() * scale + minor
        return if (total in 1..MAX_MINOR) total else null
    }

    private fun toLatin(input: String): String = buildString(input.length) {
        for (c in input) {
            append(
                when (c) {
                    in '۰'..'۹' -> '0' + (c - '۰')
                    in '٠'..'٩' -> '0' + (c - '٠')
                    else -> c
                },
            )
        }
    }
}
```

Create `app/android/app/src/main/kotlin/com/nimbustats/app/widget/PendingOverlay.kt`:

```kotlin
package com.nimbustats.app.widget

import java.time.Instant
import java.time.ZoneId

/** One tracker tap still waiting in the buffer. */
data class PendingTap(val trackerId: String, val atUtc: Long)

/**
 * What a widget row shows for today (spec §6.3). That is the snapshot's total if the snapshot is
 * from today, or nothing if not, plus every tap still in the buffer whose local day is today.
 *
 * It is optimistic, so a tap shows at once. The drain's commit then moves the tap from "pending"
 * into the snapshot in one step, so the number never changes twice. Pure: JUnit covers it.
 */
object PendingOverlay {
    fun todayValue(
        snapshotDayKey: Int,
        snapshotTotal: Double,
        perTap: Double,
        trackerId: String,
        pending: List<PendingTap>,
        zone: ZoneId,
        now: Instant,
    ): Double {
        val today = dayKey(now, zone)
        val base = if (snapshotDayKey == today) snapshotTotal else 0.0
        val taps = pending.count {
            it.trackerId == trackerId && dayKey(Instant.ofEpochMilli(it.atUtc), zone) == today
        }
        return base + taps * perTap
    }

    /** A boolean tracker is done once today holds anything. */
    fun isDone(type: String, value: Double): Boolean = type == "boolean" && value > 0.0

    /** The local Gregorian `yyyymmdd` [instant] falls on, like every `local_date_key`. */
    fun dayKey(instant: Instant, zone: ZoneId): Int {
        val date = instant.atZone(zone).toLocalDate()
        return date.year * 10_000 + date.monthValue * 100 + date.dayOfMonth
    }
}
```

- [ ] **Step 6: GREEN (JUnit)**

Run from `app/android/`: `./gradlew :app:testDebugUnitTest`. Expected: `BUILD SUCCESSFUL`, with every test green.

- [ ] **Step 7: The buffer, and the channel arms**

Create `app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetBuffer.kt`:

```kotlin
package com.nimbustats.app.widget

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import org.json.JSONObject

/**
 * The widget's files under `filesDir` (spec §2.1), behind one lock.
 *
 * Every reader and writer runs in the app's process: widget broadcasts, the dialog, the drain job
 * and the channel. So a synchronized object is enough. An append writes one line and syncs it to
 * disk. Anything that removes lines or replaces the snapshot writes a temp file and renames it
 * over the original, so a crash leaves the old file, never half of one.
 */
object WidgetBuffer {
    private const val BUFFER = "widget_buffer.jsonl"
    private const val REJECTED = "widget_buffer.rejected.jsonl"
    private const val SNAPSHOT = "widget_snapshot.json"
    private const val VERSION = 1

    @Synchronized
    fun appendExpense(context: Context, atUtc: Long, amountMinor: Long, categoryId: String?) {
        require(amountMinor in 1..AmountParser.MAX_MINOR) { "amount $amountMinor is out of range" }
        append(context, line("expense", atUtc).put("amountMinor", amountMinor).put("categoryId", categoryId ?: JSONObject.NULL))
    }

    @Synchronized
    fun appendTrackerTap(context: Context, atUtc: Long, trackerId: String) {
        append(context, line("tracker", atUtc).put("trackerId", trackerId))
    }

    /** Every pending line, raw. Nothing is removed (spec §2.3 step 1). */
    @Synchronized
    fun lines(context: Context): List<String> = readLines(file(context, BUFFER))

    /**
     * Tracker taps still waiting, for [PendingOverlay]. A line that does not read is left out
     * here. The drain rejects it, keeps it in the rejected file, and reports it (spec §2.3).
     */
    @Synchronized
    fun pendingTaps(context: Context): List<PendingTap> = lines(context).mapNotNull { raw ->
        runCatching {
            JSONObject(raw).takeIf { it.optString("kind") == "tracker" }
                ?.let { PendingTap(it.getString("trackerId"), it.getLong("atUtc")) }
        }.getOrNull()
    }

    @Synchronized
    fun writeSnapshot(context: Context, json: String) = replace(file(context, SNAPSHOT), json)

    @Synchronized
    fun readSnapshot(context: Context): String? = file(context, SNAPSHOT).takeIf { it.exists() }?.readText()

    /**
     * Spec §2.3 step 4, in one locked call:
     * 1. keeps the rejected lines with their reasons in `widget_buffer.rejected.jsonl`;
     * 2. writes the snapshot;
     * 3. drops the acked and rejected lines.
     *
     * One call is what keeps a tap from counting twice (in the snapshot and still pending) or not
     * at all.
     */
    @Synchronized
    fun commit(context: Context, snapshot: String, ackIds: Set<String>, rejected: Map<String, String>) {
        if (rejected.isNotEmpty()) {
            FileOutputStream(file(context, REJECTED), true).use { out ->
                for ((line, reason) in rejected) {
                    out.write((JSONObject().put("line", line).put("reason", reason).toString() + "\n").toByteArray())
                }
                out.fd.sync()
            }
        }
        replace(file(context, SNAPSHOT), snapshot)
        val kept = readLines(file(context, BUFFER)).filter { raw -> raw !in rejected && idOf(raw) !in ackIds }
        replace(file(context, BUFFER), kept.joinToString("") { "$it\n" })
    }

    private fun line(kind: String, atUtc: Long): JSONObject =
        JSONObject().put("v", VERSION).put("id", Uuid7.shared.next()).put("kind", kind).put("atUtc", atUtc)

    private fun append(context: Context, json: JSONObject) {
        FileOutputStream(file(context, BUFFER), true).use { out ->
            out.write((json.toString() + "\n").toByteArray())
            out.fd.sync()
        }
    }

    private fun replace(target: File, content: String) {
        val temp = File(target.parentFile, "${target.name}.tmp")
        FileOutputStream(temp).use { out ->
            out.write(content.toByteArray())
            out.fd.sync()
        }
        if (!temp.renameTo(target)) throw IOException("could not replace ${target.name}")
    }

    private fun readLines(file: File): List<String> =
        if (file.exists()) file.readLines().filter { it.isNotBlank() } else emptyList()

    private fun idOf(raw: String): String? = runCatching { JSONObject(raw).getString("id") }.getOrNull()

    private fun file(context: Context, name: String) = File(context.filesDir, name)
}
```

In `OutsideChannelHandler.kt`:
1. Add `import com.nimbustats.app.widget.WidgetBuffer`.
2. Add these arms before `"takeLaunchRoute"`:

```kotlin
                "takeBuffer" -> result.success(WidgetBuffer.lines(context))
                "writeSnapshot" -> {
                    WidgetBuffer.writeSnapshot(context, call.string("snapshot"))
                    result.success(null)
                }
                "commitDrain" -> {
                    val ackIds = call.argument<List<String>>("ackIds")
                        ?: throw IllegalArgumentException("missing ackIds")
                    val rejected = call.argument<List<Map<String, String>>>("rejected")
                        ?: throw IllegalArgumentException("missing rejected")
                    WidgetBuffer.commit(
                        context,
                        call.string("snapshot"),
                        ackIds.toSet(),
                        rejected.associate {
                            (it["line"] ?: throw IllegalArgumentException("rejected without line")) to
                                (it["reason"] ?: throw IllegalArgumentException("rejected without reason"))
                        },
                    )
                    result.success(null)
                }
```

- [ ] **Step 8: Build and the broader suites**

Run, from `app/`: `flutter build apk --debug`. From `app/android/`: `./gradlew :app:testDebugUnitTest`. From the repo root: `dart analyze --fatal-infos`. Expected: green.

- [ ] **Step 9: Commit and fast-forward**

```bash
git add app/android/app/src
git commit -m "$(cat <<'EOF'
feat(widget): the native buffer, line ids, amount parsing, pending overlay

The widget's taps never start Flutter: each becomes one line in
files/widget_buffer.jsonl, synced to disk, under one in-process lock;
removals and snapshot writes go through temp-file renames so a crash
leaves the old file. commit applies a drain's outcome in one locked
call (rejected log, snapshot, buffer) so a tap is never counted twice
or not at all.

Pure, JUnit-tested helpers: Uuid7 (the line id is the row id, so
v7 like every other row, monotonic within a millisecond); AmountParser
(mirrors MoneyFormatter.parse across three digit sets and both group
separators, refuses zero, negatives and amounts past 15 nines);
PendingOverlay (today's value: today's snapshot plus today's pending
taps only). The buffer itself is Android file I/O, verified on device
in Task 17.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/widget-buffer
```

---

### Task 13: The drain, in Dart — exactly once, in either engine

Slug: `widget-drain`. Spec §2.2–§2.4, rulings R5 and R10. Review Focus 1 and 3.

**Files:**
- Create: `app/lib/features/widget/application/widget_drain.dart`
- Create: `app/lib/features/widget/application/drain_service.dart`
- Create: `app/lib/drain_main.dart`
- Modify: `app/lib/main.dart` (export, R5)
- Modify: `app/lib/features/widget/presentation/widget_sync.dart` (drain triggers, queued snapshot)
- Test: `app/test/features/widget/widget_drain_test.dart`, `app/test/features/widget/drain_service_test.dart`, `app/test/features/widget/widget_sync_test.dart`

**Interfaces:**
- Consumes:
  - `add(id:)` and `logEntry(id:)` (Task 2) and `checkNow` (Task 3).
  - `OutsideChannel` and `RejectedLine` (Task 4).
  - `alertRouterProvider` (Task 7) and `SnapshotWriter` (Task 11).
- Produces:
  - `typedef DrainOutcome = ({List<String> ackIds, List<RejectedLine> rejected, int failed})`.
  - `final class WidgetDrain`, with `Future<DrainOutcome> apply(List<String> lines)`, and `const maxAmountMinor = 999999999999999`.
  - `final class DrainService`, with `Future<bool> run()` and `Future<void> refreshSnapshot()`, and `drainServiceProvider`.
  - `Future<bool> runDrain(ProviderContainer container)`.
  - `@pragma('vm:entry-point') Future<void> drainMain()` in `package:nimbustats/drain_main.dart`. Task 14 boots it.

- [ ] **Step 1: Branch**

```bash
git checkout -b feat/widget-drain phase/6-outside-the-app
```

- [ ] **Step 2: Write the failing tests**

Create `app/test/features/widget/support/buffer_lines.dart`, the lines native writes (spec §2.1):

```dart
import 'dart:convert';

/// An expense line as the dialog appends it. 2026-10-05 09:00 UTC is the
/// fake clock's now.
String expense(String id,
        {int amount = 120000, String? category, DateTime? at}) =>
    jsonEncode({
      'v': 1,
      'id': id,
      'kind': 'expense',
      'atUtc': (at ?? DateTime.utc(2026, 10, 5, 9)).millisecondsSinceEpoch,
      'amountMinor': amount,
      'categoryId': category,
    });

/// A tracker tap line as the widget appends it.
String tap(String id, String trackerId, {DateTime? at}) => jsonEncode({
      'v': 1,
      'id': id,
      'kind': 'tracker',
      'atUtc': (at ?? DateTime.utc(2026, 10, 5, 9)).millisecondsSinceEpoch,
      'trackerId': trackerId,
    });
```

Create `app/test/features/widget/widget_drain_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/features/trackers/data/tracker_repository.dart';
import 'package:nimbustats/features/transactions/data/transaction_repository.dart';
import 'package:nimbustats/features/widget/application/widget_drain.dart';

import '../goals/support/goal_test_app.dart';
import '../trackers/support/tracker_fixture.dart';
import 'support/buffer_lines.dart';

void main() {
  late AppDatabase db;
  late FakeClock fake;
  late TrackerRepository trackers;
  late WidgetDrain drain;

  WidgetDrain drainOver(AppDatabase database) => WidgetDrain(
        db: database,
        transactions: TransactionRepository(
            database.transactionsDao, database.tagsDao, Currency.toman),
        trackers: repositoryFor(database, fake),
      );

  setUp(() async {
    db = AppDatabase.openInMemory();
    fake = FakeClock();
    trackers = repositoryFor(db, fake);
    drain = drainOver(db);
    await seedCategories(db);
  });
  tearDown(() => db.close());

  Future<Transaction?> row(String id) => db.transactionsDao.byId(id);

  test('each line is written once: a second drain writes nothing', () async {
    final cig = await trackers.create(cigarettes);
    final lines = [expense('e1', category: 'seed-dining'), tap('t1', cig.id)];

    final first = await drain.apply(lines);
    final second = await drain.apply(lines);

    expect(first.ackIds, ['e1', 't1']);
    expect(second.ackIds, ['e1', 't1'], reason: 'settled, so acked again');
    expect((await row('e1'))!.amount, const Money(120000));
    expect((await row('e1'))!.source, TxSource.widget);
    expect((await trackers.entriesPage(cig.id)).items, hasLength(1));
  });

  test('an expense deleted after it was drained is not resurrected',
      () async {
    await drain.apply([expense('e2')]);
    await db.transactionsDao.softDelete('e2');
    await drain.apply([expense('e2')]);

    expect((await row('e2'))!.deletedAt, isNotNull);
  });

  test('the tap time is kept, across midnight (Review Focus 1)', () async {
    final cig = await trackers.create(cigarettes);
    // 23:59 on the 4th in Tehran; drained at 12:30 on the 5th.
    final lateLastNight = DateTime.utc(2026, 10, 4, 20, 29);
    await drain.apply([
      expense('e3', at: lateLastNight),
      tap('t3', cig.id, at: lateLastNight),
    ]);

    expect((await row('e3'))!.occurredAtUtc,
        lateLastNight.millisecondsSinceEpoch);
    final entry = (await trackers.entriesPage(cig.id)).items.single;
    expect(entry.occurredAtUtc, lateLastNight);
    expect(entry.localDateKey, const DateKey(20261004));
  });

  test('no chip, or a category deleted since the snapshot, files it as '
      'Uncategorized', () async {
    await db.categoriesDao.softDeleteSubtree('seed-transport');
    await drain.apply([
      expense('e4'),
      expense('e5', category: 'seed-transport'),
    ]);

    expect((await row('e4'))!.categoryId, SystemCategoryIds.uncategorized);
    expect((await row('e5'))!.categoryId, SystemCategoryIds.uncategorized);
  });

  test('a tracker gone, archived or timed is rejected with a reason',
      () async {
    final gone = await trackers.create(cigarettes);
    // The app archives trackers and never deletes one, but a soft-deleted
    // row must still read as gone.
    await db.customStatement(
        'UPDATE trackers SET deleted_at = 1 WHERE id = ?', [gone.id]);
    final archived = await trackers.create(gym);
    await trackers.archive(archived.id);
    final timed = await trackers.create(sleep);

    final outcome = await drain.apply([
      tap('g', gone.id),
      tap('a', archived.id),
      tap('d', timed.id),
      tap('x', 'no-such-tracker'),
    ]);

    expect(outcome.ackIds, isEmpty);
    expect([for (final r in outcome.rejected) r.reason], [
      'tracker gone',
      'tracker archived',
      'duration tracker',
      'tracker gone',
    ]);
    expect(outcome.rejected.first.line, tap('g', gone.id));
  });

  test('a malformed line, an unknown version or an amount out of range is '
      'rejected', () async {
    final outcome = await drain.apply([
      'not json',
      '[1,2]',
      jsonEncode({'v': 2, 'id': 'v2', 'kind': 'expense', 'atUtc': 0}),
      expense('big', amount: maxAmountMinor + 1),
      expense('zero', amount: 0),
      jsonEncode({'v': 1, 'id': 'k', 'kind': 'transfer', 'atUtc': 0}),
    ]);

    expect(outcome.ackIds, isEmpty);
    expect(outcome.rejected, hasLength(6));
    expect(await db.transactionsDao.byId('big'), isNull);
  });

  test("a boolean already done that day is acked: it is the repository's "
      'rule', () async {
    final done = await trackers.create(gym);
    await trackers.logEntry(done.id);
    final outcome = await drain.apply([tap('t6', done.id)]);

    expect(outcome.ackIds, ['t6']);
    expect((await trackers.entriesPage(done.id)).items, hasLength(1));
  });

  test('an unexpected failure leaves the line for the next drain and is '
      'reported', () async {
    final bare = AppDatabase.openInMemory(); // no Uncategorized row: FK fails
    addTearDown(bare.close);
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);

    final outcome = await drainOver(bare).apply([expense('e7')]);

    expect(outcome.ackIds, isEmpty);
    expect(outcome.rejected, isEmpty);
    expect(outcome.failed, 1);
    expect(reported.single.library, 'widget drain');
  });

  test('two engines draining the same lines at once write each once '
      '(Review Focus 3)', () async {
    final dir = Directory.systemTemp.createTempSync('nimbus_drain_race');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}nimbustats.sqlite';
    final app = AppDatabase.openAtPath(path);
    final headless = AppDatabase.openAtPath(path);
    addTearDown(app.close);
    addTearDown(headless.close);
    await seedCategories(app);
    final lines = [for (var i = 0; i < 30; i++) expense('r$i')];

    await Future.wait(
        [drainOver(app).apply(lines), drainOver(headless).apply(lines)]);

    final rows = await app.transactionsDao.inRange(
        const DateRange(DateKey(20000101), DateKey(20991231)));
    expect(rows, hasLength(30));
  });
}
```

Create `app/test/features/widget/drain_service_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';
import 'package:nimbustats/bootstrap/database_provider.dart';
import 'package:nimbustats/bootstrap/provider_retry.dart';
import 'package:nimbustats/drain_main.dart';
import 'package:nimbustats/features/notifications/application/notification_providers.dart';
import 'package:nimbustats/features/notifications/data/outside_channel.dart';
import 'package:nimbustats/features/settings/data/app_settings.dart';
import 'package:nimbustats/features/settings/data/settings_repository.dart';

import '../goals/support/goal_test_app.dart';
import '../notifications/support/fake_outside_channel.dart';
import '../trackers/support/tracker_fixture.dart';
import 'support/buffer_lines.dart';

/// One drain as the headless engine runs it: a bare container, no widget
/// tree, the channel faked (spec §10, "runDrain end to end").
void main() {
  late AppDatabase db;
  late FakeClock fake;
  late FakeOutsideChannel outside;

  setUp(() async {
    db = AppDatabase.openInMemory();
    fake = FakeClock();
    outside = FakeOutsideChannel();
    await seedCategories(db);
  });
  tearDown(() => db.close());

  ProviderContainer engine() {
    final c = ProviderContainer(retry: nimbusNoRetry, overrides: [
      appDatabaseProvider.overrideWithValue(db),
      outsideChannelProvider.overrideWithValue(outside),
      ...trackerOverrides(fake),
      // The headless engine has no lifecycle.
      isForegroundProvider.overrideWithValue(() => false),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('takes, writes, commits once with a fresh snapshot; the buffer '
      'empties', () async {
    outside.buffer = [expense('e1'), 'garbage'];
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);

    expect(await runDrain(engine()), isTrue);

    expect(outside.commits, hasLength(1));
    expect(outside.commits.single.ackIds, ['e1']);
    expect(outside.commits.single.rejected.single.line, 'garbage');
    expect(jsonDecode(outside.commits.single.snapshot), containsPair('v', 1));
    expect(outside.buffer, isEmpty);
    expect(reported.single.library, 'widget drain',
        reason: 'every rejection is reported');
  });

  test('a fresh engine stamps the saved currency, not the default', () async {
    await SettingsRepository(db.settingsDao)
        .save(AppSettings.defaults.copyWith(currency: Currency.usd));
    outside.buffer = [expense('e2', amount: 1250)];

    await runDrain(engine());

    final tx = (await db.transactionsDao.byId('e2'))!;
    expect(tx.currencyCode, 'USD');
    expect(tx.amount, const Money(1250));
  });

  test('a crossing the drain causes is posted before the drain ends',
      () async {
    final service = goalServiceFor(db, fake.clock.today);
    await service.save(spendingCap()); // 1,000,000 a month on Dining
    outside.buffer = [expense('e3', amount: 850000, category: 'seed-dining')];

    await runDrain(engine());

    expect(outside.posted.single.tag, 'goal:cap');
    expect(outside.calls.indexOf('commitDrain'),
        lessThan(outside.calls.indexOf('postAlert')));
  });

  test('a line that failed unexpectedly makes the drain not ok', () async {
    final bare = AppDatabase.openInMemory();
    addTearDown(bare.close);
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = previous);
    outside.buffer = [expense('e4')];
    final c = ProviderContainer(retry: nimbusNoRetry, overrides: [
      appDatabaseProvider.overrideWithValue(bare), // no categories: FK fails
      outsideChannelProvider.overrideWithValue(outside),
      isForegroundProvider.overrideWithValue(() => false),
    ]);
    addTearDown(c.dispose);

    expect(await runDrain(c), isFalse);
    expect(outside.buffer, [expense('e4')], reason: 'kept for the next drain');
  });

  test('an empty buffer commits nothing', () async {
    expect(await runDrain(engine()), isTrue);
    expect(outside.commits, isEmpty);
  });
}
```

The `FlutterError.onError = (_) {}` in the "not ok" test silences the expected report in this one test only. The previous test asserts that the report happens.

Append inside `main()` of `app/test/features/widget/widget_sync_test.dart`. Also add `import 'support/buffer_lines.dart';`:

```dart
  testWidgets('the app engine drains after the first frame', (tester) async {
    outside.buffer = [expense('w1')];
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);
    await tester.pumpAndSettle();

    expect(outside.buffer, isEmpty);
    expect(await db.transactionsDao.byId('w1'), isNotNull);
  });

  testWidgets("native's drainNow drains in the app engine and answers ok",
      (tester) async {
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);
    await tester.pumpAndSettle();
    outside.buffer = [expense('w2')];

    final answered = outside.onDrainNow!();
    await tester.pumpAndSettle();

    expect(await answered, isTrue);
    expect(outside.buffer, isEmpty);
  });

  testWidgets('a resume drains', (tester) async {
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);
    await tester.pumpAndSettle();
    outside.buffer = [expense('w3')];

    await backgroundAndResume(tester);
    await tester.pumpAndSettle();

    expect(outside.buffer, isEmpty);
  });

  testWidgets('leaving the shell unregisters the drain, so native drains '
      'headless', (tester) async {
    await pumpApp(tester, database: db, seedFirstRun: true, outside: outside);
    expect(outside.onDrainNow, isNotNull);

    await tester.pumpWidget(const SizedBox());
    expect(outside.onDrainNow, isNull);
  });
```

- [ ] **Step 3: RED**

Run from `app/`: `flutter test --no-pub test/features/widget/`. Expected: compile errors. `widget_drain.dart`, `drain_service.dart` and `drain_main.dart` do not exist.

- [ ] **Step 4: Tag**

```bash
git tag pre-widget-drain phase/6-outside-the-app
```

- [ ] **Step 5: `WidgetDrain`**

Create `app/lib/features/widget/application/widget_drain.dart`:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:nimbus_domain/nimbus_domain.dart';

import '../../notifications/data/outside_channel.dart';
import '../../trackers/data/tracker_repository.dart';
import '../../transactions/data/transaction_draft.dart';
import '../../transactions/data/transaction_repository.dart';

/// The largest amount a buffer line may carry. It is the dialog's own bound
/// (`AmountParser.MAX_MINOR`), checked again here because the buffer is a
/// trust boundary.
const maxAmountMinor = 999999999999999;

/// What one pass over the buffer decided (spec §2.3 step 2). [failed] counts
/// lines left for the next drain after an unexpected error.
typedef DrainOutcome = ({
  List<String> ackIds,
  List<RejectedLine> rejected,
  int failed,
});

/// Writes widget buffer lines through the app's one write path, each
/// exactly once (spec §2.2, §2.3).
///
/// A line's id is its row's id, so a repeated drain writes nothing new and a
/// deleted row stays deleted. Each line is settled one of three ways:
/// - **acked**: written, or written before. A boolean already done that day
///   is acked too, because that is the repository's rule.
/// - **rejected, with a reason**:
///   - a malformed line, or one with an unknown version or kind;
///   - an amount out of range;
///   - a tracker gone, archived, or timed.
/// - **left in place**: anything unexpected, reported under `widget drain`.
///   It is retried by the next drain.
///
/// A category deleted since the snapshot is not a rejection. The expense
/// is filed as Uncategorized, because the amount is what matters.
final class WidgetDrain {
  WidgetDrain({
    required AppDatabase db,
    required TransactionRepository transactions,
    required TrackerRepository trackers,
  })  : _db = db,
        _transactions = transactions,
        _trackers = trackers;

  final AppDatabase _db;
  final TransactionRepository _transactions;
  final TrackerRepository _trackers;

  Future<DrainOutcome> apply(List<String> lines) async {
    final ackIds = <String>[];
    final rejected = <RejectedLine>[];
    var failed = 0;
    for (final raw in lines) {
      final _Line line;
      try {
        line = _Line.parse(raw);
      } on FormatException catch (error) {
        rejected.add((line: raw, reason: error.message));
        continue;
      }
      try {
        final reason = await switch (line) {
          _Expense() => _expense(line),
          _Tap() => _tap(line),
        };
        if (reason == null) {
          ackIds.add(line.id);
        } else {
          rejected.add((line: raw, reason: reason));
        }
      } on Object catch (error, stack) {
        failed++;
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'widget drain',
          context: ErrorDescription(
              'while writing buffer line ${line.id}; it stays for the next drain'),
        ));
      }
    }
    return (ackIds: ackIds, rejected: rejected, failed: failed);
  }

  Future<String?> _expense(_Expense line) async {
    final chosen = line.categoryId;
    final category = chosen == null ? null : await _db.categoriesDao.byId(chosen);
    await _transactions.add(
      TransactionDraft(
        amount: Money(line.amountMinor),
        direction: TxDirection.expense,
        categoryId: category != null && category.deletedAt == null
            ? category.id
            : SystemCategoryIds.uncategorized,
        occurredAtUtc: line.at,
        source: TxSource.widget,
      ),
      id: line.id,
    );
    return null;
  }

  Future<String?> _tap(_Tap line) async {
    final tracker = await _db.trackersDao.byId(line.trackerId); // live only
    if (tracker == null) return 'tracker gone';
    if (tracker.archived) return 'tracker archived';
    if (tracker.type == TrackerType.duration) return 'duration tracker';
    final result = await _trackers.logEntry(tracker.id, at: line.at, id: line.id);
    return switch (result) {
      EntryLogged() || AlreadyLogged() || AlreadyDoneToday() => null,
    };
  }
}

/// One buffer line (spec §2.1).
sealed class _Line {
  const _Line(this.id, this.at);

  final String id;

  /// The tap time, so a late drain files the tap when it happened.
  final DateTime at;

  /// Throws [FormatException] whose message is the rejection's reason.
  static _Line parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException('malformed line');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('malformed line');
    }
    if (decoded['v'] != 1) {
      throw FormatException('unknown line version ${decoded['v']}');
    }
    final id = decoded['id'];
    final atUtc = decoded['atUtc'];
    if (id is! String || id.isEmpty || atUtc is! int) {
      throw const FormatException('malformed line');
    }
    final at = DateTime.fromMillisecondsSinceEpoch(atUtc, isUtc: true);
    switch (decoded['kind']) {
      case 'expense':
        final amount = decoded['amountMinor'];
        final category = decoded['categoryId'];
        if (amount is! int || amount < 1 || amount > maxAmountMinor) {
          throw FormatException('amount out of range: $amount');
        }
        if (category != null && category is! String) {
          throw const FormatException('malformed line');
        }
        return _Expense(id, at, amount, category as String?);
      case 'tracker':
        final trackerId = decoded['trackerId'];
        if (trackerId is! String) throw const FormatException('malformed line');
        return _Tap(id, at, trackerId);
      default:
        throw FormatException('unknown line kind ${decoded['kind']}');
    }
  }
}

final class _Expense extends _Line {
  const _Expense(super.id, super.at, this.amountMinor, this.categoryId);

  final int amountMinor;
  final String? categoryId;
}

final class _Tap extends _Line {
  const _Tap(super.id, super.at, this.trackerId);

  final String trackerId;
}
```

- [ ] **Step 6: `DrainService`, `runDrain` and `drainMain`**

Create `app/lib/features/widget/application/drain_service.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';

import '../../../bootstrap/database_provider.dart';
import '../../goals/application/goal_watcher.dart';
import '../../notifications/application/alert_router.dart';
import '../../notifications/data/outside_channel.dart';
import '../../settings/data/settings_repository.dart';
import '../../trackers/application/tracker_providers.dart';
import '../../trackers/data/tracker_repository.dart';
import '../../transactions/data/transaction_repository.dart';
import 'snapshot_writer.dart';
import 'widget_drain.dart';

/// One drain of the widget buffer, in whichever engine runs it (spec §2.3):
/// 1. take every pending line;
/// 2. write each through the repositories;
/// 3. build a fresh snapshot;
/// 4. commit the snapshot, the acks and the rejects in one native call;
/// 5. report every rejection;
/// 6. check every goal, and wait for any notification to post.
///
/// Drains and snapshot writes in one engine are queued, never run side by
/// side. So a snapshot built from rows a drain has written never meets the
/// lines that drain is about to ack.
final class DrainService {
  DrainService(this._ref);

  final Ref _ref;
  Future<void> _tail = Future.value();

  /// Returns whether every line was settled (ruling R10).
  Future<bool> run() => _queued(_drain);

  /// The app engine's snapshot rewrite (`WidgetSync`), queued like a drain.
  Future<void> refreshSnapshot() => _queued(() async => _ref
      .read(outsideChannelProvider)
      .writeSnapshot(await _ref.read(snapshotWriterProvider).build()));

  Future<T> _queued<T>(Future<T> Function() job) {
    final result = _tail.then((_) => job());
    // The caller gets the failure through [result]. The queue itself only
    // waits for the job to end.
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<bool> _drain() async {
    final channel = _ref.read(outsideChannelProvider);
    // Subscribed before the goal check can emit.
    final alerts = _ref.read(alertRouterProvider);
    final lines = await channel.takeBuffer();
    if (lines.isEmpty) return true;

    final db = _ref.read(appDatabaseProvider);
    // Read once, not from the settings stream. A headless engine drains
    // before that stream emits, and would stamp the default currency.
    final settings = await SettingsRepository(db.settingsDao).load();
    final outcome = await WidgetDrain(
      db: db,
      transactions: TransactionRepository(
          db.transactionsDao, db.tagsDao, settings.currency),
      trackers: TrackerRepository(
        db.trackersDao,
        db.trackerEntriesDao,
        AnalyticsEngine(db, calendar: settings.calendar),
        _ref.read(trackerClockProvider),
      ),
    ).apply(lines);

    await channel.commitDrain(
      snapshot: await _ref.read(snapshotWriterProvider).build(),
      ackIds: outcome.ackIds,
      rejected: outcome.rejected,
    );
    for (final rejected in outcome.rejected) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: StateError('widget buffer line rejected: ${rejected.reason}'),
        library: 'widget drain',
        context: ErrorDescription(
            'kept in widget_buffer.rejected.jsonl: ${rejected.line}'),
      ));
    }

    await _ref.read(goalWatcherProvider).checkNow();
    // The alerts stream delivers in a microtask; then the posts it started.
    await Future<void>.delayed(Duration.zero);
    await alerts.idle();
    return outcome.failed == 0;
  }
}

final drainServiceProvider = Provider<DrainService>(DrainService.new);
```

Create `app/lib/drain_main.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nimbus_data/nimbus_data.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bootstrap/database_provider.dart';
import 'bootstrap/provider_retry.dart';
import 'features/notifications/application/outside_errors.dart';
import 'features/notifications/data/outside_channel.dart';
import 'features/widget/application/drain_service.dart';

/// The widget drain's headless engine (spec §2.4). DrainJobService starts it
/// when no app engine is alive.
///
/// It opens the database exactly as `main()` does, drains, checks every
/// goal, and tells native it is done. There is no widget tree and no
/// `runApp`. The widget tap itself never comes here: it ended with a buffer
/// append.
@pragma('vm:entry-point')
Future<void> drainMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final channel = OutsideChannel();
  AppDatabase? db;
  ProviderContainer? container;
  var ok = false;
  try {
    final dir = await getApplicationDocumentsDirectory();
    db = AppDatabase.openAtPath(p.join(dir.path, 'nimbustats.sqlite'));
    container = ProviderContainer(retry: nimbusNoRetry, overrides: [
      appDatabaseProvider.overrideWithValue(db),
      outsideChannelProvider.overrideWithValue(channel),
    ]);
    ok = await runDrain(container);
  } on Object catch (error, stack) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'widget drain',
      context: ErrorDescription('while draining in the headless engine'),
    ));
  } finally {
    container?.dispose();
    await db?.close();
    await reportingFailure('widget drain', 'while telling native the drain ended',
        () => channel.drainFinished(ok));
  }
}

/// One drain in [container]: what both engines run (spec §2.4). The channel
/// is the container's own `outsideChannelProvider`.
Future<bool> runDrain(ProviderContainer container) =>
    container.read(drainServiceProvider).run();
```

In `app/lib/main.dart`, after the imports, add:

```dart
// Ruling R5: an AOT build compiles only what main reaches, and the drain
// job boots `package:nimbustats/drain_main.dart`'s drainMain by name.
export 'drain_main.dart' show drainMain;
```

- [ ] **Step 7: The app engine drains**

In `app/lib/features/widget/presentation/widget_sync.dart`:
1. Add the imports:

```dart
import '../application/drain_service.dart';
```

2. In the state, add these fields:

```dart
  late final DrainService _drain;
  late final OutsideChannel _channel;
  late final Future<bool> Function() _onDrainNow;
```

3. At the top of `initState`, after `super.initState();`, add:

```dart
    _drain = ref.read(drainServiceProvider);
    _channel = ref.read(outsideChannelProvider);
    // Native's drain job hands a live app engine the work (spec §2.4).
    _onDrainNow = _drain.run;
    _channel.onDrainNow = _onDrainNow;
```

4. Replace `_lifecycle = AppLifecycleListener(onResume: _changed);` with:

```dart
    _lifecycle = AppLifecycleListener(onResume: () {
      _drainNow();
      _changed();
    });
```

5. Replace the post-frame callback line with:

```dart
    // After the first frame, never before it: cold start stays in budget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainNow();
      _changed();
    });
```

6. Add this method:

```dart
  void _drainNow() => unawaited(reportingFailure(
      'widget drain', 'while draining the widget buffer', _drain.run));
```

7. Replace `_write` with:

```dart
  Future<void> _write() => reportingFailure('widget drain',
      'while writing the widget snapshot', _drain.refreshSnapshot);
```

8. In `dispose`, before `super.dispose();`, add:

```dart
    // A newer shell may have registered its own drain already.
    if (_channel.onDrainNow == _onDrainNow) _channel.onDrainNow = null;
```

9. Remove the now-unused `snapshot_writer.dart` import if the analyzer reports it.
10. Extend the class doc comment: `/// It also drains the buffer after the first frame, on every resume, and when native asks (drainNow).`

- [ ] **Step 8: GREEN**

Run from `app/`: `flutter test --no-pub test/features/widget/`. Expected: all pass.

- [ ] **Step 9: Broader suite**

Run, from the repo root: `dart analyze --fatal-infos`. From `app/`: `flutter test --no-pub --concurrency=4 --timeout 90s`, then `flutter build apk --debug`. Expected: green.

- [ ] **Step 10: Commit and fast-forward**

```bash
git add app/lib app/test/features/widget
git commit -m "$(cat <<'EOF'
feat(widget): drain the buffer through the repositories, exactly once

Each buffer line becomes a transaction or a tracker entry through the
one write path, with its own id as the row id and its tap time as the
row's time: repeated drains and two engines draining at once write each
tap once, a deleted expense stays deleted, and a tap from 23:59 lands on
its own day. A deleted category files the expense as Uncategorized; a
gone, archived or timed tracker, a malformed line or an out-of-range
amount is rejected, kept in the rejected log and reported; anything
unexpected stays for the next drain. The snapshot, the acks and the
rejects commit in one native call, then every goal is checked and any
notification posted before the drain reports done.

The app engine drains after the first frame, on resume and on native's
drainNow; drainMain is the headless engine's entrypoint, exported from
main.dart so the AOT build keeps it. Settings are read once per drain so
a headless engine stamps the saved currency, not the default.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/widget-drain
```

---

### Task 14: The drain job — hand off to the app engine, or boot `drainMain` headless

Slug: `drain-job`. Spec §2.4, rulings R4 and R10. There is no host test (Global Constraints). It is built here, and verified on device in Task 17.

**Files:**
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/DrainScheduler.kt`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/DrainJobService.kt`
- Modify: `OutsideChannelHandler.kt` (`drainFinished` arm), `AndroidManifest.xml` (service)

**Interfaces:**
- Consumes:
  - `OutsideChannelHandler.appChannel` and the handler's `onDrainFinished` (Task 5).
  - `WidgetBuffer.lines` (Task 12).
  - `drainMain` (Task 13).
- Produces: `DrainScheduler.enqueue(context: Context, force: Boolean = false)`. Tasks 15 and 16 call it after every buffer append.

- [ ] **Step 1: Branch and tag**

```bash
git checkout -b feat/drain-job phase/6-outside-the-app
git tag pre-drain-job phase/6-outside-the-app
```

- [ ] **Step 2: The scheduler**

Create `app/android/app/src/main/kotlin/com/nimbustats/app/widget/DrainScheduler.kt`:

```kotlin
package com.nimbustats.app.widget

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG

/**
 * Enqueues the one drain job (spec §2.4).
 *
 * There is one fixed id, and nothing is scheduled while that job is already pending or running.
 * A burst of taps is one drain, and the next tap never stops a running drain, which `schedule`
 * would do. Taps made during a run are picked up when it finishes, because [DrainJobService]
 * re-enqueues with [force].
 *
 * The job is expedited on Android 12+. Below 12, or when expedited quota is spent, it is a plain
 * job that may start at once. It has no network constraint.
 */
object DrainScheduler {
    private const val JOB_ID = 6_000

    fun enqueue(context: Context, force: Boolean = false) {
        val scheduler = context.getSystemService(JobScheduler::class.java)
        if (!force && scheduler.getPendingJob(JOB_ID) != null) return
        val component = ComponentName(context, DrainJobService::class.java)
        if (Build.VERSION.SDK_INT >= 31 &&
            scheduler.schedule(JobInfo.Builder(JOB_ID, component).setExpedited(true).build()) ==
            JobScheduler.RESULT_SUCCESS
        ) {
            return
        }
        val plain = scheduler.schedule(JobInfo.Builder(JOB_ID, component).setOverrideDeadline(0).build())
        if (plain != JobScheduler.RESULT_SUCCESS) {
            Log.e(TAG, "widget drain job was not scheduled; the next app start drains the buffer")
        }
    }
}
```

- [ ] **Step 3: The job service**

Create `app/android/app/src/main/kotlin/com/nimbustats/app/widget/DrainJobService.kt`:

```kotlin
package com.nimbustats.app.widget

import android.app.job.JobParameters
import android.app.job.JobService
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Drains the widget buffer after a tap (spec §2.4). The tap itself never waits for this.
 *
 * - **App engine alive:** if its Dart side has registered the drain, the job sends `drainNow`
 *   and finishes on the reply.
 * - **Otherwise:** a `notImplemented` reply, or no app engine at all, means a headless
 *   `FlutterEngine` runs `drainMain`. The engine is destroyed on `drainFinished`, or after 60 s
 *   without it.
 *
 * The job never asks to be rescheduled, so a persistent failure cannot loop. After a clean drain
 * it enqueues again only if taps arrived meanwhile (ruling R10).
 */
class DrainJobService : JobService() {
    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var params: JobParameters? = null
    private val timeout = Runnable {
        Log.e(TAG, "widget drain: no drainFinished within 60 s; the buffer stays for the next app start")
        finish(ok = false)
    }

    override fun onStartJob(params: JobParameters): Boolean {
        this.params = params
        val app = OutsideChannelHandler.appChannel
        if (app == null) {
            runHeadless()
            return true
        }
        app.invokeMethod(
            "drainNow",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) = finish(ok = result == true)

                override fun error(code: String, message: String?, details: Any?) {
                    Log.e(TAG, "widget drain: the app engine's drain failed ($code: $message); draining headless")
                    runHeadless()
                }

                // The app engine's Dart side has not registered its drain yet.
                override fun notImplemented() = runHeadless()
            },
        )
        return true
    }

    private fun runHeadless() {
        val engine = FlutterEngine(applicationContext)
        this.engine = engine
        MethodChannel(engine.dartExecutor.binaryMessenger, OutsideChannelHandler.CHANNEL).setMethodCallHandler(
            OutsideChannelHandler(applicationContext, onDrainFinished = { ok -> main.post { finish(ok) } }),
        )
        main.postDelayed(timeout, TIMEOUT_MS)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "package:nimbustats/drain_main.dart",
                "drainMain",
            ),
        )
    }

    private fun finish(ok: Boolean) {
        main.removeCallbacks(timeout)
        engine?.destroy()
        engine = null
        val finished = params ?: return
        params = null
        jobFinished(finished, false)
        if (ok && WidgetBuffer.lines(applicationContext).isNotEmpty()) {
            DrainScheduler.enqueue(applicationContext, force = true)
        }
    }

    override fun onStopJob(params: JobParameters): Boolean {
        main.removeCallbacks(timeout)
        engine?.destroy()
        engine = null
        this.params = null
        Log.e(TAG, "widget drain stopped by the system; the buffer stays for the next drain")
        return false
    }

    private companion object {
        const val TIMEOUT_MS = 60_000L
    }
}
```

- [ ] **Step 4: The channel arm and the manifest**

In `OutsideChannelHandler.kt`, add this arm before `"takeLaunchRoute"`:

```kotlin
                "drainFinished" -> {
                    val done = onDrainFinished
                        ?: throw IllegalStateException("drainFinished outside the headless drain engine")
                    val ok = call.argument<Boolean>("ok") ?: throw IllegalArgumentException("missing ok")
                    result.success(null)
                    done(ok)
                }
```

In `AndroidManifest.xml`, inside `<application>`, add:

```xml
        <service
            android:name=".widget.DrainJobService"
            android:exported="false"
            android:permission="android.permission.BIND_JOB_SERVICE" />
```

- [ ] **Step 5: Build**

Run, from `app/`: `flutter build apk --debug`. From `app/android/`: `./gradlew :app:testDebugUnitTest`. From the repo root: `dart analyze --fatal-infos`. Expected: green.

- [ ] **Step 6: Commit and fast-forward**

```bash
git add app/android/app/src/main
git commit -m "$(cat <<'EOF'
feat(widget): the drain job hands off to the app or boots drainMain

After a widget tap, one fixed-id JobScheduler job (expedited on 12+)
drains the buffer: through the live app engine via drainNow when its
Dart side is ready, otherwise in a headless FlutterEngine at drainMain,
destroyed on drainFinished or after 60 s. It never reschedules itself,
so a persistent failure cannot loop; after a clean drain it re-enqueues
only for taps that arrived meanwhile, and a running drain is never
stopped by the next tap.

No host test exists for a JobService; built here, verified on device in
Task 17 (drain latency with the app killed, and whether Samsung defers
the job).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/drain-job
```

---
### Task 15: The add-expense dialog

Slug: `expense-dialog`. Spec §7, ruling R8. There is no host test for the activity. Its parsing is `AmountParser`, which has JUnit tests from Task 12. Verified on device in Task 17.

**Files:**
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetSnapshot.kt`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/ExpenseEntryActivity.kt`
- Create: `app/android/app/src/main/res/layout/activity_expense_entry.xml`
- Create: `app/android/app/src/main/res/drawable/entry_chip.xml`, `app/android/app/src/main/res/color/entry_chip_text.xml`
- Create: `app/android/app/src/main/res/values/colors.xml`, `app/android/app/src/main/res/values-night/colors.xml`
- Modify: `app/android/app/src/main/res/values/styles.xml`, `app/android/app/src/main/res/values-night/styles.xml`, `AndroidManifest.xml`

**Interfaces:**
- Consumes:
  - `WidgetBuffer.readSnapshot` and `appendExpense`, and `AmountParser` (Task 12).
  - `DrainScheduler.enqueue` (Task 14).
- Produces, for Task 16:
  - `WidgetSnapshot.read(context): WidgetSnapshot?`, with null for both the loading and the error state, and `WidgetSnapshot.parse(json)`.
  - `WidgetSnapshot.string(key)`.
  - `data class SnapTracker(id, name, color, type, perTap, unit, todayTotal)` and `data class SnapChip(id, name)`.
  - The colour resources `nimbus_widget_bg`, `_text`, `_muted`, `_accent` and `_on_accent`.

- [ ] **Step 1: Branch and tag**

```bash
git checkout -b feat/expense-dialog phase/6-outside-the-app
git tag pre-expense-dialog phase/6-outside-the-app
```

- [ ] **Step 2: The snapshot reader**

Create `app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetSnapshot.kt`:

```kotlin
package com.nimbustats.app.widget

import android.content.Context
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import org.json.JSONObject

data class SnapTracker(
    val id: String,
    val name: String,
    val color: Int,
    val type: String,
    val perTap: Double,
    val unit: String?,
    val todayTotal: Double,
)

data class SnapChip(val id: String, val name: String)

/** `widget_snapshot.json` as native reads it (spec §6.1). Dart writes it, and native only reads. */
class WidgetSnapshot(
    val dayKey: Int,
    val localeTag: String,
    val rtl: Boolean,
    val currencyDecimalDigits: Int,
    val currencyLabel: String,
    val trackers: List<SnapTracker>,
    val chips: List<SnapChip>,
    private val strings: Map<String, String>,
) {
    /** A label Dart sent. A missing one breaks the contract, so it throws and the caller shows the error state. */
    fun string(key: String): String = strings[key] ?: throw IllegalStateException("the snapshot has no string $key")

    companion object {
        private const val VERSION = 1

        /**
         * The current snapshot, or null. Null means either:
         * - there is none yet, which is the loading state; or
         * - it does not read, which is the error state. The cause is logged, and the next app
         *   start rewrites the snapshot (spec §6.5).
         */
        fun read(context: Context): WidgetSnapshot? {
            val json = WidgetBuffer.readSnapshot(context) ?: return null
            return try {
                parse(json)
            } catch (error: Exception) {
                Log.e(TAG, "widget snapshot unreadable; showing the loading state until the app rewrites it", error)
                null
            }
        }

        fun parse(json: String): WidgetSnapshot {
            val root = JSONObject(json)
            val version = root.getInt("v")
            require(version == VERSION) { "snapshot version $version is not $VERSION" }
            val currency = root.getJSONObject("currency")
            val strings = root.getJSONObject("strings")
            val trackers = root.getJSONArray("trackers")
            val chips = root.getJSONArray("chips")
            return WidgetSnapshot(
                dayKey = root.getInt("dayKey"),
                localeTag = root.getString("localeTag"),
                rtl = root.getBoolean("rtl"),
                currencyDecimalDigits = currency.getInt("decimalDigits"),
                currencyLabel = currency.getString("label"),
                trackers = List(trackers.length()) { i ->
                    val t = trackers.getJSONObject(i)
                    SnapTracker(
                        id = t.getString("id"),
                        name = t.getString("name"),
                        color = t.getLong("color").toInt(), // ARGB stored as an unsigned 32-bit number
                        type = t.getString("type"),
                        perTap = t.getDouble("perTap"),
                        unit = if (t.isNull("unit")) null else t.getString("unit"),
                        todayTotal = t.getDouble("todayTotal"),
                    )
                },
                chips = List(chips.length()) { i ->
                    val c = chips.getJSONObject(i)
                    SnapChip(c.getString("id"), c.getString("name"))
                },
                strings = strings.keys().asSequence().associateWith { strings.getString(it) },
            )
        }
    }
}
```

- [ ] **Step 3: Colours, chip drawables, the dialog theme**

These colours are the app's tokens: the seed `#2E7D64`, and the neutral and dark-income colours from `nimbus_design/lib/src/colors.dart`.

Create `app/android/app/src/main/res/values/colors.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Phase 6 widget and dialog, light. -->
    <color name="nimbus_widget_bg">#FFF7F9F7</color>
    <color name="nimbus_widget_text">#FF1A1C1B</color>
    <color name="nimbus_widget_muted">#FF5A5F5C</color>
    <color name="nimbus_widget_accent">#FF2E7D64</color>
    <color name="nimbus_widget_on_accent">#FFFFFFFF</color>
</resources>
```

Create `app/android/app/src/main/res/values-night/colors.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Phase 6 widget and dialog, dark. -->
    <color name="nimbus_widget_bg">#FF1A1C1B</color>
    <color name="nimbus_widget_text">#FFE2E3E0</color>
    <color name="nimbus_widget_muted">#FFA8B0AC</color>
    <color name="nimbus_widget_accent">#FF6EE7B7</color>
    <color name="nimbus_widget_on_accent">#FF0F2A20</color>
</resources>
```

Create `app/android/app/src/main/res/drawable/entry_chip.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<selector xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:state_checked="true">
        <shape android:shape="rectangle">
            <corners android:radius="16dp" />
            <solid android:color="@color/nimbus_widget_accent" />
            <padding android:left="16dp" android:right="16dp" />
        </shape>
    </item>
    <item>
        <shape android:shape="rectangle">
            <corners android:radius="16dp" />
            <stroke android:width="1dp" android:color="@color/nimbus_widget_muted" />
            <padding android:left="16dp" android:right="16dp" />
        </shape>
    </item>
</selector>
```

Create `app/android/app/src/main/res/color/entry_chip_text.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<selector xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:color="@color/nimbus_widget_on_accent" android:state_checked="true" />
    <item android:color="@color/nimbus_widget_text" />
</selector>
```

In `app/android/app/src/main/res/values/styles.xml`, add before `</resources>`:

```xml
    <!-- Phase 6: the widget's add-expense dialog. Translucent, so the home
         screen stays behind it; a tap outside cancels. -->
    <style name="EntryDialogTheme" parent="@android:style/Theme.DeviceDefault.Light.Dialog">
        <item name="android:windowIsTranslucent">true</item>
        <item name="android:windowNoTitle">true</item>
        <item name="android:windowCloseOnTouchOutside">true</item>
        <item name="android:windowMinWidthMajor">90%</item>
        <item name="android:windowMinWidthMinor">90%</item>
    </style>
```

In `app/android/app/src/main/res/values-night/styles.xml`, add the same style with `parent="@android:style/Theme.DeviceDefault.Dialog"`.

- [ ] **Step 4: The layout**

Create `app/android/app/src/main/res/layout/activity_expense_entry.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/entry_root"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:padding="24dp">

    <TextView
        android:id="@+id/entry_title"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:textAlignment="viewStart"
        android:textColor="@color/nimbus_widget_text"
        android:textSize="20sp" />

    <EditText
        android:id="@+id/entry_amount"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        android:imeOptions="actionDone"
        android:importantForAutofill="no"
        android:inputType="number"
        android:minHeight="48dp"
        android:textAlignment="viewStart"
        android:textSize="24sp" />

    <HorizontalScrollView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        android:scrollbars="none">

        <LinearLayout
            android:id="@+id/entry_chips"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:orientation="horizontal" />
    </HorizontalScrollView>

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        android:gravity="end"
        android:orientation="horizontal">

        <Button
            android:id="@+id/entry_cancel"
            style="?android:attr/buttonBarButtonStyle"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:minHeight="48dp" />

        <Button
            android:id="@+id/entry_save"
            style="?android:attr/buttonBarButtonStyle"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:minHeight="48dp" />
    </LinearLayout>
</LinearLayout>
```

- [ ] **Step 5: The activity**

Create `app/android/app/src/main/kotlin/com/nimbustats/app/widget/ExpenseEntryActivity.kt`:

```kotlin
package com.nimbustats.app.widget

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import android.widget.ToggleButton
import com.nimbustats.app.MainActivity
import com.nimbustats.app.R

/**
 * The widget's add-expense dialog (spec §7).
 *
 * It is native end to end: no Flutter engine starts, and no database opens. Save appends one
 * buffer line, enqueues the drain, shows "saved" and closes, with no spinner. Cancel, back or a
 * tap outside closes without writing.
 *
 * It has its own task affinity and is excluded from recents, so it never brings the app forward.
 * Its direction and every word come from the snapshot.
 */
class ExpenseEntryActivity : Activity() {
    private lateinit var snapshot: WidgetSnapshot
    private val chips = mutableListOf<ToggleButton>()
    private var categoryId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val read = WidgetSnapshot.read(this)
        if (read == null) {
            // No snapshot: the widget is in its loading state, which opens the app instead.
            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            finish()
            return
        }
        snapshot = read
        setContentView(R.layout.activity_expense_entry)
        window.decorView.layoutDirection =
            if (snapshot.rtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR

        findViewById<TextView>(R.id.entry_title).text = snapshot.string("entryTitle")
        val amount = findViewById<EditText>(R.id.entry_amount)
        amount.hint = snapshot.currencyLabel
        amount.inputType = if (snapshot.currencyDecimalDigits > 0) {
            InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL
        } else {
            InputType.TYPE_CLASS_NUMBER
        }
        val save = findViewById<Button>(R.id.entry_save).apply {
            text = snapshot.string("save")
            isEnabled = false
            setOnClickListener { save(amount.text.toString()) }
        }
        findViewById<Button>(R.id.entry_cancel).apply {
            text = snapshot.string("cancel")
            setOnClickListener { finish() }
        }
        amount.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
            override fun afterTextChanged(s: Editable?) {
                save.isEnabled = parse(s?.toString().orEmpty()) != null
            }
        })
        amount.setOnEditorActionListener { _, action, _ ->
            (action == EditorInfo.IME_ACTION_DONE && save.isEnabled).also { if (it) save(amount.text.toString()) }
        }

        val row = findViewById<LinearLayout>(R.id.entry_chips)
        for (chip in snapshot.chips) {
            val button = ToggleButton(this).apply {
                textOn = chip.name
                textOff = chip.name
                text = chip.name
                minHeight = dp(48)
                setBackgroundResource(R.drawable.entry_chip)
                setTextColor(getColorStateList(R.color.entry_chip_text))
                // Single-select; tapping the chosen one again leaves no chip, which is Uncategorized.
                setOnCheckedChangeListener { view, checked ->
                    if (checked) {
                        chips.filter { it !== view }.forEach { it.isChecked = false }
                        categoryId = chip.id
                    } else if (categoryId == chip.id) {
                        categoryId = null
                    }
                }
            }
            chips += button
            row.addView(
                button,
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                    .apply { marginEnd = dp(8) },
            )
        }

        amount.requestFocus()
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
    }

    private fun parse(text: String): Long? = AmountParser.parse(text, snapshot.currencyDecimalDigits)

    private fun save(text: String) {
        val minor = parse(text) ?: return
        WidgetBuffer.appendExpense(this, System.currentTimeMillis(), minor, categoryId)
        DrainScheduler.enqueue(this)
        // The application context: the toast outlives this dialog.
        Toast.makeText(applicationContext, snapshot.string("saved"), Toast.LENGTH_SHORT).show()
        finish()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
```

- [ ] **Step 6: The manifest**

Inside `<application>`, add:

```xml
        <!-- Not exported: only the widget's own PendingIntent opens it. Its
             own task affinity keeps MainActivity in the background. -->
        <activity
            android:name=".widget.ExpenseEntryActivity"
            android:excludeFromRecents="true"
            android:exported="false"
            android:noHistory="true"
            android:taskAffinity="com.nimbustats.app.entry"
            android:theme="@style/EntryDialogTheme"
            android:windowSoftInputMode="stateAlwaysVisible|adjustResize" />
```

- [ ] **Step 7: Build**

Run, from `app/`: `flutter build apk --debug`. From `app/android/`: `./gradlew :app:testDebugUnitTest`. Expected: green.

- [ ] **Step 8: Commit and fast-forward**

```bash
git add app/android/app/src/main
git commit -m "$(cat <<'EOF'
feat(widget): the add-expense dialog, native end to end

A translucent dialog activity, excluded from recents with its own task
affinity, so adding an expense from the widget never starts Flutter,
opens the database or brings the app forward: the amount (focused,
number keyboard, parsed by AmountParser in the snapshot's currency) and
up to four predicted category chips (none chosen is Uncategorized).
Save appends one buffer line, enqueues the drain, shows "Saved" and
closes. Every word and the layout direction come from Dart's snapshot.

Colours are the app's tokens, light and night. Verified on device in
Task 17, which times the cold path.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/expense-dialog
```

---

### Task 16: The home-screen widget — rows, taps, states, midnight

Slug: `home-widget`. Spec §6.2–§6.5, ruling R9. There is no host test for `RemoteViews`. Its arithmetic is `PendingOverlay`, which has JUnit tests. Verified on device in Task 17.

**Files:**
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetRenderer.kt`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/ExpenseWidgetProvider.kt`
- Create: `app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetActionReceiver.kt`
- Create: `app/android/app/src/main/res/layout/widget_expense.xml`, `app/android/app/src/main/res/layout/widget_tracker_row.xml`, `app/android/app/src/main/res/layout/widget_loading.xml`
- Create: `app/android/app/src/main/res/xml/expense_widget_info.xml`
- Create: `app/android/app/src/main/res/drawable/widget_background.xml`, `app/android/app/src/main/res/drawable/widget_button.xml`, `app/android/app/src/main/res/drawable/widget_dot.xml`, `app/android/app/src/main/res/drawable/ic_widget_add.xml`, `app/android/app/src/main/res/drawable/ic_widget_done.xml`
- Modify:
  - `notifications/ReminderScheduler.kt` (midnight arming in `rearm`)
  - `notifications/RearmReceiver.kt` (re-render)
  - `OutsideChannelHandler.kt` (render after `writeSnapshot` and `commitDrain`)
  - `AndroidManifest.xml`

**Interfaces:**
- Consumes:
  - `WidgetSnapshot` (Task 15).
  - `WidgetBuffer.pendingTaps` and `appendTrackerTap`, and `PendingOverlay` (Task 12).
  - `DrainScheduler` (Task 14).
  - `ReminderTime.nextMidnight` (Task 9).
- Produces:
  - `WidgetRenderer.renderAll(context)`.
  - `WidgetActionReceiver.tapIntent(context, trackerId)` and `WidgetActionReceiver.midnightIntent(context)`.
  - `ReminderScheduler.armMidnight(context)` and `ReminderScheduler.cancelMidnight(context)`.

- [ ] **Step 1: Branch and tag**

```bash
git checkout -b feat/home-widget phase/6-outside-the-app
git tag pre-home-widget phase/6-outside-the-app
```

- [ ] **Step 2: Drawables**

Create `res/drawable/widget_background.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:radius="16dp" />
    <solid android:color="@color/nimbus_widget_bg" />
</shape>
```

Create `res/drawable/widget_button.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <corners android:radius="24dp" />
    <solid android:color="@color/nimbus_widget_accent" />
</shape>
```

Create `res/drawable/widget_dot.xml`. It is white, and each row tints it with its tracker's colour:

```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval">
    <size android:width="12dp" android:height="12dp" />
    <solid android:color="#FFFFFFFF" />
</shape>
```

Create `res/drawable/ic_widget_add.xml`:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="@color/nimbus_widget_accent"
        android:pathData="M19,13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z" />
</vector>
```

Create `res/drawable/ic_widget_done.xml`:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="@color/nimbus_widget_accent"
        android:pathData="M9,16.17L4.83,12l-1.42,1.41L9,19 21,7l-1.41,-1.41z" />
</vector>
```

`widget_dot.xml`'s `#FFFFFFFF` is a resource colour that the row's `setColorFilter` replaces. The "no raw Color literal" rule (`ux_rules_test`) covers Dart only.

- [ ] **Step 3: Layouts and the provider info**

Create `res/layout/widget_expense.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/widget_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/widget_background"
    android:orientation="vertical"
    android:padding="12dp">

    <TextView
        android:id="@+id/widget_add_expense"
        android:layout_width="match_parent"
        android:layout_height="48dp"
        android:background="@drawable/widget_button"
        android:gravity="center"
        android:textColor="@color/nimbus_widget_on_accent"
        android:textSize="16sp"
        android:textStyle="bold" />

    <TextView
        android:id="@+id/widget_empty"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:layout_marginTop="8dp"
        android:textAlignment="viewStart"
        android:textColor="@color/nimbus_widget_muted"
        android:textSize="14sp"
        android:visibility="gone" />

    <LinearLayout
        android:id="@+id/widget_rows"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical" />
</LinearLayout>
```

Create `res/layout/widget_tracker_row.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="48dp"
    android:gravity="center_vertical"
    android:orientation="horizontal">

    <ImageView
        android:id="@+id/row_dot"
        android:layout_width="12dp"
        android:layout_height="12dp"
        android:importantForAccessibility="no"
        android:src="@drawable/widget_dot" />

    <TextView
        android:id="@+id/row_name"
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_marginStart="12dp"
        android:layout_weight="1"
        android:ellipsize="end"
        android:maxLines="1"
        android:textAlignment="viewStart"
        android:textColor="@color/nimbus_widget_text"
        android:textSize="16sp" />

    <TextView
        android:id="@+id/row_value"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginStart="8dp"
        android:importantForAccessibility="no"
        android:textColor="@color/nimbus_widget_text"
        android:textSize="16sp"
        android:textStyle="bold" />

    <ImageView
        android:id="@+id/row_add"
        android:layout_width="48dp"
        android:layout_height="48dp"
        android:padding="12dp"
        android:src="@drawable/ic_widget_add" />

    <ImageView
        android:id="@+id/row_done"
        android:layout_width="48dp"
        android:layout_height="48dp"
        android:padding="12dp"
        android:src="@drawable/ic_widget_done"
        android:visibility="gone" />
</LinearLayout>
```

Create `res/layout/widget_loading.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/widget_loading_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/widget_background">

    <!-- The loading state carries no text: native code has no strings of
         its own (spec §6.5). The widget picker names the widget. -->
    <ImageView
        android:layout_width="48dp"
        android:layout_height="48dp"
        android:layout_gravity="center"
        android:importantForAccessibility="no"
        android:src="@mipmap/ic_launcher" />
</FrameLayout>
```

Create `res/xml/expense_widget_info.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- One resizable widget, 4x2 by default (spec §6.4). No polling:
     updatePeriodMillis is 0, and the widget re-renders on snapshot writes,
     taps and the midnight alarm. -->
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:initialLayout="@layout/widget_loading"
    android:minHeight="110dp"
    android:minResizeHeight="100dp"
    android:minResizeWidth="180dp"
    android:minWidth="250dp"
    android:previewLayout="@layout/widget_loading"
    android:resizeMode="horizontal|vertical"
    android:targetCellHeight="2"
    android:targetCellWidth="4"
    android:updatePeriodMillis="0"
    android:widgetCategory="home_screen" />
```

- [ ] **Step 4: The renderer**

Create `app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetRenderer.kt`:

```kotlin
package com.nimbustats.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.icu.text.NumberFormat
import android.icu.util.ULocale
import android.os.Build
import android.util.Log
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import com.nimbustats.app.MainActivity
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import com.nimbustats.app.R
import java.time.Instant
import java.time.ZoneId

/**
 * Builds the widget from the snapshot plus the pending taps (spec §6.3–§6.5).
 *
 * | State     | When                                     | Shows                                    |
 * |-----------|------------------------------------------|------------------------------------------|
 * | loading   | no snapshot yet                          | the app icon; a tap opens the app        |
 * | error     | snapshot unreadable                      | as loading, plus a logged cause          |
 * | empty     | no eligible trackers                     | "+ Expense" and the empty-trackers text  |
 * | populated | otherwise                                | "+ Expense" and one row per tracker      |
 *
 * Android 12+ gets responsive layouts with 1 to 4 rows by height; below 12 there are 2 rows.
 * Numbers are formatted by ICU for the snapshot's language, with at most two fraction digits.
 * That is the CLDR data the app's `NumberFormat.decimalPattern` is built on (spec §6.2).
 */
object WidgetRenderer {
    private class Row(val tracker: SnapTracker, val value: String, val done: Boolean, val description: String)

    fun renderAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, ExpenseWidgetProvider::class.java))
        if (ids.isEmpty()) return
        val views = build(context)
        for (id in ids) manager.updateAppWidget(id, views)
    }

    private fun build(context: Context): RemoteViews {
        val snapshot = WidgetSnapshot.read(context) ?: return loading(context)
        return try {
            val rows = rows(context, snapshot)
            if (Build.VERSION.SDK_INT >= 31) {
                RemoteViews(
                    mapOf(
                        SizeF(180f, 100f) to layout(context, snapshot, rows, 1),
                        SizeF(180f, 150f) to layout(context, snapshot, rows, 2),
                        SizeF(180f, 200f) to layout(context, snapshot, rows, 3),
                        SizeF(180f, 250f) to layout(context, snapshot, rows, 4),
                    ),
                )
            } else {
                layout(context, snapshot, rows, 2)
            }
        } catch (error: Exception) {
            Log.e(TAG, "widget render failed; showing the loading state", error)
            loading(context)
        }
    }

    private fun rows(context: Context, snapshot: WidgetSnapshot): List<Row> {
        val format = NumberFormat.getInstance(ULocale.forLanguageTag(snapshot.localeTag)).apply {
            maximumFractionDigits = 2
        }
        val pending = WidgetBuffer.pendingTaps(context)
        val zone = ZoneId.systemDefault()
        val now = Instant.now()
        return snapshot.trackers.map { tracker ->
            val value = PendingOverlay.todayValue(
                snapshot.dayKey, tracker.todayTotal, tracker.perTap, tracker.id, pending, zone, now,
            )
            val done = PendingOverlay.isDone(tracker.type, value)
            // As TrackerFormat.total writes it: a quantity carries its unit.
            val text = tracker.unit?.let { "${format.format(value)} $it" } ?: format.format(value)
            val description = if (done) {
                snapshot.string("trackerDone").replace("{name}", tracker.name)
            } else {
                snapshot.string("trackerAdd").replace("{name}", tracker.name).replace("{total}", text)
            }
            Row(tracker, text, done, description)
        }
    }

    private fun layout(context: Context, snapshot: WidgetSnapshot, rows: List<Row>, capacity: Int): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_expense).apply {
            setInt(
                R.id.widget_root,
                "setLayoutDirection",
                if (snapshot.rtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR,
            )
            setTextViewText(R.id.widget_add_expense, snapshot.string("addExpense"))
            setOnClickPendingIntent(R.id.widget_add_expense, entryIntent(context))
            removeAllViews(R.id.widget_rows)
            if (rows.isEmpty()) {
                setViewVisibility(R.id.widget_empty, View.VISIBLE)
                setTextViewText(R.id.widget_empty, snapshot.string("emptyTrackers"))
            } else {
                setViewVisibility(R.id.widget_empty, View.GONE)
                for (row in rows.take(capacity)) addView(R.id.widget_rows, rowViews(context, row))
            }
        }

    private fun rowViews(context: Context, row: Row): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_tracker_row).apply {
            setInt(R.id.row_dot, "setColorFilter", row.tracker.color)
            setTextViewText(R.id.row_name, row.tracker.name)
            // A boolean says it with the tick, not a number.
            setViewVisibility(R.id.row_value, if (row.tracker.type == "boolean") View.GONE else View.VISIBLE)
            setTextViewText(R.id.row_value, row.value)
            if (row.done) {
                setViewVisibility(R.id.row_add, View.GONE)
                setViewVisibility(R.id.row_done, View.VISIBLE)
                setContentDescription(R.id.row_done, row.description)
            } else {
                setViewVisibility(R.id.row_done, View.GONE)
                setViewVisibility(R.id.row_add, View.VISIBLE)
                setContentDescription(R.id.row_add, row.description)
                setOnClickPendingIntent(R.id.row_add, WidgetActionReceiver.tapIntent(context, row.tracker.id))
            }
        }

    private fun loading(context: Context): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_loading).apply {
            setOnClickPendingIntent(
                R.id.widget_loading_root,
                PendingIntent.getActivity(
                    context,
                    0,
                    Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }

    private fun entryIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        1,
        Intent(context, ExpenseEntryActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_IMMUTABLE,
    )
}
```

- [ ] **Step 5: The provider and the action receiver**

Create `app/android/app/src/main/kotlin/com/nimbustats/app/widget/ExpenseWidgetProvider.kt`:

```kotlin
package com.nimbustats.app.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import com.nimbustats.app.notifications.ReminderScheduler

/**
 * The home-screen widget. Exported only for the system's widget broadcasts. Taps go to the
 * non-exported [WidgetActionReceiver] (ruling R9), so no other app can log a tap.
 */
class ExpenseWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        WidgetRenderer.renderAll(context)
        ReminderScheduler.armMidnight(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        WidgetRenderer.renderAll(context)
    }

    override fun onEnabled(context: Context) = ReminderScheduler.armMidnight(context)

    override fun onDisabled(context: Context) = ReminderScheduler.cancelMidnight(context)
}
```

Create `app/android/app/src/main/kotlin/com/nimbustats/app/widget/WidgetActionReceiver.kt`:

```kotlin
package com.nimbustats.app.widget

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import com.nimbustats.app.OutsideChannelHandler.Companion.TAG
import com.nimbustats.app.notifications.ReminderScheduler

/**
 * The widget's own actions. It is not exported: only this app's PendingIntents reach it.
 * - **A tracker tap** appends one buffer line, re-renders with the tap counted, and enqueues the
 *   drain. Nothing waits for Flutter.
 * - **Local midnight** re-renders, so yesterday's totals clear, and arms the next midnight.
 */
class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_TAP -> {
                val trackerId = intent.getStringExtra(EXTRA_TRACKER)
                if (trackerId == null) {
                    Log.e(TAG, "widget tap without a tracker id; nothing logged")
                    return
                }
                WidgetBuffer.appendTrackerTap(context, System.currentTimeMillis(), trackerId)
                WidgetRenderer.renderAll(context)
                DrainScheduler.enqueue(context)
            }
            ACTION_MIDNIGHT -> {
                WidgetRenderer.renderAll(context)
                ReminderScheduler.armMidnight(context)
            }
            else -> Log.e(TAG, "unknown widget action ${intent.action}")
        }
    }

    companion object {
        private const val ACTION_TAP = "com.nimbustats.app.widget.TAP"
        private const val ACTION_MIDNIGHT = "com.nimbustats.app.widget.MIDNIGHT"
        private const val EXTRA_TRACKER = "trackerId"

        /** One intent per tracker. The data URI keeps them distinct, so each row logs its own tracker. */
        fun tapIntent(context: Context, trackerId: String): PendingIntent = PendingIntent.getBroadcast(
            context,
            trackerId.hashCode(),
            Intent(context, WidgetActionReceiver::class.java)
                .setAction(ACTION_TAP)
                .setData(Uri.parse("nimbustats://tracker/$trackerId"))
                .putExtra(EXTRA_TRACKER, trackerId),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        fun midnightIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, WidgetActionReceiver::class.java).setAction(ACTION_MIDNIGHT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
```

- [ ] **Step 6: Midnight, re-arm, render after writes**

In `ReminderScheduler.kt`:
1. Add the imports:

```kotlin
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import com.nimbustats.app.widget.ExpenseWidgetProvider
import com.nimbustats.app.widget.WidgetActionReceiver
```

2. Change `rearm` to:

```kotlin
    /** Everything this app keeps armed, re-armed from the local clock now. */
    fun rearm(context: Context) {
        armReminder(context)
        armMidnight(context)
    }
```

3. Add:

```kotlin
    /**
     * The widget's local-midnight refresh (spec §6.3). It uses inexact, non-waking `RTC`: a
     * sleeping phone shows the widget at its next wake, and yesterday's totals clear then. It is
     * armed only while a widget is placed.
     */
    fun armMidnight(context: Context) {
        val widgets = AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, ExpenseWidgetProvider::class.java))
        if (widgets.isEmpty()) {
            cancelMidnight(context)
            return
        }
        context.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(
            AlarmManager.RTC,
            ReminderTime.nextMidnight(ZonedDateTime.now()).toInstant().toEpochMilli(),
            WidgetActionReceiver.midnightIntent(context),
        )
    }

    fun cancelMidnight(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(WidgetActionReceiver.midnightIntent(context))
    }
```

In `RearmReceiver.kt`:
1. Add `import com.nimbustats.app.widget.WidgetRenderer`.
2. After `ReminderScheduler.rearm(context)`, add:

```kotlin
        // A zone or clock change can move today; re-render so the rows follow it.
        WidgetRenderer.renderAll(context)
```

In `OutsideChannelHandler.kt`:
1. Add `import com.nimbustats.app.widget.WidgetRenderer`.
2. In both the `"writeSnapshot"` arm and the `"commitDrain"` arm, insert `WidgetRenderer.renderAll(context)` directly before `result.success(null)`.

- [ ] **Step 7: The manifest**

Inside `<application>`, add:

```xml
        <!-- The home-screen widget. Exported for the system's update
             broadcast only; taps go to the receiver below (ruling R9). -->
        <receiver
            android:name=".widget.ExpenseWidgetProvider"
            android:exported="true"
            android:label="NimbuStats">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/expense_widget_info" />
        </receiver>
        <receiver
            android:name=".widget.WidgetActionReceiver"
            android:exported="false" />
```

The label is the brand name, untranslated, as `appTitle` is in both ARB files.

- [ ] **Step 8: Build and every host suite**

Run each of these:

| Where | Command |
|---|---|
| `app/` | `flutter build apk --debug` |
| `app/android/` | `./gradlew :app:testDebugUnitTest` |
| repo root | `dart analyze --fatal-infos` |
| repo root | `dart test test/architecture_test.dart` |
| `packages/nimbus_domain/` | `dart test` |
| `packages/nimbus_data/` | `dart test` |
| `app/` | `flutter test --no-pub --concurrency=4` |

Expected: all green.

- [ ] **Step 9: Commit and fast-forward**

```bash
git add app/android/app/src/main
git commit -m "$(cat <<'EOF'
feat(widget): the home-screen widget's rows, taps, states and midnight

A resizable 4x2 widget rendered natively from the snapshot: "+ Expense"
(the dialog) over one row per tracker -- colour dot, name, today's
value formatted by ICU for the app's language, a 48 dp [+], or a tick
for a boolean done today. A tap appends a buffer line, re-renders with
the tap counted (snapshot total if today's, plus today's pending taps)
and enqueues the drain; Flutter is never on the tap path. Loading,
error, empty and populated states; layout direction from the snapshot;
light and dark from the system; 1-4 rows by height on Android 12+.

Taps go to a non-exported receiver, so no other app can log one. A
local-midnight RTC alarm clears yesterday's totals and is re-armed
after reboot, zone and clock changes. Verified on device in Task 17.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only feat/home-widget
```

---

### Task 17: On-device verification on the Galaxy A53

Slug: none. This task records results and commits nothing yet. Spec §11, and the brief's definition of done.

This task needs the operator. **Stop and ask before each of these:**
- driving the phone at all: confirm the A53 is free and unlocked;
- the reboot (step 9);
- the time-zone change (step 10), which the operator makes by hand and restores.

Bugs found here become numbered DEFERRED items (D26 and up). A bug gets a focused fix commit only if it blocks this verification. Write every result to `<scratchpad>/phase6-gate.md` as you go, with exact command output.

**Before starting:**
- Run `adb` as `/c/dev/android-sdk/platform-tools/adb.exe`, set as `ADB` below.
- Prefix device paths with `MSYS_NO_PATHCONV=1` in Git Bash.
- A uiautomator dump that prints `ERROR: null root node` read nothing. Retry it, and never trust the stale file left behind.

- [ ] **Step 1: Device and build**

```bash
ADB=/c/dev/android-sdk/platform-tools/adb.exe
$ADB devices                      # expect: RZCT209E3QX  device
curl -s https://api.ipify.org; echo
cd app && flutter build apk --profile && cd ..
```

Before installing, copy the database out as a pre-upgrade baseline. Include `-wal` and `-shm`; they may be absent before Phase 6.

```bash
mkdir -p "$SCRATCH/pre"
for f in nimbustats.sqlite nimbustats.sqlite-wal nimbustats.sqlite-shm; do
  MSYS_NO_PATHCONV=1 $ADB exec-out run-as com.nimbustats.app cat app_flutter/$f > "$SCRATCH/pre/$f" 2>/dev/null || true
done
python -I -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute('select count(*) from transactions').fetchone(), c.execute('select count(*) from tracker_entries').fetchone())" "$SCRATCH/pre/nimbustats.sqlite"
$ADB install -r app/build/app/outputs/flutter-apk/app-profile.apk
```

Here `SCRATCH` is this session's scratchpad. Python's `sqlite3` runs only on scratch copies, never on the phone's files.

Expected: `Success`. Open the app once, then pull the database again. The same counts must read back, and `PRAGMA journal_mode` on the copy must read `wal`. A `nimbustats.sqlite-wal` should now exist on the phone: check with `$ADB shell run-as com.nimbustats.app ls app_flutter`.

- [ ] **Step 2: Place the widget** (by hand)

Ask the operator to long-press the home screen, open Widgets, find NimbuStats, and place it at 4×2. Then take a screenshot:

```bash
$ADB exec-out screencap -p > "$SCRATCH/widget-fa.png"
MSYS_NO_PATHCONV=1 $ADB exec-out run-as com.nimbustats.app cat files/widget_snapshot.json
```

Expected: the populated state in Persian, right to left, with Persian digits. The snapshot `v` is 1 and `localeTag` is `fa`. Compare each row's digits with the Trackers tab.

- [ ] **Step 3: The cold path** (spec §11, row 1)

```bash
$ADB shell input keyevent KEYCODE_HOME
$ADB shell am kill com.nimbustats.app      # background kill; not force-stop, which would clear alarms
$ADB logcat -c
```

Ask the operator to tap "+ Expense" on the widget. Then:

```bash
$ADB logcat -d | grep -E "Displayed com.nimbustats.app|MainActivity|flutter" | head
```

Expected:
- one line `ActivityTaskManager: Displayed com.nimbustats.app/.widget.ExpenseEntryActivity: +NNNms`. Record `NNN`;
- no `MainActivity` start, and no `flutter` line before the dialog shows.

Repeat three times, and record each.

- [ ] **Step 4: Save an expense and time the background path**

The operator types an amount: `12500` in fa digits from the Samsung keyboard if it offers them. They pick no chip, then tap Save. Then:

```bash
sleep 20
MSYS_NO_PATHCONV=1 $ADB exec-out run-as com.nimbustats.app cat files/widget_buffer.jsonl
for f in nimbustats.sqlite nimbustats.sqlite-wal nimbustats.sqlite-shm; do
  MSYS_NO_PATHCONV=1 $ADB exec-out run-as com.nimbustats.app cat app_flutter/$f > "$SCRATCH/$f"
done
python -I -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute(\"select id, amount, source, category_id, occurred_at_utc, created_at, created_at-occurred_at_utc as drain_ms from transactions order by created_at desc limit 1\").fetchone())" "$SCRATCH/nimbustats.sqlite"
```

Expected:
- the buffer is empty;
- the newest row has `source = widget`, the typed amount and Uncategorized;
- `drain_ms` is the tap-to-row latency with the app killed. Record it, along with whether Samsung deferred the job: a long `drain_ms`, or `dumpsys jobscheduler | grep -A3 com.nimbustats`.

- [ ] **Step 5: One entry per tracker tap** (spec §11, row 2)

Ask the operator to tap a counter's [+] five times quickly, and a boolean's [+] once. The boolean's [+] then turns into a tick. Wait 20 s, pull the database, and count:

```bash
python -I -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute(\"select tracker_id, count(*) from tracker_entries where deleted_at is null and created_at > (strftime('%s','now')-300)*1000 group by tracker_id\").fetchall())" "$SCRATCH/nimbustats.sqlite"
```

Expected: the counter has exactly 5 new rows, and the boolean exactly 1. The widget's numbers did not jump twice: each tap showed at once and stayed.

- [ ] **Step 6: An 80% crossing → exactly one notification** (spec §11, row 5)

In the app, the operator creates a cap goal on a category with a target just above this month's spending, so one widget expense crosses 80%. Grant the permission when the first-goal ask appears. Kill the app (`am kill`, as in step 3). Then the operator adds a widget expense that crosses 80%. Wait 20 s.

```bash
$ADB shell dumpsys notification --noredact | grep -A12 "pkg=com.nimbustats.app" | grep -E "tag=|android.text=|visibility"
```

Expected: exactly one notification, with tag `goal:<id>` and text `یک هدف نیاز به بررسی دارد` (details are off by default).

Then relaunch the app, open any transaction, edit its note and save. Run `dumpsys notification` again and expect still one notification: recomputation posted nothing. Repeat with the app in the background rather than killed, and expect again exactly one.

- [ ] **Step 7: The discreet setting** (spec §11, row 6)

Turn on Settings → Notifications → "Show details in notifications". Cross a second goal, or another percent, then run `dumpsys notification --noredact` again. Expected: the full text, such as `<name>: ۸۵٪ از سقف این ماه`.

Lock the phone and take a screenshot:

```bash
$ADB exec-out screencap -p > "$SCRATCH/lock.png"
```

Expected on the lock screen: the discreet text only, in both settings. The operator confirms by eye if the lock-screen capture comes back black.

- [ ] **Step 8: Tap-through**

Tap the alert notification and confirm the goal's detail screen opens. Arm the reminder 2 minutes ahead (step 9), let it fire, tap it, and confirm the add-expense screen opens.

- [ ] **Step 9: The reminder survives a reboot** (spec §11, row 3). Ask first.

In Settings → Notifications, switch the reminder on and set the time to now + 4 minutes. Then:

```bash
$ADB shell dumpsys alarm | grep -B1 -A6 "com.nimbustats.app" | grep -E "RTC_WAKEUP|when|origWhen|ReminderReceiver"
```

Ask the operator: "OK to reboot the A53 now? It comes back on its own, and you'll need to unlock it." On a yes:

```bash
$ADB reboot && $ADB wait-for-device && sleep 60
$ADB shell dumpsys alarm | grep -B1 -A6 "com.nimbustats.app" | grep -E "RTC_WAKEUP|when|ReminderReceiver"
```

Expected: the alarm is listed again after boot, at the same local time. Wait for it, then run `dumpsys notification --noredact`, which shows the reminder (tag `reminder`) with `امروز چیزی برای ثبت دارید؟`.

- [ ] **Step 10: The reminder follows a time-zone change** (spec §11, row 4). Ask first, by hand.

Record the zone with `$ADB shell getprop persist.sys.timezone`. Ask the operator to turn off automatic time zone and pick Europe/Istanbul (UTC+3, half an hour behind Tehran's +3:30) under Settings → General management → Date and time. Then run `dumpsys alarm` and expect the trigger instant moved by 30 minutes, so it still lands at the same local wall time. Let it fire.

Ask the operator to restore automatic time zone. Confirm `getprop persist.sys.timezone` reads the recorded zone again, and that `dumpsys alarm` shows the trigger back.

- [ ] **Step 11: Both locales, RTL and LTR** (spec §11, row 7)

In the app, switch the language to English. Go to the home screen, wait for the widget to re-render, then take screenshots `widget-en.png` and, with the dialog open, `dialog-en.png`. Switch back to Persian and take `widget-fa.png` and `dialog-fa.png`.

Expected:
- English is left to right, with Latin digits.
- Persian is right to left, with Persian digits.
- The widget's digits match the Trackers tab in both. Check a quantity with a fraction, such as 0.25 L, to compare the decimal separator.

If the launcher ignores `setLayoutDirection`, the Persian rows read left to right. Record a DEFERRED item for the RTL-variant layout fallback (spec §6.4).

- [ ] **Step 12: Midnight and the theme**

Switch the system dark mode on: the widget and the dialog follow it. Ask the operator to check the widget after the next local midnight: yesterday's totals have cleared. That one can't be shown inside the session. Record it as observed the next morning, or as not observed.

- [ ] **Step 13: Restore the phone**

Ask the operator whether to:
- leave the widget, the reminder and the test goals in place;
- remove the test expenses (by hand, with Undo-free deletes in the app);
- switch dark mode back.

Confirm the time zone is restored. Record the final state in the gate notes.

---

### Task 18: Docs, the Persian review, and the gate

Slug: `phase-6-complete`. CONVENTIONS §5.

**Files:**
- Modify: `docs/phases/CONVENTIONS.md` (ownership rows)
- Modify: `docs/phases/phase-6-outside-the-app.md` (`MessageBuffer` note, gate record)
- Modify: `docs/phases/README.md` (status board)
- Modify: `docs/phases/DEFERRED.md` (items D26 and up, from Task 17, if any)
- Modify: `docs/superpowers/specs/2026-10-12-outside-6-design.md` (status line)

- [ ] **Step 1: The Persian review**

List every new `fa` value with its English key and value. Generate the list with `git diff main -- app/lib/l10n/app_fa.arb | grep '^+ '`. Ask the operator to approve or correct each one, as in Phase 5. Apply the corrections in one commit on `feat/fa-review`, which runs `localization_test` green and fast-forwards. **Do not tag the gate before this approval.**

- [ ] **Step 2: The full definition of done**

Run each of these:

| Where | Command |
|---|---|
| repo root | `dart analyze --fatal-infos` |
| repo root | `dart test test/architecture_test.dart` |
| `packages/nimbus_domain/` | `dart test` |
| `packages/nimbus_data/` | `dart test` |
| `app/` | `flutter test --no-pub --concurrency=4` |
| `app/android/` | `./gradlew :app:testDebugUnitTest` |

Record the test counts. Expected: all green, and an app test count of at least 609, Phase 5's figure, plus this phase's additions.

- [ ] **Step 3: The docs**

```bash
git checkout -b docs/phase-6-complete phase/6-outside-the-app
```

- In `docs/phases/CONVENTIONS.md` §3's table, below the `app/android/**/widget/**` row, add:

```markdown
| `app/lib/features/widget/**` | Phase 6 |
| `app/android/**/notifications/**` | Phase 6 |
```

- In `docs/phases/phase-6-outside-the-app.md`, under "Required reading", replace the `MessageBuffer.kt` bullet with:

```markdown
- ~~`app/android/**/capture/MessageBuffer.kt` (Phase 2)~~ — it does not
  exist: only Phase 2A (pure Dart parsing) shipped. Phase 6 created its
  own buffer (`widget/WidgetBuffer.kt`) on the brief's rule — native
  writes are buffered and drained through the repositories (spec
  `docs/superpowers/specs/2026-10-12-outside-6-design.md`, finding 1).
```

- Append a `### Gate record (2026-MM-DD, Galaxy A53)` section under `## Definition of done`. Tick each checkbox and paste Task 17's measured values:
  - the dialog's `Displayed` times;
  - `drain_ms` with the app killed, and whether Samsung deferred the job;
  - the per-tap row counts;
  - the `dumpsys` notification lines with details off and on;
  - the alarm before and after the reboot and the zone change;
  - the screenshot names;
  - the test counts;
  - ruling R11's known limit, and any DEFERRED items.
- In `docs/phases/README.md`'s status board, set Phase 6 to:

```markdown
| 6 — Outside the app | [phase-6-outside-the-app.md](phase-6-outside-the-app.md) | **Complete** (2026-MM-DD). Home-screen widget (expense dialog and tracker taps, drained exactly once through the repositories by a background job), goal alerts as discreet notifications, and an optional daily reminder that survives reboot and zone changes; verified on the Galaxy A53. minSdk is now 26. Carried forward: <D-items or "none"> | `phase-6-complete` |
```

- In the spec, change the status line to `**Status:** implemented; gate passed 2026-MM-DD (see the brief's gate record).`
- Add each Task 17 finding to `DEFERRED.md` as D26 and up, in the house format: summary-table row, then a section with *what*, *why deferred*, *what unblocks it*.

```bash
git add docs
git commit -m "$(cat <<'EOF'
docs: Phase 6 is complete

Records the A53 gate: the widget's cold path (dialog Displayed times,
no Flutter on the tap path), one row per tap, one notification per
crossing and none on recomputation, discreet text by default and on
the lock screen always, a reminder that survives a reboot and a
time-zone change, and both locales in RTL and LTR. Adds the two Phase
6 ownership rows to CONVENTIONS, corrects the brief's pointer to a
Phase 2 buffer that never shipped, and moves the board.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
git checkout phase/6-outside-the-app && git merge --ff-only docs/phase-6-complete
```

- [ ] **Step 4: Merge and tag.** Ask first.

Use `superpowers:finishing-a-development-branch`, with base branch `main`. On the operator's choice to merge locally:

```bash
git checkout main && git merge --ff-only phase/6-outside-the-app
git tag phase-6-complete
git tag --list 'phase-*-complete'
```

Do not push unless the operator asks.

---

## Self-review notes (for the reviewer of this plan)

- **Spec coverage:**
  - §1 → Tasks 4, 5 and 14
  - §1.1 → Tasks 4, 5, 7, 9, 12, 14 and 16 (every method has a handler arm)
  - §2 → Tasks 2, 12, 13 and 14
  - §3 → Task 1
  - §4 → Tasks 5–8
  - §5 → Task 9
  - §6 → Tasks 11, 12 and 16
  - §7 → Task 15
  - §8 → Tasks 7 and 10
  - §9 → the Global Constraints, plus each task's `reportingFailure` and `Log.e`
  - §10 → the tests in each task, plus the JUnit tests in Tasks 9 and 12
  - §11 → Task 17
  - §12 → nothing out of scope is built
- **Departures from the spec, all named:**
  - R1: `minSdk` 26.
  - R2: the pragmas run in `setup`, not `beforeOpen`.
  - R7: `NotificationPermission` is folded into the channel.
  - `runDrain(container)` takes no separate `channel` argument. The channel is the container's own `outsideChannelProvider`.
  - The widget gains `WidgetRenderer` and `WidgetActionReceiver` beside spec §1's units.
