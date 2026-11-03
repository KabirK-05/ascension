# edge — Cloudflare Worker

Owned by **ASC-4** (read tools + sync API) and **ASC-13** (write tools).
Not yet implemented; this directory is a placeholder so CI path filters resolve.

## What goes here

A stateless MCP server over Streamable HTTP, plus the sync API the phone talks to.
See [`../docs/TECH_STACK.md`](../docs/TECH_STACK.md) §2 for the architecture and
[`../docs/EXPORT_SCHEMA.md`](../docs/EXPORT_SCHEMA.md) for the data contract.

- `createMcpHandler` — **not** `McpAgent`, which Cloudflare has deprecated
- `@cloudflare/workers-oauth-provider` for OAuth 2.1 + PKCE
- D1 tables: `rollups`, `documents`, `mutations`
- `POST /v1/ingest`, `GET /v1/mutations`, `POST /v1/mutations/ack`, `PUT /v1/documents/:key`

## Rules

Secrets go in `wrangler secret`, never in the repo or in `wrangler.toml`.
Every MCP response carries `schemaVersion`. Tier-2 tools return
`pending_device_apply` — see [`../docs/MUSE_CAPABILITIES.md`](../docs/MUSE_CAPABILITIES.md).
