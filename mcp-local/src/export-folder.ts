/**
 * The export folder, read strictly for reading.
 *
 * `ExportKit` writes `export.json` atomically — temp file, then rename — so a plain
 * read either sees the whole previous file or the whole new one. What this must still
 * survive is a folder that is *not* in the happy state: no export yet, a zero-byte
 * file, a file iCloud has only partly materialised, or one a hand-edit has broken.
 * None of those may throw: a tool answers "nothing synced" and the reason goes to
 * stderr, because a server that dies on a bad byte is worse than one that says so.
 *
 * `export.json` is the only file the tools read. `docs/EXPORT_SCHEMA.md` §4 calls it
 * the superset and every CSV a projection of `rollups[]` — reading the CSVs too would
 * add a second source for the same number and with it the chance of disagreeing.
 *
 * Nothing here opens a file for anything but reading, and nothing writes, moves or
 * removes. That is the whole contract of this server (spec §9.3).
 */
import { stat } from "node:fs/promises";
import { join } from "node:path";
import { z } from "zod";
import { DayRollup, SCHEMA_VERSION, Targets, isoTimestamp } from "./contract";
import { readJsonFile } from "./read-file";

export const fileNames = {
  export: "export.json",
  dailyLog: "daily-log.md",
  summary: "summary-latest.md",
} as const;

export const EXPORT_DIR_ENV = "ASCENSION_EXPORT_DIR";

/**
 * The folder itself is missing or unreadable. A configuration problem, not an absence
 * of data, so it is raised rather than reported as an empty day — the two need
 * different answers from the person reading them.
 */
export class ExportFolderUnavailable extends Error {
  constructor(dir: string, reason: string) {
    super(
      `cannot read the export folder ${dir}: ${reason}. ` +
        `Set ${EXPORT_DIR_ENV} to the iCloud Drive folder the app exports into.`,
    );
    this.name = "ExportFolderUnavailable";
  }
}

/**
 * The slice of `documents.goalSettings` the read tools use: the targets a day is judged
 * against and the goal weight. Parsed loosely on purpose — the stored document also
 * carries `version`/`updatedAt`/`updatedBy` inline (`docs/EXPORT_SCHEMA.md` §4) and may
 * grow fields this server has no use for, and neither should cost a reader its targets.
 */
const StoredGoalSettings = z.object({
  targets: Targets,
  body: z.object({ goalWeightKg: z.number() }),
});

export type StoredGoalSettings = z.infer<typeof StoredGoalSettings>;

/**
 * Only what this server reads, and every part of it optional: a file missing one of
 * these is a file with less data, not a file to reject.
 */
const ExportEnvelope = z.object({
  schemaVersion: z.number().int().optional(),
  exportedAt: isoTimestamp.optional(),
  rollups: z.array(z.unknown()).optional(),
  documents: z.object({ goalSettings: z.unknown().optional() }).optional(),
});

export type Snapshot = {
  /** When the app wrote the file, or `null` when there is no readable export. */
  exportedAt: string | null;
  /** Readable days, oldest first. */
  rollups: DayRollup[];
  byDate: Map<string, DayRollup>;
  /** The newest readable day, which is every tool's `asOf`. */
  latest: string | null;
  /**
   * Days whose entry in `rollups[]` no longer satisfies the contract — a hand-edit or
   * an export from a newer `schemaVersion`. Skipped rather than thrown, so one bad day
   * cannot take every tool down, and surfaced so it is visible. The same field the
   * cloud server reports for the same reason (`edge/src/db/rollups.ts`).
   */
  unreadableDates: string[];
  goalSettings: StoredGoalSettings | null;
  /** Why the folder holds less than it should. For stderr, never for a tool response. */
  problem: string | null;
};

function emptySnapshot(problem: string | null): Snapshot {
  return {
    exportedAt: null,
    rollups: [],
    byDate: new Map(),
    latest: null,
    unreadableDates: [],
    goalSettings: null,
    problem,
  };
}

/** The `date` of an entry we could not parse, when the entry at least has one. */
function entryDate(entry: unknown): string | null {
  if (typeof entry !== "object" || entry === null) return null;
  const date = (entry as { date?: unknown }).date;
  return typeof date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(date) ? date : null;
}

function decode(parsed: z.infer<typeof ExportEnvelope>): Snapshot {
  const problems: string[] = [];
  if (parsed.schemaVersion !== undefined && parsed.schemaVersion !== SCHEMA_VERSION) {
    problems.push(
      `${fileNames.export} is schemaVersion ${parsed.schemaVersion}, this server reads ${SCHEMA_VERSION}`,
    );
  }

  const rollups: DayRollup[] = [];
  const unreadable = new Set<string>();
  let datelessEntries = 0;
  for (const entry of parsed.rollups ?? []) {
    const day = DayRollup.safeParse(entry);
    if (day.success) {
      rollups.push(day.data);
      continue;
    }
    const date = entryDate(entry);
    // A day with no readable date cannot be named in `unreadableDates` without putting
    // a non-date in a list of dates, so it is counted here and reported to stderr.
    if (date === null) datelessEntries += 1;
    else unreadable.add(date);
  }
  if (datelessEntries > 0) {
    problems.push(
      `${datelessEntries} ${datelessEntries === 1 ? "entry" : "entries"} in rollups[] could not be read and carry no date`,
    );
  }
  if (unreadable.size > 0) {
    problems.push(`${unreadable.size} day(s) in rollups[] do not satisfy the contract`);
  }

  // Sorted and deduplicated here rather than trusted: the app writes days in order and
  // only once, but this file can be edited by hand, and every tool below reads
  // `rollups` as ordered.
  const byDate = new Map<string, DayRollup>();
  for (const day of rollups.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0))) {
    byDate.set(day.date, day);
  }
  const ordered = [...byDate.values()];

  const goalSettings = StoredGoalSettings.safeParse(parsed.documents?.goalSettings);
  if (!goalSettings.success && parsed.documents?.goalSettings !== undefined) {
    problems.push("documents.goalSettings could not be read, so targets are unavailable");
  }

  return {
    exportedAt: parsed.exportedAt ?? null,
    rollups: ordered,
    byDate,
    latest: ordered.length > 0 ? ordered[ordered.length - 1]!.date : null,
    unreadableDates: [...unreadable].sort(),
    goalSettings: goalSettings.success ? goalSettings.data : null,
    problem: problems.length > 0 ? problems.join("; ") : null,
  };
}

/** Where a diagnostic goes. stdout is the MCP wire, so this can only be stderr. */
export type Warn = (message: string) => void;

const warnToStderr: Warn = (message) => {
  process.stderr.write(`ascension-mcp-local: ${message}\n`);
};

export class ExportFolder {
  readonly dir: string;
  readonly #warn: Warn;
  #key: string | null = null;
  #loading: Promise<Snapshot> | null = null;
  #reported: string | null = null;

  constructor(dir: string, warn: Warn = warnToStderr) {
    this.dir = dir;
    this.#warn = warn;
  }

  path(file: (typeof fileNames)[keyof typeof fileNames]): string {
    return join(this.dir, file);
  }

  /**
   * The current export, re-read when `export.json` has changed on disk. The app
   * rewrites the file nightly under a long-lived server, so a snapshot held for the
   * process lifetime would answer this week's question with last week's data.
   */
  async snapshot(): Promise<Snapshot> {
    await this.#requireFolder();
    const key = await this.#exportKey();
    if (this.#loading !== null && this.#key === key) return this.#loading;
    this.#key = key;
    this.#loading = this.#load();
    return this.#loading;
  }

  async #requireFolder(): Promise<void> {
    try {
      const info = await stat(this.dir);
      if (!info.isDirectory()) throw new ExportFolderUnavailable(this.dir, "not a directory");
    } catch (error) {
      if (error instanceof ExportFolderUnavailable) throw error;
      throw new ExportFolderUnavailable(this.dir, describe(error));
    }
  }

  /** Identity of the file as it is right now: a change here means a re-read. */
  async #exportKey(): Promise<string> {
    try {
      const info = await stat(this.path(fileNames.export));
      return `${info.ino}:${info.size}:${info.mtimeMs}`;
    } catch {
      return "absent";
    }
  }

  async #load(): Promise<Snapshot> {
    const snapshot = await this.#read();
    if (snapshot.problem !== null && snapshot.problem !== this.#reported) {
      this.#reported = snapshot.problem;
      this.#warn(snapshot.problem);
    }
    return snapshot;
  }

  async #read(): Promise<Snapshot> {
    const file = await readJsonFile(this.path(fileNames.export));
    switch (file.kind) {
      case "absent":
        return emptySnapshot(`no ${fileNames.export} in ${this.dir} yet — nothing has been exported`);
      case "empty":
        return emptySnapshot(`${fileNames.export} is empty — an export may be in progress`);
      case "unparseable":
        return emptySnapshot(
          `${fileNames.export} is not valid JSON (${file.reason}) — a partial file, or edited by hand`,
        );
      case "unreadable":
        return emptySnapshot(`${fileNames.export} could not be read: ${file.reason}`);
      case "ok": {
        const envelope = ExportEnvelope.safeParse(file.value);
        if (!envelope.success) {
          return emptySnapshot(
            `${fileNames.export} is not an Ascension export (${envelope.error.issues[0]?.message ?? "unexpected shape"})`,
          );
        }
        return decode(envelope.data);
      }
    }
  }
}

function describe(error: unknown): string {
  const code = (error as { code?: string } | null)?.code;
  if (code === "ENOENT") return "no such folder";
  if (code === "ENOTDIR") return "not a directory";
  if (code === "EACCES" || code === "EPERM") return "permission denied";
  return error instanceof Error ? error.message : String(error);
}
