import SwiftUI
import SwiftData

/// Search — one index over everything. A search field, scope chips, grouped
/// results with the query highlighted, and an Ayumi plain-words answer card.
struct SearchScreen: View {
    @Environment(HaloController.self) private var halo
    @Environment(\.modelContext) private var context
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
            searchField.padding(.horizontal, 24).padding(.top, 70).padding(.bottom, 12)
            scopeRow.padding(.horizontal, 24).padding(.bottom, 6)
            results
        }
        .onAppear {
            // DEV: seed a query via `simctl launch … --query Ireland` for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--query"), i + 1 < args.count { query = args[i + 1] }
            runSettle()
        }
        .onChange(of: query) { _, _ in onChange() }
        .onChange(of: scope) { _, _ in onChange() }
    }

    // ─── Search field ─────────────────────────────────────────────
    private var live: Bool { !query.isEmpty }
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .regular)).foregroundStyle(Theme.Palette.inkFaint)
            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text("Search everything…").font(Theme.Font.serifItalic(18)).foregroundStyle(Theme.Palette.inkFaint)
                }
                TextField("", text: $query)
                    .font(Theme.Font.serifItalic(18)).foregroundStyle(Theme.Palette.ink)
                    .focused($focused).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if live {
                Button { query = ""; focused = true } label: {
                    Text("CLEAR").font(Theme.Font.mono(9)).tracking(1.0).foregroundStyle(Theme.Palette.inkFaint)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Palette.paperDeep)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(live ? Theme.Palette.teal.opacity(0.4) : Theme.Palette.rule, lineWidth: 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.Palette.teal.opacity(live ? 0.08 : 0), lineWidth: 3)
        )
        .animation(.easeInOut(duration: 0.22), value: live)
    }

    private var scopeRow: some View {
        HStack(spacing: 6) {
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
                    JadeCard(radius: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("AYUMI").font(Theme.Font.mono(9)).tracking(1.6).foregroundStyle(Theme.Palette.jadeCardInk.opacity(0.7))
                            Text(answerText).font(Theme.Font.serifItalic(16)).foregroundStyle(Theme.Palette.jadeCardInk)
                                .lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.bottom, 18)
                }
                let groups = grouped
                if query.isEmpty {
                    emptyState("Ask anything.", "Briefs, notes, people, chapters, todos — all in one place.")
                } else if groups.isEmpty && displayedAnswer == nil {
                    emptyState("Nothing yet.", "Try \"retention\", \"Karan\", or \"Ireland\".")
                } else {
                    ForEach(groups, id: \.0) { type, items in
                        Text("\(groupLabel(type)) · \(items.count)")
                            .font(Theme.Font.mono(9)).tracking(1.8).foregroundStyle(Theme.Palette.ink3)
                            .padding(.bottom, 8).padding(.top, 14)
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            row(item, last: idx == items.count - 1)
                        }
                    }
                }
                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 24).padding(.top, 8)
        }
    }

    private func row(_ item: Result, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 5).fill(typeColor(item.type)).frame(width: 20, height: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(highlighted(item.title))
                Text(item.meta).font(Theme.Font.mono(9)).tracking(0.4).foregroundStyle(Theme.Palette.inkFaint)
            }
            Spacer(minLength: 0)
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

    private var filtered: [Result] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return liveCorpus.filter { (scope == nil || $0.type == scope) && ($0.title + " " + $0.kw).lowercased().contains(q) }
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
            if let cached = ragCache[key] { ragAnswer = cached; halo.setState(.delivered); return }

            // Only spend a call when it can actually help.
            guard q.count >= 3, !hits.isEmpty, AtlasLLM.isConfigured else {
                halo.setState(currentAnswer != nil ? .delivered : .idle)
                return
            }
            let context = hits.prefix(8)
                .map { "- [\($0.type.rawValue)] \($0.title)\($0.meta.isEmpty ? "" : " — \($0.meta)")" }
                .joined(separator: "\n")
            let system = "You are Ayumi, a calm chief-of-staff. Answer the user's query in 1–2 short sentences, first person, grounded ONLY in the provided context. If the context doesn't contain the answer, say what you do see instead. Never invent facts."
            let user = "Query: \(q)\n\nContext from the user's own data:\n\(context)"
            do {
                let text = try await AtlasLLM.complete(system: system, user: user, maxTokens: 200)
                if Task.isCancelled { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { ragCache[key] = trimmed; ragAnswer = trimmed }
                halo.setState(.delivered)
            } catch {
                halo.setState(currentAnswer != nil ? .delivered : .idle)
            }
        }
    }

    // ─── Corpus + answers ─────────────────────────────────────────
    static let corpus: [Result] = [
        .init(type: .brief, title: "Karan Mehta — pre-meeting brief", meta: "today · 14:30 · 6 sources", kw: "karan retention sequoia"),
        .init(type: .brief, title: "Ireland relocation — visa window", meta: "drafted · 3 sources", kw: "ireland vfs visa mba"),
        .init(type: .note, title: "M6 cohort held after the pricing change", meta: "Stratyfix · pinned", kw: "m6 cohort retention pricing"),
        .init(type: .note, title: "Decision: lead with retention, not the round", meta: "Stratyfix · logged", kw: "retention decision round"),
        .init(type: .todo, title: "Send Karan the M6 retention dashboard", meta: "due today · Stratyfix", kw: "retention m6 dashboard karan"),
        .init(type: .todo, title: "Book a VFS slot before Jun 28", meta: "Ireland · urgent", kw: "vfs ireland visa slot"),
        .init(type: .person, title: "Karan Mehta", meta: "Partner · Sequoia India", kw: "karan sequoia partner"),
        .init(type: .person, title: "Vandita (V.)", meta: "Portrait · photographer", kw: "vandita portrait studio"),
        .init(type: .chapter, title: "Stratyfix", meta: "14 notes · 2 watchers", kw: "stratyfix seed retention"),
        .init(type: .chapter, title: "Ireland MBA", meta: "9 notes · VFS Jun 28", kw: "ireland mba vfs visa"),
        .init(type: .note, title: "Studio for the portrait sitting moved south", meta: "Portrait · 1d ago", kw: "portrait studio vandita sitting"),
        .init(type: .todo, title: "Confirm the new studio address with V.", meta: "Portrait · Thu", kw: "portrait studio vandita"),
    ]
    static let answers: [Answer] = [
        .init(keys: ["retention", "cohort", "m6", "month"], text: "The M6 cohort held at 0.94 after the pricing change — that's your headline for Karan. Three notes and the dashboard back it."),
        .init(keys: ["karan"], text: "Karan reads retention, not the round. Open with the curve; the follow-on will come to you."),
        .init(keys: ["ireland", "vfs", "visa", "mba"], text: "The VFS window closes Jun 28. I'm watching every 3 hours; nothing's open yet — book the slot this week."),
        .init(keys: ["portrait", "vandita", "studio", "sitting"], text: "The sitting with V. is tomorrow at 11:00; the studio moved one block south."),
    ]
}
