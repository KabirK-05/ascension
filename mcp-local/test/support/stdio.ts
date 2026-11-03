/**
 * The server as a client sees it: the real process, the real stdio transport,
 * newline-delimited JSON-RPC on the wire. This is what `npx @modelcontextprotocol/
 * inspector` does, run in CI so it keeps being true.
 *
 * `edge/test/mcp.test.ts` drives raw JSON-RPC at its transport for the same reason, so
 * these two test suites exercise their servers the same way.
 */
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createInterface, type Interface } from "node:readline";
import { fileURLToPath } from "node:url";

const TSX = fileURLToPath(new URL("../../node_modules/.bin/tsx", import.meta.url));
const ENTRY = fileURLToPath(new URL("../../src/index.ts", import.meta.url));
const PACKAGE = fileURLToPath(new URL("../..", import.meta.url));

export type Rpc = { result?: any; error?: { code: number; message: string } };

export class StdioServer {
  readonly stderr: string[] = [];
  #child: ChildProcessWithoutNullStreams;
  #lines: Interface;
  #waiting = new Map<number, (message: Rpc) => void>();
  #nextId = 1;
  #exited: Promise<number | null>;

  private constructor(exportDir: string | undefined) {
    const env = { ...process.env };
    delete env.ASCENSION_EXPORT_DIR;
    if (exportDir !== undefined) env.ASCENSION_EXPORT_DIR = exportDir;

    this.#child = spawn(TSX, [ENTRY], {
      cwd: PACKAGE,
      env,
      stdio: ["pipe", "pipe", "pipe"],
    }) as ChildProcessWithoutNullStreams;

    this.#lines = createInterface({ input: this.#child.stdout, crlfDelay: Infinity });
    this.#lines.on("line", (line) => {
      if (line.trim() === "") return;
      const message = JSON.parse(line);
      if (typeof message.id === "number") this.#waiting.get(message.id)?.(message);
    });

    this.#child.stderr.setEncoding("utf8");
    this.#child.stderr.on("data", (chunk: string) => {
      for (const line of chunk.split("\n")) if (line.trim() !== "") this.stderr.push(line);
    });

    this.#exited = new Promise((resolve) => this.#child.on("exit", resolve));
  }

  /** A server already through the `initialize` handshake. */
  static async start(exportDir: string): Promise<StdioServer> {
    const server = new StdioServer(exportDir);
    const initialized = await server.request("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "ascension-tests", version: "0" },
    });
    if (initialized.error) throw new Error(`initialize failed: ${initialized.error.message}`);
    server.notify("notifications/initialized");
    return server;
  }

  /** A server started with no export folder configured, to watch it refuse to run. */
  static unconfigured(): StdioServer {
    return new StdioServer(undefined);
  }

  request(method: string, params: Record<string, unknown> = {}): Promise<Rpc> {
    const id = this.#nextId++;
    const answered = new Promise<Rpc>((resolve) => this.#waiting.set(id, resolve));
    this.#child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    return answered;
  }

  notify(method: string, params: Record<string, unknown> = {}): void {
    this.#child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method, params })}\n`);
  }

  /** The tool payload: compact JSON in a single text block, as `edge/` returns it too. */
  async callTool(name: string, args: Record<string, unknown> = {}) {
    const { result, error } = await this.request("tools/call", { name, arguments: args });
    if (error) throw new Error(`${name} failed: ${error.message}`);
    return {
      isError: result.isError === true,
      payload: JSON.parse(result.content[0].text) as Record<string, any>,
    };
  }

  async readResource(uri: string) {
    const { result, error } = await this.request("resources/read", { uri });
    if (error) throw new Error(`${uri} failed: ${error.message}`);
    return result.contents[0] as { uri: string; mimeType?: string; text: string };
  }

  exited(): Promise<number | null> {
    return this.#exited;
  }

  async stop(): Promise<void> {
    this.#lines.close();
    this.#child.stdin.end();
    this.#child.kill();
    await this.#exited;
  }
}
