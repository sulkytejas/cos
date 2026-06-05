import { db } from "./client";
import { chapters, todos, decisions, entries, chapterLinks } from "./schema";
import { sql } from "drizzle-orm";
import { randomUUID } from "node:crypto";

function id() {
  return randomUUID();
}

function iso(date: string) {
  return new Date(date).toISOString();
}

export async function seedIfEmpty() {
  const existing = db
    .select({ count: sql<number>`count(*)` })
    .from(chapters)
    .all();

  if (existing[0]?.count && existing[0].count > 0) {
    console.log("[atlas] db already has data, skipping seed");
    return;
  }

  console.log("[atlas] seeding fresh database…");

  const trip = id();
  const move = id();
  const project = id();
  const health = id();

  db.insert(chapters)
    .values([
      {
        id: trip,
        title: "Varanasi + Parvati Valley",
        type: "trip",
        status: "upcoming",
        startDate: "2026-05-23",
        endDate: "2026-06-04",
        purpose:
          "Reset before the MBA. Kainchi blessing, Rishikesh stillness, Parvati for the wildness.",
      },
      {
        id: move,
        title: "Ireland MBA relocation",
        type: "move",
        status: "active",
        startDate: "2026-08-01",
        endDate: "2027-06-30",
        purpose:
          "MBA at Trinity Dublin. Build European optionality. Bridge between Stratyfix and what's next.",
      },
      {
        id: project,
        title: "Stratyfix seed round",
        type: "project",
        status: "active",
        startDate: "2026-05-01",
        endDate: "2026-08-15",
        purpose:
          "Karan at 14:30 today. Six notes this month; the open question is month-6 retention.",
      },
      {
        id: health,
        title: "Health baseline",
        type: "recurring",
        status: "active",
        startDate: "2026-01-01",
        endDate: null,
        purpose:
          "Gym 4x/week, tennis 2x/week, sleep 7h+. Maintain through the move.",
      },
    ])
    .run();

  db.insert(todos)
    .values([
      // Trip
      { id: id(), chapterId: trip, text: "Book BOM → PGH flight (May 23)", dueDate: "2026-05-15", done: true },
      { id: id(), chapterId: trip, text: "Reserve Ganga Kinare for 3 nights in Varanasi", dueDate: "2026-05-16", done: true },
      { id: id(), chapterId: trip, text: "Book Volvo sleeper Delhi → Manali", dueDate: "2026-05-20", done: false },
      { id: id(), chapterId: trip, text: "Kasol → Tosh shared cab arrangement", dueDate: "2026-05-28", done: false },
      { id: id(), chapterId: trip, text: "Pack trek shoes + rain shell", dueDate: "2026-05-22", done: false },
      { id: id(), chapterId: trip, text: "Buy offline maps for Parvati Valley", dueDate: "2026-05-22", done: false },
      { id: id(), chapterId: trip, text: "Stock cash — ATMs sparse past Kasol", dueDate: "2026-05-22", done: false },
      { id: id(), chapterId: trip, text: "Block calendar, set OOO for the team", dueDate: "2026-05-22", done: false },
      { id: id(), chapterId: trip, text: "Download books for Volvo overnight", dueDate: "2026-05-22", done: false },
      { id: id(), chapterId: trip, text: "Confirm Kainchi Dham timing with driver", dueDate: "2026-05-24", done: false },
      // Move
      { id: id(), chapterId: move, text: "Submit Irish student visa application", dueDate: "2026-06-01", done: false },
      { id: id(), chapterId: move, text: "Get bank statements apostilled", dueDate: "2026-05-28", done: false },
      { id: id(), chapterId: move, text: "Trinity housing portal — shortlist 5 options", dueDate: "2026-06-10", done: false },
      { id: id(), chapterId: move, text: "Open Revolut / N26 account for landing day", dueDate: "2026-06-15", done: false },
      { id: id(), chapterId: move, text: "Shipping quote — 2 boxes books + 1 box winter clothes", dueDate: "2026-07-01", done: false },
      { id: id(), chapterId: move, text: "Notify Stratyfix team — async transition plan", dueDate: "2026-06-15", done: false },
      { id: id(), chapterId: move, text: "Sublet Mumbai apartment for 11 months", dueDate: "2026-07-20", done: false },
      { id: id(), chapterId: move, text: "Tax residency calculation w/ CA", dueDate: "2026-07-10", done: false },
      { id: id(), chapterId: move, text: "Health insurance — Irish + travel cover", dueDate: "2026-07-25", done: false },
      { id: id(), chapterId: move, text: "Buy winter coat before Dublin Sept", dueDate: "2026-08-15", done: false },
      { id: id(), chapterId: move, text: "Forwarding address / mail consolidation", dueDate: "2026-07-25", done: false },
      { id: id(), chapterId: move, text: "Goodbye dinner — Mumbai close circle", dueDate: "2026-07-28", done: false },
      // Project
      { id: id(), chapterId: project, text: "Refine deck v3 — drop slides 12–15", dueDate: "2026-05-22", done: false },
      { id: id(), chapterId: project, text: "Schedule meetings with Accel, Lightspeed, Stellaris", dueDate: "2026-05-25", done: true },
      { id: id(), chapterId: project, text: "Finalize $49/seat pricing across all tiers", dueDate: "2026-05-30", done: false },
      { id: id(), chapterId: project, text: "Get one more LOI to anchor diligence", dueDate: "2026-06-10", done: false },
      { id: id(), chapterId: project, text: "Term sheet redlines w/ counsel", dueDate: "2026-07-01", done: false },
      { id: id(), chapterId: project, text: "Update data room — May numbers", dueDate: "2026-05-21", done: false },
      { id: id(), chapterId: project, text: "Founder references — line up 4", dueDate: "2026-06-05", done: false },
      { id: id(), chapterId: project, text: "Close commitments by Aug 1, wire by Aug 10", dueDate: "2026-08-01", done: false },
      // Health
      { id: id(), chapterId: health, text: "Gym 4x this week", dueDate: "2026-05-24", done: false },
      { id: id(), chapterId: health, text: "Tennis Tue + Sat", dueDate: "2026-05-23", done: false },
      { id: id(), chapterId: health, text: "Lights out by 11pm — track for 30 days", dueDate: "2026-06-15", done: false },
      { id: id(), chapterId: health, text: "Find tennis partner in Dublin (advance scout)", dueDate: "2026-07-15", done: false },
      { id: id(), chapterId: health, text: "Annual bloodwork before move", dueDate: "2026-07-20", done: false },
    ])
    .run();

  db.insert(decisions)
    .values([
      {
        id: id(),
        chapterId: trip,
        title: "Rishikesh over Bhutan for the second leg",
        rationale:
          "Bhutan is logistically heavy and expensive for a 12-day window. Rishikesh keeps the trip honest to its purpose — stillness, not novelty.",
        optionsConsidered:
          "1. Bhutan (Thimphu → Paro, ~$3.5k incl. SDF)\n2. Rishikesh (familiar, cheap, fits the reset theme)\n3. Sikkim (beautiful but adds a third hop)",
        decidedAt: iso("2026-05-08"),
      },
      {
        id: id(),
        chapterId: trip,
        title: "Kainchi → Varanasi → Parvati routing over direct Delhi entry",
        rationale:
          "Kainchi at the start sets the tone. Varanasi grounds it. Parvati is the release. Direct Delhi → Manali misses the arc.",
        optionsConsidered:
          "1. Delhi → Manali direct (efficient but bland)\n2. Kainchi → Varanasi → Manali (chosen)\n3. Mumbai → Goa → Manali (rejected — too soft an opening)",
        decidedAt: iso("2026-05-10"),
      },
      {
        id: id(),
        chapterId: move,
        title: "Trinity Dublin over UCD Smurfit",
        rationale:
          "Smurfit's brand is stronger in Europe but Trinity's general MBA gives me more optionality across sectors. Trinity campus is in the city — I want the city, not the suburbs.",
        optionsConsidered:
          "1. UCD Smurfit (stronger finance brand, suburban)\n2. Trinity Dublin (chosen — city, general management)\n3. ESADE Barcelona (great program, wrong city for me now)",
        decidedAt: iso("2026-03-15"),
      },
      {
        id: id(),
        chapterId: move,
        title: "Deferred from Jan 2026 to Aug 2026 intake",
        rationale:
          "Seed round timing made Jan unrealistic — would have been raising the round during orientation. Aug intake aligns: close round in Aug, land in Dublin Sept, classes start late Sept.",
        optionsConsidered:
          "1. Jan 2026 — original plan, but conflicts with raise\n2. Aug 2026 — chosen\n3. Jan 2027 — too late, momentum lost",
        decidedAt: iso("2026-02-20"),
      },
      {
        id: id(),
        chapterId: move,
        title: "Sublet Mumbai apartment, do not sell",
        rationale:
          "MBA is 11 months. Selling and re-entering the Mumbai market post-MBA is a worse deal than 11 months of friction subletting. Anchor in India matters psychologically too.",
        optionsConsidered:
          "1. Sell — clean break, lose Mumbai option\n2. Sublet (chosen) — 11 months, trusted PM\n3. Leave empty — wasteful",
        decidedAt: iso("2026-04-22"),
      },
      {
        id: id(),
        chapterId: project,
        title: "Cloud-hosted as primary over self-hosted",
        rationale:
          "Self-hosted demos better with enterprise but slows iteration. Cloud-first lets us ship weekly and our ICP (mid-market) actually prefers it. Self-hosted becomes an Enterprise SKU later.",
        optionsConsidered:
          "1. Self-hosted primary (slower, enterprise-friendly)\n2. Cloud primary (chosen — speed)\n3. Both at launch (rejected — split focus)",
        decidedAt: iso("2026-04-30"),
      },
      {
        id: id(),
        chapterId: project,
        title: "$49/seat pricing, no usage component",
        rationale:
          "Usage pricing was creating sales-cycle friction. $49/seat is simple, defensible, and lands inside discretionary budgets. We model 14% lower ARPA but ~2x velocity.",
        optionsConsidered:
          "1. $29/seat + usage (sticky but complex)\n2. $49/seat flat (chosen)\n3. $99/seat with bundled credits (too high for self-serve)",
        decidedAt: iso("2026-05-05"),
      },
    ])
    .run();

  db.insert(entries)
    .values([
      {
        id: id(),
        chapterId: trip,
        date: iso("2026-05-10"),
        content:
          "Talked to A. about Parvati. He said don't over-plan Tosh — three days, no agenda, just walk. Booking the rest tight, leaving that part loose.",
        source: "manual",
      },
      {
        id: id(),
        chapterId: trip,
        date: iso("2026-05-15"),
        content:
          "Flight booked. The whole arc finally feels real — Kainchi at 6am on the 24th. Will probably be the quietest morning of the year.",
        source: "manual",
      },
      {
        id: id(),
        chapterId: trip,
        date: iso("2026-05-18"),
        content:
          "Pulled the trek shoes out — soles cracked. Ordered new ones, arriving Wed. One small thing that would have ruined a day in the valley.",
        source: "manual",
      },
      {
        id: id(),
        chapterId: move,
        date: iso("2026-04-10"),
        content:
          "Trinity acceptance came through. Read the email twice. Mostly relief, then the move stack started forming itself in my head — visa, housing, banking, team.",
        source: "manual",
      },
      {
        id: id(),
        chapterId: move,
        date: iso("2026-05-02"),
        content:
          "Coffee with R. He did Trinity in '22 — said the first 6 weeks are a fog, don't decide anything important then. Filed that away.",
        source: "manual",
      },
      {
        id: id(),
        chapterId: move,
        date: iso("2026-05-12"),
        content:
          "Started a Dublin housing list. Stoneybatter keeps coming up. Walkable to campus, not the student bubble. Looking for a small place near the canal.",
        source: "manual",
      },
      {
        id: id(),
        chapterId: project,
        date: iso("2026-05-06"),
        content:
          "First Accel meeting today. They get the wedge, pushed hard on retention. Honest answer: cohorts are too young to call. Promised June numbers by next call.",
        source: "manual",
      },
      {
        id: id(),
        chapterId: project,
        date: iso("2026-05-15"),
        content:
          "Pricing change shipped to website. Two churns within 24h on the old plan, but three upgrades. Net positive but watching carefully.",
        source: "manual",
      },
    ])
    .run();

  db.insert(chapterLinks)
    .values([
      {
        fromId: move,
        toId: project,
        relation: "conflicts",
        note: "Ireland MBA overlaps the seed close. Need async coverage Aug 1–15.",
      },
      {
        fromId: project,
        toId: move,
        relation: "enables",
        note: "Closing the seed before move funds living costs + keeps CEO role credible from Dublin.",
      },
      {
        fromId: move,
        toId: trip,
        relation: "related",
        note: "Trip is the reset before the move — same arc.",
      },
    ])
    .run();

  console.log("[atlas] seed complete");
}

if (require.main === module) {
  seedIfEmpty()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error(err);
      process.exit(1);
    });
}
