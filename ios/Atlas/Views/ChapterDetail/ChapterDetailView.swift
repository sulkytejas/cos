import SwiftUI
import SwiftData

struct ChapterDetailView: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var tab: DetailTab = .todos

    enum DetailTab: String, Hashable, CaseIterable {
        case todos, decisions, journal, links
        var label: String {
            switch self {
            case .todos: return "Todos"
            case .decisions: return "Decisions"
            case .journal: return "Journal"
            case .links: return "Links"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backRow
                masthead
                tabBar
                tabContent
                Spacer().frame(height: 110)
            }
            .padding(.top, 6)
        }
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
    }

    // ─── Back ──────────────────────────────────────────────────────
    private var backRow: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Chapters")
                        .font(Theme.Font.sans(13, weight: .medium))
                }
                .foregroundStyle(Theme.Palette.inkFaint)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 4)
    }

    // ─── Masthead ──────────────────────────────────────────────────
    private var masthead: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ChapterGlyphView(letter: chapter.glyph, iconData: chapter.iconData, accent: chapter.accent, size: 28)
                MicroText(text: chapter.type.label)
                Spacer()
                StatePill(status: chapter.status)
            }
            Text(chapter.title)
                .font(Theme.Font.serifItalic(36))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(2)
            if let p = chapter.purpose {
                Text(p)
                    .font(Theme.Font.sans(14.5))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: 320, alignment: .leading)
            }
            if chapter.startDate != nil || chapter.endDate != nil {
                Text(AtlasFormat.range(chapter.startDate, chapter.endDate))
                    .font(Theme.Font.mono(10.5))
                    .foregroundStyle(Theme.Palette.inkFainter)
                    .tracking(0.6)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    // ─── Tabs ──────────────────────────────────────────────────────
    private var tabBar: some View {
        VStack(spacing: 0) {
            MagneticTabs(
                tabs: DetailTab.allCases.map { .init(id: $0, label: $0.label) },
                active: $tab
            )
            Hairline()
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
    }

    @ViewBuilder
    private var tabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch tab {
            case .todos:     TodosTab(chapter: chapter)
            case .decisions: DecisionsTab(chapter: chapter)
            case .journal:   JournalTab(chapter: chapter)
            case .links:     LinksTab(chapter: chapter)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }
}
