/**
 * OAuth `state` signing (SERVER_ARCHITECTURE.md §4.f Phase 5).
 *
 * The Google redirect lands on the UNAUTHENTICATED callback route (it's a browser
 * redirect from Google, so it can't carry the device bearer token). The signed
 * `state` is therefore BOTH the CSRF defense and the identity carrier: it binds
 * the `userId` + `source` that initiated the flow, signed with HMAC-SHA256 keyed
 * by `AUTH_TOKEN_PEPPER` (reusing the existing required secret — no new secret),
 * and expires after 10 minutes so a leaked URL is not a durable credential.
 *
 * Format: `base64url(JSON{userId,source,nonce,exp}).base64url(hmac)`.
 */
import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { getAuthPepper } from "./auth";

const STATE_TTL_MS = 10 * 60 * 1000;

type ConnectorOAuthSource = "gmail" | "calendar" | "drive";

interface StatePayload {
  userId: string;
  source: ConnectorOAuthSource;
  nonce: string;
  exp: number;
}

function b64url(buf: Buffer | string): string {
  return Buffer.from(buf).toString("base64url");
}

function hmac(data: string): string {
  return createHmac("sha256", getAuthPepper()).update(data).digest("base64url");
}

/** Sign a fresh state token for `{userId, source}`, valid for 10 minutes. */
export function signState(args: { userId: string; source: ConnectorOAuthSource }): string {
  const payload: StatePayload = {
    userId: args.userId,
    source: args.source,
    nonce: randomBytes(12).toString("base64url"),
    exp: Date.now() + STATE_TTL_MS,
  };
  const body = b64url(JSON.stringify(payload));
  return `${body}.${hmac(body)}`;
}

/**
 * Verify + decode a state token. Returns the `{userId, source}` it carries, or
 * null if the signature is invalid, the format is malformed, or it has expired.
 */
export function verifyState(
  state: string | null | undefined,
): { userId: string; source: ConnectorOAuthSource } | null {
  if (!state) return null;
  const dot = state.lastIndexOf(".");
  if (dot <= 0) return null;
  const body = state.slice(0, dot);
  const sig = state.slice(dot + 1);

  const expected = hmac(body);
  // Constant-time compare; lengths must match for timingSafeEqual.
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;

  let payload: StatePayload;
  try {
    payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) as StatePayload;
  } catch {
    return null;
  }
  if (
    !payload ||
    typeof payload.userId !== "string" ||
    !["gmail", "calendar", "drive"].includes(payload.source) ||
    typeof payload.exp !== "number"
  ) {
    return null;
  }
  if (Date.now() > payload.exp) return null;
  return { userId: payload.userId, source: payload.source };
}
