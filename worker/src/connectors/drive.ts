/**
 * Stubbed Drive connector. Same shape as Gmail/Calendar. Real OAuth in v0.3.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { db, schema } from "../db";
import { eq, and } from "drizzle-orm";
import { randomUUID } from "node:crypto";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

interface Fixture {
  external_id: string;
  summary?: string;
  raw: Record<string, unknown>;
}

export async function pollOnce(): Promise<void> {
  const file = path.join(__dirname, "fixtures", "drive.json");
  if (!fs.existsSync(file)) return;
  const fixtures = JSON.parse(fs.readFileSync(file, "utf-8")) as Fixture[];
  let inserted = 0;
  for (const fx of fixtures) {
    const existing = db
      .select()
      .from(schema.signals)
      .where(
        and(eq(schema.signals.source, "drive"), eq(schema.signals.externalId, fx.external_id))
      )
      .get();
    if (existing) continue;
    const id = randomUUID();
    db.insert(schema.signals)
      .values({
        id,
        source: "drive",
        externalId: fx.external_id,
        summary: fx.summary ?? null,
        rawData: fx.raw,
      })
      .run();
    db.insert(schema.events)
      .values({ id: randomUUID(), type: "signal_received", payload: { signalId: id } })
      .run();
    inserted++;
  }
  if (inserted > 0) console.log(`[drive] ingested ${inserted} signals`);
}
