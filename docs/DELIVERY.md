# Ascension — Delivery Workflow

## Branches

```
main      production only. Protected. Accepts PRs from `staging` and nothing else.
staging   integration. Protected. Accepts PRs from ticket branches only.
asc/<id>-<slug>   one ticket, cut from `staging`, merged back by PR.
```

- `asc/6-edge-mcp-read`, `asc/9-train-tab`. Cut from `staging`, **never** from `main`.
- Ticket → `staging`: **squash merge**. One ticket, one commit on staging.
- `staging` → `main`: **merge commit**, PR titled `release: <summary>`, tagged
  `v0.N.0`. This is the only path to `main`.
- Branch deleted on merge.

## Enforcement (GitHub rulesets, applied at setup)

On both `main` and `staging`: require a PR, require passing status checks, block force
pushes, dismiss stale approvals. On `main` additionally: restrict the merge source to
`staging`. Public repo, so rulesets cost nothing.

A worker that cannot push to `staging` directly is working correctly.

## CI (`.github/workflows/`)

Three jobs, ordered cheapest-first so failures surface fast:

| Job | Trigger | What |
|---|---|---|
| `lint` | every PR | SwiftLint, swift-format check, `tsc --noEmit`, prettier. ~30 s, ubuntu + macos. |
| `packages` | every PR | `swift test` on `AscensionCore`, `AscensionEngines`, `ExportKit`, `SyncClient` for **macOS**. No simulator → fast and cheap. This is where the engine tests live. |
| `app` | every PR | `tuist generate` + `xcodebuild build-for-testing` on the iOS 26.5 simulator. |
| `edge` | PRs touching `edge/` | `vitest` against `wrangler dev` with a local D1. |
| `release` | PRs into `main` | All of the above + `xcodebuild test` with UI smoke tests. |

Pure-Swift packages test on macOS without booting a simulator, which keeps the common
path to well under two minutes.

## Commits

Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`.
Subject in the imperative, under 72 chars. Reference the ticket: `feat(edge): add
get_consistency_grid tool (ASC-6)`.

## PR template

Every PR body:
- **Ticket** — ASC-N
- **What changed** — a few lines, not a changelog
- **Verification** — the command you ran and its result. Not "should work".
- UI PRs additionally: light + dark screenshots, the one question the screen answers,
  and **what you removed** (`docs/DESIGN_RULES.md` §7.3).

## Definition of done

A ticket is done when: CI green, tests cover the new logic, `docs/` updated if a
contract changed, and `EXPORT_SCHEMA.md` bumped if a field changed shape. Engines
(readiness, trends, calorie rules) ship with unit tests — the spec calls them the
product (§8), and they are the one thing a worker may not merge untested.

## Worker rules

- One ticket, one branch, one package. Do not edit another ticket's package.
- `.xcodeproj` is generated and gitignored. Never commit it.
- Never commit a secret. API keys go to Keychain (app) or `wrangler secret` (edge).
- Read `docs/DESIGN_RULES.md` before any UI work, and Mobbin MCP before any screen.
- Blocked on another ticket's contract? Stop and report. Do not stub around it.
