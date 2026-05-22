import Foundation
import SwiftData

/// v0.2 seed — briefs, proposals, watchers, signals + the morning page record.
/// Runs once if the database has no briefs yet. Pairs with v0.1 Seed (chapters
/// must already exist).
enum SeedV2 {
    @MainActor
    static func run(in context: ModelContext) {
        // Idempotent — if any brief exists, assume we've already seeded.
        let descriptor = FetchDescriptor<Brief>()
        if let count = try? context.fetchCount(descriptor), count > 0 {
            return
        }

        // Locate the v0.1 chapters by title.
        guard
            let chapters = try? context.fetch(FetchDescriptor<Chapter>()),
            let stratyfix = chapters.first(where: { $0.title.hasPrefix("Stratyfix") }),
            let health    = chapters.first(where: { $0.title.hasPrefix("Health") }),
            let move      = chapters.first(where: { $0.title.hasPrefix("Ireland") }),
            let trip      = chapters.first(where: { $0.title.hasPrefix("Varanasi") })
        else {
            return
        }

        // ─── Briefs ──────────────────────────────────────────────
        // 1. Karan — meeting prep
        let karanStructure = BriefStructure(sections: [
            .person(PersonData(
                name: "Karan Mohla",
                role: "Partner, Sequoia India",
                avatar: "KM",
                facts: [
                    "Led Series A in Mindtickle, Pixxel, Stoa.",
                    "Background: founder, exited 2014.",
                    "Writes a weekly memo on B2B SaaS retention.",
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
                    .init(date: "2026·03·02", text: "You sent the Q1 cohort numbers. He replied within an hour.", subtle: nil),
                    .init(date: "2026·04·28", text: "A. introduced him formally as a partner candidate.", subtle: nil),
                    .init(date: "2026·05·18", text: "You sent v3 of the deck. No reply yet.", subtle: true),
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
        context.insert(Brief(
            title: "Karan, in 90 minutes",
            situationDescription: "Second touch with Karan ahead of the seed round. He has v3 of the deck.",
            structureData: encode(karanStructure),
            chapter: stratyfix,
            chapterTitle: "Stratyfix seed round",
            relevance: "partner intro · second touch",
            when: "today · 14:30",
            drafted: "drafted 06:40",
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
            chapter: health,
            chapterTitle: "Portrait sitting",
            relevance: "second sitting · three left",
            when: "Thu · 11:00 · Bandra studio",
            drafted: "drafted 06:40",
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
            chapter: trip,
            chapterTitle: "Varanasi + Parvati Valley",
            relevance: "T−3d",
            when: "Sat · 06:30 departure",
            drafted: "drafted 06:40",
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

        try? context.save()
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}
