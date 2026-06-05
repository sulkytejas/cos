import Foundation
import SwiftData

enum Seed {
    static func run(in context: ModelContext) {
        let cal = Calendar(identifier: .gregorian)
        func ymd(_ y: Int, _ m: Int, _ d: Int, h: Int = 9, min: Int = 0) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? Date()
        }
        // Use *today's* date for the today-scoped todos so the HourRibbon shows pins.
        func today(_ h: Int, _ m: Int = 0) -> Date {
            let now = Date()
            let comps = cal.dateComponents([.year, .month, .day], from: now)
            return cal.date(from: DateComponents(
                year: comps.year, month: comps.month, day: comps.day, hour: h, minute: m
            )) ?? now
        }

        // ─── Chapters ──────────────────────────────────────────────
        let move = Chapter(
            title: "Ireland MBA relocation",
            type: .move,
            status: .active,
            startDate: ymd(2026, 8, 1),
            endDate: ymd(2027, 6, 30),
            purpose: "MBA at Trinity Dublin. Build European optionality. Bridge between Stratyfix and what comes next."
        )
        let project = Chapter(
            title: "Stratyfix seed round",
            type: .project,
            status: .active,
            startDate: ymd(2026, 5, 1),
            endDate: ymd(2026, 8, 15),
            // Design detail-strip copy (ref-chapters): Stratyfix is the default-
            // selected thread, so its purpose reads as the strip's description.
            purpose: "Karan at 14:30 today. Six notes this month; the open question is month-6 retention."
        )
        let health = Chapter(
            title: "Health baseline",
            type: .recurring,
            status: .active,
            startDate: ymd(2026, 1, 1),
            endDate: nil,
            purpose: "Gym 4×/week, tennis 2×/week, sleep 7h+. Maintain through the move."
        )
        let trip = Chapter(
            title: "Varanasi + Parvati Valley",
            type: .trip,
            status: .upcoming,
            startDate: ymd(2026, 5, 23),
            endDate: ymd(2026, 6, 4),
            purpose: "Reset before the MBA. Kainchi blessing, Rishikesh stillness, Parvati for the wildness."
        )

        [move, project, health, trip].forEach { context.insert($0) }

        // ─── Todos ─────────────────────────────────────────────────
        func todo(_ chapter: Chapter, _ text: String, due: Date? = nil, done: Bool = false) {
            context.insert(Todo(text: text, done: done, dueDate: due, chapter: chapter))
        }

        // Today-scoped (so the hour ribbon paints pins)
        todo(trip,    "Book Volvo sleeper Delhi → Manali", due: today(18, 30))
        todo(project, "Update data room — May numbers",     due: today(14, 0))
        todo(trip,    "Pack trek shoes + rain shell",       due: ymd(2026, 5, 22, h: 20))
        todo(trip,    "Buy offline maps for Parvati Valley", due: ymd(2026, 5, 22, h: 11))
        todo(trip,    "Stock cash — ATMs sparse past Kasol", due: ymd(2026, 5, 22, h: 16, min: 30))
        todo(move,    "Confirm Trinity I-20 equivalent",    due: ymd(2026, 5, 31, h: 10))

        // Trip — full list
        todo(trip, "Book BOM → PGH flight (May 23)", due: ymd(2026, 5, 15), done: true)
        todo(trip, "Reserve Ganga Kinare for 3 nights in Varanasi", due: ymd(2026, 5, 16), done: true)
        todo(trip, "Kasol → Tosh shared cab arrangement", due: ymd(2026, 5, 28))
        todo(trip, "Block calendar, set OOO for the team", due: ymd(2026, 5, 22))
        todo(trip, "Download books for Volvo overnight", due: ymd(2026, 5, 22))
        todo(trip, "Confirm Kainchi Dham timing with driver", due: ymd(2026, 5, 24))

        // Move — full list
        todo(move, "Submit Irish student visa application", due: ymd(2026, 6, 1))
        todo(move, "Get bank statements apostilled", due: ymd(2026, 5, 28))
        todo(move, "Trinity housing portal — shortlist 5 options", due: ymd(2026, 6, 10))
        todo(move, "Open Revolut / N26 account for landing day", due: ymd(2026, 6, 15))
        todo(move, "Shipping quote — 2 boxes books + 1 box winter clothes", due: ymd(2026, 7, 1))
        todo(move, "Notify Stratyfix team — async transition plan", due: ymd(2026, 6, 15))
        todo(move, "Sublet Mumbai apartment for 11 months", due: ymd(2026, 7, 20))
        todo(move, "Tax residency calculation w/ CA", due: ymd(2026, 7, 10))
        todo(move, "Health insurance — Irish + travel cover", due: ymd(2026, 7, 25))
        todo(move, "Buy winter coat before Dublin Sept", due: ymd(2026, 8, 15))
        todo(move, "Forwarding address / mail consolidation", due: ymd(2026, 7, 25))

        // Project — full list
        todo(project, "Refine deck v3 — drop slides 12–15", due: ymd(2026, 5, 22))
        todo(project, "Schedule meetings with Accel, Lightspeed, Stellaris", due: ymd(2026, 5, 25), done: true)
        todo(project, "Finalize $49/seat pricing across all tiers", due: ymd(2026, 5, 30))
        todo(project, "Get one more LOI to anchor diligence", due: ymd(2026, 6, 10))
        todo(project, "Term sheet redlines w/ counsel", due: ymd(2026, 7, 1))
        todo(project, "Founder references — line up 4", due: ymd(2026, 6, 5))
        todo(project, "Close commitments by Aug 1, wire by Aug 10", due: ymd(2026, 8, 1))

        // Health — full list
        todo(health, "Gym 4× this week", due: ymd(2026, 5, 24))
        todo(health, "Tennis Tue + Sat", due: ymd(2026, 5, 23))
        todo(health, "Lights out by 11pm — track for 30 days", due: ymd(2026, 6, 15))
        todo(health, "Find tennis partner in Dublin (advance scout)", due: ymd(2026, 7, 15))
        todo(health, "Annual bloodwork before move", due: ymd(2026, 7, 20))

        // ─── Decisions (prototype-matching) ───────────────────────
        context.insert(Decision(
            title: "Chose Trinity over UCD",
            rationale: "Trinity's alum network in tech is denser in London + Berlin. UCD had the better tuition deal but the European founder list at Trinity matters more for the post-MBA seed-to-A I'm planning.",
            optionsConsidered: "1. UCD Smurfit (stronger finance brand)\n2. Trinity Dublin (chosen)\n3. ESADE Barcelona (great program, wrong city)",
            decidedAt: ymd(2026, 4, 14), chapter: move
        ))
        context.insert(Decision(
            title: "Cloud over self-hosted for v2",
            rationale: "Two enterprise prospects asked about SOC2 — meeting them on cloud is six weeks; on self-hosted it is six months. We can revisit at $3M ARR.",
            optionsConsidered: "1. Self-hosted (slower, enterprise-friendly)\n2. Cloud-first (chosen)\n3. Both at launch (rejected)",
            decidedAt: ymd(2026, 5, 2), chapter: project
        ))
        context.insert(Decision(
            title: "Declined Bhutan extension",
            rationale: "Adds five days. Pushes the data-room update past the Lightspeed partner intro. Reset is still real with the current trip — don't stretch it.",
            optionsConsidered: "1. Bhutan (~$3.5k incl. SDF)\n2. Rishikesh-only reset (chosen)\n3. Add Sikkim leg (rejected)",
            decidedAt: ymd(2026, 5, 10), chapter: trip
        ))
        context.insert(Decision(
            title: "Deferred from Jan 2026 to Aug 2026 intake",
            rationale: "Seed round timing made Jan unrealistic — would have been raising the round during orientation. Aug aligns: close round in Aug, land in Dublin Sept.",
            optionsConsidered: "1. Jan 2026 (rejected — conflicts with raise)\n2. Aug 2026 (chosen)\n3. Jan 2027 (too late)",
            decidedAt: ymd(2026, 2, 20), chapter: move
        ))
        context.insert(Decision(
            title: "$49/seat pricing, no usage component",
            rationale: "Usage pricing was creating sales-cycle friction. $49/seat is simple, defensible, and lands inside discretionary budgets. We model 14% lower ARPA but ~2x velocity.",
            optionsConsidered: "1. $29/seat + usage (sticky but complex)\n2. $49/seat flat (chosen)\n3. $99/seat with bundled credits (too high for self-serve)",
            decidedAt: ymd(2026, 5, 5), chapter: project
        ))

        // ─── Entries (passive + manual) ───────────────────────────
        func entry(_ chapter: Chapter, _ on: Date, _ content: String, source: EntrySource = .manual) {
            context.insert(Entry(date: on, content: content, source: source, chapter: chapter))
        }
        entry(project, today(8, 12), "Sent the LOI redline to V. — moved the IP clause to a side letter.", source: .email)
        entry(project, today(11, 30), "Partner intro with Lightspeed (30 min). First touch since the Jan dinner.", source: .calendar)
        entry(project, ymd(2026, 5, 19), "Kept hearing \"irreversibility\" in V.'s objections — that's the real worry, not the burn.")
        entry(project, ymd(2026, 5, 18), "Touched Stratyfix — Seed Deck v3.key 14 times. The third pivot of the week on the ARR slide.", source: .drive)
        entry(trip, ymd(2026, 5, 10), "Talked to A. about Parvati. He said don't over-plan Tosh — three days, no agenda, just walk.")
        entry(move, ymd(2026, 5, 12), "Started a Dublin housing list. Stoneybatter keeps coming up. Walkable to campus, not the student bubble.")

        // ─── Links (chapter relations) ────────────────────────────
        context.insert(ChapterLink(from: move, to: project, relation: .blocks,
                                   note: "data-room update must land before LP intro"))
        context.insert(ChapterLink(from: move, to: health, relation: .enables,
                                   note: "Trinity gym access kicks in Aug 26"))
        context.insert(ChapterLink(from: project, to: trip, relation: .conflicts,
                                   note: "overlaps deck deadline by 4 days"))
        context.insert(ChapterLink(from: health, to: trip, relation: .enables,
                                   note: "trek fitness compounds"))

        try? context.save()
    }
}
