/**
 * Per-user refresh-token encryption (SERVER_ARCHITECTURE.md §4.f).
 *
 *   "Connector OAuth tokens — encrypt refresh tokens with a key from
 *    /etc/atlas/atlas.env (AES-GCM / libsodium secretbox) before insert, scoped
 *    per userId; the encryption key is never in the DB; replicate only
 *    ciphertext. These grant full inbox/Drive access — higher-value than the
 *    app's own token."
 *
 * We use AES-256-GCM from Node's built-in `crypto` (no new dependency, so it
 * stays $0 and works identically in the worker and the Next.js process). The
 * key lives ONLY in `CONNECTOR_ENCRYPTION_KEY` in /etc/atlas/atlas.env and is
 * never written to the DB — only the ciphertext + per-message IV + auth tag are
 * persisted, so a DB/backup leak alone yields no usable refresh token.
 *
 * Per-user scoping is enforced cryptographically AND at the row level: the
 * owning `userId` is bound into the GCM **additional authenticated data (AAD)**,
 * so a ciphertext copied from user A's row into user B's row fails decryption
 * (the tag won't verify against B's userId). Combined with the `(userId, source)`
 * row key, a token can only ever be decrypted in the exact context it was sealed.
 */
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from "node:crypto";

const ALGORITHM = "aes-256-gcm";
const IV_BYTES = 12; // 96-bit nonce, the GCM standard
const KEY_BYTES = 32; // AES-256

/**
 * Derive the 32-byte AES key from `CONNECTOR_ENCRYPTION_KEY`. It is a hard error
 * to encrypt/decrypt without it — a missing key is a launch blocker for real
 * connectors, not a dev convenience, so we fail loudly. Read lazily so importing
 * this module never crashes a process that touches only the fixture/demo path.
 *
 * The env value may be either base64 / hex of exactly 32 bytes (preferred — a
 * raw 256-bit key), or an arbitrary passphrase ≥32 chars which we SHA-256 into a
 * 32-byte key. We never silently accept a short/weak passphrase.
 */
function getKey(): Buffer {
  const raw = process.env.CONNECTOR_ENCRYPTION_KEY;
  if (!raw || raw.length < 32) {
    throw new Error(
      "CONNECTOR_ENCRYPTION_KEY is missing or too short (need a 32-byte key as " +
        "base64/hex, or a passphrase ≥32 chars). Set it in /etc/atlas/atlas.env; " +
        "the connector OAuth store refuses to run without it.",
    );
  }

  // Try base64, then hex — accept only if it decodes to exactly 32 bytes.
  for (const enc of ["base64", "hex"] as const) {
    try {
      const buf = Buffer.from(raw, enc);
      if (buf.length === KEY_BYTES) return buf;
    } catch {
      // not this encoding — fall through
    }
  }
  // Otherwise treat it as a passphrase and stretch with SHA-256 to 32 bytes.
  return createHash("sha256").update(raw, "utf8").digest();
}

/**
 * A sealed token, ready to persist. The key is NOT part of this — it lives only
 * in env. We store the IV + auth tag alongside the ciphertext so each value is
 * self-describing for decryption.
 */
export interface SealedToken {
  /** base64 ciphertext. */
  ciphertext: string;
  /** base64 96-bit IV (unique per message). */
  iv: string;
  /** base64 128-bit GCM auth tag. */
  tag: string;
}

/**
 * Encrypt a refresh token for a given owner. `userId` is bound as AAD so the
 * ciphertext can only be decrypted in that user's context.
 */
export function sealToken(plaintext: string, userId: string): SealedToken {
  const key = getKey();
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv(ALGORITHM, key, iv);
  cipher.setAAD(Buffer.from(userId, "utf8"));
  const ct = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return {
    ciphertext: ct.toString("base64"),
    iv: iv.toString("base64"),
    tag: tag.toString("base64"),
  };
}

/**
 * Decrypt a sealed refresh token. Throws if the auth tag doesn't verify — which
 * happens on tamper, key rotation, OR a row read under the wrong `userId` (the
 * AAD binding). Callers should treat a throw as "re-authentication required".
 */
export function openToken(sealed: SealedToken, userId: string): string {
  const key = getKey();
  const decipher = createDecipheriv(
    ALGORITHM,
    key,
    Buffer.from(sealed.iv, "base64"),
  );
  decipher.setAAD(Buffer.from(userId, "utf8"));
  decipher.setAuthTag(Buffer.from(sealed.tag, "base64"));
  const pt = Buffer.concat([
    decipher.update(Buffer.from(sealed.ciphertext, "base64")),
    decipher.final(),
  ]);
  return pt.toString("utf8");
}

/**
 * True iff a usable encryption key is configured. Lets the connector layer
 * decide demo-vs-real without throwing: no key (or fixtures flag) ⇒ demo mode.
 */
export function hasEncryptionKey(): boolean {
  const raw = process.env.CONNECTOR_ENCRYPTION_KEY;
  return !!raw && raw.length >= 32;
}
