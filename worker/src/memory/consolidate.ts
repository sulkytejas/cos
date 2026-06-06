/**
 * Consolidate — memory layer Phase 2.2 (W3): keeping the notebook clean.
 *
 * Each draft is held against the existing notes about the same people. Four
 * outcomes: ADD (new — keep it), REINFORCE (already known — the old note gets
 * stronger), SUPERSEDE (contradicts an old note — write the new one, end-date
 * the old one, never delete), DROP (noise). Plus the resurrection guard: a
 * draft that re-states a STRUCK note is DROPPED — being told to forget is
 * itself remembered (the fix for ChatGPT's cancelled-trip-keeps-returning bug).
 *
 * Split per §4.c: `reconcile` (the AI judgment) runs in the prepare phase with
 * NO writes; `applyDecisions` is synchronous better-sqlite3 work the event
 * commit runs inside ONE transaction — a crash rolls the whole night back and
 * the requeued event re-runs cleanly. No partial state, no cleanup pass.
 */
import { randomUUID } from "node:crypto";
import { and, eq, inArray, isNull } from "drizzle-orm";
import { db, schema } from "../db";
import { createMessage } from "../../../src/server/anthropic/gateway";
import { bareId, parseModelJson, type DraftNote } from "./extract";

const CONSOLIDATE_MAX_OUTPUT_TOKENS = 800;

export type ConsolidateAction = "add" | "reinforce" | "supersede" | "drop";

export interface Decision {
  draft: DraftNote;
  action: ConsolidateAction;
  /** The existing note this reinforces / supersedes. */
  targetNoteId: string | null;
}

const CONSOLIDATE_SYSTEM = `You reconcile freshly drafted notes against an existing notebook. For EACH draft, decide exactly one action:

- "add"        — genuinely new information. No existing note covers it.
- "reinforce"  — an existing LIVING note already says this (same meaning, any wording). Name that note's id as target.
- "supersede"  — it CONTRADICTS an existing living note (the world changed). Name the contradicted note's id as target.
- "drop"       — noise, trivia, a duplicate of another draft in this same batch, or a re-statement of a STRUCK or SUPERSEDED note (the user chose to forget those — they must not come back).

Be conservative: when unsure between add and reinforce, prefer reinforce; when unsure between add and drop for trivia, prefer drop.

Output ONLY JSON: {"decisions":[{"draft_index":0,"action":"add|reinforce|supersede|drop","target_note_id":"..or null"}]} — one entry per draft, in order.`;

/** Existing notes that share a handle with any draft — the comparison set. */
function comparisonSet(userId: string, drafts: DraftNote[]) {
  const handles = [...new Set(drafts.flatMap((d) => d.about))];
  let ids: string[] = [];
  if (handles.length > 0) {
    ids = [
      ...new Set(
        db
          .select({ observationId: schema.observationAbout.observationId })
          .from(schema.observationAbout)
          .where(
            and(
              eq(schema.observationAbout.userId, userId),
              inArray(schema.observationAbout.handle, handles),
            ),
          )
          .all()
          .map((r) => r.observationId),
      ),
    ];
  }
  const rows = ids.length
    ? db
        .select()
        .from(schema.observations)
        .where(and(inArray(schema.observations.id, ids), isNull(schema.observations.deletedAt)))
        .all()
    : [];
  const living = rows.filter((o) => !o.invalidatedAt && !o.struckAt && o.kind !== "prediction");
  const dead = rows.filter((o) => o.invalidatedAt || o.struckAt);
  return { living, dead };
}

/**
 * Phase 1 (prepare, no writes): hold the drafts against the notebook and get a
 * decision per draft. Unparseable model output degrades to ADD-all — worst
 * case the notebook gains a duplicate that next night's reinforce collapses.
 */
export async function reconcile(userId: string, drafts: DraftNote[]): Promise<Decision[]> {
  if (drafts.length === 0) return [];
  const { living, dead } = comparisonSet(userId, drafts);

  // Nothing to compare against → everything is an ADD; skip the model call.
  if (living.length === 0 && dead.length === 0) {
    return drafts.map((draft) => ({ draft, action: "add" as const, targetNoteId: null }));
  }

  const user = [
    "DRAFTS:",
    ...drafts.map((d, i) => `${i}. [${d.kind}] ${d.body} (about: ${d.about.join(", ") || "—"})`),
    "",
    "EXISTING LIVING NOTES:",
    ...living.map((o) => `- ${o.id} [${o.kind}, ×${o.weight}] ${o.body}`),
    "",
    "DEAD NOTES (struck or superseded — drafts repeating these get dropped):",
    ...dead.map((o) => `- ${o.id} [${o.struckAt ? "STRUCK" : "superseded"}] ${o.body}`),
  ].join("\n");

  const response = await createMessage(
    {
      route: "one_shot",
      system: CONSOLIDATE_SYSTEM,
      messages: [{ role: "user", content: user }],
      maxTokens: CONSOLIDATE_MAX_OUTPUT_TOKENS,
    },
    { userId },
  );
  const text = response.content
    .filter((b): b is Extract<(typeof response.content)[number], { type: "text" }> => b.type === "text")
    .map((b) => b.text)
    .join("\n");

  const parsed = parseModelJson<{
    decisions?: Array<{ draft_index?: number; action?: string; target_note_id?: string | null }>;
  }>(text);

  const livingIds = new Set(living.map((o) => o.id));
  return drafts.map((draft, i) => {
    const d = parsed?.decisions?.find((x) => x.draft_index === i);
    let action = (["add", "reinforce", "supersede", "drop"] as const).includes(
      d?.action as ConsolidateAction,
    )
      ? (d!.action as ConsolidateAction)
      : ("add" as const);
    let targetNoteId = typeof d?.target_note_id === "string" ? bareId(d.target_note_id) : null;
    // A reinforce/supersede must point at a real living note, else degrade to add.
    if ((action === "reinforce" || action === "supersede") && (!targetNoteId || !livingIds.has(targetNoteId))) {
      action = "add";
      targetNoteId = null;
    }
    return { draft, action, targetNoteId };
  });
}

export interface ApplyStats {
  added: number;
  reinforced: number;
  superseded: number;
  dropped: number;
  addedIds: string[];
}

/**
 * Phase 2 (commit, synchronous): write the reconciled outcome. Runs inside the
 * event's single transaction (with markDone), so the night either fully
 * happened or fully didn't.
 */
export function applyDecisions(
  userId: string,
  decisions: Decision[],
  generatedByEventId: string,
): ApplyStats {
  const now = new Date().toISOString();
  const stats: ApplyStats = { added: 0, reinforced: 0, superseded: 0, dropped: 0, addedIds: [] };

  const insertNote = (draft: DraftNote): string => {
    const id = randomUUID();
    db.insert(schema.observations)
      .values({
        id,
        userId,
        body: draft.body,
        kind: draft.kind,
        source: draft.source,
        confidence: draft.confidence,
        receipts: draft.receipts,
        firstSeenAt: now,
        lastSeenAt: now,
        weight: 1,
        generatedByEventId,
        updatedAt: now,
      })
      .run();
    for (const handle of new Set(draft.about)) {
      db.insert(schema.observationAbout)
        .values({ userId, observationId: id, handle })
        .onConflictDoNothing()
        .run();
    }
    return id;
  };

  for (const { draft, action, targetNoteId } of decisions) {
    switch (action) {
      case "add": {
        stats.addedIds.push(insertNote(draft));
        stats.added++;
        break;
      }
      case "reinforce": {
        const existing = db
          .select()
          .from(schema.observations)
          .where(eq(schema.observations.id, targetNoteId!))
          .get();
        if (!existing) break;
        const receipts = [...new Set([...(existing.receipts ?? []), ...draft.receipts])];
        db.update(schema.observations)
          .set({
            weight: existing.weight + 1,
            lastSeenAt: now,
            receipts,
            updatedAt: now,
          })
          .where(eq(schema.observations.id, existing.id))
          .run();
        stats.reinforced++;
        break;
      }
      case "supersede": {
        const newId = insertNote(draft);
        db.update(schema.observations)
          .set({ invalidatedAt: now, supersededById: newId, updatedAt: now })
          .where(eq(schema.observations.id, targetNoteId!))
          .run();
        stats.addedIds.push(newId);
        stats.superseded++;
        break;
      }
      case "drop":
        stats.dropped++;
        break;
    }
  }
  return stats;
}

/**
 * Memory v2 (slice P) credit assignment — outcomes flow back along a
 * prediction's `basedOnIds`. Confirmed → backing notes REINFORCE (a successful
 * prediction is evidence the beliefs were right). Refuted → they weaken
 * (weight floor 1; the rehearsal decides if we need harsher correction).
 * Synchronous; runs in the same commit transaction as the resolution write.
 */
export function applyPredictionOutcome(
  userId: string,
  basedOnIds: string[],
  outcome: "confirmed" | "refuted",
): void {
  if (basedOnIds.length === 0) return;
  const now = new Date().toISOString();
  const notes = db
    .select()
    .from(schema.observations)
    .where(
      and(
        inArray(schema.observations.id, basedOnIds),
        eq(schema.observations.userId, userId),
        isNull(schema.observations.deletedAt),
      ),
    )
    .all();
  for (const n of notes) {
    if (n.kind === "prediction") continue;
    db.update(schema.observations)
      .set({
        weight: outcome === "confirmed" ? n.weight + 1 : Math.max(1, n.weight - 1),
        lastSeenAt: outcome === "confirmed" ? now : n.lastSeenAt,
        updatedAt: now,
      })
      .where(eq(schema.observations.id, n.id))
      .run();
  }
}
