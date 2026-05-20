import SwiftUI
import SwiftData

struct TodosTab: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context

    @State private var newText = ""
    @State private var newDueDate: Date = Date()
    @State private var hasDueDate = false
    @State private var showDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            addRow
            openSection
            if !chapter.doneTodos.isEmpty {
                doneSection
            }
        }
    }

    private var addRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TextField("Add a todo…", text: $newText)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.sans(15))
                    .submitLabel(.done)
                    .onSubmit { addTodo() }
                Button {
                    addTodo()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.atlasPrimary)
                .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Toggle(isOn: $hasDueDate) {
                    MetaLabel(text: "due date")
                }
                .toggleStyle(.switch)
                .tint(Theme.Palette.moss)
                if hasDueDate {
                    DatePicker("", selection: $newDueDate, displayedComponents: .date)
                        .labelsHidden()
                }
                Spacer()
            }
        }
        .padding(16)
        .card()
    }

    private var openSection: some View {
        VStack(spacing: 0) {
            let items = chapter.openTodos.sorted(by: sortTodos)
            if items.isEmpty {
                HStack {
                    Text("All clear.")
                        .font(Theme.Font.sans(14))
                        .foregroundStyle(Theme.Palette.inkFaint)
                    Spacer()
                }
                .padding(20)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, t in
                    TodoRow(todo: t,
                            onToggle: { toggle(t) },
                            onDelete: { delete(t) })
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    if idx < items.count - 1 {
                        Hairline()
                    }
                }
            }
        }
        .card()
    }

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showDone.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showDone ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    MetaLabel(text: "Done · \(chapter.doneTodos.count)")
                }
            }
            .buttonStyle(.plain)
            if showDone {
                let items = chapter.doneTodos.sorted(by: sortTodos)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, t in
                        TodoRow(todo: t,
                                onToggle: { toggle(t) },
                                onDelete: { delete(t) })
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        if idx < items.count - 1 {
                            Hairline()
                        }
                    }
                }
                .card()
            }
        }
    }

    private func sortTodos(_ a: Todo, _ b: Todo) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (l?, r?): return l < r
        case (nil, _?): return false
        case (_?, nil): return true
        default: return a.createdAt < b.createdAt
        }
    }

    private func addTodo() {
        let trimmed = newText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let todo = Todo(text: trimmed,
                        dueDate: hasDueDate ? newDueDate : nil,
                        chapter: chapter)
        context.insert(todo)
        chapter.touch()
        try? context.save()
        newText = ""
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
    @State private var showDelete = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(todo.done ? Theme.Palette.moss : Theme.Palette.borderWarmStrong, lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(todo.done ? Theme.Palette.moss : Color.clear)
                        )
                        .frame(width: 16, height: 16)
                    if todo.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.Palette.paper)
                    }
                }
                .padding(.top, 2)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(todo.text)
                    .font(Theme.Font.sans(14))
                    .foregroundStyle(todo.done ? Theme.Palette.inkFaint : Theme.Palette.ink)
                    .strikethrough(todo.done)
                if let due = todo.dueDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                        Text(AtlasFormat.mediumDate.string(from: due))
                            .font(Theme.Font.mono(11))
                    }
                    .foregroundStyle(Color.dueColor(for: due))
                }
            }
            Spacer()
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
