import SwiftUI

/// When the value changes, the new string rises 8pt from below with blur(2 → 0)
/// over 380ms — the prototype's `morph-in` keyframe.
struct MorphText: View {
    let value: String
    var font: Font = Theme.Font.mono(11)
    var color: Color = Theme.Palette.teal
    var tracking: CGFloat = 0.4

    var body: some View {
        Text(value)
            .font(font)
            .tracking(tracking)
            .foregroundStyle(color)
            // Each new `value` becomes a new identity → triggers a transition.
            .id(value)
            .transition(.morphIn)
            .animation(.easeOut(duration: 0.38), value: value)
    }
}

private struct BlurMod: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

extension AnyTransition {
    /// Slide up + fade in + blur fade-out, matching the prototype's `morph-in`.
    static var morphIn: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: 8))
                .combined(with: .modifier(active: BlurMod(radius: 2),
                                          identity: BlurMod(radius: 0))),
            removal: .opacity
        )
    }
}
