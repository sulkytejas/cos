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
    /// Suppress the decorative paper-fade gradient even with no bottom bar. The
    /// Living Chapter's `.conv` has NO `mask-image` in the design CSS, so its
    /// timeline (lower chips, pencil, the "here" pin) must reach the card's
    /// bottom edge at full opacity — the cue dot still rides at the foot, just
    /// without the white wash that the conversational screens carry.
    var suppressBottomFade: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the host has a bottom bar to clear (drops the gradient).
    private var hasBottomBar: Bool { avoidBottomInset > 0 }
    /// Whether to draw the decorative paper-fade gradient at all.
    private var showsFade: Bool { !hasBottomBar && !suppressBottomFade }

    // Geometry from atlas-capture.css `.ac-summon` / `.ac-cue`. The container
    // height drives ONLY the dot's resting position (CSS `.ac-summon`
    // height 78 / padding-bottom 17; `.ac-dot` bottom 7) — DO NOT shrink it or
    // the cue dot drifts off the CSS-correct rest point on every screen.
    private var summonHeight: CGFloat { hasBottomBar ? 46 : 78 }
    private var bottomPadding: CGFloat { hasBottomBar ? 8 : 17 }

    // The decorative paper-fade is the CSS `.ac-summon` background verbatim:
    // `linear-gradient(180deg, rgba(255,255,255,0) 0%, var(--paper) 64%)` over the
    // 78pt summon container. The `.conv` surfaces (Today/Brief/Review/Search) carry
    // NO mask of their own, so this 78pt wash IS the only thing that dissolves
    // content scrolling under the foot to paper.
    //
    // The prior 46pt / endpoint-0.7 wash was too short and too weak: the bottom-most
    // Review HELD card (its pink HELD pill sits ~64pt above the screen bottom) read
    // at FULL saturation in the sim, whereas the reference washes that pill to
    // near-white (#FEFEFE) — see ref-review.png vs sim-review.png. Restore the
    // CSS-authoritative 78pt height with the solid-paper point at 64% so content at
    // the foot dissolves to paper exactly as the reference shows. (The `suppressBottomFade`
    // chapter path is untouched — the chapter `.conv` has no wash by design.)
    private var fadeHeight: CGFloat { 78 }
    /// CSS `.ac-summon` gradient reaches solid `--paper` at 64% of its height.
    private var fadeSolidPoint: CGFloat { 0.64 }

    var body: some View {
        // The decorative gradient container — NON-interactive. Only the cue dot
        // inside is tappable, so controls beneath the gradient stay reachable.
        ZStack(alignment: .bottom) {
            if showsFade {
                LinearGradient(
                    colors: [Theme.Palette.paper.opacity(0), Theme.Palette.paper],
                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: fadeSolidPoint)
                )
                .frame(height: fadeHeight)
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
        // but never vanishes completely. A high opacity floor keeps the resting
        // dot reading as saturated accent teal (#0089a8) rather than a pale cyan,
        // so a static capture always shows the saturated accent (ref: the bottom
        // timeline terminus / pagination dot).
        //
        // Measured: at floor 0.85 the 7px dot composited over the warm paper
        // gradient read ~#299CB6 (too light/cyan) vs the ref ~#0889AA (= --teal
        // #0089a8). Raised to 0.97 so the resting/captured frame reads as the
        // saturated accent teal while the rise still fades visibly toward the
        // top of the breathe. (The CSS dot is opacity 1 across its 16–58% hold;
        // a near-1 floor keeps the resting hue true without flattening the loop.)
        let floor = 0.97
        let p = Double(phase)
        let breathe: Double
        if p < 0.16 { breathe = floor + (1 - floor) * (p / 0.16) }     // fade in
        else if p < 0.58 { breathe = 1 }                              // held bright
        else if p < 0.76 { breathe = 1 - (1 - floor) * (p - 0.58) / 0.18 } // fade as it rises
        else { breathe = floor }                                      // quiet rest (still present)
        return breathe
    }

    private var trailOpacity: Double {
        guard !reduceMotion else { return 0.6 }
        // The vertical stem (`.ac-trail`) reads as a ~25px teal stem below the dot
        // in the ref's resting frame. The pure CSS keyframe drops the trail to
        // opacity 0 for the held 80–100% tail, so a static capture landing there
        // showed NO stem. Keep a low floor (0.3) so the breathe still pulses the
        // stem brighter/dimmer but it never fully vanishes — a captured frame
        // always shows the stem, matching the reference.
        let floor = 0.30
        let p = Double(phase)
        let v: Double
        if p < 0.24 { v = 0.85 * (p / 0.24) }
        else if p < 0.66 { v = 0.85 - (0.85 - 0.4) * (p - 0.24) / 0.42 }
        else if p < 0.80 { v = 0.4 - 0.4 * (p - 0.66) / 0.14 }
        else { v = 0 }
        return max(floor, v)
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
