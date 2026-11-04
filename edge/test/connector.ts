/**
 * A real MCP client for the acceptance run (ASC-18).
 *
 * Every other suite in this directory reaches past the front door: `helpers.ts`
 * calls a tool's `run` directly, and `mcp.test.ts` drives `mcpHandler` with the
 * auth already granted. Neither would notice if `/mcp` stopped being reachable
 * the way Muse reaches it.
 *
 * This one goes in through `SELF.fetch`, which is the deployed Worker's own
 * entrypoint: dynamic client registration, the consent page with the owner's
 * password, PKCE, a bearer token, and then JSON-RPC over Streamable HTTP. If any
 * link in that chain breaks, the acceptance suite stops before it asks a single
 * question.
 */
import { SELF } from "cloudflare:test";
import { expect } from "vitest";

const ORIGIN = "http://localhost:8787";
/** Loopback, like a desktop connector: the consent page says so, and allows it. */
const REDIRECT_URI = "http://127.0.0.1:41234/callback";

const base64url = (bytes: ArrayBuffer | Uint8Array) =>
  btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

async function challenge(verifier: string): Promise<string> {
  return base64url(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)));
}

/** Everything `Set-Cookie` asked for, folded into one `Cookie` header. */
function cookiesFrom(response: Response, existing: string): string {
  const jar = new Map<string, string>(
    existing
      .split("; ")
      .filter(Boolean)
      .map((pair) => [pair.slice(0, pair.indexOf("=")), pair.slice(pair.indexOf("=") + 1)]),
  );
  for (const header of response.headers.getSetCookie?.() ?? []) {
    const [pair] = header.split(";");
    if (!pair) continue;
    const index = pair.indexOf("=");
    if (index > 0) jar.set(pair.slice(0, index).trim(), pair.slice(index + 1));
  }
  return [...jar].map(([name, value]) => `${name}=${value}`).join("; ");
}

export type McpResult = {
  /** The decoded tool payload — the compact JSON in the single text block. */
  body: Record<string, any>;
  isError: boolean;
};

export class Connector {
  private constructor(
    readonly accessToken: string,
    readonly scopes: string[],
  ) {}

  /**
   * The whole OAuth 2.1 + PKCE dance a custom connector performs, with no
   * shortcut through an internal helper. Returns a client holding a real token.
   */
  static async connect(
    password = "test-owner-password",
    scope = "mcp:read mcp:write",
  ): Promise<Connector> {
    const registration = await SELF.fetch(`${ORIGIN}/oauth/register`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        client_name: "Acceptance connector",
        redirect_uris: [REDIRECT_URI],
        token_endpoint_auth_method: "none",
        grant_types: ["authorization_code", "refresh_token"],
        response_types: ["code"],
      }),
    });
    expect(registration.status, await registration.clone().text()).toBeLessThan(300);
    const client = (await registration.json()) as { client_id: string };

    const verifier = base64url(crypto.getRandomValues(new Uint8Array(32)));
    const query = new URLSearchParams({
      response_type: "code",
      client_id: client.client_id,
      redirect_uri: REDIRECT_URI,
      scope,
      state: "acceptance",
      code_challenge: await challenge(verifier),
      code_challenge_method: "S256",
    });

    const consent = await SELF.fetch(`${ORIGIN}/authorize?${query}`);
    expect(consent.status, await consent.clone().text()).toBe(200);
    const page = await consent.text();
    const cookies = cookiesFrom(consent, "");
    const handle = /name="handle" value="([^"]+)"/.exec(page)?.[1];
    expect(handle, "the consent page must carry a handle to approve").toBeTruthy();

    const form = new URLSearchParams();
    form.set("handle", handle as string);
    for (const item of scope.split(" ")) form.append("scope", item);
    form.set("password", password);
    form.set("decision", "approve");

    const approved = await SELF.fetch(`${ORIGIN}/authorize`, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        ...(cookies ? { Cookie: cookies } : {}),
      },
      body: form,
      redirect: "manual",
    });
    expect(approved.status, await approved.clone().text()).toBe(302);
    const redirect = new URL(approved.headers.get("Location") as string);
    const code = redirect.searchParams.get("code");
    expect(redirect.searchParams.get("error")).toBeNull();
    expect(code, "approving the consent page must hand back a code").toBeTruthy();

    const token = await SELF.fetch(`${ORIGIN}/oauth/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        code: code as string,
        redirect_uri: REDIRECT_URI,
        client_id: client.client_id,
        code_verifier: verifier,
      }),
    });
    expect(token.status, await token.clone().text()).toBe(200);
    const granted = (await token.json()) as { access_token: string; scope?: string };
    expect(granted.access_token).toBeTruthy();
    return new Connector(granted.access_token, (granted.scope ?? scope).split(" "));
  }

  /** One JSON-RPC round trip over Streamable HTTP, with the bearer token. */
  async rpc(
    method: string,
    params: Record<string, unknown> = {},
  ): Promise<{ status: number; payload: Record<string, any> }> {
    const response = await SELF.fetch(`${ORIGIN}/mcp`, {
      method: "POST",
      headers: {
        // workerd does not derive Host from the URL for a constructed Request,
        // and the handler validates it against the localhost allowlist. The
        // same line is in `mcp.test.ts`; it is the harness, not the Worker.
        Host: "localhost:8787",
        Authorization: `Bearer ${this.accessToken}`,
        "Content-Type": "application/json",
        Accept: "application/json, text/event-stream",
      },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    });
    const text = await response.text();
    const payload = response.headers.get("Content-Type")?.includes("text/event-stream")
      ? JSON.parse(
          text
            .split("\n")
            .filter((line) => line.startsWith("data:"))
            .map((line) => line.slice(5).trim())
            .join(""),
        )
      : JSON.parse(text);
    return { status: response.status, payload };
  }

  /** `tools/call`, unwrapped to the tool's own JSON. Never throws on a tool error. */
  async call(name: string, args: Record<string, unknown> = {}): Promise<McpResult> {
    const { payload } = await this.rpc("tools/call", { name, arguments: args });
    expect(payload.error, `${name}: ${JSON.stringify(payload.error)}`).toBeUndefined();
    const text = payload.result?.content?.[0]?.text;
    expect(typeof text, `${name} must answer with a text block`).toBe("string");
    return { body: JSON.parse(text), isError: payload.result.isError === true };
  }

  /** `tools/call` that must succeed. */
  async ok(name: string, args: Record<string, unknown> = {}): Promise<Record<string, any>> {
    const result = await this.call(name, args);
    expect(result.isError, `${name} was rejected: ${JSON.stringify(result.body)}`).toBe(false);
    expect(result.body.schemaVersion).toBe(1);
    return result.body;
  }

  /** `tools/call` that must be rejected, handing back the error envelope. */
  async rejected(
    name: string,
    args: Record<string, unknown> = {},
  ): Promise<Record<string, any>> {
    const result = await this.call(name, args);
    expect(result.isError, `${name} was expected to be rejected, and was not`).toBe(true);
    return result.body;
  }
}

export { ORIGIN };
