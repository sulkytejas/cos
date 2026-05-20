import SwiftUI
import SwiftData

struct DecisionsTab: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context
    @State private var showNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text("The record of choices. Why you chose this path over the alternatives.")
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                Spacer()
                Button {
                    showNew = true
                } label: {
                    Label("Log", systemImage: "plus")
                }
                .buttonStyle(.atlasPrimary)
            }

            if chapter.decisions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Palette.inkFaint)
                    Text("No decisions logged yet.")
                        .font(Theme.Font.sans(14))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .card()
            } else {
                VStack(spacing: 14) {
                    ForEach(chapter.decisions.sorted(by: { $0.decidedAt > $1.decidedAt })) { d in
                        DecisionCard(decision: d) {
                            context.delete(d)
                            chapter.touch()
                            try? context.save()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showNew) {
            DecisionSheet(chapter: chapter)
        }
    }
}

struct DecisionCard: View {
    let decision: Decision
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MetaLabel(text: AtlasFormat.mediumDate.string(from: decision.decidedAt))
            Text(decision.title)
                .font(Theme.Font.serif(22))
                .foregroundStyle(Theme.Palette.ink)
            if let r = decision.rationale, !r.isEmpty {
                Text(r)
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(3)
            }
            if let o = decision.optionsConsidered, !o.isEmpty {
                Hairline()
                MetaLabel(text: "Options considered")
                Text(o)
                    .font(Theme.Font.mono(12))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .card()
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct DecisionSheet: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var rationale = ""
    @State private var options = ""
    @State private var decidedAt = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you decide?", text: $title)
                        .font(Theme.Font.serif(20))
                } header: {
                    MetaLabel(text: "Title")
                }
                Section {
                    TextEditor(text: $rationale)
                        .frame(minHeight: 100)
                } header: {
                    MetaLabel(text: "Rationale")
                }
                Section {
                    TextEditor(text: $options)
                        .frame(minHeight: 100)
                        .font(Theme.Font.mono(13))
                } header: {
                    MetaLabel(text: "Options considered")
                }
                Section {
                    DatePicker("Decided at", selection: $decidedAt, displayedComponents: .date)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.paper)
            .navigationTitle("Log decision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let d = Decision(
            title: trimmed,
            rationale: rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : rationale.trimmingCharacters(in: .whitespacesAndNewlines),
            optionsConsidered: options.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : options.trimmingCharacters(in: .whitespacesAndNewlines),
            decidedAt: decidedAt,
            chapter: chapter
        )
        context.insert(d)
        chapter.touch()
        try? context.save()
        dismiss()
    }
}
