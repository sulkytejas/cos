import Foundation
import SwiftData

enum Seed {
    static func run(in context: ModelContext) {
        let cal = Calendar(identifier: .gregorian)
        func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d)) ?? Date()
        }

        let trip = Chapter(
            title: "Varanasi + Parvati Valley",
            type: .trip,
            status: .upcoming,
            startDate: ymd(2026, 5, 23),
            endDate: ymd(2026, 6, 4),
            purpose: "Reset before the MBA. Kainchi blessing, Rishikesh stillness, Parvati for the wildness."
        )
        let move = Chapter(
            title: "Ireland MBA relocation",
            type: .move,
            status: .active,
            startDate: ymd(2026, 8, 1),
            endDate: ymd(2027, 6, 30),
            purpose: "MBA at Trinity Dublin. Build European optionality. Bridge between Stratyfix and what's next."
        )
        let project = Chapter(
            title: "Stratyfix seed round",
            type: .project,
            status: .active,
            startDate: ymd(2026, 5, 1),
            endDate: ymd(2026, 8, 15),
            purpose: "Close $1.5M seed before MBA starts. Maintain CEO role remotely post-move."
        )
        let health = Chapter(
            title: "Health baseline",
            type: .recurring,
            status: .active,
            startDate: ymd(2026, 1, 1),
            endDate: nil,
            purpose: "Gym 4x/week, tennis 2x/week, sleep 7h+. Maintain through the move."
        )

        [trip, move, project, health].forEach { context.insert($0) }

        func todo(_ chapter: Chapter, _ text: String, due: Date? = nil, done: Bool = false) {
            let t = Todo(text: text, done: done, dueDate: due, chapter: chapter)
            context.insert(t)
        }

        // Trip
        todo(trip, "Book BOM → PGH flight (May 23)", due: ymd(2026, 5, 15), done: true)
        todo(trip, "Reserve Ganga Kinare for 3 nights in Varanasi", due: ymd(2026, 5, 16), done: true)
        todo(trip, "Book Volvo sleeper Delhi → Manali", due: ymd(2026, 5, 20))
        todo(trip, "Kasol → Tosh shared cab arrangement", due: ymd(2026, 5, 28))
        todo(trip, "Pack trek shoes + rain shell", due: ymd(2026, 5, 22))
        todo(trip, "Buy offline maps for Parvati Valley", due: ymd(2026, 5, 22))
        todo(trip, "Stock cash — ATMs sparse past Kasol", due: ymd(2026, 5, 22))
        todo(trip, "Block calendar, set OOO for the team", due: ymd(2026, 5, 22))
        todo(trip, "Download books for Volvo overnight", due: ymd(2026, 5, 22))
        todo(trip, "Confirm Kainchi Dham timing with driver", due: ymd(2026, 5, 24))

        // Move
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
        todo(move, "Goodbye dinner — Mumbai close circle", due: ymd(2026, 7, 28))

        // Project
        todo(project, "Refine deck v3 — drop slides 12–15", due: ymd(2026, 5, 22))
        todo(project, "Schedule meetings with Accel, Lightspeed, Stellaris", due: ymd(2026, 5, 25), done: true)
        todo(project, "Finalize $49/seat pricing across all tiers", due: ymd(2026, 5, 30))
        todo(project, "Get one more LOI to anchor diligence", due: ymd(2026, 6, 10))
        todo(project, "Term sheet redlines w/ counsel", due: ymd(2026, 7, 1))
        todo(project, "Update data room — May numbers", due: ymd(2026, 5, 21))
        todo(project, "Founder references — line up 4", due: ymd(2026, 6, 5))
        todo(project, "Close commitments by Aug 1, wire by Aug 10", due: ymd(2026, 8, 1))

        // Health
        todo(health, "Gym 4x this week", due: ymd(2026, 5, 24))
        todo(health, "Tennis Tue + Sat", due: ymd(2026, 5, 23))
        todo(health, "Lights out by 11pm — track for 30 days", due: ymd(2026, 6, 15))
        todo(health, "Find tennis partner in Dublin (advance scout)", due: ymd(2026, 7, 15))
        todo(health, "Annual bloodwork before move", due: ymd(2026, 7, 20))

        // Decisions
        func decision(_ chapter: Chapter, _ title: String, _ rationale: String, _ options: String, _ on: Date) {
            context.insert(Decision(title: title, rationale: rationale, optionsConsidered: options, decidedAt: on, chapter: chapter))
        }

        decision(trip,
                 "Rishikesh over Bhutan for the second leg",
                 "Bhutan is logistically heavy and expensive for a 12-day window. Rishikesh keeps the trip honest to its purpose — stillness, not novelty.",
                 "1. Bhutan (Thimphu → Paro, ~$3.5k incl. SDF)\n2. Rishikesh (familiar, cheap, fits the reset theme)\n3. Sikkim (beautiful but adds a third hop)",
                 ymd(2026, 5, 8))
        decision(trip,
                 "Kainchi → Varanasi → Parvati routing over direct Delhi entry",
                 "Kainchi at the start sets the tone. Varanasi grounds it. Parvati is the release. Direct Delhi → Manali misses the arc.",
                 "1. Delhi → Manali direct (efficient but bland)\n2. Kainchi → Varanasi → Manali (chosen)\n3. Mumbai → Goa → Manali (rejected — too soft an opening)",
                 ymd(2026, 5, 10))
        decision(move,
                 "Trinity Dublin over UCD Smurfit",
                 "Smurfit's brand is stronger in Europe but Trinity's general MBA gives me more optionality across sectors. Trinity campus is in the city — I want the city, not the suburbs.",
                 "1. UCD Smurfit (stronger finance brand, suburban)\n2. Trinity Dublin (chosen — city, general management)\n3. ESADE Barcelona (great program, wrong city for me now)",
                 ymd(2026, 3, 15))
        decision(move,
                 "Deferred from Jan 2026 to Aug 2026 intake",
                 "Seed round timing made Jan unrealistic — would have been raising the round during orientation. Aug intake aligns: close round in Aug, land in Dublin Sept, classes start late Sept.",
                 "1. Jan 2026 — original plan, but conflicts with raise\n2. Aug 2026 — chosen\n3. Jan 2027 — too late, momentum lost",
                 ymd(2026, 2, 20))
        decision(move,
                 "Sublet Mumbai apartment, do not sell",
                 "MBA is 11 months. Selling and re-entering the Mumbai market post-MBA is a worse deal than 11 months of friction subletting. Anchor in India matters psychologically too.",
                 "1. Sell — clean break, lose Mumbai option\n2. Sublet (chosen) — 11 months, trusted PM\n3. Leave empty — wasteful",
                 ymd(2026, 4, 22))
        decision(project,
                 "Cloud-hosted as primary over self-hosted",
                 "Self-hosted demos better with enterprise but slows iteration. Cloud-first lets us ship weekly and our ICP (mid-market) actually prefers it. Self-hosted becomes an Enterprise SKU later.",
                 "1. Self-hosted primary (slower, enterprise-friendly)\n2. Cloud primary (chosen — speed)\n3. Both at launch (rejected — split focus)",
                 ymd(2026, 4, 30))
        decision(project,
                 "$49/seat pricing, no usage component",
                 "Usage pricing was creating sales-cycle friction. $49/seat is simple, defensible, and lands inside discretionary budgets. We model 14% lower ARPA but ~2x velocity.",
                 "1. $29/seat + usage (sticky but complex)\n2. $49/seat flat (chosen)\n3. $99/seat with bundled credits (too high for self-serve)",
                 ymd(2026, 5, 5))

        // Entries
        func entry(_ chapter: Chapter, _ on: Date, _ content: String) {
            context.insert(Entry(date: on, content: content, chapter: chapter))
        }

        entry(trip, ymd(2026, 5, 10), "Talked to A. about Parvati. He said don't over-plan Tosh — three days, no agenda, just walk. Booking the rest tight, leaving that part loose.")
        entry(trip, ymd(2026, 5, 15), "Flight booked. The whole arc finally feels real — Kainchi at 6am on the 24th. Will probably be the quietest morning of the year.")
        entry(trip, ymd(2026, 5, 18), "Pulled the trek shoes out — soles cracked. Ordered new ones, arriving Wed. One small thing that would have ruined a day in the valley.")
        entry(move, ymd(2026, 4, 10), "Trinity acceptance came through. Read the email twice. Mostly relief, then the move stack started forming itself in my head — visa, housing, banking, team.")
        entry(move, ymd(2026, 5, 2), "Coffee with R. He did Trinity in '22 — said the first 6 weeks are a fog, don't decide anything important then. Filed that away.")
        entry(move, ymd(2026, 5, 12), "Started a Dublin housing list. Stoneybatter keeps coming up. Walkable to campus, not the student bubble. Looking for a small place near the canal.")
        entry(project, ymd(2026, 5, 6), "First Accel meeting today. They get the wedge, pushed hard on retention. Honest answer: cohorts are too young to call. Promised June numbers by next call.")
        entry(project, ymd(2026, 5, 15), "Pricing change shipped to website. Two churns within 24h on the old plan, but three upgrades. Net positive but watching carefully.")

        // Links
        context.insert(ChapterLink(from: move, to: project, relation: .conflicts,
                                   note: "Ireland MBA overlaps the seed close. Need async coverage Aug 1–15."))
        context.insert(ChapterLink(from: project, to: move, relation: .enables,
                                   note: "Closing the seed before move funds living costs + keeps CEO role credible from Dublin."))
        context.insert(ChapterLink(from: move, to: trip, relation: .related,
                                   note: "Trip is the reset before the move — same arc."))

        try? context.save()
    }
}
