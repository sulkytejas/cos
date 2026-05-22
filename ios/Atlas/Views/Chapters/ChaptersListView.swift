import SwiftUI
import SwiftData

struct ChaptersListView: View {
    @Query(sort: \Chapter.updatedAt, order: .reverse) private var chapters: [Chapter]
    @Query private var links: [ChapterLink]
    @Query private var todos: [Todo]

    @State private var viewMode: ViewMode = .map
    @State private var focusedID: UUID? = nil
    @State private var pendingChapter: Chapter? = nil
    @State private var showNew = false

    enum ViewMode: String, Identifiable {
        case map, list
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if viewMode == .map {
                    mapBody
                } else {
                    listBody
                }

                Spacer().frame(height: 110)
            }
            .padding(.top, 18)
        }
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
        .navigationDestination(for: Chapter.self) { ch in
            ChapterDetailView(chapter: ch)
        }
        .sheet(isPresented: $showNew) { NewChapterSheet() }
    }

    // ─── Header ────────────────────────────────────────────────────
    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                MicroText(text: "All arcs")
                Text("Chapters")
                    .font(Theme.Font.serif(46))
                    .foregroundStyle(Theme.Palette.ink)
            }
            Spacer()
            AtlasViewToggle(
                options: [
                    .init(id: ViewMode.map, label: "Map"),
                    .init(id: ViewMode.list, label: "List"),
                ],
                selection: $viewMode
            )
        }
        .padding(.horizontal, 22)
    }

    // ─── Map view ──────────────────────────────────────────────────
    private var mapBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 22)
            ConstellationView(
                chapters: chapters,
                edges: links,
                todos: todos,
                focusedID: $focusedID,
                onOpen: { ch in pendingChapter = ch }
            )
            // Below the constellation: swaps between BLOCKS/ENABLES/CONFLICTS
            // legend (when nothing is focused) and the "tap × to return" hint
            // (when a chapter is focused).
            ZStack {
                if focusedID == nil {
                    legend
                        .transition(.opacity)
                } else {
                    Text("Tap the × to return to the constellation")
                        .font(Theme.Font.serifItalic(13))
                        .foregroundStyle(Theme.Palette.inkFaint)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .animation(.easeOut(duration: 0.28), value: focusedID)
        }
        .navigationDestination(item: $pendingChapter) { ch in
            ChapterDetailView(chapter: ch)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            LegendDot(label: "blocks", color: Theme.Palette.teal)
            LegendDot(label: "enables", color: Theme.Palette.forest)
            LegendDot(label: "conflicts", color: Theme.Palette.teal, dashed: true)
        }
    }

    private struct LegendDot: View {
        let label: String
        let color: Color
        var dashed: Bool = false
        var body: some View {
            HStack(spacing: 6) {
                Rectangle()
                    .strokeBorder(color,
                                  style: StrokeStyle(lineWidth: 1.2, dash: dashed ? [3, 3] : []))
                    .frame(width: 20, height: 1.2)
                Text(label.uppercased())
                    .font(Theme.Font.mono(9))
                    .tracking(1.5)
                    .foregroundStyle(Theme.Palette.inkFaint)
            }
        }
    }

    // ─── List view ─────────────────────────────────────────────────
    private var listBody: some View {
        let groups: [(label: String, items: [Chapter])] = [
            ("Active",   chapters.filter { $0.status == .active }),
            ("Upcoming", chapters.filter { $0.status == .upcoming }),
            ("Paused",   chapters.filter { $0.status == .paused }),
            ("Complete", chapters.filter { $0.status == .done }),
        ].filter { !$0.items.isEmpty }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.label) { group in
                RibbonHeader(title: group.label, meta: "\(group.items.count)")
                    .padding(.horizontal, 22)
                VStack(spacing: 12) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, ch in
                        NavigationLink(value: ch) {
                            ChapterCardFull(chapter: ch)
                        }
                        .buttonStyle(.pressScale)
                        .staggerReveal(index: idx, step: 0.09)
                    }
                }
                .padding(.horizontal, 22)
            }
        }
    }
}

struct ChapterCardFull: View {
    let chapter: Chapter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ChapterGlyphView(letter: chapter.glyph, iconData: chapter.iconData, accent: chapter.accent, size: 26)
                MicroText(text: chapter.type.label)
                Spacer()
                Text(chapter.rangeShort)
                    .font(Theme.Font.mono(10))
                    .foregroundStyle(Theme.Palette.inkFainter)
            }
            Text(chapter.title)
                .font(Theme.Font.serif(24))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.top, 10)
                .lineLimit(2)
            if let p = chapter.purpose {
                Text(p)
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(3)
                    .padding(.top, 6)
                    .lineLimit(3)
            }
            HStack(spacing: 10) {
                Text("\(chapter.doneTodos.count) / \(chapter.todos.count) todos")
                    .font(Theme.Font.mono(10.5))
                    .foregroundStyle(Theme.Palette.inkFaint)
                HairlineProgress(done: chapter.doneTodos.count,
                                 total: chapter.todos.count,
                                 accent: chapter.accent)
                Text("\(Int(chapter.progress * 100))%")
                    .font(Theme.Font.mono(10.5))
                    .foregroundStyle(chapter.accent.stroke)
            }
            .padding(.top, 14)

            Hairline().opacity(0.5).padding(.top, 12)
            HStack {
                StatePill(status: chapter.status)
                Spacer()
                Text("UPDATED \(AtlasFormat.relative(chapter.updatedAt))".uppercased())
                    .font(Theme.Font.mono(9.5))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Palette.inkFainter)
            }
            .padding(.top, 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
