/**
 * v0.2 seed — lays briefs / proposals / watchers / signals on top of the
 * v0.1 chapter/todo/decision/entry data so the Today + Review + Brief
 * screens have realistic content on first launch.
 *
 * Idempotent: returns early if any brief already exists.
 */
import { db } from "./client";
import {
  briefs,
  proposals,
  watchers,
  signals,
  chapters,
  chapterLinks,
  turns,
} from "./schema";
import { randomUUID } from "node:crypto";
import { sql, eq, and, isNull } from "drizzle-orm";

function id() {
  return randomUUID();
}

function isoFromNow(deltaSeconds: number) {
  return new Date(Date.now() + deltaSeconds * 1000).toISOString();
}

/** Today, local clock, set to HH:MM — the thread renders "while you slept" times off these. */
function todayAtLocal(hours: number, minutes: number) {
  const d = new Date();
  d.setHours(hours, minutes, 0, 0);
  return d.toISOString();
}

export async function seedV2IfEmpty() {
  const existing = db.select({ count: sql<number>`count(*)` }).from(briefs).all();
  if ((existing[0]?.count ?? 0) > 0) {
    console.log("[atlas v0.2] briefs already seeded, skipping");
    // The churn brief + the Today thread (turns) land in their OWN guards so an
    // already-seeded DB (pre-dating the Today agentic flow) still gains them on
    // the next boot, without re-seeding the rest of v0.2.
    seedTurnsAndChurnBrief();
    return;
  }

  // Find chapter ids by title (we don't hardcode UUIDs)
  const allChapters = db.select().from(chapters).all();
  const byTitle = (t: string) => allChapters.find((c) => c.title.startsWith(t))?.id;
  const stratyfix = byTitle("Stratyfix");
  const health = byTitle("Health");
  const move = byTitle("Ireland");
  const trip = byTitle("Varanasi");

  if (!stratyfix || !health || !move || !trip) {
    console.log("[atlas v0.2] v0.1 chapters not yet seeded; skipping v0.2 seed for now");
    return;
  }

  console.log("[atlas v0.2] seeding briefs, proposals, watchers, signals…");

  // ─── Signals (raw inbox) ────────────────────────────────────────
  const overnight = new Date();
  overnight.setHours(2, 14, 0, 0);
  const overnightIso = overnight.toISOString();

  const newsletterSignals = Array.from({ length: 20 }).map((_, i) => ({
    id: id(),
    source: "gmail" as const,
    externalId: `newsletter-${i}`,
    summary: "(newsletter)",
    rawData: { from: `news-${i}@stratechery.com`, subject: "filed quietly", body: "" },
    arrivedAt: new Date(overnight.getTime() + i * 8 * 60 * 1000).toISOString(),
    processed: true,
  }));

  db.insert(signals).values(newsletterSignals).run();

  const karanEmailId = id();
  db.insert(signals)
    .values([
      {
        id: karanEmailId,
        source: "gmail",
        externalId: "karan-deck-1",
        summary: "Karan — saw the deck, can we chat Thurs?",
        rawData: {
          from: "karan@sequoiacap.com",
          subject: "Saw the deck",
          body: "Want to talk through retention; specifically month-6 cohort and the pivot away from self-hosted. Thursday 2:30pm work?",
          received_at: "2026-05-21T06:12:00+05:30",
        },
        arrivedAt: "2026-05-21T06:12:00+05:30",
        processed: true,
      },
      {
        id: id(),
        source: "calendar",
        externalId: "karan-cal-1",
        summary: "Karan Mohla — partner intro",
        rawData: {
          title: "Karan Mohla — partner intro · Sequoia",
          startsAt: "2026-05-21T14:30:00+05:30",
          attendees: ["karan@sequoiacap.com", "tejas@stratyfix.com"],
        },
        arrivedAt: "2026-05-20T22:00:00+05:30",
        processed: true,
      },
      {
        id: id(),
        source: "calendar",
        externalId: "sitting-cal-1",
        summary: "Sitting with V. — Bandra studio",
        rawData: {
          title: "Sitting with V.",
          startsAt: "2026-05-22T11:00:00+05:30",
          location: "Bandra studio (above the bakery, code 4417)",
        },
        arrivedAt: "2026-05-21T04:18:00+05:30",
        processed: true,
      },
      {
        id: id(),
        source: "drive",
        externalId: "deck-arr-1",
        summary: "Seed Deck v3 — ARR slide touched 14× this week",
        rawData: { doc: "Stratyfix — Seed Deck v3.key", slide: "ARR (7)", edits_last_7d: 14 },
        arrivedAt: "2026-05-21T03:42:00+05:30",
        processed: true,
      },
      {
        id: id(),
        source: "voice",
        externalId: "walk-1",
        summary: "Voice memo — yesterday's walk",
        rawData: { text: "Trinity over UCD. The network argument tips the balance." },
        arrivedAt: "2026-05-20T11:30:00+05:30",
        processed: true,
      },
    ])
    .run();

  // ─── Briefs (3 examples of different shapes) ────────────────────
  const karanBriefId = id();
  const sittingBriefId = id();
  const tripBriefId = id();
  const now = new Date().toISOString();

  db.insert(briefs)
    .values([
      // 1) Meeting prep — the Karan brief, fully composed.
      {
        id: karanBriefId,
        chapterId: stratyfix,
        title: "Karan, in 90 minutes",
        situationDescription:
          "Second touch with Karan ahead of the seed round. He has v3 of the deck.",
        structure: {
          sections: [
            {
              kind: "person",
              data: {
                name: "Karan Mohla",
                role: "Partner, Sequoia India",
                avatar: "KM",
                facts: [
                  "Led Series A in Mindtickle, Pixxel, Stoa.",
                  "Background: founder, exited 2014.",
                  "Writes a weekly memo on B2B SaaS retention.",
                ],
                mutual: [
                  { name: "A. Iyer", via: "IIT Bombay '15" },
                  { name: "R. Shah", via: "Stoa cohort 7" },
                ],
              },
            },
            {
              kind: "timeline",
              data: {
                title: "Your history with Karan",
                items: [
                  { date: "2026·01·14", text: "Dinner at Soam. He asked you to keep him posted on retention." },
                  { date: "2026·03·02", text: "You sent the Q1 cohort numbers. He replied within an hour." },
                  { date: "2026·04·28", text: "A. introduced him formally as a partner candidate for the seed." },
                  { date: "2026·05·18", text: "You sent v2 of the deck. No reply yet.", subtle: true },
                ],
              },
            },
            {
              kind: "prediction",
              data: {
                title: "Likely to come up",
                items: [
                  { text: "Net retention by cohort — he'll want month 6 and month 12.", confidence: "high" },
                  { text: "Why the pivot away from self-hosted.", confidence: "high" },
                  { text: "Your CEO arrangement post-MBA — remote, hours, fallback.", confidence: "medium" },
                  { text: "Hiring plan, specifically the second engineer.", confidence: "medium" },
                  { text: "Whether you'd take a smaller round at a higher valuation.", confidence: "low" },
                ],
              },
            },
            {
              kind: "materials",
              data: {
                title: "Have these open",
                items: [
                  { text: "Deck v3 — slide 7 (retention)", ready: true },
                  { text: "Cohort table — May numbers", ready: true },
                  { text: "CEO continuity memo — one-pager", ready: false },
                  { text: "Hiring plan", ready: false },
                ],
              },
            },
            {
              kind: "tactical",
              data: {
                text: "He runs ten minutes late as a rule. Plan the meeting around twenty real minutes, not thirty. Lead with retention; the rest is buffer.",
              },
            },
          ],
        },
        primaryAction: "Open deck v3",
        secondaryActions: ["Snooze 1h", "Ask Atlas to dig deeper"],
        status: "surfaced",
        surfaceAt: now,
        expiresAt: isoFromNow(72 * 3600),
        chapterTitle: "Stratyfix seed round",
        relevance: "partner intro · second touch",
        when: "today · 14:30",
        drafted: "drafted 06:40",
        preview: "Likely to push on retention. He runs late — plan for 20 minutes, not 30.",
        agentTrace: { trace: [], raw: "(seeded)", error: null, validation: "ok" },
      },

      // 2) Creative session — the sitting brief.
      {
        id: sittingBriefId,
        chapterId: health,
        title: "Sitting for V., tomorrow 11:00",
        situationDescription:
          "Second sitting in V.'s commission, with three remaining. Studio moved.",
        structure: {
          sections: [
            {
              kind: "person",
              data: {
                name: "V. Sundaresan",
                role: "Painter · Bandra studio",
                avatar: "V",
                facts: [
                  "Working in oil; commission begun Mar 2026.",
                  "Sittings last 90 minutes, no breaks.",
                  "Prefers conversation, not silence.",
                ],
                mutual: [{ name: "A. Iyer", via: "recommended her" }],
              },
            },
            {
              kind: "quote",
              data: {
                text: "I'm trying to keep the jaw soft. Don't shave the morning of — the line gets too clean and the painting goes flat.",
                attribution: "V., after the first sitting · Apr 11",
              },
            },
            {
              kind: "options",
              data: {
                title: "What to wear",
                items: [
                  {
                    label: "The charcoal linen shirt",
                    reasoning:
                      "Matte. Holds shadow well under her north light. Crease-tolerant; you'll be still for 90 min.",
                    mark: "recommended",
                  },
                  {
                    label: "White cotton tee",
                    reasoning: "Too much bounce — V. mentioned last time the light flattens the face on white.",
                  },
                  {
                    label: "The navy overshirt",
                    reasoning: "You wore this for the first sitting. Repetition is fine; she's already painted the silhouette.",
                  },
                ],
              },
            },
            {
              kind: "tactical",
              data: {
                text: "Eat before — there are no breaks. Skip coffee within the hour; she said the small hand-tremors read in the eyes.",
              },
            },
            {
              kind: "diff",
              data: {
                title: "Changed since the last brief",
                items: [
                  { kind: "added", text: "Studio moved one block south, above the bakery. New door code 4417." },
                  { kind: "removed", text: "You no longer need to bring the reference photographs." },
                  { kind: "changed", text: "Sitting moved from 10:00 to 11:00 to catch better light." },
                ],
              },
            },
          ],
        },
        primaryAction: "Open route to studio",
        secondaryActions: ["Snooze", "Ask Atlas to dig deeper"],
        status: "surfaced",
        surfaceAt: now,
        expiresAt: isoFromNow(36 * 3600),
        chapterTitle: "Portrait sitting",
        relevance: "second sitting · three left",
        when: "Thu · 11:00 · Bandra studio",
        drafted: "drafted 06:40",
        preview: "She runs warm light all morning. Wear something matte, not pressed.",
        agentTrace: { trace: [], raw: "(seeded)", error: null, validation: "ok" },
      },

      // 3) Trip approaching — a lighter shape (timeline + materials + tactical + watcher)
      {
        id: tripBriefId,
        chapterId: trip,
        title: "Three days until Varanasi",
        situationDescription:
          "Departure in 72 hours; trip arc Kainchi → Varanasi → Parvati Valley with a tight packing window.",
        structure: {
          sections: [
            {
              kind: "timeline",
              data: {
                title: "Trip arc",
                items: [
                  { date: "May 23", text: "BOM → PGH; settle in at Ganga Kinare." },
                  { date: "May 24", text: "Kainchi Dham — 6am visit, then drive to Varanasi." },
                  { date: "May 26", text: "Volvo sleeper Delhi → Manali (overnight)." },
                  { date: "May 28", text: "Kasol → Tosh shared cab." },
                  { date: "Jun 04", text: "Return.", subtle: true },
                ],
              },
            },
            {
              kind: "materials",
              data: {
                title: "Pack list",
                items: [
                  { text: "Trek shoes + rain shell", ready: false },
                  { text: "Offline maps for Parvati Valley", ready: false },
                  { text: "Cash — ATMs sparse past Kasol", ready: false },
                  { text: "Power bank + Volvo overnight playlist", ready: true },
                ],
              },
            },
            {
              kind: "tactical",
              data: {
                text: "Stock cash in Manali, not Kasol. The valley ATMs are unreliable from the second week of May onward and the offline maps will save you a guide fee at the Tosh fork.",
              },
            },
            {
              kind: "watcher",
              data: {
                text: "Weather window across Parvati for trek days",
                cadence: "daily",
              },
            },
          ],
        },
        primaryAction: "Open packing list",
        secondaryActions: ["Snooze", "Ask Atlas to dig deeper"],
        status: "surfaced",
        surfaceAt: now,
        expiresAt: isoFromNow(72 * 3600),
        chapterTitle: "Varanasi + Parvati Valley",
        relevance: "T−3d",
        when: "Sat · 06:30 departure",
        drafted: "drafted 06:40",
        preview: "Pack list is light; cash and offline maps matter more than gear.",
        agentTrace: { trace: [], raw: "(seeded)", error: null, validation: "ok" },
      },
    ])
    .run();

  // ─── Watchers ───────────────────────────────────────────────────
  db.insert(watchers)
    .values([
      {
        id: id(),
        chapterId: move,
        description: "VFS appointment slots before Jun 28",
        prompt: "Check VFS website daily for Irish study permit appointment slots before Jun 28.",
        sourceType: "web",
        nextCheck: isoFromNow(3 * 3600),
        cadenceMinutes: 180,
        cadenceLabel: "every 3h",
        status: "active",
      },
      {
        id: id(),
        chapterId: stratyfix,
        description: "Karan's reply to the deck",
        prompt: "Look for any reply from karan@sequoiacap.com referencing v3 of the seed deck",
        sourceType: "gmail",
        nextCheck: isoFromNow(20 * 60),
        cadenceMinutes: 60,
        cadenceLabel: "on inbox",
        status: "active",
      },
      {
        id: id(),
        chapterId: health,
        description: "Smruti's birthday — 11 days",
        prompt: "Surface a brief 3 days before Smruti's birthday with present ideas.",
        sourceType: "internal",
        nextCheck: isoFromNow(8 * 3600),
        cadenceMinutes: 60 * 24,
        cadenceLabel: "daily",
        status: "active",
      },
    ])
    .run();

  // ─── Proposals ──────────────────────────────────────────────────
  // 5 filed (Atlas was confident) + 3 asked (medium/low) = 8 visible in queue,
  // plus a handful of "lower noise" filed examples.
  //
  // Two of these ids are hoisted so the morning turn's memo lines can point a
  // `refKind:'proposal'` line back at the underlying proposal: the Karan-reply
  // todo and the "filed 23 newsletters" journal note (Today agentic flow v1).
  const karanReplyProposalId = id();
  const newslettersProposalId = id();
  db.insert(proposals)
    .values([
      // ── Filed high-confidence (status='approved' with decided_at = today) ──
      {
        id: karanReplyProposalId,
        type: "todo",
        proposedPayload: { text: "Reply to Karan about the retention slide", chapterId: stratyfix },
        sourceBriefId: karanBriefId,
        sourceSignalIds: [karanEmailId],
        chapterId: stratyfix,
        status: "approved",
        confidence: 0.92,
        summary: 'Added todo "Reply to Karan about the retention slide"',
        sourceLabel: "Email",
        sourceMeta: "from karan@sequoiacap.com · 06:12",
        decidedAt: now,
        decidedPayload: { text: "Reply to Karan about the retention slide" },
      },
      {
        id: id(),
        type: "todo",
        proposedPayload: { text: "Book Volvo sleeper Manali → Kasol for May 26", chapterId: trip },
        chapterId: trip,
        status: "approved",
        confidence: 0.9,
        summary: 'Added todo "Book Volvo sleeper Manali → Kasol for May 26"',
        sourceLabel: "Inferred",
        sourceMeta: "from itinerary",
        decidedAt: now,
        decidedPayload: { text: "Book Volvo sleeper Manali → Kasol for May 26" },
      },
      {
        id: id(),
        type: "todo",
        proposedPayload: { text: "Confirm Trinity I-20 equivalent", chapterId: move },
        chapterId: move,
        status: "approved",
        confidence: 0.91,
        summary: 'Added todo "Confirm Trinity I-20 equivalent"',
        sourceLabel: "Email",
        sourceMeta: "from registry@tcd.ie",
        decidedAt: now,
        decidedPayload: { text: "Confirm Trinity I-20 equivalent" },
      },
      {
        id: newslettersProposalId,
        type: "journal_entry",
        proposedPayload: {
          content: "Filed 23 newsletters — none flagged for follow-up",
          chapterId: null,
        },
        chapterId: null,
        status: "approved",
        confidence: 0.95,
        summary: "Filed 23 newsletters — none flagged for follow-up",
        sourceLabel: "Email",
        sourceMeta: "inbox · 04:00–06:30",
        decidedAt: now,
        decidedPayload: { content: "Filed 23 newsletters — none flagged for follow-up" },
      },
      {
        id: id(),
        type: "todo",
        proposedPayload: { text: "Buy offline maps for Parvati Valley", chapterId: trip },
        chapterId: trip,
        status: "approved",
        confidence: 0.93,
        summary: 'Added todo "Buy offline maps for Parvati Valley"',
        sourceLabel: "Inferred",
        sourceMeta: "from itinerary",
        decidedAt: now,
        decidedPayload: { text: "Buy offline maps for Parvati Valley" },
      },

      // ── Asked (pending — show up in the Review Queue) ──
      {
        id: id(),
        type: "decision",
        proposedPayload: {
          title: "Trinity over UCD",
          rationale: "Network argument tips it.",
          chapterId: move,
        },
        chapterId: move,
        status: "pending",
        confidence: 0.7,
        summary: "Trinity over UCD — capture this decision?",
        sourceLabel: "Voice memo",
        sourceMeta: "walk · yesterday morning",
        setup:
          "You said aloud on yesterday's walk that Trinity was decided in April. I want to capture it before it slips, but I'm not sure of its shape.",
        question: "Is this",
        options: [
          {
            label: "a decision",
            value: "decision",
            type: "decision",
            result: "Will log to Ireland MBA Decisions with your reasoning attached.",
          },
          {
            label: "a journal note",
            value: "journal",
            type: "journal_entry",
            result: "Will save as a journal entry in Ireland MBA relocation.",
          },
        ],
      },
      {
        id: id(),
        type: "journal_entry",
        proposedPayload: {
          content: 'You came back to "irreversibility" three times when talking about V.\'s objections.',
          chapterId: stratyfix,
        },
        chapterId: stratyfix,
        status: "pending",
        confidence: 0.6,
        summary: "Three returns to 'irreversibility' — save as?",
        sourceLabel: "Voice memo",
        sourceMeta: "last night · 02:11",
        setup:
          "You came back to one phrase three times last night — \"irreversibility\" — when you talked about V.'s objections.",
        question: "Save it as",
        options: [
          {
            label: "a journal entry",
            value: "journal",
            type: "journal_entry",
            result: "Will sit quietly under Stratyfix journal.",
          },
          {
            label: "a finding for the brief",
            value: "finding",
            type: "finding",
            result: "Will pin it to your next Stratyfix brief.",
          },
        ],
      },
      {
        id: id(),
        type: "journal_entry",
        proposedPayload: {
          content: "Touched ARR slide 14 times this week — by far the most-edited slide.",
          chapterId: stratyfix,
        },
        chapterId: stratyfix,
        status: "pending",
        confidence: 0.45,
        summary: "ARR slide edited 14× this week — signal or noise?",
        sourceLabel: "Drive",
        sourceMeta: "passive · last 7 days",
        setup:
          "You've touched the ARR slide of the seed deck 14 times this week — more than any other slide, by a lot.",
        question: "Worth noting as",
        options: [
          {
            label: "a signal",
            value: "signal",
            type: "journal_entry",
            result: "Will journal it; you can revisit when you reread the deck.",
          },
          {
            label: "noise",
            value: "noise",
            type: "noise",
            result: "I will stop counting edits on this deck for now.",
          },
        ],
      },
      // Two more "Atlas filed" examples to round out the queue
      {
        id: id(),
        type: "todo",
        proposedPayload: { text: "Schedule second engineer phone screens", chapterId: stratyfix },
        chapterId: stratyfix,
        status: "approved",
        confidence: 0.88,
        summary: 'Added todo "Schedule second engineer phone screens"',
        sourceLabel: "Calendar",
        sourceMeta: "from Karan call prep",
        decidedAt: now,
        decidedPayload: { text: "Schedule second engineer phone screens" },
      },
      {
        id: id(),
        type: "todo",
        proposedPayload: { text: "Stock cash before Manali — ATMs sparse past Kasol", chapterId: trip },
        chapterId: trip,
        status: "approved",
        confidence: 0.94,
        summary: 'Added todo "Stock cash — ATMs sparse past Kasol"',
        sourceLabel: "Inferred",
        sourceMeta: "from prior trip notes",
        decidedAt: now,
        decidedPayload: { text: "Stock cash before Manali — ATMs sparse past Kasol" },
      },
      {
        id: id(),
        type: "journal_entry",
        proposedPayload: {
          content: "Karan acknowledged receipt of v3 of the deck.",
          chapterId: stratyfix,
        },
        chapterId: stratyfix,
        status: "approved",
        confidence: 0.97,
        summary: "Logged Karan's deck acknowledgement",
        sourceLabel: "Email",
        sourceMeta: "from karan@sequoiacap.com · 06:12",
        decidedAt: now,
        decidedPayload: { content: "Karan acknowledged receipt of v3 of the deck." },
      },
      // One proposed chapter link — used by Constellation's dotted-edge UI
      {
        id: id(),
        type: "chapter_link",
        proposedPayload: {
          fromId: stratyfix,
          toId: health,
          relation: "related",
          note: "Sleep loss on the ARR slide is starting to show in your health logs.",
        },
        chapterId: stratyfix,
        status: "pending",
        confidence: 0.55,
        summary: 'Link "Stratyfix seed round" → "Health baseline" as related?',
        sourceLabel: "Inferred",
        sourceMeta: "from journal cross-references",
        setup:
          "Two journal entries this week mention sleep loss tied to the deck work. I noticed but haven't linked anything.",
        question: "Should I",
        options: [
          {
            label: "link them as related",
            value: "related",
            type: "chapter_link",
            result: "Will draw a dotted edge in the Constellation map.",
          },
          {
            label: "let it ride",
            value: "noise",
            type: "noise",
            result: "I'll keep watching but not link them yet.",
          },
        ],
      },
    ])
    .run();

  // Also write one "proposed" chapter link directly (separate from the pending
  // proposal above) so the Constellation has a dotted edge to render even
  // before the user reviews the proposal.
  db.insert(chapterLinks)
    .values({
      fromId: stratyfix,
      toId: health,
      relation: "related",
      note: "Atlas-proposed: sleep loss showing in health logs",
      proposed: true,
    })
    .onConflictDoNothing()
    .run();

  console.log("[atlas v0.2] seeded 3 briefs, 12 proposals, 3 watchers, ~25 signals");

  // The Today thread + the churn brief — their own guards (see below) make this
  // safe to call after a fresh seed too.
  seedTurnsAndChurnBrief();
}

/**
 * The Today agentic flow's seed content — a churn-slide Brief and the four
 * conversational turns that make up the morning thread (Today agentic flow v1).
 *
 * Runs in its OWN existence guards (the churn brief by title, the turns by an
 * empty `turns` table) so it lands on a freshly-seeded DB AND backfills a DB that
 * was seeded before this flow existed. Ids for the briefs/proposals the memo
 * lines reference are looked up from the DB (not minted here) so the refs point
 * at the rows the main seed actually created.
 */
function seedTurnsAndChurnBrief() {
  // Resolve the chapters + the brief/proposal rows the turn content points at.
  const allChapters = db.select().from(chapters).all();
  const stratyfix = allChapters.find((c) => c.title.startsWith("Stratyfix"))?.id;
  if (!stratyfix) {
    console.log("[atlas today] Stratyfix chapter not yet seeded; skipping turn seed for now");
    return;
  }

  const now = new Date().toISOString();

  // ─── 4th brief: "Swap the churn slide" (own existence guard, by title) ───
  let churnBriefId = db
    .select({ id: briefs.id })
    .from(briefs)
    .where(and(eq(briefs.title, "Swap the churn slide"), isNull(briefs.deletedAt)))
    .get()?.id;

  if (!churnBriefId) {
    churnBriefId = id();
    db.insert(briefs)
      .values({
        id: churnBriefId,
        chapterId: stratyfix,
        title: "Swap the churn slide",
        situationDescription:
          "Deck v3 still carries the old churn slide; the cohort curve is stronger.",
        structure: {
          sections: [
            {
              kind: "tactical",
              data: {
                text: "Replace slide 9 with the May cohort curve. Five minutes in Keynote; the old churn frame invites the wrong question.",
              },
            },
          ],
        },
        primaryAction: "Swap it",
        status: "surfaced",
        surfaceAt: now,
        chapterTitle: "Stratyfix seed round",
        relevance: "deck v3",
        when: "today · 5 min",
        drafted: "drafted 07:16",
        preview: "The cohort curve is stronger than the churn slide.",
        agentTrace: { trace: [], raw: "(seeded)", error: null, validation: "ok" },
      })
      .run();
    console.log("[atlas today] seeded the churn-slide brief");
  }

  // ─── Turns (own guard: only when the thread is empty) ───
  const turnCount = db.select({ count: sql<number>`count(*)` }).from(turns).all();
  if ((turnCount[0]?.count ?? 0) > 0) {
    console.log("[atlas today] turns already seeded, skipping");
    return;
  }

  // The memo lines reference the Karan-reply todo proposal + the filed-newsletters
  // journal proposal + the Karan brief. Look them up by their seeded shape.
  const karanBriefId = db
    .select({ id: briefs.id })
    .from(briefs)
    .where(and(eq(briefs.title, "Karan, in 90 minutes"), isNull(briefs.deletedAt)))
    .get()?.id ?? null;
  const karanReplyProposalId = db
    .select({ id: proposals.id })
    .from(proposals)
    .where(and(eq(proposals.summary, 'Added todo "Reply to Karan about the retention slide"'), isNull(proposals.deletedAt)))
    .get()?.id ?? null;
  const newslettersProposalId = db
    .select({ id: proposals.id })
    .from(proposals)
    .where(and(eq(proposals.summary, "Filed 23 newsletters — none flagged for follow-up"), isNull(proposals.deletedAt)))
    .get()?.id ?? null;

  // Today, local clock: the thread renders 06:38 / 07:15 / 07:15 / 07:16.
  const t1At = todayAtLocal(6, 38);
  const t2At = todayAtLocal(7, 15);
  const t3At = todayAtLocal(7, 15);
  const t4At = todayAtLocal(7, 16);

  db.insert(turns)
    .values([
      // T1 — the morning turn: verdict on Today + a redlineable memo in Review.
      {
        id: id(),
        role: "ayumi",
        kind: "morning",
        body: "Karan at ==14:30== is prepared — opened with the cohort, not the round. Two changes folded; one note held.",
        sourceTag: "6 sources · email, voice memo, calendar, deck v3",
        briefIds: karanBriefId ? [karanBriefId] : null,
        memo: {
          lines: [
            {
              id: id(),
              text: "A note from *Karan* landed at *03:42* — held until morning.",
              refKind: "proposal",
              refId: karanReplyProposalId,
              struck: false,
            },
            {
              id: id(),
              text: "Drafted the ==14:30== brief — opened with the cohort, not the round.",
              refKind: "brief",
              refId: karanBriefId,
              struck: false,
            },
            {
              id: id(),
              text: "The portrait sitting shifted one block south — folded under your stack.",
              refKind: null,
              refId: null,
              struck: false,
            },
            {
              id: id(),
              text: "Filed *23* newsletters — none flagged.",
              refKind: "proposal",
              refId: newslettersProposalId,
              struck: false,
            },
          ],
          status: "draft",
          keptAt: null,
          keptBy: null,
        },
        // The connector suggestion is mirrored to iOS, where the Today
        // connector-line CTA routes to the North India Living Chapter's
        // ConnectorsSection — the only live surface that actually grants a
        // source. That section has Gmail/Health/Maps/HDFC/IRCTC/Calendar but NO
        // Drive row, so the seed promises the source that surface CAN grant:
        // Calendar (one of the spec's allowed sources gmail|calendar|drive).
        connector: {
          source: "calendar",
          copy: "I have Karan's invite but not the rest of your day — connect Calendar and I'll hold the hour around 14:30 clear.",
        },
        meta: { windowStart: todayAtLocal(2, 14), windowEnd: t1At },
        createdAt: t1At,
        updatedAt: t1At,
      },
      // T2 — the user's reply.
      {
        id: id(),
        role: "user",
        kind: "message",
        body: "thanks — anything else I should know before the call?",
        createdAt: t2At,
        updatedAt: t2At,
      },
      // T3 — the transient "thinking" beat.
      {
        id: id(),
        role: "ayumi",
        kind: "thinking",
        body: "reading the deck and yesterday's voice memo…",
        createdAt: t3At,
        updatedAt: t3At,
      },
      // T4 — her follow-up, embedding the churn-slide brief.
      {
        id: id(),
        role: "ayumi",
        kind: "message",
        body: "Two small things. Your ==deck v3== still has the old churn slide — I can swap it for the cohort curve in five minutes if you want. And *V.* emailed about Thursday with a softer studio time, ==11:30== instead of ==11:00== — I haven't accepted yet.",
        sourceTag: "3 sources · drive, gmail, calendar",
        briefIds: churnBriefId ? [churnBriefId] : null,
        createdAt: t4At,
        updatedAt: t4At,
      },
    ])
    .run();

  console.log("[atlas today] seeded 4 turns (1 morning + 1 user + 1 thinking + 1 message)");
}

if (require.main === module) {
  seedV2IfEmpty()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error(err);
      process.exit(1);
    });
}
