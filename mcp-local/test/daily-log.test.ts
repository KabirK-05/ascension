/**
 * `daily-log.md`: the trailing days, one day by date, and what happens when the file is
 * far bigger than anything a reader should load.
 */
import { appendFile, rm, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { TAIL_BLOCKS, findBlock, readDates, readTail } from "../src/daily-log";
import { copyFixture, emptyFolderDir, fixtureDir, writeLongDailyLog } from "./support/folders";

const temporary: string[] = [];
afterEach(async () => {
  while (temporary.length > 0) {
    await rm(temporary.pop()!, { recursive: true, force: true });
  }
});

async function scratch(create: () => Promise<string>): Promise<string> {
  const dir = await create();
  temporary.push(dir);
  return dir;
}

const fullLog = join(fixtureDir("full"), "daily-log.md");

describe("the trailing days", () => {
  it("returns whole blocks, newest last, from a journal that fits the window", async () => {
    const tail = await readTail(fullLog);

    expect(tail).not.toBeNull();
    expect(tail!.truncated).toBe(false);
    expect(tail!.blocks).toHaveLength(TAIL_BLOCKS);
    expect(tail!.blocks.at(-1)!.date).toBe("2026-11-30");
    expect(tail!.blocks.at(-1)!.text).toMatch(/^## 2026-11-30 \(Mon\)\n/);
    expect(tail!.blocks.at(-1)!.text).toContain("- Readiness: 68");
    // The file's own title line belongs to no day.
    for (const block of tail!.blocks) expect(block.text).not.toContain("# Ascension — daily log");
  });

  it("is null when there is no journal yet", async () => {
    const dir = await scratch(emptyFolderDir);
    expect(await readTail(join(dir, "daily-log.md"))).toBeNull();
  });
});

describe("one day by date", () => {
  it("finds a day in the middle of the file and stops at the next header", async () => {
    const block = await findBlock(fullLog, "2026-11-09");

    expect(block).not.toBeNull();
    expect(block!.text).toMatch(/^## 2026-11-09 \(Mon\)\n/);
    expect(block!.text.trimEnd().split("\n").at(-1)).toMatch(/^- Weight: /);
    expect(block!.text).not.toContain("2026-11-10");
  });

  it("is null for a day the journal does not hold", async () => {
    expect(await findBlock(fullLog, "2020-01-01")).toBeNull();
  });
});

describe("a journal far longer than the window", () => {
  it("reads only the end of it, and still returns whole days", async () => {
    const dir = await scratch(emptyFolderDir);
    const bytes = await writeLongDailyLog(dir, 4_000);
    const path = join(dir, "daily-log.md");

    expect(bytes).toBeGreaterThan(1_500_000);
    const tail = await readTail(path);

    expect(tail!.truncated).toBe(true);
    // The guarantee that matters: the read is bounded by the window, not the file.
    expect(tail!.bytesRead).toBeLessThanOrEqual(64 * 1024);
    expect(tail!.bytesRead * 20).toBeLessThan(bytes);
    expect(tail!.blocks).toHaveLength(TAIL_BLOCKS);
    for (const block of tail!.blocks) {
      expect(block.date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      expect(block.text).toMatch(/^## \d{4}-\d{2}-\d{2} /);
    }
    // 4,000 days from 2020-01-01 ends on 2030-12-13.
    expect(tail!.blocks.at(-1)!.date).toBe("2030-12-13");
  });

  it("finds an early day without reading to the end", async () => {
    const dir = await scratch(emptyFolderDir);
    await writeLongDailyLog(dir, 4_000);
    const path = join(dir, "daily-log.md");

    const block = await findBlock(path, "2020-01-03");
    expect(block!.text).toMatch(/^## 2020-01-03 \(Day 3\)\n/);
    expect(block!.text).not.toContain("2020-01-04");
  });

  it("lists every date it holds without holding the file", async () => {
    const dir = await scratch(emptyFolderDir);
    await writeLongDailyLog(dir, 4_000);
    const dates = await readDates(join(dir, "daily-log.md"));

    expect(dates).toHaveLength(4_000);
    expect(dates[0]).toBe("2020-01-01");
    expect(dates.at(-1)).toBe("2030-12-13");
  });
});

describe("a journal cut short", () => {
  it("returns a trailing partial block rather than rejecting the file", async () => {
    const dir = await scratch(() => copyFixture("full"));
    const path = join(dir, "daily-log.md");
    await appendFile(path, "\n## 2026-12-01 (Tue)\n- Readiness: 77 — train as pla");

    const tail = await readTail(path);
    const last = tail!.blocks.at(-1)!;
    expect(last.date).toBe("2026-12-01");
    expect(last.text).toContain("train as pla");
  });

  it("returns a header-less fragment when one day is longer than the window", async () => {
    const dir = await scratch(emptyFolderDir);
    const path = join(dir, "daily-log.md");
    await writeFile(
      path,
      `# Ascension — daily log\n\n## 2026-11-30 (Mon)\n${"- Top sets: goblet squat 24 kg × 12\n".repeat(400)}`,
    );
    expect((await stat(path)).size).toBeGreaterThan(2_048);

    const tail = await readTail(path, { maxBytes: 2_048 });
    expect(tail!.truncated).toBe(true);
    expect(tail!.blocks).toHaveLength(1);
    expect(tail!.blocks[0]!.date).toBeNull();
    expect(tail!.blocks[0]!.text).toContain("goblet squat");
  });

  it("drops a half-read multi-byte character instead of returning it", async () => {
    const dir = await scratch(emptyFolderDir);
    const path = join(dir, "daily-log.md");
    await writeFile(
      path,
      "# Ascension — daily log\n\n## 2026-11-29 (Sun)\n- Top sets: goblet squat 24 kg × 12 · RDL 22 kg × 12\n\n## 2026-11-30 (Mon)\n- Food: 2,281 kcal · protein 159 g / 150 g\n",
    );

    // A window that lands inside the `·` of the 29th's line.
    const tail = await readTail(path, { maxBytes: 70 });
    expect(tail!.truncated).toBe(true);
    for (const block of tail!.blocks) expect(block.text).not.toContain("�");
  });
});
