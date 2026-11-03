# Ascension — Build Plan

18 tickets in 5 waves. Wave boundaries are real dependency barriers; everything
within a wave is genuinely parallel — disjoint packages, no shared files.

Slice order follows the spec's §11 intent (data access early, because that is the
point of the app), re-sequenced for the two-way cloud bridge.

---

## Wave 0 — Foundation (serial, orchestrator)

Everything blocks on this, so it is not parallelised.

**ASC-1 — Repo, tooling, scaffold, contracts**
- `git init`; `main` + `staging`; public repo `KabirK-05/ascension`; rulesets.
- Tuist project, the 10 SPM packages as empty compiling targets, 4-tab shell.
- SwiftLint, swift-format, CI workflows, PR template, `.gitignore`.
- `docs/`: this plan, TECH_STACK, DESIGN_RULES, DELIVERY, MUSE_CAPABILITIES,
  **EXPORT_SCHEMA.md v1** (the rollup + document contract — this is what unblocks the
  edge work in parallel with the app work), `CLAUDE.md` pointing workers at the rules.
- **Done:** `tuist generate && xcodebuild build` green in CI; empty 4-tab app runs on
  the iOS 26.5 simulator.

---

## Wave 1 — Contracts in code (3 parallel)

**ASC-2 — Domain model + seed data** · `AscensionCore`
All §7 entities as SwiftData models plus Codable DTOs. `GoalSettings` seeded from §2,
`Program` seeded from the §3 Upper/Lower split, staple foods, the ~15 program
exercises. Model must hold both program shapes (§3). Round-trip tests.

**ASC-3 — Design system + Mobbin pass** · `DesignSystem`
Mobbin research (Whoop/Oura readiness, Strong/Hevy history, Apple Fitness trends),
tokens, and the small component set: value row, ring, stat card, **the consistency
grid (§6 of DESIGN_RULES)**. Dark-first, both modes. Zero subtitles — this ticket sets
the bar every feature ticket inherits.

**ASC-4 — Edge: Worker + D1 + read tools** · `edge/`
Stateless `createMcpHandler` over Streamable HTTP, `workers-oauth-provider`, D1 schema
(`rollups`, `documents`, `mutations`), `POST /v1/ingest`, and all Tier-3 read tools.
Verified with MCP Inspector against seeded fixture data, then deployed to your existing
Cloudflare account. Depends only on EXPORT_SCHEMA.md, so it runs fully parallel to the
app.

---

## Wave 2 — Data layer (4 parallel)

**ASC-5 — HealthBridge** · `HealthBridge`
Permissions flow, the §6 read map, observer queries + background delivery, idempotent
mirrors keyed on HealthKit UUIDs, and the write-back API for nutrition/water/weight.
Tested against a fake HealthKit store.

**ASC-6 — Engines** · `AscensionEngines`
Readiness (F5) with its verdicts and the hard muscle-group constraints; trends (F6);
weekly calorie auto-adjust; load/ACWR + deload detection. Pure functions over value
types, exhaustively unit-tested. **The highest-value ticket in the project.**

**ASC-7 — ExportKit** · `ExportKit`
`export.json`, CSV per entity, append-only `daily-log.md`, rolling `summary-latest.md`
(<150 lines), security-scoped iCloud Drive bookmark, atomic temp-file-plus-rename
writes, nightly scheduling. Golden-file tests.

**ASC-8 — Exercise library** · `AscensionCore` + `FeatureTrain`
free-exercise-db import (Unlicense) bundled locally — no runtime dependency. Search,
detail cards, and the curated cues/common-mistakes layer for the ~15 program exercises.

---

## Wave 3 — Features (4 parallel)

**ASC-9 — Today** · `FeatureToday` — readiness hero, session card with Send-to-Watch,
activity, calorie/protein rings, **the consistency grid**, one-line rule-based summary.
**ASC-10 — Train** · `FeatureTrain` — week view, planned-vs-done (EventKit ∩ HealthKit),
WorkoutKit `CustomWorkout` scheduling, post-workout debrief with time-in-zone, top-set
quick log.
**ASC-11 — Eat** · `FeatureEat` — staples quick-add as the primary path, diary, barcode
via Open Food Facts, search via USDA FoodData Central, manual foods, HealthKit
write-back, protein ring as the hero.
**ASC-12 — SyncClient** · `SyncClient` — rollup computation, `POST /v1/ingest`, mutation
pull/apply/ack, `If-Match` conflict handling, device token in Keychain, BGTask wiring,
and APNs device-token registration for the silent-push wake path.

---

## Wave 4 — Close the loop (5, mostly parallel)

**ASC-13 — Edge: write tools** · `edge/` — all Tier-1 and Tier-2 tools, zod validation,
server-side enforcement of the §F5 muscle-group and §2 dietary constraints, the
`pending_device_apply` contract, and the silent-APNs trigger (JWT-signed, from the
Worker) so queued mutations wake the phone immediately.
**ASC-14 — Check-in + readiness surfacing** — CareKit-style ≤10 s morning check-in,
verdicts with their top two reasons on Today.
**ASC-15 — Trends + weekly review** — weight 7-day average and rate of change, calorie
suggestions, load/deload, VO2/RHR/sleep trends, Sunday review (F7).
**ASC-16 — System surfaces** — widgets, App Intents/Siri, smart notifications (only the
four in §F8), optional Live Activity. Plus **Settings → Changes** with Muse-write undo.
**ASC-17 — Local stdio MCP** · `mcp-local/` — read-only server over the export folder,
for Claude Code on the Mac.

**ASC-18 — Acceptance** — the spec's own test (§9.3), extended for writes: with only
the connector attached, Muse answers "how is my training going this month?" accurately
**and** successfully changes a calorie target and swaps a session, with the phone
applying a queued `log_meal` into Apple Health.

---

## Maintenance tickets (found during the build, not planned up front)

**ASC-19 — Toolchain alignment**
Every package manifest built under laxer rules than the app target, which sets
`SWIFT_STRICT_CONCURRENCY=complete`. A Swift 6 concurrency error in `SyncClient`
therefore passed the package's own tests and only failed the `app` job (ASC-12, PR #9).
Pins `.swiftLanguageMode(.v6)` on every target so a package cannot pass while the app
it ships in does not compile. Also extends the opt-in simulator test list ASC-9 added
to CI — `FeatureEat`'s and `FeatureTrain`'s tests were not running anywhere.
Origin: an ASC-1 scaffolding gap.

**ASC-20 — Composition root**
Every feature package was built to receive HealthKit, networking and write-back through
protocols injected by the app shell — which is what keeps them building and testing with
no device, since CI has no HealthKit. No ticket owned that injection, so after twelve
merges `app/Sources/RootTabView.swift` was still the ASC-1 scaffold and nothing was
connected to anything. Adds the composition root, the app lifecycle (HealthKit
authorization and observers, the two background tasks, APNs, the nightly export), the
Send-to-Watch link both Today and Train leave to the shell, and a rollup ledger — the
store of `DayRollup`s that `AscensionSchema` has no entity for and that the grid, the
export and the Worker push all read.
Origin: a gap in this plan, not in any ticket's execution.

---

## Orchestration

| Wave | Parallel sessions | Blocks on |
|---|---|---|
| 0 | orchestrator, alone | — |
| 1 | 3 | ASC-1 |
| 2 | 4 | ASC-2 (+ ASC-3 for UI) |
| 3 | 4 | ASC-5, ASC-6, ASC-4 |
| 4 | 5 | Wave 3 |

Each session: own worktree, own branch cut from `staging`, own package, PR into
`staging`. No two concurrent sessions touch the same package — that is what makes the
wave boundaries safe.
