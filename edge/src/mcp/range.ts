import { z } from "zod";
import { isoDate } from "../contract";
import { addDays, compareDates } from "../dates";
import { latestDate, listRollups, type RollupPage } from "../db/rollups";

/** Retention is 400 days, so no window may usefully ask for more. */
export const MAX_WINDOW_DAYS = 400;

export const rangeArgs = {
  from: isoDate.optional().describe("First date to include, YYYY-MM-DD."),
  to: isoDate
    .optional()
    .describe("Last date to include. Defaults to the most recent synced day."),
  days: z
    .number()
    .int()
    .min(1)
    .max(MAX_WINDOW_DAYS)
    .optional()
    .describe("Window length ending at `to`. Ignored when `from` is given."),
};

export type RangeArgs = { from?: string; to?: string; days?: number };

export type ResolvedRange = RollupPage & {
  from: string;
  to: string;
  /** The newest day the phone has synced, whatever window was asked for. */
  asOf: string;
};

/**
 * Resolve a window against synced data and load it. Returns `null` when the
 * database holds no rollups at all, which every tool reports as an empty answer
 * rather than inventing a window around the Worker's clock.
 */
export async function resolveRange(
  db: D1Database,
  args: RangeArgs,
  defaultDays: number,
): Promise<ResolvedRange | null> {
  const asOf = await latestDate(db);
  if (!asOf) return null;

  const to = args.to ?? asOf;
  const from = args.from ?? addDays(to, -(Math.max(args.days ?? defaultDays, 1) - 1));
  if (compareDates(from, to) > 0) {
    throw new Error(`\`from\` (${from}) is after \`to\` (${to})`);
  }

  const page = await listRollups(db, from, to);
  return { ...page, from, to, asOf };
}

export function mean(values: Array<number | null | undefined>): number | null {
  const present = values.filter((value): value is number => typeof value === "number");
  if (present.length === 0) return null;
  return present.reduce((sum, value) => sum + value, 0) / present.length;
}

export function round(value: number | null, places = 1): number | null {
  if (value === null) return null;
  const factor = 10 ** places;
  return Math.round(value * factor) / factor;
}

export function sum(values: Array<number | null | undefined>): number {
  return values.reduce<number>(
    (total, value) => total + (typeof value === "number" ? value : 0),
    0,
  );
}
