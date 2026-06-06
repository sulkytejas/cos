import Foundation
import SwiftData

/// v0.2 seed — briefs, proposals, watchers, signals + the morning page record.
/// Plus the Today agentic flow v1 seed: the churn-slide brief and the morning
/// THREAD of `Turn` rows (the conversation Today now renders from data).
///
/// Each concern runs under its OWN existence guard so the seed is additive: an
/// already-seeded database (briefs present from a prior boot) still GAINS the
/// churn brief and the turns on the next launch, instead of being short-circuited
/// by a single top-level early-return. Pairs with v0.1 Seed (chapters must exist).
enum SeedV2 {
    @MainActor
    static func run(in context: ModelContext) {
        // Locate the v0.1 chapters by title (needed by every block below).
        guard
            let chapters = try? context.fetch(FetchDescriptor<Chapter>()),
            let stratyfix = chapters.first(where: { $0.title.hasPrefix("Stratyfix") }),
            let health    = chapters.first(where: { $0.title.hasPrefix("Health") }),
            let move      = chapters.first(where: { $0.title.hasPrefix("Ireland") }),
            let trip      = chapters.first(where: { $0.title.hasPrefix("Varanasi") })
        else {
            return
        }

        // ════════════════════════════════════════════════════════════
        //  Block A — the original v0.2 briefs / watchers / proposals.
        //  Guard: only if NO brief exists yet (the original idempotency).
        // ════════════════════════════════════════════════════════════
        let briefCount = (try? context.fetchCount(FetchDescriptor<Brief>())) ?? 0
        if briefCount == 0 {
            seedBriefsWatchersProposals(in: context, stratyfix: stratyfix,
                                        health: health, move: move, trip: trip)
        }

        // ════════════════════════════════════════════════════════════
        //  Block B — the churn-slide brief (Today agentic flow v1).
        //  Guard: only if no brief with that title exists yet.
        // ════════════════════════════════════════════════════════════
        let churnTitle = "Swap the churn slide"
        let hasChurn = ((try? context.fetch(FetchDescriptor<Brief>(
            predicate: #Predicate { $0.title == churnTitle }
        )))?.isEmpty == false)
        if !hasChurn {
            seedChurnBrief(in: context, stratyfix: stratyfix)
        }

        // ════════════════════════════════════════════════════════════
        //  Block C — the morning THREAD of turns (Today agentic flow v1).
        //  Guard: only if NO Turn row exists yet. Resolves the briefs +
        //  approved proposals the memo lines reference by content (they
        //  may have been inserted on a prior boot, by Block A above, or
        //  by the server delta-sync).
        // ════════════════════════════════════════════════════════════
        let turnCount = (try? context.fetchCount(FetchDescriptor<Turn>())) ?? 0
        if turnCount == 0 {
            seedTurns(in: context)
        }

        try? context.save()
    }

    // MARK: - Block A — briefs / watchers / proposals

    @MainActor
    private static func seedBriefsWatchersProposals(
        in context: ModelContext,
        stratyfix: Chapter, health: Chapter, move: Chapter, trip: Chapter
    ) {
        // ─── Briefs ──────────────────────────────────────────────
        // 1. Karan — meeting prep
        let karanStructure = BriefStructure(sections: [
            .person(PersonData(
                name: "Karan Mehta",
                role: "Partner · Sequoia India",
                avatar: "KM",
                facts: [
                    "Led your A round at Visu in '22.",
                    "Runs late — block 20 min, not 30.",
                    "Asked at Soam dinner: \"show me month-6 retention.\"",
                ],
                mutual: [
                    .init(name: "A. Iyer", via: "IIT Bombay '15"),
                    .init(name: "R. Shah", via: "Stoa cohort 7"),
                ]
            )),
            .timeline(TimelineData(
                title: "Your history with Karan",
                items: [
                    .init(date: "2026·01·14", text: "Dinner at Soam. He asked you to keep him posted on retention.", subtle: nil),
                    .init(date: "2026·03·02", text: "Liked your tweet about the M6 cohort curve — first sign he reads them.", subtle: true),
                    .init(date: "2026·04·11", text: "Coffee at Blue Tokai. He floated a $4M cheque, vague on terms.", subtle: nil),
                    .init(date: "2026·05·18", text: "No reply yet to the data-room email from Friday.", subtle: true),
                ]
            )),
            .prediction(PredictionData(
                title: "Likely to come up",
                items: [
                    .init(text: "Net retention by cohort — he'll want month 6 and month 12.", confidence: .high),
                    .init(text: "Why the pivot away from self-hosted.", confidence: .high),
                    .init(text: "Your CEO arrangement post-MBA — remote, hours, fallback.", confidence: .medium),
                    .init(text: "Hiring plan, specifically the second engineer.", confidence: .medium),
                    .init(text: "Whether you'd take a smaller round at a higher valuation.", confidence: .low),
                ]
            )),
            .materials(MaterialsData(
                title: "Have these open",
                items: [
                    .init(text: "Deck v3 — slide 7 (retention)", ready: true),
                    .init(text: "Cohort table — May numbers", ready: true),
                    .init(text: "CEO continuity memo — one-pager", ready: false),
                    .init(text: "Hiring plan", ready: false),
                ]
            )),
            .tactical(TacticalData(
                text: "He runs ten minutes late as a rule. Plan the meeting around twenty real minutes, not thirty. Lead with retention; the rest is buffer."
            )),
        ])
        // The Brief surface binds to the most-recently-surfaced Brief (BriefScreen
        // sorts by surfaceAt, reverse, .first). The Karan brief is the person-
        // bearing one that matches the reference, so it must win — give it the
        // latest surfaceAt; the Portrait/Trip briefs surface earlier.
        let now = Date()
        context.insert(Brief(
            title: "Karan, in 90 minutes",
            situationDescription: "Second touch with Karan ahead of the seed round. He has v3 of the deck.",
            structureData: encode(karanStructure),
            surfaceAt: now,
            chapter: stratyfix,
            chapterTitle: "Stratyfix seed round",
            relevance: "partner intro · second touch",
            when: "14:30",
            drafted: "6 sources · email, voice memo, calendar, deck v3",
            preview: "Likely to push on retention. He runs late — plan for 20 minutes, not 30.",
            primaryAction: "Open deck v3",
            secondaryActions: ["Snooze 1h", "Ask Ayumi to dig deeper"]
        ))

        // 2. Portrait sitting
        let sittingStructure = BriefStructure(sections: [
            .person(PersonData(
                name: "V. Sundaresan",
                role: "Painter · Bandra studio",
                avatar: "V",
                facts: [
                    "Working in oil; commission begun Mar 2026.",
                    "Sittings last 90 minutes, no breaks.",
                    "Prefers conversation, not silence.",
                ],
                mutual: [.init(name: "A. Iyer", via: "recommended her")]
            )),
            .quote(QuoteData(
                text: "I'm trying to keep the jaw soft. Don't shave the morning of — the line gets too clean and the painting goes flat.",
                attribution: "V., after the first sitting · Apr 11"
            )),
            .options(OptionsData(
                title: "What to wear",
                items: [
                    .init(label: "The charcoal linen shirt",
                          reasoning: "Matte. Holds shadow well under her north light. Crease-tolerant; you'll be still for 90 min.",
                          mark: "recommended"),
                    .init(label: "White cotton tee",
                          reasoning: "Too much bounce — V. mentioned last time the light flattens the face on white.",
                          mark: nil),
                    .init(label: "The navy overshirt",
                          reasoning: "You wore this for the first sitting. Repetition is fine; she's already painted the silhouette.",
                          mark: nil),
                ]
            )),
            .tactical(TacticalData(
                text: "Eat before — there are no breaks. Skip coffee within the hour; she said the small hand-tremors read in the eyes."
            )),
            .diff(DiffData(
                title: "Changed since the last brief",
                items: [
                    .init(kind: .added,   text: "Studio moved one block south, above the bakery. New door code 4417."),
                    .init(kind: .removed, text: "You no longer need to bring the reference photographs."),
                    .init(kind: .changed, text: "Sitting moved from 10:00 to 11:00 to catch better light."),
                ]
            )),
        ])
        context.insert(Brief(
            title: "Sitting for V., tomorrow 11:00",
            situationDescription: "Second sitting in V.'s commission, with three remaining. Studio moved.",
            structureData: encode(sittingStructure),
            surfaceAt: now.addingTimeInterval(-3600),   // surfaces before Karan
            chapter: health,
            chapterTitle: "Portrait sitting",
            relevance: "second sitting · three left",
            when: "11:00",
            drafted: "4 sources · calendar, email, voice memo, maps",
            preview: "She runs warm light all morning. Wear something matte, not pressed.",
            primaryAction: "Open route to studio",
            secondaryActions: ["Snooze", "Ask Ayumi to dig deeper"]
        ))

        // 3. Trip approaching
        let tripStructure = BriefStructure(sections: [
            .timeline(TimelineData(
                title: "Trip arc",
                items: [
                    .init(date: "May 23", text: "BOM → PGH; settle in at Ganga Kinare.", subtle: nil),
                    .init(date: "May 24", text: "Kainchi Dham — 6am visit, then drive to Varanasi.", subtle: nil),
                    .init(date: "May 26", text: "Volvo sleeper Delhi → Manali (overnight).", subtle: nil),
                    .init(date: "May 28", text: "Kasol → Tosh shared cab.", subtle: nil),
                    .init(date: "Jun 04", text: "Return.", subtle: true),
                ]
            )),
            .materials(MaterialsData(
                title: "Pack list",
                items: [
                    .init(text: "Trek shoes + rain shell", ready: false),
                    .init(text: "Offline maps for Parvati Valley", ready: false),
                    .init(text: "Cash — ATMs sparse past Kasol", ready: false),
                    .init(text: "Power bank + Volvo overnight playlist", ready: true),
                ]
            )),
            .tactical(TacticalData(
                text: "Stock cash in Manali, not Kasol. The valley ATMs are unreliable from the second week of May onward and offline maps will save you a guide fee at the Tosh fork."
            )),
            .watcher(WatcherSectionData(
                text: "Weather window across Parvati for trek days",
                cadence: "daily",
                last: nil
            )),
        ])
        context.insert(Brief(
            title: "Three days until Varanasi",
            situationDescription: "Departure in 72 hours; trip arc Kainchi → Varanasi → Parvati Valley with a tight packing window.",
            structureData: encode(tripStructure),
            surfaceAt: now.addingTimeInterval(-7200),   // surfaces before Karan
            chapter: trip,
            chapterTitle: "Varanasi + Parvati Valley",
            relevance: "T−3d",
            when: "06:30",
            drafted: "5 sources · email, calendar, drive, maps, weather",
            preview: "Pack list is light; cash and offline maps matter more than gear.",
            primaryAction: "Open packing list",
            secondaryActions: ["Snooze", "Ask Ayumi to dig deeper"]
        ))

        // ─── Watchers ────────────────────────────────────────────
        context.insert(Watcher(
            watcherDescription: "VFS appointment slots before Jun 28",
            prompt: "Check VFS website daily for Irish study permit appointment slots before Jun 28.",
            sourceType: .web,
            nextCheck: Date().addingTimeInterval(3 * 3600),
            cadenceMinutes: 180,
            cadenceLabel: "every 3h",
            chapter: move
        ))
        context.insert(Watcher(
            watcherDescription: "Karan's reply to the deck",
            prompt: "Look for any reply from karan@sequoiacap.com referencing v3 of the seed deck.",
            sourceType: .gmail,
            nextCheck: Date().addingTimeInterval(20 * 60),
            cadenceMinutes: 60,
            cadenceLabel: "on inbox",
            chapter: stratyfix
        ))
        context.insert(Watcher(
            watcherDescription: "Smruti's birthday — 11 days",
            prompt: "Surface a brief 3 days before Smruti's birthday with present ideas.",
            sourceType: .internalSource,
            nextCheck: Date().addingTimeInterval(8 * 3600),
            cadenceMinutes: 60 * 24,
            cadenceLabel: "daily",
            chapter: health
        ))
        context.insert(Watcher(
            watcherDescription: "Mumbai → Dublin flight prices",
            prompt: "Track AI/EI fare drift for Aug 25–28 BOM → DUB.",
            sourceType: .web,
            nextCheck: Date().addingTimeInterval(6 * 3600),
            cadenceMinutes: 60 * 6,
            cadenceLabel: "every 6h",
            chapter: move
        ))

        // ─── Proposals — split into filed (approved) + asked (pending) ─
        struct TodoPayload: Encodable { let text: String }
        struct DecisionPayload: Encodable { let title: String; let rationale: String }
        struct JournalPayload: Encodable { let content: String }

        context.insert(Proposal(
            type: .todo,
            proposedPayload: TodoPayload(text: "Reply to Karan about the retention slide"),
            confidence: 0.92,
            chapter: stratyfix,
            status: .approved,
            summary: "Added todo \"Reply to Karan about the retention slide\"",
            sourceLabel: "Email",
            sourceMeta: "from karan@sequoiacap.com · 06:12"
        ))
        context.insert(Proposal(
            type: .todo,
            proposedPayload: TodoPayload(text: "Book Volvo sleeper Manali → Kasol for May 26"),
            confidence: 0.90,
            chapter: trip,
            status: .approved,
            summary: "Added todo \"Book Volvo sleeper Manali → Kasol for May 26\"",
            sourceLabel: "Inferred",
            sourceMeta: "from itinerary"
        ))
        context.insert(Proposal(
            type: .journalEntry,
            proposedPayload: JournalPayload(content: "Filed 23 newsletters — none flagged for follow-up"),
            confidence: 0.95,
            chapter: nil,
            status: .approved,
            summary: "Filed 23 newsletters — none flagged for follow-up",
            sourceLabel: "Email",
            sourceMeta: "inbox · 04:00–06:30"
        ))
        // Asked — pending
        context.insert(Proposal(
            type: .decision,
            proposedPayload: DecisionPayload(
                title: "Trinity over UCD",
                rationale: "Network argument tips it."
            ),
            confidence: 0.70,
            chapter: move,
            status: .pending,
            summary: "Trinity over UCD — capture this decision?",
            sourceLabel: "Voice memo",
            sourceMeta: "walk · yesterday morning",
            question: "Is this",
            setup: "You said aloud on yesterday's walk that Trinity was decided in April. I want to capture it before it slips, but I'm not sure of its shape.",
            options: [
                .init(label: "a decision", value: "decision", result: "Will log to Ireland MBA Decisions with your reasoning attached.", type: "decision"),
                .init(label: "a journal note", value: "journal", result: "Will save as a journal entry in Ireland MBA relocation.", type: "journal_entry"),
            ]
        ))
        context.insert(Proposal(
            type: .journalEntry,
            proposedPayload: JournalPayload(content: "You came back to \"irreversibility\" three times when talking about V.'s objections."),
            confidence: 0.60,
            chapter: stratyfix,
            status: .pending,
            summary: "Three returns to 'irreversibility' — save as?",
            sourceLabel: "Voice memo",
            sourceMeta: "last night · 02:11",
            question: "Save it as",
            setup: "You came back to one phrase three times last night — \"irreversibility\" — when you talked about V.'s objections.",
            options: [
                .init(label: "a journal entry", value: "journal", result: "Will sit quietly under Stratyfix journal.", type: "journal_entry"),
                .init(label: "a finding for the brief", value: "finding", result: "Will pin it to your next Stratyfix brief.", type: "finding"),
            ]
        ))
    }

    // MARK: - Block B — the churn-slide brief (Today agentic flow v1)

    @MainActor
    private static func seedChurnBrief(in context: ModelContext, stratyfix: Chapter) {
        let churnStructure = BriefStructure(sections: [
            .tactical(TacticalData(
                text: "Replace slide 9 with the May cohort curve. Five minutes in Keynote; the old churn frame invites the wrong question."
            )),
        ])
        context.insert(Brief(
            title: "Swap the churn slide",
            situationDescription: "Deck v3 still carries the old churn slide; the cohort curve is stronger.",
            structureData: encode(churnStructure),
            surfaceAt: Date(),
            chapter: stratyfix,
            chapterTitle: "Stratyfix seed round",
            relevance: "deck v3",
            when: "today · 5 min",
            drafted: "drafted 07:16",
            preview: "The cohort curve is stronger than the churn slide.",
            primaryAction: "Swap it"
        ))
    }

    // MARK: - Block C — the morning thread of turns (Today agentic flow v1)

    @MainActor
    private static func seedTurns(in context: ModelContext) {
        // Resolve the briefs + approved proposals the memo lines reference. They
        // exist by now (Block A inserts them, or a prior boot / the server did),
        // so we look them up by their stable content rather than holding refs
        // across blocks — which also keeps Block C correct on an already-seeded DB.
        let karanBriefId = brief(in: context, title: "Karan, in 90 minutes")?.id
        let churnBriefId = brief(in: context, title: "Swap the churn slide")?.id
        let replyProposalId = proposal(
            in: context, summary: "Added todo \"Reply to Karan about the retention slide\""
        )?.id
        let newslettersProposalId = proposal(
            in: context, summary: "Filed 23 newsletters — none flagged for follow-up"
        )?.id

        // Timestamps are TODAY in the local timezone — set the wall-clock times
        // the thread reads against the morning scan.
        let cal = Calendar.current
        func today(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
        }

        // ── T1 — the morning turn (the redlineable memo) ────────────────
        let t1Lines: [TurnMemoLine] = [
            TurnMemoLine(
                id: UUID().uuidString,
                text: "A note from *Karan* landed at *03:42* — held until morning.",
                refKind: replyProposalId != nil ? "proposal" : nil,
                refId: replyProposalId?.uuidString.lowercased(),
                struck: false
            ),
            TurnMemoLine(
                id: UUID().uuidString,
                text: "Drafted the ==14:30== brief — opened with the cohort, not the round.",
                refKind: karanBriefId != nil ? "brief" : nil,
                refId: karanBriefId?.uuidString.lowercased(),
                struck: false
            ),
            TurnMemoLine(
                id: UUID().uuidString,
                text: "The portrait sitting shifted one block south — folded under your stack.",
                refKind: nil, refId: nil, struck: false
            ),
            TurnMemoLine(
                id: UUID().uuidString,
                text: "Filed *23* newsletters — none flagged.",
                refKind: newslettersProposalId != nil ? "proposal" : nil,
                refId: newslettersProposalId?.uuidString.lowercased(),
                struck: false
            ),
        ]
        context.insert(Turn(
            role: .ayumi, kind: .morning,
            body: "Karan at ==14:30== is prepared — opened with the cohort, not the round. Two changes folded; one note held.",
            sourceTag: "6 sources · email, voice memo, calendar, deck v3",
            briefIds: karanBriefId.map { [$0] },
            memo: TurnMemo(lines: t1Lines, status: "draft", keptAt: nil, keptBy: nil),
            // The connector suggestion opens Today's in-place CONNECT sheet — the
            // same generic surface for any supported source (gmail|calendar|drive),
            // so any of the three is a valid seed. We pick Calendar because this
            // morning's concrete gap is the rest of the day around Karan's 14:30
            // invite, which Calendar is exactly what would close.
            connector: TurnConnector(
                source: "calendar",
                copy: "I have Karan's invite but not the rest of your day — connect Calendar and I'll hold the hour around 14:30 clear."
            ),
            window: (start: today(2, 14), end: today(6, 38)),
            createdAt: today(6, 38), updatedAt: today(6, 38)
        ))

        // ── T2 — the user's reply ───────────────────────────────────────
        context.insert(Turn(
            role: .user, kind: .message,
            body: "thanks — anything else I should know before the call?",
            createdAt: today(7, 15), updatedAt: today(7, 15)
        ))

        // ── T3 — Ayumi thinking ──────────────────────────────────────────
        context.insert(Turn(
            role: .ayumi, kind: .thinking,
            body: "reading the deck and yesterday's voice memo…",
            createdAt: today(7, 15), updatedAt: today(7, 15)
        ))

        // ── T4 — Ayumi's follow-up message (references the churn brief) ──
        context.insert(Turn(
            role: .ayumi, kind: .message,
            body: "Two small things. Your ==deck v3== still has the old churn slide — I can swap it for the cohort curve in five minutes if you want. And *V.* emailed about Thursday with a softer studio time, ==11:30== instead of ==11:00== — I haven't accepted yet.",
            sourceTag: "3 sources · drive, gmail, calendar",
            briefIds: churnBriefId.map { [$0] },
            createdAt: today(7, 16), updatedAt: today(7, 16)
        ))
    }

    // MARK: - Lookups

    @MainActor
    private static func brief(in context: ModelContext, title: String) -> Brief? {
        try? context.fetch(FetchDescriptor<Brief>(
            predicate: #Predicate { $0.title == title }
        )).first
    }

    @MainActor
    private static func proposal(in context: ModelContext, summary: String) -> Proposal? {
        try? context.fetch(FetchDescriptor<Proposal>(
            predicate: #Predicate { $0.summary == summary }
        )).first
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}
