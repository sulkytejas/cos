/**
 * Event processor — dispatches each event row to the right handler.
 *
 * SERVER_ARCHITECTURE.md §4.c (output-idempotency, ship-blocker): each handler
 * is split into two phases:
 *
 *   1. an async **prepare** phase that runs the agent and reads context (NO db
 *      writes), then
 *   2. a synchronous **commit** closure that performs every db write for this
 *      event — brief/proposal/watcher inserts AND the post-effects (mark the
 *      signal processed, reschedule the watcher).
 *
 * `queue.ts` runs the returned `commit` inside ONE better-sqlite3 transaction
 * together with `markDone`, AFTER the await returns. A crash before/within that
 * txn rolls back every write and cleanly requeues the event — so a kill mid
 * `daily_scan` never doubles the "drafted while you slept" briefs, and a signal
 * is never marked processed without its brief (or vice-versa).
 */
import { db, schema } from "../db";
import { runAgent } from "../agent/loop";
import { persistAgentResult } from "../persist";
import { createMessage } from "../../../src/server/anthropic/gateway";
import {
  CAPTURE_SYSTEM,
  CAPTURE_MAX_OUTPUT_TOKENS,
  buildCaptureUserMessage,
  parseCaptureCompletion,
  type CaptureChapter,
  type CaptureCompletionResult,
} from "../../../src/server/anthropic/capture-prompt";
import { and, eq, isNull } from "drizzle-orm";

/** Caps for the grounded Ask prompt — mirror ai.ts; the worker slices to these. */
const ASK_MAX_CONTEXT_CHARS = 4_000;
const ASK_MAX_OUTPUT_TOKENS = 600;

/**
 * The synchronous write phase for one event. Receives the claimed event's id so
 * every row it writes can be stamped `generatedByEventId` — recovery deletes a
 * requeued event's prior output (briefs/proposals) before re-running. Must
 * contain ONLY synchronous better-sqlite3 work so it can run inside a txn.
 */
export type EventCommit = (eventId: string) => void;

/** A no-op commit for event types that have nothing to persist. */
const NOOP_COMMIT: EventCommit = () => {};

/**
 * Phase 1: run the agent / read context for an event. Returns the synchronous
 * write phase. THROWS on a genuine processing error so the queue fails the
 * event; a handler that simply has nothing to do returns `NOOP_COMMIT`.
 */
export async function prepareEvent(event: schema.Event): Promise<EventCommit> {
  switch (event.type) {
    case "capture_received":
      return prepareCapture(event);
    case "chapter_created":
    case "chapter_updated":
      return prepareChapterTouched(event);
    case "signal_received":
      return prepareSignalReceived(event);
    case "watcher_due":
      return prepareWatcherDue(event);
    case "daily_scan":
      return prepareDailyScan(event);
    case "forward_drift_scan":
      return prepareForwardDriftScan(event);
    case "time_trigger":
      return prepareTimeTrigger(event);
    case "brief_acted_on":
      // Log only — could be used to refine future brief reasoning.
      return NOOP_COMMIT;
    case "ai_ask":
      return prepareAiAsk(event);
    case "capture_complete":
      return prepareCaptureComplete(event);
  }
}

/**
 * Back-compat shim: run + commit in two steps (non-atomic). Retained so
 * `worker/src/once.ts` keeps working; the long-running worker uses the queue's
 * transactional path via `prepareEvent`.
 */
export async function processEvent(event: schema.Event): Promise<void> {
  const commit = await prepareEvent(event);
  commit(event.id);
}

async function prepareCapture(event: schema.Event): Promise<EventCommit> {
  const payload = event.payload as { text?: string; chapterId?: string | null };
  const text = (payload.text ?? "").trim();
  if (!text) return NOOP_COMMIT;

  // Look up active chapters for the agent's context — scoped to this event's
  // owner, live rows only (§4.d/§4.f).
  const activeChapters = db
    .select({ id: schema.chapters.id, title: schema.chapters.title, status: schema.chapters.status })
    .from(schema.chapters)
    .where(and(eq(schema.chapters.userId, event.userId), isNull(schema.chapters.deletedAt)))
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

  const result = await runAgent(context, { userId: event.userId });
  return (eventId) => {
    const persisted = persistAgentResult(result, {
      chapterId: payload.chapterId ?? null,
      generatedByEventId: eventId,
      userId: event.userId,
    });
    // §4.a (capture job contract): write the proposals THIS capture produced into
    // `events.result` so the client renders exactly them via `event.status` —
    // NOT a `createdAt >= sendStart` window, which a background scan can pollute.
    // Same txn as markDone, so the ids and the `done` status commit atomically.
    writeEventResult(eventId, { answer: "", resultProposalIds: persisted.proposalIds });
  };
}

async function prepareChapterTouched(event: schema.Event): Promise<EventCommit> {
  const payload = event.payload as { chapterId?: string };
  if (!payload.chapterId) return NOOP_COMMIT;
  const chapter = db
    .select()
    .from(schema.chapters)
    .where(
      and(
        eq(schema.chapters.id, payload.chapterId),
        eq(schema.chapters.userId, event.userId),
        isNull(schema.chapters.deletedAt)
      )
    )
    .get();
  if (!chapter) return NOOP_COMMIT;

  // For now, chapter_created/updated just produces a daily-style overview brief.
  // Real use: trigger a "you might be missing something" check.
  const context = [
    `A chapter has just been ${event.type === "chapter_created" ? "created" : "updated"}: ${chapter.title}.`,
    `Type: ${chapter.type}, status: ${chapter.status}, range: ${chapter.startDate ?? "—"} → ${chapter.endDate ?? "—"}.`,
    chapter.purpose ? `Purpose: ${chapter.purpose}` : "",
    "",
    "Consider whether this chapter needs an opening brief, a few extracted todos, or just an acknowledgement. Use chapter_query to see what's already in it.",
  ].join("\n");

  const result = await runAgent(context, { userId: event.userId });
  return (eventId) =>
    persistAgentResult(result, {
      chapterId: chapter.id,
      generatedByEventId: eventId,
      userId: event.userId,
    });
}

async function prepareSignalReceived(event: schema.Event): Promise<EventCommit> {
  // §4.c connector backpressure: a single signal_received event may coalesce
  // several freshly-ingested signals into ONE agent context (one run, not one
  // run per signal). Falls back to the single-signal payload for older rows.
  const payload = event.payload as { signalId?: string; signalIds?: string[] };
  const ids = payload.signalIds ?? (payload.signalId ? [payload.signalId] : []);
  if (ids.length === 0) return NOOP_COMMIT;

  const signals = ids
    .map((id) =>
      db
        .select()
        .from(schema.signals)
        .where(
          and(
            eq(schema.signals.id, id),
            eq(schema.signals.userId, event.userId),
            isNull(schema.signals.deletedAt)
          )
        )
        .get()
    )
    .filter((s): s is schema.Signal => !!s);
  if (signals.length === 0) return NOOP_COMMIT;

  const context = [
    `${signals.length === 1 ? "A new signal arrived" : `${signals.length} new signals arrived`}.`,
    ...signals.map(
      (s) =>
        `- source=${s.source}, summary=${s.summary ?? "(none)"}, raw=${JSON.stringify(s.rawData).slice(0, 1200)}`,
    ),
    "",
    "Decide what (if anything) these signals warrant. Most signals should produce zero or one small proposals. Some — a meeting on the calendar within the next 24h, a deadline confirmation — should produce a Brief. Coalesce related signals into a single brief where it makes sense.",
  ].join("\n");

  const result = await runAgent(context, { userId: event.userId });
  return (eventId) => {
    persistAgentResult(result, { generatedByEventId: eventId, userId: event.userId });
    // CRITICAL (§4.c.1): mark the signals processed in the SAME txn as the
    // brief insert. Doing it in a separate statement re-briefs the same signal
    // if the worker crashes in between. The queue runs this whole closure in
    // one transaction, so the brief + the processed flag commit atomically.
    const now = new Date().toISOString();
    for (const s of signals) {
      db.update(schema.signals)
        .set({ processed: true, updatedAt: now })
        .where(eq(schema.signals.id, s.id))
        .run();
    }
  };
}

async function prepareWatcherDue(event: schema.Event): Promise<EventCommit> {
  const payload = event.payload as { watcherId?: string };
  if (!payload.watcherId) return NOOP_COMMIT;
  const watcher = db
    .select()
    .from(schema.watchers)
    .where(
      and(
        eq(schema.watchers.id, payload.watcherId),
        eq(schema.watchers.userId, event.userId),
        isNull(schema.watchers.deletedAt)
      )
    )
    .get();
  if (!watcher) return NOOP_COMMIT;

  const context = [
    "A watcher has come due.",
    `Description: ${watcher.description}`,
    `Prompt: ${watcher.prompt}`,
    watcher.chapterId ? `Chapter: ${watcher.chapterId}` : "",
    "",
    "Re-check the source. If you find something worth surfacing, produce a brief or a proposal. If nothing changed, return an empty brief structure with a one-line tactical note acknowledging the check.",
  ].join("\n");

  const result = await runAgent(context, { userId: event.userId });
  return (eventId) => {
    persistAgentResult(result, {
      chapterId: watcher.chapterId,
      generatedByEventId: eventId,
      userId: event.userId,
    });
    // Reschedule the next check in the SAME txn — so a crash can't both file
    // the brief and leave the watcher un-rescheduled (it would re-fire forever).
    const now = new Date().toISOString();
    const next = new Date(Date.now() + watcher.cadenceMinutes * 60 * 1000).toISOString();
    db.update(schema.watchers)
      .set({ lastChecked: now, nextCheck: next, updatedAt: now })
      .where(eq(schema.watchers.id, watcher.id))
      .run();
  };
}

async function prepareDailyScan(event: schema.Event): Promise<EventCommit> {
  // Read active chapters + signals from last 24h; ask agent for a "Briefs for
  // today" pass that may produce 0..N briefs across chapters. Scoped to the
  // event's owner, live rows only (§4.d/§4.f).
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const recentSignals = db
    .select()
    .from(schema.signals)
    .where(and(eq(schema.signals.userId, event.userId), isNull(schema.signals.deletedAt)))
    .all()
    .filter((s) => s.arrivedAt >= since);
  const activeChapters = db
    .select()
    .from(schema.chapters)
    .where(and(eq(schema.chapters.userId, event.userId), isNull(schema.chapters.deletedAt)))
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

  const result = await runAgent(context, { userId: event.userId });
  return (eventId) =>
    persistAgentResult(result, { generatedByEventId: eventId, userId: event.userId });
}

async function prepareForwardDriftScan(event: schema.Event): Promise<EventCommit> {
  // §4.c / Phase 1: the forward-drift scan looks PAST the next 24h — at upcoming
  // chapters and standing commitments that need preparation started now (a trip
  // in three weeks with nothing booked, a deadline whose lead time is closing).
  const upcoming = db
    .select()
    .from(schema.chapters)
    .where(and(eq(schema.chapters.userId, event.userId), isNull(schema.chapters.deletedAt)))
    .all()
    .filter((c) => c.status === "upcoming" || c.status === "active");

  const context = [
    "Forward-drift scan (weekly). Look BEYOND the next 24 hours.",
    `Today is ${new Date().toISOString().slice(0, 10)}.`,
    "",
    "Active & upcoming chapters:",
    ...upcoming.map(
      (c) => `  - ${c.id} · ${c.title} · ${c.status} · ${c.startDate ?? "—"} → ${c.endDate ?? "—"}`,
    ),
    "",
    "For each chapter whose preparation should START now to avoid a last-minute scramble (lead time closing, an upcoming trip/launch with open loops), produce a brief and/or a few proposals or a watcher to track it. If everything is comfortably on track, emit a single tiny brief titled 'Nothing drifting' with one tactical line and zero proposals.",
  ].join("\n");

  const result = await runAgent(context, { userId: event.userId });
  return (eventId) =>
    persistAgentResult(result, { generatedByEventId: eventId, userId: event.userId });
}

async function prepareTimeTrigger(event: schema.Event): Promise<EventCommit> {
  // §4.c / Phase 1: a scheduled point-in-time nudge (e.g. "T-2h before a
  // meeting"). The payload carries the reason and optional chapter; the agent
  // decides whether the moment warrants a brief.
  const payload = event.payload as { reason?: string; chapterId?: string | null };
  const reason = (payload.reason ?? "").trim();
  if (!reason) return NOOP_COMMIT;

  const chapter = payload.chapterId
    ? db
        .select()
        .from(schema.chapters)
        .where(
          and(
            eq(schema.chapters.id, payload.chapterId),
            eq(schema.chapters.userId, event.userId),
            isNull(schema.chapters.deletedAt)
          )
        )
        .get()
    : null;

  const context = [
    "A scheduled time-trigger fired.",
    `Reason: ${reason}`,
    `Now: ${new Date().toISOString()}`,
    chapter ? `Chapter: ${chapter.id} · ${chapter.title} · ${chapter.status}` : "Chapter: unspecified.",
    "",
    "Decide whether this moment warrants a brief or a small proposal (e.g. last-minute prep for an imminent situation). If nothing is needed, return an empty brief structure with a one-line acknowledgement.",
  ].join("\n");

  const result = await runAgent(context, { userId: event.userId });
  return (eventId) =>
    persistAgentResult(result, {
      chapterId: payload.chapterId ?? null,
      generatedByEventId: eventId,
      userId: event.userId,
    });
}

/**
 * §4.a/§4.b: the grounded one-shot Ask, enqueued by `ai.ask` and drained HERE so
 * the gateway's in-memory token bucket stays authoritative (only the worker calls
 * messages.create). Builds the same grounded prompt the legacy inline `ai.ask`
 * built, routes it through the gateway as `route:'one_shot'` (Haiku), and writes
 * the answer into `events.result` so the client's `event.status(jobId)` poll
 * reads `{ answer, resultProposalIds }` on `done`.
 *
 * The await (gateway call) happens in this prepare phase; the returned commit only
 * writes `events.result`. queue.ts runs that commit + markDone in ONE txn, so the
 * answer and the `done` status commit atomically — a crash before the txn leaves
 * the row `processing` for the watchdog to requeue (and the gateway call re-runs).
 */
async function prepareAiAsk(event: schema.Event): Promise<EventCommit> {
  const payload = event.payload as {
    query?: string;
    scope?: string | null;
    context?: string | null;
    history?: Array<{ role: "user" | "atlas"; text: string }>;
  };
  const query = (payload.query ?? "").trim();
  if (!query) {
    // Nothing to ask — record an empty answer so the client poll resolves.
    return (eventId) =>
      writeEventResult(eventId, { answer: "", resultProposalIds: [] });
  }

  const scope = payload.scope ?? null;
  const context = payload.context ?? null;
  const history = payload.history ?? [];

  const historyText = history
    .map((t) => `${t.role === "user" ? "User" : "Atlas"}: ${t.text}`)
    .join("\n");

  const groundingBlock = context
    ? `\n\nGrounding (what I know that's relevant):\n"""\n${context.slice(0, ASK_MAX_CONTEXT_CHARS)}\n"""`
    : "";

  const userMessage = `You are Atlas, a quiet personal AI assistant answering a grounded question.${
    scope ? `\n\nScope: ${scope}` : ""
  }${groundingBlock}

Conversation so far:
${historyText || "(none)"}
User: ${query}

Reply as Atlas. Rules:
- 2-5 sentences. Quiet, conversational, no exclamation marks.
- Ground every claim in what you actually know above; if you don't know, say so plainly.
- Never say "Great question" or anything performative.
- You may add italic-serif emphasis using *asterisks*.

Reply:`;

  let answer: string;
  try {
    const response = await createMessage(
      {
        route: "one_shot",
        messages: [{ role: "user", content: userMessage }],
        maxTokens: ASK_MAX_OUTPUT_TOKENS,
      },
      { userId: event.userId },
    );
    answer = response.content
      .filter((b): b is Extract<(typeof response.content)[number], { type: "text" }> => b.type === "text")
      .map((b) => b.text)
      .join("\n")
      .trim();
  } catch (err) {
    // Surface a quiet, in-voice fallback as the answer rather than failing the
    // event — the user asked a question and should always get a reply back.
    const messageText = (err as Error).message ?? "unknown error";
    answer = `I lost the thread for a moment — *${messageText.slice(0, 120)}*. Try again?`;
  }

  return (eventId) => writeEventResult(eventId, { answer, resultProposalIds: [] });
}

/** Caps for the capture co-completion prompt (mirror the router's input cap). */
const CAPTURE_MAX_FRAGMENT_CHARS = 4_000;

/**
 * Capture co-completion (PART 1 / Module MC), enqueued by `capture.complete` and
 * drained HERE so only the worker touches the gateway — the same single-bucket
 * discipline as `ai_ask` (§4.a/§4.b). Routes the fragment through the gateway as
 * `route:'one_shot'` (Haiku, for low latency), producing (a) a GHOST completion of
 * the fragment into a full structured note and (b) a CLASSIFICATION — kind +
 * best-matching chapter + a single low-confidence clarifying question.
 *
 * The result `{ghost,kind,chapterId,question,confidence}` is written to
 * `events.result`; the router polls `events.status` and returns it to the well.
 * The gateway caches CAPTURE_SYSTEM (the byte-stable instructions + JSON
 * contract), so every capture after the first is a cache_read — only the fragment
 * and the user's live chapter list (the per-call variation) ride in the user
 * message. max_tokens is small (ghost + tiny JSON), keeping latency reasonable.
 */
async function prepareCaptureComplete(event: schema.Event): Promise<EventCommit> {
  const payload = event.payload as { fragment?: string; scope?: string | null };
  const fragment = (payload.fragment ?? "").trim().slice(0, CAPTURE_MAX_FRAGMENT_CHARS);
  const scope = (payload.scope ?? null)?.slice(0, CAPTURE_MAX_FRAGMENT_CHARS) ?? null;

  // An empty fragment can't be completed — return a calm auto-file default so the
  // well's poll resolves immediately rather than spending a token.
  if (!fragment) {
    return (eventId) => writeCaptureResult(eventId, EMPTY_CAPTURE_RESULT);
  }

  // The user's live chapters give the classifier its chapterId candidates —
  // scoped to this event's owner, live rows only (§4.d/§4.f).
  const chapters: CaptureChapter[] = db
    .select({
      id: schema.chapters.id,
      title: schema.chapters.title,
      status: schema.chapters.status,
    })
    .from(schema.chapters)
    .where(and(eq(schema.chapters.userId, event.userId), isNull(schema.chapters.deletedAt)))
    .all();
  const validChapterIds = new Set(chapters.map((c) => c.id));

  const userMessage = buildCaptureUserMessage({ fragment, scope, chapters });

  let result: CaptureCompletionResult;
  try {
    const response = await createMessage(
      {
        route: "one_shot",
        system: CAPTURE_SYSTEM,
        messages: [{ role: "user", content: userMessage }],
        maxTokens: CAPTURE_MAX_OUTPUT_TOKENS,
      },
      { userId: event.userId },
    );
    const raw = response.content
      .filter((b): b is Extract<(typeof response.content)[number], { type: "text" }> => b.type === "text")
      .map((b) => b.text)
      .join("\n")
      .trim();
    // Defend against one-shot JSON drift / a hallucinated chapterId; fall back to a
    // calm auto-file note so the well always settles rather than hanging.
    result = parseCaptureCompletion(raw, validChapterIds) ?? EMPTY_CAPTURE_RESULT;
  } catch {
    // A gateway/budget/circuit failure must not break the capture surface — the
    // user can still file the fragment as a plain note. Return the safe default.
    result = EMPTY_CAPTURE_RESULT;
  }

  return (eventId) => writeCaptureResult(eventId, result);
}

/**
 * The deterministic fallback completion — an empty ghost (so the well shows the
 * user's own text untouched) auto-filed as a top-level note. Used when the
 * fragment is empty, the model output can't be parsed, or the gateway errors.
 */
const EMPTY_CAPTURE_RESULT: CaptureCompletionResult = {
  ghost: "",
  kind: "note",
  chapterId: null,
  question: null,
  confidence: 0.3,
};

/**
 * Write a capture co-completion result into `events.result`. Synchronous: runs
 * inside the queue's commit txn so the result + `status='done'` commit atomically
 * (a crash before the txn leaves the row `processing` for the watchdog to requeue,
 * and the gateway call re-runs). The well reads this off `events.status`.
 */
function writeCaptureResult(eventId: string, result: CaptureCompletionResult): void {
  db.update(schema.events)
    .set({ result, updatedAt: new Date().toISOString() })
    .where(eq(schema.events.id, eventId))
    .run();
}

/**
 * Write an Ask job's result into `events.result`. A one-shot grounded Ask is
 * read-only (it produces no proposals), so `resultProposalIds` is always `[]` —
 * the field is kept so the client's job-result shape is uniform with capture
 * jobs (which DO populate it). Synchronous: runs inside the queue's commit txn.
 */
function writeEventResult(
  eventId: string,
  result: { answer: string; resultProposalIds: string[] },
): void {
  db.update(schema.events)
    .set({ result, updatedAt: new Date().toISOString() })
    .where(eq(schema.events.id, eventId))
    .run();
}

function countBySource(rows: schema.Signal[]): string {
  const buckets: Record<string, number> = {};
  for (const r of rows) buckets[r.source] = (buckets[r.source] ?? 0) + 1;
  return Object.entries(buckets).map(([k, v]) => `${k}=${v}`).join(", ");
}
