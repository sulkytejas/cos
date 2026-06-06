import { z } from "zod";
import { and, eq, isNull } from "drizzle-orm";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import { turns, proposals } from "@/db/schema";

/**
 * Turn router (Today agentic flow v1, §4.d/§4.f).
 *
 * The morning turn's `memo` is the redline surface: in Review the user strikes
 * the lines that don't matter (teaching her what to stop surfacing) and then
 * "keeps" the memo. Both mutations are scoped to `ctx.userId` with
 * `deletedAt IS NULL`, bump `updatedAt` so the edit rides the delta-sync cursor
 * back to the mirror, and are idempotent under an at-least-once outbox retry.
 */
export const turnRouter = router({
  /**
   * Strike (or un-strike) one memo line. Striking a line that references a
   * still-`pending` proposal also dismisses that proposal — the gesture says
   * "this doesn't matter," which is the same disposition as dismissing the
   * underlying proposal. Runs in a transaction so the memo patch and the
   * proposal dismissal commit atomically (mirrors proposal.approve's
   * transition-guard discipline: the proposal only moves `pending → dismissed`).
   */
  strike: protectedProcedure
    .input(z.object({ turnId: z.string(), lineId: z.string(), struck: z.boolean() }))
    .mutation(({ input, ctx }) => {
      const now = new Date().toISOString();
      return db.transaction((tx) => {
        const turn = tx
          .select()
          .from(turns)
          .where(
            and(eq(turns.id, input.turnId), eq(turns.userId, ctx.userId), isNull(turns.deletedAt))
          )
          .get();
        if (!turn) throw new Error("turn not found");
        if (!turn.memo) throw new Error("turn has no memo");

        const memo = turn.memo;
        const line = memo.lines.find((l) => l.id === input.lineId);
        if (!line) throw new Error("memo line not found");

        line.struck = input.struck;

        // Striking a proposal-ref line dismisses the underlying proposal — only
        // on the `pending → dismissed` edge (a retry / an already-decided
        // proposal is a no-op), so an outbox replay can never re-stamp it.
        if (input.struck && line.refKind === "proposal" && line.refId) {
          tx.update(proposals)
            .set({ status: "dismissed", decidedAt: now, updatedAt: now })
            .where(
              and(
                eq(proposals.id, line.refId),
                eq(proposals.userId, ctx.userId),
                eq(proposals.status, "pending"),
                isNull(proposals.deletedAt)
              )
            )
            .run();
        }

        tx.update(turns)
          .set({ memo, updatedAt: now })
          .where(and(eq(turns.id, input.turnId), eq(turns.userId, ctx.userId)))
          .run();

        return { ok: true };
      });
    }),

  /**
   * Keep the memo — flips its status `draft → kept`, stamping who/when. Idempotent:
   * an already-kept memo returns ok without re-stamping. Bumps `updatedAt` so the
   * collapsed "kept" card syncs to the mirror.
   */
  keep: protectedProcedure
    .input(z.object({ turnId: z.string() }))
    .mutation(({ input, ctx }) => {
      const now = new Date().toISOString();
      return db.transaction((tx) => {
        const turn = tx
          .select()
          .from(turns)
          .where(
            and(eq(turns.id, input.turnId), eq(turns.userId, ctx.userId), isNull(turns.deletedAt))
          )
          .get();
        if (!turn) throw new Error("turn not found");
        if (!turn.memo) throw new Error("turn has no memo");

        // Idempotent: already kept → no-op (don't re-stamp keptAt/keptBy).
        if (turn.memo.status === "kept") return { ok: true };

        const memo = { ...turn.memo, status: "kept" as const, keptAt: now, keptBy: "user" as const };
        tx.update(turns)
          .set({ memo, updatedAt: now })
          .where(and(eq(turns.id, input.turnId), eq(turns.userId, ctx.userId)))
          .run();

        return { ok: true };
      });
    }),
});
