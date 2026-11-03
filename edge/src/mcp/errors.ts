import { z } from "zod";

/**
 * A rejection a write tool reports with a slug and the offending values.
 *
 * Nothing is ever coerced into legality: an unknown enum value or an unexpected
 * field means the app and the Worker have diverged, and a target that breaks an
 * invariant is a bad instruction — both come back as a failure naming what was
 * wrong, so Muse can fix it rather than guess.
 */
export class ToolError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly detail: Record<string, unknown> = {},
  ) {
    super(message);
    this.name = "ToolError";
  }
}

/** Enough to fix a divergence, few enough that one bad call cannot flood logs. */
const MAX_REPORTED_ISSUES = 20;

export function zodIssues(
  error: z.ZodError,
): Array<{ path: string; message: string }> {
  return error.issues.slice(0, MAX_REPORTED_ISSUES).map((issue) => ({
    path: issue.path.join("."),
    message: issue.message,
  }));
}

/**
 * Parse tool arguments against the contract, or fail loudly.
 *
 * The MCP server validates against the same schema before `run` is reached, so
 * over the wire this is belt and braces; called directly — by the phone's
 * endpoints and by the tests — it is the only gate.
 */
export function parseArgs<T>(schema: z.ZodType<T>, args: unknown): T {
  const parsed = schema.safeParse(args);
  if (!parsed.success) {
    throw new ToolError("contract_violation", "the arguments do not match the contract", {
      hint: "field names and enums must match docs/EXPORT_SCHEMA.md exactly",
      issues: zodIssues(parsed.error),
    });
  }
  return parsed.data;
}
