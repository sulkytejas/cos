import SwiftUI
import SwiftData

/// Decisions — vertical timeline of chosen paths. No cards, no headers, no
/// add buttons. Each decision is a left-railed row: hairline rule with a
/// teal pip, mono date, serif title, sans rationale. New decisions are
/// captured via the global Capture sheet.
struct DecisionsTab: View {
    @Bindable var chapter: Chapter
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if chapter.decisions.isEmpty {
                Text("No decisions logged for this chapter.")
                    .font(Theme.Font.serifItalic(15))
                    .foregroundStyle(Theme.Palette.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ForEach(chapter.decisions.sorted(by: { $0.decidedAt > $1.decidedAt })) { d in
                    DecisionRow(decision: d) {
                        context.delete(d); chapter.touch(); try? context.save()
                    }
                }
            }
        }
    }
}

struct DecisionRow: View {
    let decision: Decision
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Left rail with the teal "kept choice" pip at the top
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(width: 1)
                Circle()
                    .fill(Theme.Palette.teal)
                    .frame(width: 7, height: 7)
                    .offset(y: 4)
            }
            .frame(width: 7)

            VStack(alignment: .leading, spacing: 4) {
                Text(AtlasFormat.mediumDate.string(from: decision.decidedAt).uppercased())
                    .font(Theme.Font.mono(10))
                    .tracking(1.4)
                    .foregroundStyle(Theme.Palette.inkFaint)
                Text(decision.title)
                    .font(Theme.Font.serif(19))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(2)
                    .padding(.top, 2)
                if let r = decision.rationale, !r.isEmpty {
                    Text(r)
                        .font(Theme.Font.sans(13.5))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .lineSpacing(3)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
