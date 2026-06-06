/**
 * Digest builder — memory layer Phase 3 (designs/Atlas Memory Layer build plan, W4).
 *
 * Boils the strongest LIVING notes (not struck, not end-dated, not deleted —
 * often-confirmed and recent first) into the one-page cheat sheet: grouped by
 * person, every line carrying how many receipts back it ("runs late, as a rule
 * (×4)"). One `digests` row per user, overwritten in place, rebuilt at the end
 * of every nightly memory job — and pasted into every single thing Ayumi writes.
 * The locked decision (§4): don't search memory — keep one short summary always
 * in hand, the same trick ChatGPT and Gemini converged on.
 *
 * Deterministic string-building, no AI call — the digest must cost nothing and
 * never hallucinate; the notes themselves are the only source of words.
 */
import { randomUUID } from "node:crypto";
import { and, eq, isNull, ne } from "drizzle-orm";
import { db, schema } from "../db";
import { followMerges } from "./people";
import { calibrationSummary } from "./predict";

/** Keep the cheat sheet to ~half a page — strongest notes win the cut. */
const MAX_NOTES = 30;
const MAX_BODY_CHARS = 3_000;

interface NoteWithHandles {
  note: schema.Observation;
  handles: string[];
}

/** Living notes for a user — strongest first (weight, then recency). */
function livingNotes(userId: string): NoteWithHandles[] {
  const notes = db
    .select()
    .from(schema.observations)
    .where(
      and(
        eq(schema.observations.userId, userId),
        // Predictions are bets, not beliefs — they get their own digest
        // section ("open expectations"), never the People/Now sections.
        ne(schema.observations.kind, "prediction"),
        isNull(schema.observations.deletedAt),
        isNull(schema.observations.invalidatedAt),
        isNull(schema.observations.struckAt),
      ),
    )
    .all()
    .sort(
      (a, b) => b.weight - a.weight || b.lastSeenAt.localeCompare(a.lastSeenAt),
    )
    .slice(0, MAX_NOTES);

  return notes.map((note) => ({
    note,
    handles: db
      .select({ handle: schema.observationAbout.handle })
      .from(schema.observationAbout)
      .where(eq(schema.observationAbout.observationId, note.id))
      .all()
      .map((r) => r.handle),
  }));
}

/** Resolve a handle to its card's display name, following merges; null if uncarded. */
function nameFor(userId: string, handle: string, cards: schema.Person[]): string | null {
  const h = handle.toLowerCase();
  const card = cards.find(
    (p) =>
      p.canonicalName.toLowerCase() === h ||
      (p.handles ?? []).some((x) => x.toLowerCase() === h),
  );
  return card ? followMerges(card, cards).canonicalName : null;
}

/** One cheat-sheet line: the note in Ayumi's words + how often life confirmed it. */
function line(n: schema.Observation): string {
  const count = n.weight > 1 ? ` (×${n.weight})` : ` (×${Math.max(1, (n.receipts ?? []).length)})`;
  return `- ${n.body}${count}`;
}

/**
 * Build the cheat-sheet markdown from the strongest living notes, grouped by
 * person; `state`-kind notes close the page as "what's going on right now".
 * Returns null when there are no living notes (a digest of nothing is noise).
 */
export function buildDigestBody(
  userId: string,
): { body: string; sourceObservationIds: string[] } | null {
  const rows = livingNotes(userId);
  if (rows.length === 0) return null;

  const cards = db
    .select()
    .from(schema.people)
    .where(and(eq(schema.people.userId, userId), isNull(schema.people.deletedAt)))
    .all();

  // Group by person (a two-person note appears under both — that IS the
  // relationship); kind=state notes also collect into the "right now" section.
  const byPerson = new Map<string, schema.Observation[]>();
  const unattributed: schema.Observation[] = [];
  const now: schema.Observation[] = [];
  for (const { note, handles } of rows) {
    if (note.kind === "state") now.push(note);
    const names = [
      ...new Set(handles.map((h) => nameFor(userId, h, cards) ?? h)),
    ];
    if (names.length === 0 && note.kind !== "state") unattributed.push(note);
    for (const name of names) {
      if (note.kind === "state") continue; // already in "right now"
      const list = byPerson.get(name) ?? [];
      list.push(note);
      byPerson.set(name, list);
    }
  }

  const parts: string[] = ["What you know (rebuilt nightly from your notes — each line counts its receipts):"];
  if (byPerson.size > 0) {
    parts.push("", "People:");
    for (const [name, notes] of byPerson) {
      parts.push(`**${name}**`);
      for (const n of notes) parts.push(line(n));
    }
  }
  if (unattributed.length > 0) {
    parts.push("", "Standing notes:");
    for (const n of unattributed) parts.push(line(n));
  }
  if (now.length > 0) {
    parts.push("", "Going on right now:");
    for (const n of now) parts.push(line(n));
  }

  // Memory v2 (slice P): the open bets ride the cheat sheet so every prompt
  // knows what Ayumi is expecting — "expect Karan's reply today" comes from
  // here — and the calibration line keeps the voice honest about its record.
  const openPredictions = db
    .select()
    .from(schema.observations)
    .where(
      and(
        eq(schema.observations.userId, userId),
        eq(schema.observations.kind, "prediction"),
        isNull(schema.observations.deletedAt),
        isNull(schema.observations.struckAt),
      ),
    )
    .all()
    .filter((o) => !o.resolvedAt)
    .sort((a, b) => (a.resolveBy ?? "").localeCompare(b.resolveBy ?? ""));
  if (openPredictions.length > 0) {
    parts.push("", "Open expectations (your own bets — flag when one settles):");
    for (const p of openPredictions) {
      parts.push(`- ${p.body} (${Math.round(p.confidence * 100)}% · settles by ${p.resolveBy})`);
    }
  }
  const calibration = calibrationSummary(userId);
  if (calibration) parts.push("", `Your track record: ${calibration}`);

  let body = parts.join("\n");
  if (body.length > MAX_BODY_CHARS) body = body.slice(0, MAX_BODY_CHARS) + "\n… (trimmed)";
  return { body, sourceObservationIds: rows.map((r) => r.note.id) };
}

/**
 * Rebuild and persist the one-row-per-user cheat sheet (overwritten in place).
 * Synchronous better-sqlite3 writes — callable from a commit phase. Returns the
 * fresh body, or null when there were no living notes (any stale digest row is
 * then soft-deleted so the read path stops serving it).
 */
export function rebuildDigest(userId: string): string | null {
  const built = buildDigestBody(userId);
  const nowIso = new Date().toISOString();
  const existing = db
    .select()
    .from(schema.digests)
    .where(eq(schema.digests.userId, userId))
    .get();

  if (!built) {
    if (existing && !existing.deletedAt) {
      db.update(schema.digests)
        .set({ deletedAt: nowIso, updatedAt: nowIso })
        .where(eq(schema.digests.id, existing.id))
        .run();
    }
    return null;
  }

  if (existing) {
    db.update(schema.digests)
      .set({
        body: built.body,
        sourceObservationIds: built.sourceObservationIds,
        builtAt: nowIso,
        updatedAt: nowIso,
        deletedAt: null,
      })
      .where(eq(schema.digests.id, existing.id))
      .run();
  } else {
    db.insert(schema.digests)
      .values({
        id: randomUUID(),
        userId,
        body: built.body,
        sourceObservationIds: built.sourceObservationIds,
        builtAt: nowIso,
        updatedAt: nowIso,
      })
      .run();
  }
  return built.body;
}

/** The cheat sheet as the prompt block readers paste in — null when none exists. */
export function getDigestBody(userId: string): string | null {
  const row = db
    .select()
    .from(schema.digests)
    .where(and(eq(schema.digests.userId, userId), isNull(schema.digests.deletedAt)))
    .get();
  return row?.body ?? null;
}
