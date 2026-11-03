/**
 * Ascension — the cloud bridge (ASC-4, ASC-13).
 *
 * Two streams, in opposite directions (docs/TECH_STACK.md §2.3):
 *   Stream A  observed  phone -> `POST /v1/ingest` -> `rollups`      one-way
 *   Stream B  intent    `documents` + `mutations` <-> phone          two-way
 *
 * Stream A is `POST /v1/ingest` and the Tier-3 read tools. Stream B is the
 * Tier-1 and Tier-2 write tools on `/mcp`, plus the four endpoints the phone
 * drives: the mutation drain and its ack, the documents it also edits, and where
 * it registers for the silent push that wakes it (ASC-13).
 */
import OAuthProvider, {
  type OAuthHelpers,
} from "@cloudflare/workers-oauth-provider";
import type { Env } from "./env";
import { handleAuthorize } from "./http/authorize";
import { handlePushToken } from "./http/device";
import { handleDocument } from "./http/documents";
import { handleIngest } from "./http/ingest";
import { handleMutationAck, handleMutations } from "./http/mutations";
import { handleSuggestions } from "./http/suggestions";
import { json, problem } from "./http/respond";
import { mcpHandler } from "./mcp/server";

/**
 * `mcp:write` is what the Tier-1 and Tier-2 tools need. It is not in
 * `requiredScopes`: a client may hold `mcp:read` alone and still read, and the
 * consent page lists whatever it asked for, so granting write is a decision made
 * once, in the open, with the password.
 */
const SCOPES = ["mcp:read", "mcp:write", "offline_access"];

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
    if (pathname === "/v1/mutations") {
      return handleMutations(request, env);
    }
    if (pathname === "/v1/mutations/ack") {
      return handleMutationAck(request, env);
    }
    if (pathname === "/v1/suggestions") {
      return handleSuggestions(request, env);
    }
    if (pathname === "/v1/device/push-token") {
      return handlePushToken(request, env);
    }
    const document = /^\/v1\/documents\/([^/]+)$/.exec(pathname);
    if (document) {
      return handleDocument(request, env, decodeURIComponent(document[1] as string));
    }
    if (pathname === "/" || pathname === "/health") {
      return json({
        service: "ascension-edge",
        mcp: "/mcp",
        ingest: "/v1/ingest",
        mutations: "/v1/mutations",
        documents: "/v1/documents/<key>",
      });
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
