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
import { wakeDevices } from "../push/apns";
import { ToolError } from "./errors";
import { readTools, type ToolContext } from "./tools";
import { writeTools, type WriteContext } from "./writes";

const INSTRUCTIONS = `Ascension is a single-user personal health manager. The Apple Watch and Apple Health record the training; this server manages it.

Scope is daily rollups: totals, trends, readiness scores and reasons, top sets, and the four daily consistency wins. Raw heart-rate series, per-meal rows and sleep stages never leave the phone, so do not ask for them.

Data is as fresh as the last phone sync, not live. Every response carries \`asOf\`, the most recent synced day — read it before saying what happened today.

Units are fixed: kg, kcal, grams, millilitres, minutes, bpm, ms. \`null\` means not measured; it never means zero.

You may write. \`set_targets\`, \`update_program\`, \`set_flag\` and \`accept_suggestion\` take effect at once; \`set_staples\` and every \`log_*\` tool, \`schedule_workout\` and \`trigger_export\` are queued for the phone and answer \`pending_device_apply\` — never say a meal, a water entry or a check-in has landed in Apple Health until the phone has applied it, because only the phone can write there.

Hard limits are enforced here and are not negotiable: calories within 1400–4000, fat floor at least 60 g, protein floor no higher than the protein target, pork and beef always excluded, and no two non-rest days training the same muscle region less than 48 h apart. A write that breaks one is rejected with the offending values named — fix the write, do not retry it unchanged.

When \`flags.museWriteMode\` is \`propose\`, a settings write becomes a pending suggestion instead of a change, and the response says \`proposed\`. Report that honestly: nothing changed until it is accepted.

There are no delete tools. Nothing here can remove data.`;

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

/**
 * A failure carries the same envelope as a success, plus the slug and the
 * offending values when the tool named them: a rejection has to be actionable,
 * or Muse will retry the same illegal write.
 */
function failure(error: unknown) {
  const body =
    error instanceof ToolError
      ? { error: error.code, message: error.message, ...error.detail }
      : { error: error instanceof Error ? error.message : String(error) };
  return {
    isError: true,
    content: [
      {
        type: "text" as const,
        text: JSON.stringify({ schemaVersion: SCHEMA_VERSION, ...body }),
      },
    ],
  };
}

export function buildMcpServer(ctx: ToolContext & WriteContext): McpServer {
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

  for (const tool of writeTools) {
    server.registerTool(
      tool.name,
      {
        title: tool.title,
        description: tool.description,
        inputSchema: tool.inputSchema,
        annotations: {
          readOnlyHint: false,
          // Nothing here deletes: a Tier-1 write replaces a document the
          // mutations log records the previous value of, and a Tier-2 write
          // appends. There are no delete tools in v1.
          destructiveHint: false,
          // A repeated call appends a second mutation, so it is not idempotent:
          // calling `log_meal` twice logs the meal twice.
          idempotentHint: false,
          openWorldHint: false,
        },
      },
      async (args: unknown) => {
        try {
          return reply(await tool.run(args, ctx));
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
  const handler = createMcpHandler(
    () => buildMcpServer({ db: env.DB, wake: () => wakeDevices(env) }),
    { route: "/mcp" },
  );
  handlers.set(env, handler);
  return handler;
}
