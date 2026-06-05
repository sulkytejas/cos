import SwiftUI
import SwiftData

/// Search — one index over everything. A search field, scope chips, grouped
/// results with the query highlighted, and an Ayumi plain-words answer card.
struct SearchScreen: View {
    @Environment(HaloController.self) private var halo
    @Environment(\.modelContext) private var context
    @Environment(AtlasRepo.self) private var repo
    @Environment(NavRouter.self) private var router
    @Query private var briefs: [Brief]
    @Query private var entries: [Entry]
    @Query private var decisions: [Decision]
    @Query private var todos: [Todo]
    @Query private var chapters: [Chapter]
    @State private var query = ""
    @State private var scope: RType? = nil
    @State private var ragAnswer: String? = nil          // real grounded answer
    @State private var ragCache: [String: String] = [:]  // by "scope|query"
    @State private var settleTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    enum RType: String, CaseIterable { case brief, note, todo, person, chapter }
    struct Result: Identifiable { let id = UUID(); let type: RType; let title: String; let meta: String; let kw: String }
    struct Answer { let keys: [String]; let text: String }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // In-content topbar (back link left + app-mark right) replaces the
            // shell app-mark on Search — the shell suppresses AppMark for .search
            // (see sharedRequests), matching the reference's two-ended topbar.
            // CSS `.topbar{top:30px}` → content band starts at the app-mark offset.
            topbar.padding(.horizontal, 20)
            // CSS `.body-area{inset:64px…}` + `.search-head{padding:8px 24px 12px}`.
            // The field's absolute y is fixed by `body-area top:64 + search-head
            // top:8` (≈72pt below the page top); the topbar is `position:absolute`
            // and does NOT push it down. In this VStack the field stacks below the
            // topbar, so the top gap clears the topbar's own height AND restores the
            // `body-area` top inset the absolute CSS layout opens between the
            // topbar band and the search head — at 13pt the whole body block rode
            // ~5pt too high (pass-9: field/chips/Ayumi card all ~15-20px high).
            // 18pt seats the field at the reference y and carries the chips + card
            // down with it. 12pt bottom = `.search-head` padding-bottom:12.
            searchField.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
            // CSS `.scopes{padding:10px 24px 4px}` — 10pt above the chip row (on top
            // of the field's 12pt bottom = ~22pt combined gap) and 6pt below (CSS 4
            // + ~2pt to recover the last ~2px of the Ayumi card's downward drift so
            // its top lands at the reference y720 not y700).
            scopeRow.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 6)
            results
        }
        .padding(.top, 30)              // CSS .topbar top:30 (same band as the shell app-mark)
        .onAppear {
            // DEV: seed a query via `simctl launch … --query Ireland` for screenshots.
            // Default to the prototype's seeded "retention" so the screen
            // demonstrates its populated state (matches the design reference).
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--query"), i + 1 < args.count {
                query = args[i + 1]
            } else if query.isEmpty {
                query = "retention"
            }
            runSettle()
        }
        .onChange(of: query) { _, _ in onChange() }
        .onChange(of: scope) { _, _ in onChange() }
    }

    // ─── Topbar (replaces the shell app-mark on Search) ──────────────
    /// Reference top chrome: a left `‹ Today` back-affordance (sans 14, ink-2)
    /// and a right `A SEARCH ▾` app-mark (serif-italic glyph + mono crumb).
    private var topbar: some View {
        HStack(alignment: .center, spacing: 0) {
            Button { withAnimation(Theme.Motion.overshoot()) { router.go(.today) } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .regular))
                    Text("Today").font(Theme.Font.sans(14))
                }
                .foregroundStyle(Theme.Palette.ink2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            // CSS .app-mark: serif-italic glyph 19 (ink) + mono crumb 9 (ink-3).
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("A").font(Theme.Font.serifItalic(19)).foregroundStyle(Theme.Palette.ink).tracking(-0.38)
                Text("SEARCH ▾").font(Theme.Font.mono(9)).tracking(1.44).foregroundStyle(Theme.Palette.ink3)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // ─── Search field ─────────────────────────────────────────────
    private var live: Bool { !query.isEmpty }
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .regular)).foregroundStyle(Theme.Palette.inkFaint)
            ZStack(alignment: .leading) {
                // Empty: italic gray placeholder. Typed: upright serif, dark ink
                // (matches the ref's "retention" query, which is non-italic).
                if query.isEmpty {
                    Text("Search everything…").font(Theme.Font.serifItalic(18)).foregroundStyle(Theme.Palette.inkFaint)
                }
                TextField("", text: $query)
                    .font(Theme.Font.serif(18)).foregroundStyle(Theme.Palette.ink)
                    .focused($focused).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if live {
                // CSS .clear: mono 9, letter-spacing 0.1em (→0.9pt), ink-3, uppercase.
                // The reference seats CLEAR ~9pt inside the field content edge (its
                // right edge sits well clear of the field border), not flush at the
                // 14pt field padding. Add ~7pt trailing padding so CLEAR lands at the
                // same right inset as the design (pass-7: SIM sat ~7pt too far right).
                Button { query = ""; focused = true } label: {
                    Text("CLEAR").font(Theme.Font.mono(9)).tracking(0.9).foregroundStyle(Theme.Palette.ink3)
                }.buttonStyle(.plain).padding(.trailing, 7)
            }
        }
        // CSS .search-field: padding 12 14, radius 14, paper-deep fill.
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Palette.paperDeep)
                // .live border rgba(0,137,168,0.4) 1px / idle faint rule. CSS `border`
                // paints fully INSIDE the box, so use `.strokeBorder` (not `.stroke`,
                // which straddles the edge) — that keeps the sampled border at the full
                // teal-0.4 saturation (≈rgb 149,204,217 over #f7f7f5) rather than the
                // washed read a half-outside stroke composites against the tan margin.
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(live ? Theme.Palette.teal.opacity(0.4) : Theme.Palette.rule, lineWidth: 1))
        )
        // .live glow: box-shadow 0 0 0 3px rgba(0,137,168,0.08) — a SOLID 3pt teal ring
        // that sits strictly OUTSIDE the field box (CSS box-shadow spread does not
        // overlap the border). A 3pt-wide `.strokeBorder` on a rect outset by 3pt
        // (negative padding) draws the ring entirely beyond the 1pt border, so the
        // teal-0.08 ring no longer composites over the teal-0.4 border and pale it.
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(Theme.Palette.teal.opacity(live ? 0.08 : 0), lineWidth: 3)
                .padding(-3)
        )
        .animation(.easeInOut(duration: 0.22), value: live)
    }

    private var scopeRow: some View {
        // Six chips don't fit one phone-width row — wrap whole chips onto a
        // second line (like the mock) instead of wrapping the label to "BRIE/FS".
        FlowLayout(spacing: 6) {
            chip("All", nil)
            chip("Briefs", .brief)
            chip("Notes", .note)
            chip("People", .person)
            chip("Chapters", .chapter)
            chip("Todos", .todo)
        }
    }
    private func chip(_ label: String, _ t: RType?) -> some View {
        let on = scope == t
        return Button { withAnimation(.easeOut(duration: 0.18)) { scope = t } } label: {
            Text(label.uppercased()).font(Theme.Font.mono(9)).tracking(1.0)
                .lineLimit(1).fixedSize()
                .foregroundStyle(on ? .white : Theme.Palette.inkFaint)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(Capsule().fill(on ? Theme.Palette.ink : Color.clear))
                .overlay(Capsule().stroke(on ? Theme.Palette.ink : Theme.Palette.rule, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    // ─── Results ──────────────────────────────────────────────────
    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let answerText = displayedAnswer {
                    ayumiAnswer(answerText)
                }
                let groups = grouped
                if query.isEmpty {
                    emptyState("Ask anything.", "Briefs, notes, people, chapters, todos — all in one place.")
                } else if groups.isEmpty && displayedAnswer == nil {
                    emptyState("Nothing yet.", "Try \"retention\", \"Karan\", or \"Ireland\".")
                } else {
                    ForEach(Array(groups.enumerated()), id: \.element.0) { gi, group in
                        let (type, items) = group
                        // CSS .gl: mono 9, 0.18em (→1.62pt), ink-3; count `.ct` ink-4.
                        // CSS `.res-group{margin-top:14}` on every group. The FIRST
                        // group follows the Ayumi answer (whose own 4pt bottom margin
                        // already opens part of the gap), so its label takes a reduced
                        // 10pt top — 4 + 10 ≈ the ref's ~17pt answer→label gap (pass-7:
                        // the SIM read ~21pt with a flat 14pt top here). Later groups
                        // keep the full 14pt res-group margin between sections.
                        (Text(groupLabel(type)).foregroundColor(Theme.Palette.ink3)
                            + Text(" · \(items.count)").foregroundColor(Theme.Palette.ink4))
                            .font(Theme.Font.mono(9)).tracking(1.62)
                            .padding(.bottom, 8).padding(.top, gi == 0 ? 10 : 14)
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            row(item, last: idx == items.count - 1)
                        }
                    }
                }
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 24).padding(.top, 8)
        }
        // Match the shared scroll-window pattern (Review: bottom inset 22) —
        // results clip above the home-indicator band instead of riding over it.
        .padding(.bottom, 22)
    }

    // ─── Ayumi answer bubble ──────────────────────────────────────
    // CSS `.ayumi-answer { margin:8px 0 4px; padding:14px 16px; radius:12px;
    // background:linear-gradient(180deg,#dceae0,#cfe2d6); color:#16321e }` with a
    // top-left white radial sheen (`::before`). Rendered inline (not via the
    // shared JadeCard, whose 16/18 padding ran the bubble ~10pt too tall) so the
    // vertical extent matches the reference: padding 14 top/bottom, 16 sides.
    // CSS `.ayumi-answer { margin:8px 0 4px }` — its OWN 8pt top margin sits on top
    // of the results `.padding(.top, 8)`, so the band sits ~20pt below the chips
    // (scopes pb:4 + results pt:8 + ayumi mt:8), matching the reference (pass-4:
    // the SIM was ~7pt too tight). The 4pt bottom margin is added here too.
    private func ayumiAnswer(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // CSS .k: mono 9, 0.16em (→1.44pt); .a: serif-italic 16, line-height 1.45.
            Text("AYUMI").font(Theme.Font.mono(9)).tracking(1.44).foregroundStyle(Theme.Palette.jadeCardInk.opacity(0.7))
            Text(text).font(Theme.Font.serifItalic(16)).foregroundStyle(Theme.Palette.jadeCardInk)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Palette.jadeCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        // .ayumi-answer::before — white radial sheen confined to the
                        // top-left. CSS paints it into a 60%×90% box at top:-30%
                        // left:-10%, fading to clear at 60% of that box — it must NOT
                        // reach the band's bottom, or it lightens the #cfe2d6 bottom
                        // gradient stop (pass-4: SIM bottom read ~#d7e7dc, too light).
                        // A tight endRadius keeps the sheen top-left so the bottom
                        // shows the pure jade-card gradient.
                        .fill(RadialGradient(colors: [Color.white.opacity(0.5), .clear],
                                             center: UnitPoint(x: -0.1, y: -0.3), startRadius: 0, endRadius: 130))
                        .allowsHitTesting(false)
                )
        )
        .padding(.top, 8)      // CSS .ayumi-answer margin-top 8 (on top of results pt:8)
        .padding(.bottom, 4)   // CSS margin-bottom 4
    }

    private func row(_ item: Result, last: Bool) -> some View {
        // CSS `.res .b { flex:1; min-width:0 }` — the title column takes ALL the
        // width the row leaves after the 20pt icon + 11pt gap (card-inner −
        // results pad 24×2). The serif title must use that full width or it wraps
        // ~10-15px early (pass-4: note1 "He wants month-6 retention before he
        // commits." spilled to 2 lines). `.frame(maxWidth:.infinity)` on the body
        // claims the slack (no trailing Spacer to compete) and `.fixedSize(…)` lets
        // the title use the whole column before wrapping.
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 5).fill(typeColor(item.type)).frame(width: 20, height: 20).padding(.top, 2)
            // `.b { flex:1; min-width:0 }` — the column must take ALL the slack the
            // row leaves after the 20pt icon + 11pt gap. Claim it on the VStack
            // itself (not only the inner Text) so the title is proposed the full
            // ~314pt column width and wraps at the reference point — "SaaS retention"
            // on line 1, "teardown." on line 2 — instead of one word too early.
            VStack(alignment: .leading, spacing: 3) {
                Text(highlighted(item.title))
                    .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.meta).font(Theme.Font.mono(9)).tracking(0.4).foregroundStyle(Theme.Palette.inkFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.Palette.ruleSoft).frame(height: 1) } }
    }

    private func emptyState(_ a: String, _ b: String) -> some View {
        VStack(spacing: 8) {
            Text(a).font(Theme.Font.serifItalic(22)).foregroundStyle(Theme.Palette.ink2)
            Text(b).font(Theme.Font.serifItalic(14)).foregroundStyle(Theme.Palette.ink3)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50).padding(.horizontal, 24)
    }

    // ─── Logic ────────────────────────────────────────────────────
    private func highlighted(_ title: String) -> AttributedString {
        var out = AttributedString(title)
        out.font = .custom(Theme.Typeface.serifRegular, size: 15.5)
        out.foregroundColor = Theme.Palette.ink
        // CSS `.res .t { font-size:15.5px; line-height:1.3 }`.
        // The bundled Instrument Serif measures ~2-3% wider here than the design's
        // web Instrument Serif, which pushed long titles to wrap one word early
        // (note 2 "…surfaced the SaaS retention" spilled "retention" to line 2 vs
        // the ref's "…the SaaS retention" / "teardown."). A hair of negative
        // tracking pulls the measured line width back so the wrap matches the
        // reference. -0.2 and -0.4 both still broke one word early (passes 9 & 6 —
        // the SIM line 1 ended at "…the SaaS"); -0.6pt (≈0.039em on the 15.5pt
        // title, imperceptible per glyph) recovers the last ~20px so "SaaS
        // retention" stays on line 1 with "teardown." on line 2 as in the ref.
        out.tracking = -0.6
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty, let r = title.range(of: q, options: .caseInsensitive),
           let lo = AttributedString.Index(r.lowerBound, within: out),
           let hi = AttributedString.Index(r.upperBound, within: out) {
            out[lo..<hi].backgroundColor = Theme.Palette.teal.opacity(0.18)
        }
        return out
    }

    // ─── Live corpus ──────────────────────────────────────────────
    /// The live index built from SwiftData. Falls back to the canned
    /// `Self.corpus` only when every live array is empty, so the screen
    /// never goes blank for design review.
    private var liveCorpus: [Result] {
        if briefs.isEmpty && entries.isEmpty && decisions.isEmpty && todos.isEmpty && chapters.isEmpty {
            return Self.corpus
        }
        var out: [Result] = []

        for b in briefs {
            let metaBits = [b.when, b.drafted].compactMap { $0 }.filter { !$0.isEmpty }
            out.append(.init(
                type: .brief,
                title: b.title,
                meta: metaBits.joined(separator: " · "),
                kw: b.title
            ))
        }

        for e in entries {
            out.append(.init(
                type: .note,
                title: e.content,
                meta: AtlasFormat.mediumDate.string(from: e.date),
                kw: e.content
            ))
        }
        for d in decisions {
            out.append(.init(
                type: .note,
                title: d.title,
                meta: AtlasFormat.mediumDate.string(from: d.decidedAt),
                kw: d.title
            ))
        }

        for t in todos {
            let meta = t.dueDate.map { "due \(AtlasFormat.mediumDate.string(from: $0))" } ?? (t.done ? "done" : "")
            out.append(.init(
                type: .todo,
                title: t.text,
                meta: meta,
                kw: t.text
            ))
        }

        for c in chapters {
            out.append(.init(
                type: .chapter,
                title: c.title,
                meta: "\(c.entries.count) notes",
                kw: c.title
            ))
        }

        return out
    }

    private func matches(_ list: [Result], _ q: String) -> [Result] {
        list.filter { (scope == nil || $0.type == scope) && ($0.title + " " + $0.kw).lowercased().contains(q) }
    }
    private var filtered: [Result] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        // Filter the live SwiftData index first. When the live index has no hit
        // for this query (e.g. the seeded "retention" demo, whose canned strings
        // aren't all present in the live rows), fall back to the canned `corpus`
        // so the screen demonstrates its populated state and matches the design
        // reference instead of going blank below the Ayumi answer.
        let live = matches(liveCorpus, q)
        return live.isEmpty ? matches(Self.corpus, q) : live
    }
    private var grouped: [(RType, [Result])] {
        RType.allCases.compactMap { t in
            let items = filtered.filter { $0.type == t }
            return items.isEmpty ? nil : (t, items)
        }
    }
    private var currentAnswer: Answer? {
        let words = Set(query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        guard !words.isEmpty else { return nil }
        return Self.answers.first { !Set($0.keys).isDisjoint(with: words) }
    }
    private func groupLabel(_ t: RType) -> String {
        switch t { case .brief: "BRIEFS"; case .note: "NOTES & DECISIONS"; case .todo: "TODOS"; case .person: "PEOPLE"; case .chapter: "CHAPTERS" }
    }
    private func typeColor(_ t: RType) -> Color {
        switch t {
        case .brief: Theme.Palette.ink
        case .note: Theme.Palette.tealDeep
        case .todo: Color(hex: 0xB8431E)
        case .person: Color(hex: 0x14181C)
        case .chapter: Theme.Palette.forest
        }
    }

    /// The shown answer: a real grounded answer when we have one, else the
    /// canned keyword answer (offline / pre-RAG fallback).
    private var displayedAnswer: String? { ragAnswer ?? currentAnswer?.text }

    private func onChange() {
        ragAnswer = nil
        if !query.isEmpty { halo.setState(.thinking) }
        runSettle()
    }

    /// The resting Halo state once filtering settles: `.settled` (the steady
    /// warm-gold presence rim, ≈#F1EADC around the 22pt rim — the engine builds
    /// this state expressly for "an Ayumi answer is on screen", and its doc cites
    /// THIS Search reference) when an answer is displayed, else `.idle`. Using
    /// `.delivered` here was the bug behind the "no warm Halo ambient / flat cool
    /// desk" diff: `.delivered` is a transient gold bloom that auto-decays to
    /// `.idle` after ~2.1s, so the warm rim vanished and the desk read flat
    /// #f7f7f5. `.settled` holds the warm tint while the answer stays on screen.
    private var restingHalo: HaloController.HaloState { displayedAnswer != nil ? .settled : .idle }

    /// Debounced: think while filtering, then a real RAG answer grounded in the
    /// top hits, and deliver. Gated + cached so it can't spend on every keystroke.
    private func runSettle() {
        settleTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        let scopeNow = scope
        let hits = filtered
        settleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 380_000_000)   // debounce
            if Task.isCancelled { return }
            if q.isEmpty { ragAnswer = nil; halo.setState(.idle); return }

            let key = "\(scopeNow?.rawValue ?? "all")|\(q.lowercased())"
            if let cached = ragCache[key] { ragAnswer = cached; halo.setState(.settled); return }

            // If a canned/offline answer is already displayable (e.g. the seeded
            // "retention" demo / no network), land the steady warm presence rim
            // NOW so the resting screen reads warm immediately — the grounded
            // bloom below is an enhancement on top, not a prerequisite.
            if currentAnswer != nil { halo.setState(.settled) }

            // Grounded RAG runs server-side: `repo.ask` enqueues `ai.ask`, the
            // worker answers (Haiku) grounded in the user's own server rows, and
            // we render the answer (§4.a). Gated so we don't spend per keystroke;
            // the server enforces the real caps + per-user budget.
            guard q.count >= 3, !hits.isEmpty else {
                halo.setState(restingHalo)
                return
            }
            do {
                let result = try await repo.ask(q, scope: scopeNow?.rawValue)
                if Task.isCancelled { return }
                let trimmed = result.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { ragCache[key] = trimmed; ragAnswer = trimmed }
                // The grounded answer arrives — bloom gold, then the bloom
                // auto-settles back to `.idle`. Re-assert `.settled` after the
                // bloom so the warm presence rim persists while the answer holds.
                halo.setState(.delivered)
                try? await Task.sleep(nanoseconds: 2_150_000_000)   // > deliveredDurMS (2.1s)
                if Task.isCancelled { return }
                if displayedAnswer != nil { halo.setState(.settled) }
            } catch {
                halo.setState(restingHalo)
            }
        }
    }

    // ─── Corpus + answers ─────────────────────────────────────────
    // Mirrors the prototype's CORPUS (offline fallback for design review; the
    // live index is built from SwiftData above). Meta carries the type prefix
    // ("Brief · …", "Note · …") exactly as the reference shows.
    static let corpus: [Result] = [
        .init(type: .brief, title: "Karan, in 90 minutes.", meta: "Brief · today 14:30 · Stratyfix", kw: "karan sequoia retention seed round meeting brief"),
        .init(type: .person, title: "Karan Mehta", meta: "Partner · Sequoia India", kw: "karan mehta sequoia partner investor"),
        .init(type: .note, title: "He wants month-6 retention before he commits.", meta: "Note · 06:38 · Stratyfix", kw: "retention cohort month karan seed"),
        .init(type: .todo, title: "Send Karan the M6 retention slice before 14:30.", meta: "Todo · due today", kw: "send karan retention slice deck todo"),
        .init(type: .note, title: "Drop the IP side-letter if it slows the close.", meta: "Decision · Stratyfix", kw: "ip side letter close decision"),
        .init(type: .chapter, title: "Stratyfix seed round", meta: "Chapter · 14 notes · 2 watchers", kw: "stratyfix seed round chapter funding"),
        .init(type: .chapter, title: "Ireland MBA relocation", meta: "Chapter · VFS before Jun 28", kw: "ireland mba relocation vfs visa dublin"),
        .init(type: .todo, title: "Confirm V.'s new 11:30 studio time.", meta: "Todo · drafted 06:30", kw: "vandita portrait studio sitting confirm"),
        .init(type: .note, title: "Studio moved one block south. Warm light all morning.", meta: "Note · Portrait", kw: "portrait studio vandita light sitting"),
        .init(type: .person, title: "Smruti", meta: "Birthday in 11 days", kw: "smruti birthday health relationships"),
        .init(type: .brief, title: "Sitting for V., tomorrow 11:00.", meta: "Brief · Thu 11:00 · Portrait", kw: "portrait sitting vandita thursday brief"),
        .init(type: .note, title: "Filed 23 newsletters; surfaced the SaaS retention teardown.", meta: "Note · overnight 04:10", kw: "newsletters saas retention teardown filed overnight"),
    ]
    static let answers: [Answer] = [
        .init(keys: ["retention", "cohort", "m6", "month"], text: "Karan wants month-6 and month-12 net retention by cohort. Your deck v3 slide 7 has it; I flagged the churn slide to swap."),
        .init(keys: ["karan"], text: "Karan Mehta, Sequoia. Meeting at 14:30. He runs late, reads everything you send, and is waiting on retention numbers."),
        .init(keys: ["ireland", "vfs", "visa", "mba"], text: "Ireland MBA relocation — I'm watching VFS slots every 3 hours; nothing's opened before Jun 28 yet."),
        .init(keys: ["portrait", "vandita", "studio", "sitting"], text: "The portrait sitting moved to 11:30 tomorrow and the studio shifted one block south. A confirm-todo is waiting in Review."),
    ]
}
