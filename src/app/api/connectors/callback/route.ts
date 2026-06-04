/**
 * Google OAuth callback (SERVER_ARCHITECTURE.md §4.f Phase 5).
 *
 * This is the UNAUTHENTICATED redirect target Google sends the browser to after
 * consent (`GOOGLE_OAUTH_REDIRECT_URI`). It can't carry the device bearer token,
 * so the signed `state` re-establishes the `userId` + `source` and is verified
 * here as the CSRF + identity check. It then:
 *
 *   1. exchanges the `code` for tokens (incl. the refresh token),
 *   2. encrypts the refresh token (AES-256-GCM, key from env, bound to `userId`),
 *   3. upserts the `connector_accounts` row (only ciphertext + IV + tag stored),
 *   4. returns a tiny "connected — return to Ayumi" HTML page.
 *
 * The worker's 15-min poll then picks up the new grant and starts ingesting
 * signals through the same per-user backpressure path as the fixtures.
 *
 * NOTE: the encryption + token exchange modules live under worker/src/connectors
 * but are pure (no DB coupling), so the Next.js process imports them directly and
 * writes via the web `@/db/client` — it never opens the worker's DB handle.
 */
import { randomUUID } from "node:crypto";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { connectorAccounts } from "@/db/schema";
import { verifyState } from "@/server/connector-state";
import {
  exchangeCode,
  fetchAccountEmail,
  type GoogleConnectorSource,
} from "../../../../../worker/src/connectors/google-oauth";
import { sealToken } from "../../../../../worker/src/connectors/crypto";

export const dynamic = "force-dynamic";

/**
 * HTML-escape a value before interpolating it into the served page. This
 * callback is an UNAUTHENTICATED GET whose query string is fully
 * attacker-controllable (e.g. `?error=<script>…`), and it returns text/html on
 * our own origin — so every interpolated value MUST be escaped to prevent
 * reflected XSS. Escapes the five characters that are significant in HTML
 * text/attribute contexts.
 */
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * Build the page. `title` and `body` may contain a small, fixed set of trusted
 * markup tokens we generate ourselves (e.g. `<b>` around an already-escaped
 * email), so callers are responsible for escaping any untrusted substring with
 * `escapeHtml()` before passing it in. The page also carries a restrictive CSP
 * (`default-src 'none'`, inline styles only) as defense-in-depth: even if an
 * escape were ever missed, no script/connect/img/frame can execute or exfil.
 */
function htmlPage(title: string, body: string, status = 200): Response {
  const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title><style>body{font-family:-apple-system,system-ui,sans-serif;background:#0b0b0f;color:#e8e8ee;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}.card{max-width:420px;padding:32px;text-align:center}h1{font-size:20px;margin:0 0 8px}p{color:#9a9aa6;line-height:1.5;margin:0}</style></head><body><div class="card"><h1>${title}</h1><p>${body}</p></div></body></html>`;
  return new Response(html, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'",
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer",
    },
  });
}

export async function GET(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const params = url.searchParams;

  // Google passes `error` when the user declines or something fails upstream.
  const oauthError = params.get("error");
  if (oauthError) {
    return htmlPage("Connection cancelled", `Google reported: ${escapeHtml(oauthError)}. You can close this and try again from Ayumi.`, 400);
  }

  const code = params.get("code");
  const state = params.get("state");
  const verified = verifyState(state);
  if (!verified) {
    // Bad/expired/forged state — never proceed (CSRF + identity check).
    return htmlPage("Invalid or expired link", "This connection link is invalid or has expired. Open Ayumi and start the connection again.", 400);
  }
  if (!code) {
    return htmlPage("Missing authorization code", "Google didn't return an authorization code. Please try connecting again from Ayumi.", 400);
  }

  const { userId, source } = verified;

  try {
    // 1) Exchange the code for tokens (incl. the long-lived refresh token).
    const tokens = await exchangeCode(code);

    // 2) Label the account (best-effort) using the fresh access token.
    const accountEmail = await fetchAccountEmail(tokens.accessToken);

    // 3) Encrypt the refresh token for this user (key from env, bound as AAD).
    const sealed = sealToken(tokens.refreshToken, userId);
    const now = new Date().toISOString();

    // 4) Upsert the grant — only ciphertext + IV + tag are persisted.
    const existing = db
      .select({ id: connectorAccounts.id })
      .from(connectorAccounts)
      .where(
        and(
          eq(connectorAccounts.userId, userId),
          eq(connectorAccounts.source, source as GoogleConnectorSource),
        ),
      )
      .get();
    const id = existing?.id ?? randomUUID();

    db.insert(connectorAccounts)
      .values({
        id,
        userId,
        source,
        accountEmail,
        refreshTokenCiphertext: sealed.ciphertext,
        refreshTokenIv: sealed.iv,
        refreshTokenTag: sealed.tag,
        scope: tokens.scope,
        // Re-connecting resets the upstream cursor so the next poll re-syncs.
        syncCursor: null,
        status: "active",
        lastError: null,
        updatedAt: now,
        deletedAt: null,
      })
      .onConflictDoUpdate({
        target: [connectorAccounts.userId, connectorAccounts.source],
        set: {
          accountEmail,
          refreshTokenCiphertext: sealed.ciphertext,
          refreshTokenIv: sealed.iv,
          refreshTokenTag: sealed.tag,
          scope: tokens.scope,
          syncCursor: null,
          status: "active",
          lastError: null,
          updatedAt: now,
          deletedAt: null,
        },
      })
      .run();

    const label = escapeHtml(source.charAt(0).toUpperCase() + source.slice(1));
    return htmlPage(
      `${label} connected`,
      `Ayumi is now watching ${accountEmail ? `<b>${escapeHtml(accountEmail)}</b>'s ` : "your "}${label}. You can close this tab and return to the app.`,
    );
  } catch (err) {
    return htmlPage(
      "Couldn't finish connecting",
      `Something went wrong completing the connection: ${escapeHtml((err as Error).message)}. Please try again from Ayumi.`,
      500,
    );
  }
}
