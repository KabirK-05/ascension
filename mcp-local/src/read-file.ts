/**
 * Reading files out of a folder that is user data, and therefore untrusted input: the
 * caller gets a described outcome instead of an exception, so "no export yet" and
 * "half a file" are answers rather than crashes.
 */
import { readFile } from "node:fs/promises";

export type JsonFile =
  | { kind: "ok"; value: unknown }
  | { kind: "absent" }
  | { kind: "empty" }
  | { kind: "unparseable"; reason: string }
  | { kind: "unreadable"; reason: string };

export type TextFile =
  | { kind: "ok"; text: string }
  | { kind: "absent" }
  | { kind: "unreadable"; reason: string };

/** The file as JSON, or why it is not. Never throws. */
export async function readJsonFile(path: string): Promise<JsonFile> {
  const file = await readTextFile(path);
  if (file.kind !== "ok") return file;
  if (file.text.trim() === "") return { kind: "empty" };
  try {
    return { kind: "ok", value: JSON.parse(file.text) };
  } catch (error) {
    return { kind: "unparseable", reason: error instanceof Error ? error.message : String(error) };
  }
}

/** The file as text, or why not. Never throws. Opened read-only, as everything here is. */
export async function readTextFile(path: string): Promise<TextFile> {
  try {
    return { kind: "ok", text: await readFile(path, { encoding: "utf8", flag: "r" }) };
  } catch (error) {
    const code = (error as { code?: string } | null)?.code;
    if (code === "ENOENT" || code === "ENOTDIR") return { kind: "absent" };
    return {
      kind: "unreadable",
      reason: error instanceof Error ? error.message : String(error),
    };
  }
}
