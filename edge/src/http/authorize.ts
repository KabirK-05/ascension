/**
 * `/authorize` — the consent page. Single registered user: one password, no
 * accounts, no profile. docs/TECH_STACK.md §2.6 keeps PII out of this Worker,
 * so the granted identity is the constant `owner` and nothing else.
 *
 * The page shows what the MCP authorization spec requires: who is asking, the
 * scopes, where the tokens will be sent, and a warning when that is a local
 * process. Everything the client supplied is escaped — it chose those strings.
 */
import type {
  ConsentDescription,
  OAuthHelpers,
} from "@cloudflare/workers-oauth-provider";
import {
  AuthorizationError,
  CimdFetchError,
} from "@cloudflare/workers-oauth-provider";
import type { Env } from "../env";
import { secretMatches } from "./respond";

/** The only user. Must not contain `:` — the provider namespaces on it. */
export const OWNER_USER_ID = "owner";

const escape = (value: string) =>
  value.replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);

const style = `<style>
  :root { color-scheme: dark light }
  body { font: 16px/1.5 ui-sans-serif, system-ui, sans-serif; max-width: 34rem;
         margin: 4rem auto; padding: 0 1.25rem }
  h1 { font-size: 1.25rem; font-weight: 600 }
  dt { font-size: .8125rem; opacity: .6; margin-top: .75rem }
  dd { margin: 0; font-variant-numeric: tabular-nums }
  form { margin-top: 2rem; display: grid; gap: .75rem }
  input { font: inherit; padding: .5rem; width: 100% }
  .row { display: flex; gap: .75rem }
  button { font: inherit; padding: .5rem 1rem }
  .warn { border-left: 3px solid currentColor; padding-left: .75rem }
  .error { font-weight: 600 }
</style>`;

function html(body: string, status = 200): Response {
  return new Response(`<!doctype html><meta charset="utf-8">${body}`, {
    status,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

/**
 * What this grant actually permits, in the owner's words rather than in scope
 * slugs. `mcp:write` lets a client change targets, the program and the flags and
 * queue logs for the phone, so the page has to say so before the password is
 * typed -- the scope list alone is not consent anyone can read.
 */
function permission(scopes: string[]): string {
  return scopes.includes("mcp:write")
    ? "read <strong>and change</strong> your Ascension data"
    : "read your Ascension data";
}

function consentPage(
  details: ConsentDescription,
  handle: string,
  error?: string,
): string {
  const name = escape(details.clientName);
  return `<title>Authorize ${name}</title>${style}
<h1>Allow ${name} to ${permission(details.scope)}?</h1>
${
  details.scope.includes("mcp:write")
    ? `<p class="warn">It will be able to set your calorie and macro targets, rewrite your training program, change feature flags, and queue meals, water, check-ins and top sets for your phone to write to Apple Health. It cannot delete anything, and every change is listed in Settings → Changes.</p>`
    : ""
}
<dl>
  <dt>Publisher</dt>
  <dd>${
    details.clientDomain
      ? escape(details.clientDomain)
      : "unverified — this app registered itself"
  }</dd>
  <dt>Tokens sent to</dt>
  <dd>${escape(details.redirectHost)}</dd>
  <dt>Scopes</dt>
  <dd>${details.scope.map((scope) => escape(scope)).join(", ") || "none"}</dd>
</dl>
${
  details.redirectIsLoopback
    ? `<p class="warn">This sends access to an app on your own computer. Continue only if you just started signing in from it.</p>`
    : ""
}
<form method="post">
  <input type="hidden" name="handle" value="${escape(handle)}">
  ${details.scope
    .map(
      (scope) =>
        `<input type="hidden" name="scope" value="${escape(scope)}">`,
    )
    .join("")}
  ${error ? `<p class="error">${escape(error)}</p>` : ""}
  <label>Password
    <input type="password" name="password" autocomplete="current-password" autofocus required>
  </label>
  <div class="row">
    <button name="decision" value="approve">Allow</button>
    <button name="decision" value="deny">Deny</button>
  </div>
</form>`;
}

/** A retry that does not consume the handle, so a typo is not a dead end. */
function retryPage(handle: string, scope: string[], error: string): string {
  return `<title>Authorize</title>${style}
<h1>Allow a client to ${permission(scope)}?</h1>
<form method="post">
  <input type="hidden" name="handle" value="${escape(handle)}">
  ${scope
    .map((item) => `<input type="hidden" name="scope" value="${escape(item)}">`)
    .join("")}
  <p class="error">${escape(error)}</p>
  <label>Password
    <input type="password" name="password" autocomplete="current-password" autofocus required>
  </label>
  <div class="row">
    <button name="decision" value="approve">Allow</button>
    <button name="decision" value="deny">Deny</button>
  </div>
</form>`;
}

export async function handleAuthorize(
  request: Request,
  env: Env,
  oauth: OAuthHelpers,
): Promise<Response> {
  try {
    if (request.method === "GET") {
      const authRequest = await oauth.parseAuthRequest(request);
      // describeConsent first: a failed lookup then leaves nothing behind.
      const details = await oauth.describeConsent(authRequest);
      const consent = await oauth.beginConsent(authRequest);
      consent.headers.set("Content-Type", "text/html; charset=utf-8");
      return new Response(
        `<!doctype html><meta charset="utf-8">${consentPage(details, consent.handle)}`,
        { headers: consent.headers },
      );
    }

    if (request.method !== "POST") {
      return html("<p>Method not allowed.</p>", 405);
    }

    const form = await request.formData();
    const handle = String(form.get("handle") ?? "");
    const scope = form.getAll("scope").map(String);

    if (form.get("decision") !== "approve") {
      const denied = await oauth.denyConsent(request, handle);
      return new Response(null, { status: 302, headers: denied.headers });
    }

    if (!(await secretMatches(String(form.get("password") ?? ""), env.OWNER_PASSWORD))) {
      return html(retryPage(handle, scope, "That password is not right."), 401);
    }

    const approved = await oauth.approveConsent(request, handle, { scope });
    const { redirectTo } = await oauth.completeAuthorization({
      request: approved.request,
      userId: OWNER_USER_ID,
      metadata: {},
      scope: approved.request.scope,
      props: { userId: OWNER_USER_ID },
    });
    approved.headers.set("Location", redirectTo);
    return new Response(null, { status: 302, headers: approved.headers });
  } catch (error) {
    if (error instanceof AuthorizationError && error.redirectTo) {
      return Response.redirect(error.redirectTo, 302);
    }
    if (error instanceof AuthorizationError || error instanceof CimdFetchError) {
      const message =
        error instanceof AuthorizationError
          ? error.description
          : "This app could not be verified.";
      return html(`${style}<p class="error">${escape(message)}</p>`, 400);
    }
    throw error;
  }
}
