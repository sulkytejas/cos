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
import { randomUUID } from "node:crypto";
import { db, schema } from "../db";
import { runAgent } from "../agent/loop";
import { persistAgentResult } from "../persist";
import { getDigestBody, rebuildDigest } from "../memory/digest";
import { setDesk } from "../memory/desk";
import { gatherMaterial, extractDrafts } from "../memory/extract";
import { reconcile, applyDecisions } from "../memory/consolidate";
import { draftPredictions } from "../memory/predict";
import { resolveDuePredictions, applyResolutions } from "../memory/resolve";
import { createMessage } from "../../../src/server/anthropic/gateway";
import {
  CAPTURE_SYSTEM,
  CAPTURE_MAX_OUTPUT_TOKENS,
  buildCaptureUserMessage,
  parseCaptureCompletion,
  type CaptureChapter,
  type CaptureCompletionResult,
} from "../../../src/server/anthropic/capture-prompt";
import { and, eq, inArray, isNull, ne } from "drizzle-orm";

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
    case "memory_consolidate":
      return prepareMemoryConsolidate(event);
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
    "",
    // This is a chapter touch — emit the advisory palette + missing_modules.
    "Also emit `palette` (this is a chapter touch): the vocabulary of component kinds from the library this chapter's life will need — advisory, not a template. And emit `missing_modules`: any named modules you wish existed for this chapter, each with a one-line `spec`.",
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

  // The overnight window the morning turn covers ("while you slept" divider): the
  // [min,max] of the last-24h signals' arrival times. With no overnight signal,
  // fall back to a six-hour pre-scan window so the divider still reads sensibly.
  const scanTime = new Date();
  const window = computeOvernightWindow(recentSignals, scanTime);

  // (a) Lines the user struck on recent morning turns — a negative-signal context
  // so the agent doesn't resurface dispositions the user has already told it don't
  // matter. Live morning turns from the last 7 days, struck lines only.
  const struckSince = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const recentMorningTurns = db
    .select()
    .from(schema.turns)
    .where(
      and(
        eq(schema.turns.userId, event.userId),
        eq(schema.turns.kind, "morning"),
        isNull(schema.turns.deletedAt),
      ),
    )
    .all()
    .filter((t) => t.createdAt >= struckSince);
  const struckLines = recentMorningTurns.flatMap((t) =>
    (t.memo?.lines ?? []).filter((l) => l.struck).map((l) => l.text),
  );

  // (b) Connector gaps — which of [gmail, calendar, drive] have NO active grant.
  // The agent may suggest AT MOST ONE via day_memo.connector, and only when a
  // concrete gap was observed in tonight's signals (the prompt enforces this).
  const activeConnectors = db
    .select()
    .from(schema.connectorAccounts)
    .where(
      and(
        eq(schema.connectorAccounts.userId, event.userId),
        eq(schema.connectorAccounts.status, "active"),
        isNull(schema.connectorAccounts.deletedAt),
      ),
    )
    .all();
  const connectedSources = new Set(activeConnectors.map((c) => c.source));
  const unconnected = (["gmail", "calendar", "drive"] as const).filter(
    (s) => !connectedSources.has(s),
  );

  // (c) Memory layer (build plan 3.2 + 4.1): the cheat sheet is ALWAYS in hand —
  // never searched for — and the desk is set with the top living notes about
  // whoever shows up in today's calendar / overnight email, receipts included.
  // Plain indexed reads (~2ms), done BEFORE the AI call starts, never during.
  const digest = getDigestBody(event.userId);
  const desk = setDesk(event.userId, recentSignals, scanTime);

  const context = [
    "Daily scan. Examine the active chapters and signals from the last 24 hours.",
    `Today is ${new Date().toISOString().slice(0, 10)}.`,
    "",
    digest
      ? `Your cheat sheet — what you've learned so far, kept short. Let it shape the plan (e.g. real meeting lengths, what a person tends to push on):\n"""\n${digest}\n"""\n`
      : "",
    desk ? `${desk}\n` : "",
    "Active chapters:",
    // Each chapter carries its advisory palette (the vocabulary of component kinds
    // this chapter's life tends to need) so the scan reasons in the right idiom.
    ...activeChapters.map(
      (c) =>
        `  - ${c.id} · ${c.title} · ${c.status}${
          c.palette && c.palette.length ? ` · palette: ${c.palette.join(", ")}` : ""
        }`,
    ),
    "",
    `Recent signals (count by source): ${countBySource(recentSignals)}`,
    "",
    struckLines.length
      ? `Lines the user struck recently — do not resurface similar items:\n${struckLines
          .map((t) => `- ${t}`)
          .join("\n")}\n`
      : "",
    unconnected.length
      ? `Sources not connected: ${unconnected.join(", ")}. Suggest at most ONE via day_memo.connector IF a concrete gap was observed in tonight's signals; otherwise omit.\n`
      : "",
    "Produce briefs for situations that deserve preparation in the next 24 hours. If nothing warrants a brief, emit a single tiny brief titled 'A quiet day' with one tactical line and zero proposals.",
    "Also emit day_memo (this is a daily scan).",
  ]
    .filter((line) => line !== "")
    .join("\n");

  const result = await runAgent(context, { userId: event.userId });
  return (eventId) => {
    // Pass the morning turn-kind + window so persist composes the Today thread's
    // morning turn from `day_memo` (verdict + redlineable memo + connector).
    persistAgentResult(result, {
      generatedByEventId: eventId,
      userId: event.userId,
      turnKind: "morning",
      window,
    });
    // Auto-seal yesterday's unresolved morning drafts: every live morning turn
    // still in `draft` from before today's local midnight is sealed `kept` by
    // 'auto' — a stale draft the user never opened shouldn't stay redlineable, and
    // sealing it preserves its lines as the agent's record of that night. Runs in
    // the SAME commit txn as the new turn insert, so today's scan and yesterday's
    // seal commit atomically.
    sealStaleMorningDrafts(event.userId);

    // Memory layer 2.3: the morning work just finished — queue the nightly
    // memory pass (extract → consolidate → predict/resolve → digest). The
    // dedupeKey collapses it to ONE per LOCAL day no matter how many scans run
    // (local, not UTC — a midnight-IST scan must not collide with yesterday's
    // UTC bucket); same txn as the turn insert, so the learning job exists iff
    // the morning did.
    const d = new Date();
    const pad = (n: number) => String(n).padStart(2, "0");
    const day = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
    db.insert(schema.events)
      .values({
        id: randomUUID(),
        userId: event.userId,
        type: "memory_consolidate",
        payload: {},
        dedupeKey: `memory_consolidate:${day}`,
        updatedAt: new Date().toISOString(),
      })
      .onConflictDoNothing()
      .run();
  };
}

/**
 * The nightly memory pass — memory layer W2–W4 + Memory v2 slice P, one job:
 *
 *   1. RESOLVE  — predictions whose date passed get judged against the signals
 *                 that actually arrived; outcomes teach the notes that made
 *                 them (credit assignment along basedOnIds).
 *   2. EXTRACT  — draft candidate notes from what the day brought (in-memory
 *                 only; a draft with no receipts is thrown away on principle).
 *   3. CONSOLIDATE — hold drafts against the notebook: ADD / REINFORCE /
 *                 SUPERSEDE / DROP, with the resurrection guard (struck notes
 *                 stay forgotten).
 *   4. PREDICT  — write tonight's falsifiable bets (numeric confidence,
 *                 basedOn pointers, resolve-by dates).
 *   5. DIGEST   — rebuild the one-page cheat sheet from the strongest living
 *                 notes (+ open expectations + the calibration line).
 *
 * §4.c discipline: every AI call happens HERE in prepare (no writes); the
 * returned commit is pure synchronous better-sqlite3 work that queue.ts runs
 * in ONE transaction with markDone — a crash rolls the whole night back and
 * the requeued event re-runs cleanly. No partial learning, ever.
 */
async function prepareMemoryConsolidate(event: schema.Event): Promise<EventCommit> {
  const now = new Date();

  // 1 · resolve (AI judgment only — writes happen in commit)
  const resolutions = await resolveDuePredictions(event.userId, now);

  // 2 · extract
  const material = gatherMaterial(event.userId, now);
  const drafts = await extractDrafts(event.userId, material);

  // 3 · consolidate (judgment)
  const decisions = await reconcile(event.userId, drafts);

  // 4 · predict (uses pre-commit notebook state; next night sees tonight's writes)
  const predictions = await draftPredictions(event.userId, now);

  return (eventId) => {
    const settled = applyResolutions(event.userId, resolutions);
    const stats = applyDecisions(event.userId, decisions, eventId);
    for (const row of predictions.rows) {
      db.insert(schema.observations)
        .values({ ...row, generatedByEventId: eventId })
        .run();
    }
    for (const about of predictions.aboutRows) {
      db.insert(schema.observationAbout).values(about).onConflictDoNothing().run();
    }
    rebuildDigest(event.userId);
    // The night's ledger, inspectable via event.status / the events table.
    writeEventResult(eventId, {
      noted: stats.added,
      reinforced: stats.reinforced,
      superseded: stats.superseded,
      dropped: stats.dropped,
      predictionsMade: predictions.rows.length,
      predictionsSettled: settled,
    });
    console.log(
      `[memory] night done — +${stats.added} noted, ${stats.reinforced} reinforced, ` +
        `${stats.superseded} superseded, ${stats.dropped} dropped · ` +
        `${predictions.rows.length} predictions made, ${settled} settled`,
    );
  };
}

/**
 * Compute the overnight window ("while you slept") as [min,max] of the last-24h
 * signals' arrival times. With no overnight signal there's no real span, so fall
 * back to a six-hour pre-scan window ending at the scan time.
 */
function computeOvernightWindow(
  signals: schema.Signal[],
  scanTime: Date,
): { start: string; end: string } {
  if (signals.length === 0) {
    return {
      start: new Date(scanTime.getTime() - 6 * 60 * 60 * 1000).toISOString(),
      end: scanTime.toISOString(),
    };
  }
  let min = signals[0].arrivedAt;
  let max = signals[0].arrivedAt;
  for (const s of signals) {
    if (s.arrivedAt < min) min = s.arrivedAt;
    if (s.arrivedAt > max) max = s.arrivedAt;
  }
  return { start: min, end: max };
}

/**
 * Seal stale morning drafts (Today agentic flow v1). A morning turn left in
 * `draft` from before today's LOCAL midnight is sealed `kept` by 'auto' — the
 * user moved on without redlining it, so it stops being editable but keeps its
 * lines as the night's record. Synchronous: runs inside the daily-scan commit txn.
 */
function sealStaleMorningDrafts(userId: string): void {
  const localMidnight = new Date();
  localMidnight.setHours(0, 0, 0, 0);
  const cutoff = localMidnight.toISOString();
  const now = new Date().toISOString();
  const stale = db
    .select()
    .from(schema.turns)
    .where(
      and(
        eq(schema.turns.userId, userId),
        eq(schema.turns.kind, "morning"),
        isNull(schema.turns.deletedAt),
      ),
    )
    .all()
    .filter((t) => t.memo?.status === "draft" && t.createdAt < cutoff);
  for (const t of stale) {
    if (!t.memo) continue;
    db.update(schema.turns)
      .set({
        memo: { ...t.memo, status: "kept", keptBy: "auto", keptAt: now },
        updatedAt: now,
      })
      .where(eq(schema.turns.id, t.id))
      .run();
  }
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

  // Memory layer 3.2: the Q&A flow starts with the cheat sheet in the prompt,
  // same as the morning run — a chief of staff who waits to be asked isn't one.
  const digest = getDigestBody(event.userId);
  const digestBlock = digest
    ? `\n\nYour cheat sheet (what you've learned about the user's world — use it where relevant):\n"""\n${digest}\n"""`
    : "";

  // Memory layer 4.3: names in the question get matched to contact cards, and
  // their living notes come along before the answer — same desk-setting as the
  // morning run, triggered by the question's own words.
  const mentioned = db
    .select()
    .from(schema.people)
    .where(and(eq(schema.people.userId, event.userId), isNull(schema.people.deletedAt)))
    .all()
    .filter((p) => {
      const q = query.toLowerCase();
      const first = p.canonicalName.toLowerCase().split(/\s+/)[0];
      return (
        (first.length >= 3 && q.includes(first)) ||
        (p.handles ?? []).some((h) => h.includes("@") && q.includes(h.toLowerCase()))
      );
    });
  let notesBlock = "";
  if (mentioned.length > 0) {
    const handles = [...new Set(mentioned.flatMap((p) => (p.handles ?? []).map((h) => h.toLowerCase())))];
    const aboutRows = handles.length
      ? db
          .select({ observationId: schema.observationAbout.observationId })
          .from(schema.observationAbout)
          .where(
            and(
              eq(schema.observationAbout.userId, event.userId),
              inArray(schema.observationAbout.handle, handles),
            ),
          )
          .all()
      : [];
    const ids = [...new Set(aboutRows.map((r) => r.observationId))];
    if (ids.length > 0) {
      const notes = db
        .select()
        .from(schema.observations)
        .where(
          and(
            inArray(schema.observations.id, ids),
            ne(schema.observations.kind, "prediction"),
            isNull(schema.observations.deletedAt),
            isNull(schema.observations.invalidatedAt),
            isNull(schema.observations.struckAt),
          ),
        )
        .all()
        .sort((a, b) => b.weight - a.weight || b.lastSeenAt.localeCompare(a.lastSeenAt))
        .slice(0, 10);
      if (notes.length > 0) {
        notesBlock =
          `\n\nYour notes on the people named in the question:\n` +
          notes.map((n) => `- ${n.body} (seen ×${n.weight})`).join("\n");
      }
    }
  }

  const userMessage = `You are Atlas, a quiet personal AI assistant answering a grounded question.${
    scope ? `\n\nScope: ${scope}` : ""
  }${digestBlock}${notesBlock}${groundingBlock}

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
  result:
    | { answer: string; resultProposalIds: string[] }
    // The nightly memory pass writes its ledger here instead (inspectable
    // via the events table / event.status) — same column, different shape.
    | {
        noted: number;
        reinforced: number;
        superseded: number;
        dropped: number;
        predictionsMade: number;
        predictionsSettled: number;
      },
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
