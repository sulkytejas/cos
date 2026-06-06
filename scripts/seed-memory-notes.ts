/**
 * Seed planted notes — memory layer slice B (designs/Atlas Memory Layer build plan).
 *
 * Plants 3 hand-written notes about Karan (no AI note-taking yet — that's
 * Phase 2) so the cheat sheet + desk-setting have something real to read, and
 * the Today page can say something it could never say before. Receipts point
 * at the REAL signal rows already in the database. Also plants a Karan meeting
 * for today, since the desk is only set for people in today's picture.
 *
 *   pnpm tsx scripts/seed-memory-notes.ts            # plant + rebuild digest
 *   pnpm tsx scripts/seed-memory-notes.ts --remove   # slice C: unplant, rebuild
 *
 * Idempotent: deterministic ids (seed-karan-*) are deleted and re-inserted on
 * each run. Hard delete is correct here — these are seed rows, not Ayumi's notes.
 */
import { eq, like, isNull } from "drizzle-orm";
import { db, schema } from "../worker/src/db";
import { findPerson } from "../worker/src/memory/people";
import { rebuildDigest } from "../worker/src/memory/digest";

const USER = schema.BOOTSTRAP_USER_ID;
const KARAN = "karan@sequoiacap.com";

function removePlanted(): void {
  // observationAbout rows cascade with the FK (foreign_keys=ON on this handle).
  db.delete(schema.observations).where(like(schema.observations.id, "seed-karan-%")).run();
  db.delete(schema.signals).where(eq(schema.signals.externalId, "seed-karan-today")).run();
}

function main(): void {
  if (process.argv[2] === "--remove") {
    removePlanted();
    const digest = rebuildDigest(USER);
    console.log("[seed-memory] planted notes removed; digest", digest ? "rebuilt" : "cleared");
    return;
  }

  const karan = findPerson(USER, KARAN);
  if (!karan) {
    console.error("[seed-memory] no Karan card — run `pnpm tsx scripts/backfill-people.ts` first");
    process.exit(1);
  }

  // The real rows his receipts point at.
  const signals = db
    .select()
    .from(schema.signals)
    .where(isNull(schema.signals.deletedAt))
    .all();
  const deckEmail = signals.find(
    (s) => s.source === "gmail" && JSON.stringify(s.rawData).includes(KARAN),
  );
  const partnerIntro = signals.find(
    (s) => s.source === "calendar" && JSON.stringify(s.rawData).includes(KARAN),
  );
  if (!deckEmail || !partnerIntro) {
    console.error("[seed-memory] expected Karan's email + calendar signals in the DB");
    process.exit(1);
  }

  removePlanted();

  // A Karan meeting TODAY (14:30 local), so the desk-setting fetches his notes.
  // Format with the LOCAL offset (like the connector fixtures) — a bare UTC
  // instant reads as "09:00" in the agent's verdict, which looks wrong to the
  // user whose calendar says 14:30.
  const meetingAt = new Date();
  meetingAt.setHours(14, 30, 0, 0);
  const localIso = (d: Date): string => {
    const tz = -d.getTimezoneOffset();
    const sign = tz >= 0 ? "+" : "-";
    const pad = (n: number) => String(Math.abs(n)).padStart(2, "0");
    const off = `${sign}${pad(Math.trunc(tz / 60))}:${pad(tz % 60)}`;
    return (
      `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
      `T${pad(d.getHours())}:${pad(d.getMinutes())}:00${off}`
    );
  };
  db.insert(schema.signals)
    .values({
      id: "seed-karan-today-signal",
      userId: USER,
      source: "calendar",
      externalId: "seed-karan-today",
      rawData: {
        title: "Karan Mohla — follow-up · Sequoia",
        startsAt: localIso(meetingAt),
        endsAt: localIso(new Date(meetingAt.getTime() + 30 * 60_000)),
        location: "Zoom",
        attendees: [KARAN, "tejas@stratyfix.com"],
      },
      summary: "Karan Mohla — follow-up (seeded for memory slice B)",
      arrivedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    })
    .run();

  // 3 planted notes — what the AI note-taker WOULD have written, by hand.
  const nowIso = new Date().toISOString();
  const notes: Array<{ note: schema.NewObservation; handles: string[] }> = [
    {
      note: {
        id: "seed-karan-note-1",
        userId: USER,
        body: "Karan usually runs about 10 minutes late to calls — plan for 20 real minutes in a 30-minute slot.",
        kind: "pattern",
        source: "observed",
        confidence: 0.85,
        receipts: [partnerIntro.id, deckEmail.id],
        firstSeenAt: "2026-05-21T15:10:00.000Z",
        lastSeenAt: nowIso,
        weight: 4,
        updatedAt: nowIso,
      },
      handles: [KARAN],
    },
    {
      note: {
        id: "seed-karan-note-2",
        userId: USER,
        body: "Retention is Karan's lens — he reads everything through the month-6 cohort and asks about it first.",
        kind: "preference",
        source: "observed",
        confidence: 0.8,
        receipts: [deckEmail.id],
        firstSeenAt: "2026-05-21T06:12:00.000Z",
        lastSeenAt: nowIso,
        weight: 3,
        updatedAt: nowIso,
      },
      handles: [KARAN],
    },
    {
      note: {
        id: "seed-karan-note-3",
        userId: USER,
        body: "Deck v3 is with Karan; he asked to talk retention and the self-hosted pivot — the ball is in his court.",
        kind: "state",
        source: "observed",
        confidence: 0.9,
        receipts: [deckEmail.id],
        firstSeenAt: "2026-05-21T06:12:00.000Z",
        lastSeenAt: nowIso,
        weight: 1,
        updatedAt: nowIso,
      },
      handles: [KARAN],
    },
  ];

  for (const { note, handles } of notes) {
    db.insert(schema.observations).values(note).run();
    for (const handle of handles) {
      db.insert(schema.observationAbout)
        .values({ userId: USER, observationId: note.id as string, handle })
        .run();
    }
    console.log(`[seed-memory] + ${note.id}: ${(note.body as string).slice(0, 60)}…`);
  }

  const digest = rebuildDigest(USER);
  console.log(`\n[seed-memory] digest rebuilt:\n${"-".repeat(60)}\n${digest}\n${"-".repeat(60)}`);
}

main();
