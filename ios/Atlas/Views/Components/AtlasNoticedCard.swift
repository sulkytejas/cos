import SwiftUI

/// "Ayumi noticed" — the one agentic ask, rendered on **Material C** (pressed
/// specimen: lifted higher than everything else so the eye is drawn to it).
/// Surfaces a decision Ayumi thinks is forming; "Formalize" turns it into a real
/// Decision, "Not yet" sets it aside. Used in the chapter Decisions tab.
///
/// This is the only place Material C appears — per the v0.3 language, it is
/// reserved for the single agentic ask on a screen.
struct AtlasNoticedCard: View {
    let topic: String
    var onFormalize: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                WatcherIcon(size: 12)
                Text("AYUMI NOTICED")
                    .font(Theme.Font.mono(9.5))
                    .tracking(1.8)
                    .foregroundStyle(Theme.Palette.tealDeep)
            }

            (Text("You may be deciding: ").font(Theme.Font.serif(17))
             + Text(topic).font(Theme.Font.serifItalic(17))
             + Text(". Want to formalize this?").font(Theme.Font.serif(17)))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(3)

            HStack(spacing: 8) {
                Button(action: onFormalize) {
                    Text("Formalize")
                        .font(Theme.Font.sans(12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.Palette.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    Text("Not yet")
                        .font(Theme.Font.sans(12.5))
                        .foregroundStyle(Theme.Palette.inkFaint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .materialC()
    }
}
