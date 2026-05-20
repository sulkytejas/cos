import SwiftUI
import SwiftData

struct CaptureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Chapter.updatedAt, order: .reverse) private var chapters: [Chapter]
    @FocusState private var textFocused: Bool

    @State private var text: String = ""
    @State private var chapterID: UUID?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(Theme.Font.sans(16))
                        .scrollContentBackground(.hidden)
                        .background(Theme.Palette.paper)
                        .focused($textFocused)
                    if text.isEmpty {
                        Text("What just happened? What needs to happen?")
                            .font(Theme.Font.sans(16))
                            .foregroundStyle(Theme.Palette.inkFaint)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Hairline()

                VStack(spacing: 12) {
                    HStack {
                        MetaLabel(text: "chapter")
                        Spacer()
                        Picker("Chapter", selection: $chapterID) {
                            ForEach(chapters) { c in
                                Text(c.title).tag(Optional(c.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.Palette.ink)
                    }

                    HStack(spacing: 10) {
                        ghostAction(label: "Todo", icon: "checkmark.square") { save(as: .todo) }
                        ghostAction(label: "Decision", icon: "lightbulb") { save(as: .decision) }
                        primaryAction(label: "Journal", icon: "book") { save(as: .journal) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Theme.Palette.paper)
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if chapterID == nil {
                let active = chapters.first(where: { $0.status == .active })
                chapterID = (active ?? chapters.first)?.id
            }
            textFocused = true
        }
    }

    private func primaryAction(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.atlasPrimary)
        .disabled(canSave == false)
        .opacity(canSave ? 1 : 0.4)
    }

    private func ghostAction(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.atlasGhost)
        .disabled(canSave == false)
        .opacity(canSave ? 1 : 0.4)
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chapterID != nil
    }

    private enum Kind { case todo, decision, journal }

    private func save(as kind: Kind) {
        guard let chapterID,
              let chapter = chapters.first(where: { $0.id == chapterID }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch kind {
        case .todo:
            context.insert(Todo(text: trimmed, chapter: chapter))
        case .decision:
            let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
            let head = String(firstLine.prefix(120))
            context.insert(Decision(title: head, rationale: trimmed, chapter: chapter))
        case .journal:
            context.insert(Entry(content: trimmed, chapter: chapter))
        }
        chapter.touch()
        try? context.save()
        dismiss()
    }
}

