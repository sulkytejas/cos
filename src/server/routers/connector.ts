/**
 * Connector OAuth router (SERVER_ARCHITECTURE.md §4.f Phase 5).
 *
 * Drives the Google OAuth consent flow for the thin iOS client and exposes the
 * per-user connection state. The refresh token returned by the exchange is
 * encrypted (AES-256-GCM, key from env, bound to `ctx.userId` as AAD) before it
 * touches the DB — only ciphertext + IV + tag are stored (§4.f).
 *
 * Flow:
 *   1. iOS calls `connector.authUrl({ source })` → gets a Google consent URL with
 *      a signed `state` (HMAC over userId|source|nonce|exp, pepper-keyed) and
 *      opens it in a browser/ASWebAuthenticationSession.
 *   2. Google redirects to `GOOGLE_OAUTH_REDIRECT_URI` (the unauthenticated
 *      `/api/connectors/callback` route), which verifies the state, exchanges the
 *      code, encrypts + upserts the grant, and shows a "connected — return to the
 *      app" page.
 *   3. iOS polls `connector.list` / `connector.status` to reflect the connection.
 *
 * The callback can't carry the bearer token (it's a browser redirect from
 * Google), so the SIGNED STATE is what re-establishes the userId — it is the CSRF
 * defense and the identity carrier in one. State is short-lived (10 min).
 */
import { z } from "zod";
import { TRPCError } from "@trpc/server";
import { and, eq, isNull } from "drizzle-orm";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import { connectorAccounts } from "@/db/schema";
import {
  buildAuthUrl,
  hasGoogleOAuthConfig,
  type GoogleConnectorSource,
} from "../../../worker/src/connectors/google-oauth";
import { signState } from "../connector-state";

/** The three OAuth-backed sources (calendar also has the EventKit push path). */
const connectorSourceEnum = z.enum(["gmail", "calendar", "drive"]);

export const connectorRouter = router({
  /**
   * Build a Google consent URL for one source. Returns `{ url }` for the client
   * to open. Fails fast if OAuth isn't configured on the server (deploy-time
   * config), so the client shows a clear "connectors not configured" state
   * instead of a broken redirect.
   */
  authUrl: protectedProcedure
    .input(z.object({ source: connectorSourceEnum }))
    .mutation(({ input, ctx }) => {
      if (!hasGoogleOAuthConfig()) {
        throw new TRPCError({
          code: "PRECONDITION_FAILED",
          message:
            "Google OAuth is not configured on the server. Set GOOGLE_OAUTH_CLIENT_ID / " +
            "GOOGLE_OAUTH_CLIENT_SECRET / GOOGLE_OAUTH_REDIRECT_URI in /etc/atlas/atlas.env.",
        });
      }
      const source = input.source as GoogleConnectorSource;
      const state = signState({ userId: ctx.userId, source });
      return { url: buildAuthUrl(source, state) };
    }),

  /** All non-tombstoned connector accounts for the caller (UI list). */
  list: protectedProcedure.query(({ ctx }) => {
    const rows = db
      .select({
        source: connectorAccounts.source,
        accountEmail: connectorAccounts.accountEmail,
        status: connectorAccounts.status,
        lastPolledAt: connectorAccounts.lastPolledAt,
        lastError: connectorAccounts.lastError,
        scope: connectorAccounts.scope,
      })
      .from(connectorAccounts)
      .where(
        and(eq(connectorAccounts.userId, ctx.userId), isNull(connectorAccounts.deletedAt)),
      )
      .all();
    return rows;
  }),

  /** Connection state for one source (null = not connected). */
  status: protectedProcedure
    .input(z.object({ source: connectorSourceEnum }))
    .query(({ input, ctx }) => {
      const row = db
        .select({
          source: connectorAccounts.source,
          accountEmail: connectorAccounts.accountEmail,
          status: connectorAccounts.status,
          lastPolledAt: connectorAccounts.lastPolledAt,
          lastError: connectorAccounts.lastError,
        })
        .from(connectorAccounts)
        .where(
          and(
            eq(connectorAccounts.userId, ctx.userId),
            eq(connectorAccounts.source, input.source),
            isNull(connectorAccounts.deletedAt),
          ),
        )
        .get();
      return row ?? null;
    }),

  /**
   * Disconnect a connector: soft-delete the grant so the poller stops and the
   * encrypted refresh token is no longer used. Idempotent.
   */
  disconnect: protectedProcedure
    .input(z.object({ source: connectorSourceEnum }))
    .mutation(({ input, ctx }) => {
      const now = new Date().toISOString();
      const res = db
        .update(connectorAccounts)
        .set({ status: "revoked", deletedAt: now, updatedAt: now })
        .where(
          and(
            eq(connectorAccounts.userId, ctx.userId),
            eq(connectorAccounts.source, input.source),
            isNull(connectorAccounts.deletedAt),
          ),
        )
        .run();
      return { disconnected: res.changes > 0 };
    }),
});
