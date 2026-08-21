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
- `app/android/**/capture/MessageBuffer.kt` (Phase 2) — **read it for the
  native-buffer pattern, then apply the same shape here**

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

- [ ] Widget expense entry completes without the full app launching; the
      measured time is recorded.
- [ ] Widget tracker increment writes exactly one entry per tap.
- [ ] Reminder survives a reboot.
- [ ] Reminder survives a timezone change and fires at the new local time.
- [ ] A budget crossing 80% produces exactly one notification, and
      recomputation produces none.
- [ ] Notifications respect the discreet-content setting.
- [ ] Widget renders correctly in both locales, RTL and LTR.
- [ ] `git tag phase-6-complete`.

---

## Parallelism notes

Run this one **alone**. It touches the widget, notifications, and the surfaces
of every feature it exposes, and it competes with Phase 2 for the Android
manifest and build-flavor files. Pairing it with 2B is the worst combination in
the project.
