import {
  documentBodies,
  type DocumentKey,
  type FlagsBody,
  type GoalSettingsBody,
  type ProgramBody,
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

export async function readProgram(
  db: D1Database,
): Promise<StoredDocument<ProgramBody> | null> {
  return (await readDocument(db, "program")) as StoredDocument<ProgramBody> | null;
}

/** The version a document is at, and `0` for one that has never been written. */
export async function documentVersion(
  db: D1Database,
  key: DocumentKey,
): Promise<number> {
  const row = await db
    .prepare(`SELECT version FROM documents WHERE key = ?1`)
    .bind(key)
    .first<{ version: number }>();
  return row?.version ?? 0;
}

export type WriteOutcome<Body> =
  | { ok: true; document: StoredDocument<Body> }
  | { ok: false; currentVersion: number; document: StoredDocument<Record<string, unknown>> | null };

/**
 * Write a document body, bumping `version`, under `If-Match` concurrency
 * (docs/EXPORT_SCHEMA.md §2).
 *
 * `expectedVersion` is the version the edit was made against; `0` means "this
 * document does not exist yet", which is how `program` starts — migration 0002
 * deliberately does not seed it. `null` means the caller did not ask for a
 * version check.
 *
 * The UPDATE carries the version in its WHERE clause, so the check and the write
 * are one statement and two concurrent writers cannot both see version 3 and
 * both produce version 4.
 */
export async function writeDocument<K extends DocumentKey>(
  db: D1Database,
  key: K,
  body: unknown,
  options: {
    expectedVersion: number | null;
    updatedBy: string;
    updatedAt: string;
  },
): Promise<WriteOutcome<Record<string, unknown>>> {
  const json = JSON.stringify(body);
  const current = await documentVersion(db, key);
  const { expectedVersion, updatedBy, updatedAt } = options;

  if (expectedVersion !== null && expectedVersion !== current) {
    return { ok: false, currentVersion: current, document: await readDocument(db, key) };
  }

  if (current === 0) {
    const inserted = await db
      .prepare(
        `INSERT INTO documents (key, version, json, updatedAt, updatedBy)
         VALUES (?1, 1, ?2, ?3, ?4)
         ON CONFLICT(key) DO NOTHING`,
      )
      .bind(key, json, updatedAt, updatedBy)
      .run();
    if ((inserted.meta.changes ?? 0) === 0) {
      // Someone inserted the row between the read and the insert.
      return { ok: false, currentVersion: await documentVersion(db, key), document: await readDocument(db, key) };
    }
  } else {
    const updated = await db
      .prepare(
        `UPDATE documents SET version = version + 1, json = ?2, updatedAt = ?3, updatedBy = ?4
         WHERE key = ?1 AND version = ?5`,
      )
      .bind(key, json, updatedAt, updatedBy, current)
      .run();
    if ((updated.meta.changes ?? 0) === 0) {
      return { ok: false, currentVersion: await documentVersion(db, key), document: await readDocument(db, key) };
    }
  }

  const document = await readDocument(db, key);
  if (!document) {
    // Only reachable if the body just written no longer parses, which means the
    // contract and the validator disagree -- loud, not silent.
    throw new Error(`wrote ${key} but it no longer parses against the contract`);
  }
  return { ok: true, document };
}
