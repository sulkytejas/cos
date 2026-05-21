import { z } from "zod";
import { router, publicProcedure } from "../trpc";
import { db } from "@/db/client";
import { chapters, todos, decisions, entries } from "@/db/schema";
import { SEEDED_MORNING_PAGE } from "@/lib/morning-page";
import { randomUUID } from "node:crypto";

/**
 * Morning page router — exposes the latest morning page and the
 * "Send to chapters" filing action.
 */
export const morningRouter = router({
  latest: publicProcedure.query(() => {
    return SEEDED_MORNING_PAGE;
  }),

  /**
   * File the unstruck sentences' extracts into their target chapters
   * as todos / decisions / journal entries. Returns counts so the UI
   * can render the Filed confirmation.
   */
  filed: publicProcedure
    .input(
      z.object({
        sentences: z.array(
          z.object({
            id: z.string(),
            text: z.string(),
            chapter: z.string().nullable(),
            extracts: z
              .object({
                todo: z.number().optional(),
                decision: z.number().optional(),
                journal: z.number().optional(),
              })
              .nullable(),
          })
        ),
      })
    )
    .mutation(({ input }) => {
      const allChapters = db.select({ id: chapters.id, title: chapters.title }).from(chapters).all();
      const findChapterId = (hint: string | null): string | null => {
        if (!hint) return null;
        const match = allChapters.find((c) => c.title.toLowerCase().includes(hint.toLowerCase()));
        return match?.id ?? null;
      };

      const counts = { todo: 0, decision: 0, journal: 0 };

      for (const s of input.sentences) {
        if (!s.extracts) continue;
        const chapterId = findChapterId(s.chapter);
        if (!chapterId) continue;

        // The morning page is per-sentence prose. Each extract count is
        // realised as one row of the matching kind, taking the sentence text
        // as its body. This is intentionally simple — the worker is what
        // decomposes a single sentence into multiple rows in v0.3.
        for (let i = 0; i < (s.extracts.todo ?? 0); i++) {
          db.insert(todos)
            .values({
              id: randomUUID(),
              chapterId,
              text: s.text,
              source: "extracted",
            })
            .run();
          counts.todo++;
        }
        for (let i = 0; i < (s.extracts.decision ?? 0); i++) {
          db.insert(decisions)
            .values({
              id: randomUUID(),
              chapterId,
              title: s.text.slice(0, 120),
              rationale: s.text,
              decidedAt: new Date().toISOString(),
              source: "extracted",
            })
            .run();
          counts.decision++;
        }
        for (let i = 0; i < (s.extracts.journal ?? 0); i++) {
          db.insert(entries)
            .values({
              id: randomUUID(),
              chapterId,
              date: new Date().toISOString(),
              content: s.text,
              source: "manual",
            })
            .run();
          counts.journal++;
        }
      }

      return { ok: true, counts };
    }),
});
