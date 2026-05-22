import SwiftUI

/// KanjiBrushed — the kanji 歩 (ayumu, "step") set in Shippori Mincho Bold
/// and revealed like a stone being discovered: it starts faint and slightly
/// out of focus, then settles into full clarity as the paper "clears".
///
/// The character was always there — we're just bringing it into focus.
/// (Earlier per-stroke implementations rendered the KanjiVG hairline paths
/// which don't match the actual font's serif weight — this uses the real
/// typeface so it looks like the design.)
struct KanjiBrushed: View {
    /// Final visible size — passed to Theme.Font.kanji as the point size.
    var size: CGFloat = 96
    /// Ink color — defaults to Theme.Palette.ink.
    var ink: Color = Theme.Palette.ink
    /// Total seconds the reveal takes (fade + blur + scale + settle).
    var totalDuration: Double = 1.1
    /// Called when the reveal finishes.
    var onComplete: (() -> Void)? = nil

    @State private var opacity: Double = 0
    @State private var blurRadius: CGFloat = 14
    @State private var scale: CGFloat = 0.92
    @State private var yOffset: CGFloat = 8

    var body: some View {
        Text("歩")
            .font(Theme.Font.kanji(size))
            .foregroundStyle(ink)
            .opacity(opacity)
            .blur(radius: blurRadius)
            .scaleEffect(scale)
            .offset(y: yOffset)
            .frame(width: size * 1.4, height: size * 1.4)   // give blur halo room
            .task { await runReveal() }
    }

    private func runReveal() async {
        // One coordinated reveal — everything resolves together, like the
        // image you've been squinting at coming into focus.
        withAnimation(.easeOut(duration: totalDuration)) {
            opacity = 1.0
            blurRadius = 0
            scale = 1.0
            yOffset = 0
        }
        let nanos = UInt64(totalDuration * 1_000_000_000) + 60_000_000
        try? await Task.sleep(nanoseconds: nanos)
        onComplete?()
    }
}

#Preview {
    VStack(spacing: 32) {
        KanjiBrushed(size: 160)
        BrushedA(size: 96)
    }
    .padding(40)
    .background(Theme.Palette.paper)
}
