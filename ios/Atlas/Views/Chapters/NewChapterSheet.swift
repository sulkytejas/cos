import SwiftUI
import SwiftData

struct NewChapterSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var type: ChapterType = .project
    @State private var status: ChapterStatus = .active
    @State private var hasStart = false
    @State private var hasEnd = false
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(60 * 60 * 24 * 30)
    @State private var purpose = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Trip to Ladakh", text: $title)
                        .font(Theme.Font.serif(20))
                } header: {
                    MetaLabel(text: "Title")
                }

                Section {
                    Picker("Type", selection: $type) {
                        ForEach(ChapterType.allCases) { t in
                            Text(t.rawValue.capitalized).tag(t)
                        }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(ChapterStatus.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                }

                Section {
                    Toggle("Start date", isOn: $hasStart)
                    if hasStart {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    Toggle("End date", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("End", selection: $endDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }

                Section {
                    TextEditor(text: $purpose)
                        .frame(minHeight: 80)
                } header: {
                    MetaLabel(text: "Purpose")
                } footer: {
                    Text("Why this matters. One or two sentences.")
                        .font(Theme.Font.sans(12))
                        .foregroundStyle(Theme.Palette.inkFaint)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.paper)
            .navigationTitle("New chapter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() {
        let chapter = Chapter(
            title: title.trimmingCharacters(in: .whitespaces),
            type: type,
            status: status,
            startDate: hasStart ? startDate : nil,
            endDate: hasEnd ? endDate : nil,
            purpose: purpose.trimmingCharacters(in: .whitespaces).isEmpty ? nil : purpose.trimmingCharacters(in: .whitespaces)
        )
        context.insert(chapter)
        try? context.save()
        dismiss()
    }
}
