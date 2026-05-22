import SwiftUI
import SwiftData

/// Journal — passive + manual entries woven together as a single feed.
/// Each entry is a hairline-divided row: source label + relative time +
/// the entry text. Passive sources (Email/Calendar/Drive) render at 78%
/// opacity in lighter ink so manual entries quietly dominate the page.
/// No add card — new entries arrive via the global Capture sheet.
struct JournalTab: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context

    var body: some View {
        let sorted = chapter.entries.sorted(by: { $0.date > $1.date })
        if sorted.isEmpty {
            Text("Nothing logged yet.")
                .font(Theme.Font.serifItalic(15))
                .foregroundStyle(Theme.Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, e in
                    EntryRow(entry: e) {
                        context.delete(e); try? context.save()
                    }
                    if idx < sorted.count - 1 {
                        Hairline().opacity(0.5)
                    }
                }
            }
        }
    }
}

struct EntryRow: View {
    let entry: Entry
    let onDelete: () -> Void

    private var passive: Bool { entry.source != .manual }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(entry.source.rawValue.uppercased())
                    .font(Theme.Font.mono(9.5))
                    .tracking(1.8)
                    .foregroundStyle(passive ? Theme.Palette.inkFainter : Theme.Palette.teal)
                Text("·")
                    .foregroundStyle(Theme.Palette.inkFainter)
                Text(AtlasFormat.relative(entry.date))
                    .font(Theme.Font.mono(9.5))
                    .foregroundStyle(Theme.Palette.inkFainter)
            }
            Text(entry.content)
                .font(.system(size: 14,
                              weight: passive ? .regular : .medium,
                              design: .default))
                .foregroundStyle(passive ? Theme.Palette.inkSecondary : Theme.Palette.ink)
                .lineSpacing(3)
        }
        .opacity(passive ? 0.78 : 1.0)
        .padding(.vertical, 12)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
