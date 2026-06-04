/**
 * POST /api/ask — short conversational reply from Atlas, used by AskAtlas
 * inside the web Morning Page. A one-shot grounded chat (no tool loop).
 *
 * SERVER_ARCHITECTURE.md §4.b (cross-process single-bucket, ship-blocker): the
 * gateway's triple-token bucket is an in-memory JS object and the gateway links
 * into BOTH the Next.js process and the worker process. Two processes can't
 * share an in-memory bucket, so calling `messages.create` from BOTH would admit
 * ~85% each → ~170% combined against the shared Haiku org pool and re-breach the
 * org RPM/ITPM/OTPM limit. (The shared `usage_ledger` only caps per-user DAILY
 * token spend — it does NOT bound the org-wide rate the buckets exist to protect.)
 *
 * Resolution (spec §4.b, line 166): make Anthropic calls single-process. This
 * route NO LONGER calls the gateway inline. Exactly like the `ai.ask` tRPC
 * procedure, it ENQUEUES an `ai_ask` `one_shot` job (an `events` row) that ONLY
 * the worker drains through the single gateway/bucket. Because the web client
 * (AskAtlas.tsx) awaits one synchronous fetch and expects `{ reply }`, this
 * handler then polls `events.status(jobId)` server-side — the same DB-backed
 * submit→poll→read loop Capture/Ask already run — and returns the answer once the
 * worker marks the job `done`. No process outside the worker calls Anthropic.
 *
 * SERVER_ARCHITECTURE.md §4.a hardening (still enforced): Anthropic-touching, so
 * a valid device token is required (NO fail-open) and every prompt-feeding field
 * is Zod-validated and size-capped BEFORE a job is enqueued — otherwise it's a
 * public token-burn hole. Budget is charged to the resolved userId by the worker.
 *
 * Falls back to a deterministic stub when ANTHROPIC_API_KEY is missing so the
 * typing-stream animation still runs end-to-end in dev (the worker's `ai_ask`
 * drain produces the same in-voice fallback when the key is absent, but the web
 * Morning Page may run without a worker in dev, so we short-circuit here too).
 */
import { NextResponse } from "next/server";
import { z } from "zod";
import { randomUUID } from "node:crypto";
import { and, eq } from "drizzle-orm";
import { db } from "@/db/client";
import { events } from "@/db/schema";
import { extractBearer, resolveUserIdFromToken } from "@/server/auth";

/** Size caps (§4.a): bound every field that feeds the prompt before we enqueue. */
const MAX_MESSAGE_CHARS = 4_000;
const MAX_CONTEXT_CHARS = 4_000;
const MAX_HISTORY_TURNS = 20;
const MAX_HISTORY_TURN_CHARS = 2_000;

/** Server-side poll loop for the enqueued job (mirrors the client submit→poll→read). */
const POLL_INTERVAL_MS = 250;
const POLL_TIMEOUT_MS = 60_000;

const HistoryTurn = z.object({
  role: z.enum(["user", "atlas"]),
  text: z.string().max(MAX_HISTORY_TURN_CHARS),
});

const AskInput = z.object({
  // The morning page Atlas is replying about. Sliced, then capped.
  context: z.string().max(MAX_CONTEXT_CHARS * 4).default(""),
  message: z.string().trim().min(1).max(MAX_MESSAGE_CHARS),
  history: z.array(HistoryTurn).max(MAX_HISTORY_TURNS).optional(),
});

/** The shape the worker writes into `events.result` for an `ai_ask` job. */
interface AskResult {
  answer: string;
  resultProposalIds: string[];
}

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

export async function POST(req: Request) {
  // 0) Auth (§4.a hardening): this endpoint is Anthropic-touching and requires a
  // valid device token. NO fail-open — an absent/unknown/revoked token is rejected
  // with 401 BEFORE we enqueue a job, and the per-user/day budget is charged (by
  // the worker) to the resolved userId, not a shared bootstrap id.
  const userId = resolveUserIdFromToken(extractBearer(req.headers.get("authorization")));
  if (!userId) {
    return NextResponse.json({ error: "missing or invalid device token" }, { status: 401 });
  }

  // 1) Parse + validate. Reject oversized/malformed input BEFORE enqueueing.
  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid JSON body" }, { status: 400 });
  }

  const parsed = AskInput.safeParse(raw);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "invalid input", issues: parsed.error.flatten() },
      { status: 400 },
    );
  }
  const { context, message, history } = parsed.data;

  // 2) No key → deterministic stub (keeps the typing-stream working in dev even
  // when no worker is running to drain the job).
  if (!process.env.ANTHROPIC_API_KEY) {
    return NextResponse.json({
      reply:
        "I'm running without a key right now — the typing stream is working but I don't have anything thoughtful to say. Add ANTHROPIC_API_KEY to *.env* and ask again.",
    });
  }

  // 3) Enqueue an `ai_ask` one_shot job — IDENTICAL to the `ai.ask` tRPC path.
  // Only the worker drains it through the single gateway/bucket. The validated,
  // bounded request travels in the payload; the worker (prepareAiAsk) builds the
  // grounded prompt and calls the gateway as `route:'one_shot'` (Haiku). The web
  // Morning Page's `message`/`context` map to the worker's `query`/`context`.
  const jobId = randomUUID();
  db.insert(events)
    .values({
      id: jobId,
      userId,
      type: "ai_ask",
      payload: {
        query: message,
        scope: null,
        context: context.slice(0, MAX_CONTEXT_CHARS) || null,
        history: history ?? [],
      },
      updatedAt: new Date().toISOString(),
    })
    .run();

  // 4) Poll the job to completion server-side so the existing web client (which
  // awaits one synchronous fetch and expects `{ reply }`) is unchanged. Scoped to
  // the resolved userId — a device only reads the status of events it emitted.
  const deadline = Date.now() + POLL_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const row = db
      .select({ status: events.status, error: events.error, result: events.result })
      .from(events)
      .where(and(eq(events.id, jobId), eq(events.userId, userId)))
      .get();

    if (row?.status === "done") {
      const result = (row.result ?? null) as AskResult | null;
      return NextResponse.json({ reply: (result?.answer ?? "").trim() });
    }
    if (row?.status === "failed") {
      const errText = (row.error ?? "the worker couldn't answer").slice(0, 120);
      return NextResponse.json({
        reply: `I lost the thread for a moment — *${errText}*. Try again?`,
      });
    }
    await sleep(POLL_INTERVAL_MS);
  }

  // 5) Timed out waiting for the worker. Return an in-voice fallback rather than a
  // hard error; the job may still complete and be visible on a later poll.
  return NextResponse.json({
    reply: "I'm taking longer than usual to think this through — *give me a moment and ask again?*",
  });
}
