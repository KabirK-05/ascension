/**
 * The rollup accessors, with the signatures `edge/src/db/rollups.ts` exposes — the
 * export folder standing in for D1. Keeping the names and shapes identical is what lets
 * `src/tools.ts` be the cloud server's tool file verbatim; `test/parity.test.ts` holds
 * it to that.
 *
 * There is no `upsertRollups` here, and there never will be: this server reads.
 */
import { SCHEMA_VERSION, type DayRollup } from "../contract";
import type { ExportFolder } from "../export-folder";

export type RollupPage = {
  rollups: DayRollup[];
  /** See `Snapshot.unreadableDates` — the same field the cloud server reports. */
  unreadableDates: string[];
};

/** Rollups from `from` to `to` inclusive, oldest first. */
export async function listRollups(
  folder: ExportFolder,
  from: string,
  to: string,
): Promise<RollupPage> {
  const snapshot = await folder.snapshot();
  return {
    rollups: snapshot.rollups.filter((day) => day.date >= from && day.date <= to),
    unreadableDates: snapshot.unreadableDates.filter((date) => date >= from && date <= to),
  };
}

export async function getRollup(
  folder: ExportFolder,
  date: string,
): Promise<DayRollup | null> {
  const snapshot = await folder.snapshot();
  return snapshot.byDate.get(date) ?? null;
}

/**
 * The newest day in the export. Every tool anchors on this rather than on the Mac's
 * clock: an export folder iCloud has not synced for three days must report the day it
 * has, not today with nothing in it.
 */
export async function latestDate(folder: ExportFolder): Promise<string | null> {
  return (await folder.snapshot()).latest;
}

export { SCHEMA_VERSION };
