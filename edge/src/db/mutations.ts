/**
 * The append-only write log (docs/EXPORT_SCHEMA.md §3).
 *
 * No UPDATE of `payload` and no DELETE, ever: every change Muse makes is an
 * audit record with an actor and a timestamp, which is what makes writing
 * without confirmation safe rather than reckless (docs/MUSE_CAPABILITIES.md).
 * The one column that is ever updated is `appliedAt`, and only from NULL.
 */
import { Mutation, type MutationKind } from "../contract";
import { ulid } from "../ulid";

type Row = {
  id: string;
  createdAt: string;
  actor: string;
  kind: string;
  payload: string;
  appliedAt: string | null;
  appliedResult: string | null;
};

export type AppendedMutation = {
  id: string;
  createdAt: string;
  kind: MutationKind;
  appliedAt: string | null;
};

function decode(row: Row): Mutation | null {
  const parsed = Mutation.safeParse({
    id: row.id,
    createdAt: row.createdAt,
    actor: row.actor,
    kind: row.kind,
    payload: JSON.parse(row.payload),
    appliedAt: row.appliedAt,
    appliedResult: row.appliedResult === null ? null : JSON.parse(row.appliedResult),
  });
  return parsed.success ? parsed.data : null;
}

/**
 * Append one mutation. `appliedAt` is set here only for a Tier-1 kind the Worker
 * has just applied in D1; a Tier-2 kind is left NULL for the device to stamp.
 */
export async function appendMutation(
  db: D1Database,
  entry: {
    kind: MutationKind;
    payload: unknown;
    actor?: string;
    createdAt?: string;
    appliedAt?: string | null;
    appliedResult?: unknown;
  },
): Promise<AppendedMutation> {
  const id = ulid();
  const createdAt = entry.createdAt ?? new Date().toISOString();
  const appliedAt = entry.appliedAt ?? null;
  await db
    .prepare(
      `INSERT INTO mutations (id, createdAt, actor, kind, payload, appliedAt, appliedResult)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`,
    )
    .bind(
      id,
      createdAt,
      entry.actor ?? "muse",
      entry.kind,
      JSON.stringify(entry.payload ?? {}),
      appliedAt,
      entry.appliedResult === undefined ? null : JSON.stringify(entry.appliedResult),
    )
    .run();
  return { id, createdAt, kind: entry.kind, appliedAt };
}

export type MutationPage = {
  mutations: Mutation[];
  /** What to send as `since` next time. `null` when the page is empty. */
  cursor: string | null;
  /** Rows whose stored shape no longer satisfies the contract. */
  unreadableIds: string[];
};

/**
 * The tail after `since`, in ULID order. Not filtered on `appliedAt`: the device
 * applies Tier-1 mutations too, to catch its local state up with a write the
 * Worker already made, so the cursor is the only thing that decides the page.
 */
export async function listMutationsSince(
  db: D1Database,
  since: string | null,
  limit = 500,
): Promise<MutationPage> {
  const { results } = await db
    .prepare(
      `SELECT id, createdAt, actor, kind, payload, appliedAt, appliedResult FROM mutations
       WHERE id > ?1 ORDER BY id ASC LIMIT ?2`,
    )
    .bind(since ?? "", limit)
    .all<Row>();

  const mutations: Mutation[] = [];
  const unreadableIds: string[] = [];
  for (const row of results) {
    const decoded = decode(row);
    if (decoded) mutations.push(decoded);
    else unreadableIds.push(row.id);
  }
  const last = results[results.length - 1];
  return { mutations, cursor: last?.id ?? null, unreadableIds };
}

export type AckOutcome = {
  acked: string[];
  /** Already stamped by an earlier delivery, so applied zero extra times. */
  alreadyApplied: string[];
  unknown: string[];
};

/**
 * Stamp `appliedAt` from the device's own instant, and only where it is NULL.
 *
 * A repeated ack is ordinary — the device re-delivers a page whose ack did not
 * land — and must not move a timestamp that is already recorded, or a Tier-1
 * row's cloud-side instant would be overwritten by the phone's later catch-up.
 */
export async function ackMutations(
  db: D1Database,
  ids: string[],
  appliedAt: string,
): Promise<AckOutcome> {
  const acked: string[] = [];
  const alreadyApplied: string[] = [];
  const unknown: string[] = [];

  for (const id of ids) {
    const row = await db
      .prepare(`SELECT appliedAt FROM mutations WHERE id = ?1`)
      .bind(id)
      .first<{ appliedAt: string | null }>();
    if (!row) {
      unknown.push(id);
      continue;
    }
    if (row.appliedAt !== null) {
      alreadyApplied.push(id);
      continue;
    }
    await db
      .prepare(`UPDATE mutations SET appliedAt = ?2 WHERE id = ?1 AND appliedAt IS NULL`)
      .bind(id, appliedAt)
      .run();
    acked.push(id);
  }

  return { acked, alreadyApplied, unknown };
}

/** How many mutations are still waiting for the phone. */
export async function countPending(db: D1Database): Promise<number> {
  const row = await db
    .prepare(`SELECT count(*) AS pending FROM mutations WHERE appliedAt IS NULL`)
    .first<{ pending: number }>();
  return row?.pending ?? 0;
}
