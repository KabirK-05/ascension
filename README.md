# Ascension

Personal health manager for iOS. **Apple records the data; this app manages it.**

Single-user iOS app sitting on top of Apple Health and the Apple Watch Workout app —
planning training, logging food, scoring readiness, tracking recomp trends — and
exposing all of it to an AI assistant (Muse) as a read **and write** MCP connector.

This app never records a workout. The Watch does that.

## Layout

| Path | What |
|---|---|
| `app/` | Tuist-generated iOS app shell: 4 tabs, DI, entitlements |
| `packages/` | Local SPM packages — domain, engines, HealthKit, export, sync, design system, features |
| `edge/` | Cloudflare Worker: stateless MCP server + sync API over D1 |
| `mcp-local/` | Read-only stdio MCP server over the iCloud Drive export folder |
| `docs/` | Spec, architecture, design rules, delivery workflow, build plan |

## Start here

- [`docs/PLAN.md`](docs/PLAN.md) — the 18 tickets and their dependency waves
- [`docs/TECH_STACK.md`](docs/TECH_STACK.md) — stack, module graph, the two-way sync architecture
- [`docs/DESIGN_RULES.md`](docs/DESIGN_RULES.md) — **read before any UI work**
- [`docs/MUSE_CAPABILITIES.md`](docs/MUSE_CAPABILITIES.md) — the MCP tool contract
- [`docs/DELIVERY.md`](docs/DELIVERY.md) — branches, CI, definition of done

## Setup

Requires Xcode 26+ (iOS 26 SDK), Tuist, SwiftLint, node 20+.

Tuist has no Homebrew bottle on macOS 26, so `brew install tuist` compiles from
source and takes a while. The quicker route is mise:

```
curl https://mise.run | sh && mise use -g tuist swiftlint
```

Or let Homebrew build them in the background:

```
brew install tuist swiftlint
```

## Build

```
tuist generate      # the .xcodeproj is generated and gitignored
```

Per-module work needs no Tuist at all — each package builds standalone:

```
swift test --package-path packages/AscensionEngines
```

Device builds need your Apple Developer team set in Xcode's signing tab; the
simulator needs nothing. No health data lives in this repo, and API keys live in
Keychain (app) and `wrangler secret` (edge) — never in version control.

## Third-party data

- [free-exercise-db](https://github.com/yuhonas/free-exercise-db) — Unlicense (public domain), bundled locally
- [Open Food Facts](https://world.openfoodfacts.org) — ODbL; attribution surfaced in Settings → Credits
- [USDA FoodData Central](https://fdc.nal.usda.gov) — CC0
