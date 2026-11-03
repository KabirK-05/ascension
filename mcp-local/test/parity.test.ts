/**
 * The anti-drift gate.
 *
 * Muse reaches the data through `edge/`, Claude Code reaches it through here. If a
 * field name or a tool description drifts between the two, the same training week gets
 * described two different ways — which is the one failure this ticket exists to
 * prevent. So three files are held to the cloud server's: the contract and the date
 * arithmetic byte-for-byte, and everything in `tools.ts` from `ReadTool` down.
 *
 * These skip rather than fail when `edge/` is not beside this package, so the package
 * still tests on its own; CI checks out the whole repo, where they run.
 */
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { toolNames } from "./support/tools";

const edge = (file: string) =>
  fileURLToPath(new URL(`../../edge/src/${file}`, import.meta.url));
const local = (file: string) =>
  fileURLToPath(new URL(`../src/${file}`, import.meta.url));

/** Where `tools.ts` stops being this package's and starts being the cloud server's. */
const SHARED_FROM = "export type ReadTool = {";

function sharedBody(path: string): string {
  const text = readFileSync(path, "utf8");
  const at = text.indexOf(SHARED_FROM);
  expect(at, `${SHARED_FROM} not found in ${path}`).toBeGreaterThan(-1);
  return text.slice(at);
}

const hasEdge = existsSync(edge("contract.ts"));

describe.skipIf(!hasEdge)("the cloud server's files, copied verbatim", () => {
  it.each(["contract.ts", "dates.ts"])(
    "%s is byte-identical to edge/src/%s",
    (file) => {
      expect(readFileSync(local(file), "utf8")).toBe(readFileSync(edge(file), "utf8"));
    },
  );

  it("tools.ts shares the cloud server's tool bodies byte for byte", () => {
    expect(sharedBody(local("tools.ts"))).toBe(sharedBody(edge("mcp/tools.ts")));
  });
});

describe("the tool surface", () => {
  it("is the eight read tools docs/MUSE_CAPABILITIES.md lists, and nothing else", () => {
    expect(toolNames).toEqual([
      "get_today",
      "get_workouts",
      "get_nutrition",
      "get_weight_trend",
      "get_readiness",
      "get_checkins",
      "get_exercise_history",
      "get_consistency_grid",
    ]);
  });

  it("has no tool that writes", () => {
    const writing = toolNames.filter((name) =>
      /^(set|log|update|swap|queue|delete|propose|apply)_/.test(name),
    );
    expect(writing).toEqual([]);
  });
});
