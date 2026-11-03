import { expect } from "vitest";
import type { ExportFolder } from "../../src/export-folder";
import { readTools } from "../../src/tools";

export const toolNames = readTools.map((tool) => tool.name);

export function tool(name: string) {
  const found = readTools.find((candidate) => candidate.name === name);
  expect(found, `no tool named ${name}`).toBeDefined();
  return found!;
}

/** Call a tool the way the server does: parse the arguments, then run it. */
export async function runTool(
  name: string,
  args: Record<string, unknown>,
  folder: ExportFolder,
): Promise<Record<string, any>> {
  const definition = tool(name);
  const parsed = definition.inputSchema.parse(args);
  return definition.run(parsed as never, { db: folder });
}
