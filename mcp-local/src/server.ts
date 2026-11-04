/**
 * The MCP server: the eight read tools over stdio, plus the two markdown files the
 * folder holds as resources.
 *
 * `reply` and `failure` are `edge/src/mcp/server.ts`'s — compact JSON with
 * `schemaVersion` on every response, errors in the same envelope — so a client parses
 * either server's answers the same way.
 *
 * No transport but stdio is wired up, and none should be: the spec (§9.3) requires a
 * bearer token the moment this listens on a socket, and nothing here has one.
 */
import { McpServer, ResourceTemplate } from "@modelcontextprotocol/server";
import { SCHEMA_VERSION } from "./contract";
import { TAIL_BLOCKS, findBlock, readTail } from "./daily-log";
import { fileNames, type ExportFolder } from "./export-folder";
import { readTextFile } from "./read-file";
import { readTools, type ToolContext } from "./tools";

export const SUMMARY_URI = "ascension://summary";
export const DAILY_LOG_URI = "ascension://daily-log";
const DAILY_LOG_TEMPLATE = "ascension://daily-log/{date}";

const INSTRUCTIONS = `Ascension is a single-user personal health manager. The Apple Watch and Apple Health record the training; this server reports it.

It reads an export folder on this Mac — the files the app writes to iCloud Drive — and only reads them. Read the \`${SUMMARY_URI}\` resource first: it is the rolling 28-day summary the app writes for exactly this purpose, under 150 lines, with targets, averages, adherence and anything waiting on a decision. \`${DAILY_LOG_URI}\` is the day-by-day journal, and \`${DAILY_LOG_TEMPLATE}\` is one day of it.

Scope is daily rollups: totals, trends, readiness scores and reasons, top sets, and the four daily consistency wins. Raw heart-rate series, per-meal rows and sleep stages never leave the phone, so do not ask for them.

Data is as fresh as the last export the phone wrote and iCloud delivered, not live. Every response carries \`asOf\`, the most recent day in the export — read it before saying what happened today.

Units are fixed: kg, kcal, grams, millilitres, minutes, bpm, ms. \`null\` means not measured; it never means zero.

These tools only read. Changing targets, the program or logs is not available here — that is the cloud bridge.`;

/** Compact JSON, and `schemaVersion` on every response. */
function reply(payload: Record<string, unknown>) {
  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify({ schemaVersion: SCHEMA_VERSION, ...payload }),
      },
    ],
  };
}

function failure(error: unknown) {
  return {
    isError: true,
    content: [
      {
        type: "text" as const,
        text: JSON.stringify({
          schemaVersion: SCHEMA_VERSION,
          error: error instanceof Error ? error.message : String(error),
        }),
      },
    ],
  };
}

function markdown(uri: string, text: string) {
  return { contents: [{ uri, mimeType: "text/markdown", text }] };
}

export function buildMcpServer(ctx: ToolContext): McpServer {
  const folder: ExportFolder = ctx.db;
  const server = new McpServer(
    { name: "ascension-local", version: "1.0.0" },
    { instructions: INSTRUCTIONS },
  );

  for (const tool of readTools) {
    server.registerTool(
      tool.name,
      {
        title: tool.title,
        description: tool.description,
        inputSchema: tool.inputSchema,
        annotations: { readOnlyHint: true, openWorldHint: false },
      },
      async (args: unknown) => {
        try {
          return reply(await tool.run(args as never, ctx));
        } catch (error) {
          return failure(error);
        }
      },
    );
  }

  server.registerResource(
    "summary",
    SUMMARY_URI,
    {
      title: "Summary",
      description:
        "The rolling 28-day summary the app overwrites on every export: targets, the program, 7- and 28-day averages, adherence, the last 14 days as a table, and any open suggestion. Under 150 lines, and the file to read first.",
      mimeType: "text/markdown",
    },
    async (uri) => {
      const file = await readTextFile(folder.path(fileNames.summary));
      if (file.kind === "absent") {
        return markdown(
          uri.href,
          `No ${fileNames.summary} in ${folder.dir} yet — nothing has been exported.\n`,
        );
      }
      if (file.kind === "unreadable") {
        throw new Error(`${fileNames.summary} could not be read: ${file.reason}`);
      }
      return markdown(uri.href, file.text);
    },
  );

  server.registerResource(
    "daily-log",
    DAILY_LOG_URI,
    {
      title: "Daily log",
      description: `The append-only daily journal, most recent ${TAIL_BLOCKS} days. One block per day: readiness and its reasons, workouts with heart rate, top sets, food, sleep, weight and steps. Read from the end of the file, so its length does not matter.`,
      mimeType: "text/markdown",
    },
    async (uri) => {
      const tail = await readTail(folder.path(fileNames.dailyLog));
      if (tail === null) {
        return markdown(
          uri.href,
          `No ${fileNames.dailyLog} in ${folder.dir} yet — nothing has been exported.\n`,
        );
      }
      const header = tail.truncated
        ? `# Ascension — daily log (most recent ${tail.blocks.length} days)\n\n`
        : "# Ascension — daily log\n\n";
      return markdown(uri.href, header + tail.blocks.map((block) => block.text).join("\n"));
    },
  );

  server.registerResource(
    "daily-log-day",
    new ResourceTemplate(DAILY_LOG_TEMPLATE, {
      // Deliberately not listed: enumerating every day means reading the whole journal,
      // which grows without bound. `get_today` and the summary name the dates worth
      // asking for.
      list: undefined,
    }),
    {
      title: "Daily log — one day",
      description: "One day of the journal, by `YYYY-MM-DD` date.",
      mimeType: "text/markdown",
    },
    async (uri, variables) => {
      const date = Array.isArray(variables.date) ? variables.date[0] : variables.date;
      if (typeof date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
        throw new Error(`expected a YYYY-MM-DD date in ${DAILY_LOG_TEMPLATE}, got ${String(date)}`);
      }
      const block = await findBlock(folder.path(fileNames.dailyLog), date);
      if (block === null) {
        return markdown(uri.href, `No entry for ${date} in ${fileNames.dailyLog}.\n`);
      }
      return markdown(uri.href, block.text);
    },
  );

  return server;
}
