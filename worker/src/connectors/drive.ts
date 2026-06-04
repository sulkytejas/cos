/**
 * Drive connector (SERVER_ARCHITECTURE.md §4.f Phase 5).
 *
 * REAL MODE: for every user who connected Google Drive, mint an access token from
 * their encrypted refresh token, fetch a bounded page of recent changes via the
 * Drive Changes API (`pageToken`), and ingest through the shared per-user
 * backpressure path (§4.c). First connect records a `startPageToken` and ingests
 * nothing, so we only ever surface changes AFTER the connection — never a flood
 * of the user's entire Drive.
 *
 * DEMO MODE (`CONNECTORS_DEMO=1` or no OAuth config): read `fixtures/drive.json`
 * for the bootstrap operator.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ingestSignals, type ConnectorItem } from "./ingest";
import { isDemoMode } from "./mode";
import { pollRealForSource } from "./poll-real";
import { fetchDrive } from "./google-api";
import { BOOTSTRAP_USER_ID } from "../../../src/db/schema";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface Fixture {
  external_id: string;
  summary?: string;
  raw: Record<string, unknown>;
}

function pollDemo(): void {
  const file = path.join(__dirname, "fixtures", "drive.json");
  if (!fs.existsSync(file)) return;
  const fixtures = JSON.parse(fs.readFileSync(file, "utf-8")) as Fixture[];
  const items: ConnectorItem[] = fixtures.map((fx) => ({
    externalId: fx.external_id,
    summary: fx.summary ?? null,
    raw: fx.raw,
  }));
  const { inserted, more } = ingestSignals("drive", items, { userId: BOOTSTRAP_USER_ID });
  if (inserted > 0) {
    console.log(
      `[drive:demo] ingested ${inserted} signal(s)${more ? " (more pending — capped this poll)" : ""}`,
    );
  }
}

export async function pollOnce(): Promise<void> {
  if (isDemoMode()) {
    pollDemo();
    return;
  }
  await pollRealForSource("drive", fetchDrive);
}
