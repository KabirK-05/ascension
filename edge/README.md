# edge — Cloudflare Worker

The cloud bridge. A stateless MCP server over Streamable HTTP so Meta Muse and
Claude can read Ascension from their own clouds, plus the endpoint the phone
pushes daily rollups to.

Why it exists, and why it is not a local file-watcher, is
[`../docs/TECH_STACK.md`](../docs/TECH_STACK.md) §2. The data contract is
[`../docs/EXPORT_SCHEMA.md`](../docs/EXPORT_SCHEMA.md) and this directory holds
no second copy of it: [`src/contract.ts`](src/contract.ts) is that document in
zod, and every field name on the edge comes from there.

**ASC-4 (this)** — Worker, D1, `POST /v1/ingest`, the eight Tier-3 read tools.
**ASC-13 (next)** — the Tier-1 and Tier-2 write tools, `GET /v1/mutations`,
`POST /v1/mutations/ack`, `PUT /v1/documents/:key`, and the silent-APNs trigger.

---

## Layout

```
migrations/     D1 schema, applied with `wrangler d1 migrations apply`
src/
  index.ts      OAuthProvider wiring and the non-MCP routes
  contract.ts   docs/EXPORT_SCHEMA.md in zod — the single source of field names
  dates.ts      calendar arithmetic on YYYY-MM-DD, clock-free
  db/           rollups and documents
  http/         /v1/ingest, the consent page, response helpers
  mcp/          the stateless MCP server and the eight read tools
test/           vitest, running inside workerd against a real local D1
scripts/        seed a local `wrangler dev` with fixtures
```

## Routes

| Route | Auth | What |
|---|---|---|
| `POST /v1/ingest` | device token | Stream A. A batch of `DayRollup`, upserted on `date`. |
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

There are **no write tools here**. `tools/list` returning only these eight is
asserted in [`test/mcp.test.ts`](test/mcp.test.ts).

`get_consistency_grid` returns 17 Monday-to-Sunday weeks — the 7×17 the iOS
Today grid renders — and a day with no rollup comes back `null`, never a loss.
`wins` are computed on device and stored; the Worker passes them through
untouched, so the grid can never disagree with the app.

`get_weight_trend` likewise returns the device's stored `weightAvg7Kg` and
`rateKgPerWeek` rather than re-deriving them.

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
  the phone drains with `WHERE id > ?`. Written by ASC-13.

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

## Tests

```bash
npm ci
npx tsc --noEmit
npm test
```

Vitest runs inside workerd with a real D1, with the same migrations applied. The
suite covers the contract (including the `DayRollup` printed in
`EXPORT_SCHEMA.md` §1, parsed verbatim), ingest's idempotence and its
whole-batch rejection, every read tool against seeded fixtures, and the MCP
transport end to end.

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

# 3. Point PUBLIC_ORIGIN in wrangler.toml at the deployed origin, then
wrangler deploy
```

| Secret | Used by | What it is |
|---|---|---|
| `DEVICE_TOKEN` | `POST /v1/ingest` | A long random string, also stored in the phone's Keychain. Separate from OAuth by design (§2.6). |
| `OWNER_PASSWORD` | `/authorize` | What you type to approve a connector. There is one user; there are no accounts. |

`PUBLIC_ORIGIN` is a `[vars]` entry, not a secret: the OAuth metadata and the MCP
resource identifier are derived from it, and it has to match the origin clients
actually reach.

### Connecting a client

Add `https://<your-origin>/mcp` as a custom connector. Claude's callback is
`https://claude.ai/api/mcp/auth_callback`; nothing needs configuring for it,
because clients register themselves through dynamic client registration and the
consent page shows you the redirect host before you approve.

Scopes today are `mcp:read` and `offline_access`. ASC-13 adds `mcp:write`, which
clients obtain by step-up rather than by re-registering.

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
