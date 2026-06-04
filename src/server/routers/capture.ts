import { z } from "zod";
import { randomUUID } from "node:crypto";
import { and, eq } from "drizzle-orm";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import { events } from "@/db/schema";

/**
 * Capture router (v0.7 — co-completion) — SCAFFOLD STUB.
 *
 * Backs the global "well" sheet summoned from any screen (design handoff PART 1).
 * The user hands Ayumi a *fragment*; she completes it into a structured note and
 * files it. This router exposes the two halves of that loop:
 *
 *  - `complete({ fragment })` → `{ ghost, kind, chapterId?, question? }`
 *    The streaming-ghost + classifier step. The client renders `ghost` as the
 *    italic remainder of the fragment and `kind`/`chapterId` as the forming tag.
 *    `question` is set ONLY when confidence is low (the one-question card).
 *
 *  - `file({ ... })` → `{ ok, id }`
 *    Commits the completed fragment as a note/todo/decision under a chapter.
 *
 * Anthropic choke-point note (§4.b cross-process single-bucket fix): real
 * co-completion is a gateway call (src/server/anthropic/gateway.ts,
 * `route:'one_shot'`, Haiku) plus a lightweight kind/chapter classifier — and the
 * gateway's in-memory token bucket is authoritative ONLY in the worker process.
 * So `complete()` does NOT call the gateway inline in Next.js (that would re-breach
 * the org limit). It ENQUEUES a `capture_complete` `one_shot` job the WORKER drains
 * (mirroring `ai.ask` / `/api/ask`), then polls `events.status` server-side and
 * returns the parsed `{ghost,kind,chapterId,question,confidence}`. Only the worker
 * ever touches Anthropic; the app NEVER calls it directly.
 */

/** What Ayumi is forming the fragment into. Mirrors the prototype's tag kinds. */
const captureKindEnum = z.enum(["todo", "decision", "note"]);

const MAX_FRAGMENT_CHARS = 4_000;

/** Server-side poll loop for the enqueued completion job (mirrors /api/ask). */
const POLL_INTERVAL_MS = 120;
const POLL_TIMEOUT_MS = 20_000;

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/**
 * The completion shape the well consumes. `ghost` is the suggested remainder,
 * `kind` the forming tag's kind, `chapterId` the inferred home chapter (null when
 * she'd auto-file), `question` the single low-confidence clarifier (or null), and
 * `confidence` (0..1) drives whether the well settles the tag or asks.
 */
const CaptureCompletion = z.object({
  ghost: z.string(),
  kind: captureKindEnum,
  chapterId: z.string().nullable(),
  question: z
    .object({
      text: z.string(),
      answers: z.array(z.string()),
    })
    .nullable(),
  confidence: z.number().min(0).max(1),
});

type CaptureCompletionT = z.infer<typeof CaptureCompletion>;

/**
 * The calm, deterministic completion returned when there's no worker/key to drain
 * the job, the worker fails, or the poll times out. An empty ghost (the well shows
 * the user's own text untouched) auto-filed as a top-level note — so the surface
 * never hangs and the user can always file the fragment as-is.
 */
const FALLBACK_COMPLETION: CaptureCompletionT = {
  ghost: "",
  kind: "note",
  chapterId: null,
  question: null,
  confidence: 0.3,
};

export const captureRouter = router({
  /**
   * Co-completion: ghost-complete a fragment into a structure (Module MC).
   *
   * Enqueues a `capture_complete` `one_shot` job (only the worker calls the
   * gateway — §4.b) and polls `events.status` server-side so the well awaits one
   * call and gets the structured result back, exactly like `ai.ask`/`/api/ask`.
   * The worker produces a GHOST completion + a kind/chapter classification, and
   * populates `question` only when its confidence is low. On no key / no worker /
   * timeout, returns a calm auto-file fallback so the well always settles.
   */
  complete: protectedProcedure
    .input(
      z.object({
        fragment: z.string().trim().min(1).max(MAX_FRAGMENT_CHARS),
        /** Optional screen the well was summoned over (grounding hint). */
        scope: z.string().max(MAX_FRAGMENT_CHARS).optional(),
      })
    )
    .mutation(async ({ input, ctx }): Promise<CaptureCompletionT> => {
      // No key → the worker's drain can't reach Anthropic; skip the round-trip and
      // return the calm fallback so the well renders offline (dev parity).
      if (!process.env.ANTHROPIC_API_KEY) return FALLBACK_COMPLETION;

      // Enqueue the completion job. Only the worker drains it through the single
      // gateway/bucket; the validated, bounded fragment travels in the payload.
      const jobId = randomUUID();
      db.insert(events)
        .values({
          id: jobId,
          userId: ctx.userId,
          type: "capture_complete",
          payload: { fragment: input.fragment, scope: input.scope ?? null },
          updatedAt: new Date().toISOString(),
        })
        .run();

      // Poll the job to completion server-side so the client awaits one call. The
      // worker writes the parsed result into `events.result` in the commit txn.
      const deadline = Date.now() + POLL_TIMEOUT_MS;
      while (Date.now() < deadline) {
        const row = db
          .select({ status: events.status, result: events.result })
          .from(events)
          .where(and(eq(events.id, jobId), eq(events.userId, ctx.userId)))
          .get();

        if (row?.status === "done") {
          // Validate the worker-written result; on any drift, settle with the
          // fallback rather than surfacing a malformed completion to the well.
          const parsed = CaptureCompletion.safeParse(row.result);
          return parsed.success ? parsed.data : FALLBACK_COMPLETION;
        }
        if (row?.status === "failed") return FALLBACK_COMPLETION;
        await sleep(POLL_INTERVAL_MS);
      }
      // Timed out — return the fallback so the surface settles; the job may still
      // complete and be a no-op (its result is read only by this poll).
      return FALLBACK_COMPLETION;
    }),

  /**
   * File the completed fragment as a captured item (STUB).
   *
   * Emits a `capture_received` event the worker drains into the right todo/
   * decision/note row (and re-classifies if `kind`/`chapterId` were left to
   * Ayumi). Returns the minted id so the client reconciles its optimistic
   * "Kept." row.
   */
  file: protectedProcedure
    .input(
      z.object({
        text: z.string().trim().min(1).max(MAX_FRAGMENT_CHARS),
        kind: captureKindEnum.default("note"),
        chapterId: z.string().nullable().optional(),
        /** The answer the user picked on the one-question card, if any. */
        answer: z.string().max(MAX_FRAGMENT_CHARS).optional(),
        /** `text` = typed/edited, `voice` = spoken duet (settle/hands-free). */
        source: z.enum(["text", "voice"]).default("text"),
      })
    )
    .mutation(({ input, ctx }) => {
      const id = randomUUID();
      db.insert(events)
        .values({
          id,
          userId: ctx.userId,
          type: "capture_received",
          payload: {
            text: input.text,
            kind: input.kind,
            chapterId: input.chapterId ?? null,
            answer: input.answer ?? null,
            source: input.source,
          },
          updatedAt: new Date().toISOString(),
        })
        .run();
      return { ok: true as const, id };
    }),
});
