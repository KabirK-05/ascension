# Ascension — Tech Stack & Architecture

Verified against this machine: Xcode 26.6 (build 17F113), iOS 26.5 SDK, iOS 26.5
simulator, Swift 6.3.3, node 20.18.1, gh 2.87.3 authed as `KabirK-05`.

---

## 1. iOS app

| Concern | Choice | Why |
|---|---|---|
| UI | SwiftUI, iOS 26 deployment target | Spec §8. SDK present locally. |
| Persistence | SwiftData | Spec §8. CloudKit mirroring **off** in v1. |
| Language | Swift 6.3, strict concurrency | Catches data races at compile time. |
| Project file | **Tuist** (`Project.swift`) | See §1.1 — this is the key call. |
| Modules | Local SPM packages | Parallel-work isolation + testable on macOS. |
| Tests | Swift Testing (+ XCTest for UI) | Engines ship with tests (spec §8). |
| Lint | SwiftLint + swift-format | Enforced in CI. |
| Charts | Swift Charts | Spec §F6. Heatmap is custom (a grid, not a chart). |
| Barcode | VisionKit `DataScannerViewController` | Less code than raw AVFoundation. |
| On-device LLM | FoundationModels | iPhone 15 Pro+ confirmed, so F7's summaries are real on-device text, not templates. |

### 1.1 Why Tuist (the decision that makes parallel workers possible)

A committed `.xcodeproj` is a single XML file that **every** feature branch mutates.
With several worker branches open at once, every merge into `staging` conflicts in
`project.pbxproj`, and those conflicts are not meaningfully resolvable by hand.

Tuist generates the project from `Project.swift`. The `.xcodeproj` is **gitignored**
and never committed. Each worker edits its own package manifest. Merge conflicts in
the project file become structurally impossible.

### 1.2 Module layout

Pure-logic packages build and test on macOS in seconds, with no simulator — which
keeps CI cheap and makes the engines genuinely unit-testable.

```
packages/
  AscensionCore      SwiftData models (§7) + Codable DTOs. No UI. No HealthKit.
  AscensionEngines   Readiness (F5), trends (F6), calorie rules. Pure functions.
  HealthBridge       HealthKit read/write, mirrors (§6), background delivery.
  ExportKit          export.json, CSV, daily-log.md, summary-latest.md (§9.1).
  SyncClient         Cloudflare push/pull + mutation application.
  DesignSystem       Tokens, components, the consistency grid.
  SystemSurfaces     The shared day snapshot the widgets, App Intents and
                     notifications read, plus the streak rule (§F8).
  FeatureToday / FeatureTrain / FeatureEat / FeatureTrends
app/                 Thin shell: 4 tabs, Settings, DI wiring, entitlements.
widgets/             WidgetKit extension: Today, protein, streak.
```

Dependency rule, enforced in review: `Features → DesignSystem, Core, Engines`.
`Core` and `Engines` depend on **nothing**. No feature imports another feature.
`SystemSurfaces` depends on `Core` and `Engines` only, because the widget extension
links it and a feature in that process would drag four screens into a target that
draws one number.

The widget extension and the app share the app group
`group.com.kabirkumar.ascension`. A widget runs in its own process with no HealthKit
authorization and no SwiftData container, so the app writes `surface.json` into that
group after every refresh and the widgets read it — which is also why a widget can
never disagree with the tab behind it.

---

## 2. The cloud bridge (Cloudflare)

### 2.1 Why it is unavoidable

The spec (§9.3) proposes a local stdio MCP server over an iCloud Drive folder. That
cannot serve the stated requirement, for two independent reasons:

1. **Meta Muse reaches custom connectors from Meta's cloud**, so the endpoint must be
   public HTTPS. The same is true of Claude on mobile — connectors are configured on
   claude.ai and cannot run local processes.
2. **Muse must write** (schedules, calorie goals, "all other details"). Files in a
   folder have no auth, no validation, and no conflict handling.

So: a deliberately small Cloudflare footprint. Workers + D1 and nothing else. No R2
(rollups are kilobytes), no Durable Objects, no KV.

### 2.2 Current Cloudflare MCP shape

Cloudflare has **deprecated `McpAgent`** and now documents a **stateless
`createMcpHandler`** server over **Streamable HTTP** (SSE is deprecated). Stateless
suits us: no Durable Objects, no hibernation billing, less to go wrong.

Auth is `@cloudflare/workers-oauth-provider`, which implements the OAuth 2.1 + PKCE
requirements that Claude and Muse custom connectors expect. A bearer-token header is
not an option in Claude's connector UI (authless or OAuth only), and an unguessable
URL is not acceptable for health data — so OAuth it is. The provider makes this small.

### 2.3 Two data streams

The critical insight: **observed data and intent flow in opposite directions.** Keeping
them separate removes almost all of the sync complexity.

**Stream A — observed (phone → cloud, one-way, immutable).**
The phone computes one `DayRollup` per day and upserts it, keyed by date:

> date, kcal, protein, fat, carbs, steps, sleepMinutes, restingHR, hrvSDNN, weightKg,
> weightAvg7, readinessScore, verdict, reasons[], sessionPlanned, sessionDone,
> workoutType, workoutMinutes, activeEnergy, hrAvg, hrMax, timeInZones, topSets[],
> soreness, energy, proteinHit, stepsHit, sleepHit, sessionHit

`POST /v1/ingest` is idempotent (upsert on date). Runs nightly via
`BGProcessingTask`, on app foreground, and after any manual export.

Daily rollups only — your chosen scope. No raw HR series, no per-meal rows, no sleep
stages leave the device. The grid's four daily wins are exactly the `*Hit` booleans,
so the rollup is also what powers Today.

**Stream B — intent (cloud ↔ phone, two-way, mutable).**
D1 holds the authoritative copy of the few documents Muse may change:

```
documents(key, version, json, updatedAt, updatedBy)   -- goalSettings | program | flags
mutations(id, createdAt, actor, kind, payload, appliedAt)  -- append-only
```

- A Muse write tool validates input (zod), appends a `mutation`, bumps the document
  `version`.
- The phone pulls `GET /v1/mutations?since=<cursor>` on foreground and background
  refresh, applies them in order, then `POST /v1/mutations/ack`.
- A phone-side edit does `PUT /v1/documents/<key>` with `If-Match: <version>`. On 409
  the phone refetches, merges last-write-wins per field by timestamp, and retries.

### 2.4 The HealthKit write constraint (state this plainly)

**HealthKit can only be written from the device.** When Muse logs a meal, that mutation
sits in D1 until the phone applies it and writes the dietary samples to Apple Health.
This is a platform constraint, not a design choice.

With the paid Apple Developer account confirmed, the Worker sends a **silent APNs push**
(`content-available`) on every queued mutation, so the phone wakes and applies it in
**seconds**. The foreground/background-refresh path remains the fallback for when push
is throttled or the device is offline — so correctness never depends on push arriving.

### 2.5 MCP tools

Read: `get_today`, `get_workouts`, `get_nutrition`, `get_weight_trend`,
`get_readiness`, `get_checkins`, `get_exercise_history`, `get_consistency_grid`.

Write: `set_targets` (calories/protein/fat), `update_program` (schedule/exercises),
`log_meal`, `log_water`, `log_top_set`, `log_checkin`, `accept_suggestion`,
`set_flag`.

Every response carries `schemaVersion`. Writes are allowlisted and schema-validated;
no delete tools in v1. `log_*` tools return `"pending_device_apply"` so the assistant
never claims a Health write already landed.

### 2.6 Privacy posture

- D1 stores rollups and config only. No name, no email, no DOB. `deviceId` is a
  random UUID generated on first launch.
- Phone↔Worker uses a device token in Keychain, separate from the OAuth client.
- Rolling 400-day retention; `DELETE /v1/account` wipes everything.
- Secrets live in `wrangler secret` and Keychain. **Never in the repo** (spec §8).

### 2.7 Feature flags

A `flags` document in D1, read by both the Worker and the app at runtime, per your
standing rule: launch-phase behaviour is a flag flip, never a code change or a
resubmission. v1 flags: `remoteBridgeEnabled`, `museWritesEnabled`,
`rawDetailSyncEnabled` (off — the escape hatch to full-detail sync),
`foundationModelsEnabled`.

---

## 3. Local stdio MCP (kept, demoted)

`mcp-local/` still ships: a read-only stdio server over the iCloud Drive export
folder, for Claude Code on your Mac. It needs no network, no auth, and no cloud, and
it is the fallback if you ever switch the bridge off. Built late (ASC-17), because the
cloud path is what you actually asked for.

---

## 4. Repo

`github.com/KabirK-05/ascension`, **public** — code only, no health data, keys in
Keychain. Public buys free unlimited macOS Actions minutes (a private personal repo
gets ~200 macOS minutes/month at the 10× multiplier) and free branch-protection
rulesets.

```
app/  packages/  edge/  mcp-local/  docs/  .github/
```

Monorepo, because the export schema is a contract shared by the app, the Worker, and
both MCP servers. Splitting them would mean versioning that contract across repos on
day one.
