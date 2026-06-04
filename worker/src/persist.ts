/**
 * Persistence — writes the agent's output to the database. Validates the
 * brief structure against the shared Zod schema; rejects with status=failed
 * if invalid.
 */
import { randomUUID } from "node:crypto";
import { db, schema } from "./db";
import { BOOTSTRAP_USER_ID } from "../../src/db/schema";
import type { AgentResult, AgentTraceEntry, BriefOutput } from "./agent/loop";
import { BriefStructure } from "../../src/lib/brief-schema";

export interface PersistedBrief {
  briefId: string | null;
  proposalIds: string[];
  watcherIds: string[];
}

/** Confidence threshold above which a proposal is filed immediately. */
const FILE_THRESHOLD = 0.85;

/**
 * Persist the agent's output (§4.d/§4.f). Every row is stamped with the owning
 * `userId` (defaulting to the single-tenant bootstrap operator) and a fresh
 * `updatedAt`, so the API's per-user reads and a future cursor-by-`updatedAt`
 * sync see worker-written rows correctly.
 */
export function persistAgentResult(
  result: AgentResult,
  opts: {
    chapterId?: string | null;
    generatedByEventId?: string | null;
    userId?: string;
  } = {}
): PersistedBrief {
  const userId = opts.userId ?? BOOTSTRAP_USER_ID;
  if (!result.brief) {
    return { briefId: null, proposalIds: [], watcherIds: [] };
  }
  const o = result.brief;

  // 1) Validate structure
  const structureValidation = BriefStructure.safeParse(o.structure);
  const structure = structureValidation.success
    ? structureValidation.data
    : { sections: [] };

  // 2) Write the brief
  const briefId = randomUUID();
  const now = new Date().toISOString();
  const surfaceAt = now;
  const expiresAt = new Date(Date.now() + 72 * 60 * 60 * 1000).toISOString();

  db.insert(schema.briefs)
    .values({
      id: briefId,
      userId,
      chapterId: opts.chapterId ?? o.chapter_id ?? null,
      title: o.title ?? "Untitled brief",
      situationDescription: o.situation ?? "",
      structure,
      primaryAction: o.primary_action ?? null,
      secondaryActions: o.secondary_actions ?? null,
      status: structureValidation.success ? "surfaced" : "failed",
      surfaceAt,
      expiresAt,
      chapterTitle: o.chapter_title ?? null,
      relevance: o.relevance ?? null,
      when: o.when ?? null,
      drafted: o.preview ? `drafted ${new Date().toISOString().slice(11, 16)}` : null,
      preview: o.preview ?? null,
      agentTrace: {
        trace: result.trace as unknown,
        raw: result.raw,
        error: result.error ?? null,
        validation: structureValidation.success ? "ok" : structureValidation.error.flatten(),
      },
      generatedByEventId: opts.generatedByEventId ?? null,
      updatedAt: now,
    })
    .run();

  // 3) Write proposals — high-confidence ones land approved immediately
  const proposalIds: string[] = [];
  for (const p of o.proposals ?? []) {
    const pid = randomUUID();
    const isFiled = p.confidence >= FILE_THRESHOLD && !p.question;
    db.insert(schema.proposals)
      .values({
        id: pid,
        userId,
        type: (p.type ?? "todo") as schema.ProposalType,
        proposedPayload: p.payload as unknown,
        sourceBriefId: briefId,
        sourceSignalIds: null,
        chapterId: p.chapter_id ?? null,
        status: isFiled ? "approved" : "pending",
        confidence: p.confidence ?? 0.5,
        reasoning: p.reasoning ?? null,
        summary: p.summary ?? null,
        sourceLabel: p.source_label ?? null,
        sourceMeta: p.source_meta ?? null,
        question: p.question ?? null,
        setup: p.setup ?? null,
        options: p.options ?? null,
        decidedAt: isFiled ? now : null,
        decidedPayload: isFiled ? p.payload : null,
        generatedByEventId: opts.generatedByEventId ?? null,
        updatedAt: now,
      })
      .run();
    proposalIds.push(pid);

    // If filed, also write the payload into the canonical table now. Stamp the
    // proposal id (pid) so the canonical row is idempotent (§4.d): a crash-
    // recovery re-run of this event can't double-file the same todo/decision/
    // entry — the unique `sourceProposalId` collapses it via ON CONFLICT.
    if (isFiled) writePayload(userId, p.type, p.payload, p.chapter_id ?? null, briefId, pid);
  }

  // 4) Write watchers
  const watcherIds: string[] = [];
  for (const w of o.watchers_to_create ?? []) {
    const wid = randomUUID();
    const nextCheck = new Date(
      Date.now() + (w.cadence_minutes ?? 180) * 60 * 1000
    ).toISOString();
    db.insert(schema.watchers)
      .values({
        id: wid,
        userId,
        chapterId: w.chapter_id ?? null,
        description: w.description,
        prompt: w.prompt,
        sourceType: (w.source_type ?? "internal") as schema.WatcherSourceType,
        nextCheck,
        cadenceMinutes: w.cadence_minutes ?? 180,
        cadenceLabel: w.cadence_label ?? null,
        status: "active",
        updatedAt: now,
      })
      .run();
    watcherIds.push(wid);
  }

  return { briefId, proposalIds, watcherIds };
}

/** Same canonical-write logic as the proposal router. Kept duplicated rather than
 * shared because worker and web are separate processes / different import roots.
 * Stamps the owning `userId` and `updatedAt` on every row (§4.d/§4.f). */
function writePayload(
  userId: string,
  type: string,
  payload: Record<string, unknown>,
  chapterId: string | null,
  briefId: string,
  proposalId: string
) {
  const cid = chapterId ?? (payload.chapterId as string | undefined);
  if (!cid) return;
  const now = new Date().toISOString();
  // §4.d: stamp `sourceProposalId` + bare `ON CONFLICT DO NOTHING` (the unique
  // index is partial, so a named target wouldn't match) so a crash-recovery
  // re-run of the generating event can't double-file the canonical row.
  switch (type) {
    case "todo":
      db.insert(schema.todos)
        .values({
          id: randomUUID(),
          userId,
          chapterId: cid,
          text: payload.text as string,
          dueDate: (payload.dueDate as string | undefined) ?? null,
          source: "extracted",
          sourceBriefId: briefId,
          sourceProposalId: proposalId,
          updatedAt: now,
        })
        .onConflictDoNothing()
        .run();
      return;
    case "decision":
      db.insert(schema.decisions)
        .values({
          id: randomUUID(),
          userId,
          chapterId: cid,
          title: payload.title as string,
          rationale: (payload.rationale as string | undefined) ?? null,
          decidedAt: (payload.decidedAt as string | undefined) ?? now,
          source: "extracted",
          sourceBriefId: briefId,
          sourceProposalId: proposalId,
          updatedAt: now,
        })
        .onConflictDoNothing()
        .run();
      return;
    case "journal_entry":
    case "journal":
      db.insert(schema.entries)
        .values({
          id: randomUUID(),
          userId,
          chapterId: cid,
          date: (payload.date as string | undefined) ?? now,
          content: payload.content as string,
          source: (payload.source as never) ?? "manual",
          sourceBriefId: briefId,
          sourceProposalId: proposalId,
          updatedAt: now,
        })
        .onConflictDoNothing()
        .run();
      return;
    default:
      return;
  }
}
