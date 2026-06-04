/**
 * Real per-user OAuth poll driver (SERVER_ARCHITECTURE.md §4.f Phase 5).
 *
 * For one connector source, fan out across every connected user: mint a fresh
 * access token from their encrypted refresh token, fetch a bounded page of new
 * items, and ingest them through the SAME backpressure path as the fixtures
 * (`ingestSignals`, per-user, cap + coalesce). The upstream incremental cursor
 * (historyId / syncToken / pageToken) is persisted per account so each poll is a
 * delta, not a full re-scan.
 *
 * Failure isolation: one user's revoked grant or transient API error never blocks
 * the others — an `invalid_grant` marks that account revoked (stops polling it),
 * any other error is stamped on the account for observability and the loop moves
 * on. This is the 24/7-poller half the spec calls out as "neither belongs on a
 * phone".
 */
import {
  activeAccountsForSource,
  markAccountPolled,
  markAccountRevoked,
  markAccountError,
  setSyncCursor,
} from "./accounts";
import { ingestSignals, MAX_SIGNALS_PER_POLL } from "./ingest";
import {
  refreshAccessToken,
  InvalidGrantError,
  type GoogleConnectorSource,
} from "./google-oauth";
import type { FetchPage } from "./google-api";

/** A source-specific fetcher: (accessToken, cursor, pageSize) → one page. */
export type Fetcher = (
  accessToken: string,
  cursor: string | null,
  pageSize: number,
) => Promise<FetchPage>;

/**
 * Poll one source for ALL connected users. Returns the total new signals
 * ingested across users this poll (for logging).
 */
export async function pollRealForSource(
  source: GoogleConnectorSource,
  fetcher: Fetcher,
): Promise<number> {
  const accounts = activeAccountsForSource(source);
  let totalInserted = 0;

  for (const account of accounts) {
    try {
      // 1) Mint a short-lived access token from the encrypted refresh token.
      const { accessToken } = await refreshAccessToken(account.refreshToken);

      // 2) Fetch one bounded page (the source's own incremental cursor).
      const page = await fetcher(accessToken, account.syncCursor, MAX_SIGNALS_PER_POLL);

      // 3) Ingest with per-user backpressure. The real path passes an
      //    already-paginated batch, so the integer fixture cursor is bypassed
      //    (`useCursor: false`) — dedupe on (userId, source, externalId) still
      //    guards against any overlap the upstream delta returns.
      if (page.items.length > 0) {
        const { inserted, more } = ingestSignals(source, page.items, {
          userId: account.userId,
          useCursor: false,
        });
        totalInserted += inserted;
        if (inserted > 0) {
          console.log(
            `[${source}] ingested ${inserted} signal(s) for ${account.accountEmail ?? account.userId}` +
              `${more || page.more ? " (more pending — capped this poll)" : ""}`,
          );
        }
      }

      // 4) Advance the upstream cursor (even on an empty page, so a first-connect
      //    Drive start-token / Gmail watermark is recorded immediately).
      if (page.nextCursor !== account.syncCursor) {
        setSyncCursor(account.userId, source, page.nextCursor);
      }
      markAccountPolled(account.userId, source);
    } catch (err) {
      if (err instanceof InvalidGrantError) {
        // The refresh token is dead — stop polling and flag re-auth in the UI.
        markAccountRevoked(account.userId, source, err.message);
        console.warn(
          `[${source}] grant revoked for ${account.accountEmail ?? account.userId} — re-auth required`,
        );
      } else {
        markAccountError(account.userId, source, (err as Error).message);
        console.warn(
          `[${source}] poll failed for ${account.accountEmail ?? account.userId}:`,
          (err as Error).message,
        );
      }
    }
  }

  return totalInserted;
}
