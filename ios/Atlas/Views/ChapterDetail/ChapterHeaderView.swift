import SwiftUI

struct ChapterHeaderView: View {
    @Bindable var chapter: Chapter
    @FocusState private var titleFocused: Bool
    @FocusState private var purposeFocused: Bool
    @State private var purposeDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Title", text: Binding(
                get: { chapter.title },
                set: { chapter.title = $0; chapter.touch() }
            ), axis: .vertical)
                .focused($titleFocused)
                .font(Theme.Font.serif(38))
                .foregroundStyle(Theme.Palette.ink)
                .lineLimit(3)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit { titleFocused = false }

            if let p = chapter.purpose, !p.isEmpty, !purposeFocused {
                Text(p)
                    .font(Theme.Font.serif(17))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(2)
                    .onTapGesture {
                        purposeDraft = p
                        purposeFocused = true
                    }
            } else {
                TextEditor(text: Binding(
                    get: { purposeDraft },
                    set: { purposeDraft = $0 }
                ))
                .focused($purposeFocused)
                .frame(minHeight: 60)
                .font(Theme.Font.serif(17))
                .foregroundStyle(Theme.Palette.inkSecondary)
                .scrollContentBackground(.hidden)
                .background(Theme.Palette.paper.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onAppear { purposeDraft = chapter.purpose ?? "" }
                .onChange(of: purposeFocused) { _, isFocused in
                    if !isFocused {
                        let trimmed = purposeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        chapter.purpose = trimmed.isEmpty ? nil : trimmed
                        chapter.touch()
                    }
                }
            }
        }
    }
}
