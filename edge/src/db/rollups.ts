import { DayRollup, SCHEMA_VERSION } from "../contract";

type Row = {
  date: string;
  timezone: string;
  updatedAt: string;
  json: string;
  ingestedAt: string;
};

export type RollupPage = {
  rollups: DayRollup[];
  /**
   * Rows whose stored JSON no longer satisfies the contract -- only reachable by
   * editing D1 by hand or by a botched migration. Skipped rather than thrown, so
   * one bad row cannot take every read tool down, and surfaced so it is visible.
   */
  unreadableDates: string[];
};

function decode(rows: Row[]): RollupPage {
  const rollups: DayRollup[] = [];
  const unreadableDates: string[] = [];
  for (const row of rows) {
    const parsed = DayRollup.safeParse(JSON.parse(row.json));
    if (parsed.success) rollups.push(parsed.data);
    else unreadableDates.push(row.date);
  }
  return { rollups, unreadableDates };
}

/**
 * Upsert on `date`, so the phone re-sending a day is always safe
 * (docs/EXPORT_SCHEMA.md §1). One `batch()`, so a partial batch never lands.
 */
export async function upsertRollups(
  db: D1Database,
  rollups: DayRollup[],
  ingestedAt: string,
): Promise<void> {
  if (rollups.length === 0) return;
  const statement = db.prepare(
    `INSERT INTO rollups (date, timezone, updatedAt, json, ingestedAt)
     VALUES (?1, ?2, ?3, ?4, ?5)
     ON CONFLICT(date) DO UPDATE SET
       timezone   = excluded.timezone,
       updatedAt  = excluded.updatedAt,
       json       = excluded.json,
       ingestedAt = excluded.ingestedAt`,
  );
  await db.batch(
    rollups.map((rollup) =>
      statement.bind(
        rollup.date,
        rollup.timezone,
        rollup.updatedAt,
        JSON.stringify(rollup),
        ingestedAt,
      ),
    ),
  );
}

/** Rollups from `from` to `to` inclusive, oldest first. */
export async function listRollups(
  db: D1Database,
  from: string,
  to: string,
): Promise<RollupPage> {
  const { results } = await db
    .prepare(
      `SELECT date, timezone, updatedAt, json, ingestedAt FROM rollups
       WHERE date >= ?1 AND date <= ?2 ORDER BY date ASC`,
    )
    .bind(from, to)
    .all<Row>();
  return decode(results);
}

export async function getRollup(
  db: D1Database,
  date: string,
): Promise<DayRollup | null> {
  const row = await db
    .prepare(
      `SELECT date, timezone, updatedAt, json, ingestedAt FROM rollups WHERE date = ?1`,
    )
    .bind(date)
    .first<Row>();
  if (!row) return null;
  return decode([row]).rollups[0] ?? null;
}

/**
 * The newest date the phone has pushed. Every tool anchors on this rather than
 * on the Worker's clock: Muse sees what the phone has synced, not real time
 * (docs/MUSE_CAPABILITIES.md), and anchoring on a wall clock would silently
 * report an un-synced day as a day with no training.
 */
export async function latestDate(db: D1Database): Promise<string | null> {
  const row = await db
    .prepare(`SELECT max(date) AS date FROM rollups`)
    .first<{ date: string | null }>();
  return row?.date ?? null;
}

export { SCHEMA_VERSION };
