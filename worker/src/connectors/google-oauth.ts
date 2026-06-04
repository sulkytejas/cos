/**
 * Google OAuth 2.0 — code exchange + refresh (SERVER_ARCHITECTURE.md §4.f Phase 5).
 *
 * Real Gmail / Calendar / Drive connectors need a long-lived OAuth grant. This
 * module owns the OAuth dance with Google's endpoints using nothing but Node's
 * built-in global `fetch` (Node ≥18) — NO `googleapis` dependency, so it stays
 * $0 and runs identically in the Next.js process (for the callback) and the
 * worker process (for per-poll refresh).
 *
 * DEPLOY-TIME CONFIG (read from env; never invented here — these are real Google
 * Cloud OAuth client credentials the operator creates in the Cloud Console):
 *
 *   GOOGLE_OAUTH_CLIENT_ID      — the OAuth 2.0 Client ID (Web application)
 *   GOOGLE_OAUTH_CLIENT_SECRET  — the OAuth 2.0 Client secret
 *   GOOGLE_OAUTH_REDIRECT_URI   — must EXACTLY match an "Authorized redirect URI"
 *                                 registered on the client, e.g.
 *                                 https://<your-domain>/api/connectors/callback
 *
 * The refresh token returned by the exchange is the high-value secret; the caller
 * encrypts it (crypto.ts) before persisting. The short-lived access token is held
 * only in memory for the duration of one poll.
 */

const GOOGLE_AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";

/** Per-connector OAuth scopes. Read-only everywhere — we only ingest signals. */
export const GOOGLE_SCOPES = {
  gmail: ["https://www.googleapis.com/auth/gmail.readonly"],
  calendar: ["https://www.googleapis.com/auth/calendar.readonly"],
  drive: ["https://www.googleapis.com/auth/drive.metadata.readonly"],
} as const;

export type GoogleConnectorSource = keyof typeof GOOGLE_SCOPES;

/** All scopes plus the userinfo email so we can label the connected account. */
const EMAIL_SCOPE = "https://www.googleapis.com/auth/userinfo.email";

export interface GoogleOAuthConfig {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
}

/**
 * Read the deploy-time OAuth client config from env. Throws (a launch blocker for
 * real connectors) if any piece is missing — these are real credentials the
 * operator must create; we never invent them.
 */
export function getGoogleOAuthConfig(): GoogleOAuthConfig {
  const clientId = process.env.GOOGLE_OAUTH_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_OAUTH_CLIENT_SECRET;
  const redirectUri = process.env.GOOGLE_OAUTH_REDIRECT_URI;
  if (!clientId || !clientSecret || !redirectUri) {
    throw new Error(
      "Google OAuth is not configured. Set GOOGLE_OAUTH_CLIENT_ID, " +
        "GOOGLE_OAUTH_CLIENT_SECRET and GOOGLE_OAUTH_REDIRECT_URI in " +
        "/etc/atlas/atlas.env (deploy-time config from the Google Cloud Console).",
    );
  }
  return { clientId, clientSecret, redirectUri };
}

/** True iff real Google OAuth client credentials are configured. */
export function hasGoogleOAuthConfig(): boolean {
  return (
    !!process.env.GOOGLE_OAUTH_CLIENT_ID &&
    !!process.env.GOOGLE_OAUTH_CLIENT_SECRET &&
    !!process.env.GOOGLE_OAUTH_REDIRECT_URI
  );
}

/**
 * Build the Google consent-screen URL for one connector source. `state` carries
 * our CSRF/identity token (the caller binds it to the user + source).
 *
 *   - `access_type=offline` + `prompt=consent` is what makes Google return a
 *     REFRESH token (without it you only get a 1h access token and can't poll
 *     overnight). `prompt=consent` forces a refresh token even on re-consent.
 *   - We always request the email scope too so we can label the account.
 */
export function buildAuthUrl(source: GoogleConnectorSource, state: string): string {
  const cfg = getGoogleOAuthConfig();
  const scopes = [...GOOGLE_SCOPES[source], EMAIL_SCOPE];
  const params = new URLSearchParams({
    client_id: cfg.clientId,
    redirect_uri: cfg.redirectUri,
    response_type: "code",
    scope: scopes.join(" "),
    access_type: "offline",
    include_granted_scopes: "true",
    prompt: "consent",
    state,
  });
  return `${GOOGLE_AUTH_ENDPOINT}?${params.toString()}`;
}

export interface TokenExchangeResult {
  /** The long-lived refresh token — the secret the caller encrypts before storing. */
  refreshToken: string;
  /** A fresh short-lived access token (use immediately, then discard). */
  accessToken: string;
  /** Seconds until the access token expires. */
  expiresIn: number;
  /** Granted scopes (space-separated). */
  scope: string;
}

/**
 * Exchange an authorization `code` (from the redirect) for tokens. Google only
 * returns a refresh token on the FIRST consent (or when `prompt=consent` forces
 * it). We throw if no refresh token comes back, since an access-token-only grant
 * can't power overnight polling.
 */
export async function exchangeCode(code: string): Promise<TokenExchangeResult> {
  const cfg = getGoogleOAuthConfig();
  const body = new URLSearchParams({
    code,
    client_id: cfg.clientId,
    client_secret: cfg.clientSecret,
    redirect_uri: cfg.redirectUri,
    grant_type: "authorization_code",
  });

  const res = await fetch(GOOGLE_TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`Google token exchange failed (${res.status}): ${text}`);
  }
  const json = (await res.json()) as {
    access_token?: string;
    refresh_token?: string;
    expires_in?: number;
    scope?: string;
  };
  if (!json.refresh_token) {
    throw new Error(
      "Google returned no refresh_token. The account may have already granted " +
        "access without prompt=consent — revoke at https://myaccount.google.com/permissions and retry.",
    );
  }
  return {
    refreshToken: json.refresh_token,
    accessToken: json.access_token ?? "",
    expiresIn: json.expires_in ?? 3600,
    scope: json.scope ?? "",
  };
}

/** Marker error for an irrecoverably-revoked grant — the caller marks the account 'revoked'. */
export class InvalidGrantError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidGrantError";
  }
}

/**
 * Mint a fresh access token from a stored refresh token. The poller calls this
 * once per poll (access tokens live ~1h; a 15-min poll re-fetches anyway, so we
 * never persist the short-lived token).
 *
 * On `invalid_grant` (revoked/expired refresh token) we throw an
 * `InvalidGrantError` so the caller can mark the account 'revoked' and stop
 * polling it instead of retrying a dead grant forever.
 */
export async function refreshAccessToken(refreshToken: string): Promise<{
  accessToken: string;
  expiresIn: number;
}> {
  const cfg = getGoogleOAuthConfig();
  const body = new URLSearchParams({
    refresh_token: refreshToken,
    client_id: cfg.clientId,
    client_secret: cfg.clientSecret,
    grant_type: "refresh_token",
  });

  const res = await fetch(GOOGLE_TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    if (res.status === 400 && /invalid_grant/.test(text)) {
      throw new InvalidGrantError(`Refresh token rejected (invalid_grant): ${text}`);
    }
    throw new Error(`Google token refresh failed (${res.status}): ${text}`);
  }
  const json = (await res.json()) as { access_token?: string; expires_in?: number };
  if (!json.access_token) throw new Error("Google token refresh returned no access_token.");
  return { accessToken: json.access_token, expiresIn: json.expires_in ?? 3600 };
}

/** Fetch the authenticated account's primary email (for labeling the connection). */
export async function fetchAccountEmail(accessToken: string): Promise<string | null> {
  try {
    const res = await fetch("https://www.googleapis.com/oauth2/v2/userinfo", {
      headers: { authorization: `Bearer ${accessToken}` },
    });
    if (!res.ok) return null;
    const json = (await res.json()) as { email?: string };
    return json.email ?? null;
  } catch {
    return null;
  }
}
