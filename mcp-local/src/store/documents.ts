/**
 * The document accessors, with the signature `edge/src/db/documents.ts` exposes. Only
 * `goalSettings` is read: it carries the targets a day is judged against and the goal
 * weight, which is all the eight read tools ask a document for.
 *
 * On the device the documents sit inline in `export.json` with their `version` and
 * `updatedAt` (`docs/EXPORT_SCHEMA.md` §4), where D1 keeps those as columns — so the
 * body is parsed loosely here and composed there, and the tools see the same fields.
 */
import type { ExportFolder, StoredGoalSettings } from "../export-folder";

export async function readGoalSettings(
  folder: ExportFolder,
): Promise<StoredGoalSettings | null> {
  return (await folder.snapshot()).goalSettings;
}
