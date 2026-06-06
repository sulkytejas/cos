/**
 * Extract — memory layer Phase 2.1 (W2): Ayumi drafts candidate notes.
 *
 * One small AI pass per night reads what the morning touched — the emails, the
 * meetings, what Ayumi wrote — and drafts candidate notes: what was learned,
 * about whom, with which signals as receipts. There is NO fixed list of
 * allowed note types ("he goes quiet before big asks" is a perfectly good
 * note); the kind is just a coarse bucket. A draft without receipts is thrown
 * away on principle — every note must be able to prove itself.
 *
 * Drafts live ONLY in memory between this call and consolidate.ts — they are
 * never persisted. Only the reconciled outcome touches the database.
 */
import { and, eq, isNull } from "drizzle-orm";
import { db, schema } from "../db";
import { createMessage } from "../../../src/server/anthropic/gateway";
import { extractAddresses, findPerson, ROBOT_RE } from "./people";

/** A candidate note — in-memory only, the raw material consolidate reconciles. */
export interface DraftNote {
  body: string;
  kind: schema.ObservationKind;
  about: string[];
  confidence: number;
  source: schema.ObservationSource;
  receipts: string[];
}

const EXTRACT_MAX_OUTPUT_TOKENS = 1_200;
/** How far back "what the morning touched" reaches. */
const MATERIAL_WINDOW_MS = 36 * 60 * 60 * 1000;

const EXTRACT_SYSTEM = `You are the nightly note-taking pass of Ayumi, a personal chief of staff. You read what the last day brought (emails, meetings, what Ayumi itself wrote) and draft the SMALL number of notes worth keeping in the notebook.

A good note:
- is one plain-words sentence about a person, a pattern, a preference, a relationship, or a current state ("Karan usually runs ~10 minutes late", "deck v3 is with Karan — ball in his court");
- names who it concerns by their EMAIL ADDRESS when one is known (use the handles listed in PEOPLE), otherwise the bare name;
- cites receipts: the signal ids (given in the material) that prove it. A claim with no receipt must NOT be drafted;
- is something that will still matter tomorrow. Logistics that expire tonight, newsletter noise, and one-off trivia are NOT notes.

Anti-rules:
- Do NOT note things about the operating of Ayumi itself.
- Do NOT invent facts not present in the material.
- 0 notes is a fine answer on a quiet night. Never pad. Maximum 6.

Output: ONLY a JSON object, no commentary, shaped:
{"notes":[{"body":"...","kind":"fact|preference|pattern|relationship|state","about":["handle"],"confidence":0.0-1.0,"source":"observed|told|inferred","receipts":["signal-id"]}]}`;

/** Strip fences / salvage the outermost JSON object from a model reply. */
export function parseModelJson<T>(raw: string): T | null {
  let body = raw.trim();
  if (body.startsWith("```")) {
    body = body.replace(/^```(?:json)?\s*/i, "").replace(/```$/i, "").trim();
  }
  try {
    return JSON.parse(body) as T;
  } catch {
    const first = body.indexOf("{");
    const last = body.lastIndexOf("}");
    if (first !== -1 && last > first) {
      try {
        return JSON.parse(body.slice(first, last + 1)) as T;
      } catch {
        return null;
      }
    }
    return null;
  }
}

/** Squeeze a signal's rawData into one prompt line. Bare id first — models
 *  copy whatever token shape they see, so no `id:` prefix to drag along. */
function signalLine(s: schema.Signal): string {
  const raw = JSON.stringify(s.rawData);
  return `- ${s.id} · ${s.source} · ${s.summary ?? ""} · ${raw.slice(0, 320)}`;
}

/** Models sometimes echo a prompt's `id:` prefix — strip it before validating. */
export const bareId = (v: string): string => v.replace(/^id:\s*/i, "").trim();

/** The night's material: recent signals + what Ayumi wrote + who was involved. */
export function gatherMaterial(userId: string, now: Date): {
  signals: schema.Signal[];
  block: string;
} {
  const since = new Date(now.getTime() - MATERIAL_WINDOW_MS).toISOString();
  const signals = db
    .select()
    .from(schema.signals)
    .where(and(eq(schema.signals.userId, userId), isNull(schema.signals.deletedAt)))
    .all()
    .filter((s) => s.arrivedAt >= since)
    // Robot mail is never note material.
    .filter((s) => {
      if (s.source !== "gmail") return true;
      const from = String((s.rawData as Record<string, unknown>).from ?? "");
      return !ROBOT_RE.test(from.toLowerCase());
    });

  // Who is in the material — list their cards so drafts use canonical handles.
  const handleSet = new Set<string>();
  for (const s of signals) {
    for (const a of extractAddresses(s)) {
      const h = (a.email ?? a.name)?.toLowerCase();
      if (h && !(a.email && ROBOT_RE.test(a.email))) handleSet.add(h);
    }
  }
  const cards = db
    .select()
    .from(schema.people)
    .where(and(eq(schema.people.userId, userId), isNull(schema.people.deletedAt)))
    .all()
    .filter((p) =>
      (p.handles ?? []).some((h) => handleSet.has(h.toLowerCase())) ||
      handleSet.has(p.canonicalName.toLowerCase()),
    );

  // What Ayumi wrote today (morning turn + briefs) — the run's own conclusions
  // are material too (kind: inferred), receipted by the signals beneath them.
  const todayStart = new Date(now);
  todayStart.setHours(0, 0, 0, 0);
  const turnsToday = db
    .select()
    .from(schema.turns)
    .where(
      and(
        eq(schema.turns.userId, userId),
        eq(schema.turns.kind, "morning"),
        isNull(schema.turns.deletedAt),
      ),
    )
    .all()
    .filter((t) => t.createdAt >= todayStart.toISOString());
  const briefsToday = db
    .select({ title: schema.briefs.title, situation: schema.briefs.situationDescription })
    .from(schema.briefs)
    .where(and(eq(schema.briefs.userId, userId), isNull(schema.briefs.deletedAt)))
    .all();

  const block = [
    "PEOPLE (use these handles in `about`):",
    ...cards.map((p) => `- ${p.canonicalName}: ${(p.handles ?? []).join(", ")}`),
    "",
    "SIGNALS (the receipts — cite by id):",
    ...signals.map(signalLine),
    "",
    "WHAT AYUMI WROTE TODAY:",
    ...turnsToday.map((t) => `- verdict: ${t.body}`),
    ...turnsToday.flatMap((t) => (t.memo?.lines ?? []).map((l) => `- memo: ${l.text}`)),
    ...briefsToday.slice(-3).map((b) => `- brief: ${b.title} — ${b.situation.slice(0, 140)}`),
  ].join("\n");

  return { signals, block };
}

/**
 * Draft candidate notes from the night's material. Returns [] on a quiet night
 * or when the model's reply can't be parsed (a lost draft costs nothing — the
 * same material is still there tomorrow).
 */
export async function extractDrafts(
  userId: string,
  material: { signals: schema.Signal[]; block: string },
): Promise<DraftNote[]> {
  if (material.signals.length === 0) return [];

  const response = await createMessage(
    {
      route: "one_shot",
      system: EXTRACT_SYSTEM,
      messages: [{ role: "user", content: material.block }],
      maxTokens: EXTRACT_MAX_OUTPUT_TOKENS,
    },
    { userId },
  );
  const text = response.content
    .filter((b): b is Extract<(typeof response.content)[number], { type: "text" }> => b.type === "text")
    .map((b) => b.text)
    .join("\n");

  const parsed = parseModelJson<{ notes?: unknown[] }>(text);
  if (!parsed?.notes || !Array.isArray(parsed.notes)) return [];

  const validSignalIds = new Set(material.signals.map((s) => s.id));
  const drafts: DraftNote[] = [];
  for (const n of parsed.notes) {
    const d = n as Record<string, unknown>;
    const body = typeof d.body === "string" ? d.body.trim() : "";
    const receipts = Array.isArray(d.receipts)
      ? d.receipts
          .filter((r): r is string => typeof r === "string")
          .map(bareId)
          .filter((r) => validSignalIds.has(r))
      : [];
    // Normalize `about` to a card's primary EMAIL handle when one resolves —
    // the model often writes the display name ("karan"), but every lookup path
    // (desk, person_lookup, memory_lookup) walks card.handles, which hold the
    // addresses. Unresolvable handles stay as written (a bare-name temp card
    // may exist for them later).
    const about = Array.isArray(d.about)
      ? d.about
          .filter((a): a is string => typeof a === "string" && !!a.trim())
          .map((a) => {
            const card = findPerson(userId, a);
            const email = card?.handles?.find((h) => h.includes("@"));
            return (email ?? a).toLowerCase();
          })
      : [];
    // The principle: no receipts, no note. Also drop empty bodies and orphans.
    if (!body || receipts.length === 0) continue;
    const kind = (schema.observationKinds as readonly string[]).includes(String(d.kind))
      ? (d.kind as schema.ObservationKind)
      : "fact";
    if (kind === "prediction") continue; // predictions come from predict.ts, never extract
    const source = (schema.observationSources as readonly string[]).includes(String(d.source))
      ? (d.source as schema.ObservationSource)
      : "observed";
    const confidence = typeof d.confidence === "number" ? Math.min(1, Math.max(0, d.confidence)) : 0.6;
    drafts.push({ body, kind, about, confidence, source, receipts });
  }
  return drafts.slice(0, 6);
}
