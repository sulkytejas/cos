import SwiftUI
import SwiftData

struct LinksTab: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context
    @State private var showNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text("How this chapter relates to the others. Blocks, enables, conflicts with, or simply touches.")
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                Spacer()
                Button {
                    showNew = true
                } label: {
                    Label("Add link", systemImage: "plus")
                }
                .buttonStyle(.atlasPrimary)
            }

            let allLinks = annotatedLinks()
            if allLinks.isEmpty {
                Text("No links yet.")
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(allLinks.enumerated()), id: \.element.id) { idx, item in
                        LinkRow(link: item.link, other: item.other, direction: item.direction) {
                            context.delete(item.link)
                            try? context.save()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        if idx < allLinks.count - 1 {
                            Hairline()
                        }
                    }
                }
                .card()
            }
        }
        .sheet(isPresented: $showNew) {
            LinkSheet(chapter: chapter)
        }
    }

    struct LinkItem: Identifiable {
        let id: UUID
        let link: ChapterLink
        let other: Chapter
        let direction: Direction
        enum Direction { case outgoing, incoming }
    }

    private func annotatedLinks() -> [LinkItem] {
        var items: [LinkItem] = []
        for l in chapter.outgoingLinks {
            if let other = l.toChapter {
                items.append(LinkItem(id: l.id, link: l, other: other, direction: .outgoing))
            }
        }
        for l in chapter.incomingLinks {
            if let other = l.fromChapter {
                items.append(LinkItem(id: l.id, link: l, other: other, direction: .incoming))
            }
        }
        return items
    }
}

struct LinkRow: View {
    let link: ChapterLink
    let other: Chapter
    let direction: LinksTab.LinkItem.Direction
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Chip(text: link.relation.label, tone: tone)
            Image(systemName: direction == .outgoing ? "arrow.right" : "arrow.left")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Palette.inkFaint)
            NavigationLink(value: other) {
                HStack(spacing: 6) {
                    Image(systemName: other.type.sfSymbol)
                        .font(.system(size: 12))
                    Text(other.title)
                        .font(Theme.Font.sans(14))
                }
                .foregroundStyle(Theme.Palette.ink)
            }
            Spacer()
            if let n = link.note, !n.isEmpty {
                Text("“\(n)”")
                    .italic()
                    .font(Theme.Font.sans(12))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Remove link", systemImage: "trash")
            }
        }
    }

    private var tone: ChipTone {
        switch link.relation {
        case .blocks, .conflicts: return .ember
        case .enables: return .moss
        case .related: return .neutral
        }
    }
}

struct LinkSheet: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Chapter.title) private var allChapters: [Chapter]

    @State private var relation: LinkRelation = .related
    @State private var targetID: UUID?
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Relation", selection: $relation) {
                        ForEach(LinkRelation.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                }
                Section {
                    Picker("Target chapter", selection: $targetID) {
                        Text("— select —").tag(UUID?.none)
                        ForEach(allChapters.filter { $0.id != chapter.id }) { c in
                            Text(c.title).tag(Optional(c.id))
                        }
                    }
                }
                Section {
                    TextField("Optional note", text: $note)
                } header: {
                    MetaLabel(text: "Note")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.paper)
            .navigationTitle("Link chapter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Link") { save() }
                        .disabled(targetID == nil)
                }
            }
        }
    }

    private func save() {
        guard let targetID,
              let target = allChapters.first(where: { $0.id == targetID }) else { return }
        let link = ChapterLink(
            from: chapter,
            to: target,
            relation: relation,
            note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note.trimmingCharacters(in: .whitespaces)
        )
        context.insert(link)
        chapter.touch()
        try? context.save()
        dismiss()
    }
}
