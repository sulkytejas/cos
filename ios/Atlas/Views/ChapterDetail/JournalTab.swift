import SwiftUI
import SwiftData

struct JournalTab: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            addCard
            entriesList
        }
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $draft)
                .frame(minHeight: 80)
                .font(Theme.Font.sans(14))
                .foregroundStyle(Theme.Palette.ink)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Note something. A thought, a meeting, a turn.")
                            .font(Theme.Font.sans(14))
                            .foregroundStyle(Theme.Palette.inkFaint)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }
            Hairline()
            HStack {
                Spacer()
                Button {
                    addEntry()
                } label: {
                    Label("Add entry", systemImage: "plus")
                }
                .buttonStyle(.atlasPrimary)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .card()
    }

    private var entriesList: some View {
        Group {
            if chapter.entries.isEmpty {
                Text("Nothing logged yet.")
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                VStack(spacing: 0) {
                    let sorted = chapter.entries.sorted(by: { $0.date > $1.date })
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, e in
                        EntryRow(entry: e) {
                            context.delete(e)
                            try? context.save()
                        }
                        if idx < sorted.count - 1 {
                            Hairline()
                                .padding(.leading, 100)
                        }
                    }
                }
            }
        }
    }

    private func addEntry() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = Entry(content: trimmed, chapter: chapter)
        context.insert(entry)
        chapter.touch()
        try? context.save()
        draft = ""
    }
}

struct EntryRow: View {
    let entry: Entry
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .trailing, spacing: 2) {
                MetaLabel(text: AtlasFormat.shortDay.string(from: entry.date))
                Text(AtlasFormat.relative(entry.date))
                    .font(Theme.Font.mono(9))
                    .foregroundStyle(Theme.Palette.inkFaint)
            }
            .frame(width: 80, alignment: .trailing)

            VStack(alignment: .leading, spacing: 8) {
                Text(entry.content)
                    .font(Theme.Font.sans(15))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(3)
                Chip(text: entry.source.rawValue,
                     tone: entry.source == .manual ? .neutral : .moss)
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
