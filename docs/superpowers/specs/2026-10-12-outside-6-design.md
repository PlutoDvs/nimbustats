# Phase 6 — Outside the app — design

**Status:** implemented; gate passed 2026-10-13 (see the brief's gate record). Implementation plan:
`docs/superpowers/plans/2026-10-12-nimbustats-phase-6-outside-the-app.md`.
**Brief:** `docs/phases/phase-6-outside-the-app.md`.
**Prerequisites:** `phase-1-complete`, `phase-4-complete` and `phase-5-complete`
all exist.
**Schema:** none · **Branch:** `phase/6-outside-the-app` · **Gate:**
`phase-6-complete`

## Context

The app reaches the user without being opened: a home-screen widget logs an
expense or a tracker tap, a budget crossing arrives as a notification while
there is still time to act, and one daily reminder can be switched on.

Phase 5 decides *whether* an alert is due (`goalWatcherProvider.alerts`, one
event per crossing, guarded by `recordCrossing`'s transaction). Phase 6 only
decides *where* it is shown. It adds no firing logic.

### What the code showed before the design

1. **There is no native buffer to copy.** The brief points at Phase 2's
   `MessageBuffer.kt`, but only 2A (pure Dart parsing) shipped. The Android
   side is one line: `class MainActivity : FlutterActivity()`. Phase 6 creates
   the buffer shape itself.
2. **The database runs in rollback-journal mode with no busy timeout**
   (`AppDatabase.openAtPath` → `NativeDatabase(File(path))`; the Phase 5
   device check found no `-wal` file). A second connection that writes while
   the app holds one fails at once with "database is locked".
3. **The goal watcher runs only while the app does.** `GoalAlertListener`
   starts it from the shell. A widget write made with the app closed would
   otherwise alert only at the next launch.
4. **Both write paths already promise this phase.** `TransactionRepository`
   and `TrackerRepository` each say Phase 6's widget writes through them and
   nothing else. `TxSource.widget` exists. `TrackerRepository.logEntry` takes
   the tap time as `at:` and returns `AlreadyDoneToday` for a boolean already
   done.
5. **Settings are key/value** (`settings(key, value)`), so the reminder and the
   detail setting are new keys, not a migration.
6. **`goalServiceProvider` needs only `appDatabaseProvider`** (plus the engine
   and today providers it builds itself), so a bare `ProviderContainer` with
   one override can run a real goal check with no widget tree.
7. **Numbers.** Tracker values format through
   `NumberFormat.decimalPattern(localeTag)` (two fraction digits at most);
   money through `MoneyFormatter` (`Digits.toPersian`, group separator
   U+066C). Digits follow the settings locale.
8. **No widget, notification or scheduling package is cached**, Google Maven
   is unreachable on the current exit, and the Gradle cache has
   `androidx.core:1.13.1` but no WorkManager, Glance or JUnit.

### Decisions taken with the operator (2026-10-12)

| Question | Decision |
|---|---|
| How soon a crossing caused from the widget (app closed) must alert | Within seconds: a background job drains the buffer in a headless Dart engine and runs the goal check |
| The widget's add-expense surface | Native dialog: amount (focused, number keyboard) + up to 4 predicted category chips; no chip = Uncategorized |
| Which trackers the widget shows | The first N in the Trackers tab's order, as many as the widget's size fits; no new setting |
| An alert while the app is on screen | Phase 5's snackbar only; a notification only when the app is not in the foreground |
| What "discreet by default" means | No goal name or amount anywhere by default; a "Show details in notifications" setting turns the full text on. With details on, the notification is `VISIBILITY_PRIVATE` with the discreet public version, which Android shows on a lock screen set to hide sensitive content; with "show all content" Android shows the full text, because an app cannot set a channel's lock-screen visibility (found on the Galaxy A53, Android 16; operator decision 2026-10-13) |
| The daily reminder | Off by default; 21:00 default time; fires every day around that time whether or not anything was logged |
| Implementation approach | Native Kotlin on Android framework APIs + one MethodChannel; no new pub or runtime Gradle dependency |
| Kotlin tests | `junit:junit:4.13.2` as a **test-only** Gradle dependency (Maven Central), never in the APK |
| Android floor (settled while planning) | `minSdk` 26, up from Flutter's 24, so the `java.time` in §5 and §6.3 is native without desugaring. Phones on Android 7.0/7.1 can no longer install the app |

### Where this design departs from the brief

1. **The buffer is Phase 6's own** (finding 1). It follows the brief's rule —
   native writes are buffered and drained through the repositories, never
   inserted by a second path — without a Phase 2 file to mirror.
2. **A headless Dart engine runs, but never on the tap path.** The brief
   rejects a widget *tap* that boots the engine, opens the database and builds
   the provider tree. The tap here is native end to end: a dialog or a
   broadcast, one buffer append, done. The engine starts afterwards, in a
   background job, to drain and evaluate (finding 3). Its `ProviderContainer`
   holds only the providers the drain reads, with no widget tree.
3. **WAL journal mode** (finding 2) — a pragma in `app_database.dart`
   (Phase 0's file), not a schema version. The master spec already expects WAL
   (Phase 7's "correct SQLite WAL checkpointing").
4. **Ownership grows by one native directory:** `app/android/**/notifications/**`
   (Phase 6). `app/lib/features/widget/**` is in the brief but missing from
   the CONVENTIONS table; both rows are added.
5. **Edits outside Phase 6's directories**, each additive and named in its
   commit: `app_database.dart` (WAL), the two repositories and their DAOs
   (caller-supplied id, §3.2), `GoalWatcher` (`checkNow`), `GoalAlertListener`
   (foreground stream), the goal editor (permission hook), the settings screen
   and `settings_keys.dart` (§8), `MainActivity.kt` (the channel),
   `AndroidManifest.xml` and `build.gradle.kts`.
6. **One test-only dependency** (JUnit), deliberate and stated, not a side
   effect (CONVENTIONS §1).

---

## 1. Architecture

```
 HOME SCREEN — no Flutter                     DART — app engine, or headless drain engine
 ┌───────────────────────────┐               ┌──────────────────────────────────────────┐
 │ ExpenseWidgetProvider.kt  │─tracker tap─┐ │ WidgetDrain: takeBuffer → repositories   │
 │ ExpenseEntryActivity.kt   │─save──────┐ │ │   (row id = buffer id: exactly once)     │
 └────────────▲──────────────┘           ▼ ▼ │ → commitDrain(snapshot, acks, rejects)   │
              │ render          WidgetBuffer.kt ──enqueue──► DrainJobService.kt         │
              │                                  app engine alive? yes → "drainNow"     │
   widget_snapshot.json ◄── commitDrain / writeSnapshot      no  → headless drainMain() │
                                                 │ → GoalWatcher.checkNow → AlertRouter │
 Notifier.kt ◄── postAlert ──────────────────────┘                                      │
 ReminderReceiver / RearmReceiver (boot, time zone, time set, locale, package replaced) │
```

### Native — `app/android/app/src/main/kotlin/com/nimbustats/app/`

| Unit | Package | Does |
|---|---|---|
| `ExpenseWidgetProvider` | `widget` | Renders the widget from the snapshot plus the pending buffer; receives tracker taps (append, re-render, enqueue drain) |
| `ExpenseEntryActivity` | `widget` | The translucent add-expense dialog (§7) |
| `WidgetBuffer` | `widget` | The buffer file; one synchronized `object` (§2) |
| `WidgetSnapshot` | `widget` | Reads and version-checks `widget_snapshot.json` |
| `DrainJobService` | `widget` | The JobScheduler job: hands over to a live app engine, or runs a headless engine at `drainMain` |
| `Notifier` | `notifications` | Channels, alert and reminder posting |
| `ReminderScheduler` | `notifications` | Arms and cancels the reminder and the widget's midnight refresh |
| `ReminderReceiver`, `RearmReceiver` | `notifications` | Fires the reminder; re-arms after boot, time-zone, time-set, locale and package-replaced broadcasts |
| `MainActivity` | — | Registers the channel; passes notification-tap routes to Dart |

Pure logic sits in Android-free classes so JUnit covers it on the host:
`ReminderTime` (next trigger), `AmountParser`, `PendingOverlay` (today's value
with pending taps), `Uuid7`.

Native code **displays** text; it never composes it. Every string it shows
arrives from Dart, formatted from the ARB files in the app's locale (§6.1).

### Dart

| Unit | Location | Does |
|---|---|---|
| `OutsideChannel` | `features/notifications/data/` | The one platform boundary (§1.1); a fake replaces it in every test |
| `NotificationPermission` | `features/notifications/application/` | `enabled()`, `requestInContext()`, `openSettings()` |
| `AlertRouter` | `features/notifications/application/` | The only subscriber to `goalWatcherProvider.alerts`; routes each alert to the snackbar stream or to a notification (§4.3) |
| `ReminderController` | `features/notifications/application/` | Reads and writes the reminder keys; pushes the native reminder config |
| Settings section | `features/notifications/presentation/` | Reminder switch and time, the detail switch, the blocked row (§8) |
| `SnapshotWriter` | `features/widget/application/` | Builds the snapshot (§6.1) and pushes it on every relevant change |
| `WidgetDrain` | `features/widget/application/` | Parses buffer lines, writes them through the repositories, commits (§2) |
| `drainMain` | `app/lib/drain_main.dart` | `@pragma('vm:entry-point')`; opens the database as `main.dart` does and calls `runDrain` |

### 1.1 The channel — `com.nimbustats.app/outside`

Dart → native:

| Method | Arguments | Returns |
|---|---|---|
| `notificationsEnabled` | — | `bool` (`areNotificationsEnabled`) |
| `requestNotificationPermission` | — | `bool` granted. Below API 33 it returns `notificationsEnabled` without a dialog |
| `openNotificationSettings` | — | — |
| `registerChannels` | names and descriptions of `alerts` and `reminder` | — |
| `postAlert` | `tag`, `text`, `publicText`, `route` | — |
| `setReminder` | `enabled`, `minuteOfDay`, `text`, `route` | — (arms or cancels) |
| `writeSnapshot` | snapshot JSON | — (stores atomically, updates every widget instance) |
| `takeBuffer` | — | `List<String>`, the raw pending lines |
| `commitDrain` | snapshot JSON, `ackIds`, `rejected: [{line, reason}]` | — (§2.3) |
| `drainFinished` | `ok` | — (headless engine only) |
| `takeLaunchRoute` | — | `String?`, the route a notification tap launched the app with |

Native → Dart: `drainNow` (the app engine drains), `openRoute(route)` (a
notification tapped while the app runs).

---

## 2. The widget buffer and the drain

### 2.1 Format

`files/widget_buffer.jsonl`, one JSON object per line:

```json
{"v":1,"id":"<uuidv7>","kind":"expense","atUtc":1760270000000,"amountMinor":120000,"categoryId":"<id or null>"}
{"v":1,"id":"<uuidv7>","kind":"tracker","atUtc":1760270000000,"trackerId":"<id>"}
```

Every reader and writer of the file runs in the app's process (widget
broadcasts, the dialog, the job, the channel), so `WidgetBuffer` is one Kotlin
`object` whose methods are `synchronized`. An append writes one line and
flushes. Anything that removes lines rewrites the file to a temp file and
renames it over the original, so a crash leaves the old file, never half of
one.

### 2.2 Exactly once — the buffer id is the row id

`TransactionRepository.add` and `TrackerRepository.logEntry` gain an optional
caller-supplied `id`. With an id, the DAO inserts **only if no row with that id
exists — a soft-deleted row counts as existing** — inside one transaction, and
reports which happened. So:

- a drain repeated after a crash or a kill writes nothing new;
- an expense deleted after it was drained is never resurrected;
- two drains running at once (app engine and headless) write each item once.

Without an id, both methods behave exactly as today.

### 2.3 The drain, step by step

1. `takeBuffer()` — every pending line; nothing is removed.
2. Each line is parsed and written, with its id and its tap time
   (`occurredAtUtc` / `at:`), so a late drain files the tap when it happened.
   - **Category gone** (deleted since the snapshot): written as Uncategorized —
     the amount is what matters, and Uncategorized is the spec's own default.
   - **Tracker gone**, archived, or now a duration tracker: rejected with a
     reason.
   - **Malformed line** or unknown `v`: rejected with a reason.
   - **`AlreadyDoneToday`**: acked; it is the repository's rule.
   - **Any other exception**: neither acked nor rejected — the line stays for
     the next drain — and reported through `FlutterError.reportError`.
3. A fresh snapshot is built (§6.1).
4. `commitDrain(snapshot, ackIds, rejected)` — under the buffer lock, in one
   call: write the snapshot, drop acked and rejected lines, append the
   rejected ones with their reasons to `widget_buffer.rejected.jsonl`, update
   the widgets. One call is what keeps the widget from ever counting a tap
   twice (snapshot and pending both) or not at all (neither).
5. Every rejection is reported through `FlutterError.reportError`. Nothing is
   dropped silently.
6. `GoalWatcher.checkNow()`; alerts go through `AlertRouter` (§4.3).

A drain killed after step 4 loses no alert: Phase 5's watcher evaluates every
goal at app start.

### 2.4 Who drains, and when

**The app engine:** after the first frame at start-up (never before it — cold
start stays within budget), on every resume, and on `drainNow`.

**The job** (`DrainJobService`, one fixed job id, so a burst of taps enqueues
one job): expedited on API 31+, an immediate deadline below; no network
constraint.

- If the app's engine is alive and its Dart side has registered the channel,
  the job sends `drainNow` and finishes.
- Otherwise it starts a headless `FlutterEngine` at
  `DartEntrypoint(appBundlePath, "package:nimbustats/drain_main.dart", "drainMain")`.
  `drainMain` opens the database exactly as `main.dart` does, builds a
  `ProviderContainer(overrides: [appDatabaseProvider...])`, runs
  `runDrain(container, channel)` and calls `drainFinished(ok)`. The job then
  destroys the engine and calls `jobFinished(params, false)`.
- If `drainFinished` has not arrived within 60 s, the job destroys the engine,
  logs `Log.e`, and finishes without reschedule. The buffer is intact; the
  next app open drains it. A persistent failure therefore never loops.

### 2.5 `GoalWatcher.checkNow()`

A Phase 5 addition: evaluates every active goal's current period now, emits
any alert on `alerts` exactly as a debounced evaluation does, and completes
when the evaluation has. The headless engine uses it; the app engine's
watcher keeps its own triggers.

---

## 3. Database concurrency

`AppDatabase` sets `PRAGMA journal_mode=WAL` and `PRAGMA busy_timeout=5000` in
`beforeOpen` on every connection. Reads then run beside a write, and a second
writer waits up to 5 s instead of failing.

Overlap is rare — the job hands a live app engine the work — but possible (the
app opened mid-job). It is safe: drains are idempotent per item (§2.2), and
`recordCrossing`'s transaction keeps two goal checks from firing one crossing
twice (Phase 5 spec §3).

Knock-on, recorded in the same commit:
- the Phase 7 brief: the database now has a `-wal` file; a backup checkpoints
  first;
- device checks copy `nimbustats.sqlite-wal` and `-shm` with the database.

---

## 4. Notifications

### 4.1 Channels

`alerts` and `reminder`, both `IMPORTANCE_DEFAULT`, so either can be silenced
in Android's settings. Names and descriptions are ARB strings, registered by
Dart at start-up and again on a locale change (re-registering an existing
channel id renames it). Nothing posts before the app has run once, so the
channels exist whenever they are needed.

A monochrome small icon (`ic_stat_nimbus`) is added for the status bar.

### 4.2 Permission — Android 13+ `POST_NOTIFICATIONS`

Requested in context, never at first launch:
- after the **first goal** is saved — the editor's save-success path asks when
  no goal existed before the save;
- when the **reminder** is switched on.

Android enforces the rest: a granted permission returns at once with no
dialog, and after two denials it shows nothing. No extra "already asked" state
is kept. A denied permission leaves the reminder off and shows the blocked row
(§8). Foreground alerts are snackbars and need no permission.

### 4.3 Alert delivery — `AlertRouter`

- Subscribes once to `goalWatcherProvider.alerts`, before the watcher starts.
- **Foreground** (`WidgetsBinding.instance.lifecycleState == resumed`): the
  alert goes to `foregroundAlerts`, which `GoalAlertListener` now listens to
  instead of the watcher. One decision point, so no alert is shown twice or
  missed at a lifecycle boundary. Injected as `bool Function() isForeground`
  for tests.
- **Otherwise** (including the headless engine, which has no lifecycle): a
  notification.
  - Tag `goal:<goalId>`, id 1, so a 100% crossing replaces that goal's 80%
    notification.
  - Text: discreet `notificationsAlertDiscreet` ("A goal needs a look") by
    default; with `notification_detail` on, Phase 5's
    `GoalFormat.alertMessage(l10n, alert, period)`.
  - `VISIBILITY_PRIVATE`, with the discreet text as the public version, which
    Android shows on a lock screen set to hide sensitive content. With "show all
    content" Android shows the full text: an app cannot set a channel's
    lock-screen visibility (found on the Galaxy A53, Android 16; operator
    decision 2026-10-13).
  - Tap: opens `goalDetailRoute(goalId)`.

---

## 5. The daily reminder

- Keys: `reminder_enabled` (default false), `reminder_minute_of_day` (default
  1260 = 21:00).
- Dart pushes `setReminder(enabled, minuteOfDay, text, route)`. Native keeps it
  in SharedPreferences, so the receivers can re-arm without Dart.
- **Alarm:** `AlarmManager.setAndAllowWhileIdle(RTC_WAKEUP, next)` — inexact,
  delivered in Doze, no exact-alarm permission. One-shot: each firing arms the
  next day's from the current local wall clock, which keeps DST and time-zone
  changes correct where `setInexactRepeating` drifts.
- **`ReminderTime.nextTrigger(now: ZonedDateTime, minuteOfDay)`**: the next
  local occurrence strictly after `now`, through `java.time`, so a DST gap or
  overlap resolves the way `java.time` does.
- **Re-arm:** `RearmReceiver` handles `BOOT_COMPLETED`, `TIMEZONE_CHANGED`,
  `TIME_SET`, `LOCALE_CHANGED` and `MY_PACKAGE_REPLACED`; it re-arms the
  reminder (if enabled) and the widget's midnight refresh (§6.3).
- Text: `notificationsReminderText`. Tap: opens `addTransactionRoute`.

Manifest: `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`. Deliberately absent:
`SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`,
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (a Play policy risk). Samsung's
"sleeping apps" behaviour is measured and documented (§10), not worked around.

---

## 6. The widget

### 6.1 The snapshot — `files/widget_snapshot.json`

Written by Dart, read by native. Example (values illustrative):

```json
{
  "v": 1,
  "dayKey": 20261012,
  "localeTag": "fa",
  "rtl": true,
  "currency": {"code": "IRT", "decimalDigits": 0, "label": "تومان"},
  "trackers": [
    {"id": "…", "name": "سیگار", "color": 4294198070, "type": "counter",
     "perTap": 1.0, "unit": null, "todayTotal": 3.0,
     "goal": {"current": 3.0, "target": 5.0, "step": 1.0}}
  ],
  "chips": [{"id": "…", "name": "خوراک"}],
  "strings": {"addExpense": "…", "emptyTrackers": "…", "entryTitle": "…",
              "save": "…", "cancel": "…", "saved": "…",
              "trackerAdd": "{name}، امروز {total}", "trackerDone": "…",
              "goalProgress": "{current} از {target}"}
}
```

- **Trackers:** live, unarchived, in tab order, duration trackers excluded
  (a timer cannot run from a widget). At most 4 — the largest layout's rows.
  `goal` (added 2026-10-19, optional) is the tracker's goal progress over the
  goal's own period, as the Trackers tab shows it: the first active goal on
  the tracker whose period is open today (`trackerGoal`). `step` is what one
  tap adds: 1 for a count goal, `perTap` for a sum. Absent without a goal, so
  `v` stays 1; `goalProgress` is required only when some tracker has a goal.
- **Chips:** `CategoryPredictor.predict(at: now, limit: 4)`, resolved to names.
- **Strings:** every label and content description the widget and dialog
  show, already in the app's language; templates carry `{name}` / `{total}`
  slots that native fills with already-formatted values.
- **Written** after every drain (inside `commitDrain`), and by the app engine,
  debounced 300 ms, on: start-up, resume, `engine.changes()`,
  `engine.trackerChanges()`, tracker list changes, goal changes, and locale
  or currency changes. (Nothing in the snapshot depends on the calendar: `dayKey` is
  Gregorian, like every `local_date_key`.)

### 6.2 Numbers on the native side

An optimistic tap means native formats "3 → 4" itself. It uses Android's ICU
`DecimalFormat` for `localeTag`, two fraction digits at most — the CLDR data
the app's `NumberFormat.decimalPattern` is built on. The device check compares
widget digits with the Trackers tab's in both locales. A quantity appends its
unit as `TrackerFormat.total` does.

### 6.3 What a row shows

`PendingOverlay`: the snapshot's `todayTotal` if its `dayKey` is today (local
Gregorian `yyyymmdd`), else 0, plus every pending tap for that tracker whose
local day is today. A boolean shows ✓ — with no [+] — when either holds it.

With a `goal`, the row shows `goalProgress` instead: the goal's `current`
plus today's pending taps × `step`, "of" its `target`. A snapshot from
another day shows today's value instead, since the goal's period may have
rolled over; the next snapshot write brings the progress back.

Re-rendered on every snapshot write, every tap, and at local midnight
(`setAndAllowWhileIdle(RTC, nextMidnight)`, re-armed by `RearmReceiver`).
`updatePeriodMillis` is 0: no polling.

### 6.4 Layout

- One resizable widget, default 4×2. Android 12+: responsive `RemoteViews`
  keyed by size, 1–4 tracker rows by height. Below 12: 2 rows.
- Top: "+ Expense" (opens §7). Rows: colour dot, name, today's value, a 48 dp
  [+].
- RTL: the root's layout direction comes from `rtl`. If the A53's launcher
  ignores it, the fallback is an RTL layout variant chosen by the same flag.
- Theme: light and dark follow the system (`values-night`), using the app's
  token colours.
- Content descriptions from `trackerAdd` / `trackerDone`; text sizes in `sp`.

### 6.5 States

| State | When | Shows |
|---|---|---|
| Loading | No snapshot (placed before the first app run) | The app icon; a tap opens the app. No text, so no native strings |
| Error | Snapshot unreadable or `v` unknown | As loading, plus `Log.e`; the next app start rewrites it |
| Empty | No eligible trackers | "+ Expense" and `emptyTrackers` |
| Populated | Otherwise | §6.4 |

---

## 7. The add-expense dialog — `ExpenseEntryActivity`

- Translucent dialog activity, `excludeFromRecents`, its own task affinity, so
  it never brings `MainActivity` forward.
- Amount field focused, number keyboard shown. `AmountParser` accepts Latin,
  Persian and Arabic-Indic digits and both group separators, and yields an
  integer number of minor units for the snapshot's `decimalDigits`, mirroring
  `MoneyFormatter.parse` (the plan pins its exact rules and bound).
- Up to 4 chips, single-select; none selected → Uncategorized.
- Save is enabled once the amount is above zero. Save: append an `expense`
  line, enqueue the drain, show a `saved` Toast, finish. No spinner.
- Cancel, back, or a tap outside: finish without writing.
- Layout direction and strings from the snapshot. No snapshot → the widget is
  in its loading state and opens the app instead of this dialog.

---

## 8. Settings

New keys in `SettingsKeys` (outside `appSettings`, so a settings reset leaves
the reminder armed state and the native alarm consistent):
`reminder_enabled`, `reminder_minute_of_day`, `notification_detail` (default
false). A value that does not parse is reported through `FlutterError` and
reads as its default; saving a new value repairs it.

A "Notifications" section on the settings screen (additive):
- **Daily reminder** switch. On → `requestInContext()`; granted → save and
  `setReminder`; denied → stays off and the blocked row shows.
- **Reminder time** — the platform time picker, shown while the reminder is
  on. 24-hour, in the settings' digits.
- **Show details in notifications** switch.
- **Blocked row** — "Notifications are blocked · Open settings" — shown when
  notifications are disabled and the reminder is on, or right after a denial;
  re-checked on resume.

States: loading (keys not read yet), error (a read failed: `NimbusErrorState`
with the error, as the settings screen's own body does), populated. There is
no empty state.

---

## 9. Strings and errors

**ARB prefixes:** `notifications…` (channels, alert and reminder texts, the
settings section) and `widget…` (everything in the snapshot's `strings`). Both
locales; every Persian value is reviewed by the operator before the gate, as
in Phase 5.

**No silent failures:**
- Dart: every rejected buffer line, every failed drain item, every failed
  snapshot write and every channel error is reported through
  `FlutterError.reportError` with a `library` of `widget drain`,
  `alert router` or `reminder`.
- Native: anything that cannot reach Dart (an unreadable snapshot, a drain
  timeout, a failed post) logs `Log.e` under the tag `NimbuStats`.
- A failed `postAlert` does not undo the crossing: Phase 5 has recorded it, by
  design, so it is reported, not retried.

---

## 10. Testing

**Host, Dart (TDD; `OutsideChannel` faked; in-memory database unless noted):**
- DAOs: insert-if-absent with an id — second insert is a no-op; a
  soft-deleted row blocks it; without an id, behaviour unchanged.
- `AppDatabase` on a temp file: `journal_mode` reads `wal`; two connections
  writing concurrently both succeed.
- `WidgetDrain`: twice → one row; deleted row not resurrected; tap time kept;
  missing category → Uncategorized; missing tracker and malformed line →
  rejected and reported; `AlreadyDoneToday` → acked; an unexpected exception →
  neither acked nor rejected; one `commitDrain` per drain.
- `AlertRouter`: foreground → `foregroundAlerts`, no post; background → post
  with tag `goal:<id>`; discreet vs detailed text by setting; the public text
  is always discreet.
- `GoalWatcher.checkNow()`: emits a due alert once; a second call emits none.
- `SnapshotWriter`: tab order, duration excluded, cap of 4, chips, fa and en
  strings, `dayKey`, `rtl`.
- Settings section: reminder on → request → `setReminder`; denied → off +
  blocked row; detail switch persists; loading, error, populated; fa and en;
  48 dp tap targets.
- Goal editor: the first goal's save asks once; a later goal's does not.
- `runDrain(container, channel)` end to end on an in-memory database.

**Host, Kotlin (JUnit, `testDebugUnitTest`):** `ReminderTime.nextTrigger`
(same day, next day, DST gap, DST overlap, time-zone change);
`AmountParser` (three digit sets, separators, zero, bound, garbage);
`PendingOverlay` (stale `dayKey`, pending only today's, boolean);
`Uuid7` (version and variant bits, monotonic within a millisecond).

**Before JUnit is added**, Maven Central reachability is probed; if it is
blocked, the operator is asked to switch exit rather than the dependency
being dropped.

---

## 11. On-device verification (Galaxy A53)

The A53 is the operator's daily phone: confirm it is free and unlocked first.
The reboot and the time-zone change alter its state, so each is asked for at
the time and undone afterwards.

| Brief's definition of done | How it is shown |
|---|---|
| Widget expense entry without the full app; time recorded | `ActivityTaskManager: Displayed …/.widget.ExpenseEntryActivity: +N ms`; no `MainActivity` start and no `flutter` log lines on the tap path. The background path (tap → row → notification) is timed separately |
| One entry per tracker tap | N taps → N rows in a database copy (with `-wal`); a boolean → one row |
| Reminder survives a reboot | Arm a few minutes ahead, `adb reboot`, `dumpsys alarm` shows it re-armed, it fires |
| Reminder survives a time-zone change | Change zone, `dumpsys alarm` shows the new local trigger, it fires; zone restored |
| 80% crossing → exactly one notification; recomputation → none | App killed: widget expense → one notification (`dumpsys notification`); relaunch and a note edit → none. Repeated with the app backgrounded |
| Discreet setting respected | `dumpsys notification --noredact` text with the setting off and on; the lock screen discreet when Android's own setting hides sensitive content (§4.3) |
| Both locales, RTL and LTR | Widget and dialog screenshots in fa and en; widget digits match the Trackers tab |

Also recorded, honestly: drain latency with the app killed, and whether
Samsung defers the job.

---

## 12. Out of scope

Lock-screen widgets, Wear OS, quick-settings tiles, rich notification actions
(the brief's Out); per-widget tracker choice; a reminder that skips days
already logged; duration trackers on the widget; undo from the widget;
requesting a battery-optimisation exemption; iOS.
