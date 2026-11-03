/**
 * The silent APNs wake (docs/TECH_STACK.md §2.4).
 *
 * A Tier-2 mutation sits in D1 until the phone applies it, so the Worker sends a
 * `content-available` push and the phone drains in seconds. **Correctness never
 * depends on the push arriving**: foreground and `BGAppRefreshTask` drain the
 * same log, so every failure here is reported and swallowed, never raised.
 *
 * The payload is exactly what `SilentPushHandler` recognises. A push carrying the
 * `aps` flag but no known `reason` is ignored by the device rather than guessed
 * at, so the `ascension.reason` key is not optional.
 *
 * Unconfigured is a normal state: `wrangler dev` has no signing key, and this
 * then reports `not_configured` and does nothing.
 */
import type { Env } from "../env";

export const PUSH_REASON = "mutations";

export type PushResult = {
  sent: number;
  failed: number;
  /** Why nothing was sent, when nothing was. */
  skipped?: "not_configured" | "no_registered_devices";
};

type TokenRow = { token: string; environment: string };

const HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
} as const;

/** Apple allows an hour; refreshed well inside it, per isolate. */
const TOKEN_TTL_MS = 45 * 60 * 1000;

type Config = {
  keyId: string;
  teamId: string;
  topic: string;
  privateKey: string;
};

function configOf(env: Env): Config | null {
  const { APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC, APNS_PRIVATE_KEY } = env;
  if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_TOPIC || !APNS_PRIVATE_KEY) return null;
  return {
    keyId: APNS_KEY_ID,
    teamId: APNS_TEAM_ID,
    topic: APNS_TOPIC,
    privateKey: APNS_PRIVATE_KEY,
  };
}

function base64url(bytes: ArrayBuffer | Uint8Array): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (const byte of view) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** The PEM body of a `.p8`, which holds a PKCS#8 private key. */
function pkcs8(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  return Uint8Array.from(raw, (char) => char.charCodeAt(0));
}

let cached: { jwt: string; issuedAt: number; keyId: string } | null = null;

async function providerToken(config: Config, now: number): Promise<string> {
  if (cached && cached.keyId === config.keyId && now - cached.issuedAt < TOKEN_TTL_MS) {
    return cached.jwt;
  }
  const encoder = new TextEncoder();
  const header = base64url(
    encoder.encode(JSON.stringify({ alg: "ES256", kid: config.keyId })),
  );
  const payload = base64url(
    encoder.encode(JSON.stringify({ iss: config.teamId, iat: Math.floor(now / 1000) })),
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8(config.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(`${header}.${payload}`),
  );
  const jwt = `${header}.${payload}.${base64url(signature)}`;
  cached = { jwt, issuedAt: now, keyId: config.keyId };
  return jwt;
}

/**
 * Wake every registered device. Returns what happened; never throws.
 *
 * A token APNs reports as dead is removed: it can never deliver again, and the
 * row is an APNs identifier, not health data.
 */
export async function wakeDevices(env: Env): Promise<PushResult> {
  const config = configOf(env);
  if (!config) return { sent: 0, failed: 0, skipped: "not_configured" };

  const { results } = await env.DB.prepare(
    `SELECT token, environment FROM push_tokens`,
  ).all<TokenRow>();
  if (results.length === 0) {
    return { sent: 0, failed: 0, skipped: "no_registered_devices" };
  }

  const body = JSON.stringify({
    aps: { "content-available": 1 },
    ascension: { reason: PUSH_REASON },
  });

  let jwt: string;
  try {
    jwt = await providerToken(config, Date.now());
  } catch {
    return { sent: 0, failed: results.length };
  }

  let sent = 0;
  let failed = 0;
  const dead: string[] = [];

  for (const row of results) {
    const host = HOSTS[row.environment === "sandbox" ? "sandbox" : "production"];
    try {
      const response = await fetch(`${host}/3/device/${row.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": config.topic,
          "apns-push-type": "background",
          // A background push must be priority 5; Apple rejects 10.
          "apns-priority": "5",
          "content-type": "application/json",
        },
        body,
      });
      if (response.ok) {
        sent += 1;
        continue;
      }
      failed += 1;
      const reason = response.status === 400 ? await response.text() : "";
      if (response.status === 410 || reason.includes("BadDeviceToken")) {
        dead.push(row.token);
      }
    } catch {
      failed += 1;
    }
  }

  for (const token of dead) {
    await env.DB.prepare(`DELETE FROM push_tokens WHERE token = ?1`).bind(token).run();
  }

  return { sent, failed };
}
