/**
 * Resolve — Memory v2 slice P: reality grades the homework.
 *
 * Each night, predictions whose `resolveBy` has passed are judged against the
 * signals that actually arrived since they were made: confirmed / refuted /
 * unresolved (no evidence either way — counted, not spun). The outcome flows
 * back along `basedOnIds` (consolidate.applyPredictionOutcome): confirmed →
 * backing notes reinforce; refuted → they weaken. Being wrong becomes raw
 * material; the calibration summary (predict.ts) keeps the score honest.
 */
import { and, eq, isNull } from "drizzle-orm";
import { db, schema } from "../db";
import { createMessage } from "../../../src/server/anthropic/gateway";
import { bareId, parseModelJson } from "./extract";
import { applyPredictionOutcome } from "./consolidate";

const RESOLVE_MAX_OUTPUT_TOKENS = 500;

const RESOLVE_SYSTEM = `You judge whether predictions came true, using ONLY the evidence signals provided.

For each prediction decide:
- "confirmed"  — a signal clearly shows it happened.
- "refuted"    — a signal clearly shows it did NOT happen, OR its resolve-by date passed and the predicted event visibly failed to occur given the evidence.
- "unresolved" — the evidence genuinely cannot settle it either way.

Be strict: no grading on a curve, no benefit of the doubt. Output ONLY JSON:
{"results":[{"id":"prediction-id","outcome":"confirmed|refuted|unresolved","why":"one short clause"}]}`;

export interface Resolution {
  prediction: schema.Observation;
  outcome: schema.ObservationOutcome;
  why: string;
}

/**
 * Prepare-phase (no writes): judge every due, unresolved prediction. Returns
 * [] when nothing is due — the common case, costing zero tokens.
 */
export async function resolveDuePredictions(
  userId: string,
  now: Date,
): Promise<Resolution[]> {
  const today = now.toISOString().slice(0, 10);
  const due = db
    .select()
    .from(schema.observations)
    .where(
      and(
        eq(schema.observations.userId, userId),
        eq(schema.observations.kind, "prediction"),
        isNull(schema.observations.deletedAt),
      ),
    )
    .all()
    .filter((o) => !o.resolvedAt && !o.struckAt && o.resolveBy !== null && o.resolveBy <= today);
  if (due.length === 0) return [];

  // Evidence: every signal that arrived since the EARLIEST due prediction was
  // made (bounded window — the judge sees what the world actually sent).
  const earliest = due.reduce((m, o) => (o.createdAt < m ? o.createdAt : m), due[0].createdAt);
  const evidence = db
    .select()
    .from(schema.signals)
    .where(and(eq(schema.signals.userId, userId), isNull(schema.signals.deletedAt)))
    .all()
    .filter((s) => s.arrivedAt >= earliest);

  const user = [
    `Today is ${today}.`,
    "",
    "PREDICTIONS DUE:",
    ...due.map((o) => `- ${o.id} · made ${o.createdAt.slice(0, 10)} · resolve by ${o.resolveBy} · stated confidence ${o.confidence} · "${o.body}"`),
    "",
    "EVIDENCE (signals since the predictions were made):",
    ...evidence.map((s) => `- ${s.arrivedAt.slice(0, 16)} · ${s.source} · ${s.summary ?? ""} · ${JSON.stringify(s.rawData).slice(0, 240)}`),
    evidence.length === 0 ? "(none arrived)" : "",
  ].join("\n");

  const response = await createMessage(
    {
      route: "one_shot",
      system: RESOLVE_SYSTEM,
      messages: [{ role: "user", content: user }],
      maxTokens: RESOLVE_MAX_OUTPUT_TOKENS,
    },
    { userId },
  );
  const text = response.content
    .filter((b): b is Extract<(typeof response.content)[number], { type: "text" }> => b.type === "text")
    .map((b) => b.text)
    .join("\n");

  const parsed = parseModelJson<{
    results?: Array<{ id?: string; outcome?: string; why?: string }>;
  }>(text);

  return due.map((prediction) => {
    const r = parsed?.results?.find((x) => typeof x.id === "string" && bareId(x.id) === prediction.id);
    const outcome = (schema.observationOutcomes as readonly string[]).includes(String(r?.outcome))
      ? (r!.outcome as schema.ObservationOutcome)
      : ("unresolved" as const);
    return { prediction, outcome, why: r?.why ?? "no judgment returned" };
  });
}

/**
 * Commit-phase (synchronous, runs in the event's transaction): stamp the
 * outcomes AND run credit assignment — confirmed/refuted flow back along
 * `basedOnIds` (consolidate.applyPredictionOutcome). `unresolved` predictions
 * get ONE grace night (resolveBy bumped a day) and then resolve
 * refuted-by-default — an unfalsifiable bet counts against, per the
 * forecasting discipline. Returns the count of settled predictions.
 */
export function applyResolutions(userId: string, resolutions: Resolution[]): number {
  const now = new Date().toISOString();
  let settled = 0;
  for (const { prediction, outcome } of resolutions) {
    let effective: "confirmed" | "refuted";
    if (outcome === "unresolved") {
      const alreadyExtended = prediction.lastSeenAt > prediction.firstSeenAt;
      if (!alreadyExtended) {
        // One grace night: push resolveBy a day, mark the extension via lastSeenAt.
        const nextDay = new Date(new Date(prediction.resolveBy! + "T00:00:00Z").getTime() + 86_400_000)
          .toISOString()
          .slice(0, 10);
        db.update(schema.observations)
          .set({ resolveBy: nextDay, lastSeenAt: now, updatedAt: now })
          .where(eq(schema.observations.id, prediction.id))
          .run();
        continue;
      }
      // Already extended once → refuted by default. Unfalsifiable bets count against.
      effective = "refuted";
    } else {
      effective = outcome;
    }
    db.update(schema.observations)
      .set({ resolvedAt: now, outcome: effective, updatedAt: now })
      .where(eq(schema.observations.id, prediction.id))
      .run();
    // Credit assignment: the outcome teaches the notes that made the bet.
    applyPredictionOutcome(userId, prediction.basedOnIds ?? [], effective);
    settled++;
  }
  return settled;
}
