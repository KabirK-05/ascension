import { testEnv } from "./env";
import type { DayRollup, FlagsBody, ProgramBody } from "../src/contract";
import { upsertRollups } from "../src/db/rollups";
import { ToolError } from "../src/mcp/errors";
import { readTools, type ReadTool } from "../src/mcp/tools";
import { writeTools, type WriteContext, type WriteTool } from "../src/mcp/writes";
import { FLAGS, GOAL_SETTINGS, PROGRAM, seedSeries } from "./fixtures";

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

/* ------------------------------------------------------------ write tools -- */

/**
 * Put the three documents back to the state migration 0002 leaves them in, and
 * empty the two append-only tables. Every write test starts from here, so one
 * test's flag flip cannot change what the next one is testing.
 */
export async function seedDocuments(
  options: { program?: ProgramBody | null; flags?: Partial<FlagsBody> } = {},
): Promise<void> {
  await testEnv.DB.prepare(`DELETE FROM documents`).run();
  await testEnv.DB.prepare(`DELETE FROM mutations`).run();
  await testEnv.DB.prepare(`DELETE FROM suggestions`).run();

  const at = "2026-11-03T18:00:00-05:00";
  const insert = testEnv.DB.prepare(
    `INSERT INTO documents (key, version, json, updatedAt, updatedBy)
     VALUES (?1, 1, ?2, ?3, 'system')`,
  );
  await insert.bind("goalSettings", JSON.stringify(GOAL_SETTINGS), at).run();
  await insert
    .bind("flags", JSON.stringify({ ...FLAGS, ...options.flags }), at)
    .run();

  // `program` is not seeded by a migration: §2.2 prints one session, and
  // inventing the rest in SQL would fork a contract the device owns. A test that
  // needs one passes it.
  const program = options.program === undefined ? PROGRAM : options.program;
  if (program) {
    await insert.bind("program", JSON.stringify(program), at).run();
  }
}

export function writeTool(name: string): WriteTool {
  const found = writeTools.find((candidate) => candidate.name === name);
  if (!found) throw new Error(`no such write tool: ${name}`);
  return found;
}

/**
 * Run a write tool the way the MCP server does, but with the raw arguments: the
 * tool's own `parseArgs` is then the gate under test, which is the one that
 * matters for a client that sends something the contract does not allow.
 */
export async function write(
  name: string,
  args: Record<string, unknown> = {},
  ctx: Partial<WriteContext> = {},
): Promise<Record<string, any>> {
  return writeTool(name).run(args, { db: testEnv.DB, ...ctx });
}

/** Run a write expected to fail, and hand back the rejection to assert on. */
export async function writeFails(
  name: string,
  args: Record<string, unknown> = {},
  ctx: Partial<WriteContext> = {},
): Promise<ToolError> {
  try {
    await write(name, args, ctx);
  } catch (error) {
    if (error instanceof ToolError) return error;
    throw error;
  }
  throw new Error(`${name} was expected to be rejected, and was not`);
}

export async function mutationRows(): Promise<
  Array<{ id: string; kind: string; actor: string; appliedAt: string | null; payload: string }>
> {
  const { results } = await testEnv.DB.prepare(
    `SELECT id, kind, actor, appliedAt, payload FROM mutations ORDER BY id ASC`,
  ).all<{ id: string; kind: string; actor: string; appliedAt: string | null; payload: string }>();
  return results;
}

export async function documentRow(
  key: string,
): Promise<{ version: number; json: string; updatedBy: string } | null> {
  return testEnv.DB.prepare(
    `SELECT version, json, updatedBy FROM documents WHERE key = ?1`,
  )
    .bind(key)
    .first<{ version: number; json: string; updatedBy: string }>();
}
