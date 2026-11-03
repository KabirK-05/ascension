# edge — Cloudflare Worker

The cloud bridge. A stateless MCP server over Streamable HTTP so Meta Muse and
Claude can read **and manage** Ascension from their own clouds, plus the
endpoints the phone pushes rollups to and drains write instructions from.

Why it exists, and why it is not a local file-watcher, is
[`../docs/TECH_STACK.md`](../docs/TECH_STACK.md) §2. The data contract is
[`../docs/EXPORT_SCHEMA.md`](../docs/EXPORT_SCHEMA.md) and this directory holds
no second copy of it: [`src/contract.ts`](src/contract.ts) is that document in
zod, and every field name on the edge comes from there.

**ASC-4** — Worker, D1, `POST /v1/ingest`, the eight Tier-3 read tools.
**ASC-13 (this)** — the eleven Tier-1 and Tier-2 write tools with their
guardrails, `GET /v1/mutations`, `POST /v1/mutations/ack`,
`GET|PUT /v1/documents/:key`, `GET|POST /v1/suggestions`,
`POST /v1/device/push-token`, and the silent-APNs trigger.

---

## Layout

```
migrations/     D1 schema, applied with `wrangler d1 migrations apply`
src/
  index.ts      OAuthProvider wiring and the non-MCP routes
  contract.ts   docs/EXPORT_SCHEMA.md in zod — the single source of field names
  dates.ts      calendar arithmetic on YYYY-MM-DD, clock-free
  guardrails.ts the invariants a write is rejected for -- §2 and §F5
  ulid.ts       mutation ids: monotonic, lexicographically ordered
  db/           rollups, documents, mutations, suggestions
  http/         the phone's endpoints, the consent page, response helpers
  mcp/          the stateless MCP server, the read tools and the write tools
  push/         the silent APNs wake
test/           vitest, running inside workerd against a real local D1
scripts/        seed a local `wrangler dev` with fixtures
```

## Routes

| Route | Auth | What |
|---|---|---|
| `POST /v1/ingest` | device token | Stream A. A batch of `DayRollup`, upserted on `date`. |
| `GET /v1/mutations?since=` | device token | Stream B. The write log's tail, in ULID order. |
| `POST /v1/mutations/ack` | device token | The ids the phone applied, and when it applied them. |
| `GET\|PUT /v1/documents/:key` | device token | The phone's own edit of a document Muse also writes. `If-Match`. |
| `GET\|POST /v1/suggestions` | device token | What is waiting for a one-tap accept, both halves of it. |
| `POST /v1/device/push-token` | device token | Where to send the silent wake. |
| `/mcp` | OAuth 2.1 | The MCP server, Streamable HTTP. |
| `/authorize` | password | The consent page. |
| `/oauth/token`, `/oauth/register` | — | Issued by `@cloudflare/workers-oauth-provider`. |
| `/.well-known/oauth-protected-resource`, `/.well-known/oauth-authorization-server` | — | RFC 9728 / RFC 8414 discovery. |
| `/`, `/health` | — | Status. No secrets, no data. |

### `POST /v1/ingest`

```
Authorization: Bearer <DEVICE_TOKEN>
Content-Type: application/json

{ "schemaVersion": 1, "rollups": [ { …DayRollup… } ] }
```

A bare array is accepted too. `schemaVersion` is optional and must be `1` when
present. Up to 400 rollups per batch.

Idempotent: the upsert is keyed on `date`, so the phone may re-send any day and
a corrected day simply replaces the earlier one.

**The whole batch is rejected if any rollup fails validation** — `400` with the
offending paths (`rollups.3.training.sessionPlanned`). An unknown enum value or
an extra field means the app and this contract have diverged, and that has to be
loud: a half-applied batch would leave the phone unable to tell what landed.

### The eight read tools

`get_today` · `get_workouts` · `get_nutrition` · `get_weight_trend` ·
`get_readiness` · `get_checkins` · `get_exercise_history` ·
`get_consistency_grid`

Every response is compact JSON carrying `schemaVersion`, and every windowed
response carries `asOf` — the most recent day the phone has synced. Muse sees
what the phone has pushed, not live HealthKit, so `asOf` is the difference
between "you did not train today" and "today has not synced yet".

`get_consistency_grid` returns 17 Monday-to-Sunday weeks — the 7×17 the iOS
Today grid renders — and a day with no rollup comes back `null`, never a loss.
`wins` are computed on device and stored; the Worker passes them through
untouched, so the grid can never disagree with the app.

`get_weight_trend` likewise returns the device's stored `weightAvg7Kg` and
`rateKgPerWeek` rather than re-deriving them.

### The eleven write tools

Two tiers, and the difference is where the state lives
([`../docs/MUSE_CAPABILITIES.md`](../docs/MUSE_CAPABILITIES.md)).

| Tool | Answers | What it touches |
|---|---|---|
| `set_targets` | `applied` | `goalSettings.targets`, patched field by field |
| `update_program` | `applied` | the whole `program` document |
| `set_flag` | `applied` | one key of `flags` |
| `accept_suggestion` | `applied` or `pending_device_apply` | whatever the suggestion carries |
| `set_staples` | `pending_device_apply` | the phone's quick-add list |
| `log_meal` · `log_water` | `pending_device_apply` | Apple Health, written by the phone |
| `log_top_set` · `log_checkin` | `pending_device_apply` | app-owned state on the phone |
| `schedule_workout` | `pending_device_apply` | WorkoutKit, scheduled by the phone |
| `trigger_export` | `pending_device_apply` | the iCloud Drive folder |

A Tier-1 write bumps the document's `version`, appends a mutation already marked
applied, and is live the moment the app next reads. A Tier-2 write appends a
mutation with `appliedAt: null` and answers **`pending_device_apply`** — an
assistant may never report a HealthKit write as landed before the phone has
applied it, and the tool's own `hint` says so in the response.

`set_staples` and `accept_suggestion` are Tier 1 in the log but have no
cloud-side document: the staples list and the suggestion ledger are the phone's.
So they queue like Tier 2 and say `pending_device_apply`, which is the honest
answer rather than an apply the cloud did not make.

**There are no delete tools, in either tier.**

### The guardrails

[`src/guardrails.ts`](src/guardrails.ts) is the whole of it, and every rule there
mirrors one `AscensionCore` already enforces in Swift — the phone writes the same
documents through `PUT /v1/documents/:key`, so a rule enforced on one side only
would mean a document the other half of the loop cannot store. The wording
follows `DomainValidationError.description`, so a rejection reads the same on
both sides.

- `targets.kcal` within 1400–4000 · `targets.fatMinG >= 60` ·
  `fatMinG <= fatMaxG` · `proteinMinG <= proteinG`
- `dietaryRules.excludedMeats` always contains `pork` and `beef`. Spec §2 is a
  hard constraint, not a preference.
- `program.days` holds exactly seven entries, ISO weekdays 1–7 once each, every
  planned session defined and non-empty.
- **Spec §F5:** no two non-rest days training the same muscle region sit less
  than 48 h apart. Consecutive weekdays are 24 h apart and the week is a cycle,
  so Sunday → Monday is checked too. Two days apart is exactly 48 h and so is
  legal — which is what makes Monday/Wednesday Upper the shape the program
  actually uses.

Every violation is reported at once, with the offending values named — a
rejection has to be actionable, or Muse retries the same illegal write. Nothing
is ever clamped into legality, and an unexpected field or unknown enum value is a
`contract_violation` with the issue list, never a silent drop.

### `museWriteMode`

`flags.museWriteMode` is `apply` (the default) or `propose`. In `propose`, a
Tier-1 write is validated as usual and then **recorded as a suggestion**: no
document is written and no mutation is appended, because a proposal is not yet a
change. The response says `proposed` and carries the `suggestionId`.

`accept_suggestion` is deliberately not routed through that path — accepting is
how a proposal becomes a change, so proposing it again would make `propose` a
mode nothing could leave.

Tier-2 logging is unaffected by the mode: a log records what happened, which is
not a proposal.

`museWritesEnabled: false` refuses every write tool, including the `set_flag`
that would turn it back on. That switch is the app's.

### The silent wake

[`src/push/apns.ts`](src/push/apns.ts) signs an ES256 provider JWT and sends
`{"aps":{"content-available":1},"ascension":{"reason":"mutations"}}` to every
registered token after a queued mutation — exactly what `SilentPushHandler`
recognises, since a push with no known `reason` is ignored rather than guessed
at.

Unconfigured is a normal state: with no APNs secrets the response reports
`devicePush: { skipped: "not_configured" }` and the phone drains on foreground or
background refresh instead. **Correctness never depends on the push arriving**,
so every failure here is reported and swallowed, and a token APNs reports dead is
dropped.

---

## D1

Three tables, per [`../docs/EXPORT_SCHEMA.md`](../docs/EXPORT_SCHEMA.md):

- **`rollups`** — `date` is the primary key and holds the whole validated
  `DayRollup` as JSON. Only `timezone` and `updatedAt` are promoted to columns,
  because they are envelope facts the reads sort and report on. Everything else
  is read out of the JSON and shaped in TypeScript: a single user's 400 days are
  kilobytes, and keeping one copy of each field name is worth more than an index.
- **`documents`** — `(key, version, json, updatedAt, updatedBy)` for
  `goalSettings` | `program` | `flags`. The body in `json` does **not** repeat
  `version`, `updatedAt` or `updatedBy`; the full document as §2 prints it is
  composed from the body plus those columns on read, so neither half can drift.
- **`mutations`** — append-only `(id, createdAt, actor, kind, payload,
  appliedAt, appliedResult)`. `id` is a ULID, so ordering is lexicographic and
  the phone drains with `WHERE id > ?`. No UPDATE of `payload` and no DELETE,
  ever; the one column that is ever updated is `appliedAt`, and only from NULL,
  so a re-delivered ack cannot move a timestamp already recorded.
- **`suggestions`** — what a one-tap accept acts on, from both sources, with the
  action accepting performs. Decided rows are kept: it is the record of what was
  accepted and when.
- **`push_tokens`** — an APNs token, a random `deviceId` and a timestamp. Nothing
  that identifies a person (§2.6).

The drain is **not** filtered on `appliedAt`: the device applies Tier-1 mutations
too, to catch its local copy up with a write the Worker already made, so the
cursor alone decides the page.

Migration `0002` seeds `goalSettings` and `flags`, which §2.1 and §2.3 specify in
full. `program` is deliberately not seeded: §2.2 shows only the `upperA` session,
and inventing the rest here would fork a contract the device owns.

```bash
npm run db:apply:local     # the local .wrangler D1
npm run db:apply:remote    # the real one, after `wrangler d1 create ascension`
```

---

## Running it locally

Node 22 or newer — Wrangler 4 and Vitest 4 both require it.

```bash
npm ci
cp .dev.vars.example .dev.vars   # then edit it; .dev.vars is gitignored
npm run db:apply:local
npm run dev
```

Seed the local database with fixtures, through the real ingest endpoint:

```bash
DEVICE_TOKEN="<the value in your .dev.vars>" npm run seed:local
```

Then point the MCP Inspector at `http://localhost:8787/mcp` over
`streamable-http`; it registers itself through dynamic client registration and
sends you to the consent page.

```bash
npm run inspect
```

The Inspector's CLI mode works too, once a token exists, which is how the write
tools in this ticket were verified by hand:

```bash
npx @modelcontextprotocol/inspector --cli http://localhost:8787/mcp \
  --transport http --header "Authorization: Bearer <token>" --method tools/list
```

## Tests

```bash
npm ci
npx tsc --noEmit
npm test
```

Vitest runs inside workerd with a real D1, with the same migrations applied. The
suite covers the contract (including the `DayRollup` printed in
`EXPORT_SCHEMA.md` §1, parsed verbatim), ingest's idempotence and its
whole-batch rejection, every read tool against seeded fixtures, the MCP transport
end to end, every write tool's happy path, **every guardrail rejecting** — the
§F5 rule including its exact 48 h boundary and the Sunday → Monday wrap —
`If-Match` conflicts on both the tool and the endpoint, `propose` against
`apply`, and that each Tier-2 tool answers `pending_device_apply` and leaves
`appliedAt` null.

Fixtures are invented. No real health data ever enters this repo.

---

## Deploying — the steps you run

Nothing here deploys itself.

```bash
# 1. Storage
wrangler d1 create ascension                 # put the id in wrangler.toml
wrangler kv namespace create OAUTH_KV        # put the id in wrangler.toml
npm run db:apply:remote

# 2. Secrets. Never in wrangler.toml, never in the repo.
wrangler secret put DEVICE_TOKEN             # the phone's Keychain token
wrangler secret put OWNER_PASSWORD           # what the consent page asks for

# 2b. APNs, for the silent wake. Optional: without them the phone still drains
#     on foreground and background refresh, just not within seconds.
wrangler secret put APNS_KEY_ID
wrangler secret put APNS_TEAM_ID
wrangler secret put APNS_TOPIC               # the app's bundle identifier
wrangler secret put APNS_PRIVATE_KEY         # the .p8 body, PKCS#8 PEM

# 3. Point PUBLIC_ORIGIN in wrangler.toml at the deployed origin, then
wrangler deploy
```

| Secret | Used by | What it is |
|---|---|---|
| `DEVICE_TOKEN` | `POST /v1/ingest` | A long random string, also stored in the phone's Keychain. Separate from OAuth by design (§2.6). |
| `OWNER_PASSWORD` | `/authorize` | What you type to approve a connector. There is one user; there are no accounts. |
| `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`, `APNS_PRIVATE_KEY` | the silent push | The APNs key pair for `content-available` wakes. All four or none; the `.p8` body never goes in a file in this repo. |

`PUBLIC_ORIGIN` is a `[vars]` entry, not a secret: the OAuth metadata and the MCP
resource identifier are derived from it, and it has to match the origin clients
actually reach.

### Connecting a client

Add `https://<your-origin>/mcp` as a custom connector. Claude's callback is
`https://claude.ai/api/mcp/auth_callback`; nothing needs configuring for it,
because clients register themselves through dynamic client registration and the
consent page shows you the redirect host before you approve.

Scopes are `mcp:read`, `mcp:write` and `offline_access`. Only `mcp:read` is
required, so a client may hold read alone; the consent page lists what it asked
for and says in words that `mcp:write` lets it change targets, the program and
the flags and queue writes for the phone. Granting write is a decision made once,
in the open, with the password.

---

## Two notes on the architecture

**KV.** `../docs/TECH_STACK.md` §2.1 says "no KV", and no health data goes
there — rollups and documents are D1, as designed. But
`@cloudflare/workers-oauth-provider`, which §2.2 mandates, keeps authorization
codes, grants and token hashes in a namespace bound as `OAUTH_KV` and offers no
D1 backend. So the binding exists, holding OAuth state and nothing else.

**CIMD.** Client ID Metadata Documents are off, so the Worker never fetches a
client-supplied metadata URL. Dynamic client registration covers Claude and Muse.
Turning it on would need the `global_fetch_strictly_public` compatibility flag.
