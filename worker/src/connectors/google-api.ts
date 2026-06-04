/**
 * Read-only Google API fetchers (SERVER_ARCHITECTURE.md §4.f Phase 5).
 *
 * Given a fresh access token, fetch a bounded page of new items from Gmail /
 * Calendar / Drive and return them as `ConnectorItem[]` plus the next opaque
 * upstream cursor. All requests use Node's global `fetch` (no `googleapis`
 * dependency). Read-only scopes only — we ingest signals, never write.
 *
 * Each fetcher is INCREMENTAL where the API supports it (so we don't re-scan the
 * whole inbox every poll) and CAPPED to `pageSize` items so a first-time backfill
 * drains over many polls (the backpressure contract in §4.c). The cursor we
 * return is persisted on the account by the connector (`setSyncCursor`).
 */
import type { ConnectorItem } from "./ingest";

/** One bounded page of upstream items + the cursor to persist for the next poll. */
export interface FetchPage {
  items: ConnectorItem[];
  /** Opaque cursor to store (historyId / syncToken / pageToken); null = unchanged. */
  nextCursor: string | null;
  /** True when more pages remain right now (a backfill in progress). */
  more: boolean;
}

async function gapi<T>(url: string, accessToken: string): Promise<T> {
  const res = await fetch(url, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`Google API ${res.status} for ${url}: ${text.slice(0, 300)}`);
  }
  return (await res.json()) as T;
}

// ─────────────────────────── Gmail ───────────────────────────

interface GmailListResp {
  messages?: { id: string; threadId: string }[];
  nextPageToken?: string;
  resultSizeEstimate?: number;
}
interface GmailMessageResp {
  id: string;
  threadId: string;
  internalDate?: string;
  snippet?: string;
  payload?: { headers?: { name: string; value: string }[] };
}

function header(msg: GmailMessageResp, name: string): string | undefined {
  return msg.payload?.headers?.find(
    (h) => h.name.toLowerCase() === name.toLowerCase(),
  )?.value;
}

/**
 * Fetch up to `pageSize` recent inbox messages. We list ids (one cheap call),
 * then fetch each message's metadata (headers + snippet — `format=metadata`, no
 * body download, no extra scope). `cursor` is the Gmail `historyId` watermark:
 * we only keep messages with `internalDate` newer than the last poll's newest,
 * encoded in the cursor as `lastInternalDate`.
 *
 * Gmail's History API needs a recently-issued historyId to be valid; using the
 * newest-message timestamp as the watermark is robust across long gaps (the
 * History API 404s if the historyId is too old) and keeps this dependency-free.
 */
export async function fetchGmail(
  accessToken: string,
  cursor: string | null,
  pageSize: number,
): Promise<FetchPage> {
  const lastInternalDate = cursor ? Number(cursor) : 0;

  const list = await gapi<GmailListResp>(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=${pageSize}&labelIds=INBOX`,
    accessToken,
  );
  const ids = (list.messages ?? []).map((m) => m.id);
  if (ids.length === 0) return { items: [], nextCursor: cursor, more: false };

  const items: ConnectorItem[] = [];
  let newestSeen = lastInternalDate;
  for (const id of ids) {
    const msg = await gapi<GmailMessageResp>(
      `https://gmail.googleapis.com/gmail/v1/users/me/messages/${id}?format=metadata&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Subject&metadataHeaders=Date`,
      accessToken,
    );
    const internal = Number(msg.internalDate ?? 0);
    if (internal > newestSeen) newestSeen = internal;
    // Skip anything at/older than our watermark — incremental, no re-ingest.
    if (lastInternalDate > 0 && internal <= lastInternalDate) continue;

    const from = header(msg, "From") ?? "";
    const subject = header(msg, "Subject") ?? "(no subject)";
    items.push({
      externalId: msg.id,
      summary: `${from.split("<")[0].trim() || from} — ${subject}`.slice(0, 200),
      raw: {
        from,
        to: header(msg, "To") ?? "",
        subject,
        received_at: header(msg, "Date") ?? "",
        snippet: msg.snippet ?? "",
        threadId: msg.threadId,
      },
    });
  }

  return {
    items,
    nextCursor: newestSeen > 0 ? String(newestSeen) : cursor,
    // First connect (no cursor) with a full page likely has more history; on
    // incremental polls a full page also implies more new mail to drain.
    more: ids.length >= pageSize,
  };
}

// ─────────────────────────── Calendar ───────────────────────────

interface CalEvent {
  id: string;
  status?: string;
  summary?: string;
  location?: string;
  start?: { dateTime?: string; date?: string };
  end?: { dateTime?: string; date?: string };
  attendees?: { email?: string }[];
}
interface CalListResp {
  items?: CalEvent[];
  nextPageToken?: string;
  nextSyncToken?: string;
}

/**
 * Fetch upcoming primary-calendar events using Calendar's incremental `syncToken`.
 * First connect (no token) lists events from now forward; subsequent polls pass
 * the stored `syncToken` for a delta. A 410 GONE means the token expired — the
 * caller drops the cursor and we do a fresh initial sync next poll.
 */
export async function fetchCalendar(
  accessToken: string,
  cursor: string | null,
  pageSize: number,
): Promise<FetchPage> {
  const base = "https://www.googleapis.com/calendar/v3/calendars/primary/events";
  let url: string;
  if (cursor) {
    url = `${base}?maxResults=${pageSize}&syncToken=${encodeURIComponent(cursor)}`;
  } else {
    // Initial sync: upcoming events only, singleEvents so recurrences expand.
    const timeMin = new Date().toISOString();
    url = `${base}?maxResults=${pageSize}&singleEvents=true&orderBy=startTime&timeMin=${encodeURIComponent(timeMin)}`;
  }

  let resp: CalListResp;
  try {
    resp = await gapi<CalListResp>(url, accessToken);
  } catch (err) {
    // Expired syncToken (410) → reset cursor; the next poll re-initialises.
    if (/\b410\b/.test((err as Error).message)) {
      return { items: [], nextCursor: null, more: true };
    }
    throw err;
  }

  const items: ConnectorItem[] = [];
  for (const ev of resp.items ?? []) {
    if (ev.status === "cancelled") continue; // tombstone from a delta — skip
    const start = ev.start?.dateTime ?? ev.start?.date ?? "";
    const end = ev.end?.dateTime ?? ev.end?.date ?? "";
    items.push({
      externalId: ev.id,
      summary: (ev.summary ?? "(busy)").slice(0, 200),
      raw: {
        title: ev.summary ?? "(busy)",
        startsAt: start,
        endsAt: end,
        location: ev.location ?? "",
        attendees: (ev.attendees ?? []).map((a) => a.email).filter(Boolean),
      },
    });
  }

  return {
    items,
    nextCursor: resp.nextSyncToken ?? cursor,
    more: !!resp.nextPageToken,
  };
}

// ─────────────────────────── Drive ───────────────────────────

interface DriveChange {
  fileId?: string;
  removed?: boolean;
  time?: string;
  file?: {
    id: string;
    name?: string;
    mimeType?: string;
    modifiedTime?: string;
    webViewLink?: string;
  };
}
interface DriveChangesResp {
  changes?: DriveChange[];
  nextPageToken?: string;
  newStartPageToken?: string;
}
interface DriveStartTokenResp {
  startPageToken: string;
}

/**
 * Fetch recent Drive changes via the Changes API (`pageToken`). First connect
 * (no token) fetches a `startPageToken` and records it, ingesting nothing — so we
 * only ever surface changes that happen AFTER the connection, never a flood of
 * the user's entire Drive. Subsequent polls page from the stored token.
 */
export async function fetchDrive(
  accessToken: string,
  cursor: string | null,
  pageSize: number,
): Promise<FetchPage> {
  if (!cursor) {
    const start = await gapi<DriveStartTokenResp>(
      "https://www.googleapis.com/drive/v3/changes/startPageToken",
      accessToken,
    );
    return { items: [], nextCursor: start.startPageToken, more: false };
  }

  const fields =
    "newStartPageToken,nextPageToken,changes(fileId,removed,time,file(id,name,mimeType,modifiedTime,webViewLink))";
  const url = `https://www.googleapis.com/drive/v3/changes?pageToken=${encodeURIComponent(
    cursor,
  )}&pageSize=${pageSize}&fields=${encodeURIComponent(fields)}`;
  const resp = await gapi<DriveChangesResp>(url, accessToken);

  const items: ConnectorItem[] = [];
  for (const ch of resp.changes ?? []) {
    if (ch.removed || !ch.file) continue; // deletion/trash — no signal
    const f = ch.file;
    if (f.mimeType === "application/vnd.google-apps.folder") continue;
    items.push({
      externalId: `${f.id}@${ch.time ?? f.modifiedTime ?? ""}`,
      summary: (f.name ?? "(file changed)").slice(0, 200),
      raw: {
        doc: f.name ?? "",
        mimeType: f.mimeType ?? "",
        last_touched_at: f.modifiedTime ?? ch.time ?? "",
        webViewLink: f.webViewLink ?? "",
      },
    });
  }

  return {
    items,
    // Advance to the next page if paginating; else adopt the new start token.
    nextCursor: resp.nextPageToken ?? resp.newStartPageToken ?? cursor,
    more: !!resp.nextPageToken,
  };
}
