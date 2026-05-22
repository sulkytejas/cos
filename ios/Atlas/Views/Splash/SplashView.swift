import SwiftUI

/// SplashView — the app's first impression. Per the v0.3 brand spec
/// (Icon options.html — "Splash · the moment that earns the kanji"):
///
///   0.0s  Paper background fades in. 歩 appears at 96pt, breathing 4.5s.
///   1.0s  Wordmark "Ayumi" fades up below the kanji (26pt italic).
///   1.6s  Tagline "a quiet pace, kept for you" fades up (13pt italic).
///   2.2s  Teal pulse dot appears at the bottom.
///   2.8s  Everything fades; the morning page slides in.
///
/// The minimum splash duration must be 1.5s — anything shorter and the
/// user never reads the kanji, and the system collapses to "weird empty
/// home screen icon."
struct SplashView: View {
    let onComplete: () -> Void

    @State private var kanjiOpacity: Double = 0
    @State private var kanjiScale: CGFloat = 1.0
    @State private var wordmarkOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var dotOpacity: Double = 0
    @State private var rootOpacity: Double = 1.0
    @State private var kanjiSeed = UUID()

    var body: some View {
        ZStack {
            Theme.Palette.paper
                .ignoresSafeArea()
                // Faint radial gradients matching the design's splash-mock-frame
                .overlay(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(red: 0/255, green: 137/255, blue: 168/255).opacity(0.03), location: 0),
                            .init(color: .clear, location: 0.5),
                            .init(color: Color(red: 13/255, green: 51/255, blue: 36/255).opacity(0.025), location: 1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                )

            VStack(spacing: 18) {
                // Stroke-by-stroke 歩 — 8 strokes drawn in Japanese stroke
                // order, then a gentle breathing scale takes over.
                KanjiBrushed(size: 128, ink: Theme.Palette.ink, totalDuration: 1.0)
                    .id(kanjiSeed)
                    .opacity(kanjiOpacity)
                    .scaleEffect(kanjiScale)
                    .animation(
                        .easeInOut(duration: 2.25).repeatForever(autoreverses: true),
                        value: kanjiScale
                    )

                Text("Ayumi")
                    .font(Theme.Font.serifItalic(26))
                    .foregroundStyle(Theme.Palette.ink)
                    .tracking(-0.4)
                    .opacity(wordmarkOpacity)

                Text("a quiet pace, kept for you")
                    .font(Theme.Font.serifItalic(13))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .opacity(taglineOpacity)
            }

            // Teal pulse dot at the bottom — indicates load.
            VStack {
                Spacer()
                PulseDot()
                    .opacity(dotOpacity)
                    .padding(.bottom, 48)
            }
        }
        .opacity(rootOpacity)
        .task { await runSequence() }
    }

    private func runSequence() async {
        // 0.0s — kanji canvas appears immediately so the 8-stroke animation
        // inside KanjiBrushed can start drawing. (The strokes are invisible
        // before they're drawn — opacity controls whether the canvas itself
        // can paint.)
        kanjiOpacity = 1.0

        // 1.0s — strokes finish; nudge into the breathing scale loop
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        kanjiScale = 1.02

        // 1.0s — wordmark fades in (right as strokes settle)
        withAnimation(.easeOut(duration: 0.46)) { wordmarkOpacity = 1 }

        // 1.6s — tagline fades in
        try? await Task.sleep(nanoseconds: 600_000_000)
        withAnimation(.easeOut(duration: 0.46)) { taglineOpacity = 1 }

        // 2.2s — pulse dot appears
        try? await Task.sleep(nanoseconds: 600_000_000)
        withAnimation(.easeOut(duration: 0.32)) { dotOpacity = 1 }

        // 2.8s — fade everything out
        try? await Task.sleep(nanoseconds: 600_000_000)
        withAnimation(.easeOut(duration: 0.42)) { rootOpacity = 0 }
        try? await Task.sleep(nanoseconds: 440_000_000)
        onComplete()
    }
}

/// 6pt teal pulse dot with the .splash-pulse box-shadow ripple from the design.
private struct PulseDot: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            // Ripple
            Circle()
                .stroke(Theme.Palette.teal.opacity(0.4 - 0.4 * Double(phase)), lineWidth: 2)
                .frame(width: 6 + 16 * phase, height: 6 + 16 * phase)
            // Core dot
            Circle()
                .fill(Theme.Palette.teal)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

#Preview {
    SplashView(onComplete: {})
}
