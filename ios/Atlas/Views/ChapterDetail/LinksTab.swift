import SwiftUI
import SwiftData

/// Links — how this chapter relates to others. Clean horizontal rows:
/// 80pt right-aligned mono uppercase label → hairline arrow → serif title
/// of the other chapter + sans-grey note. No card chrome, no add button —
/// links are created via the link picker that lives elsewhere.
struct LinksTab: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context
    @State private var showNew = false

    var body: some View {
        let items = annotatedLinks()
        VStack(alignment: .leading, spacing: 14) {
            if items.isEmpty {
                Text("No links yet.")
                    .font(Theme.Font.serifItalic(15))
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ForEach(items) { item in
                    LinkRow(item: item) {
                        context.delete(item.link); try? context.save()
                    }
                }
            }
        }
        .sheet(isPresented: $showNew) { LinkSheet(chapter: chapter) }
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
    let item: LinksTab.LinkItem
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Right-aligned, fixed-width mono label
            Text(item.link.relation.rawValue.uppercased())
                .font(Theme.Font.mono(10))
                .tracking(1.7)
                .foregroundStyle(linkColor)
                .frame(width: 80, alignment: .trailing)

            // Hairline arrow
            LinkArrow(reversed: item.direction == .incoming, color: linkColor)
                .frame(width: 28, height: 10)

            // Other chapter title + note
            VStack(alignment: .leading, spacing: 2) {
                NavigationLink(value: item.other) {
                    Text(item.other.title)
                        .font(Theme.Font.serif(16))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                if let note = item.link.note, !note.isEmpty {
                    Text(note)
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(Theme.Palette.inkFaint)
                        .lineLimit(2)
                        .lineSpacing(2)
                }
            }
            Spacer(minLength: 0)
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Remove link", systemImage: "trash")
            }
        }
    }

    private var linkColor: Color {
        switch item.link.relation {
        case .blocks, .conflicts: return Theme.Palette.teal
        case .enables:            return Theme.Palette.forest
        case .related:            return Theme.Palette.inkFaint
        }
    }
}

/// Hairline arrow → with an open chevron head.
struct LinkArrow: View {
    let reversed: Bool
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let y = size.height / 2
            let xStart: CGFloat = reversed ? size.width : 0
            let xLineEnd: CGFloat = reversed ? 5 : size.width - 5
            // Shaft
            var shaft = Path()
            shaft.move(to: CGPoint(x: xStart, y: y))
            shaft.addLine(to: CGPoint(x: xLineEnd, y: y))
            ctx.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            // Arrowhead
            var head = Path()
            if reversed {
                head.move(to: CGPoint(x: 5, y: y - 4))
                head.addLine(to: CGPoint(x: 0, y: y))
                head.addLine(to: CGPoint(x: 5, y: y + 4))
            } else {
                head.move(to: CGPoint(x: size.width - 5, y: y - 4))
                head.addLine(to: CGPoint(x: size.width, y: y))
                head.addLine(to: CGPoint(x: size.width - 5, y: y + 4))
            }
            ctx.stroke(head, with: .color(color), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }
    }
}

// The Link creation sheet is still here so existing call sites (Chapter Detail
// "+ Add link" if you ever surface it) keep working — but it's no longer
// rendered as a button in the read-only Links tab.
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
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        let link = ChapterLink(
            from: chapter, to: target, relation: relation,
            note: trimmed.isEmpty ? nil : trimmed
        )
        context.insert(link); chapter.touch(); try? context.save()
        dismiss()
    }
}
