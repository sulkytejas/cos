/**
 * The Karan rehearsal — memory layer Phase 6 (designs/Atlas Memory Layer build plan).
 *
 * Seeds a fake three weeks of Karan so the WHOLE loop can be proven end to end:
 * planted habits (ran late ×4, pushed on retention ×3, went silent after the
 * deck), one red herring that must NOT become a note (expired logistics), and a
 * contradiction pair split across nights so SUPERSEDE gets exercised. The
 * planted slice-B notes are removed first — from here on, Ayumi writes its own.
 *
 *   pnpm tsx scripts/seed-memory-rehearsal.ts --night 1   # clear + seed the 3-week batch
 *   pnpm tsx scripts/seed-memory-rehearsal.ts --night 2   # the contradicting move email
 *   pnpm tsx scripts/seed-memory-rehearsal.ts --night 3   # Karan's deck reply + predictions fall due
 *   pnpm tsx scripts/seed-memory-rehearsal.ts --remove    # clean every rehearsal row
 *
 * Each --night N also enqueues the matching jobs (night 1 = a full daily_scan,
 * which chains the memory pass; nights 2-3 = the memory pass directly), so the
 * runner is just:  --night N && ANTHROPIC_API_KEY=… pnpm worker:once
 *
 * Timeline note: content tells a three-week story (received_at / startsAt), but
 * arrivedAt sits inside the extractor's material window — the rehearsal
 * compresses the calendar, not the meaning.
 */
import { randomUUID } from "node:crypto";
import { eq, like, inArray } from "drizzle-orm";
import { db, schema } from "../worker/src/db";

const USER = schema.BOOTSTRAP_USER_ID;
const KARAN = "karan@sequoiacap.com";
const TEJAS = "tejas@stratyfix.com";

const hoursAgo = (h: number) => new Date(Date.now() - h * 3_600_000).toISOString();
const daysFromNowLocal = (d: number, hh: number, mm: number) => {
  const t = new Date();
  t.setDate(t.getDate() + d);
  t.setHours(hh, mm, 0, 0);
  const tz = -t.getTimezoneOffset();
  const sign = tz >= 0 ? "+" : "-";
  const pad = (n: number) => String(Math.abs(n)).padStart(2, "0");
  return (
    `${t.getFullYear()}-${pad(t.getMonth() + 1)}-${pad(t.getDate())}` +
    `T${pad(t.getHours())}:${pad(t.getMinutes())}:00${sign}${pad(Math.trunc(tz / 60))}:${pad(tz % 60)}`
  );
};

function gmail(externalId: string, arrivedAt: string, raw: Record<string, unknown>, summary: string) {
  return {
    id: `rh-${externalId}`,
    userId: USER,
    source: "gmail" as const,
    externalId: `rehearsal-${externalId}`,
    rawData: raw,
    summary,
    arrivedAt,
    updatedAt: new Date().toISOString(),
  };
}

function calendar(externalId: string, arrivedAt: string, raw: Record<string, unknown>, summary: string) {
  return { ...gmail(externalId, arrivedAt, raw, summary), source: "calendar" as const };
}

/** Night 1 — the three-week batch: habits, silence, herring, the to-be-contradicted fact. */
function night1Rows() {
  return [
    // ── ran late, four receipts ──────────────────────────────────────────
    gmail("late-1", hoursAgo(30), {
      from: KARAN, to: TEJAS, subject: "running behind",
      body: "Stuck on a board call — joining ours 10 late. Start without me.",
      received_at: "2026-05-19T13:55:00+05:30",
    }, "Karan — running 10 late to the catch-up"),
    gmail("late-2", hoursAgo(28), {
      from: KARAN, to: TEJAS, subject: "re: intro call",
      body: "Apologies for joining late again yesterday — back-to-backs. The last ten minutes were the useful ones though.",
      received_at: "2026-05-22T09:10:00+05:30",
    }, "Karan — apologized for joining late again"),
    gmail("late-3", hoursAgo(26), {
      from: KARAN, to: TEJAS, subject: "today",
      body: "Heads up, prior meeting is overrunning — I'll be ~10 minutes late to ours.",
      received_at: "2026-05-27T14:20:00+05:30",
    }, "Karan — ~10 min late to today's call"),
    calendar("late-4", hoursAgo(25), {
      title: "Karan × Tejas — catch-up", startsAt: "2026-05-27T14:30:00+05:30",
      endsAt: "2026-05-27T15:00:00+05:30",
      attendees: [KARAN, TEJAS],
      notes: "Started 14:41 — Karan joined late (board call overran).",
    }, "Catch-up — started 11 late"),

    // ── retention is the lens, three receipts ────────────────────────────
    gmail("retention-1", hoursAgo(29), {
      from: KARAN, to: TEJAS, subject: "after the intro",
      body: "Good first chat. Before anything else: walk me through month-6 retention by cohort. Everything else is downstream of that.",
      received_at: "2026-05-21T18:40:00+05:30",
    }, "Karan — wants month-6 retention by cohort first"),
    gmail("retention-2", hoursAgo(27), {
      from: KARAN, to: TEJAS, subject: "re: numbers",
      body: "The GMV slide is fine. I keep coming back to the same question — what does the month-6 cohort look like after the self-hosted pivot?",
      received_at: "2026-05-26T11:05:00+05:30",
    }, "Karan — again on month-6 cohort post-pivot"),
    gmail("retention-3", hoursAgo(24), {
      from: KARAN, to: TEJAS, subject: "deck thoughts (partial)",
      body: "Skimmed v3 on a flight. Strong narrative. My partners will ask one thing: retention durability. Lead with the cohort curve, not the round.",
      received_at: "2026-05-29T08:15:00+05:30",
    }, "Karan — lead with the cohort curve, not the round"),

    // ── the deck is with him; silence since ──────────────────────────────
    gmail("deck-sent", hoursAgo(23), {
      from: KARAN, to: TEJAS, subject: "got it",
      body: "Deck v3 received. Give me a few days — I want to read it properly before we speak. Will revert with partner feedback.",
      received_at: "2026-05-30T16:00:00+05:30",
    }, "Karan — has deck v3, will revert with partner feedback"),

    // ── the to-be-contradicted fact (night 2 flips it) ───────────────────
    gmail("city-1", hoursAgo(22), {
      from: KARAN, to: TEJAS, subject: "logistics",
      body: "I'm based out of our Bangalore office through end of June, so let's keep everything on Zoom till then.",
      received_at: "2026-05-31T10:30:00+05:30",
    }, "Karan — in Bangalore through June, Zoom only"),

    // ── the red herring: expired logistics, must NOT become a note ───────
    gmail("herring", hoursAgo(21), {
      from: KARAN, to: TEJAS, subject: "2 min",
      body: "Left my charger at the cafe downstairs — grabbing it, dialing in right after.",
      received_at: "2026-06-01T13:58:00+05:30",
    }, "Karan — grabbing charger, dialing in after"),

    // ── a Karan meeting tomorrow, so the desk is set + predictions attach ─
    calendar("next-meeting", hoursAgo(20), {
      title: "Karan Mohla — partner feedback · Sequoia",
      startsAt: daysFromNowLocal(1, 14, 30),
      endsAt: daysFromNowLocal(1, 15, 0),
      location: "Zoom",
      attendees: [KARAN, TEJAS],
    }, "Karan — partner feedback call tomorrow 14:30"),
  ];
}

/** Night 2 — the contradiction: he moved. SUPERSEDE must fire on the Bangalore note. */
function night2Rows() {
  return [
    gmail("city-2", hoursAgo(1), {
      from: KARAN, to: TEJAS, subject: "change of plans",
      body: "Moved back to Mumbai this week — Bangalore stint ended early. Happy to do the next one in person at BKC.",
      received_at: hoursAgo(1),
    }, "Karan — back in Mumbai, in-person possible"),
  ];
}

/** Night 3 — the deck reply lands: the silence breaks, predictions can settle.
 *  arrivedAt is NOW (not back-dated): the resolver only counts evidence that
 *  arrived AFTER a prediction was made — real-time semantics the compressed
 *  rehearsal must respect. */
function night3Rows() {
  const now = new Date().toISOString();
  return [
    gmail("deck-reply", now, {
      from: KARAN, to: TEJAS, subject: "re: deck v3 — partner feedback",
      body: "Took it to Monday's partner meeting. Strong interest. Two asks before IC: the month-6 cohort table, and a self-hosted migration cost line. Can you walk me through both Thursday?",
      received_at: now,
    }, "Karan — partner feedback in, two asks before IC"),
  ];
}

function removeRehearsal(): void {
  db.delete(schema.signals).where(like(schema.signals.externalId, "rehearsal-%")).run();
  // Notes generated FROM rehearsal material are Ayumi's own — identified by
  // rehearsal receipts. Remove them (and their about-rows via FK cascade).
  const all = db.select().from(schema.observations).all();
  const rehearsalNotes = all.filter((o) => (o.receipts ?? []).some((r) => r.startsWith("rh-")));
  const noteIds = new Set(rehearsalNotes.map((o) => o.id));
  // Predictions carry no receipts — they're rehearsal-born iff their basedOn
  // pointers reference rehearsal notes. Remove those too, or they linger as
  // orphans and eat the open-predictions cap.
  const orphanPredictions = all.filter(
    (o) => o.kind === "prediction" && (o.basedOnIds ?? []).some((id) => noteIds.has(id)),
  );
  const toDelete = [...noteIds, ...orphanPredictions.map((o) => o.id)];
  if (toDelete.length > 0) {
    db.delete(schema.observations).where(inArray(schema.observations.id, toDelete)).run();
  }
  db.delete(schema.events).where(like(schema.events.dedupeKey, "rehearsal:%")).run();
  console.log(
    `[rehearsal] removed ${rehearsalNotes.length} generated notes + ${orphanPredictions.length} predictions + rehearsal signals/events`,
  );
}

/** The chain's once-per-LOCAL-day marker. The rehearsal compresses days, so
 *  night 1 clears today's marker — otherwise a memory pass that already ran
 *  today (real or a prior rehearsal) silently blocks the chained one. */
function clearTodaysMemoryMarker(): void {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  const localDay = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  // Yesterday's UTC bucket can also collide right around midnight — clear both.
  const utcDay = new Date().toISOString().slice(0, 10);
  for (const day of new Set([localDay, utcDay])) {
    db.delete(schema.events)
      .where(eq(schema.events.dedupeKey, `memory_consolidate:${day}`))
      .run();
  }
}

function removePlantedSliceB(): void {
  db.delete(schema.observations).where(like(schema.observations.id, "seed-karan-%")).run();
  db.delete(schema.signals).where(eq(schema.signals.externalId, "seed-karan-today")).run();
}

function enqueue(type: schema.EventType, dedupeKey: string): void {
  db.insert(schema.events)
    .values({
      id: randomUUID(),
      userId: USER,
      type,
      payload: {},
      dedupeKey,
      updatedAt: new Date().toISOString(),
    })
    .onConflictDoNothing()
    .run();
}

function main(): void {
  const arg = process.argv[2];
  if (arg === "--remove") {
    removeRehearsal();
    return;
  }
  const night = arg === "--night" ? Number(process.argv[3]) : NaN;
  if (![1, 2, 3].includes(night)) {
    console.error("usage: tsx scripts/seed-memory-rehearsal.ts --night 1|2|3 | --remove");
    process.exit(1);
  }

  if (night === 1) {
    // Fresh start: planted slice-B notes go away (Ayumi writes its own now),
    // and any prior rehearsal run is cleared so reruns are deterministic.
    removeRehearsal();
    removePlantedSliceB();
    clearTodaysMemoryMarker();
    for (const row of night1Rows()) {
      db.insert(schema.signals).values(row).onConflictDoNothing().run();
    }
    // Night 1 is the FULL loop: a real daily scan, which chains the memory pass.
    enqueue("daily_scan", "rehearsal:night-1-scan");
    console.log("[rehearsal] night 1 seeded (3-week batch) · daily_scan queued (memory pass chains off it)");
  } else if (night === 2) {
    for (const row of night2Rows()) {
      db.insert(schema.signals).values(row).onConflictDoNothing().run();
    }
    enqueue("memory_consolidate", "rehearsal:night-2-memory");
    console.log("[rehearsal] night 2 seeded (the Mumbai contradiction) · memory pass queued");
  } else {
    for (const row of night3Rows()) {
      db.insert(schema.signals).values(row).onConflictDoNothing().run();
    }
    // Predictions made on night 1 resolve in days; the rehearsal compresses
    // time instead of waiting — every open prediction falls due tonight.
    const today = new Date().toISOString().slice(0, 10);
    const open = db
      .select()
      .from(schema.observations)
      .where(eq(schema.observations.kind, "prediction"))
      .all()
      .filter((o) => !o.resolvedAt && o.resolveBy !== null && o.resolveBy > today);
    for (const p of open) {
      db.update(schema.observations)
        .set({ resolveBy: today, updatedAt: new Date().toISOString() })
        .where(eq(schema.observations.id, p.id))
        .run();
    }
    // Memory pass first (resolve + learn), THEN a fresh morning scan — so the
    // night-3 memo writes with the settled predictions and the grown notebook
    // in hand, and its lines can carry note_ids (the strike test needs them).
    enqueue("memory_consolidate", "rehearsal:night-3-memory");
    enqueue("daily_scan", "rehearsal:night-3-scan");
    console.log(
      `[rehearsal] night 3 seeded (deck reply lands) · ${open.length} prediction(s) pulled due · memory pass + morning scan queued`,
    );
  }
}

main();
