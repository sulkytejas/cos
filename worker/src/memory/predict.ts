/**
 * Predict — Memory v2 slice P: memory that predicts, not memory that recalls.
 *
 * After consolidation each night, Ayumi writes a few FALSIFIABLE predictions
 * as ordinary observation rows (kind=prediction): plain words, a NUMERIC
 * confidence, the notes they're based on (`basedOnIds` — the credit-assignment
 * pointers), and a resolve-by date. The discipline that makes this scientific
 * instead of vibes: a prediction that can't name what settles it is dropped.
 *
 * Small and near, not grand — "who replies today", "what slips" — resolvable
 * in days, so the loop turns daily. Passive forecasts only: never predict a
 * thing Ayumi itself controls (it would cause its own success).
 */
import { randomUUID } from "node:crypto";
import { and, eq, isNull } from "drizzle-orm";
import { db, schema } from "../db";
import { createMessage } from "../../../src/server/anthropic/gateway";
import { bareId, parseModelJson } from "./extract";

const PREDICT_MAX_OUTPUT_TOKENS = 900;
/** Max open (unresolved) predictions — past this, predict nothing new. */
const MAX_OPEN_PREDICTIONS = 8;

const PREDICT_SYSTEM = `You are the nightly prediction pass of Ayumi, a personal chief of staff. Given the notebook (living notes about the user's world) and what's coming up, write 0-4 SMALL, FALSIFIABLE predictions.

Rules:
- Each prediction must be settleable by an observable signal (an email arriving, a meeting happening or slipping, a reply landing) within 1-7 days.
- confidence is a NUMBER between 0.5 and 0.95 — your honest probability. Never hedge with words; the number is the hedge.
- based_on: the ids of the notebook notes that led to it (at least one). No basis, no prediction.
- Only predict things Ayumi does NOT control. Never predict what Ayumi will do.
- Plain words: "Karan replies about the deck by Thursday", not analytics-speak.
- 0 predictions is a fine answer. Never pad.

Output ONLY JSON:
{"predictions":[{"body":"...","confidence":0.75,"based_on":["note-id"],"resolve_by":"YYYY-MM-DD","about":["handle"]}]}`;

export interface DraftedPredictions {
  rows: schema.NewObservation[];
  aboutRows: Array<{ userId: string; observationId: string; handle: string }>;
}

/**
 * Prepare-phase: draft tonight's predictions (no writes). Returns row values
 * the commit inserts. Skips entirely when enough predictions are already open.
 */
export async function draftPredictions(
  userId: string,
  now: Date,
): Promise<DraftedPredictions> {
  const all = db
    .select()
    .from(schema.observations)
    .where(and(eq(schema.observations.userId, userId), isNull(schema.observations.deletedAt)))
    .all();

  const open = all.filter((o) => o.kind === "prediction" && !o.resolvedAt && !o.struckAt);
  if (open.length >= MAX_OPEN_PREDICTIONS) return { rows: [], aboutRows: [] };

  const living = all.filter(
    (o) => o.kind !== "prediction" && !o.invalidatedAt && !o.struckAt,
  );
  if (living.length === 0) return { rows: [], aboutRows: [] };

  // What's coming up — calendar signals in the next 7 days give the predictions
  // something concrete to attach to.
  const weekAhead = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000).toISOString();
  const upcoming = db
    .select()
    .from(schema.signals)
    .where(
      and(
        eq(schema.signals.userId, userId),
        eq(schema.signals.source, "calendar"),
        isNull(schema.signals.deletedAt),
      ),
    )
    .all()
    .filter((s) => {
      const startsAt = String((s.rawData as Record<string, unknown>).startsAt ?? "");
      return startsAt >= now.toISOString().slice(0, 10) && startsAt <= weekAhead;
    });

  const user = [
    `Today is ${now.toISOString().slice(0, 10)}.`,
    "",
    "NOTEBOOK (living notes — cite ids in based_on):",
    ...living.map((o) => `- ${o.id} [${o.kind}, ×${o.weight}] ${o.body}`),
    "",
    "ALREADY-OPEN PREDICTIONS (do not duplicate):",
    ...open.map((o) => `- ${o.body} (resolves by ${o.resolveBy})`),
    "",
    "COMING UP (next 7 days):",
    ...upcoming.map((s) => `- ${s.summary ?? ""} · ${JSON.stringify(s.rawData).slice(0, 200)}`),
  ].join("\n");

  const response = await createMessage(
    {
      route: "one_shot",
      system: PREDICT_SYSTEM,
      messages: [{ role: "user", content: user }],
      maxTokens: PREDICT_MAX_OUTPUT_TOKENS,
    },
    { userId },
  );
  const text = response.content
    .filter((b): b is Extract<(typeof response.content)[number], { type: "text" }> => b.type === "text")
    .map((b) => b.text)
    .join("\n");

  const parsed = parseModelJson<{ predictions?: unknown[] }>(text);
  if (!parsed?.predictions || !Array.isArray(parsed.predictions)) return { rows: [], aboutRows: [] };

  const livingIds = new Set(living.map((o) => o.id));
  const nowIso = new Date().toISOString();
  const rows: schema.NewObservation[] = [];
  const aboutRows: Array<{ userId: string; observationId: string; handle: string }> = [];
  for (const p of parsed.predictions.slice(0, 4)) {
    const d = p as Record<string, unknown>;
    const body = typeof d.body === "string" ? d.body.trim() : "";
    const basedOn = Array.isArray(d.based_on)
      ? d.based_on
          .filter((x): x is string => typeof x === "string")
          .map(bareId)
          .filter((x) => livingIds.has(x))
      : [];
    const resolveBy = typeof d.resolve_by === "string" && /^\d{4}-\d{2}-\d{2}/.test(d.resolve_by)
      ? d.resolve_by.slice(0, 10)
      : null;
    const confidence = typeof d.confidence === "number" ? Math.min(0.95, Math.max(0.5, d.confidence)) : null;
    // The discipline: no basis / no settle-date / no number → not a prediction.
    if (!body || basedOn.length === 0 || !resolveBy || confidence === null) continue;
    const id = randomUUID();
    rows.push({
      id,
      userId,
      body,
      kind: "prediction",
      source: "inferred",
      confidence,
      receipts: [],
      basedOnIds: basedOn,
      resolveBy,
      firstSeenAt: nowIso,
      lastSeenAt: nowIso,
      weight: 1,
      updatedAt: nowIso,
    });
    const about = Array.isArray(d.about)
      ? d.about.filter((x): x is string => typeof x === "string" && !!x.trim())
      : [];
    for (const h of new Set(about.map((x) => x.toLowerCase()))) {
      aboutRows.push({ userId, observationId: id, handle: h });
    }
  }
  return { rows, aboutRows };
}

/** Calibration so far — computed live from resolved predictions, no extra table. */
export function calibrationSummary(userId: string): string | null {
  const resolved = db
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
    .filter((o) => o.resolvedAt && (o.outcome === "confirmed" || o.outcome === "refuted"));
  if (resolved.length === 0) return null;

  const confirmed = resolved.filter((o) => o.outcome === "confirmed");
  // Brier score: mean (confidence − outcome)²; 0 is perfect, 0.25 is coin-flip.
  const brier =
    resolved.reduce((sum, o) => {
      const y = o.outcome === "confirmed" ? 1 : 0;
      return sum + (o.confidence - y) ** 2;
    }, 0) / resolved.length;
  const avgConf = resolved.reduce((s, o) => s + o.confidence, 0) / resolved.length;

  return (
    `Predictions so far: ${confirmed.length}/${resolved.length} confirmed · ` +
    `average stated confidence ${(avgConf * 100).toFixed(0)}% vs hit rate ${((confirmed.length / resolved.length) * 100).toFixed(0)}% · ` +
    `Brier ${brier.toFixed(2)} (0 perfect, 0.25 coin-flip)` +
    (avgConf - confirmed.length / resolved.length > 0.15
      ? " — running OVERCONFIDENT; hedge harder where you'd guess"
      : "")
  );
}
