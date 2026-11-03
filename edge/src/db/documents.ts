import {
  documentBodies,
  type DocumentKey,
  type FlagsBody,
  type GoalSettingsBody,
} from "../contract";

type Row = {
  key: string;
  version: number;
  json: string;
  updatedAt: string;
  updatedBy: string;
};

/**
 * The full document as docs/EXPORT_SCHEMA.md §2 shows it: the stored body with
 * `version`, `updatedAt` and `updatedBy` composed back in from the columns.
 */
export type StoredDocument<Body> = Body & {
  version: number;
  updatedAt: string;
  updatedBy: string;
};

export async function readDocument<K extends DocumentKey>(
  db: D1Database,
  key: K,
): Promise<StoredDocument<Record<string, unknown>> | null> {
  const row = await db
    .prepare(
      `SELECT key, version, json, updatedAt, updatedBy FROM documents WHERE key = ?1`,
    )
    .bind(key)
    .first<Row>();
  if (!row) return null;
  const body = documentBodies[key].safeParse(JSON.parse(row.json));
  if (!body.success) return null;
  return {
    ...(body.data as Record<string, unknown>),
    version: row.version,
    updatedAt: row.updatedAt,
    updatedBy: row.updatedBy,
  };
}

export async function readGoalSettings(
  db: D1Database,
): Promise<StoredDocument<GoalSettingsBody> | null> {
  return (await readDocument(db, "goalSettings")) as
    | StoredDocument<GoalSettingsBody>
    | null;
}

export async function readFlags(
  db: D1Database,
): Promise<StoredDocument<FlagsBody> | null> {
  return (await readDocument(db, "flags")) as StoredDocument<FlagsBody> | null;
}
