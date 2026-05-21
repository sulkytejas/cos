/**
 * Event processor — dispatches each event row to the right handler. Each
 * handler ultimately calls `runAgent(context)` and `persistAgentResult`.
 */
import { db, schema } from "../db";
import { runAgent } from "../agent/loop";
import { persistAgentResult } from "../persist";
import { eq } from "drizzle-orm";

export async function processEvent(event: schema.Event): Promise<void> {
  switch (event.type) {
    case "capture_received":
      return processCapture(event);
    case "chapter_created":
    case "chapter_updated":
      return processChapterTouched(event);
    case "signal_received":
      return processSignalReceived(event);
    case "watcher_due":
      return processWatcherDue(event);
    case "daily_scan":
      return processDailyScan(event);
    case "time_trigger":
    case "forward_drift_scan":
      // TODO(v0.3) — forward drift scan
      return;
    case "brief_acted_on":
      // Log only — could be used to refine future brief reasoning.
      return;
  }
}

async function processCapture(event: schema.Event): Promise<void> {
  const payload = event.payload as { text?: string; chapterId?: string | null };
  const text = (payload.text ?? "").trim();
  if (!text) return;

  // Look up active chapters for the agent's context.
  const activeChapters = db
    .select({ id: schema.chapters.id, title: schema.chapters.title, status: schema.chapters.status })
    .from(schema.chapters)
    .all();

  const context = [
    "A new capture has just arrived from Tejas.",
    "",
    `Capture text: """${text}"""`,
    "",
    payload.chapterId ? `Hinted chapter: ${payload.chapterId}` : "Chapter: unspecified.",
    "",
    "Active chapters in the database:",
    ...activeChapters.map((c) => `  - ${c.id} · ${c.title} · ${c.status}`),
    "",
    "Decide what proposals (todos / decisions / journal entries) this capture should produce. Most captures should not become a full Brief — they should produce 1–3 proposals that show up in the Review Queue. Only produce a Brief if the capture is *about* a specific upcoming situation that deserves preparation (a meeting in the next 24h, a decision crystallising, a trip approaching). Otherwise, emit a tiny stub brief titled 'Capture filed' with one tactical section summarising what you noted, and put the real value in proposals.",
  ].join("\n");

  const result = await runAgent(context);
  persistAgentResult(result, { chapterId: payload.chapterId ?? null });
}

async function processChapterTouched(event: schema.Event): Promise<void> {
  const payload = event.payload as { chapterId?: string };
  if (!payload.chapterId) return;
  const chapter = db
    .select()
    .from(schema.chapters)
    .where(eq(schema.chapters.id, payload.chapterId))
    .get();
  if (!chapter) return;

  // For now, chapter_created/updated just produces a daily-style overview brief.
  // Real use: trigger a "you might be missing something" check.
  const context = [
    `A chapter has just been ${event.type === "chapter_created" ? "created" : "updated"}: ${chapter.title}.`,
    `Type: ${chapter.type}, status: ${chapter.status}, range: ${chapter.startDate ?? "—"} → ${chapter.endDate ?? "—"}.`,
    chapter.purpose ? `Purpose: ${chapter.purpose}` : "",
    "",
    "Consider whether this chapter needs an opening brief, a few extracted todos, or just an acknowledgement. Use chapter_query to see what's already in it.",
  ].join("\n");

  const result = await runAgent(context);
  persistAgentResult(result, { chapterId: chapter.id });
}

async function processSignalReceived(event: schema.Event): Promise<void> {
  const payload = event.payload as { signalId?: string };
  if (!payload.signalId) return;
  const signal = db
    .select()
    .from(schema.signals)
    .where(eq(schema.signals.id, payload.signalId))
    .get();
  if (!signal) return;

  const context = [
    `A new signal arrived: source=${signal.source}, summary=${signal.summary ?? "(none)"}.`,
    `Raw data: ${JSON.stringify(signal.rawData).slice(0, 1500)}`,
    "",
    "Decide what (if anything) this signal warrants. Most signals should produce zero or one small proposals. Some — a meeting on the calendar within the next 24h, a deadline confirmation — should produce a Brief.",
  ].join("\n");

  const result = await runAgent(context);
  persistAgentResult(result);

  // Mark the signal processed so we don't re-trigger.
  db.update(schema.signals).set({ processed: true }).where(eq(schema.signals.id, signal.id)).run();
}

async function processWatcherDue(event: schema.Event): Promise<void> {
  const payload = event.payload as { watcherId?: string };
  if (!payload.watcherId) return;
  const watcher = db
    .select()
    .from(schema.watchers)
    .where(eq(schema.watchers.id, payload.watcherId))
    .get();
  if (!watcher) return;

  const context = [
    "A watcher has come due.",
    `Description: ${watcher.description}`,
    `Prompt: ${watcher.prompt}`,
    watcher.chapterId ? `Chapter: ${watcher.chapterId}` : "",
    "",
    "Re-check the source. If you find something worth surfacing, produce a brief or a proposal. If nothing changed, return an empty brief structure with a one-line tactical note acknowledging the check.",
  ].join("\n");

  const result = await runAgent(context);
  persistAgentResult(result, { chapterId: watcher.chapterId });

  // Schedule the next check.
  const next = new Date(Date.now() + watcher.cadenceMinutes * 60 * 1000).toISOString();
  db.update(schema.watchers)
    .set({ lastChecked: new Date().toISOString(), nextCheck: next })
    .where(eq(schema.watchers.id, watcher.id))
    .run();
}

async function processDailyScan(_event: schema.Event): Promise<void> {
  // Read active chapters + signals from last 24h; ask agent for a "Briefs for
  // today" pass that may produce 0..N briefs across chapters.
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const recentSignals = db
    .select()
    .from(schema.signals)
    .all()
    .filter((s) => s.arrivedAt >= since);
  const activeChapters = db
    .select()
    .from(schema.chapters)
    .all()
    .filter((c) => c.status === "active" || c.status === "upcoming");

  const context = [
    "Daily scan. Examine the active chapters and signals from the last 24 hours.",
    `Today is ${new Date().toISOString().slice(0, 10)}.`,
    "",
    `Active chapters:\n${activeChapters.map((c) => `  - ${c.id} · ${c.title} · ${c.status}`).join("\n")}`,
    "",
    `Recent signals (count by source): ${countBySource(recentSignals)}`,
    "",
    "Produce briefs for situations that deserve preparation in the next 24 hours. If nothing warrants a brief, emit a single tiny brief titled 'A quiet day' with one tactical line and zero proposals.",
  ].join("\n");

  const result = await runAgent(context);
  persistAgentResult(result);
}

function countBySource(rows: schema.Signal[]): string {
  const buckets: Record<string, number> = {};
  for (const r of rows) buckets[r.source] = (buckets[r.source] ?? 0) + 1;
  return Object.entries(buckets).map(([k, v]) => `${k}=${v}`).join(", ");
}
