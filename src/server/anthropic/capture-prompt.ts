/**
 * CAPTURE CO-COMPLETION — shared prompt + parser (Module MC).
 *
 * The "well" sheet (design handoff PART 1) hands Ayumi a *fragment* (typed or
 * spoken); she (a) GHOST-completes it into a full structured note and (b)
 * CLASSIFIES it — kind ∈ {todo,decision,note} + the best-matching chapter — and,
 * only when she isn't confident, asks EXACTLY ONE clarifying question.
 *
 * This file is the single source of truth for that prompt so both halves of the
 * round-trip agree on its shape:
 *   - the worker handler (`prepareCaptureComplete`) builds the request from here
 *     and calls the gateway (`route:'one_shot'` = Haiku, for low latency),
 *   - the capture router enqueues the job and validates the parsed result.
 *
 * Why a stable system prefix: the gateway caches `system` (ttl 1h). Keeping the
 * instructions + the response contract in a single constant string makes the
 * prefix byte-stable across calls, so every capture after the first is a
 * cache_read (free ITPM, lower latency) — the per-call variation (the fragment,
 * the user's live chapter list) rides in the user message, never the system.
 */

/** What Ayumi is forming the fragment into — mirrors the well's forming-tag kinds. */
export const CAPTURE_KINDS = ["todo", "decision", "note"] as const;
export type CaptureKind = (typeof CAPTURE_KINDS)[number];

/**
 * The canonical confidence threshold below which the well ASKS its one question
 * (and at/above which it SETTLES). Referenced by both the prompt instruction and
 * the parser so the settle/ask decision is one number, enforced server-side
 * rather than left to the model's discretion.
 */
export const CAPTURE_ASK_THRESHOLD = 0.55;

/** A chapter the classifier may file the fragment under (id is what we return). */
export interface CaptureChapter {
  id: string;
  title: string;
  status: string;
}

/** The structured result the well consumes (see CaptureCompletion in capture.ts). */
export interface CaptureCompletionResult {
  /** The italic remainder the well renders after the fragment (NOT the fragment). */
  ghost: string;
  kind: CaptureKind;
  /** Inferred home chapter id, or null when she'd auto-file at the top level. */
  chapterId: string | null;
  /** The single low-confidence clarifier, or null when she's confident. */
  question: { text: string; answers: string[] } | null;
  /** 0..1 — drives whether the well shows the forming tag as settled or asks. */
  confidence: number;
}

/**
 * The stable system prefix (cached). It defines Ayumi's voice, the co-completion
 * rules, and the EXACT JSON contract. No per-call data lives here — that keeps
 * the prefix byte-identical so the gateway cache hits on every capture.
 */
export const CAPTURE_SYSTEM = `You are Ayumi, a quiet personal chief-of-staff. The user hands you a short FRAGMENT they began typing or saying, and you co-complete it: they write intent, you write structure.

Do TWO things at once:

1. GHOST — complete the fragment into one full, structured note. Return ONLY the remainder that continues the user's text (the part they have NOT typed yet), so that fragment + ghost reads as one natural sentence. Begin the ghost with whatever character makes the join clean (usually a leading space). Keep it short — one clause or sentence, the way an assistant finishes your thought. If the fragment already reads as complete, return an empty ghost.

2. CLASSIFY — decide:
   - kind: "todo" (an action to take), "decision" (a choice being weighed or made), or "note" (an observation, fact, or reference).
   - chapterId: the id of the single best-matching chapter from the list the user provides, or null if none clearly fits (you'd file it at the top level).
   - confidence: 0..1, your overall confidence in the kind + chapter.
   - question: ONLY when confidence is low (< ${CAPTURE_ASK_THRESHOLD}) AND a single answer would resolve it, return one short clarifying question with 2 short answer options. Otherwise null. Never ask more than one question. Never ask when you can reasonably infer.

Voice: calm, concrete, never performative. No exclamation marks, no "Great". The ghost is in the user's own register, not yours.

Respond with ONLY a single JSON object, no prose, no code fence:
{"ghost": string, "kind": "todo"|"decision"|"note", "chapterId": string|null, "confidence": number, "question": {"text": string, "answers": [string, string]} | null}`;

/** Cap the chapter list we inline so a user with many chapters can't bloat the prompt. */
const MAX_CHAPTERS_IN_PROMPT = 40;

/**
 * Build the per-call user message: the fragment, an optional summon-scope hint
 * (the screen the well was opened over), and the user's live chapter list. All
 * the variation lives here so the system prefix stays cacheable.
 */
export function buildCaptureUserMessage(opts: {
  fragment: string;
  scope?: string | null;
  chapters: CaptureChapter[];
}): string {
  const chapters = opts.chapters.slice(0, MAX_CHAPTERS_IN_PROMPT);
  const chapterLines =
    chapters.length > 0
      ? chapters.map((c) => `  - id="${c.id}" · ${c.title} · ${c.status}`).join("\n")
      : "  (none — chapterId must be null)";
  return [
    opts.scope ? `Summoned over: ${opts.scope}` : null,
    "User's chapters (pick chapterId from these ids, or null):",
    chapterLines,
    "",
    `Fragment: """${opts.fragment}"""`,
    "",
    "Complete and classify it. Reply with the JSON object only.",
  ]
    .filter((l): l is string => l != null)
    .join("\n");
}

/** Reservation budget — kept small for low latency (ghost + tiny JSON, never prose). */
export const CAPTURE_MAX_OUTPUT_TOKENS = 256;

function clamp01(n: number): number {
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(1, n));
}

/**
 * Parse the model's JSON into a validated `CaptureCompletionResult`, defending
 * against the usual one-shot drift (a stray code fence, a missing field, a
 * hallucinated chapter id). `validChapterIds` is used to reject a chapterId the
 * model invented — we only ever return an id that actually exists (or null).
 * Returns null when the body can't be parsed at all (the caller supplies a
 * deterministic fallback so the well never hangs).
 */
export function parseCaptureCompletion(
  raw: string,
  validChapterIds: ReadonlySet<string>,
): CaptureCompletionResult | null {
  let body = raw.trim();
  if (body.startsWith("```")) {
    body = body.replace(/^```(?:json)?\s*/i, "").replace(/```$/i, "").trim();
  }
  // Tolerate leading/trailing prose by extracting the first balanced JSON object.
  if (!body.startsWith("{")) {
    const start = body.indexOf("{");
    const end = body.lastIndexOf("}");
    if (start === -1 || end === -1 || end <= start) return null;
    body = body.slice(start, end + 1);
  }

  let obj: Record<string, unknown>;
  try {
    obj = JSON.parse(body) as Record<string, unknown>;
  } catch {
    return null;
  }

  const ghost = typeof obj.ghost === "string" ? obj.ghost : "";
  const kind: CaptureKind = CAPTURE_KINDS.includes(obj.kind as CaptureKind)
    ? (obj.kind as CaptureKind)
    : "note";

  // Only honor a chapterId the user actually owns; otherwise auto-file (null).
  const rawChapterId = obj.chapterId;
  const chapterId =
    typeof rawChapterId === "string" && validChapterIds.has(rawChapterId) ? rawChapterId : null;

  const confidence = clamp01(typeof obj.confidence === "number" ? obj.confidence : 0.7);

  // A question is honored only if well-formed (text + ≥2 answers) AND confidence
  // is actually low. The forming-tag contract is: low confidence → ask; otherwise
  // settle. We ENFORCE the threshold here rather than trusting the model, so a
  // stray `question` returned alongside a high confidence can't surface the
  // one-question card against the design's "settle when confident" intent.
  let question: CaptureCompletionResult["question"] = null;
  const q = obj.question;
  if (q && typeof q === "object" && confidence < CAPTURE_ASK_THRESHOLD) {
    const qt = (q as { text?: unknown }).text;
    const qa = (q as { answers?: unknown }).answers;
    if (typeof qt === "string" && qt.trim() && Array.isArray(qa)) {
      const answers = qa.filter((a): a is string => typeof a === "string" && a.trim().length > 0);
      if (answers.length >= 2) {
        question = { text: qt.trim(), answers: answers.slice(0, 3) };
      }
    }
  }

  return { ghost, kind, chapterId, question, confidence };
}
