import { z } from "zod";
import { randomUUID } from "node:crypto";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import { events } from "@/db/schema";

/**
 * AI router — the grounded one-shot Ask (SERVER_ARCHITECTURE.md §4.a, Search RAG).
 *
 * `ai.ask` is Anthropic-touching, so it is HARD-gated (§4.a hardening):
 *  - `protectedProcedure`: a valid device token is required. Without it this is a
 *    public token-burn endpoint. The legacy `/api/ask` raw-cast its body and let
 *    unbounded `history` through; this procedure replaces that pattern with Zod.
 *  - Zod size caps on every field that feeds the prompt: `query ≤ 4k chars`,
 *    `scope ≤ 4k chars`, `history ≤ N turns` (each turn capped), `context` sliced
 *    — all bounded BEFORE we spend a token.
 *
 * Cross-process single-bucket fix (§4.b, ship-blocker): this procedure does NOT
 * call the gateway inline. The triple-token bucket is an in-memory JS object, and
 * the gateway links into BOTH the Next.js process and the worker process — two
 * processes can't share an in-memory bucket, so calling `messages.create` from
 * both would admit ~170% combined and re-breach the org limit. Resolution: make
 * Anthropic calls single-process. `ai.ask` ENQUEUES an `ai_ask` `one_shot` job
 * (returning the event id as `jobId`); only the WORKER ever calls the gateway, so
 * its bucket stays authoritative. The client polls `event.status(jobId)` every 1s
 * (the same submit→poll→read loop Capture already runs) and, on `done`, reads the
 * answer + `resultProposalIds` off the status response's `result`.
 */

const MAX_QUERY_CHARS = 4_000;
const MAX_SCOPE_CHARS = 4_000;
const MAX_CONTEXT_CHARS = 4_000;
const MAX_HISTORY_TURNS = 20;
const MAX_HISTORY_TURN_CHARS = 2_000;

const HistoryTurn = z.object({
  role: z.enum(["user", "atlas"]),
  text: z.string().max(MAX_HISTORY_TURN_CHARS),
});

const AskInput = z.object({
  /** The user's question. Trimmed, non-empty, hard-capped. */
  query: z.string().trim().min(1).max(MAX_QUERY_CHARS),
  /** Optional grounding scope (e.g. a chapter id / title), capped. */
  scope: z.string().max(MAX_SCOPE_CHARS).optional(),
  /** Optional server-side grounding context. Capped at ingest; the worker slices
   *  to MAX_CONTEXT_CHARS before prompting. The generous outer cap (×4) tolerates
   *  a fatter client-supplied context that the worker then trims. */
  context: z.string().max(MAX_CONTEXT_CHARS * 4).optional(),
  /** Prior turns. Bounded count, each turn bounded length. */
  history: z.array(HistoryTurn).max(MAX_HISTORY_TURNS).optional(),
});

export const aiRouter = router({
  /**
   * Enqueue a grounded Ask. Returns `{ jobId }` — the id of the `ai_ask` event
   * the worker will drain through the gateway (`route:'one_shot'`, Haiku). The
   * client polls `event.status(jobId)`; the done-status response carries
   * `{ answer, resultProposalIds }` in its `result`.
   */
  ask: protectedProcedure.input(AskInput).mutation(({ input, ctx }) => {
    const jobId = randomUUID();
    db.insert(events)
      .values({
        id: jobId,
        userId: ctx.userId,
        type: "ai_ask",
        // The full validated, bounded request travels in the payload; the worker
        // builds the prompt and calls the gateway. event.emit's 16k payload cap
        // is comfortably above these field caps.
        payload: {
          query: input.query,
          scope: input.scope ?? null,
          context: input.context ?? null,
          history: input.history ?? [],
        },
        updatedAt: new Date().toISOString(),
      })
      .run();
    return { jobId };
  }),
});
