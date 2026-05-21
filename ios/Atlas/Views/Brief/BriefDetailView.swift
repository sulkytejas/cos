import SwiftUI
import SwiftData

/// Brief detail — pushed from the Today brief teaser. Renders via BriefRenderer
/// with a sticky ActionStrip footer pinned to the bottom of the screen.
struct BriefDetailView: View {
    @Bindable var brief: Brief
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                back
                masthead
                Rectangle()
                    .fill(Theme.Palette.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, 22)
                VStack(alignment: .leading, spacing: 0) {
                    BriefRenderer(brief: brief)
                }
                .padding(.horizontal, 22)
                Spacer().frame(height: 110)
            }
            .padding(.top, 6)
        }
        .background(Theme.Palette.paper)
        .navigationBarHidden(true)
        .overlay(alignment: .bottom) {
            footer
        }
    }

    private var back: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Today")
                        .font(Theme.Font.sans(13, weight: .medium))
                }
                .foregroundStyle(Theme.Palette.inkFaint)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("BRIEF")
                .font(Theme.Font.mono(10))
                .tracking(1.6)
                .foregroundStyle(Theme.Palette.inkFaint)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if let chapter = brief.chapterTitle {
                    Text(chapter.uppercased())
                        .font(Theme.Font.mono(9.5))
                        .tracking(1.8)
                        .foregroundStyle(Theme.Palette.inkFaint)
                }
                if brief.chapterTitle != nil && brief.relevance != nil {
                    Text("·").foregroundStyle(Theme.Palette.inkFainter)
                }
                if let r = brief.relevance {
                    Text(r.uppercased())
                        .font(Theme.Font.mono(9.5))
                        .tracking(1.6)
                        .foregroundStyle(Theme.Palette.inkFaint)
                }
            }
            Text(brief.title)
                .font(Theme.Font.serifItalic(38))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(2)
            if !brief.situationDescription.isEmpty {
                Text(brief.situationDescription)
                    .font(Theme.Font.sans(14.5))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: 320, alignment: .leading)
            }
            HStack(spacing: 10) {
                if let w = brief.when {
                    Text(w)
                        .font(Theme.Font.mono(10))
                        .tracking(0.6)
                        .foregroundStyle(Theme.Palette.tealDeep)
                }
                if brief.when != nil && brief.drafted != nil {
                    Rectangle()
                        .fill(Theme.Palette.hairline)
                        .frame(width: 1, height: 10)
                }
                if let d = brief.drafted {
                    Text(d)
                        .font(Theme.Font.mono(10))
                        .foregroundStyle(Theme.Palette.inkFainter)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.Palette.hairline)
                .frame(height: 1)
            HStack(spacing: 8) {
                Button {
                    brief.status = .actedOn
                    try? context.save()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Text(brief.primaryAction ?? "Open")
                            .font(Theme.Font.sans(13.5, weight: .medium))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.Palette.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)

                ForEach(Array(brief.secondaryActions.enumerated()), id: \.offset) { _, label in
                    Button {
                        // Snooze / Dig deeper — placeholders for now
                    } label: {
                        Text(label)
                            .font(Theme.Font.sans(12, weight: .medium))
                            .foregroundStyle(Theme.Palette.inkSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Theme.Palette.paper)
        }
    }
}
