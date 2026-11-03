export type Env = Omit<Cloudflare.Env, "PUBLIC_ORIGIN"> & {
  /** Public https origin this Worker answers on. Configuration, not a secret. */
  PUBLIC_ORIGIN: string;
  /** Bearer token the phone presents to `POST /v1/ingest`. `wrangler secret`. */
  DEVICE_TOKEN: string;
  /** The single registered user's password, checked on `/authorize`. `wrangler secret`. */
  OWNER_PASSWORD: string;
};
