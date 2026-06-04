/**
 * Connector account store (SERVER_ARCHITECTURE.md §4.f Phase 5).
 *
 * The single place that reads/writes the encrypted `connector_accounts` rows.
 * Shared by the OAuth callback (which seals + upserts a grant) and the poller
 * (which opens the refresh token to mint an access token). Encryption lives in
 * `crypto.ts`; the plaintext refresh token never leaves this module's callers in
 * stored form.
 *
 * Every read/write is scoped to a `userId` so per-user isolation holds end-to-end
 * (§4.f), matching the GCM AAD binding in `crypto.ts`.
 */
import { randomUUID } from "node:crypto";
import { and, eq, isNull } from "drizzle-orm";
import { db, schema } from "../db";
import { sealToken, openToken, type SealedToken } from "./crypto";
import type { GoogleConnectorSource } from "./google-oauth";

const { connectorAccounts } = schema;

export interface StoredAccount {
  id: string;
  userId: string;
  source: GoogleConnectorSource;
  accountEmail: string | null;
  scope: string | null;
  syncCursor: string | null;
  status: string;
  lastPolledAt: string | null;
  lastError: string | null;
}

/**
 * Upsert (connect / re-connect) a connector account, encrypting the refresh
 * token for `userId` first. Re-connecting the same `(userId, source)` overwrites
 * the prior grant and clears any soft-delete/error so polling resumes.
 */
export function upsertAccount(args: {
  userId: string;
  source: GoogleConnectorSource;
  refreshToken: string;
  accountEmail: string | null;
  scope: string | null;
}): StoredAccount {
  const sealed = sealToken(args.refreshToken, args.userId);
  const now = new Date().toISOString();

  const existing = db
    .select({ id: connectorAccounts.id })
    .from(connectorAccounts)
    .where(
      and(
        eq(connectorAccounts.userId, args.userId),
        eq(connectorAccounts.source, args.source),
      ),
    )
    .get();

  const id = existing?.id ?? randomUUID();

  db.insert(connectorAccounts)
    .values({
      id,
      userId: args.userId,
      source: args.source,
      accountEmail: args.accountEmail,
      refreshTokenCiphertext: sealed.ciphertext,
      refreshTokenIv: sealed.iv,
      refreshTokenTag: sealed.tag,
      scope: args.scope,
      status: "active",
      lastError: null,
      updatedAt: now,
      deletedAt: null,
    })
    .onConflictDoUpdate({
      target: [connectorAccounts.userId, connectorAccounts.source],
      set: {
        accountEmail: args.accountEmail,
        refreshTokenCiphertext: sealed.ciphertext,
        refreshTokenIv: sealed.iv,
        refreshTokenTag: sealed.tag,
        scope: args.scope,
        status: "active",
        lastError: null,
        updatedAt: now,
        deletedAt: null,
      },
    })
    .run();

  return {
    id,
    userId: args.userId,
    source: args.source,
    accountEmail: args.accountEmail,
    scope: args.scope,
    syncCursor: null,
    status: "active",
    lastPolledAt: null,
    lastError: null,
  };
}

/**
 * Every active (non-revoked, non-tombstoned) account for a source, decrypted
 * refresh token in hand. Used by the poller to fan out across users.
 *
 * A row whose ciphertext fails to open (wrong key, tamper, AAD mismatch) is
 * skipped and its `lastError` stamped — never crashes the whole poll.
 */
export function activeAccountsForSource(
  source: GoogleConnectorSource,
): Array<StoredAccount & { refreshToken: string }> {
  const rows = db
    .select()
    .from(connectorAccounts)
    .where(
      and(
        eq(connectorAccounts.source, source),
        eq(connectorAccounts.status, "active"),
        isNull(connectorAccounts.deletedAt),
      ),
    )
    .all();

  const out: Array<StoredAccount & { refreshToken: string }> = [];
  for (const row of rows) {
    const sealed: SealedToken = {
      ciphertext: row.refreshTokenCiphertext,
      iv: row.refreshTokenIv,
      tag: row.refreshTokenTag,
    };
    let refreshToken: string;
    try {
      refreshToken = openToken(sealed, row.userId);
    } catch (err) {
      markAccountError(
        row.userId,
        source,
        `decrypt failed: ${(err as Error).message}`,
      );
      continue;
    }
    out.push({
      id: row.id,
      userId: row.userId,
      source,
      accountEmail: row.accountEmail,
      scope: row.scope,
      syncCursor: row.syncCursor,
      status: row.status,
      lastPolledAt: row.lastPolledAt,
      lastError: row.lastError,
      refreshToken,
    });
  }
  return out;
}

/** Public-facing status for the UI — never exposes any token material. */
export function accountStatus(
  userId: string,
  source: GoogleConnectorSource,
): StoredAccount | null {
  const row = db
    .select()
    .from(connectorAccounts)
    .where(
      and(
        eq(connectorAccounts.userId, userId),
        eq(connectorAccounts.source, source),
        isNull(connectorAccounts.deletedAt),
      ),
    )
    .get();
  if (!row) return null;
  return {
    id: row.id,
    userId: row.userId,
    source: source,
    accountEmail: row.accountEmail,
    scope: row.scope,
    syncCursor: row.syncCursor,
    status: row.status,
    lastPolledAt: row.lastPolledAt,
    lastError: row.lastError,
  };
}

/** All non-tombstoned accounts for a user (UI list). */
export function listAccounts(userId: string): StoredAccount[] {
  const rows = db
    .select()
    .from(connectorAccounts)
    .where(
      and(eq(connectorAccounts.userId, userId), isNull(connectorAccounts.deletedAt)),
    )
    .all();
  return rows.map((row) => ({
    id: row.id,
    userId: row.userId,
    source: row.source as GoogleConnectorSource,
    accountEmail: row.accountEmail,
    scope: row.scope,
    syncCursor: row.syncCursor,
    status: row.status,
    lastPolledAt: row.lastPolledAt,
    lastError: row.lastError,
  }));
}

/** Soft-delete (disconnect) a connector account. Idempotent. */
export function disconnectAccount(
  userId: string,
  source: GoogleConnectorSource,
): boolean {
  const now = new Date().toISOString();
  const res = db
    .update(connectorAccounts)
    .set({ status: "revoked", deletedAt: now, updatedAt: now })
    .where(
      and(
        eq(connectorAccounts.userId, userId),
        eq(connectorAccounts.source, source),
        isNull(connectorAccounts.deletedAt),
      ),
    )
    .run();
  return res.changes > 0;
}

/** Mark a grant revoked (e.g. invalid_grant on refresh) so the poller stops it. */
export function markAccountRevoked(
  userId: string,
  source: GoogleConnectorSource,
  reason: string,
): void {
  const now = new Date().toISOString();
  db.update(connectorAccounts)
    .set({ status: "revoked", lastError: reason, updatedAt: now })
    .where(
      and(eq(connectorAccounts.userId, userId), eq(connectorAccounts.source, source)),
    )
    .run();
}

/** Stamp a transient error for observability without revoking the grant. */
export function markAccountError(
  userId: string,
  source: GoogleConnectorSource,
  reason: string,
): void {
  const now = new Date().toISOString();
  db.update(connectorAccounts)
    .set({ lastError: reason, updatedAt: now })
    .where(
      and(eq(connectorAccounts.userId, userId), eq(connectorAccounts.source, source)),
    )
    .run();
}

/** Stamp a successful poll. */
export function markAccountPolled(
  userId: string,
  source: GoogleConnectorSource,
): void {
  const now = new Date().toISOString();
  db.update(connectorAccounts)
    .set({ lastPolledAt: now, lastError: null, updatedAt: now })
    .where(
      and(eq(connectorAccounts.userId, userId), eq(connectorAccounts.source, source)),
    )
    .run();
}

/**
 * Persist the opaque upstream incremental-sync cursor (Gmail historyId /
 * Calendar syncToken / Drive pageToken) for the real OAuth path. NULL means
 * "no cursor yet — next poll does the bounded initial backfill".
 */
export function setSyncCursor(
  userId: string,
  source: GoogleConnectorSource,
  cursor: string | null,
): void {
  const now = new Date().toISOString();
  db.update(connectorAccounts)
    .set({ syncCursor: cursor, updatedAt: now })
    .where(
      and(eq(connectorAccounts.userId, userId), eq(connectorAccounts.source, source)),
    )
    .run();
}
