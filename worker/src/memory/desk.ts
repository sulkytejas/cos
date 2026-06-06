/**
 * Desk-setting — memory layer step 4.1 (designs/Atlas Memory Layer build plan, R2).
 *
 * Before the morning AI call starts, plain database reads fetch the top living
 * notes about each person involved today — whoever shows up in today's calendar
 * or the overnight email. Crossed-out and end-dated notes stay out. A couple of
 * indexed reads, ~2ms; the notes ride into the prompt WITH their receipts so
 * Ayumi can quote them ("plan for 20 real minutes, not 30 — you've seen it ×4").
 */
import { and, eq, inArray, isNull, ne } from "drizzle-orm";
import { db, schema } from "../db";
import { extractAddresses, followMerges, ROBOT_RE } from "./people";

/** Top living notes carried to the desk per person. */
const NOTES_PER_PERSON = 20;

/** How far around the scan we call a meeting "today's": catches a late-evening
 *  prep run for an early-tomorrow meeting without dragging in next week. */
const CALENDAR_LOOKBACK_MS = 6 * 60 * 60 * 1000;
const CALENDAR_LOOKAHEAD_MS = 36 * 60 * 60 * 1000;

/**
 * Who is in today's picture: attendees of calendar events whose startsAt falls
 * around the scan, plus correspondents on the overnight email. Robot senders
 * are skipped the same way the people backfill skips them.
 */
function todaysHandles(
  userId: string,
  overnightSignals: schema.Signal[],
  scanTime: Date,
): string[] {
  const lo = new Date(scanTime.getTime() - CALENDAR_LOOKBACK_MS).toISOString();
  const hi = new Date(scanTime.getTime() + CALENDAR_LOOKAHEAD_MS).toISOString();

  // Today's calendar — selected by the MEETING time (rawData.startsAt), not by
  // when the signal arrived: a meeting pushed last week still sets today's desk.
  const calendarToday = db
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
      return startsAt >= lo && startsAt <= hi;
    });

  const overnightMail = overnightSignals.filter((s) => s.source === "gmail");

  const handles = new Set<string>();
  for (const signal of [...calendarToday, ...overnightMail]) {
    for (const address of extractAddresses(signal)) {
      const handle = address.email ?? address.name;
      if (!handle) continue;
      if (address.email && ROBOT_RE.test(address.email)) continue;
      handles.add(handle.toLowerCase());
    }
  }
  return [...handles];
}

/**
 * Set the desk: for each person in today's picture, their top living notes —
 * receipts included — as one prompt block. Null when nobody involved today has
 * notes (an empty block would just be prompt noise).
 */
export function setDesk(
  userId: string,
  overnightSignals: schema.Signal[],
  scanTime: Date,
): string | null {
  const handles = todaysHandles(userId, overnightSignals, scanTime);
  if (handles.length === 0) return null;

  const cards = db
    .select()
    .from(schema.people)
    .where(and(eq(schema.people.userId, userId), isNull(schema.people.deletedAt)))
    .all();

  // Resolve handles → surviving cards (dedupe two addresses of one person).
  const persons = new Map<string, schema.Person>();
  for (const h of handles) {
    const card = cards.find(
      (p) =>
        p.canonicalName.toLowerCase() === h ||
        (p.handles ?? []).some((x) => x.toLowerCase() === h),
    );
    if (card) {
      const surviving = followMerges(card, cards);
      persons.set(surviving.id, surviving);
    }
  }
  if (persons.size === 0) return null;

  const blocks: string[] = [];
  for (const person of persons.values()) {
    const personHandles = (person.handles ?? []).map((h) => h.toLowerCase());
    if (personHandles.length === 0) continue;
    const aboutRows = db
      .select({ observationId: schema.observationAbout.observationId })
      .from(schema.observationAbout)
      .where(
        and(
          eq(schema.observationAbout.userId, userId),
          inArray(schema.observationAbout.handle, personHandles),
        ),
      )
      .all();
    const ids = [...new Set(aboutRows.map((r) => r.observationId))];
    if (ids.length === 0) continue;

    const notes = db
      .select()
      .from(schema.observations)
      .where(
        and(
          inArray(schema.observations.id, ids),
          // Predictions ride the cheat sheet's "open expectations", not the desk.
          ne(schema.observations.kind, "prediction"),
          isNull(schema.observations.deletedAt),
          isNull(schema.observations.invalidatedAt),
          isNull(schema.observations.struckAt),
        ),
      )
      .all()
      .sort((a, b) => b.weight - a.weight || b.lastSeenAt.localeCompare(a.lastSeenAt))
      .slice(0, NOTES_PER_PERSON);
    if (notes.length === 0) continue;

    blocks.push(
      [
        `**${person.canonicalName}** (${(person.handles ?? []).join(", ")})`,
        // Phase 5.1: each line carries its note id — when a day_memo line leans
        // on a note, the agent cites the id in `note_ids`, so striking that
        // line can strike the note.
        ...notes.map(
          (n) =>
            `- ${n.body} [note:${n.id} · ${n.kind}, confirmed ×${n.weight} · receipts: ${(n.receipts ?? []).join(", ") || "none"}]`,
        ),
      ].join("\n"),
    );
  }
  if (blocks.length === 0) return null;

  return [
    "Notes on people in today's picture (from your notebook — living notes only; when a memo line leans on a note, carry that note's id in the line's `note_ids`):",
    ...blocks,
  ].join("\n");
}
