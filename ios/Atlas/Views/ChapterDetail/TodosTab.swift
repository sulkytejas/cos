import SwiftUI
import SwiftData

struct TodosTab: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context

    var body: some View {
        todosList
    }

    /// Single list — open and done in creation order, done rows dim in place.
    private var todosList: some View {
        let items = chapter.todos.sorted { $0.createdAt < $1.createdAt }
        return Group {
            if items.isEmpty {
                Text("No todos yet — capture one.")
                    .font(Theme.Font.serifItalic(15))
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, t in
                        TodoRow(todo: t,
                                onToggle: { toggle(t) },
                                onDelete: { delete(t) })
                            .padding(.vertical, 12)
                        if idx < items.count - 1 {
                            Hairline().opacity(0.5)
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ t: Todo) {
        t.done.toggle()
        t.doneAt = t.done ? Date() : nil
        chapter.touch()
        try? context.save()
    }

    private func delete(_ t: Todo) {
        context.delete(t)
        chapter.touch()
        try? context.save()
    }
}

struct TodoRow: View {
    @Bindable var todo: Todo
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            InkCheckbox(
                checked: todo.done,
                accent: todo.chapter?.accent ?? .forest,
                onToggle: onToggle
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(todo.text)
                    .font(.system(size: 14,
                                  weight: todo.done ? .light : .regular,
                                  design: .default))
                    .foregroundStyle(Theme.Palette.ink)
                    .strikethrough(todo.done, color: Theme.Palette.inkFaint)
                if let due = todo.dueDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.system(size: 9))
                        Text(AtlasFormat.mediumDate.string(from: due))
                            .font(Theme.Font.mono(11))
                    }
                    .foregroundStyle(Color.dueColor(for: due))
                }
            }
            Spacer()
        }
        .opacity(todo.done ? 0.5 : 1)
        .animation(.easeOut(duration: 0.28), value: todo.done)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
