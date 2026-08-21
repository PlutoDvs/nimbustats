# NimbuStats — Design & Implementation Plan

## Context

**The problem.** Daily expense tracking fails for one reason: friction. Every manual-entry app
dies in week two. The goal is an Android app where the overwhelming majority of expenses record
themselves (parsed from bank SMS), the remainder take under five seconds, and the payoff is
analytics deep enough to actually change behavior — not just a pie chart.

**Trajectory.** Personal-use app first, public Play Store release in the near future, with paid
features after that. Everything below is therefore built to be *shipped to strangers*, not just
to work on one phone: enforced module boundaries, an entitlement layer, and a capture design
that survives Play Store policy. Running cost is designed to stay at effectively zero.

**What makes this different from the hundred existing expense trackers:**

1. **Three independent labeling dimensions** on every expense — a single-select *category tree*,
   many *nestable tags*, and an optional *necessity × satisfaction* verdict — freely
   cross-tabulated. "Within #travel, break down by category" and "how much avoidable-and-regretted
   money did I spend this month" are both first-class queries.
2. **User-taught SMS parsing.** No hardcoded bank regexes. Paste a sample, tap which parts are the
   amount and merchant, and the app builds the parser itself. Any bank, any country, no code change.
3. **Nothing is ever lost.** Every inbound message is persisted raw *before* parsing is attempted.
   An unparseable message becomes a prompt to teach a new template, never a silent gap.

**Repository state.** Greenfield — only an empty `README.md` and one commit.

**Division of labor.** The user designs all UI in **Claude Design**. This plan owns the data model,
capture pipeline, analytics engine, and business logic, and delivers a *screen contract* as the
input to that design work.

---

## Decisions (settled during brainstorming)

| Decision | Choice | Consequence |
|---|---|---|
| Platform | Android only | Full native integration available |
| Stack | Flutter + Dart | `drift`, `riverpod`, `fl_chart` |
| Structure | Local packages with compiler-enforced boundaries | UI *cannot* import the database |
| Distribution | Personal build now, Play Store soon | Drives the dual capture-source design |
| Monetization | Entitlement layer now, everything unlocked, gates later | Founding users grandfathered |
| Infrastructure | Zero-cost baseline; VPS optional and non-essential | App must work fully with the server unreachable |
| Storage | Local-first SQLite, sync-ready schema | UUIDv7 ids, `updated_at`, soft deletes |
| Sync | **Not built.** Backup only | One device. Sync is a separate future project |
| Backup | Android Auto Backup + encrypted export; Drive `appDataFolder` later | User's own storage, no server |
| DB encryption | None (backups encrypted instead) | Android FDE + sandbox cover the real threat |
| App lock | None | User's explicit choice |
| Currency | Single, user-selectable, Toman first-class | Integer minor units, no FX logic |
| Calendar | Jalali **and** Gregorian, switchable | All period math via a calendar abstraction |
| Language | Farsi RTL primary, English LTR switchable | RTL-first layout and localization |
| Entry | Bank SMS auto-capture + fast manual | Recurring and receipt OCR deferred |
| Capture UX | Silent capture, best-guess category, review later | Unconfirmed rows are real rows, flagged |
| Money scope | Expenses + income + payment-method dimension | No balances, transfers, or reconciliation |

---

## User experience: the primary constraint

Ease of use is the stated north star, so it is specified here as measurable requirements rather
than left as an aspiration. These are acceptance criteria, not aspirations — each is verified in
Phase 1 and re-verified at every later phase.

**Speed budgets**
- Repeat purchase logged in **≤ 3 taps**; any expense in **≤ 5 seconds**.
- Cold start to a usable transaction list **< 1 s** on a mid-range device.
- Add-expense reachable from the home-screen widget **without loading the full app graph**.
- Lists hold **60 fps** — paginated queries, never "load all transactions".

**Interaction rules**
- **Amount is the only required field.** The numeric keypad opens focused, on the amount, immediately.
- **Never show a spinner for a save.** All writes are local and optimistic; a SQLite insert is
  sub-millisecond, so the UI updates first and persists behind it.
- **Undo, never confirm.** Destructive actions show a snackbar with undo. Modal confirmation
  dialogs are pure friction and are not used.
- **Smart defaults over blank fields.** Category is predicted from merchant, time of day, and
  recent history; the top four candidates appear as one-tap chips.
- **Nothing blocks on the review queue.** Unconfirmed captures show a badge and never a modal.
- **One-handed reach.** Primary actions sit in the bottom third of the screen.
- **Zero-config first run.** A sensible localized category tree is seeded at install. Nobody
  should have to build a taxonomy before logging their first expense.
- Haptic confirmation on capture and on habit increments.

**Inclusivity** — dynamic type, sufficient contrast, and screen-reader labels are part of the
definition of done for every screen, not a later audit.

---

## Architecture

Four layers as **separate local packages**, so the dependency direction is enforced by the
compiler rather than by discipline. Folder conventions erode; pubspec boundaries do not.

```
packages/
  nimbus_domain/    pure Dart — money, calendar, parsing, analytics specs, goals, entitlements
                    NO Flutter dependency, NO database dependency
  nimbus_data/      drift database, DAOs, capture ingestion   → depends on domain only
  nimbus_design/    design tokens, theme, shared widgets      → depends on Flutter only
app/                screens, providers, platform channels     → depends on all three
```

The domain package having no Flutter dependency is what makes calendar math, money handling,
template generation, and goal evaluation unit-testable without a device or a widget tree — and
those four are where the bugs will actually be.

### Two capture sources, one pipeline

Google Play forbids `READ_SMS`/`RECEIVE_SMS` for any app that is not the device's default SMS
handler, with no exception for expense tracking. Irrelevant to a sideloaded build; fatal to a
store release. Therefore:

```
SmsSource            (BroadcastReceiver, RECEIVE_SMS)      ← personal build flavor
NotificationSource   (NotificationListenerService)         ← store build flavor
        │
        └──► [ native buffer ] ──► CaptureIngestor ──► templates ──► transaction
```

Both implement one `MessageSource` contract emitting an identical `RawMessage`. Everything
downstream is shared, so store compliance is a build-flavor change rather than a rewrite. The
store flavor additionally needs `FOREGROUND_SERVICE_SPECIAL_USE` and a justification video at
review time.

### Reliability: native-first buffering

**Do not** depend on a Dart background isolate being alive when an SMS arrives. Doze mode and
aggressive OEM battery managers (Xiaomi, Samsung, Huawei — common on target devices) kill it, and
a killed isolate means a silently missed transaction.

The Android receiver writes the raw message to a **native-side buffer** synchronously inside
`onReceive`, before Dart is involved at all. Flutter drains that buffer on next launch, and
opportunistically live when the engine happens to be running. Capture then becomes as reliable as
the OS delivering the broadcast.

---

## Data model

Every table carries `id TEXT PRIMARY KEY` (UUIDv7, time-ordered), `created_at`, `updated_at`
(epoch ms UTC), `deleted_at` (nullable soft delete). That is the sync-ready baseline.

### Date storage — the load-bearing decision

Each transaction stores `occurred_at_utc INTEGER` plus **`local_date_key INTEGER`** (`YYYYMMDD`
in the device's local *Gregorian* date).

Jalali↔Gregorian is a bijection on calendar dates, so the analytics layer computes period
boundaries **in the active calendar**, converts those two boundaries to Gregorian keys, and runs
an indexed range scan. One indexed column serves both calendars, nothing goes stale when the user
switches, and no per-calendar denormalization exists.

### Tables

**`categories`** — `name`, `icon_key`, `color`, `parent_id`, `path`, `depth`, `sort_order`,
`kind` (expense|income), `archived`. Hierarchy uses a **materialized path** (`/rootId/childId/`),
so subtree rollup is an indexed prefix scan rather than a recursive CTE per aggregation. Paths
rebuild transactionally on move; a recursive-CTE equivalent serves as the test oracle.

**`tags`** — same shape (`parent_id`, `path`, `depth`) plus `usage_count` for suggestion ranking.
Nestable, so `#travel > #turkey-2026` rolls up automatically.

**`transactions`** — `direction` (expense|income), `amount_minor INTEGER`, `currency_code`,
`occurred_at_utc`, `local_date_key`, `tz_offset_minutes`, `category_id` (**required**, defaulting
to a system "Uncategorized" row so no chart has holes), `payment_method_id?`, `merchant?`, `note?`,
`necessity?` (needed|optional|avoidable), `satisfaction?` (glad|neutral|regret),
`source` (manual|sms|notification|widget), `is_confirmed`, `capture_id?`.
Indexes: `local_date_key`, `category_id`, `(is_confirmed, local_date_key)`, `merchant`.

**`transaction_tags`** — join, PK `(transaction_id, tag_id)`, secondary index on `tag_id`.

**`payment_methods`** — `name`, `kind` (cash|card|bank|other), `last4?`, `color`, `icon_key`,
`archived`. A pure analytics dimension — **no balances**, so nothing ever needs reconciling.

**`captured_messages`** — the reliability backbone. `source_kind`, `sender`, `package_name?`,
`body`, `received_at`, `template_id?`, `transaction_id?`,
`status` (parsed|unmatched|ignored|duplicate), `dedup_hash TEXT UNIQUE`.
Persisted **before** parsing. Consequences: a parser bug loses nothing (re-parse after fixing),
unmatched messages become the "teach me this format" queue, and the unique hash (sender +
normalized body + minute bucket) makes double-counting structurally impossible.

**`message_templates`** — `name`, `source_kind`, `sender_pattern`, `package_name?`, `regex`,
`field_map` (JSON — which named group is amount/merchant/date/card/balance),
**`amount_scale`** (Iranian bank SMS quote *Rial* while the app stores *Toman*; a per-template ÷10
handles it explicitly), `direction_rule` (fixed or keyword-driven, to tell debits from credits),
`default_category_id?`, `default_payment_method_id?`, `sample_body`, `priority`, `enabled`,
`match_count`, `last_matched_at`.

**`merchant_rules`** — auto-categorization memory. `match_type` (exact|contains|regex), `pattern`,
`category_id`, `tag_ids` (JSON), `payment_method_id?`, `hit_count`, `source` (learned|manual).
Written automatically the first time a captured expense with a merchant string is categorized;
every later match from that merchant needs zero taps.

**`trackers`** — `name`, `icon_key`, `color`, `type` (counter|boolean|quantity|duration), `unit?`,
`archived`, `sort_order`.
**`tracker_entries`** — `tracker_id`, `value REAL`, `occurred_at_utc`, `local_date_key`, `note?`.
Per-increment timestamps mean time-of-day habit patterns come for free.

**`goals`** — one table, one engine, all four goal types:
`metric` (money_sum | txn_count | tracker_sum | tracker_count | net_savings),
`scope` (JSON: category subtree, tag set with AND/OR, payment methods, necessity/satisfaction,
tracker id), `direction` (at_most | at_least), `target_value`,
`period` (day|week|month|quarter|year|rolling_n_days|fixed_range),
`calendar` (jalali|gregorian — a period is meaningless without one), `start_date`, `end_date?`,
`alert_thresholds` (JSON, default `[0.8, 1.0]`), `active`.
A dining-out budget and a five-cigarettes-a-day limit differ only by field values.

**`goal_period_results`** — cached per-period outcome so streaks and history render without
recomputing every period on open. Lazily rebuilt; always derivable from source data.

**`saved_views`** — `name`, `filter` (JSON QuerySpec), `group_by`, `chart_type`, `period`, `pinned`,
`sort_order`. This is what makes the analysis genuinely dynamic: any supported filter combination
can be pinned to the dashboard permanently.

**`settings`** — currency, calendar, locale, first day of week, theme, reminder time,
`founding_user`, `installed_at`.

---

## The three subsystems

### 1. Capture pipeline

**Template learning flow** — the feature that makes this work for any bank:

1. User pastes a sample SMS.
2. Tokenizer splits it, highlighting every number, date-like run, and word-run.
3. User taps tokens and assigns roles: *amount*, *merchant*, *date*, *card*, *balance*.
4. Generator escapes all literal text and substitutes tolerant named capture groups for the tapped
   tokens. Digit separators, Persian/Arabic-Indic digits, and variable whitespace are normalized
   before matching.
5. **The new template is immediately tested against every stored unmatched message from that
   sender** — the UI can say *"this also matches 14 past messages worth 3.2M — import them?"*.
   Free, because every raw message was persisted.
6. Saved. Future messages parse automatically.

**Ingestion:** raw message → dedup check → templates by priority → on match, build an *unconfirmed*
transaction applying `merchant_rules` for a best-guess category → on no match, mark `unmatched` and
surface a gentle "teach me this?" prompt.

**Review screen:** a fast swipe-through of unconfirmed captures. One tap sets category; optionally
two more set necessity and satisfaction. Categorizing a merchant writes a `merchant_rule`, so the
queue shrinks toward zero as the app learns.

**Design constraint:** necessity and satisfaction never appear in the add-expense flow — only in
the review screen, where the user is already reflecting. Extra taps in the add path are exactly
what kills daily tracking.

### 2. Analytics engine

A `QuerySpec` value object compiles to SQL. One engine serves every screen, every saved view, and
every goal evaluation — no bespoke queries per chart.

- **Filters:** date range, direction, category subtree(s), tags (AND/OR/NOT over subtrees), payment
  method, necessity, satisfaction, amount range, confirmed-only, text search.
- **Group by:** category at any depth, tag, day/week/month/quarter/year, payment method, merchant,
  necessity × satisfaction, hour-of-day, day-of-week.
- **Aggregate:** sum, count, average, min, max.

Covers everything requested — drill-down, tag × category cross-tab, trends and period comparison,
behavioral patterns, pinnable saved views — as different `QuerySpec`s rather than different code.

**Two correctness traps handled explicitly:**

- **Tag breakdowns double-count.** An expense tagged `#travel` *and* `#food` lands in both buckets,
  so tag sums exceed the true total. The engine returns the true total alongside the buckets, and
  the UI must say so rather than render a pie chart that quietly lies.
- **Nested tag rollup must deduplicate.** An expense tagged with both a parent and its child counts
  once when rolled up to the parent.

### 3. Goal engine

`evaluate(goal, period) → {current, target, status, projection}` — pure and unit-testable. One
implementation covers spending caps, habit maximums, habit minimums, and savings targets, because
all four reduce to *"aggregate metric M over period P, compare to T in direction D."*

Alerts fire on threshold crossings (80%, 100%) rather than on a schedule, so warnings arrive while
there is still time to act. Savings targets use `fixed_range` and report required run-rate rather
than period progress.

---

## Monetization & entitlements

Everything ships **unlocked**; the gating machinery is built now so switching it on later is
configuration rather than surgery.

- **`Entitlements` service in the domain package** — a single `bool has(Feature)` call. Gate checks
  live in one `FeatureGate` widget, never scattered through the UI.
- **`Feature` enum:** `unlimitedTemplates`, `advancedAnalytics`, `cloudBackup`. Backed by a
  swappable `EntitlementSource` — `AlwaysUnlocked` now, Play Billing later.
- **Premium features are labeled** "Pro — free during early access" from day one, so the future
  paywall is expected rather than resented.
- **Founding users are grandfathered.** A `founding_user` flag persists at first run before a
  cutoff date, permanently retaining full access. This is the mitigation for the known backlash
  risk of adding a paywall to an app whose users already have everything.
- **Play Billing needs no server** — entitlements verify against the user's Google account. Paid
  cloud backup uses the user's *own* Drive quota, so revenue carries no marginal infrastructure cost.

---

## Infrastructure & running cost

**Baseline is zero.** No backend, no database to host, no auth server. The only fixed cost is the
one-time $25 Play developer registration.

**The VPS is optional and non-essential.** One hard rule: **the app must function completely with
the server unreachable.** Anything server-side is a convenience that degrades silently.

- **Phase 2:** a static `templates.json` bank-template registry served over HTTPS — cached with
  ETag, so new users get their bank pre-configured without teaching a template. Costs nothing
  beyond bytes, needs no application server, and works equally well from a free CDN.
- **Later, optional:** anonymous crash and usage telemetry.
- Deployment specifics (host, path, web-server unit, TLS) **must be confirmed with the operator
  before Phase 2** rather than assumed.

---

## Working with Claude Design

The **screen contract** — every screen, its states (empty / loading / error / populated), the data
it consumes, and the actions it emits — is produced at the end of Phase 0 and is the input to
design work. Designing before states exist produces screens that cannot be built.

Practices that materially change the output quality:

1. **Lock the visual language on one screen first** — the add-expense screen, highest traffic and
   tightest constraints. Every other screen inherits its tokens. Consistency comes from settling
   tokens early, not from reconciling drift later.
2. **Design RTL first.** Designing LTR and mirroring afterwards breaks Farsi layouts in tedious
   ways — icon direction, number alignment, chart axes. Deriving LTR from RTL is far cheaper.
3. **Ask for the ugly states explicitly:** empty lists, nine-digit Toman amounts, forty-character
   merchant names, twenty tags on one expense, a failed parse. That is what month three looks like.
4. **Ask for a token sheet** — named colors, type ramp, spacing scale. It maps directly onto
   `nimbus_design`, so the design survives contact with code instead of being re-eyeballed per screen.

**Screen inventory:** onboarding · dashboard · add/edit transaction · transaction list · review
inbox · teach-template · category manager · tag manager · analytics (breakdown, trends, cross-tab,
patterns, regret matrix) · saved-view builder · trackers · tracker detail · goals · goal editor ·
settings · Pro screen (later).

---

## Build sequence

Each phase ends with something usable. TDD throughout (failing test → implement → green → broader
suite → commit), rollback tag `pre-<slug>` per phase.

- **Phase 0 — Foundation.** Package scaffold with enforced boundaries, drift schema + migrations,
  CI. Pure-domain `money/` and `calendar/` with full unit tests. RTL + Farsi/English localization.
  Entitlement layer. **Deliverable: the screen contract for Claude Design.**
- **Phase 1 — Expenses (usable daily).** Categories, tags, payment methods, add flow, list,
  edit/delete, first-run seeding. **Real daily use starts here**, which is what makes the later
  analytics decisions grounded rather than speculative. UX budgets verified.
- **Phase 2 — Capture.** Native buffer + SMS receiver, `captured_messages`, tokenizer and template
  generator, teaching UI, ingestion, merchant rules, review screen, optional template registry.
- **Phase 3 — Analytics.** `QuerySpec` engine, drill-down, cross-tab, trends, comparison,
  behavioral patterns, necessity × satisfaction matrix, saved views, dashboard.
- **Phase 4 — Trackers.** All four types, entry surfaces, per-tracker history and patterns.
- **Phase 5 — Goals & limits.** Goal engine, all four types, progress UI, threshold alerts.
- **Phase 6 — Outside-the-app.** Home-screen widget (one-tap expense + habit counters), budget and
  limit alerts, configurable daily reminder.
- **Phase 7 — Backup.** Android Auto Backup with correct SQLite WAL checkpointing, plus
  passphrase-encrypted export/import.
- **Phase 8 — Public release.** Store build flavor (`NotificationListenerService` +
  `FOREGROUND_SERVICE_SPECIAL_USE`), privacy policy, Data Safety declaration, crash reporting,
  store listing. Drive `appDataFolder` backup and Play Billing activation follow.

---

## Key files

```
packages/nimbus_domain/lib/   money/  calendar/  parsing/  analytics/  goals/  entitlements/
packages/nimbus_data/lib/     database.dart  tables/  daos/  capture/
packages/nimbus_design/lib/   tokens.dart  theme.dart  widgets/
app/lib/                      screens/  providers/  platform/
app/android/.../capture/      SmsReceiver.kt  NotificationListener.kt  MessageBuffer.kt
app/android/.../widget/       ExpenseWidgetProvider.kt
```

Critical files: `nimbus_domain/calendar/` (every period calculation), `nimbus_domain/parsing/`
(template generation), `nimbus_domain/analytics/query_spec.dart` (all reporting),
`nimbus_data/capture/capture_ingestor.dart` (the no-data-loss guarantee), and `MessageBuffer.kt`
(the reliability boundary).

---

## Verification

**Unit (pure domain, no device):** Jalali↔Gregorian round-trips including leap years and
month-length edges; period boundaries in both calendars across year transitions; Toman formatting,
grouping, short forms, Persian digits; template regex generation against a corpus of real bank SMS
plus deliberate near-misses; dedup hashing; goal evaluation for all four types including empty and
partial periods.

**Data layer:** materialized-path rollup verified against a recursive-CTE oracle on generated trees;
aggregations checked against hand-computed fixtures on a seeded database; **an explicit test that
tag breakdowns double-count as expected while the reported true total does not**; migration tests
across every schema version.

**Integration:** inject a raw message → assert an unconfirmed transaction with the right amount,
scale, and guessed category; inject it twice → assert one row; inject an unmatched message → assert
it is stored and surfaced, never dropped; teach a template → assert historical messages backfill.

**UX budgets (Phase 1 onward):** tap count for a repeat expense, cold-start time, and list frame
timings measured on a real mid-range device, not an emulator.

**Manual, on a real device:** send a test SMS with the app force-stopped; reboot the phone and send
another; confirm both appear on next launch. This is the OEM-battery-killer scenario that native
buffering exists to survive.

---

## Risks

| Risk | Mitigation |
|---|---|
| Play Store bans SMS permissions | Dual capture sources; store flavor uses `NotificationListenerService` + `FOREGROUND_SERVICE_SPECIAL_USE` with justification video |
| OEM battery managers kill background work | Native-side buffering; Dart never on the critical path; drain on launch |
| Paywall backlash after free launch | Features labeled "free during early access"; founding users permanently grandfathered |
| Bank SMS lacks a merchant name | Auto-capture still fills amount/date/card; review makes categorizing one tap |
| Rial vs Toman scaling errors | Per-template `amount_scale`, confirmed in the teaching UI with a live preview |
| Jalali period math bugs | Pure-domain calendar layer, exhaustively tested; no ad-hoc date math elsewhere |
| Feature creep across four subsystems | Strict phase gates; each phase ships usable before the next begins |
| Layering erodes as the app grows | Package boundaries enforced by the compiler, not by convention |

## Explicitly out of scope

Sync, account balances and transfers, multi-currency and FX, receipt OCR, recurring transactions,
iOS, app lock/biometrics, and database encryption. The schema leaves room for the plausible ones;
none are built.
