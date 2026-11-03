/**
 * `daily-log.md`, read a piece at a time.
 *
 * The journal is append-only (`docs/EXPORT_SCHEMA.md` §4) and grows by one block a day
 * for as long as the app is used, so nothing here may load it whole: the trailing days
 * are read backwards from the end of the file in a bounded window, and a single day is
 * found by streaming lines and stopping at the next header. Memory is flat in the size
 * of the file either way.
 *
 * A trailing block that is cut short — a truncated write, a hand-edit — is returned as
 * it stands rather than rejected. The file is a journal, not a schema.
 */
import { open } from "node:fs/promises";
import { createInterface } from "node:readline";

/** `## 2026-11-09 (Mon)` — the block header the app writes. */
const HEADER = /^## (\d{4}-\d{2}-\d{2})(?:\s|$)/;

/** How much of the end of the file a tail read may look at. */
export const TAIL_BYTES = 64 * 1024;

/** How many days a tail read returns. Two weeks is what the summary table shows. */
export const TAIL_BLOCKS = 14;

export type LogBlock = {
  /** `null` only for a fragment with no readable header. */
  date: string | null;
  text: string;
};

export type LogTail = {
  blocks: LogBlock[];
  /** The file is longer than the window read, so earlier days were not looked at. */
  truncated: boolean;
  /** Bytes actually read, which is what keeps this bounded. */
  bytesRead: number;
};

type TailOptions = { maxBytes?: number; maxBlocks?: number };

/**
 * The last `maxBlocks` day blocks, read from at most `maxBytes` at the end of the file.
 * `null` when there is no journal yet.
 */
export async function readTail(
  path: string,
  options: TailOptions = {},
): Promise<LogTail | null> {
  const maxBytes = options.maxBytes ?? TAIL_BYTES;
  const maxBlocks = options.maxBlocks ?? TAIL_BLOCKS;

  const handle = await openForReading(path);
  if (handle === null) return null;
  try {
    const { size } = await handle.stat();
    const length = Math.min(size, maxBytes);
    const position = size - length;
    const buffer = Buffer.alloc(length);
    const { bytesRead } = await handle.read(buffer, 0, length, position);
    let text = buffer.subarray(0, bytesRead).toString("utf8");
    const truncated = position > 0;

    if (!truncated) {
      return { blocks: splitBlocks(text).slice(-maxBlocks), truncated, bytesRead };
    }

    // The window starts mid-file, so it opens on half a line — and possibly half a
    // UTF-8 sequence. Everything before the first whole header goes.
    const boundary = text.indexOf("\n## ");
    if (boundary !== -1) {
      const blocks = splitBlocks(text.slice(boundary + 1));
      return { blocks: blocks.slice(-maxBlocks), truncated, bytesRead };
    }

    // No whole header in the window at all: one day's block is longer than `maxBytes`.
    // The fragment is still the newest thing written, so it is returned as a block with
    // no date rather than silently dropped.
    const fragment = trimPartialStart(text);
    return {
      blocks: fragment === "" ? [] : [{ date: null, text: fragment }],
      truncated,
      bytesRead,
    };
  } finally {
    await handle.close();
  }
}

/**
 * One day's block, found by streaming from the start and stopping at the next header.
 * `null` when the journal has no such day, or no journal exists.
 */
export async function findBlock(path: string, date: string): Promise<LogBlock | null> {
  const handle = await openForReading(path);
  if (handle === null) return null;

  const stream = handle.createReadStream({ encoding: "utf8" });
  const lines = createInterface({ input: stream, crlfDelay: Infinity });
  let captured: string[] | null = null;
  try {
    for await (const line of lines) {
      if (captured !== null) {
        if (line.startsWith("## ")) break;
        captured.push(line);
        continue;
      }
      const header = HEADER.exec(line);
      if (header !== null && header[1] === date) captured = [line];
    }
  } finally {
    lines.close();
    stream.destroy();
  }

  if (captured === null) return null;
  return { date, text: trimTrailingBlanks(captured) };
}

/** Every day the journal holds, streamed. Headers only, so memory is the date list. */
export async function readDates(path: string): Promise<string[]> {
  const handle = await openForReading(path);
  if (handle === null) return [];

  const stream = handle.createReadStream({ encoding: "utf8" });
  const lines = createInterface({ input: stream, crlfDelay: Infinity });
  const dates: string[] = [];
  try {
    for await (const line of lines) {
      const header = HEADER.exec(line);
      if (header !== null) dates.push(header[1]!);
    }
  } finally {
    lines.close();
    stream.destroy();
  }
  return dates;
}

async function openForReading(path: string) {
  try {
    return await open(path, "r");
  } catch {
    return null;
  }
}

/** Split text that begins at a header into one block per day. */
function splitBlocks(text: string): LogBlock[] {
  const blocks: LogBlock[] = [];
  let current: string[] | null = null;
  let date: string | null = null;

  for (const line of text.split("\n")) {
    if (line.startsWith("## ")) {
      if (current !== null) blocks.push({ date, text: trimTrailingBlanks(current) });
      current = [line];
      date = HEADER.exec(line)?.[1] ?? null;
      continue;
    }
    // Lines before the first header are the file's title, or the tail of a block the
    // window cut in half; either way they belong to no day returned here.
    if (current !== null) current.push(line);
  }
  if (current !== null) blocks.push({ date, text: trimTrailingBlanks(current) });
  return blocks;
}

/** Drop the first line of a window that opened mid-line. */
function trimPartialStart(text: string): string {
  const firstBreak = text.indexOf("\n");
  return firstBreak === -1 ? "" : text.slice(firstBreak + 1);
}

function trimTrailingBlanks(lines: string[]): string {
  const kept = [...lines];
  while (kept.length > 0 && kept[kept.length - 1]!.trim() === "") kept.pop();
  return kept.length === 0 ? "" : `${kept.join("\n")}\n`;
}
