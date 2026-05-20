import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Chapter.updatedAt, order: .reverse) private var chapters: [Chapter]
    let openCapture: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                heroHeader
                briefAndCalendar
                topTodos
                activeChapters
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 100)
        }
        .background(Theme.Palette.paper.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    private var hero: (weekday: String, day: String, milestone: NextMilestone?) {
        let date = Date()
        let weekday = AtlasFormat.weekday.string(from: date)
        let day = AtlasFormat.monthDay.string(from: date)
        return (weekday, day, computeNextMilestone(from: chapters))
    }

    private var heroHeader: some View {
        let h = hero
        return HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                MetaLabel(text: h.weekday)
                Text(h.day)
                    .font(Theme.Font.titleLarge)
                    .foregroundStyle(Theme.Palette.ink)
            }
            Spacer()
            if let m = h.milestone {
                VStack(alignment: .trailing, spacing: 2) {
                    MetaLabel(text: "next milestone")
                    HStack(spacing: 6) {
                        Text(milestoneLabel(m.days))
                            .font(Theme.Font.serif(20))
                            .foregroundStyle(Theme.Palette.ink)
                        Text(m.title)
                            .font(Theme.Font.sans(13))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: 200, alignment: .trailing)
            }
        }
    }

    private func milestoneLabel(_ days: Int) -> String {
        if days == 0 { return "today" }
        if days > 0 { return "T-\(days)d" }
        return "+\(abs(days))d"
    }

    private var briefAndCalendar: some View {
        VStack(spacing: 16) {
            briefCard
            calendarCard
        }
    }

    private var briefCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                MetaLabel(text: "Morning brief")
                Spacer()
                MetaLabel(text: AtlasFormat.yyyyMMdd.string(from: Date()))
            }
            Text(briefText)
                .font(Theme.Font.serif(20))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(4)
            Text("Synthesis is placeholder for now — the model layer plugs in here. The shape is right: a few sentences pulled from across active chapters, surfaced where you start the day.")
                .font(Theme.Font.sans(14))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .lineSpacing(3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MetaLabel(text: "Today's calendar")
                Spacer()
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.inkFaint)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(fakeCalendarEvents, id: \.time) { ev in
                    HStack(alignment: .top, spacing: 12) {
                        Text(ev.time)
                            .font(Theme.Font.mono(12))
                            .foregroundStyle(Theme.Palette.inkFaint)
                            .frame(width: 48, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ev.title)
                                .font(Theme.Font.sans(14))
                                .foregroundStyle(Theme.Palette.ink)
                            Text(ev.subtitle)
                                .font(Theme.Font.sans(12))
                                .foregroundStyle(Theme.Palette.inkFaint)
                        }
                    }
                }
            }
            Hairline()
            MetaLabel(text: "placeholder · connect Calendar in Settings")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var briefText: String {
        let active = chapters.filter { $0.status == .active }
        let upcoming = chapters.filter { $0.status == .upcoming }
        if chapters.isEmpty {
            return "Quiet board. Create a chapter to give the day a shape."
        }
        var parts: [String] = []
        if !active.isEmpty {
            let titles = active.prefix(2).map(\.title).joined(separator: ", ")
            let suffix = active.count > 2 ? ", and \(active.count - 2) more" : ""
            parts.append("\(active.count) chapter\(active.count == 1 ? "" : "s") in motion — \(titles)\(suffix).")
        }
        if !upcoming.isEmpty {
            let titles = upcoming.prefix(2).map(\.title).joined(separator: ", ")
            parts.append("On the horizon: \(titles).")
        }
        parts.append("Hold the arc, not just the items.")
        return parts.joined(separator: " ")
    }

    private var topTodos: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Up next")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                NavigationLink(value: NavRoute.chapters) {
                    HStack(spacing: 4) {
                        Text("All chapters")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                }
            }
            let items = topActiveTodos(limit: 5)
            VStack(spacing: 0) {
                if items.isEmpty {
                    HStack {
                        Text("No active todos. Tap + to capture something.")
                            .font(Theme.Font.sans(14))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                        Spacer()
                    }
                    .padding(20)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, t in
                        TopTodoRow(todo: t)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        if idx < items.count - 1 {
                            Hairline()
                        }
                    }
                }
            }
            .card()
        }
    }

    private var activeChapters: some View {
        let visible = chapters.filter { $0.status == .active || $0.status == .upcoming }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active chapters")
                    .font(Theme.Font.heading)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                let activeCount = chapters.filter { $0.status == .active }.count
                let upcomingCount = chapters.filter { $0.status == .upcoming }.count
                Text("\(activeCount) active · \(upcomingCount) upcoming")
                    .font(Theme.Font.mono(11))
                    .foregroundStyle(Theme.Palette.inkFaint)
            }
            VStack(spacing: 10) {
                ForEach(visible) { c in
                    NavigationLink(value: c) {
                        ActiveChapterRow(chapter: c)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: Chapter.self) { c in
            ChapterDetailView(chapter: c)
        }
        .navigationDestination(for: NavRoute.self) { route in
            switch route {
            case .chapters:
                ChaptersListView()
            }
        }
    }

    private func topActiveTodos(limit: Int) -> [Todo] {
        let candidates = chapters
            .filter { $0.status == .active || $0.status == .upcoming }
            .flatMap { $0.todos }
            .filter { !$0.done }
        let sorted = candidates.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return false
            }
        }
        return Array(sorted.prefix(limit))
    }
}

enum NavRoute: Hashable {
    case chapters
}

struct NextMilestone {
    let title: String
    let days: Int
}

func computeNextMilestone(from chapters: [Chapter]) -> NextMilestone? {
    var candidates: [NextMilestone] = []
    for c in chapters {
        if c.status == .done { continue }
        if let start = c.startDate {
            let d = AtlasFormat.daysUntil(start)
            if d >= -7 {
                candidates.append(NextMilestone(title: "\(c.title) begins", days: d))
            }
        }
        if let end = c.endDate {
            let d = AtlasFormat.daysUntil(end)
            if d >= 0 && d <= 365 {
                candidates.append(NextMilestone(title: "\(c.title) ends", days: d))
            }
        }
    }
    return candidates.sorted { abs($0.days) < abs($1.days) }.first
}

struct FakeCalEvent {
    let time: String
    let title: String
    let subtitle: String
}

let fakeCalendarEvents: [FakeCalEvent] = [
    .init(time: "09:00", title: "Deep work block", subtitle: "Deck v3, slides 1–6"),
    .init(time: "11:30", title: "Lightspeed — partner intro", subtitle: "30 min · video"),
    .init(time: "15:00", title: "Tennis", subtitle: "Bombay Gymkhana"),
    .init(time: "19:30", title: "Dinner — A.", subtitle: "Soam, Babulnath")
]

struct TopTodoRow: View {
    let todo: Todo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Theme.Palette.borderWarmStrong, lineWidth: 1)
                .frame(width: 14, height: 14)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(todo.text)
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 10) {
                    if let chapter = todo.chapter {
                        HStack(spacing: 5) {
                            Image(systemName: chapter.type.sfSymbol)
                                .font(.system(size: 10))
                            Text(chapter.title)
                                .font(Theme.Font.mono(11))
                        }
                        .foregroundStyle(Theme.Palette.inkFaint)
                    }
                    if let due = todo.dueDate {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(AtlasFormat.mediumDate.string(from: due))
                                .font(Theme.Font.mono(11))
                        }
                        .foregroundStyle(Color.dueColor(for: due))
                    }
                }
            }
            Spacer()
        }
    }
}

struct ActiveChapterRow: View {
    let chapter: Chapter

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: chapter.type.sfSymbol)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.inkSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                Text("\(chapter.status.rawValue) · updated \(AtlasFormat.relative(chapter.updatedAt))")
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Palette.inkFaint)
            }
            Spacer()
            Text("\(chapter.doneTodos.count)/\(chapter.todos.count)")
                .font(Theme.Font.mono(11))
                .foregroundStyle(Theme.Palette.inkFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .card()
    }
}
