export type Env = Omit<Cloudflare.Env, "PUBLIC_ORIGIN"> & {
  /** Public https origin this Worker answers on. Configuration, not a secret. */
  PUBLIC_ORIGIN: string;
  /** Bearer token the phone presents to `POST /v1/ingest`. `wrangler secret`. */
  DEVICE_TOKEN: string;
  /** The single registered user's password, checked on `/authorize`. `wrangler secret`. */
  OWNER_PASSWORD: string;

  /**
   * APNs, for the silent push that wakes the phone when a Tier-2 mutation is
   * queued (docs/TECH_STACK.md §2.4). All four go in `wrangler secret` -- the
   * `.p8` key most of all -- and all four are optional: unset means no push,
   * which is the normal state under `wrangler dev`. Correctness never depends on
   * the push, so an unconfigured Worker is a slower Worker, not a broken one.
   */
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  /** The app's bundle identifier, which is the APNs topic. */
  APNS_TOPIC?: string;
  /** The PKCS#8 PEM body of the `.p8` signing key. */
  APNS_PRIVATE_KEY?: string;
};
