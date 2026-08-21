# Phase 8 — Public Release

## Kickoff prompt

```
Read docs/phases/CONVENTIONS.md and docs/phases/phase-8-public-release.md,
then execute Phase 8. Do not read the other phase briefs or plans.
```

**Goal:** ship to strangers — a store build that complies with Google Play
policy, an honest Data Safety declaration, and the monetization machinery
switched on without alienating the people already using the app.

**Ships:** NimbuStats on the Play Store.

**Schema versions:** v70–v79 reserved. Expect to use **none**.
**Branch:** `phase/8-release` · **Gate tag:** `phase-8-complete`

---

## Prerequisites — verify, do not assume

```bash
git tag --list 'phase-*-complete'   # every prior phase
dart analyze --fatal-infos
```

Operator prerequisites that cannot be automated:

- A Google Play developer account (one-time **$25**).
- A signing keystore, backed up somewhere the phone is not.
- A privacy policy hosted at a stable public URL.
- A recorded justification video for `FOREGROUND_SERVICE_SPECIAL_USE`.

---

## Required reading

- Spec: "Two capture sources, one pipeline", "Monetization & entitlements",
  "Infrastructure & running cost", and the Risks table
- `packages/nimbus_domain/lib/src/entitlements/` — `Feature`, `Entitlements`,
  `EntitlementSource`
- Phase 2's build flavors and `NotificationSource`

---

## Owns

```
app/android/app/src/store/**              store flavor manifest and config
app/lib/features/pro/**                   Pro screen, paywall, entitlement UI
app/lib/features/billing/**               Play Billing EntitlementSource
docs/release/**                           privacy policy, Data Safety notes, listing copy
```

**Must not touch:** feature logic. If a feature needs changing to pass review,
that is a finding to raise, not a quiet edit during release prep.

---

## Scope

**In:**

- **Store build flavor**: `NotificationListenerService` +
  `FOREGROUND_SERVICE_SPECIAL_USE`, and **no SMS permission anywhere in the
  manifest**.
- Privacy policy and Data Safety declaration.
- Crash reporting, with scrubbing (see traps).
- Store listing: screenshots in both locales, description, feature graphic.
- Release signing, `--split-per-abi` or App Bundle, ProGuard/R8 rules verified
  against drift and any reflection-based code.
- **Entitlement activation**: Play Billing as the `EntitlementSource`, replacing
  `AlwaysUnlocked`.
- **Founding-user grandfathering**, tested before any gate flips.
- Gates on: auto-capture beyond one bank template, advanced analytics, cloud
  backup.
- Google Drive `appDataFolder` backup (the destination Phase 7's format was
  designed for), behind `Feature.cloudBackup`.

**Out:** iOS, web, a marketing site, anything requiring a hosted backend.

---

## Known traps

Most of these are one-way doors — expensive or impossible to walk back after
publication.

- **The store flavor must not contain `RECEIVE_SMS` or `READ_SMS`, even
  unused.** Play forbids them for any app that is not the device's default SMS
  handler, with no exception for expense tracking. A leftover declaration is an
  automatic rejection. Assert it in a build-time test that greps the merged
  manifest.
- **`FOREGROUND_SERVICE_SPECIAL_USE` requires a written justification and
  usually a video**, and review can take several iterations. Budget weeks, not
  days, and submit early.
- **The Data Safety form must match reality exactly.** SMS and notification
  content never leaves the device — say so, and make sure it stays true. A
  mismatch discovered later is an enforcement action, not a warning.
- **Crash reports must be scrubbed.** No message bodies, no merchant names, no
  amounts, no template regexes (a user's regex can embed their card digits).
  Default to sending nothing user-generated, and test what a real crash report
  contains.
- **Founding-user grandfathering is tested before any gate flips**, not after.
  The flag persists at first run before a cutoff date and permanently retains
  full access. Getting this wrong once — locking out the people who used the
  app when it was free — is the reputational risk the design exists to avoid.
- **Everything premium is already labeled "Pro — free during early access."**
  If that labeling is not in place from Phase 1 onward, the paywall arrives as a
  surprise. Verify it before flipping gates.
- **R8 and drift.** Generated code and reflection-adjacent paths need keep
  rules; a release build that crashes on first query while debug works fine is
  the classic form of this. Test the **release** build on a device, not the
  debug build.
- **Play Billing needs no server, but does need real testing** with a licence
  tester account on a real device. Sandbox behavior differs from debug.
- **OAuth verification for Drive takes time** when the app is public. Start it
  early; it is independent of the store review.
- **Version code and signing key are permanent.** Losing the keystore means you
  can never update the app under the same listing. Back it up off-device before
  the first upload.

---

## Task outline

1. Store flavor manifest, plus the test asserting no SMS permission survives
   the merge.
2. `NotificationSource` verified end to end on the store flavor.
3. Release signing and R8 rules; **release-build smoke test on a device**.
4. Crash reporting with scrubbing, verified against a deliberately triggered
   crash.
5. Privacy policy, hosted; Data Safety answers drafted from the actual data
   flows.
6. `FOREGROUND_SERVICE_SPECIAL_USE` justification and video; submit for review.
7. Store listing: screenshots in `fa` and `en`, description, graphics.
8. Play Billing `EntitlementSource`, tested with a licence tester.
9. Founding-user grandfathering, tested with a simulated cutoff date.
10. Flip the gates: capture beyond one template, advanced analytics, cloud
    backup.
11. Drive `appDataFolder` backup behind `Feature.cloudBackup`.
12. Internal testing track → closed → open → production.

---

## Definition of done

`CONVENTIONS.md` §5, plus:

- [ ] Merged store manifest contains no SMS permission — proven by a test.
- [ ] Release build (not debug) runs on a real device through a full
      add–capture–analyze–goal cycle.
- [ ] A deliberately triggered crash report contains no user data.
- [ ] Founding-user grandfathering verified against a simulated cutoff.
- [ ] Every gated feature degrades gracefully when locked — no dead ends, no
      crashes, a clear explanation.
- [ ] Data Safety answers match a written inventory of actual data flows.
- [ ] Keystore backed up off-device, and the location recorded where the
      operator will find it.
- [ ] `git tag phase-8-complete`.

---

## Parallelism notes

Run alone. Release work is serial, gated on external review, and every step
depends on the previous one being accepted.

The one thing worth starting early, in parallel with Phase 6 or 7: **the
`FOREGROUND_SERVICE_SPECIAL_USE` justification and the OAuth verification for
Drive**. Both are review queues rather than engineering work, and both can run
while the code is still being finished.
