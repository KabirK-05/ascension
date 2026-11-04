/**
 * End to end: the server as a real process on stdio, answering a real client.
 */
import { rm } from "node:fs/promises";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { DAILY_LOG_URI, SUMMARY_URI } from "../src/server";
import { emptyFolderDir, fixtureDir } from "./support/folders";
import { StdioServer } from "./support/stdio";
import { toolNames } from "./support/tools";

describe("the server over stdio, on a full folder", () => {
  let server: StdioServer;

  beforeAll(async () => {
    server = await StdioServer.start(fixtureDir("full"));
  });
  afterAll(async () => {
    await server.stop();
  });

  it("names itself and offers tools and resources", async () => {
    const { result } = await server.request("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "ascension-tests", version: "0" },
    });

    expect(result.serverInfo.name).toBe("ascension-local");
    expect(result.capabilities.tools).toBeDefined();
    expect(result.capabilities.resources).toBeDefined();
    expect(result.instructions).toContain("only reads");
    expect(result.instructions).toContain(SUMMARY_URI);
  });

  it("lists the eight read tools, each marked read-only", async () => {
    const { result } = await server.request("tools/list");
    const tools = result.tools as Array<{
      name: string;
      description: string;
      annotations?: { readOnlyHint?: boolean };
      inputSchema: Record<string, unknown>;
    }>;

    expect(tools.map((tool) => tool.name).sort()).toEqual([...toolNames].sort());
    for (const tool of tools) {
      expect(tool.annotations?.readOnlyHint, tool.name).toBe(true);
      expect(tool.description.length, tool.name).toBeGreaterThan(40);
      expect(tool.inputSchema, tool.name).toBeDefined();
    }
  });

  it.each(toolNames)("answers tools/call for %s with schemaVersion", async (name) => {
    const { isError, payload } = await server.callTool(name);

    expect(isError).toBe(false);
    expect(payload.schemaVersion).toBe(1);
    expect(payload.asOf).toBe("2026-11-30");
  });

  it("carries arguments through to the tool", async () => {
    const { payload } = await server.callTool("get_today", { date: "2026-11-03" });

    expect(payload.date).toBe("2026-11-03");
    expect(payload.rollup.readiness.score).toBe(68);
  });

  it("reports a bad window as an error in the same envelope", async () => {
    const { isError, payload } = await server.callTool("get_nutrition", {
      from: "2026-11-20",
      to: "2026-11-10",
    });

    expect(isError).toBe(true);
    expect(payload.schemaVersion).toBe(1);
    expect(payload.error).toContain("is after");
  });

  it("rejects an argument the schema does not allow", async () => {
    const { result, error } = await server.request("tools/call", {
      name: "get_today",
      arguments: { date: "the day before yesterday" },
    });

    expect(error ?? result.isError).toBeTruthy();
  });

  it("serves the summary as a resource", async () => {
    const { result } = await server.request("resources/list");
    const uris = (result.resources as Array<{ uri: string }>).map((r) => r.uri);
    expect(uris).toContain(SUMMARY_URI);
    expect(uris).toContain(DAILY_LOG_URI);

    const summary = await server.readResource(SUMMARY_URI);
    expect(summary.mimeType).toBe("text/markdown");
    expect(summary.text).toContain("# Ascension — summary");
    expect(summary.text).toContain("Sessions: 13 of 16 planned");
    expect(summary.text.split("\n").length).toBeLessThanOrEqual(150);
  });

  it("serves the trailing journal, and one day of it by date", async () => {
    const log = await server.readResource(DAILY_LOG_URI);
    expect(log.text).toContain("## 2026-11-30 (Mon)");

    const day = await server.readResource("ascension://daily-log/2026-11-09");
    expect(day.text).toMatch(/^## 2026-11-09 \(Mon\)\n/);
    expect(day.text).not.toContain("2026-11-10");
  });

  it("offers the per-day journal as a template", async () => {
    const { result } = await server.request("resources/templates/list");
    const templates = result.resourceTemplates as Array<{ uriTemplate: string }>;
    expect(templates.map((t) => t.uriTemplate)).toContain("ascension://daily-log/{date}");
  });

  it("says nothing on stderr when the folder is healthy", () => {
    expect(server.stderr).toEqual([]);
  });
});

describe("the server over stdio, on an empty folder", () => {
  let dir: string;
  let server: StdioServer;

  beforeAll(async () => {
    dir = await emptyFolderDir();
    server = await StdioServer.start(dir);
  });
  afterAll(async () => {
    await server.stop();
    await rm(dir, { recursive: true, force: true });
  });

  it("answers every tool with no data rather than an error", async () => {
    for (const name of toolNames) {
      const { isError, payload } = await server.callTool(name);
      expect(isError, name).toBe(false);
      expect(payload.asOf, name).toBeNull();
    }
  });

  it("says why on stderr, where it cannot corrupt the wire", async () => {
    expect(server.stderr.join("\n")).toContain("nothing has been exported");
  });

  it("still serves the resources, saying there is nothing yet", async () => {
    const summary = await server.readResource(SUMMARY_URI);
    expect(summary.text).toContain("nothing has been exported");
  });
});

describe("the server with no export folder configured", () => {
  it("refuses to start, and says which variable to set", async () => {
    const server = StdioServer.unconfigured();
    const code = await server.exited();

    expect(code).toBe(1);
    expect(server.stderr.join("\n")).toContain("ASCENSION_EXPORT_DIR is not set");
  });
});
