import SwiftUI
import SwiftData

struct ChaptersListView: View {
    @Query(sort: \Chapter.updatedAt, order: .reverse) private var chapters: [Chapter]
    @State private var showNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                ForEach(ChapterStatus.allCases.sorted { $0.sortIndex < $1.sortIndex }, id: \.self) { status in
                    let inGroup = chapters.filter { $0.status == status }
                    if !inGroup.isEmpty {
                        section(title: status.label, count: inGroup.count, chapters: inGroup)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 100)
        }
        .background(Theme.Palette.paper.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showNew) {
            NewChapterSheet()
        }
        .navigationDestination(for: Chapter.self) { c in
            ChapterDetailView(chapter: c)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                MetaLabel(text: "All arcs")
                Text("Chapters")
                    .font(Theme.Font.titleLarge)
                    .foregroundStyle(Theme.Palette.ink)
            }
            Spacer()
            Button {
                showNew = true
            } label: {
                Label("New chapter", systemImage: "plus")
            }
            .buttonStyle(.atlasPrimary)
        }
    }

    private func section(title: String, count: Int, chapters: [Chapter]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title, trailing: "\(count)")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(chapters) { c in
                    NavigationLink(value: c) {
                        ChapterCard(chapter: c)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ChapterCard: View {
    let chapter: Chapter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    Image(systemName: chapter.type.sfSymbol)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                    MetaLabel(text: chapter.type.label)
                }
                Spacer()
                MetaLabel(text: AtlasFormat.range(chapter.startDate, chapter.endDate))
            }

            Text(chapter.title)
                .font(Theme.Font.serif(26))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.top, 12)
                .multilineTextAlignment(.leading)

            if let p = chapter.purpose {
                Text(p)
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineLimit(2)
                    .padding(.top, 8)
            }

            VStack(spacing: 6) {
                HStack {
                    Text("\(chapter.doneTodos.count) / \(chapter.todos.count) todos")
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Palette.inkFaint)
                    Spacer()
                    Text("\(Int(chapter.progress * 100))%")
                        .font(Theme.Font.mono(11))
                        .foregroundStyle(Theme.Palette.inkFaint)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.Palette.borderWarm)
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.Palette.moss)
                            .frame(width: geo.size.width * chapter.progress, height: 3)
                    }
                }
                .frame(height: 3)
            }
            .padding(.top, 20)

            HStack {
                MetaLabel(text: chapter.status.rawValue)
                Spacer()
                MetaLabel(text: "updated \(AtlasFormat.relative(chapter.updatedAt))")
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .card()
    }
}
