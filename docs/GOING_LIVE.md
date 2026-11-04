# Going live

Everything from a green `staging` to Ascension running on your phone with Muse
connected. Nine steps, roughly an hour, most of it waiting on Xcode.

**Status when this was written:** ASC-16 (Settings, widgets, Siri, notifications)
is still in flight, and **steps 5, 7 and 8 depend on it** — they need the Settings
screen it builds. Steps 1–4 and 6 you can do now. ASC-18 then runs the end-to-end
acceptance test.

---

## 0. Prerequisites

| | Check |
|---|---|
| Apple Developer team | `open https://developer.apple.com/account` → Membership → Team ID |
| Cloudflare account | `npx wrangler login` |
| Node 22 | see below — **this is the first thing that bites** |
| Xcode 26+ | `xcodebuild -version` |
| Tuist, SwiftLint | `brew install tuist swiftlint` |

### Node 22 — do this before any `npx wrangler` command

Wrangler refuses to run on Node 20 and the repo pins `>=22`. `fnm` is installed
and so is v22, but it defaults to v20, and **`fnm use` only affects the shell you
run it in**:

```bash
fnm use 22
```

Make it the default for new shells too, or this recurs every time:

```bash
fnm default 22
```

Confirm before continuing — every step below assumes it:

```bash
node --version
```

The repo carries a `.node-version` file. If you add `--use-on-cd` to the `fnm env`
line in your `~/.zshrc`, fnm switches automatically whenever you `cd` here.

---

## 1. Create the Worker's storage

```bash
cd edge && npm ci
```

```bash
npx wrangler d1 create ascension
```

```bash
npx wrangler kv namespace create OAUTH_KV
```

Both print an id. Put them into `edge/wrangler.toml` — `database_id` and the KV
`id` — replacing the zero placeholders. Then apply the schema:

```bash
cd edge && npm run db:apply:remote
```

---

## 2. Generate and set the secrets

The device token is a shared secret between the phone and the Worker. Generate
one and keep it on your clipboard for step 5 — **this is the only time you will
see it**.

```bash
openssl rand -base64 32
```

```bash
cd edge && npx wrangler secret put DEVICE_TOKEN
```

```bash
cd edge && npx wrangler secret put OWNER_PASSWORD
```

`OWNER_PASSWORD` is what the consent page asks for when you approve a connector
in step 6. Pick something you will remember; there are no accounts to recover.

---

## 3. Deploy

```bash
cd edge && npx wrangler deploy
```

It prints an origin like `https://ascension-edge.<subdomain>.workers.dev`. Put
that into `edge/wrangler.toml` as `PUBLIC_ORIGIN` — the OAuth metadata and MCP
resource identifier derive from it and must match what clients actually reach —
then deploy once more:

```bash
cd edge && npx wrangler deploy
```

Confirm it is alive:

```bash
curl -s https://ascension-edge.<subdomain>.workers.dev/health
```

---

## 4. Optional — APNs, for second-latency writes

Without this, Muse's writes reach your phone on background refresh (minutes).
With it, a silent push wakes the app in seconds. All four or none.

Create an APNs key at **developer.apple.com → Certificates → Keys → + → Apple
Push Notifications service**, download the `.p8` once.

```bash
cd edge && npx wrangler secret put APNS_KEY_ID
```
```bash
cd edge && npx wrangler secret put APNS_TEAM_ID
```
```bash
cd edge && npx wrangler secret put APNS_TOPIC
```
`APNS_TOPIC` is the bundle id: `com.kabirkumar.ascension`.

```bash
cd edge && npx wrangler secret put APNS_PRIVATE_KEY
```
Paste the `.p8` body (PKCS#8 PEM, `-----BEGIN PRIVATE KEY-----` included). The
file never goes in the repo.

---

## 5. Build and install on your iPhone  *(needs ASC-16)*

```bash
tuist generate
```

In Xcode: select the **Ascension** target → **Signing & Capabilities** → set your
team. Plug in your iPhone, select it as the destination, and Run.

On first launch, grant HealthKit when asked. Health data is read-only to the app
except for nutrition, water and weight.

**Then pair it:** Settings → enter the Worker origin from step 3 and the device
token from step 2. Sync stays off until both exist — that is deliberate, not a
bug. Settings will show whether sync is active and when it last pushed.

---

## 6. Connect Muse and Claude

Add this as a **custom connector** in each client:

```
https://ascension-edge.<subdomain>.workers.dev/mcp
```

- **Claude:** claude.ai → Settings → Connectors → Add custom connector. Mobile
  cannot add connectors; add it on the web and it syncs to your phone.
- **Muse:** Settings → Connectors, or ask Muse in chat to add it.

Either will send you to the consent page, which asks for `OWNER_PASSWORD` and
shows the redirect host before you approve. Scopes are `mcp:read`, `mcp:write`
and `offline_access` — only read is required, so you can grant read alone first
and add write once you trust it.

---

## 7. Local MCP for Claude Code on this Mac  *(needs ASC-16)*

First pick the export folder in the app: Settings → export destination, an
iCloud Drive folder. Then:

```bash
cd mcp-local && npm ci
```

```bash
cd mcp-local && claude mcp add ascension -s user -e ASCENSION_EXPORT_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Ascension" -- "$PWD/node_modules/.bin/tsx" "$PWD/src/index.ts"
```

Adjust the path to the folder you actually picked. Verify with `claude mcp list`.

This path needs no token, no network and no Worker — it reads the files the app
exports. It is also your fallback if you ever turn the cloud bridge off.

---

## 8. Verify it actually works  *(needs ASC-16)*

Do these in order; each one proves a different half of the system.

1. **The app reads Health.** Today shows your real steps, sleep and weight, and
   matches Apple Health.
2. **The phone pushes.** Settings shows a recent successful push. Or:
   `curl -s -H "Authorization: Bearer <token>" https://<origin>/v1/mutations?since=`
3. **Muse reads.** Ask it *"how is my training going this month?"* — sessions vs
   plan, protein, weight trend, without pasting anything.
4. **Muse writes config.** Ask it to set your calorie target to 2,000. Check
   Settings → Changes: the change is listed with an undo.
5. **Muse writes through to Health.** Ask it to log a meal. The tool answers
   `pending_device_apply`. Within minutes — seconds with APNs — it appears in
   **Apple Health → Nutrition**, not just in the app.
6. **The guardrails hold.** Ask Muse to put legs on two consecutive days. It
   should be *refused by the Worker*, naming the offending pair. If it succeeds,
   stop and tell me.

Step 6 matters as much as the others: Muse writes with full authority, and the
server-side rules are the only thing between a bad tool call and a bad month.

---

## 9. Release to production

`main` has held nothing but the scaffold so far. Once step 8 passes:

```bash
gh pr create --base main --head staging --title "release: v0.1.0 — Ascension v1"
```

CI's `guard-release` job enforces that `main` only ever accepts `staging`. Merge
it as a merge commit, then tag:

```bash
git checkout main && git pull && git tag v0.1.0 && git push --tags
```

---

## Known risks on first run

Things that pass in CI but have never touched real hardware:

- **Step counts may double** if `HKStatisticsQuery` merges iPhone and Watch
  samples without deduplication (ASC-5 flagged this). Compare Today against
  Apple Health on day one.
- **Background delivery** has never woken the app for real.
- **WorkoutKit → Watch** has never scheduled to an actual Watch.
- **Barcode scanning** has no camera in the simulator.
- **The sync wire** has never run against a deployed Worker — both halves were
  built against the same written contract and verified by scripts, which is a
  good reason to expect it to work and not the same as evidence.

If something here fails, the failure is almost certainly in this list.
