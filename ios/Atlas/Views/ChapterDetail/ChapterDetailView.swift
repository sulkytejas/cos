import SwiftUI
import SwiftData

struct ChapterDetailView: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context
    @State private var tab: DetailTab = .todos

    enum DetailTab: String, CaseIterable, Hashable {
        case todos = "Todos"
        case decisions = "Decisions"
        case journal = "Journal"
        case links = "Links"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                metaRow
                ChapterHeaderView(chapter: chapter)
                tabBar
                tabContent
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .background(Theme.Palette.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            Image(systemName: chapter.type.sfSymbol)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.inkSecondary)
            MetaLabel(text: "\(chapter.type.label) · \(chapter.status.rawValue) · \(AtlasFormat.range(chapter.startDate, chapter.endDate))")
        }
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(DetailTab.allCases, id: \.self) { t in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { tab = t }
                    } label: {
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Text(t.rawValue)
                                    .font(Theme.Font.sans(14))
                                    .foregroundStyle(tab == t ? Theme.Palette.ink : Theme.Palette.inkFaint)
                                Text("\(count(for: t))")
                                    .font(Theme.Font.mono(10))
                                    .foregroundStyle(Theme.Palette.inkFaint)
                            }
                            Rectangle()
                                .fill(tab == t ? Theme.Palette.ink : Color.clear)
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            Hairline()
        }
    }

    private func count(for t: DetailTab) -> Int {
        switch t {
        case .todos: return chapter.todos.count
        case .decisions: return chapter.decisions.count
        case .journal: return chapter.entries.count
        case .links: return chapter.outgoingLinks.count + chapter.incomingLinks.count
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .todos: TodosTab(chapter: chapter)
        case .decisions: DecisionsTab(chapter: chapter)
        case .journal: JournalTab(chapter: chapter)
        case .links: LinksTab(chapter: chapter)
        }
    }
}
