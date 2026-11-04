import { beforeAll, describe, expect, it } from "vitest";
import { mcpHandler } from "../src/mcp/server";
import { readTools } from "../src/mcp/tools";
import { writeTools } from "../src/mcp/writes";
import { testEnv } from "./env";
import { LAST_DAY } from "./fixtures";
import { seedDocuments, seedRollups } from "./helpers";

const ENDPOINT = "http://localhost:8787/mcp";

/**
 * Drives the handler's own `fetch` face, which takes the verified auth
 * information rather than deriving it from headers — so these exercise the MCP
 * transport and the tools without standing up the OAuth dance.
 */
async function rpc(method: string, params: Record<string, unknown> = {}) {
  const response = await mcpHandler(testEnv).fetch(
    new Request(ENDPOINT, {
      method: "POST",
      headers: {
        // workerd does not derive Host from the URL for a constructed Request,
        // and the handler validates it against the localhost allowlist.
        Host: "localhost:8787",
        "Content-Type": "application/json",
        Accept: "application/json, text/event-stream",
      },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    }),
  );
  const text = await response.text();
  // Streamable HTTP may answer as JSON or as a single SSE event.
  const payload = response.headers.get("Content-Type")?.includes("text/event-stream")
    ? JSON.parse(
        text
          .split("\n")
          .filter((line) => line.startsWith("data:"))
          .map((line) => line.slice(5).trim())
          .join(""),
      )
    : JSON.parse(text);
  return { status: response.status, payload };
}

/** The tool payload, which is compact JSON in a single text block. */
function toolPayload(payload: Record<string, any>): Record<string, any> {
  expect(payload.error, JSON.stringify(payload.error)).toBeUndefined();
  expect(payload.result.isError).not.toBe(true);
  return JSON.parse(payload.result.content[0].text);
}

describe("the MCP server over Streamable HTTP", () => {
  beforeAll(async () => {
    await seedRollups();
  });

  it("initializes and names itself", async () => {
    const { status, payload } = await rpc("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "test", version: "0" },
    });
    expect(status).toBe(200);
    expect(payload.result.serverInfo.name).toBe("ascension");
    expect(payload.result.instructions).toContain("daily rollups");
  });

  it("lists the read and write tools, each with a schema and a description", async () => {
    const { payload } = await rpc("tools/list");
    const tools = payload.result.tools as Array<Record<string, any>>;
    expect(tools.map((tool) => tool.name).sort()).toEqual(
      [...readTools, ...writeTools].map((tool) => tool.name).sort(),
    );
    for (const tool of tools) {
      expect(tool.description?.length, tool.name).toBeGreaterThan(40);
      expect(tool.inputSchema.type, tool.name).toBe("object");
    }
  });

  it("exposes every write kind the contract declares, and nothing that deletes", async () => {
    const { payload } = await rpc("tools/list");
    const tools = payload.result.tools as Array<Record<string, any>>;
    const names = tools.map((tool) => tool.name);
    for (const expected of [
      "set_targets",
      "update_program",
      "set_staples",
      "set_flag",
      "accept_suggestion",
      "log_meal",
      "log_water",
      "log_top_set",
      "log_checkin",
      "schedule_workout",
      "trigger_export",
    ]) {
      expect(names).toContain(expected);
    }
    // No delete tools in v1 (docs/MUSE_CAPABILITIES.md), and nothing advertises
    // itself as destructive.
    expect(names.filter((name) => /delete|remove|clear|wipe/.test(name))).toEqual([]);
    for (const tool of tools) {
      expect(tool.annotations?.destructiveHint, tool.name).not.toBe(true);
    }
  });

  it("marks the read tools read-only and the write tools not", async () => {
    const { payload } = await rpc("tools/list");
    const tools = payload.result.tools as Array<Record<string, any>>;
    const byName = new Map(tools.map((tool) => [tool.name, tool]));
    expect(byName.get("get_today")?.annotations?.readOnlyHint).toBe(true);
    expect(byName.get("set_targets")?.annotations?.readOnlyHint).toBe(false);
  });

  it("says in its instructions that Tier-2 writes are not landed yet", async () => {
    const { payload } = await rpc("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "test", version: "0" },
    });
    expect(payload.result.instructions).toContain("pending_device_apply");
    expect(payload.result.instructions).toContain("no delete tools");
  });

  it("applies a Tier-1 write through the transport", async () => {
    await seedDocuments();
    const { payload } = await rpc("tools/call", {
      name: "set_targets",
      arguments: { kcal: 2050 },
    });
    const result = toolPayload(payload);
    expect(result).toMatchObject({ schemaVersion: 1, status: "applied" });
    expect(result.document).toMatchObject({ key: "goalSettings", version: 2 });
  });

  it("queues a Tier-2 write through the transport, and says it is pending", async () => {
    await seedDocuments();
    const { payload } = await rpc("tools/call", {
      name: "log_water",
      arguments: { date: LAST_DAY, ml: 500 },
    });
    const result = toolPayload(payload);
    expect(result.status).toBe("pending_device_apply");
    expect(result.mutationId).toHaveLength(26);
  });

  it("reports a rejected write as an error with the offending values", async () => {
    await seedDocuments();
    const { payload } = await rpc("tools/call", {
      name: "set_targets",
      arguments: { kcal: 12000 },
    });
    expect(payload.result.isError).toBe(true);
    const body = JSON.parse(payload.result.content[0].text);
    expect(body).toMatchObject({ schemaVersion: 1, error: "invariant_violation" });
    expect(body.issues[0].message).toContain("1400...4000");
  });

  it.each(readTools.map((tool) => tool.name))(
    "answers tools/call for %s with schemaVersion",
    async (name) => {
      const { payload } = await rpc("tools/call", { name, arguments: {} });
      const result = toolPayload(payload);
      expect(result.schemaVersion).toBe(1);
    },
  );

  it("returns the latest synced day through the transport", async () => {
    const { payload } = await rpc("tools/call", {
      name: "get_today",
      arguments: {},
    });
    const result = toolPayload(payload);
    expect(result.date).toBe(LAST_DAY);
    expect(result.rollup.training.sessionPlanned).toBe("upperA");
  });

  it("passes arguments through and validates them", async () => {
    const good = await rpc("tools/call", {
      name: "get_consistency_grid",
      arguments: { weeks: 4 },
    });
    expect(toolPayload(good.payload).grid).toHaveLength(4);

    const bad = await rpc("tools/call", {
      name: "get_consistency_grid",
      arguments: { weeks: 99 },
    });
    expect(
      bad.payload.result?.isError === true || bad.payload.error !== undefined,
    ).toBe(true);
  });

  it("reports an unknown tool as an error", async () => {
    const { payload } = await rpc("tools/call", {
      name: "set_targets",
      arguments: {},
    });
    expect(
      payload.result?.isError === true || payload.error !== undefined,
    ).toBe(true);
  });
});
