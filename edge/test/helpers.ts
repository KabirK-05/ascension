import { testEnv } from "./env";
import type { DayRollup } from "../src/contract";
import { upsertRollups } from "../src/db/rollups";
import { readTools, type ReadTool } from "../src/mcp/tools";
import { seedSeries } from "./fixtures";

export async function seedRollups(rollups: DayRollup[] = seedSeries()): Promise<void> {
  await testEnv.DB.prepare(`DELETE FROM rollups`).run();
  // Batched: D1 caps how many statements one batch may carry comfortably.
  for (let i = 0; i < rollups.length; i += 50) {
    await upsertRollups(testEnv.DB, rollups.slice(i, i + 50), "2026-11-04T02:00:00Z");
  }
}

export function tool(name: string): ReadTool {
  const found = readTools.find((candidate) => candidate.name === name);
  if (!found) throw new Error(`no such tool: ${name}`);
  return found;
}

/** Validate the arguments the way the MCP server will, then run the tool. */
export async function call(
  name: string,
  args: Record<string, unknown> = {},
): Promise<Record<string, any>> {
  const definition = tool(name);
  const parsed = definition.inputSchema.parse(args);
  return definition.run(parsed as never, { db: testEnv.DB });
}
