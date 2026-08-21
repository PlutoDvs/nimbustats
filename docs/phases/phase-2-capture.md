# Phase 2 — Capture

## Kickoff prompt

```
Read docs/phases/CONVENTIONS.md and docs/phases/phase-2-capture.md, then
execute Phase 2 (state whether you are doing 2A, 2B, or both).
Do not read the other phase briefs or plans.
```

**Goal:** the overwhelming majority of expenses record themselves, and no
inbound message is ever lost — including ones the app cannot yet parse.

**Ships:** a bank SMS arrives, an unconfirmed transaction appears with the right
amount and a guessed category. An unrecognised SMS becomes a one-screen "teach
me this format" flow that also backfills every past message it matches.

**Schema versions:** v10–v19 reserved. Expect to use **v10**.
**Branch:** `phase/2-capture` · **Gate tag:** `phase-2-complete`

---

## This phase splits in two

The split exists because 2A has no dependency on Phase 1 and can be built in
parallel with it.

| | Depends on | Nature |
|---|---|---|
| **2A — Parsing domain** | Phase 0 only | Pure Dart. Tokenizer, regex generator, matcher, dedup hashing. No UI, no database, no Android. |
| **2B — Capture pipeline** | Phase 0, 1, 2A | Android native buffer, receiver, ingestion, teach-template UI, review inbox. |

If you are running 2A alone, everything below marked **[2B]** is out of scope
for you — stop at a fully tested `nimbus_domain/src/parsing/` and tag
`phase-2a-complete`.

---

## Prerequisites — verify, do not assume

```bash
git tag --list 'phase-*-complete'   # 2A needs phase-0-complete
                                    # 2B needs phase-0-complete, phase-1-complete, phase-2a-complete
dart analyze --fatal-infos
```

**[2B]** You also need real sample messages. Collect at least a dozen genuine
bank SMS bodies (amount, merchant, date, card, balance variants) **plus
deliberate near-misses** — promotional messages from the same sender, OTP
codes, balance-only notifications. The near-misses are what stop a greedy regex
from turning an OTP into a 500,000-Toman expense.

---

## Required reading

- Spec: "Two capture sources, one pipeline", "Reliability: native-first
  buffering", "1. Capture pipeline", and the `captured_messages`,
  `message_templates`, `merchant_rules` table definitions
- `packages/nimbus_domain/lib/src/money/digits.dart` — digit normalization
- **[2B]** `TransactionRepository`, `TransactionDraft`, `CategoryPredictor` from
  Phase 1 (`app/lib/features/transactions/`, `nimbus_domain/src/prediction/`)

---

## Owns

```
packages/nimbus_domain/lib/src/parsing/**                    [2A]
packages/nimbus_data/lib/src/tables/captured_messages_table.dart      [2B]
packages/nimbus_data/lib/src/tables/message_templates_table.dart      [2B]
packages/nimbus_data/lib/src/tables/merchant_rules_table.dart         [2B]
packages/nimbus_data/lib/src/capture/**                      [2B]
app/lib/features/capture/**                                  [2B]
app/android/**/capture/**                                    [2B]
```

**Must not touch:** `analytics/`, `trackers/`, `goals/`, `backup/`,
`app/android/**/widget/**` (Phase 6).

---

## Scope

**In [2A]:**

- Tokenizer: split a message into literal runs, number runs, and date-like runs.
- Role model: `amount`, `merchant`, `date`, `card`, `balance`.
- Regex generator: escape every literal, substitute tolerant named capture
  groups for the tapped tokens, tolerate variable whitespace and digit
  separators.
- Digit normalization: Persian (U+06F0–06F9) and Arabic-Indic (U+0660–0669) to
  Latin before matching.
- `TemplateMatcher`: apply templates by priority, return typed fields.
- `amount_scale`: per-template divisor (Iranian bank SMS quote **Rial** while
  the app stores **Toman**).
- `direction_rule`: fixed, or keyword-driven, to tell debits from credits.
- `dedupHash(sender, body, receivedAt)`: sender + normalized body + minute
  bucket.

**In [2B]:**

- `MessageSource` contract with two implementations: `SmsSource`
  (BroadcastReceiver + `RECEIVE_SMS`, **personal flavor only**) and
  `NotificationSource` (`NotificationListenerService`, store flavor).
- Native-side buffer (Kotlin + Room) written to synchronously inside
  `onReceive`, drained by Dart on next launch and opportunistically when the
  engine is running.
- `CaptureIngestor`: persist raw → dedup → match templates → build an
  unconfirmed transaction via `TransactionRepository` → apply merchant rules
  for a best-guess category.
- Teach-template UI: paste sample → tap tokens to assign roles → live preview
  (including the Rial/Toman scale) → test against stored unmatched messages →
  offer backfill.
- Review inbox: swipe through unconfirmed captures. One tap sets category;
  optionally two more set necessity and satisfaction.
- Merchant rules: written automatically the first time a captured expense with
  a merchant string is categorized.
- Build flavors: `personal` and `store`, with different manifests.
- Optional: fetch a static `templates.json` registry over HTTPS with ETag
  caching. **Must degrade silently when unreachable.**

**Out:** analytics on captured data, receipt OCR, recurring detection,
multi-device dedup.

---

## Data model delta (schema v10)

Per `CONVENTIONS.md` §2, land this as one small commit before feature work.

- `captured_messages` — `source_kind`, `sender`, `package_name?`, `body`,
  `received_at`, `template_id?`, `transaction_id?`,
  `status` (parsed|unmatched|ignored|duplicate), **`dedup_hash TEXT UNIQUE`**.
- `message_templates` — `name`, `source_kind`, `sender_pattern`,
  `package_name?`, `regex`, `field_map` (JSON), `amount_scale`,
  `direction_rule`, `default_category_id?`, `default_payment_method_id?`,
  `sample_body`, `priority`, `enabled`, `match_count`, `last_matched_at`.
- `merchant_rules` — `match_type` (exact|contains|regex), `pattern`,
  `category_id`, `tag_ids` (JSON), `payment_method_id?`, `hit_count`,
  `source` (learned|manual).

---

## Interfaces produced

- `MessageSource` — `Stream<RawMessage> messages()`; both implementations emit
  an identical `RawMessage`.
- `CaptureIngestor.ingest(RawMessage) → IngestResult` (parsed | unmatched |
  duplicate | ignored).
- `MerchantRuleCategoryPredictor implements CategoryPredictor` — the Phase 2
  replacement registered in place of Phase 1's MRU predictor. **The add-expense
  UI must not change to accommodate it.**

---

## Known traps

Capture is where silent data loss hides. Each of these has a test.

- **Persist the raw message before parsing is attempted.** Non-negotiable. A
  parser bug must lose nothing; re-parsing after a fix is what makes that true.
- **`dedup_hash` is `UNIQUE` at the database level**, not checked in Dart.
  Double-counting must be structurally impossible, not merely unlikely.
- **Rial vs Toman.** Get `amount_scale` wrong and every captured number is 10×
  off — the single most damaging bug available in this phase. The teaching UI
  shows a live formatted preview so the user confirms the magnitude themselves.
- **Dart must never be on the critical path.** Doze and OEM battery managers
  (Xiaomi, Samsung, Huawei — common on target devices) kill background
  isolates. The native receiver writes to the native buffer synchronously, then
  returns. If you find yourself starting a Dart engine inside `onReceive`, stop.
- **Backfill must run through the same dedup path** as live ingestion, or
  teaching a template double-counts history.
- **Test against near-misses, not just matches.** A regex that also matches an
  OTP message is worse than one that matches nothing.
- **`RECEIVE_SMS` only exists in the personal flavor.** Google Play forbids it
  for any app that is not the device's default SMS handler, with no exception
  for expense tracking. Adding it to the store manifest is an automatic
  rejection. Set the flavors up before the manifest work, not after.
- **A message with no merchant is still useful.** Amount, date, and card still
  fill in; review makes categorizing one tap. Do not discard it.
- **`templates.json` is optional infrastructure.** Unreachable server means the
  user teaches a template manually — never an error dialog, never a blocked
  first run.

---

## Task outline

**2A** — 1. tokenizer · 2. role model + field map · 3. digit normalization ·
4. regex generator (escape-everything, tolerant groups) · 5. `TemplateMatcher`
with priority · 6. `amount_scale` and `direction_rule` · 7. `dedupHash` ·
8. corpus test: real messages plus near-misses.

**2B** — 9. schema v10 (take the lock) · 10. Kotlin `MessageBuffer` + Room ·
11. `SmsReceiver` + build flavors · 12. `MessageSource` + drain-on-launch ·
13. `CaptureIngestor` with the four outcomes tested · 14. merchant rules +
`MerchantRuleCategoryPredictor` · 15. teach-template UI with live preview ·
16. backfill against stored unmatched messages · 17. review inbox ·
18. `NotificationSource` for the store flavor · 19. optional templates.json ·
20. on-device verification.

---

## Definition of done

`CONVENTIONS.md` §5, plus **manual verification on a real device** — this is the
whole point of the native buffer and cannot be tested on the host:

- [ ] Send a test SMS with the app **force-stopped**; it appears on next launch.
- [ ] **Reboot the phone**, send another; it appears on next launch.
- [ ] Send the same message twice; exactly one transaction exists.
- [ ] Send an unparseable message; it is stored and surfaced, never dropped.
- [ ] Teach a template; past matching messages are offered for backfill and
      importing them creates no duplicates.
- [ ] The store flavor builds with **no SMS permission in its manifest**.
- [ ] `git tag phase-2-complete`.

---

## Parallelism notes

**2A runs in parallel with Phase 1** — different directories, no shared files.

**2B runs in parallel with Phase 3, 4, and 7.** Avoid pairing 2B with Phase 6:
both do Android-native work and both touch manifests and build flavors, which
conflict tediously.
