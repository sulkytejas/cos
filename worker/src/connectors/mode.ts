/**
 * Connector mode selection (SERVER_ARCHITECTURE.md §4.f Phase 5).
 *
 * Real OAuth connectors replace the fixtures, BUT the JSON fixtures stay usable
 * as an offline/demo mode behind a flag (the spec's explicit requirement). The
 * mode is demo when EITHER:
 *
 *   - `CONNECTORS_DEMO=1` is set (force the offline/demo feed), OR
 *   - real OAuth client credentials / the encryption key are NOT configured
 *     (so a box without deploy-time secrets degrades gracefully to fixtures
 *     instead of crashing every poll).
 *
 * Otherwise connectors run the real per-user OAuth poll.
 */
import { hasGoogleOAuthConfig } from "./google-oauth";
import { hasEncryptionKey } from "./crypto";

export function isDemoMode(): boolean {
  if (process.env.CONNECTORS_DEMO === "1") return true;
  // Real mode requires BOTH the OAuth client config and the token-encryption key.
  return !hasGoogleOAuthConfig() || !hasEncryptionKey();
}
