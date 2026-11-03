/**
 * Ascension — the cloud bridge (ASC-4).
 *
 * Two streams, in opposite directions (docs/TECH_STACK.md §2.3):
 *   Stream A  observed  phone -> `POST /v1/ingest` -> `rollups`      one-way
 *   Stream B  intent    `documents` + `mutations` <-> phone          two-way
 *
 * This ticket owns Stream A's ingest endpoint and the Tier-3 read tools on
 * `/mcp`. Stream B's write tools and endpoints are ASC-13.
 */
import OAuthProvider, {
  type OAuthHelpers,
} from "@cloudflare/workers-oauth-provider";
import type { Env } from "./env";
import { handleAuthorize } from "./http/authorize";
import { handleIngest } from "./http/ingest";
import { json, problem } from "./http/respond";
import { mcpHandler } from "./mcp/server";

/** Read-only today. ASC-13 adds `mcp:write`, which clients obtain by step-up. */
const SCOPES = ["mcp:read", "offline_access"];

type DefaultEnv = Env & { OAUTH_PROVIDER: OAuthHelpers };

/**
 * Everything that is not `/mcp`: the consent page, the phone's ingest endpoint,
 * and a status page. The phone authenticates with its own device token, never
 * with an OAuth grant, so ingest sits here rather than behind `apiRoute`.
 */
const defaultHandler: ExportedHandler<DefaultEnv> = {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);

    if (pathname === "/authorize") {
      return handleAuthorize(request, env, env.OAUTH_PROVIDER);
    }
    if (pathname === "/v1/ingest") {
      return handleIngest(request, env);
    }
    if (pathname === "/" || pathname === "/health") {
      return json({ service: "ascension-edge", mcp: "/mcp", ingest: "/v1/ingest" });
    }
    return problem(404, "not_found");
  },
};

/**
 * OAuth 2.1 + PKCE, which is what Claude and Muse custom connectors expect — a
 * bearer header is not offered in the connector UI, and an unguessable URL is
 * not acceptable for health data (docs/TECH_STACK.md §2.2).
 *
 * Built on first request rather than at module scope, because the resource
 * identifier is derived from `PUBLIC_ORIGIN`, and bindings only exist per
 * request.
 */
function buildProvider(env: Env): OAuthProvider<Env> {
  const origin = new URL(env.PUBLIC_ORIGIN).origin;
  return new OAuthProvider<Env>({
    apiRoute: "/mcp",
    apiHandler: {
      fetch: (request: Request, apiEnv: Env, ctx: ExecutionContext) =>
        mcpHandler(apiEnv)(request, apiEnv, ctx),
    },
    defaultHandler: defaultHandler as ExportedHandler<Env>,
    authorizeEndpoint: "/authorize",
    tokenEndpoint: "/oauth/token",
    clientRegistrationEndpoint: "/oauth/register",
    scopesSupported: SCOPES,
    requiredScopes: ["mcp:read"],
    resourceMetadata: {
      resource: `${origin}/mcp`,
      authorization_servers: [origin],
      resource_name: "Ascension",
    },
  });
}

const providers = new Map<string, OAuthProvider<Env>>();

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    let provider = providers.get(env.PUBLIC_ORIGIN);
    if (!provider) {
      provider = buildProvider(env);
      providers.set(env.PUBLIC_ORIGIN, provider);
    }
    return provider.fetch(request, env, ctx);
  },
} satisfies ExportedHandler<Env>;
