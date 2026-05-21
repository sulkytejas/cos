/**
 * Persistence — writes the agent's output to the database. Validates the
 * brief structure against the shared Zod schema; rejects with status=failed
 * if invalid.
 */
import { randomUUID } from "node:crypto";
import { db, schema } from "./db";
import type { AgentResult, AgentTraceEntry, BriefOutput } from "./agent/loop";
import { BriefStructure } from "../../src/lib/brief-schema";

export interface PersistedBrief {
  briefId: string | null;
  proposalIds: string[];
  watcherIds: string[];
}

/** Confidence threshold above which a proposal is filed immediately. */
const FILE_THRESHOLD = 0.85;

export function persistAgentResult(
  result: AgentResult,
  opts: { chapterId?: string | null } = {}
): PersistedBrief {
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
      })
      .run();
    proposalIds.push(pid);

    // If filed, also write the payload into the canonical table now.
    if (isFiled) writePayload(p.type, p.payload, p.chapter_id ?? null, briefId);
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
        chapterId: w.chapter_id ?? null,
        description: w.description,
        prompt: w.prompt,
        sourceType: (w.source_type ?? "internal") as schema.WatcherSourceType,
        nextCheck,
        cadenceMinutes: w.cadence_minutes ?? 180,
        cadenceLabel: w.cadence_label ?? null,
        status: "active",
      })
      .run();
    watcherIds.push(wid);
  }

  return { briefId, proposalIds, watcherIds };
}

/** Same canonical-write logic as the proposal router. Kept duplicated rather than
 * shared because worker and web are separate processes / different import roots. */
function writePayload(
  type: string,
  payload: Record<string, unknown>,
  chapterId: string | null,
  briefId: string
) {
  const cid = chapterId ?? (payload.chapterId as string | undefined);
  if (!cid) return;
  switch (type) {
    case "todo":
      db.insert(schema.todos)
        .values({
          id: randomUUID(),
          chapterId: cid,
          text: payload.text as string,
          dueDate: (payload.dueDate as string | undefined) ?? null,
          source: "extracted",
          sourceBriefId: briefId,
        })
        .run();
      return;
    case "decision":
      db.insert(schema.decisions)
        .values({
          id: randomUUID(),
          chapterId: cid,
          title: payload.title as string,
          rationale: (payload.rationale as string | undefined) ?? null,
          decidedAt: (payload.decidedAt as string | undefined) ?? new Date().toISOString(),
          source: "extracted",
          sourceBriefId: briefId,
        })
        .run();
      return;
    case "journal_entry":
    case "journal":
      db.insert(schema.entries)
        .values({
          id: randomUUID(),
          chapterId: cid,
          date: (payload.date as string | undefined) ?? new Date().toISOString(),
          content: payload.content as string,
          source: (payload.source as never) ?? "manual",
          sourceBriefId: briefId,
        })
        .run();
      return;
    default:
      return;
  }
}
