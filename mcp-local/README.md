# mcp-local — stdio MCP server

Owned by **ASC-17**. Not yet implemented.

A read-only MCP server over stdio that reads the iCloud Drive export folder, for
Claude Code on the Mac. No network, no auth, no cloud — and the fallback if the
Cloudflare bridge is ever switched off via the `remoteBridgeEnabled` flag.

Reads the files `ExportKit` writes: `export.json`, `daily-log.md`,
`summary-latest.md`. Export folder path comes from an env var.
