/**
 * Calendar connector (SERVER_ARCHITECTURE.md §4.f Phase 5).
 *
 * REAL MODE: for every user who connected Google Calendar, mint an access token
 * from their encrypted refresh token, fetch a bounded incremental page of
 * upcoming events (Calendar `syncToken`), and ingest through the shared per-user
 * backpressure path (§4.c).
 *
 * Note de-dupe with the iOS push fast-path (§4.e): EventKit-pushed device
 * calendar events arrive via `signal.ingest` under source `calendar`, upserting
 * on `(userId, source, externalId)`. The Google externalId is the Google event
 * id, which differs from `EKEvent.eventIdentifier`, so the two sources can
 * surface the same meeting twice; that's resolved downstream by the agent's
 * coalescing, while EventKit stays the device-only push fast-path the spec keeps.
 *
 * DEMO MODE (`CONNECTORS_DEMO=1` or no OAuth config): read `fixtures/calendar.json`
 * for the bootstrap operator.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ingestSignals, type ConnectorItem } from "./ingest";
import { isDemoMode } from "./mode";
import { pollRealForSource } from "./poll-real";
import { fetchCalendar } from "./google-api";
import { BOOTSTRAP_USER_ID } from "../../../src/db/schema";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface Fixture {
  external_id: string;
  summary?: string;
  raw: Record<string, unknown>;
}

function pollDemo(): void {
  const file = path.join(__dirname, "fixtures", "calendar.json");
  if (!fs.existsSync(file)) return;
  const fixtures = JSON.parse(fs.readFileSync(file, "utf-8")) as Fixture[];
  const items: ConnectorItem[] = fixtures.map((fx) => ({
    externalId: fx.external_id,
    summary: fx.summary ?? null,
    raw: fx.raw,
  }));
  const { inserted, more } = ingestSignals("calendar", items, { userId: BOOTSTRAP_USER_ID });
  if (inserted > 0) {
    console.log(
      `[calendar:demo] ingested ${inserted} signal(s)${more ? " (more pending — capped this poll)" : ""}`,
    );
  }
}

export async function pollOnce(): Promise<void> {
  if (isDemoMode()) {
    pollDemo();
    return;
  }
  await pollRealForSource("calendar", fetchCalendar);
}
