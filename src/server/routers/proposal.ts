import { z } from "zod";
import { and, desc, eq, gte } from "drizzle-orm";
import { randomUUID } from "node:crypto";
import { router, publicProcedure } from "../trpc";
import { db } from "@/db/client";
import {
  proposals,
  proposalTypes,
  proposalStatuses,
  todos,
  decisions,
  entries,
  chapterLinks,
} from "@/db/schema";

const proposalTypeEnum = z.enum(proposalTypes);
const proposalStatusEnum = z.enum(proposalStatuses);

/**
 * Proposal router — review-queue UI reads from here. Approving a proposal
 * writes its payload into the real table (todos / decisions / entries) and
 * marks the proposal `approved`.
 */
export const proposalRouter = router({
  /**
   * All pending proposals, plus today's filed ones (so the queue can show
   * "Atlas filed:" history at top).
   */
  forReview: publicProcedure
    .input(z.object({ type: proposalTypeEnum.optional() }).optional())
    .query(({ input }) => {
      const todayStart = new Date();
      todayStart.setHours(0, 0, 0, 0);
      const cutoff = todayStart.toISOString();

      const baseWhere = input?.type
        ? and(eq(proposals.type, input.type))
        : undefined;

      const rows = db
        .select()
        .from(proposals)
        .where(baseWhere)
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
  countsForToday: publicProcedure.query(() => {
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const cutoff = todayStart.toISOString();

    const all = db.select({ status: proposals.status, decidedAt: proposals.decidedAt, type: proposals.type }).from(proposals).all();
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
  approve: publicProcedure
    .input(
      z.object({
        id: z.string(),
        chosenValue: z.string().optional(),
        editedPayload: z.unknown().optional(),
      })
    )
    .mutation(({ input }) => {
      const row = db.select().from(proposals).where(eq(proposals.id, input.id)).get();
      if (!row) throw new Error("proposal not found");
      const payload =
        (input.editedPayload as Record<string, unknown> | undefined) ??
        (row.proposedPayload as Record<string, unknown>);

      // What type are we writing?
      // For "asked"-style proposals (with options), the user's chosen value
      // determines the destination type. Otherwise, use proposal.type.
      let resolvedType: string = row.type;
      if (input.chosenValue && row.options) {
        const opts = row.options as Array<{ value: string; type?: string }>;
        const opt = opts.find((o) => o.value === input.chosenValue);
        if (opt?.type) resolvedType = opt.type;
        else resolvedType = input.chosenValue;
      }

      writePayload(resolvedType, payload, row.chapterId, row.id);

      db.update(proposals)
        .set({
          status: "approved",
          decidedAt: new Date().toISOString(),
          decidedPayload: payload,
        })
        .where(eq(proposals.id, input.id))
        .run();
      return { ok: true };
    }),

  dismiss: publicProcedure.input(z.string()).mutation(({ input }) => {
    db.update(proposals)
      .set({ status: "dismissed", decidedAt: new Date().toISOString() })
      .where(eq(proposals.id, input))
      .run();
    return { ok: true };
  }),
});

/**
 * Write the approved payload into the right canonical table.
 * Centralized so we keep the conversion logic in one place.
 */
function writePayload(
  type: string,
  payload: Record<string, unknown>,
  chapterId: string | null,
  proposalId: string
) {
  switch (type) {
    case "todo": {
      db.insert(todos)
        .values({
          id: randomUUID(),
          chapterId: chapterId ?? (payload.chapterId as string),
          text: payload.text as string,
          dueDate: (payload.dueDate as string | undefined) ?? null,
          source: "extracted",
          sourceBriefId: (payload.sourceBriefId as string | undefined) ?? null,
          sourceSignalIds: (payload.sourceSignalIds as string[] | undefined) ?? null,
        })
        .run();
      return;
    }
    case "decision": {
      db.insert(decisions)
        .values({
          id: randomUUID(),
          chapterId: chapterId ?? (payload.chapterId as string),
          title: payload.title as string,
          rationale: (payload.rationale as string | undefined) ?? null,
          optionsConsidered: (payload.optionsConsidered as string | undefined) ?? null,
          decidedAt: (payload.decidedAt as string | undefined) ?? new Date().toISOString(),
          source: "extracted",
        })
        .run();
      return;
    }
    case "journal_entry":
    case "journal": {
      db.insert(entries)
        .values({
          id: randomUUID(),
          chapterId: chapterId ?? (payload.chapterId as string),
          date: (payload.date as string | undefined) ?? new Date().toISOString(),
          content: payload.content as string,
          source: (payload.source as never) ?? "manual",
        })
        .run();
      return;
    }
    case "chapter_link": {
      db.insert(chapterLinks)
        .values({
          fromId: payload.fromId as string,
          toId: payload.toId as string,
          relation: (payload.relation as never) ?? "related",
          note: (payload.note as string | undefined) ?? null,
          proposed: false,
        })
        .onConflictDoNothing()
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
