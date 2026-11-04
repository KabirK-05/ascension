# mcp-local — stdio MCP server

The local bridge. A **read-only** MCP server over **stdio** that reads the iCloud Drive
export folder, so Claude Code on the Mac can answer questions about the training
without a network, an account, or a cloud anywhere in the path.

It is also the fallback if the Cloudflare bridge is ever switched off — the
`remoteBridgeEnabled` flag in [`../docs/TECH_STACK.md`](../docs/TECH_STACK.md) §2.5 —
and the reason that switch is safe to throw.

**ASC-17 (this)** — the eight Tier-3 read tools over the export folder, and the two
markdown files as resources.

---

## Registering it with Claude Code

Install once, then add the server. Both paths must be absolute; `$PWD` below assumes
you are standing in this directory.

```bash
npm ci
```

```bash
claude mcp add ascension -s user \
  -e ASCENSION_EXPORT_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Ascension" \
  -- "$PWD/node_modules/.bin/tsx" "$PWD/src/index.ts"
```

`ASCENSION_EXPORT_DIR` is the folder you picked in the app's Settings — the one it
writes `export.json`, the CSVs, `daily-log.md` and `summary-latest.md` into. It is the
only configuration there is: no token, no port, no URL. Check it with `claude mcp list`,
and remove it with `claude mcp remove ascension`.

---

## What it serves

### The eight read tools

`get_today` · `get_workouts` · `get_nutrition` · `get_weight_trend` · `get_readiness` ·
`get_checkins` · `get_exercise_history` · `get_consistency_grid`

These are the cloud server's tools, not a second set of them. Everything in
[`src/tools.ts`](src/tools.ts) from `ReadTool` down is `edge/src/mcp/tools.ts` byte for
byte, and [`src/contract.ts`](src/contract.ts) and [`src/dates.ts`](src/dates.ts) are
verbatim copies — [`test/parity.test.ts`](test/parity.test.ts) diffs all three and fails
if any of them drifts. The point is that Muse and Claude Code describe the same training
week identically, including the names of the fields they describe it in.

Every response is compact JSON carrying `schemaVersion`, and every windowed response
carries `asOf`, the most recent day in the export. Locally `asOf` is the difference
between "you did not train yesterday" and "iCloud has not delivered yesterday's export
yet", so it is the first thing to read.

There are **no write tools here, on any transport.** The folder is opened read-only, and
nothing in this package writes, moves or deletes a file in it.

### The two markdown files, as resources

| URI | What |
|---|---|
| `ascension://summary` | `summary-latest.md` — the rolling 28-day summary, under 150 lines. **Read this first.** |
| `ascension://daily-log` | The most recent 14 days of `daily-log.md`. |
| `ascension://daily-log/{date}` | One day of the journal, by `YYYY-MM-DD`. |

The journal is append-only and grows forever, so neither of those loads it: the trailing
days are read backwards from the end of the file in a 64 KiB window, and a single day is
found by streaming lines and stopping at the next header. Memory is flat in the size of
the file, and a block cut short by a truncated write comes back as it stands rather than
taking the read down.

The per-day template is deliberately not listable — enumerating it means reading the
whole journal. `get_today` and the summary name the dates worth asking for.

---

## Layout

```
src/
  index.ts          the entry point: ASCENSION_EXPORT_DIR, then stdio
  server.ts         the MCP server — tools, resources, the schemaVersion envelope
  tools.ts          the eight read tools (the cloud server's bodies, verbatim)
  range.ts          window resolution and the numeric helpers
  contract.ts       a verbatim copy of edge/src/contract.ts
  dates.ts          a verbatim copy of edge/src/dates.ts
  export-folder.ts  export.json: cached by mtime, re-read when it changes
  daily-log.ts      daily-log.md, read a bounded piece at a time
  read-file.ts      reads that describe their failures instead of throwing
  store/            the accessors edge/src/db/ exposes, over the folder
test/
  fixtures/         four export folders: full, missing-export, malformed, partial
```

### Why only `export.json`

[`../docs/EXPORT_SCHEMA.md`](../docs/EXPORT_SCHEMA.md) §4 calls `export.json` the
superset and every CSV a flat projection of its `rollups[]`. Reading the CSVs too would
put a second source under the same number and with it the chance of the two disagreeing,
which is exactly what the export format is shaped to prevent. So the tools read
`export.json`, and a broken `rollups.csv` beside it changes no answer —
[`test/export-folder.test.ts`](test/export-folder.test.ts) holds that.

### A folder is untrusted input

It lives on a synced drive and a person can edit it, so every state it can be in has an
answer rather than an exception:

| The folder | The answer |
|---|---|
| not there, or not a directory | every tool errors, naming `ASCENSION_EXPORT_DIR` |
| there, no `export.json` | `asOf: null` — nothing synced yet |
| `export.json` empty or half-written | `asOf: null`, and why on stderr |
| one day's row malformed | the other days answer; that date is listed in `unreadableDates` |
| a row with no readable date | skipped, counted, and reported on stderr |
| a newer `schemaVersion` | read as far as it parses, with the mismatch on stderr |

`null` means *not measured* throughout and never means zero — a malformed measurement
takes its day out of the answer rather than entering it as a `0` that would drag an
average down. Diagnostics go to **stderr**, because stdout is the MCP wire.

`export.json` is re-read whenever it changes on disk. The app rewrites it nightly under
a server that may run for weeks.

---

## Running and testing it

Node 22 or newer, as in `edge/`.

```bash
npm ci
npx tsc --noEmit
npm test
```

The suite covers the eight tools over four fixture export folders, every degenerate
state in the table above, the journal reader against a generated multi-megabyte
`daily-log.md`, parity with the cloud server's contract and tool bodies, that the
fixture folder is byte-identical after every tool has run, and the server end to end as
a real process speaking JSON-RPC on stdio.

Fixtures are the `ExportKit` golden files under their real names, so what the tests
parse is byte-for-byte what the app writes. The data in them is invented and respects
the dietary rules. No real health data ever enters this repo.

By hand, with the MCP Inspector. It does not pass your environment through to the
server it spawns, so the folder goes in a `-e` flag rather than an export:

```bash
npm run inspect -- -e ASCENSION_EXPORT_DIR="$PWD/test/fixtures/full" --method tools/list
```

```bash
npm run inspect -- -e ASCENSION_EXPORT_DIR="$PWD/test/fixtures/full" --method tools/call --tool-name get_today
```

```bash
npm run inspect -- -e ASCENSION_EXPORT_DIR="$PWD/test/fixtures/full" --method resources/read --uri ascension://summary
```

---

## One note on the architecture

**Why stdio only.** The spec (§9.3) allows an HTTP transport and requires a bearer token
from the environment or the Keychain the moment there is one. Nothing here has a token,
so nothing here listens on a socket: the transport is a pipe to a process Claude Code
started, and the only thing authorising the read is the fact that it is running as the
owner of the files. Adding HTTP is a ticket of its own, and the cloud bridge in `edge/`
already covers everything it would be for.
