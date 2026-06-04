/**
 * Device-token auth (SERVER_ARCHITECTURE.md §4.f, §4.d).
 *
 * The single source of truth for how a presented bearer token maps to a
 * `userId`. Shared by `createContext` (src/server/trpc.ts) and the operator
 * token seeder (src/db/seed-token.ts) so the hashing scheme can never drift
 * between mint-time and verify-time.
 *
 * SECURITY model:
 *  - We store ONLY `sha256(token + AUTH_TOKEN_PEPPER)` (lowercase hex), never the
 *    plaintext. The pepper lives exclusively in /etc/atlas/atlas.env (§4.f) and
 *    is never in the DB, so a DB/backup leak alone yields no usable credential.
 *  - There is NO `DEFAULT_USER_ID` fail-open. Absent / unknown / revoked tokens
 *    resolve to `null`, which callers turn into a 401.
 */
import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { eq } from "drizzle-orm";
import { db } from "@/db/client";
import { deviceTokens } from "@/db/schema";

/**
 * The pepper mixed into every token hash. It is a hard error to mint or verify
 * tokens without it — a missing pepper would silently hash to a guessable space
 * and is a launch blocker, not a dev convenience. Read lazily so importing this
 * module (e.g. for `hashToken` in tests) doesn't crash a process that never
 * touches auth.
 */
export function getAuthPepper(): string {
  const pepper = process.env.AUTH_TOKEN_PEPPER;
  if (!pepper || pepper.length < 16) {
    throw new Error(
      "AUTH_TOKEN_PEPPER is missing or too short (need ≥16 chars). " +
        "Set it in /etc/atlas/atlas.env; device-token auth refuses to run without it.",
    );
  }
  return pepper;
}

/** sha256(token + pepper) → lowercase hex. The only place hashing happens. */
export function hashToken(token: string): string {
  return createHash("sha256")
    .update(token + getAuthPepper())
    .digest("hex");
}

/**
 * Mint a fresh, URL-safe device token. 32 random bytes (256 bits) base64url —
 * far beyond brute-force. Used only by the seeder; clients never mint.
 */
export function generateToken(): string {
  return randomBytes(32).toString("base64url");
}

/** Pull a bearer token out of an `Authorization` header. Returns null if absent/malformed. */
export function extractBearer(header: string | null | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  if (!match) return null;
  const token = match[1].trim();
  return token.length > 0 ? token : null;
}

/** Constant-time hex compare to avoid leaking the hash via timing. */
function hexEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  try {
    return timingSafeEqual(Buffer.from(a, "hex"), Buffer.from(b, "hex"));
  } catch {
    return false;
  }
}

/**
 * Resolve a presented bearer token to a `userId`, or `null` if it is
 * absent / unknown / revoked. On a successful resolve, bump `lastSeenAt`.
 *
 * NO fail-open: a `null` return is the caller's cue to throw UNAUTHORIZED.
 */
export function resolveUserIdFromToken(token: string | null): string | null {
  if (!token) return null;

  const presentedHash = hashToken(token);
  const row = db
    .select({
      userId: deviceTokens.userId,
      tokenHash: deviceTokens.tokenHash,
      revokedAt: deviceTokens.revokedAt,
    })
    .from(deviceTokens)
    .where(eq(deviceTokens.tokenHash, presentedHash))
    .get();

  if (!row) return null;
  // Defense-in-depth: the index already guarantees an exact match, but compare
  // in constant time anyway so this path is uniform regardless of the stored value.
  if (!hexEquals(row.tokenHash, presentedHash)) return null;
  if (row.revokedAt) return null;

  // Touch lastSeenAt for liveness/observability. Best-effort: a write failure
  // here must not deny an otherwise-valid request.
  try {
    db.update(deviceTokens)
      .set({ lastSeenAt: new Date().toISOString() })
      .where(eq(deviceTokens.tokenHash, presentedHash))
      .run();
  } catch {
    // ignore — auth already succeeded
  }

  return row.userId;
}
