import SwiftUI

/// Square checkbox with the prototype's exact three-stage animation:
/// 1. Background fills (220ms ease-out)
/// 2. Inner SVG scales 0.6 → 1.0 with overshoot spring (280ms)
/// 3. Check stroke trims from 0 → 1 over 360ms, with a 60ms delay so it
///    "draws on" left-to-right after the box has filled.
struct InkCheckbox: View {
    let checked: Bool
    var accent: ChapterAccent = .forest
    var onToggle: () -> Void

    var body: some View {
        Button(action: {
            // Light haptic feel via animation, no UIKit haptic dependency
            onToggle()
        }) {
            ZStack {
                // ── Outer box ──
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(checked ? accent.stroke : Theme.Palette.hairlineStrong, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(checked ? accent.stroke : Color.clear)
                    )
                    .frame(width: 22, height: 22)
                    .animation(.easeOut(duration: 0.22), value: checked)

                // ── Inner check, scaled + drawn ──
                CheckGlyph(checked: checked)
                    .frame(width: 14, height: 14)
                    .scaleEffect(checked ? 1.0 : 0.6)
                    .animation(
                        // cubic-bezier(.34,1.6,.64,1) ≈ light overshoot spring
                        .spring(response: 0.28, dampingFraction: 0.58, blendDuration: 0),
                        value: checked
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(checked ? "Mark not done" : "Mark done")
    }
}

/// The check path itself — animates its trim from 0 → 1 over 360ms after a 60ms
/// delay so the stroke draws on left-to-right once the box has filled.
private struct CheckGlyph: View {
    let checked: Bool

    var body: some View {
        Path { p in
            // Coords from the prototype: "M2.5 7.5 L5.6 10.5 L11.5 4.0" in a 14×14 viewBox
            p.move(to: CGPoint(x: 2.5, y: 7.5))
            p.addLine(to: CGPoint(x: 5.6, y: 10.5))
            p.addLine(to: CGPoint(x: 11.5, y: 4.0))
        }
        .trim(from: 0, to: checked ? 1 : 0)
        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        .animation(
            .easeOut(duration: 0.36).delay(checked ? 0.06 : 0),
            value: checked
        )
    }
}
