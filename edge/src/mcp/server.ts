/**
 * The MCP server: a stateless `createMcpHandler` over Streamable HTTP.
 *
 * Not `McpAgent` — Cloudflare has deprecated it — and not SSE, which is also
 * deprecated. Stateless means no Durable Objects (docs/TECH_STACK.md §2.2).
 */
import { McpServer } from "@modelcontextprotocol/server";
import { createMcpHandler, type StatelessMcpHandler } from "agents/mcp/server";
import { SCHEMA_VERSION } from "../contract";
import type { Env } from "../env";
import { readTools, type ToolContext } from "./tools";

const INSTRUCTIONS = `Ascension is a single-user personal health manager. The Apple Watch and Apple Health record the training; this server reports it.

Scope is daily rollups: totals, trends, readiness scores and reasons, top sets, and the four daily consistency wins. Raw heart-rate series, per-meal rows and sleep stages never leave the phone, so do not ask for them.

Data is as fresh as the last phone sync, not live. Every response carries \`asOf\`, the most recent synced day — read it before saying what happened today.

Units are fixed: kg, kcal, grams, millilitres, minutes, bpm, ms. \`null\` means not measured; it never means zero.

These tools only read. Changing targets, the program or logs is not available here.`;

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

export function buildMcpServer(ctx: ToolContext): McpServer {
  const server = new McpServer(
    { name: "ascension", version: "1.0.0" },
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

  return server;
}

const handlers = new WeakMap<Env, StatelessMcpHandler>();

/**
 * One handler per environment, built lazily. The handler is stateless, so this
 * is only to avoid rebuilding the closure on every request; `env` is not visible
 * to the server factory, which is why it is captured here.
 */
export function mcpHandler(env: Env): StatelessMcpHandler {
  const existing = handlers.get(env);
  if (existing) return existing;
  const handler = createMcpHandler(() => buildMcpServer({ db: env.DB }), {
    route: "/mcp",
  });
  handlers.set(env, handler);
  return handler;
}
