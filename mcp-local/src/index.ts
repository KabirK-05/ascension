/**
 * The entry point: a read-only MCP server on stdio over the export folder.
 *
 * stdout is the MCP wire, so every diagnostic goes to stderr. The folder comes from
 * `ASCENSION_EXPORT_DIR` and nothing else — there is no network, no auth and no cloud
 * in this path, which is the point of it (`docs/TECH_STACK.md` §3).
 */
import { stat } from "node:fs/promises";
import { resolve } from "node:path";
import { serveStdio } from "@modelcontextprotocol/server/stdio";
import { EXPORT_DIR_ENV, ExportFolder } from "./export-folder";
import { buildMcpServer } from "./server";

function warn(message: string): void {
  process.stderr.write(`ascension-mcp-local: ${message}\n`);
}

const configured = process.env[EXPORT_DIR_ENV]?.trim();
if (!configured) {
  warn(
    `${EXPORT_DIR_ENV} is not set. Point it at the iCloud Drive folder the app exports ` +
      `into, e.g. ${EXPORT_DIR_ENV}="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Ascension".`,
  );
  process.exit(1);
}

const dir = resolve(configured);
const folder = new ExportFolder(dir, warn);

// Said once at startup rather than left for the first tool call: a mistyped path is the
// likeliest thing to be wrong, and this is where it is cheapest to notice. Not fatal —
// iCloud may not have materialised the folder yet, and it may appear while this runs.
try {
  const info = await stat(dir);
  if (!info.isDirectory()) warn(`${dir} is not a directory`);
} catch {
  warn(`${dir} does not exist yet — tools will report it until it does`);
}

serveStdio(() => buildMcpServer({ db: folder }), {
  onerror: (error) => warn(error.message),
});
