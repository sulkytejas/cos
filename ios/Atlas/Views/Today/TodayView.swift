import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Chapter.updatedAt, order: .reverse) private var chapters: [Chapter]
    @Query(filter: #Predicate<Brief> { $0.statusRaw == "surfaced" },
           sort: \Brief.surfaceAt) private var briefs: [Brief]
    @Query(filter: #Predicate<Watcher> { $0.statusRaw == "active" },
           sort: \Watcher.createdAt, order: .reverse) private var watchers: [Watcher]
    @Query private var allProposals: [Proposal]
    @Query private var allSignals: [Signal]
    @State private var briefDone = false
    @Binding var pullProgress: CGFloat
    let onPullCapture: () -> Void

    private static let calendarEvents: [HourEvent] = [
        .init(time: "09:00", title: "Deep work block",          meta: "Deck v3, slides 1–6", glyph: "D", durationMin: 120),
        .init(time: "11:30", title: "Lightspeed — partner intro", meta: "30 min · video",     glyph: "L", durationMin: 30),
        .init(time: "15:00", title: "Tennis",                   meta: "Bombay Gymkhana",     glyph: "T", durationMin: 75),
        .init(time: "19:30", title: "Dinner — A.",              meta: "Soam, Babulnath",     glyph: "A", durationMin: 90),
    ]

    private static let pullThreshold: CGFloat = 80
    private let scrollSpace = "today.scroll"

    var body: some View {
        ScrollView {
            ScrollOffsetReader(coordinateSpace: scrollSpace)
            VStack(alignment: .leading, spacing: 0) {
                dateHeader
                nextMilestoneStrip

                Spacer().frame(height: 26)
                TempoNow(events: Self.calendarEvents,
                         todoHours: todoHoursToday())

                handledOvernightStrip
                briefsForTodaySection
                atlasWatchingSection

                morningBrief
                upNextSection
                chaptersSection

                Spacer().frame(height: 90)
            }
            .padding(.top, 16)
        }
        .coordinateSpace(name: scrollSpace)
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
        .navigationDestination(for: Chapter.self) { ChapterDetailView(chapter: $0) }
        .navigationDestination(for: Brief.self) { BriefDetailView(brief: $0) }
        .onPreferenceChange(ScrollOffsetKey.self) { y in
            // Overscroll downward → positive y. Convert to 0..1.x progress.
            let progress = max(0, y) / Self.pullThreshold
            // Fire on release-style: when user lets go and progress was ≥1, open capture.
            // Use a simple state machine — if progress drops to ~0 quickly and we were armed, fire.
            handlePullChange(progress: progress)
        }
    }

    // ─── Pull-to-capture tracking ─────────────────────────────────
    @State private var wasArmed = false
    private func handlePullChange(progress: CGFloat) {
        pullProgress = progress
        if progress >= 1 { wasArmed = true }
        if wasArmed && progress < 0.05 {
            wasArmed = false
            onPullCapture()
        }
    }

    // ─── Date header ──────────────────────────────────────────────
    private var dateHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                MicroText(text: weekday)
                Text(monthDay)
                    .font(Theme.Font.serifItalic(72))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .breathing()
            }
            Spacer()
            CompassDial(size: 56)
                .padding(.top, 8)
        }
        .padding(.horizontal, 22)
    }

    private var nextMilestoneStrip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.Palette.teal)
                .frame(width: 6, height: 6)
            MicroText(text: "Next")
            if let m = nextMilestone {
                MorphText(value: milestoneLabel(m.days))
                Text(m.chapterTitle)
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineLimit(1)
                Rectangle()
                    .fill(Theme.Palette.hairline.opacity(0.5))
                    .frame(height: 1)
                if let date = m.date {
                    Text(AtlasFormat.yyyyMMdd.string(from: date).replacingOccurrences(of: "-", with: "·"))
                        .font(Theme.Font.mono(9.5))
                        .foregroundStyle(Theme.Palette.inkFainter)
                        .tracking(0.6)
                }
            } else {
                Text("nothing on the horizon")
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Theme.Palette.inkFaint)
                Spacer()
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    // ─── Morning brief ────────────────────────────────────────────
    private var morningBrief: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                MicroText(text: "Morning Brief")
                Spacer()
                Text(AtlasFormat.yyyyMMdd.string(from: Date()).replacingOccurrences(of: "-", with: "·"))
                    .font(Theme.Font.mono(9.5))
                    .foregroundStyle(Theme.Palette.inkFainter)
            }
            Typewriter(
                text: briefText,
                italic: italicTokens,
                onDone: {
                    withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                        briefDone = true
                    }
                }
            )

            if briefDone {
                VStack(alignment: .leading, spacing: 0) {
                    Hairline().opacity(0.5)
                    HStack(alignment: .top, spacing: 8) {
                        Text("NOTICED")
                            .font(Theme.Font.mono(9))
                            .tracking(1.8)
                            .foregroundStyle(Theme.Palette.inkFaint)
                            .padding(.top, 3)
                        Text("You've slept under 6h for three nights running. Block tomorrow's morning?")
                            .font(Theme.Font.sans(13))
                            .foregroundStyle(Theme.Palette.inkFaint)
                            .lineSpacing(3)
                    }
                    .padding(.top, 12)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 4)),
                    removal: .opacity
                ))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, 22)
        .padding(.top, 24)
    }

    // ─── Up next (todos) ──────────────────────────────────────────
    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            RibbonHeader(title: "Up next", meta: "\(pendingCount) pending")
                .padding(.horizontal, 22)
            VStack(spacing: 0) {
                let visible = Array(allTodos.prefix(5))
                ForEach(Array(visible.enumerated()), id: \.element.id) { idx, t in
                    TodoRowToday(todo: t, onCheck: { toggle(t) })
                        .staggerReveal(index: idx)
                    if idx < visible.count - 1 {
                        Hairline().opacity(0.5)
                    }
                }
            }
            .padding(.horizontal, 22)
        }
    }

    // ─── Chapters in motion ───────────────────────────────────────
    private var chaptersSection: some View {
        let active = chapters.filter { $0.status == .active }
        let upcoming = chapters.filter { $0.status == .upcoming }
        let combined = active + upcoming

        return VStack(alignment: .leading, spacing: 0) {
            RibbonHeader(
                title: "Chapters in motion",
                meta: "\(active.count) active · \(upcoming.count) upcoming"
            )
            .padding(.horizontal, 22)
            VStack(spacing: 10) {
                ForEach(Array(combined.enumerated()), id: \.element.id) { idx, ch in
                    NavigationLink(value: ch) {
                        ChapterCardCompact(chapter: ch)
                    }
                    .buttonStyle(.pressScale)
                    .staggerReveal(index: idx, step: 0.09)
                }
            }
            .padding(.horizontal, 22)
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────
    private var weekday: String { AtlasFormat.weekday.string(from: Date()) }
    private var monthDay: String { AtlasFormat.monthDay.string(from: Date()) }

    /// All todos in creation order. Done todos stay visible so toggling them
    /// dims-in-place rather than removing them from the list (matches prototype).
    private var allTodos: [Todo] {
        chapters.flatMap { $0.todos }
            .sorted { $0.createdAt < $1.createdAt }
    }
    private var pendingCount: Int {
        allTodos.filter { !$0.done }.count
    }

    private func todoHoursToday() -> [Double] {
        allTodos.filter { !$0.done }.compactMap { $0.dueHourDouble }
    }

    private struct Milestone {
        let chapterTitle: String
        let days: Int
        let date: Date?
    }

    private var nextMilestone: Milestone? {
        var candidates: [Milestone] = []
        for c in chapters where c.status != .done {
            if let s = c.startDate {
                let d = AtlasFormat.daysUntil(s)
                if d >= 0 { candidates.append(.init(chapterTitle: c.title, days: d, date: s)) }
            }
        }
        return candidates.sorted { $0.days < $1.days }.first
    }

    private func milestoneLabel(_ days: Int) -> String {
        if days == 0 { return "today" }
        return "T−\(days)d"
    }

    private var briefText: String {
        let active = chapters.filter { $0.status == .active }
        let upcoming = chapters.filter { $0.status == .upcoming }
        if chapters.isEmpty {
            return "Quiet board. Create a chapter to give the day a shape."
        }
        var s = "\(active.count) chapter\(active.count == 1 ? "" : "s") in motion"
        let names = active.prefix(3).map(\.title).joined(separator: ", ")
        if !names.isEmpty { s += " — \(names)" }
        s += "."
        if !upcoming.isEmpty {
            s += " On the horizon: \(upcoming.prefix(2).map(\.title).joined(separator: ", "))."
        }
        s += " Hold the arc, not just the items."
        return s
    }

    private var italicTokens: [String] {
        chapters.prefix(4).map { firstWord($0.title) }.filter { !$0.isEmpty }
    }

    private func firstWord(_ s: String) -> String {
        s.split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? ""
    }

    private func toggle(_ t: Todo) {
        t.done.toggle()
        t.doneAt = t.done ? Date() : nil
        t.chapter?.touch()
        try? context.save()
    }

    // ─── v0.2 — Handled while you slept ───────────────────────────
    private var handledOvernightStrip: some View {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let signalCounts = allSignals
            .filter { $0.arrivedAt >= startOfDay }
            .reduce(into: [SignalSource: Int]()) { $0[$1.source, default: 0] += 1 }
        let filedToday = allProposals
            .filter { $0.status == .approved && ($0.decidedAt ?? .distantPast) >= startOfDay }
            .reduce(into: [ProposalType: Int]()) { $0[$1.type, default: 0] += 1 }

        var parts: [String] = []
        if let n = signalCounts[.gmail], n > 5 { parts.append("filed \(n) newsletters") }
        if let n = filedToday[.todo]            { parts.append("drafted \(n) todos") }
        if let n = filedToday[.decision]        { parts.append("noted \(n) decision") }
        if let n = filedToday[.journalEntry]    { parts.append("saved \(n) journal \(n == 1 ? "entry" : "entries")") }
        let totalSignals = signalCounts.values.reduce(0, +)
        let sentence: String
        if parts.isEmpty {
            sentence = totalSignals == 0
                ? "Nothing came in overnight."
                : "Handled \(totalSignals) small signals overnight; nothing flagged for review."
        } else {
            sentence = parts.joined(separator: " · ")
        }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("HANDLED WHILE YOU SLEPT")
                    .font(Theme.Font.mono(9))
                    .tracking(1.8)
                    .foregroundStyle(Theme.Palette.inkFaint)
                Text("· overnight")
                    .font(Theme.Font.mono(9))
                    .foregroundStyle(Theme.Palette.inkFainter)
            }
            Text(sentence + ".")
                .font(Theme.Font.mono(11.5))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .lineSpacing(2)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
    }

    // ─── v0.2 — Briefs for today ──────────────────────────────────
    private var briefsForTodaySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Briefs for today")
                    .font(Theme.Font.serif(22))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("\(briefs.count) READY")
                    .font(Theme.Font.mono(9.5))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Palette.inkFaint)
            }
            .padding(.bottom, 12)

            if briefs.isEmpty {
                Text("Nothing surfaced yet. Atlas will draft briefs as situations form.")
                    .font(Theme.Font.serifItalic(15))
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(briefs) { b in
                        NavigationLink(value: b) {
                            BriefTeaserCard(brief: b)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
    }

    // ─── v0.2 — Atlas is watching ────────────────────────────────
    private var atlasWatchingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Atlas is watching")
                    .font(Theme.Font.serif(22))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text("\(watchers.count) ACTIVE")
                    .font(Theme.Font.mono(9.5))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Palette.inkFaint)
            }
            .padding(.bottom, 4)

            if watchers.isEmpty {
                Text("Nothing on watch. Atlas adds watchers when it spots something worth checking back on.")
                    .font(Theme.Font.serifItalic(14))
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .padding(.vertical, 10)
            } else {
                ForEach(watchers.prefix(5)) { w in
                    WatcherRow(watcher: w)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
    }
}

// ─── v0.2 — Brief teaser card (Today + similar surfaces) ─────────────
struct BriefTeaserCard: View {
    let brief: Brief
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(brief.title)
                    .font(Theme.Font.serifItalic(19))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(2)
                Spacer()
                Circle()
                    .fill(Theme.Palette.teal)
                    .frame(width: 6, height: 6)
                    .opacity(0.0)  // reserve space — pulse-dot will replace later
            }
            if let preview = brief.preview {
                Text(preview)
                    .font(Theme.Font.sans(13.5))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(3)
            }
            HStack(spacing: 8) {
                if let chapter = brief.chapterTitle {
                    Text(chapter.uppercased())
                        .font(Theme.Font.mono(9.5))
                        .tracking(1.6)
                        .foregroundStyle(Theme.Palette.inkFaint)
                }
                if brief.chapterTitle != nil && brief.when != nil {
                    Text("·")
                        .foregroundStyle(Theme.Palette.inkFainter)
                }
                if let when = brief.when {
                    Text(when)
                        .font(Theme.Font.mono(9.5))
                        .foregroundStyle(Theme.Palette.inkFainter)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.card)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// ─── v0.2 — Watcher line ─────────────────────────────────────────────
struct WatcherRow: View {
    let watcher: Watcher
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            WatcherIcon(size: 12)
                .offset(y: 2)
            Text(watcher.watcherDescription)
                .font(Theme.Font.serifItalic(15))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(3)
            Spacer(minLength: 4)
            if let cadence = watcher.cadenceLabel {
                Text(cadence.uppercased())
                    .font(Theme.Font.mono(9.5))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Palette.inkFainter)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.hairline.opacity(0.5))
                .frame(height: 1)
        }
    }
}

// ─── Today todo row ─────────────────────────────────────────────────
struct TodoRowToday: View {
    @Bindable var todo: Todo
    let onCheck: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            InkCheckbox(
                checked: todo.done,
                accent: todo.isOverdue ? .teal : (todo.chapter?.accent ?? .forest),
                onToggle: onCheck
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(todo.text)
                    .font(.system(size: 15,
                                  weight: todo.done ? .light : .regular,
                                  design: .default))
                    .foregroundStyle(Theme.Palette.ink)
                    .strikethrough(todo.done, color: Theme.Palette.inkFaint)
                HStack(spacing: 10) {
                    if let ch = todo.chapter {
                        ChapterChip(title: ch.title, accent: ch.accent)
                    }
                    if let due = todo.dueDate {
                        Text("· \(AtlasFormat.mediumDate.string(from: due))")
                            .font(Theme.Font.mono(10.5))
                            .foregroundStyle(todo.isOverdue ? Theme.Palette.teal : Theme.Palette.inkFaint)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(todo.done ? 0.5 : 1)
        .animation(.easeOut(duration: 0.28), value: todo.done)
        .contentShape(Rectangle())
        .onTapGesture(perform: onCheck)
        .padding(.vertical, 12)
    }
}

// ─── Compact chapter card ────────────────────────────────────────────
struct ChapterCardCompact: View {
    let chapter: Chapter
    var body: some View {
        HStack(spacing: 12) {
            ChapterGlyphView(letter: chapter.glyph, iconData: chapter.iconData, accent: chapter.accent, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.title)
                    .font(Theme.Font.serif(17))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(chapter.status.prototypeLabel)
                        .font(Theme.Font.mono(9.5))
                        .tracking(1.5)
                        .foregroundStyle(Theme.Palette.inkFaint)
                    Text("·")
                        .foregroundStyle(Theme.Palette.inkFainter)
                    Text("\(chapter.doneTodos.count)/\(chapter.todos.count)")
                        .font(Theme.Font.mono(9.5))
                        .foregroundStyle(Theme.Palette.inkFainter)
                }
            }
            Spacer()
            HairlineProgress(done: chapter.doneTodos.count,
                             total: chapter.todos.count,
                             accent: chapter.accent)
                .frame(width: 72)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .frame(maxWidth: .infinity)
        .card()
    }
}
