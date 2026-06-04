/**
 * Gmail connector (SERVER_ARCHITECTURE.md §4.f Phase 5).
 *
 * REAL MODE: for every user who connected Gmail, mint an access token from their
 * encrypted refresh token, fetch a bounded page of new inbox messages via the
 * Gmail API, and ingest them through the shared per-user backpressure path
 * (cap-per-poll + dedupe + coalesce-into-one-event, §4.c).
 *
 * DEMO MODE (`CONNECTORS_DEMO=1` or no OAuth config): read `fixtures/gmail.json`
 * and ingest for the bootstrap operator — the offline/demo feed the spec keeps
 * usable behind a flag. Only the "fetch the feed" half differs; the backpressure
 * lives in `ingest.ts` and is identical for both modes.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ingestSignals, type ConnectorItem } from "./ingest";
import { isDemoMode } from "./mode";
import { pollRealForSource } from "./poll-real";
import { fetchGmail } from "./google-api";
import { BOOTSTRAP_USER_ID } from "../../../src/db/schema";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface Fixture {
  external_id: string;
  summary?: string;
  raw: Record<string, unknown>;
}

function pollDemo(): void {
  const file = path.join(__dirname, "fixtures", "gmail.json");
  if (!fs.existsSync(file)) return;
  const fixtures = JSON.parse(fs.readFileSync(file, "utf-8")) as Fixture[];
  const items: ConnectorItem[] = fixtures.map((fx) => ({
    externalId: fx.external_id,
    summary: fx.summary ?? null,
    raw: fx.raw,
  }));
  const { inserted, more } = ingestSignals("gmail", items, { userId: BOOTSTRAP_USER_ID });
  if (inserted > 0) {
    console.log(
      `[gmail:demo] ingested ${inserted} signal(s)${more ? " (more pending — capped this poll)" : ""}`,
    );
  }
}

export async function pollOnce(): Promise<void> {
  if (isDemoMode()) {
    pollDemo();
    return;
  }
  await pollRealForSource("gmail", fetchGmail);
}
