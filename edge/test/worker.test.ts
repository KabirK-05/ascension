import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

describe("the Worker's routes", () => {
  it("serves a status page with no secrets in it", async () => {
    const response = await SELF.fetch("http://localhost:8787/");
    expect(response.status).toBe(200);
    const body = (await response.json()) as Record<string, unknown>;
    expect(body).toMatchObject({
      schemaVersion: 1,
      service: "ascension-edge",
      mcp: "/mcp",
    });
    expect(JSON.stringify(body)).not.toContain("test-device-token");
    expect(JSON.stringify(body)).not.toContain("test-owner-password");
  });

  it("guards /mcp behind OAuth and points at the metadata", async () => {
    const response = await SELF.fetch("http://localhost:8787/mcp", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list" }),
    });
    expect(response.status).toBe(401);
    expect(response.headers.get("WWW-Authenticate")).toContain("resource_metadata");
  });

  it("publishes RFC 9728 protected resource metadata", async () => {
    const response = await SELF.fetch(
      "http://localhost:8787/.well-known/oauth-protected-resource/mcp",
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as Record<string, any>;
    expect(body.resource).toBe("http://localhost:8787/mcp");
    expect(body.scopes_supported).toContain("mcp:read");
  });

  it("publishes authorization server metadata with PKCE", async () => {
    const response = await SELF.fetch(
      "http://localhost:8787/.well-known/oauth-authorization-server",
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as Record<string, any>;
    expect(body.code_challenge_methods_supported).toContain("S256");
    expect(body.registration_endpoint).toBe("http://localhost:8787/oauth/register");
  });

  it("404s an unknown path", async () => {
    const response = await SELF.fetch("http://localhost:8787/nope");
    expect(response.status).toBe(404);
  });
});
