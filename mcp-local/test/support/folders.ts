/**
 * Fixture export folders, and the means to prove the server does not touch them.
 *
 * The committed fixtures are the `ExportKit` golden files under their real names, so
 * what these tests parse is byte-for-byte what the app writes. The data in them is
 * invented, respects the dietary rules (chicken and eggs, milk with Bournvita), and is
 * nobody's real health record.
 */
import { createHash } from "node:crypto";
import { mkdtemp, readFile, readdir, stat, writeFile } from "node:fs/promises";
import { cp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { ExportFolder } from "../../src/export-folder";

const FIXTURES = fileURLToPath(new URL("../fixtures", import.meta.url));

export type FixtureName = "full" | "missing-export" | "malformed" | "partial";

export function fixtureDir(name: FixtureName): string {
  return join(FIXTURES, name);
}

/** A folder over a committed fixture, with warnings collected instead of printed. */
export function fixtureFolder(name: FixtureName): {
  folder: ExportFolder;
  warnings: string[];
} {
  const warnings: string[] = [];
  return {
    folder: new ExportFolder(fixtureDir(name), (message) => warnings.push(message)),
    warnings,
  };
}

export function folderAt(dir: string): { folder: ExportFolder; warnings: string[] } {
  const warnings: string[] = [];
  return {
    folder: new ExportFolder(dir, (message) => warnings.push(message)),
    warnings,
  };
}

/** A fresh empty directory — an export folder the app has not written to yet. */
export async function emptyFolderDir(): Promise<string> {
  return mkdtemp(join(tmpdir(), "ascension-empty-"));
}

/** A writable copy of a fixture, for tests that need to change what is on disk. */
export async function copyFixture(name: FixtureName): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), `ascension-${name}-`));
  await cp(fixtureDir(name), dir, { recursive: true });
  return dir;
}

/**
 * A `daily-log.md` with `days` blocks, written into `dir`. Generated rather than
 * committed: the point is a file far larger than anything worth keeping in git.
 */
export async function writeLongDailyLog(dir: string, days: number): Promise<number> {
  const blocks: string[] = ["# Ascension — daily log\n"];
  for (let index = 0; index < days; index += 1) {
    const date = new Date(Date.UTC(2020, 0, 1) + index * 86_400_000)
      .toISOString()
      .slice(0, 10);
    const kcal = 2_000 + (index % 400);
    const protein = 130 + (index % 30);
    blocks.push(
      [
        `## ${date} (Day ${index + 1})`,
        `- Readiness: ${60 + (index % 40)} — train as planned (slept 7h${10 + (index % 50)}; HRV near baseline)`,
        `- Workout (Apple Workout): Strength, 19:04–19:54, 50 min, ${300 + (index % 90)} kcal, HR 118 avg / 147 max`,
        "- Top sets: goblet squat 24 kg × 12 · RDL 22 kg × 12",
        `- Food: ${kcal.toLocaleString("en-US")} kcal · protein ${protein} g / 150 g · fat 64 g · carbs 240 g`,
        "  - Lunch: Chicken breast, rice, vegetables 550 g — 650 kcal, 55 g protein",
        `- Sleep (last night): 7h${10 + (index % 50)}, resting HR 57, HRV 40 ms`,
        `- Weight: 74.0 kg (7-day avg 74.1, −0.4 kg/week) · Steps: ${8_000 + (index % 4_000)}`,
        "",
      ].join("\n"),
    );
  }
  const text = blocks.join("\n");
  await writeFile(join(dir, "daily-log.md"), text, "utf8");
  return Buffer.byteLength(text, "utf8");
}

/**
 * A digest of every file in a folder — name, size, mtime and contents. Read-only is a
 * promise about the folder, so the way to test it is to look at the folder.
 */
export async function folderDigest(dir: string): Promise<string> {
  const names = (await readdir(dir)).sort();
  const hash = createHash("sha256");
  for (const name of names) {
    const path = join(dir, name);
    const info = await stat(path);
    hash.update(`${name}\u0000${info.size}\u0000${info.mtimeMs}\u0000`);
    if (info.isFile()) hash.update(await readFile(path));
  }
  return hash.digest("hex");
}
