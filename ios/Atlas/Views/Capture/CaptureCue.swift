import SwiftUI

// ════════════════════════════════════════════════════════════════════
//  CaptureCue.swift — the persistent summon cue (README §"The summon cue").
//
//  The ONLY persistent capture UI: a tiny, calm teal dot pinned above the
//  home indicator at the foot of every screen. A 7px dot in `--teal` rises
//  ~26px and fades on a slow ~4.8s loop WITH a rest between cycles (it must
//  feel like breathing, never jittery), with a faint vertical trail behind
//  it. No text label, no bar, no chevron.
//
//  Tap the dot OR swipe up from it (pointer travel > ~24px) to summon the
//  well. The container gradient is decorative only (`pointer-events:none` in
//  the CSS) — only the dot itself is tappable, so it can never intercept the
//  controls beneath it. If the host screen has its own bottom action/compose
//  bar, pass `avoidBottomInset` so the cue lifts above it and drops its
//  gradient (the general `.has-bottom-bar` behaviour).
//
//  Honours Reduce Motion: drops the loop and shows the dot at its risen rest
//  position (mirrors the CSS `@media (prefers-reduced-motion)` end-state).
// ════════════════════════════════════════════════════════════════════

struct CaptureCue: View {
    /// Summon the well (tap or swipe-up).
    var onSummon: () -> Void
    /// Height of any host bottom bar to lift above (0 ⇒ normal, with gradient).
    var avoidBottomInset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the host has a bottom bar to clear (drops the gradient).
    private var hasBottomBar: Bool { avoidBottomInset > 0 }

    // Geometry from atlas-capture.css `.ac-summon` / `.ac-cue`.
    private var summonHeight: CGFloat { hasBottomBar ? 46 : 78 }
    private var bottomPadding: CGFloat { hasBottomBar ? 8 : 17 }

    var body: some View {
        // The decorative gradient container — NON-interactive. Only the cue dot
        // inside is tappable, so controls beneath the gradient stay reachable.
        ZStack(alignment: .bottom) {
            if !hasBottomBar {
                LinearGradient(
                    colors: [Theme.Palette.paper.opacity(0), Theme.Palette.paper],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.66)
                )
                .frame(height: summonHeight)
                .allowsHitTesting(false)
            }

            CueDot(onSummon: onSummon, reduceMotion: reduceMotion)
                .padding(.bottom, bottomPadding)
        }
        .frame(maxWidth: .infinity)
        .frame(height: summonHeight, alignment: .bottom)
        .padding(.bottom, avoidBottomInset)
        // Only the dot accepts touches; the container itself does not.
        .allowsHitTesting(true)
        .accessibilityElement()
        .accessibilityLabel("Capture — swipe up or tap")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSummon() }
    }
}

// MARK: - The rising dot + trail

/// The 7px teal dot + its faint vertical trail. Tap or swipe-up (>~24px)
/// summons. The breathe loop is a ~4.8s keyframe with a rest (16%→58% hold,
/// then rise+fade, then a quiet tail) ported from `@keyframes ac-dot`.
private struct CueDot: View {
    var onSummon: () -> Void
    var reduceMotion: Bool

    /// Drives the 0…1 loop phase via a repeating animation.
    @State private var phase: CGFloat = 0
    /// Press lift (matches `.ac-cue:active { transform: translateY(-3px) }`).
    @State private var pressed = false

    // Tap-vs-swipe tracking: a pointer travel > ~24px upward summons.
    private let swipeThreshold: CGFloat = 24

    var body: some View {
        // 64×44 tap target (CSS `.ac-cue`), dot/trail anchored 7px up from base.
        ZStack(alignment: .bottom) {
            // Faint vertical trail behind the dot.
            trail
                .offset(y: -7)
            // The dot itself.
            Circle()
                .fill(Theme.Palette.teal)
                .frame(width: 7, height: 7)
                .offset(y: dotOffsetY)
                .opacity(dotOpacity)
        }
        .frame(width: 64, height: 44, alignment: .bottom)
        .contentShape(Rectangle())          // the whole 64×44 is the touch target
        .offset(y: pressed ? -3 : 0)
        .animation(Theme.Motion.overshoot(0.34), value: pressed)
        .gesture(
            // Tap OR swipe-up. minimumDistance 0 so a plain tap registers;
            // an upward drag past the threshold summons mid-gesture.
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    pressed = true
                    if v.startLocation.y - v.location.y > swipeThreshold {
                        pressed = false
                        onSummon()
                    }
                }
                .onEnded { v in
                    pressed = false
                    let dy = v.startLocation.y - v.location.y
                    // A tap (tiny travel) or a completed upward swipe both summon.
                    if dy < swipeThreshold, abs(v.translation.height) < 10,
                       abs(v.translation.width) < 10 {
                        onSummon()
                    } else if dy > swipeThreshold {
                        onSummon()
                    }
                }
        )
        .onAppear { startBreathing() }
    }

    // ── Trail (CSS `.ac-trail`): a 2×26 teal-to-clear bar, faintly pulsing.
    private var trail: some View {
        LinearGradient(
            colors: [Theme.Palette.teal.opacity(0), Theme.Palette.teal.opacity(0.24)],
            startPoint: .top, endPoint: .bottom
        )
        .frame(width: 2, height: 26)
        .clipShape(Capsule())
        .opacity(trailOpacity)
        .scaleEffect(y: trailScaleY, anchor: .bottom)
    }

    // MARK: Keyframe mapping (phase 0…1 over ~4.8s)
    //
    // ac-dot:   0% y+6 op0 · 16% op1 · 58% op1 · 76% y-26 op0 · 100% y-26 op0
    // ac-trail: 0% op0 sY0.2 · 24% op0.85 · 66% op0.4 · 80–100% op0 sY1

    private var dotOffsetY: CGFloat {
        guard !reduceMotion else { return -8 }   // reduced-motion rest position
        let p = phase
        if p < 0.58 { return 6 }                            // rests low, breathing in
        if p < 0.76 { return 6 + (-26 - 6) * (p - 0.58) / 0.18 }  // rises to -26
        return -26                                          // held up, faded out (the rest)
    }

    private var dotOpacity: Double {
        guard !reduceMotion else { return 0.9 }
        // The dot is a *living presence* — it brightens & rises on the breathe,
        // but never vanishes completely. A calm opacity floor keeps it a
        // persistent affordance (and means a static capture always shows it).
        let floor = 0.42
        let p = Double(phase)
        let breathe: Double
        if p < 0.16 { breathe = floor + (1 - floor) * (p / 0.16) }     // fade in
        else if p < 0.58 { breathe = 1 }                              // held bright
        else if p < 0.76 { breathe = 1 - (1 - floor) * (p - 0.58) / 0.18 } // fade as it rises
        else { breathe = floor }                                      // quiet rest (still present)
        return breathe
    }

    private var trailOpacity: Double {
        guard !reduceMotion else { return 0.9 }
        let p = Double(phase)
        if p < 0.24 { return 0.85 * (p / 0.24) }
        if p < 0.66 { return 0.85 - (0.85 - 0.4) * (p - 0.24) / 0.42 }
        if p < 0.80 { return 0.4 - 0.4 * (p - 0.66) / 0.14 }
        return 0
    }

    private var trailScaleY: CGFloat {
        guard !reduceMotion else { return 1 }
        // grows 0.2 → 1 over the cycle, anchored at the base.
        return 0.2 + 0.8 * phase
    }

    private func startBreathing() {
        guard !reduceMotion else { return }
        phase = 0
        // One 4.8s pass, looping forever — the keyframe shaping above gives the
        // rise + the quiet rest, so a plain linear drive reads as breathing.
        withAnimation(.linear(duration: 4.8).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}
