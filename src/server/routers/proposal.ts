import { z } from "zod";
import { and, desc, eq, isNull } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, protectedProcedure } from "../trpc";
import { db } from "@/db/client";
import {
  proposals,
  proposalTypes,
  todos,
  decisions,
  entries,
  chapterLinks,
} from "@/db/schema";

const proposalTypeEnum = z.enum(proposalTypes);

/**
 * Proposal router (§4.d/§4.f) — review-queue UI reads from here, all scoped to
 * `ctx.userId` with `deletedAt IS NULL`. Approving writes the payload into the
 * real table (todos / decisions / entries / links), stamped with the same
 * `userId`, and marks the proposal `approved`.
 *
 * §4.d push-idempotency: `approve` is transition-guarded — the proposal only
 * transitions `pending → approved` if it is currently `pending` (and owned by
 * the caller); `writePayload` runs only when a row actually transitioned, inside
 * the same transaction. An at-least-once outbox retry therefore cannot double-
 * file a todo/decision/entry.
 */
export const proposalRouter = router({
  /**
   * All pending proposals, plus today's filed ones (so the queue can show
   * "Atlas filed:" history at top).
   */
  forReview: protectedProcedure
    .input(z.object({ type: proposalTypeEnum.optional() }).optional())
    .query(({ input, ctx }) => {
      const todayStart = new Date();
      todayStart.setHours(0, 0, 0, 0);
      const cutoff = todayStart.toISOString();

      const where = input?.type
        ? and(
            eq(proposals.userId, ctx.userId),
            isNull(proposals.deletedAt),
            eq(proposals.type, input.type)
          )
        : and(eq(proposals.userId, ctx.userId), isNull(proposals.deletedAt));

      const rows = db
        .select()
        .from(proposals)
        .where(where)
        .orderBy(desc(proposals.createdAt))
        .all();

      // Split into "pending" (asked) and "filed today" (approved high-confidence)
      const pending = rows.filter((r) => r.status === "pending");
      const filedToday = rows.filter(
        (r) => r.status === "approved" && r.decidedAt && r.decidedAt >= cutoff
      );
      return { pending, filedToday };
    }),

  // Count of pending — used in nav badges and the "handled while you slept" stat.
  countsForToday: protectedProcedure.query(({ ctx }) => {
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const cutoff = todayStart.toISOString();

    const all = db
      .select({ status: proposals.status, decidedAt: proposals.decidedAt, type: proposals.type })
      .from(proposals)
      .where(and(eq(proposals.userId, ctx.userId), isNull(proposals.deletedAt)))
      .all();
    const pending = all.filter((r) => r.status === "pending").length;
    const filedToday = all.filter((r) => r.status === "approved" && r.decidedAt && r.decidedAt >= cutoff);
    const filedByType: Record<string, number> = {};
    for (const r of filedToday) {
      filedByType[r.type] = (filedByType[r.type] ?? 0) + 1;
    }
    return { pending, filedToday: filedToday.length, filedByType };
  }),

  /**
   * Approve a proposal — writes its payload into the canonical table.
   * For voice-memo-style two-option proposals, the user picks an option
   * via `chosenValue`; that picks which canonical table to write into.
   */
  approve: protectedProcedure
    .input(
      z.object({
        id: z.string(),
        chosenValue: z.string().optional(),
        editedPayload: z.unknown().optional(),
      })
    )
    .mutation(({ input, ctx }) => {
      const now = new Date().toISOString();
      return db.transaction((tx) => {
        const row = tx
          .select()
          .from(proposals)
          .where(
            and(eq(proposals.id, input.id), eq(proposals.userId, ctx.userId), isNull(proposals.deletedAt))
          )
          .get();
        if (!row) throw new Error("proposal not found");

        // Transition-guard (§4.d): only act if this is the pending → approved
        // edge. A retry that arrives after the first approve is a no-op, so
        // writePayload can never double-file.
        if (row.status !== "pending") return { ok: true, alreadyDecided: true as const };

        const payload =
          (input.editedPayload as Record<string, unknown> | undefined) ??
          (row.proposedPayload as Record<string, unknown>);

        // What type are we writing? For "asked"-style proposals (with options),
        // the user's chosen value determines the destination type. Otherwise,
        // use proposal.type.
        let resolvedType: string = row.type;
        if (input.chosenValue && row.options) {
          const opts = row.options as Array<{ value: string; type?: string }>;
          const opt = opts.find((o) => o.value === input.chosenValue);
          if (opt?.type) resolvedType = opt.type;
          else resolvedType = input.chosenValue;
        }

        const transitioned = tx
          .update(proposals)
          .set({ status: "approved", decidedAt: now, updatedAt: now, decidedPayload: payload })
          .where(and(eq(proposals.id, input.id), eq(proposals.status, "pending")))
          .run();

        // Only fan out the payload if THIS call won the transition.
        if (transitioned.changes > 0) {
          writePayload(tx, ctx.userId, resolvedType, payload, row.chapterId, row.id);
        }
        return { ok: true };
      });
    }),

  dismiss: protectedProcedure.input(z.string()).mutation(({ input, ctx }) => {
    const now = new Date().toISOString();
    db.update(proposals)
      .set({ status: "dismissed", decidedAt: now, updatedAt: now })
      .where(and(eq(proposals.id, input), eq(proposals.userId, ctx.userId), isNull(proposals.deletedAt)))
      .run();
    return { ok: true };
  }),
});

/** The transaction handle drizzle hands the `db.transaction((tx) => …)` callback. */
type Tx = Parameters<Parameters<typeof db.transaction>[0]>[0];

/**
 * Write the approved payload into the right canonical table, scoped to `userId`.
 * Centralized so we keep the conversion logic in one place. Runs inside the
 * approve transaction (the `tx` handle) so the proposal transition and the
 * canonical insert commit atomically.
 *
 * §4.d push-idempotency: each canonical insert stamps `sourceProposalId` and
 * carries a bare `ON CONFLICT DO NOTHING` (the unique index is *partial* —
 * `WHERE source_proposal_id IS NOT NULL` — so a named conflict target wouldn't
 * match; the bare form matches any constraint). This is belt-and-suspenders with
 * the transition-guard above: even if a transition somehow re-ran, the unique
 * `sourceProposalId` collapses the canonical write to a single row, so an
 * at-least-once outbox retry can never double-file.
 */
function writePayload(
  tx: Tx,
  userId: string,
  type: string,
  payload: Record<string, unknown>,
  chapterId: string | null,
  proposalId: string
) {
  const now = new Date().toISOString();
  switch (type) {
    case "todo": {
      tx.insert(todos)
        .values({
          id: randomUUID(),
          userId,
          chapterId: chapterId ?? (payload.chapterId as string),
          text: payload.text as string,
          dueDate: (payload.dueDate as string | undefined) ?? null,
          source: "extracted",
          sourceBriefId: (payload.sourceBriefId as string | undefined) ?? null,
          sourceSignalIds: (payload.sourceSignalIds as string[] | undefined) ?? null,
          sourceProposalId: proposalId,
          updatedAt: now,
        })
        .onConflictDoNothing()
        .run();
      return;
    }
    case "decision": {
      tx.insert(decisions)
        .values({
          id: randomUUID(),
          userId,
          chapterId: chapterId ?? (payload.chapterId as string),
          title: payload.title as string,
          rationale: (payload.rationale as string | undefined) ?? null,
          optionsConsidered: (payload.optionsConsidered as string | undefined) ?? null,
          decidedAt: (payload.decidedAt as string | undefined) ?? now,
          source: "extracted",
          sourceProposalId: proposalId,
          updatedAt: now,
        })
        .onConflictDoNothing()
        .run();
      return;
    }
    case "journal_entry":
    case "journal": {
      tx.insert(entries)
        .values({
          id: randomUUID(),
          userId,
          chapterId: chapterId ?? (payload.chapterId as string),
          date: (payload.date as string | undefined) ?? now,
          content: payload.content as string,
          source: (payload.source as never) ?? "manual",
          sourceProposalId: proposalId,
          updatedAt: now,
        })
        .onConflictDoNothing()
        .run();
      return;
    }
    case "chapter_link": {
      tx.insert(chapterLinks)
        .values({
          userId,
          fromId: payload.fromId as string,
          toId: payload.toId as string,
          relation: (payload.relation as never) ?? "related",
          note: (payload.note as string | undefined) ?? null,
          proposed: false,
          updatedAt: now,
          deletedAt: null,
        })
        .onConflictDoUpdate({
          target: [chapterLinks.fromId, chapterLinks.toId, chapterLinks.relation],
          set: {
            note: (payload.note as string | undefined) ?? null,
            proposed: false,
            updatedAt: now,
            deletedAt: null,
          },
        })
        .run();
      return;
    }
    // "finding"/"signal"/"noise" — these are passive disposition outcomes
    // for medium-confidence voice memos. They don't write to a canonical
    // table; the proposal status alone records the decision.
    default:
      // log nothing; the decided_at field on the proposal is the record.
      return;
  }
}
