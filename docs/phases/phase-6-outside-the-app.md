# Phase 6 — Outside the App

## Kickoff prompt

```
Read docs/phases/CONVENTIONS.md and docs/phases/phase-6-outside-the-app.md,
then execute Phase 6. Do not read the other phase briefs or plans.
```

**Goal:** the app reaches the user without the user opening it — a home-screen
widget for one-tap logging, alerts when a budget or limit is crossing, and one
configurable daily reminder.

**Ships:** logging an expense or a cigarette from the home screen without the
app launching, and a warning at 80% of a budget while there is still time to
act.

**Schema versions:** v50–v59 reserved. Expect to use **none**.
**Branch:** `phase/6-outside-the-app` · **Gate tag:** `phase-6-complete`

---

## Prerequisites — verify, do not assume

```bash
git tag --list 'phase-*-complete'   # must include phase-1-complete, phase-4-complete, phase-5-complete
dart analyze --fatal-infos
adb devices                          # a real device is required for this phase
```

This phase cannot be verified on the host or meaningfully on an emulator.
Widget behavior, notification permissions, and battery-manager interference are
device-specific.

---

## Required reading

- Spec: "Phase 6 — Outside-the-app" in the build sequence, and the "Quick
  access" UX requirements
- `TransactionRepository` and `TransactionDraft` (Phase 1)
- `TrackerRepository` (Phase 4)
- `GoalAlert` (Phase 5)
- ~~`app/android/**/capture/MessageBuffer.kt` (Phase 2)~~ — it does not
  exist: only Phase 2A (pure Dart parsing) shipped. Phase 6 created its
  own buffer (`widget/WidgetBuffer.kt`) on the brief's rule — native
  writes are buffered and drained through the repositories (spec
  `docs/superpowers/specs/2026-10-12-outside-6-design.md`, finding 1).

---

## Owns

```
app/android/**/widget/**              ExpenseWidgetProvider.kt and friends
app/lib/features/notifications/**     channels, scheduling, permission flow
app/lib/features/widget/**            Dart side of the widget contract
```

Additive edits to Phase 1's settings screen for the reminder time.

**Must not touch:** `app/android/**/capture/**` (Phase 2 owns it), the
analytics engine, the goal engine.

---

## Scope

**In:**

- Home-screen widget:
  - one-tap "add expense" that opens a minimal entry surface
  - habit counters — increment a tracker directly from the widget, no app launch
- Budget and limit alerts driven by Phase 5's `GoalAlert`.
- One configurable daily reminder.
- Android 13+ `POST_NOTIFICATIONS` runtime permission flow, requested in
  context (when the user creates their first goal or enables the reminder) —
  never on first launch.
- Notification channels, separately controllable: alerts vs reminder.

**Out:** lock-screen widgets, Wear OS, quick-settings tiles, rich notification
actions beyond a single tap-through.

---

## Known traps

This phase is where "it works on my phone" costs the most, so each of these is
verified on hardware.

- **The widget must not load the full app graph.** The whole point is a
  sub-second tap. A widget path that boots the Flutter engine, opens the
  database, and builds the provider tree has already failed. Measure it.
- **The widget writes through the same repository, or through a native buffer
  drained later — never through a second insert path.** Phase 2 established this
  shape for a reason; duplicated write logic is how two sources of truth start.
- **`SCHEDULE_EXACT_ALARM` is policy-restricted.** A daily reminder does not
  need minute precision — use an inexact alarm. Requesting the exact-alarm
  permission for a reminder is both a review risk and unnecessary.
- **Reschedule on timezone change, locale change, and reboot.** A reminder that
  silently stops after a reboot is the most common failure in this category.
  Register for `BOOT_COMPLETED` and re-arm.
- **OEM battery managers kill scheduled work** — the same Xiaomi/Samsung/Huawei
  problem Phase 2 solved with native buffering. Test on a real device from that
  list if one is available, and document the behavior honestly rather than
  claiming reliability you have not verified.
- **Alerts must not fire in a loop.** Phase 5 owns crossing detection via
  `last_alerted_threshold`; Phase 6 delivers what Phase 5 emits and adds no
  logic of its own about *whether* to fire.
- **Notification content is sensitive.** A lock-screen notification saying
  "You have spent 12,400,000 Toman this month" is visible to anyone holding the
  phone. Use a discreet default and make the detail level a setting.
- **The widget renders in the system's locale and theme context**, not the
  app's. Persian numerals and RTL must be handled explicitly on the native side.

---

## Task outline

1. Notification channels and the Android 13+ permission flow, requested in
   context.
2. `GoalAlert` → notification delivery, with no added firing logic.
3. Daily reminder scheduling (inexact), plus the settings control.
4. Reschedule on `BOOT_COMPLETED`, timezone change, and locale change.
5. Widget: layout, RTL, Persian numerals, theme.
6. Widget: one-tap expense entry through the existing write path.
7. Widget: tracker increment through `TrackerRepository`.
8. Cold-path measurement — prove the widget tap does not boot the full app.
9. On-device verification pass.

---

## Definition of done

`CONVENTIONS.md` §5, plus, **verified on a real device**:

- [x] Widget expense entry completes without the full app launching; the
      measured time is recorded.
- [x] Widget tracker increment writes exactly one entry per tap.
- [x] Reminder survives a reboot.
- [x] Reminder survives a timezone change and fires at the new local time.
- [x] A budget crossing 80% produces exactly one notification, and
      recomputation produces none.
- [x] Notifications respect the discreet-content setting.
- [x] Widget renders correctly in both locales, RTL and LTR.
- [x] `git tag phase-6-complete`.

### Gate record (2026-10-13, Galaxy A53)

Against `CONVENTIONS.md` §5 on `9624bb1`. Device: Galaxy A53 SM-A536E
(`RZCT209E3QX`), **Android 16** (the plan assumed 15), profile build; upgrade
from the Phase 5 build kept the data (5,004 transactions, 23 tracker entries
before and after; `minSdk=26 targetSdk=36`).

- `dart analyze --fatal-infos` reports no issues.
- Test suites, all green at `9624bb1`: architecture 6; `nimbus_domain` 417;
  `nimbus_data` 337; `app` 681, run with `--no-pub --concurrency=4
  --timeout 90s`; Kotlin JUnit 30 (`ReminderTimeTest` 14, `AmountParserTest` 6,
  `PendingOverlayTest` 6, `Uuid7Test` 4). Phase 5 closed the app at 609.
- **Persian review.** The operator approved all 22 new `fa` values as written
  (2026-10-13), including `notificationsSettingsDetailsHint` as changed by
  `9624bb1`. No corrections, so no `feat/fa-review` commit.
- **Widget expense entry** (app killed, fresh process each run, no
  `MainActivity` and no `flutter` log line on the tap path). `Displayed
  …/.widget.ExpenseEntryActivity`: **551, 608, 489, 466 ms**.
  - Save with the app killed: a `widget` row, 12,500, Uncategorized,
    **drain_ms 871** (tap to row). Samsung did not defer the job
    (`dumpsys jobscheduler`: countInWindow 0, no timeouts).
  - The headless engine started about 0.5 s after Save, never on the tap path.
- **One entry per tap.** 5 taps on a counter → 5 broadcasts → **5 rows**; the
  widget showed 5. A second drain ran for the taps that arrived during the
  first (R10), with no "stopped by the system" line. A boolean tracker → **1
  row**, the row turned to ✓ ("Gym, done today") and was no longer clickable.
  The buffer was empty afterwards; no rejected file.
- **Goal notifications** (channel `alerts`, `id=1`, tag `goal:<id>`).
  - An 80% crossing from the widget with the app killed: exactly **one**
    record, `vis=PRIVATE`, text "A goal needs a look" (details off);
    `last_alerted_percent` 80; **drain_ms 541**.
  - Recomputation (a note edit on that transaction): the record unchanged, the
    percent still 80.
  - App backgrounded, 100% crossing: no headless engine (the job handed the
    drain to the live engine), **drain_ms 101**; the 100% record replaced the
    80% one under the same tag, still one record, percent 100.
  - Details on: "Transport: 80% of this month's limit", and "Transport:
    reached this month's limit" at 100%.
- **Tap-through.** App not running: the alert opened the goal detail
  (`LAUNCH_SINGLE_TOP`, extras). App running on another tab: delivered to the
  running activity, the goal opened. Back out, then Recents: lands on Home,
  no replay (`LAUNCHED_FROM_HISTORY`, no extras).
- **Reminder.** Permission double-tap on the switch: one system dialog, then
  `granted=true`, no blocked row. The 21:00 reminder fired at 21:01:13
  (`NOTIFICATION_INTERRUPTION channelId=reminder`) and re-armed to
  2026-10-14 21:00. Its tap opens the add screen (`/add`).
  - **Reboot** (`adb reboot` 22:31:55): both alarms listed again by 22:37:45,
    `ReminderReceiver` at 2026-10-14 21:00 and `widget.MIDNIGHT` at
    2026-10-14 00:00.
  - **Zone change** Tehran → Istanbul: the reminder moved from 22:46 +03:30 to
    22:46 +03:00 (same wall time), midnight to 00:00 +03:00; a reminder set to
    22:32 posted at 22:34 local, then re-armed for the next day. Restored to
    `Asia/Tehran`, automatic zone on; alarms back at +03:30.
- **Both locales and RTL.** Switching to Persian re-rendered
  `widget_snapshot.json` (`localeTag` `fa`, `rtl` true) within 2.5 s, renamed
  both channels and re-pushed the reminder text. The launcher honours
  `setLayoutDirection`, so no RTL layout variant was needed. The widget's
  value `'۰٫۲۵ L'` is U+06F0 U+066B U+06F2 U+06F5, identical to the Trackers
  tab; the content description is Persian too. Screenshots: `widget-en-1.png`,
  `dialog-en.png`, `widget-fa.png`, `dialog-fa.png`.
- **Smallest size.** The launcher's minimum for the widget is **3×2 cells**
  (`appWidgetMinWidth=294`, `appWidgetMinHeight=232` dp); all three rows and
  their [+] are fully visible (`widget-smallest.png`). The launcher offers no
  one-row height.
- **Light and dark.** Light (`light-sheet.png`): light surface, dark text,
  green accent; dark as the system default. System night mode restored.
- **Log sweep.** `logcat -s NimbuStats` across every capture: no lines. Skipped
  frames in our processes: 43 at a cold start right after the reboot (load
  average about 38), and 78 (about 650 ms at 120 Hz) when the headless engine
  booted on the main thread after the dialog had closed (D30).
- **Finding F1: the lock screen followed Android, not our channel.** The
  channel's `mLockscreenVisibility` read `-1000` and
  `lock_screen_allow_private_notifications` was 1, so with details on the
  locked screen showed the full text (`lock-details-on.png`). An app cannot
  set a channel's lock-screen visibility. Operator decision: follow Android's
  own setting. Fixed in `9624bb1` (the settings hint rewritten in en and fa,
  the no-op channel line and its comment removed; spec §4.3 and the decision
  table amended); re-checked on the phone with the new hint rendered.
- **Finding F2: a re-arm inside the delivery window skipped the day.** A
  `TIME_SET` re-arm at 22:48:59, after a 22:46 nominal time and inside its
  window, moved the reminder to tomorrow. Operator decision: fix before the
  gate. Fixed in `a2ece7a` (`armedAt` is stored; a re-arm inside the window
  fires now). Re-checked: reminder at 23:40, a `RearmReceiver` broadcast at
  23:40:03, posted at **23:40:10**, next 2026-10-14 23:40, one record, no loop.
- **Ruling R11's known limit.** A row the headless engine writes while the
  app engine is alive does not refresh the app's open lists until their next
  write (Drift's change notifications are per connection). The window is the
  few seconds of a headless drain with the app opened during it; a list is
  stale for seconds. Not seen on the device.
- **Known limits, accepted.** M8: the widget snapshot and the database can
  disagree briefly across engines (display only; the next drain or open
  reconciles). M9: one failing buffer line keeps `ok=false`; the taps behind it
  wait for the next tap or the next app open.
- **Not checkable on this device.** Persian digits typed in the dialog (the
  Samsung number keypad is Latin only; `AmountParserTest` and the dialog's key
  listener cover it), a one-row widget, Android below 12, and the midnight
  reset (alarm armed and re-armed, not observed).
- **Carried forward:** D26–D36 in `DEFERRED.md`.
- **Restore** (operator's choice). The test data was deleted through the app,
  never by editing the database: six widget expenses (including the
  operator's own 23:29 dialog test), seven test tracker entries and the two
  test goals. Live counts are back at the baseline: 5,000 transactions, and
  20 tracker entries plus the operator's own two taps. The app language is
  English again. The reminder is on at 21:00, details are on, and the widget
  stays on the home page. The time zone and night mode are restored.

---

## Parallelism notes

Run this one **alone**. It touches the widget, notifications, and the surfaces
of every feature it exposes, and it competes with Phase 2 for the Android
manifest and build-flavor files. Pairing it with 2B is the worst combination in
the project.
